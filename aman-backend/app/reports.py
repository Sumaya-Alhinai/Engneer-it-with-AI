import os
from datetime import datetime, timezone

from psycopg.errors import UniqueViolation

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Header, UploadFile
from pydantic import BaseModel

from .auth import require_staff, require_user, optional_user
from .db import get_conn
from .deduplication import check_and_link, credibility_from_confirmations
from .geocoding import reverse_geocode
from .n8n_client import trigger_report_pipeline
from .ratelimit import limiter
from .security import (constant_time_eq, safe_filename_stem, extension_for,
                       generate_guest_id, generate_report_code)

try:
    from image_processor import extract_exif, blur_faces, analyse_exif, normalize_to_jpeg
except ImportError:
    extract_exif = blur_faces = analyse_exif = normalize_to_jpeg = None
    print("⚠️ تحذير: image_processor غير متاح — سيتم حفظ الوسائط بدون معالجة")

router = APIRouter(prefix="/api/reports", tags=["reports"])

EVIDENCE_DIR = "uploads/evidence"
os.makedirs(EVIDENCE_DIR, exist_ok=True)

IMAGE_CONTENT_TYPES = {"image/jpeg", "image/png", "image/jpg",
                       "image/heic", "image/heif", "image/webp"}
AUDIO_CONTENT_TYPES = {"audio/mpeg", "audio/mp4", "audio/aac", "audio/wav",
                       "audio/x-wav", "audio/webm", "audio/ogg"}

# حدود الرفع — قابلة للضبط بمتغيرات بيئة
MAX_IMAGE_BYTES = int(os.getenv("MAX_IMAGE_MB", "5")) * 1024 * 1024
MAX_AUDIO_BYTES = int(os.getenv("MAX_AUDIO_MB", "10")) * 1024 * 1024
MAX_MEDIA_FILES = int(os.getenv("MAX_MEDIA_FILES", "4"))
CHUNK_SIZE = 1024 * 1024

N8N_CALLBACK_SECRET = os.getenv("N8N_CALLBACK_SECRET", "")


# ============== أدوات مساعدة ==============

def _save_upload(upload: UploadFile, prefix: str, max_bytes: int, allowed_types: set[str]) -> tuple[str, dict]:
    """يحفظ ملفًا مرفوعًا داخل uploads/evidence ويرجع (مسار الوصول العام، بيانات EXIF).

    ثلاثة إصلاحات أمنية مقارنة بالنسخة السابقة:
    1. اسم الملف يُنظَّف بالكامل ولا يُستخدم كمسار (منع Path Traversal —
       اسم مثل ../../app/main.py كان يكتب خارج مجلد الرفع).
    2. نوع المحتوى يُتحقق منه بقائمة بيضاء، والامتداد يُشتق منها لا من الاسم.
    3. الحجم يُفحص أثناء البث بالتقطيع وليس بعد قراءة الملف كاملًا بالذاكرة —
       مسار /api/reports لم يكن فيه أي حد للحجم إطلاقًا، ورفع ملف 2GB كان
       كافيًا لملء قرص Render (1GB) وإسقاط الخدمة.
    """
    content_type = (upload.content_type or "").lower()
    if content_type not in allowed_types:
        raise HTTPException(400, f"نوع ملف غير مدعوم: {upload.content_type or 'غير محدد'}")

    stem = safe_filename_stem(upload.filename)
    ext = extension_for(content_type)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S%f")
    safe_name = f"{prefix}_{timestamp}_{stem}{ext}"
    dest = os.path.join(EVIDENCE_DIR, safe_name)

    # حزام أمان إضافي: نتأكد أن المسار النهائي فعلًا داخل مجلد الأدلة
    if os.path.commonpath([os.path.abspath(EVIDENCE_DIR), os.path.abspath(dest)]) != os.path.abspath(EVIDENCE_DIR):
        raise HTTPException(400, "اسم ملف غير صالح")

    written = 0
    try:
        with open(dest, "wb") as f:
            while chunk := upload.file.read(CHUNK_SIZE):
                written += len(chunk)
                if written > max_bytes:
                    raise HTTPException(413, f"حجم الملف يتجاوز الحد ({max_bytes // (1024 * 1024)} ميغابايت)")
                f.write(chunk)
    except HTTPException:
        if os.path.exists(dest):
            os.remove(dest)
        raise
    except Exception as e:
        if os.path.exists(dest):
            os.remove(dest)
        raise HTTPException(500, f"تعذّر حفظ الملف: {e}")

    exif, blur_report = {}, {}
    if content_type in IMAGE_CONTENT_TYPES and extract_exif and blur_faces:
        try:
            # التوحيد إلى JPEG أولًا: يضمن أن OpenCV يستطيع كتابة الملف. بدونه
            # تفشل صور HEIC صامتة وتُحفظ بلا تمويه بينما يرد الخادم بنجاح.
            dest = normalize_to_jpeg(dest)
            safe_name = os.path.basename(dest)
            exif = extract_exif(dest)   # قبل التمويه — التمويه يعيد كتابة الملف
            blur_report = blur_faces(dest)
        except Exception as e:
            print(f"⚠️ فشلت معالجة الصورة {safe_name}: {e}")
            blur_report = {"success": False}

        # فشل مغلق: صورة لم تُموّه إطلاقًا لا تُحفظ. رفض البلاغ أقل ضررًا من
        # نشر وجوه أشخاص لم يوافقوا، والمستخدم يقدر يعيد الإرسال بصيغة أخرى.
        if not blur_report.get("success"):
            if os.path.exists(dest):
                os.remove(dest)
            raise HTTPException(
                422, "تعذّرت معالجة الصورة لحماية الخصوصية. جرّب إرسالها بصيغة JPG أو PNG.")

    return f"/media/evidence/{safe_name}", exif, blur_report


