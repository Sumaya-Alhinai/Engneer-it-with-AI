"""
يشغّل خط أنابيب الوكلاء الثمانية على n8n بعد حفظ أي بلاغ جديد، مع تتبّع
حالة كل بلاغ بقاعدة البيانات وعامل إعادة محاولة دوري للبلاغات المتعثّرة.
"""
import asyncio
import os
from datetime import datetime, timedelta, timezone

import httpx

from .db import get_conn

N8N_WEBHOOK_URL = os.getenv("N8N_WEBHOOK_URL")
N8N_WEBHOOK_TIMEOUT = float(os.getenv("N8N_WEBHOOK_TIMEOUT", "15"))
N8N_MAX_ATTEMPTS = int(os.getenv("N8N_MAX_ATTEMPTS", "5"))
RETRY_SWEEP_SECONDS = int(os.getenv("N8N_RETRY_SWEEP_SECONDS", "60"))
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "").rstrip("/")


def _set_pipeline(code: str, status: str, attempts: int | None = None,
                  error: str | None = None, next_retry_at=None) -> None:
    fields = ["pipeline_status = %s"]
    values: list = [status]
    if attempts is not None:
        fields.append("pipeline_attempts = %s"); values.append(attempts)
    fields.append("pipeline_last_error = %s"); values.append(error)
    fields.append("pipeline_next_retry_at = %s"); values.append(next_retry_at)
    values.append(code)
    try:
        with get_conn() as conn:
            conn.execute(
                f"UPDATE reports SET {', '.join(fields)} WHERE public_code = %s", tuple(values)
            )
            conn.commit()
    except Exception as e:
        print(f"⚠️ تعذّر تحديث حالة خط الأنابيب لـ {code}: {e}")


def _build_payload(report: dict) -> dict:
    media_paths = report.get("media_paths") or []
    media_exif = report.get("media_exif") or []
    image_url = ""
    if media_paths and PUBLIC_BASE_URL:
        image_url = f"{PUBLIC_BASE_URL}{media_paths[0]}"

    # إشارة ضعيفة (وليست دليلًا قاطعًا) يستخدمها Agent8 كسياق إضافي عند تقييم
    # احتمال أن تكون الصورة مولّدة بالذكاء الاصطناعي أو لقطة شاشة/معاد استخدامها
    first_exif = media_exif[0] if media_exif else {}
    has_camera_exif = bool(first_exif.get("device") or first_exif.get("gps_latitude"))

    return {
        "report_id": report["public_code"],
        "user_id": report["user_id"],
        "type": report.get("type"),
        "description": report.get("description") or report.get("report_text"),
        "location_text": report.get("location_text"),
        "latitude": report.get("latitude"),
        "longitude": report.get("longitude"),
        "image_url": image_url,
        "has_camera_exif": has_camera_exif,
    }


async def _post_once(payload: dict) -> tuple[bool, bool, str]:
    """يرجع (نجح، يستحق إعادة المحاولة، وصف الخطأ)."""
    try:
        async with httpx.AsyncClient(timeout=N8N_WEBHOOK_TIMEOUT) as client:
            resp = await client.post(N8N_WEBHOOK_URL, json=payload)
        if resp.status_code < 400:
            return True, False, ""
        if resp.status_code < 500:
            # 4xx = الحمولة أو المسار غلط — إعادة المحاولة لن تغيّر شيئًا
            return False, False, f"n8n رفض الطلب {resp.status_code}: {resp.text[:200]}"
        return False, True, f"n8n رد بخطأ {resp.status_code}"
    except Exception as e:
        return False, True, f"تعذّر الوصول لـ n8n: {e}"


