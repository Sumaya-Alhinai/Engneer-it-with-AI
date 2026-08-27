from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel

from .db import get_conn
from .notifications import send_verification_code, NotificationError
from .ratelimit import limiter
from .security import (
    hash_password,
    verify_password,
    generate_verification_code,
    generate_session_token,
    generate_public_id,
    generate_guest_id,
    constant_time_eq,
)

router = APIRouter(prefix="/api/auth", tags=["auth"])

CODE_TTL_MINUTES = 15
STAFF_SESSION_TTL_HOURS = 12
USER_SESSION_TTL_DAYS = 30
MAX_CODE_ATTEMPTS = 5


# ============== نماذج الطلبات ==============

class RegisterIn(BaseModel):
    name: str
    email: str | None = None
    phone: str | None = None
    password: str


class VerifyEmailIn(BaseModel):
    email: str | None = None
    phone: str | None = None
    code: str


class ResendCodeIn(BaseModel):
    email: str | None = None
    phone: str | None = None


class LoginIn(BaseModel):
    email: str | None = None
    phone: str | None = None
    password: str


class StaffLoginIn(BaseModel):
    code: str


# ============== أدوات مساعدة ==============

def _find_user(conn, email: str | None, phone: str | None):
    if email:
        return conn.execute("SELECT * FROM users WHERE email = %s", (email,)).fetchone()
    if phone:
        return conn.execute("SELECT * FROM users WHERE phone = %s", (phone,)).fetchone()
    return None


def _send_code(channel: str, destination: str, code: str) -> None:
    """يرسل عبر المزوّد المضبوط بـ NOTIFY_PROVIDER (console/resend/twilio).
    فشل الإرسال يصير خطأ ظاهرًا للمستخدم بدل نجاح كاذب يتركه ينتظر رمزًا
    لن يصل أبدًا."""
    try:
        send_verification_code(channel, destination, code)
    except NotificationError as e:
        print(f"❌ فشل إرسال رمز التحقق إلى {destination}: {e}")
        raise HTTPException(502, "تعذّر إرسال رمز التحقق حاليًا، حاول بعد قليل")


def _issue_code(conn, user_id: int, channel: str) -> str:
    code = generate_verification_code()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=CODE_TTL_MINUTES)
    # نلغي أي رموز سابقة غير مستخدمة حتى لا يبقى رمز قديم صالحًا بالتوازي
    conn.execute("DELETE FROM verification_codes WHERE user_id = %s", (user_id,))
    conn.execute(
        "INSERT INTO verification_codes (user_id, code, channel, expires_at) VALUES (%s, %s, %s, %s)",
        (user_id, code, channel, expires_at),
    )
    return code


def _issue_user_session(conn, public_id: str, is_guest: bool) -> str:
    """ينشئ جلسة مواطن ويرجع التوكن.

    ⚠️ هذا هو الإصلاح الجذري لأخطر ثغرة بالمشروع: قبله كان /api/auth/login
    يرجع public_id فقط بدون أي توكن، يعني لم تكن هناك وسيلة أصلًا للباك-إند
    يتحقق أن من يطلب بلاغات USR-1234 هو فعلًا صاحبها. النتيجة أن كل مسارات
    قراءة البلاغات كانت مفتوحة للجميع (تفاصيل + إحداثيات GPS دقيقة).
    """
    token = generate_session_token()
    expires_at = datetime.now(timezone.utc) + timedelta(days=USER_SESSION_TTL_DAYS)
    conn.execute(
        "INSERT INTO user_sessions (token, user_public_id, is_guest, expires_at) VALUES (%s, %s, %s, %s)",
        (token, public_id, is_guest, expires_at),
    )
    return token


# ============== المستخدمون ==============

@router.post("/register", dependencies=[Depends(limiter("auth_register", 5, 3600))])
def register(body: RegisterIn):
    if not body.email and not body.phone:
        raise HTTPException(400, "أدخل بريدًا إلكترونيًا أو رقم هاتف")
    if len(body.password) < 8:
        raise HTTPException(400, "كلمة المرور يجب أن تكون 8 أحرف على الأقل")
    with get_conn() as conn:
        existing = _find_user(conn, body.email, body.phone)
        if existing and existing["is_verified"]:
            raise HTTPException(409, "هذا الحساب مسجّل مسبقًا")

        channel = "email" if body.email else "phone"
        destination = body.email or body.phone

        if existing and not existing["is_verified"]:
            # حساب موجود وغير مفعّل — نحدّث بياناته ونرسل رمزًا جديدًا بدل رمي خطأ
            conn.execute(
                "UPDATE users SET name = %s, password_hash = %s WHERE id = %s",
                (body.name, hash_password(body.password), existing["id"]),
            )
            user_id = existing["id"]
        else:
            row = conn.execute(
                """
                INSERT INTO users (public_id, name, email, phone, password_hash, is_verified)
                VALUES (%s, %s, %s, %s, %s, FALSE) RETURNING id
                """,
                (generate_public_id("USR"), body.name, body.email, body.phone, hash_password(body.password)),
            ).fetchone()
            user_id = row["id"]

        code = _issue_code(conn, user_id, channel)
        conn.commit()

    _send_code(channel, destination, code)
    return {"message": "تم إنشاء الحساب، تحقق من رمز التفعيل"}