def _serialize(row: dict, include_exif: bool = False) -> dict:
    """يحوّل صف قاعدة البيانات لشكل الاستجابة اللي يتوقعه التطبيق/الداشبورد.
    include_exif=True فقط لمسارات الموظفين — بيانات EXIF (GPS/وقت/جهاز) للتحقق
    الداخلي من صحة البلاغ، ولا تُعرض بمسارات المواطن العامة."""
    data = {
        "report_id": row["public_code"],
        "user_id": row["user_id"],
        "type": row.get("type"),
        "description": row.get("description") or row.get("report_text"),
        "latitude": row.get("latitude"),
        "longitude": row.get("longitude"),
        "location_text": row.get("location_text"),
        "media_paths": row.get("media_paths") or [],
        "voice_note_path": row.get("voice_note_path"),
        "confirmed_incident_type": row.get("confirmed_incident_type"),
        "priority": row.get("priority"),
        "risk_score": row.get("risk_score"),
        "department": row.get("department"),
        "status": row.get("status"),
        "created_at": row["created_at"].isoformat() if row.get("created_at") else None,
        "updated_at": row["updated_at"].isoformat() if row.get("updated_at") else None,
    }
    # الموقع الإداري الحقيقي — يظهر للمواطن والموظف
    data["geo_wilayat"] = row.get("geo_wilayat")
    data["geo_governorate"] = row.get("geo_governorate")
    data["geo_neighbourhood"] = row.get("geo_neighbourhood")

    # حالة التأكيدات: كم بلاغًا مستقلًا ورد عن نفس الحادث
    count = row.get("confirmation_count") or 0
    data["confirmation_count"] = count
    data["credibility"] = credibility_from_confirmations(count)
    data["is_confirmation"] = row.get("parent_report_id") is not None

    if include_exif:
        # حالة خط الوكلاء — تسمح للموظف بتمييز بلاغ لم يُصنَّف آليًا (يحتاج
        # مراجعة يدوية) عن بلاغ صنّفه الوكلاء فعلًا بأولوية منخفضة
        data["media_verification"] = row.get("media_verification") or []
        data["pipeline_status"] = row.get("pipeline_status")
        data["pipeline_attempts"] = row.get("pipeline_attempts")
        data["pipeline_last_error"] = row.get("pipeline_last_error")
        data["media_exif"] = row.get("media_exif") or []
        data["image_is_plausible"] = row.get("image_is_plausible")
        data["image_authenticity_reason"] = row.get("image_authenticity_reason")
        data["image_ai_generated_suspected"] = row.get("image_ai_generated_suspected")
        data["image_ai_generated_reason"] = row.get("image_ai_generated_reason")
    return data


