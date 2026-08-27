import os

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from fastapi.exceptions import HTTPException as StarletteHTTPException

import asyncio

from .db import get_conn, init_db, close_pool
from .notifications import provider_health
from .n8n_client import retry_worker
from .ratelimit import limiter
from . import auth, reports

app = FastAPI(title="Aman AI API")

IS_PRODUCTION = os.getenv("ENVIRONMENT", "development").lower() in ("production", "prod")

# ============== CORS ==============
# ⚠️ التركيبة السابقة كانت غير صالحة أصلًا: allow_origins=["*"] مع
# allow_credentials=True ترفضها المتصفحات نفسها (المواصفة تمنع الجمع بينهما).
# الآن: لو النطاقات محددة → نسمح بالاعتماديات؛ لو "*" → نعطّلها ونحذّر.
_allowed_raw = os.getenv("ALLOWED_ORIGINS", "*").strip()
_wildcard = _allowed_raw == "*"
_origins = ["*"] if _wildcard else [o.strip() for o in _allowed_raw.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=not _wildcard,
    allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
    allow_headers=["Content-Type", "x-user-token", "x-staff-token", "x-webhook-secret"],
)

os.makedirs("uploads/temp", exist_ok=True)
os.makedirs("uploads/evidence", exist_ok=True)

# يقدّم الوسائط المحفوظة (صور/تسجيلات صوتية بعد معالجة الخصوصية) عبر رابط عام
app.mount("/media", StaticFiles(directory="uploads"), name="media")

app.include_router(auth.router)
app.include_router(reports.router)


@app.middleware("http")
async def security_headers(request, call_next):
    """ترويسات أمان أساسية — أهمها منع تفسير أي ملف مرفوع بنوع مختلف عن
    المصرّح به (nosniff)، لأن مجلد /media يُقدَّم للعموم مباشرة."""
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    if IS_PRODUCTION:
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


@app.on_event("startup")
def _startup():
    try:
        init_db()
        print("✅ تم التحقق من سكيما قاعدة البيانات")
    except Exception as e:
        # لا نمنع الإقلاع بالكامل حتى تظهر رسالة الخطأ بوضوح بالسجلات على Render/Railway
        print(f"❌ فشل تطبيق سكيما قاعدة البيانات: {e}")

    _seed_staff_if_requested()

    # ============== فحوصات ما قبل الإنتاج ==============
    # الهدف: ألا يمر إعداد ناقص بصمت للإنتاج. بالتطوير تحذير، بالإنتاج توقّف.
    problems = []
    if _wildcard:
        problems.append("ALLOWED_ORIGINS = '*' — حدّد نطاقات الداشبورد والتطبيق صراحة")
    if not os.getenv("N8N_CALLBACK_SECRET"):
        problems.append("N8N_CALLBACK_SECRET فارغ — مسار تحديث التصنيف معطّل")
    if not os.getenv("PUBLIC_BASE_URL"):
        problems.append("PUBLIC_BASE_URL فارغ — وكيل تحليل الصورة لن يصل للصور")

    notify = provider_health()
    if notify["provider"] == "console":
        problems.append(
            "NOTIFY_PROVIDER=console — رموز التحقق تُطبع بسجلات الخادم ولا تصل "
            "للمستخدم. اضبطي resend أو twilio قبل الإطلاق"
        )
    elif not notify["ready"]:
        problems.append(f"مزوّد الرسائل {notify['provider']} غير مكتمل: {notify['warning']}")

    if not os.getenv("REDIS_URL"):
        problems.append(
            "REDIS_URL فارغ — حد المعدّل بذاكرة كل عملية، أي أنه مضروب بعدد "
            "العمليات ويُصفَّر مع كل نشر"
        )

    with get_conn() as conn:
        default_codes = conn.execute(
            "SELECT count(*) AS n FROM staff WHERE access_code IN ('ADMIN-0000','POLICE-1001','AMB-1001','CIVIL-1001')"
        ).fetchone()
    if default_codes and default_codes["n"] > 0:
        problems.append(
            f"لا تزال {default_codes['n']} من أكواد الموظفين الافتراضية فعّالة "
            "(ADMIN-0000 وأخواتها) — أي شخص قرأ الكود بـ GitHub يدخل الداشبورد ويقرأ كل البلاغات"
        )

    if problems:
        header = "❌ إعداد غير آمن للإنتاج:" if IS_PRODUCTION else "⚠️ تنبيهات إعداد (وضع التطوير):"
        print(header)
        for p in problems:
            print(f"   • {p}")
        if IS_PRODUCTION and os.getenv("ALLOW_INSECURE", "").lower() not in ("true", "1"):
            raise RuntimeError(
                "تم إيقاف الإقلاع لحماية بيانات المواطنين. عالج النقاط أعلاه، "
                "أو اضبط ALLOW_INSECURE=true مؤقتًا إذا كنت تعرف ما تفعل."
            )