@router.post("/verify-email", dependencies=[Depends(limiter("auth_verify", 10, 900))])
def verify_email(body: VerifyEmailIn):
    if not body.email and not body.phone:
        raise HTTPException(400, "أدخل بريدًا إلكترونيًا أو رقم هاتف")
    with get_conn() as conn:
        user = _find_user(conn, body.email, body.phone)
        if user is None:
            raise HTTPException(404, "الحساب غير موجود")

        latest = conn.execute(
            "SELECT * FROM verification_codes WHERE user_id = %s ORDER BY created_at DESC LIMIT 1",
            (user["id"],),
        ).fetchone()
        if latest is None:
            raise HTTPException(400, "لا يوجد رمز فعّال، اطلب رمزًا جديدًا")

        # حد لعدد المحاولات: رمز من 6 أرقام = مليون احتمال فقط، وبدون حد
        # يمكن تخمينه آليًا بدقائق. بعد 5 محاولات خاطئة يُلغى الرمز نهائيًا.
        if latest["attempts"] >= MAX_CODE_ATTEMPTS:
            conn.execute("DELETE FROM verification_codes WHERE id = %s", (latest["id"],))
            conn.commit()
            raise HTTPException(429, "تجاوزت عدد المحاولات المسموحة، اطلب رمزًا جديدًا")

        if latest["expires_at"] < datetime.now(timezone.utc):
            raise HTTPException(400, "انتهت صلاحية الرمز، اطلب رمزًا جديدًا")

        # مقارنة بزمن ثابت حتى لا يسرّب وقت الرد أي معلومة عن الرمز الصحيح
        if not constant_time_eq(latest["code"], body.code):
            conn.execute(
                "UPDATE verification_codes SET attempts = attempts + 1 WHERE id = %s", (latest["id"],)
            )
            conn.commit()
            raise HTTPException(400, "رمز التحقق غير صحيح")

        conn.execute("UPDATE users SET is_verified = TRUE WHERE id = %s", (user["id"],))
        conn.execute("DELETE FROM verification_codes WHERE user_id = %s", (user["id"],))
        token = _issue_user_session(conn, user["public_id"], is_guest=False)
        conn.commit()

    return {
        "token": token,
        "user_id": user["public_id"],
        "name": user["name"],
        "email": user["email"],
        "phone": user["phone"],
    }


@router.post("/resend-code", dependencies=[Depends(limiter("auth_resend", 3, 900))])
def resend_code(body: ResendCodeIn):
    if not body.email and not body.phone:
        raise HTTPException(400, "أدخل بريدًا إلكترونيًا أو رقم هاتف")
    with get_conn() as conn:
        user = _find_user(conn, body.email, body.phone)
        if user is None:
            raise HTTPException(404, "الحساب غير موجود")
        channel = "email" if body.email else "phone"
        code = _issue_code(conn, user["id"], channel)
        conn.commit()
    _send_code(channel, body.email or body.phone, code)
    return {"message": "تم إرسال رمز جديد"}


@router.post("/login", dependencies=[Depends(limiter("auth_login", 10, 300))])
def login(body: LoginIn):
    if not body.email and not body.phone:
        raise HTTPException(400, "أدخل بريدًا إلكترونيًا أو رقم هاتف")
    with get_conn() as conn:
        user = _find_user(conn, body.email, body.phone)
        if user is None or not verify_password(body.password, user["password_hash"]):
            raise HTTPException(400, "بيانات الدخول غير صحيحة")
        if not user["is_verified"]:
            raise HTTPException(
                403,
                detail={"code": "EMAIL_NOT_VERIFIED", "email": user["email"], "phone": user["phone"],
                        "message": "الحساب غير مفعّل بعد"},
            )
        token = _issue_user_session(conn, user["public_id"], is_guest=False)
        conn.commit()
    return {
        "token": token,
        "user_id": user["public_id"],
        "name": user["name"],
        "email": user["email"],
        "phone": user["phone"],
    }