def _serialize_public(row: dict) -> dict:
    """نسخة مُنقّحة للخلاصة العامة (شاشة التنبيهات بالتطبيق).

    الخلاصة العامة كانت ترجع كل شيء: نص البلاغ الحر، معرّف صاحبه، وإحداثيات
    GPS بدقة كاملة — لأي شخص بلا مصادقة. نص البلاغ قد يحتوي أسماء وأرقام
    ("فلان مصاب بالبيت رقم..."), والإحداثيات الدقيقة تكشف منزل المبلّغ.
    هنا نحتفظ بما يخدم الغرض فعلًا (وين وأي نوع حادث وكم خطورته) ونحذف الباقي،
    مع تقريب الإحداثيات لمنزلتين عشريتين (~1 كم) بدل خمس (~1 متر).
    """
    lat, lng = row.get("latitude"), row.get("longitude")
    return {
        "report_id": row["public_code"],
        "type": row.get("confirmed_incident_type") or row.get("type"),
        "priority": row.get("priority"),
        "status": row.get("status"),
        "location_text": row.get("location_text"),
        "latitude": round(float(lat), 2) if lat is not None else None,
        "longitude": round(float(lng), 2) if lng is not None else None,
        "created_at": row["created_at"].isoformat() if row.get("created_at") else None,
    }


def _to_jsonb(value) -> str:
    import json
    return json.dumps(value, ensure_ascii=False)


# ============== إنشاء بلاغ (من التطبيق) ==============