def _seed_staff_if_requested():
    """يزرع أكواد موظفين للتجربة المحلية فقط، عند ضبط SEED_STAFF_CODES صراحةً.
    الصيغة: "كود:الاسم:القسم:is_admin" مفصولة بفواصل، مثال:
      SEED_STAFF_CODES=DEV-ADMIN-x9f2:المدير العام::true,DEV-POL-k3m8:عمليات الشرطة:Police:false
    لم نعد نضعها بـ schema.sql لأن الملف بمستودع Git ويقرأه الجميع."""
    raw = os.getenv("SEED_STAFF_CODES", "").strip()
    if not raw:
        return
    if IS_PRODUCTION:
        print("⚠️ تجاهل SEED_STAFF_CODES — غير مسموح بوضع الإنتاج")
        return
    created = 0
    with get_conn() as conn:
        for entry in raw.split(","):
            parts = [p.strip() for p in entry.split(":")]
            if len(parts) < 2 or not parts[0]:
                continue
            code, label = parts[0], parts[1]
            department = parts[2] if len(parts) > 2 and parts[2] else None
            is_admin = len(parts) > 3 and parts[3].lower() in ("true", "1", "yes")
            result = conn.execute(
                """
                INSERT INTO staff (access_code, label, department, is_admin)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (access_code) DO NOTHING
                RETURNING id
                """,
                (code, label, department, is_admin),
            ).fetchone()
            if result:
                created += 1
        conn.commit()
    if created:
        print(f"🌱 تم إنشاء {created} كود موظف للتجربة المحلية")


_retry_task: asyncio.Task | None = None


@app.on_event("startup")
async def _start_retry_worker():
    """يشغّل عامل التقاط البلاغات المتعثّرة بخط الوكلاء."""
    global _retry_task
    if os.getenv("N8N_RETRY_WORKER", "true").lower() in ("false", "0", "no"):
        print("ℹ️ عامل إعادة المحاولة معطّل")
        return
    _retry_task = asyncio.create_task(retry_worker())


@app.on_event("shutdown")
async def _shutdown():
    if _retry_task is not None:
        _retry_task.cancel()
    close_pool()


# ============== توحيد شكل الأخطاء ==============
# عملاء التطبيق والداشبورد يقرأون body['message'] (وبعضها body['code']) على
# المستوى الأعلى مباشرة، بينما FastAPI افتراضيًا يلف كل شيء داخل {"detail": ...}.
# هذا المعالج يفرد "detail" إلى المستوى الأعلى ليتوافق مع العملاء الحاليين.
@app.exception_handler(StarletteHTTPException)
async def unified_error_handler(request, exc: StarletteHTTPException):
    detail = exc.detail
    if isinstance(detail, dict):
        body = {"message": detail.get("message", "حدث خطأ"), **detail}
    else:
        body = {"message": str(detail)}
    return JSONResponse(status_code=exc.status_code, content=body, headers=getattr(exc, "headers", None))


@app.get("/")
def health():
    return {"status": "ok", "service": "Aman AI Backend"}


# ============== سياسة الخصوصية ==============

@app.get("/privacy-policy")
def privacy_policy():
    return {
        "policy": [
            "✅ الصورة الأصلية تُحذف فوراً بعد المعالجة",
            "✅ الصورة المموهة فقط تُحفظ",
            "✅ وجوه الأشخاص الآخرين بالصورة مموهة (Blurred)",
            "ℹ️ بيانات GPS ووقت الالتقاط تُحفظ داخليًا للتحقق من صحة البلاغ، ولا تُعرض للعموم",
            "✅ حفظ حسب حالة البلاغ",
        ]
    }


# ============== أقرب فرقة استجابة ==============

@app.get("/nearest-unit")
def nearest_unit(lat: float, lng: float, staff=Depends(auth.require_staff)):
    """للموظفين فقط.

    ⚠️ كان مفتوحًا للجميع، وهو عمليًا واجهة استعلام عن مواقع دوريات الشرطة
    والإسعاف والدفاع المدني وحالة توفّرها لحظيًا. مسح شبكي بسيط للإحداثيات
    كان يكفي لرسم خريطة كاملة بمواقع القوات — معلومة أمنية حساسة.
    """
    with get_conn() as conn:
        unit = conn.execute(
            """
            SELECT name, unit_type,
              ROUND(CAST(6371 * acos(
                  LEAST(1, GREATEST(-1,
                      cos(radians(%s)) * cos(radians(latitude)) *
                      cos(radians(longitude) - radians(%s)) +
                      sin(radians(%s)) * sin(radians(latitude))
                  ))
              ) AS numeric), 2) AS distance_km
            FROM response_units
            WHERE is_available
            ORDER BY distance_km
            LIMIT 1
            """,
            (lat, lng, lat),
        ).fetchone()
    if unit is None:
        raise HTTPException(404, "لا توجد فرق استجابة متاحة")
    return unit


# ============== المسارات القديمة ==============
# POST /reports و POST /reports-with-image و GET /reports/{code} و GET /image-info
# حُذفت. كانت نسخة ثانية غير مصادَقة من نفس المنطق تكتب بنفس الجدول بـ
# user_id='LEGACY'، أي باب خلفي يتجاوز كل ما سبق من ضوابط. لم يعد أي عميل
# بالمشروع يستدعيها (التطبيق والداشبورد يستخدمان /api/reports).
# إذا احتجتِ استدعاءها لاختبار قديم، استخدمي /api/reports بدلًا منها.