@router.post("/guest", dependencies=[Depends(limiter("auth_guest", 10, 3600))])
def guest_session():
    """جلسة ضيف يولّدها الخادم.

    البلاغ بدون حساب ميزة أساسية بالمنتج (تبسيط الإبلاغ)، لكن قبل هذا التعديل
    كان التطبيق يولّد معرّف الضيف محليًا ويرسله كحقل نصي — أي أن أي شخص يقدر
    يكتب user_id=USR-1234 وينتحل مواطنًا مسجّلًا. الآن المعرّف يأتي من الخادم
    مربوطًا بتوكن، والانتحال غير ممكن.
    """
    guest_id = generate_guest_id()
    with get_conn() as conn:
        token = _issue_user_session(conn, guest_id, is_guest=True)
        conn.commit()
    return {"token": token, "user_id": guest_id, "is_guest": True}


@router.post("/logout")
def user_logout(x_user_token: str | None = Header(default=None)):
    if x_user_token:
        with get_conn() as conn:
            conn.execute("DELETE FROM user_sessions WHERE token = %s", (x_user_token,))
            conn.commit()
    return {"message": "تم تسجيل الخروج"}


# ============== Dependencies للمواطن ==============

def require_user(x_user_token: str | None = Header(default=None)) -> dict:
    """تتحقق من جلسة المواطن (مسجّل أو ضيف) وترجع بياناتها."""
    if not x_user_token:
        raise HTTPException(401, "مطلوب تسجيل الدخول")
    with get_conn() as conn:
        session = conn.execute(
            "SELECT * FROM user_sessions WHERE token = %s", (x_user_token,)
        ).fetchone()
        if session is None or session["expires_at"] < datetime.now(timezone.utc):
            raise HTTPException(401, "انتهت الجلسة، يرجى تسجيل الدخول مجددًا")
    return session


def optional_user(x_user_token: str | None = Header(default=None)) -> dict | None:
    """مثل require_user لكن ترجع None بدل الخطأ — تُستخدم بمسار إنشاء البلاغ
    الذي يجب أن يبقى متاحًا حتى لمن لا يملك جلسة (حالة طوارئ فعلية)."""
    if not x_user_token:
        return None
    try:
        return require_user(x_user_token)
    except HTTPException:
        return None


# ============== الموظفون (لوحة التحكم) ==============

@router.post("/staff/login", dependencies=[Depends(limiter("auth_staff_login", 10, 300))])
def staff_login(body: StaffLoginIn):
    with get_conn() as conn:
        staff = conn.execute("SELECT * FROM staff WHERE access_code = %s", (body.code,)).fetchone()
        if staff is None:
            raise HTTPException(401, "كود الدخول غير صحيح")
        token = generate_session_token()
        expires_at = datetime.now(timezone.utc) + timedelta(hours=STAFF_SESSION_TTL_HOURS)
        conn.execute(
            "INSERT INTO staff_sessions (token, staff_id, expires_at) VALUES (%s, %s, %s)",
            (token, staff["id"], expires_at),
        )
        conn.commit()
    return {
        "token": token,
        "department": staff["department"],
        "is_admin": staff["is_admin"],
        "label": staff["label"],
    }


@router.post("/staff/logout")
def staff_logout(x_staff_token: str | None = Header(default=None)):
    if x_staff_token:
        with get_conn() as conn:
            conn.execute("DELETE FROM staff_sessions WHERE token = %s", (x_staff_token,))
            conn.commit()
    return {"message": "تم تسجيل الخروج"}


def require_staff(x_staff_token: str | None = Header(default=None)):
    """Dependency تتحقق من جلسة الموظف وتُرجع صفّه — تُستخدم بمسارات الداشبورد."""
    if not x_staff_token:
        raise HTTPException(401, "مطلوب تسجيل دخول الموظف")
    with get_conn() as conn:
        session = conn.execute(
            "SELECT * FROM staff_sessions WHERE token = %s", (x_staff_token,)
        ).fetchone()
        if session is None or session["expires_at"] < datetime.now(timezone.utc):
            raise HTTPException(401, "انتهت الجلسة، يرجى تسجيل الدخول مجددًا")
        staff = conn.execute("SELECT * FROM staff WHERE id = %s", (session["staff_id"],)).fetchone()
        if staff is None:
            raise HTTPException(401, "الجلسة غير صالحة")
    return staff