@router.post("", dependencies=[Depends(limiter("reports_create", 5, 300))])
async def create_report(
    background_tasks: BackgroundTasks,
    user_id: str = Form(""),
    type: str = Form(""),
    description: str = Form(""),
    location_text: str = Form(""),
    latitude: float | None = Form(None),
    longitude: float | None = Form(None),
    media: list[UploadFile] = File(default=[]),
    voice_note: UploadFile | None = File(default=None),
    session=Depends(optional_user),
):
    """يبقى متاحًا بدون تسجيل دخول (الإبلاغ بحالة طوارئ يجب ألا يُعطَّل بشاشة
    دخول)، لكن هوية المُبلِّغ لم تعد تُؤخذ من حقل نصي يتحكم فيه العميل."""
    if session is not None:
        # الجلسة هي مصدر الحقيقة — حقل user_id المُرسل يُتجاهل تمامًا
        effective_user_id = session["user_public_id"]
    else:
        # بلا جلسة: ضيف. نرفض انتحال معرّف مستخدم مسجّل ونولّد معرّفًا خادميًا.
        if user_id.upper().startswith("USR-"):
            raise HTTPException(401, "مطلوب تسجيل الدخول لاستخدام هذا الحساب")
        effective_user_id = generate_guest_id()

    if not description.strip() and not type.strip() and not media:
        raise HTTPException(400, "البلاغ فارغ — أضف وصفًا أو نوع الحادث أو صورة")

    if len(media) > MAX_MEDIA_FILES:
        raise HTTPException(400, f"الحد الأقصى {MAX_MEDIA_FILES} ملفات لكل بلاغ")

    media_paths = []
    media_exif = []  # بترتيب media_paths نفسه — للتحقق الداخلي فقط (لا يُعرض للمواطن)
    for f in media:
        if f and f.filename:
            path, exif, blur_report = _save_upload(f, "media", MAX_IMAGE_BYTES, IMAGE_CONTENT_TYPES)
            media_paths.append(path)
            media_exif.append({"path": path, **exif, "blur": blur_report})

    voice_note_path = None
    if voice_note and voice_note.filename:
        voice_note_path, _, _ = _save_upload(voice_note, "voice", MAX_AUDIO_BYTES, AUDIO_CONTENT_TYPES)

    # تحليل البيانات الوصفية: يقارن وقت الصورة وموقعها ببيانات البلاغ ويحوّل
    # الفروق إلى تحذيرات صريحة، بدل ترك الموظف يقارن الأرقام بنفسه
    media_verification = []
    if analyse_exif:
        now = datetime.now()
        for entry in media_exif:
            analysis = analyse_exif(entry, latitude, longitude, now)
            media_verification.append({"path": entry.get("path"), **analysis})

    # الموقع الإداري الحقيقي — استعلام جغرافي فعلي بدل تخمين النموذج
    geo = reverse_geocode(latitude, longitude) if latitude is not None else {}

    # الرمز يُولَّد عشوائيًا قبل الإدراج بدل اشتقاقه من المعرّف المتسلسل.
    # احتمال التصادم ضئيل (31^8) لكن نتعامل معه صراحةً بدل الاعتماد على الحظ.
    saved = None
    with get_conn() as conn:
        for _ in range(5):
            candidate = generate_report_code()
            try:
                saved = conn.execute(
                    """
                    INSERT INTO reports
                        (public_code, user_id, channel, type, description, location_text,
                         latitude, longitude, media_paths, media_exif, media_verification,
                         voice_note_path, geo_wilayat, geo_governorate, geo_neighbourhood,
                         geo_source, status, pipeline_status)
                    VALUES (%s, %s, 'app', %s, %s, %s, %s, %s, %s::jsonb, %s::jsonb, %s::jsonb,
                            %s, %s, %s, %s, %s, 'received', 'pending')
                    RETURNING *
                    """,
                    (
                        candidate, effective_user_id, type, description, location_text,
                        latitude, longitude, _to_jsonb(media_paths), _to_jsonb(media_exif),
                        _to_jsonb(media_verification), voice_note_path,
                        geo.get("wilayat"), geo.get("governorate"),
                        geo.get("neighbourhood"), geo.get("source"),
                    ),
                ).fetchone()
                conn.commit()
                break
            except UniqueViolation:
                conn.rollback()
                continue
    if saved is None:
        raise HTTPException(500, "تعذّر توليد رقم بلاغ فريد، حاول مرة أخرى")

    # فحص التكرار قبل استدعاء الوكلاء: إن كان هذا البلاغ تأكيدًا لحادث قائم،
    # نربطه ونوقف خط الوكلاء — الحادث مُصنَّف أصلًا، وإعادة تصنيفه إنفاق بلا فائدة
    with get_conn() as conn:
        dedup = check_and_link(conn, saved)
        conn.commit()

    if dedup["linked"]:
        return {
            "report_id": saved["public_code"],
            "user_id": effective_user_id,
            "linked_to": dedup["parent_code"],
            "is_confirmation": True,
            "message": "تم ربط بلاغك بحادث مُبلَّغ عنه مسبقًا في نفس الموقع، وأضاف بلاغك تأكيدًا له",
            "department": "",
            "priority": "",
        }

    # حادث جديد — يشغّل خط أنابيب الوكلاء بالخلفية (لا يؤخر الرد على المستخدم)
    background_tasks.add_task(trigger_report_pipeline, saved)

    return {
        "report_id": saved["public_code"],
        "user_id": effective_user_id,   # يحتاجه الضيف بلا جلسة لمتابعة بلاغه
        "is_confirmation": False,
        "department": saved.get("department") or "",
        "priority": saved.get("priority") or "",
    }


# ============== جلب البلاغات ==============

@router.get("/public", dependencies=[Depends(limiter("reports_public", 60, 60))])
def public_feed():
    """خلاصة عامة مُنقّحة لشاشة التنبيهات — بدون نص البلاغ ولا هوية المُبلِّغ
    ولا إحداثيات دقيقة. آخر 50 بلاغًا خلال آخر 24 ساعة فقط."""
    with get_conn() as conn:
        rows = conn.execute(
            """
            SELECT * FROM reports
            WHERE created_at > now() - INTERVAL '24 hours'
            ORDER BY created_at DESC LIMIT 50
            """
        ).fetchall()
    return [_serialize_public(r) for r in rows]


@router.get("")
def list_my_reports(session=Depends(require_user)):
    """بلاغات صاحب الجلسة فقط.

    ⚠️ أخطر ثغرة كانت هنا: المسار كان يقبل ?user_id=... من العميل بلا أي
    تحقق، وبدون user_id كان يرجع آخر 200 بلاغ لكل المستخدمين — نصوص وإحداثيات
    كاملة لأي شخص يفتح الرابط بالمتصفح. الآن المعرّف يأتي من التوكن حصرًا،
    ولا يمكن للعميل تجاوزه.
    """
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT * FROM reports WHERE user_id = %s ORDER BY created_at DESC LIMIT 100",
            (session["user_public_id"],),
        ).fetchall()
    return [_serialize(r) for r in rows]