async def trigger_report_pipeline(report: dict) -> None:
    """يُستدعى من BackgroundTasks بعد إنشاء البلاغ. لا يرفع استثناء أبدًا
    (فشل الوكيل لا يجب أن يكسر تجربة المستخدم اللي بلّغ بنجاح).

    ثلاث محاولات فورية بتراجع أسّي؛ وإن فشلت كلها يُسجَّل البلاغ كـ failed
    مع موعد إعادة محاولة يلتقطه العامل الدوري أدناه — بدل أن يضيع بصمت.
    """
    code = report["public_code"]
    if not N8N_WEBHOOK_URL:
        _set_pipeline(code, "failed", 0, "N8N_WEBHOOK_URL غير مضبوط")
        print(f"⚠️ {code}: N8N_WEBHOOK_URL غير مضبوط — البلاغ بحاجة مراجعة يدوية")
        return

    _set_pipeline(code, "processing", 0)
    payload = _build_payload(report)

    for attempt in range(1, 4):
        ok, retryable, err = await _post_once(payload)
        if ok:
            _set_pipeline(code, "completed", attempt)
            if attempt > 1:
                print(f"✅ {code}: نجح تشغيل الوكلاء بالمحاولة {attempt}")
            return
        if not retryable:
            _set_pipeline(code, "failed", attempt, err)
            print(f"❌ {code}: {err}")
            return
        print(f"⚠️ {code}: {err} (محاولة {attempt}/3)")
        if attempt < 3:
            await asyncio.sleep(2 ** attempt)  # 2ث ثم 4ث

    # فشلت المحاولات الفورية — نجدولها للعامل الدوري بدل الاستسلام
    next_retry = datetime.now(timezone.utc) + timedelta(minutes=2)
    _set_pipeline(code, "failed", 3, err, next_retry)
    print(f"⚠️ {code}: فشلت 3 محاولات — مجدول لإعادة المحاولة {next_retry:%H:%M}")


async def retry_stuck_reports() -> int:
    """يلتقط البلاغات المتعثّرة ويعيد محاولتها بتراجع أسّي متزايد.

    يغطّي أيضًا حالة لم تكن معالَجة إطلاقًا: بلاغ عالق بـ 'processing' لأن
    الخدمة أُعيد تشغيلها (نشر جديد على Render) في منتصف الاستدعاء — مهمة
    BackgroundTasks تموت مع العملية ولا أحد يلتقط البلاغ بعدها أبدًا.
    """
    if not N8N_WEBHOOK_URL:
        return 0
    now = datetime.now(timezone.utc)
    with get_conn() as conn:
        rows = conn.execute(
            """
            SELECT * FROM reports
            WHERE pipeline_attempts < %s
              AND (
                (pipeline_status = 'failed' AND pipeline_next_retry_at <= %s)
                OR (pipeline_status = 'processing' AND updated_at < %s)
                OR (pipeline_status = 'pending'    AND created_at < %s)
              )
            ORDER BY created_at LIMIT 20
            """,
            (N8N_MAX_ATTEMPTS, now, now - timedelta(minutes=10), now - timedelta(minutes=5)),
        ).fetchall()

    recovered = 0
    for row in rows:
        code = row["public_code"]
        attempts = row["pipeline_attempts"] + 1
        ok, retryable, err = await _post_once(_build_payload(row))
        if ok:
            _set_pipeline(code, "completed", attempts)
            print(f"✅ {code}: تعافى بإعادة المحاولة {attempts}")
            recovered += 1
        elif not retryable or attempts >= N8N_MAX_ATTEMPTS:
            _set_pipeline(code, "failed", attempts, f"{err} — استنفد المحاولات، يحتاج مراجعة يدوية")
            print(f"❌ {code}: استنفد {attempts} محاولات — ظاهر بالداشبورد للمراجعة اليدوية")
        else:
            # تراجع أسّي: 2، 4، 8، 16 دقيقة
            _set_pipeline(code, "failed", attempts, err,
                          now + timedelta(minutes=2 ** attempts))
    return recovered


async def retry_worker() -> None:
    """حلقة خلفية تُشغَّل عند إقلاع الخدمة."""
    print(f"🔁 عامل إعادة المحاولة يعمل كل {RETRY_SWEEP_SECONDS} ثانية")
    while True:
        await asyncio.sleep(RETRY_SWEEP_SECONDS)
        try:
            await retry_stuck_reports()
        except Exception as e:
            print(f"⚠️ خطأ بعامل إعادة المحاولة: {e}")