@router.get("/staff")
def list_reports_for_staff(department: str | None = None, staff=Depends(require_staff)):
    effective_department = staff["department"] if not staff["is_admin"] else department
    with get_conn() as conn:
        # نستثني بلاغات التأكيد: تظهر مدمجة داخل بلاغها الأصل بعدّاد التأكيدات،
        # فغرفة العمليات ترى حادثًا واحدًا بدل عشرين بطاقة لنفس الحريق
        if effective_department:
            rows = conn.execute(
                """SELECT * FROM reports WHERE department = %s AND parent_report_id IS NULL
                   ORDER BY created_at DESC""", (effective_department,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM reports WHERE parent_report_id IS NULL ORDER BY created_at DESC"
            ).fetchall()
    return [_serialize(r, include_exif=True) for r in rows]


@router.get("/needs-review")
def reports_needing_review(staff=Depends(require_staff)):
    """بلاغات لم يُكملها خط الوكلاء — لا تظهر بقائمة القسم لأن department
    فارغ، فبدون هذا المسار تبقى غير مرئية لأحد رغم أنها محفوظة."""
    with get_conn() as conn:
        rows = conn.execute(
            """
            SELECT * FROM reports
            WHERE pipeline_status = 'failed' AND pipeline_attempts >= %s
            ORDER BY created_at DESC LIMIT 100
            """,
            (int(os.getenv("N8N_MAX_ATTEMPTS", "5")),),
        ).fetchall()
    return [_serialize(r, include_exif=True) for r in rows]


@router.get("/{report_id}")
def get_report(
    report_id: str,
    session=Depends(require_user),
):
    """صاحب البلاغ فقط.

    ⚠️ كان مفتوحًا بلا مصادقة، وأرقام البلاغات متسلسلة ومتوقّعة
    (AMN-1001, AMN-1002, ...) — أي أن حلقة while بسيطة كانت تكفي لسحب كل
    بلاغات النظام واحدًا واحدًا. هذا نمط ثغرة IDOR الكلاسيكي.
    الموظفون يستخدمون /api/reports/staff بدلًا من هذا المسار.
    """
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM reports WHERE public_code = %s", (report_id,)).fetchone()
    if row is None:
        raise HTTPException(404, "البلاغ غير موجود")
    if row["user_id"] != session["user_public_id"]:
        # نرجع 404 وليس 403 حتى لا نؤكد للمهاجم أن رقم البلاغ موجود أصلًا
        raise HTTPException(404, "البلاغ غير موجود")
    return _serialize(row)


# ============== تحديث الحالة (من الداشبورد) ==============

class StatusUpdateIn(BaseModel):
    status: str


ALLOWED_STATUSES = {"received", "verified", "dispatched", "in_progress", "resolved", "rejected", "flag_for_review"}


@router.patch("/{report_id}/status")
def update_status(report_id: str, body: StatusUpdateIn, staff=Depends(require_staff)):
    if body.status not in ALLOWED_STATUSES:
        raise HTTPException(400, f"حالة غير معروفة: {body.status}")
    with get_conn() as conn:
        row = conn.execute(
            """
            UPDATE reports SET status = %s, updated_at = now()
            WHERE public_code = %s RETURNING *
            """,
            (body.status, report_id),
        ).fetchone()
        conn.commit()
    if row is None:
        raise HTTPException(404, "البلاغ غير موجود")
    return _serialize(row, include_exif=True)


# ============== استقبال نتيجة خط أنابيب الوكلاء (من n8n) ==============

class ClassificationIn(BaseModel):
    confirmed_incident_type: str | None = None
    department: str | None = None
    priority: str | None = None          # أو urgency القادمة من Agent 6 — أرسلها بنفس الاسم
    risk_score: int | float | str | None = None   # نطبّعه لاحقًا إلى 0-100 صحيح مهما كانت صيغته
    verification_status: str | None = None
    location_status: str | None = None
    ai_reason: str | None = None
    image_is_plausible: bool | str | None = None
    image_authenticity_reason: str | None = None
    image_ai_generated_suspected: bool | str | None = None
    image_ai_generated_reason: str | None = None
    status: str | None = None


def _normalize_risk_score(value) -> int | None:
    """يحوّل درجة الخطورة الواردة من الوكلاء إلى عدد صحيح 0-100.

    ⚠️ هذه الدالة كانت تحتوي خطأً حقيقيًا وخطيرًا، ويستحق التوضيح:
    كانت تفترض أن أي قيمة بين 0 و1 هي نسبة كسرية فتضربها في 100، وأي قيمة
    بين 1 و10 على قياس عشري فتضربها في 10. الافتراض جاء من أن الوكلاء القدامى
    كانوا يخلطون بين المقاييس.

    النتيجة كانت انقلابًا كاملًا للمعنى: بلاغ يقيّمه الوكيل بخطورة 1 من 100
    (أي "لا خطر تقريبًا" — صورة فواكه مثلًا) كان يُخزَّن ويُعرض بـ 100%، أي
    "خطورة قصوى". وبقرار طوارئ، عرض بلاغ غير خطر كأنه أخطر ما ورد اليوم خطأ
    قد يصرف فرقة عن حادث حقيقي.

    الآن المقياس موحّد: كل الوكلاء يرجعون 0-100 صراحةً بتوجيهاتهم، فنقصّ
    القيمة على المدى المسموح دون إعادة قياس. لا تخمين، لا مضاعفة.
    """
    if value is None or value == "":
        return None
    try:
        num = float(value)
    except (TypeError, ValueError):
        return None
    return max(0, min(100, round(num)))


@router.patch("/{report_id}/classification")
def update_classification(
    report_id: str,
    body: ClassificationIn,
    x_webhook_secret: str | None = Header(default=None),
):
    """يستقبله عقدة HTTP Request الأخيرة بوركفلو n8n (Aman_AI_Master_Workflow)
    بعد أن يُنهي الوكلاء الثمانية التصنيف والتحقق وتحديد الجهة المسؤولة.

    ⚠️ تغيير مهم: السر لم يعد اختياريًا. الشرط السابق
        if N8N_CALLBACK_SECRET and not constant_time_eq(...)
    كان يعني أن نسيان ضبط المتغير بلوحة Render = مسار مفتوح للجميع يسمح لأي
    شخص بتغيير تصنيف وأولوية وحالة أي بلاغ (تحويل بلاغ حريق حرج إلى "مرفوض").
    الفشل الآمن هو الرفض عند غياب السر، لا القبول.
    """
    if not N8N_CALLBACK_SECRET:
        raise HTTPException(503, "N8N_CALLBACK_SECRET غير مضبوط بالخادم — المسار معطّل لأسباب أمنية")
    if not constant_time_eq(x_webhook_secret or "", N8N_CALLBACK_SECRET):
        raise HTTPException(401, "غير مصرّح")

    fields, values = [], []
    for key in ("confirmed_incident_type", "department", "priority", "risk_score",
                "verification_status", "location_status", "ai_reason",
                "image_is_plausible", "image_authenticity_reason",
                "image_ai_generated_suspected", "image_ai_generated_reason", "status"):
        val = getattr(body, key)
        if key == "risk_score":
            val = _normalize_risk_score(val)
        elif key in ("image_is_plausible", "image_ai_generated_suspected") and isinstance(val, str):
            val = val.strip().lower() in ("true", "1", "yes")
        if val is not None:
            fields.append(f"{key} = %s")
            values.append(val)
    if not fields:
        raise HTTPException(400, "لا يوجد تحديث لتطبيقه")

    # وصول نتيجة من n8n = خط الأنابيب أنهى عمله؛ نغلق حالة التتبّع
    fields.append("pipeline_status = 'completed'")
    fields.append("pipeline_last_error = NULL")
    fields.append("pipeline_next_retry_at = NULL")
    fields.append("updated_at = now()")
    values.append(report_id)

    with get_conn() as conn:
        row = conn.execute(
            f"UPDATE reports SET {', '.join(fields)} WHERE public_code = %s RETURNING *",
            tuple(values),
        ).fetchone()
        conn.commit()
    if row is None:
        raise HTTPException(404, "البلاغ غير موجود")
    return _serialize(row)
