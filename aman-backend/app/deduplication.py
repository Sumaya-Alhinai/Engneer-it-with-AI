"""
ربط البلاغات المتعددة عن حادث واحد.

⚠️ المشكلة التشغيلية التي تحلها هذه الوحدة:
حريق في منطقة مزدحمة يولّد عشرين بلاغًا من عشرين شخصًا خلال دقائق. النظام
السابق يعاملها كعشرين حادثًا منفصلًا، فتظهر بغرفة العمليات عشرون بطاقة،
ويُستدعى خط الوكلاء عشرين مرة، وقد تُرسل فرق متعددة لنفس الموقع بينما مناطق
أخرى تنتظر.

المعالجة هنا تقلب هذا رأسًا على عقب: البلاغات المتقاربة زمانًا ومكانًا ومن
النوع نفسه تُربط بحادث واحد، والبلاغ الأول يصبح "البلاغ الأصل" والبقية
"تأكيدات". النتيجة ثلاث فوائد في آن:

1. غرفة العمليات ترى حادثًا واحدًا بدل عشرين.
2. خط الوكلاء يُستدعى مرة واحدة — توفير يقارب 95% من كلفة النماذج.
3. تعدد المصادر المستقلة يصبح دليل مصداقية: بلاغ واحد معزول قد يكون كاذبًا،
   لكن عشرة بلاغات من أجهزة مختلفة عن نفس الموقع خلال دقائق يصعب تزويرها.
   هذا تحقق من صحة البلاغ لا يحتاج ذكاءً اصطناعيًا إطلاقًا.
"""
import os
from math import radians, sin, cos, asin, sqrt

from .db import get_conn

# نافذة الربط: مسافة وزمن. القيم افتراضية قابلة للضبط حسب طبيعة المدينة.
DEDUP_RADIUS_M = float(os.getenv("DEDUP_RADIUS_M", "500"))
DEDUP_WINDOW_MINUTES = int(os.getenv("DEDUP_WINDOW_MINUTES", "20"))
DEDUP_ENABLED = os.getenv("DEDUP_ENABLED", "true").lower() not in ("false", "0", "no")

# حالات لا يصح الربط بها: البلاغ المرفوض أو المُغلق ليس حادثًا جاريًا
OPEN_STATUSES = ("received", "verified", "dispatched", "in_progress")


def haversine_m(lat1, lon1, lat2, lon2) -> float:
    """المسافة بالمتر بين نقطتين على سطح الأرض."""
    lat1, lon1, lat2, lon2 = map(radians, (float(lat1), float(lon1), float(lat2), float(lon2)))
    a = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2
    return 6371000 * 2 * asin(sqrt(a))


def find_parent_report(conn, *, incident_type: str, latitude, longitude,
                       exclude_id: int | None = None) -> dict | None:
    """يبحث عن بلاغ سابق يمثل نفس الحادث.

    الشرط: النوع نفسه، وضمن نافذة زمنية، وضمن نصف قطر محدد، وحالته مفتوحة.

    البلاغ بلا إحداثيات لا يُربط إطلاقًا — الربط الخاطئ أخطر من عدم الربط،
    لأنه قد يُخفي حادثًا حقيقيًا داخل حادث آخر.
    """
    if latitude is None or longitude is None:
        return None

    # ترشيح أولي بصندوق إحداثي تقريبي (أسرع من حساب المسافة لكل صف)،
    # ثم قياس المسافة الحقيقية على المرشحين القلائل
    degree_pad = (DEDUP_RADIUS_M / 111_000) * 1.5

    rows = conn.execute(
        f"""
        SELECT * FROM reports
        WHERE created_at > now() - INTERVAL '{DEDUP_WINDOW_MINUTES} minutes'
          AND status = ANY(%s)
          AND latitude BETWEEN %s AND %s
          AND longitude BETWEEN %s AND %s
          AND (parent_report_id IS NULL)
          AND (%s IS NULL OR id <> %s)
        ORDER BY created_at ASC
        """,
        (list(OPEN_STATUSES),
         float(latitude) - degree_pad, float(latitude) + degree_pad,
         float(longitude) - degree_pad, float(longitude) + degree_pad,
         exclude_id, exclude_id),
    ).fetchall()

    normalized_type = (incident_type or "").strip().lower()

    for row in rows:
        # النوع المؤكد من الوكلاء أدق من النوع الذي اختاره المستخدم
        row_type = (row.get("confirmed_incident_type") or row.get("type") or "").strip().lower()
        if normalized_type and row_type and normalized_type != row_type:
            continue
        distance = haversine_m(latitude, longitude, row["latitude"], row["longitude"])
        if distance <= DEDUP_RADIUS_M:
            return {"report": row, "distance_m": round(distance)}

    return None


def link_as_confirmation(conn, child_id: int, parent_row: dict, distance_m: float) -> dict:
    """يربط البلاغ الجديد كتأكيد لبلاغ أصل، ويحدّث عدّاد التأكيدات.

    درجة التأكيد تُحسب من عدد المصادر المستقلة، بتناقص في الأثر: أول تأكيدين
    يرفعان الثقة كثيرًا، والعاشر يضيف قليلًا — لأن ما يهم هو وجود شهود
    متعددين لا عددهم الدقيق.
    """
    conn.execute(
        """
        UPDATE reports
        SET parent_report_id = %s,
            status = 'duplicate_confirmation',
            pipeline_status = 'skipped_duplicate'
        WHERE id = %s
        """,
        (parent_row["id"], child_id),
    )

    updated = conn.execute(
        """
        UPDATE reports
        SET confirmation_count = COALESCE(confirmation_count, 0) + 1,
            updated_at = now()
        WHERE id = %s
        RETURNING confirmation_count, public_code
        """,
        (parent_row["id"],),
    ).fetchone()

    count = updated["confirmation_count"]
    return {
        "linked": True,
        "parent_code": updated["public_code"],
        "confirmation_count": count,
        "distance_m": distance_m,
        "credibility": credibility_from_confirmations(count),
    }


def credibility_from_confirmations(count: int) -> dict:
    """يحوّل عدد التأكيدات المستقلة إلى تقييم مصداقية مقروء."""
    if count >= 5:
        return {"level": "very_high", "label": "مؤكد من مصادر متعددة",
                "note": f"{count} بلاغات مستقلة عن نفس الموقع"}
    if count >= 2:
        return {"level": "high", "label": "مؤكد",
                "note": f"{count} بلاغات مستقلة عن نفس الموقع"}
    if count == 1:
        return {"level": "medium", "label": "تأكيد واحد",
                "note": "بلاغ إضافي واحد عن نفس الموقع"}
    return {"level": "unconfirmed", "label": "بلاغ منفرد",
            "note": "لم يرد بلاغ آخر عن هذا الموقع بعد"}


def check_and_link(conn, new_report: dict) -> dict:
    """نقطة الدخول: تُستدعى بعد حفظ البلاغ وقبل تشغيل خط الوكلاء.

    ترجع {'linked': False} إذا كان البلاغ حادثًا جديدًا (فيُكمل مساره
    الطبيعي)، أو تفاصيل الربط إذا كان تأكيدًا لحادث قائم (فيُوقف خط الوكلاء).
    """
    if not DEDUP_ENABLED:
        return {"linked": False}

    match = find_parent_report(
        conn,
        incident_type=new_report.get("type"),
        latitude=new_report.get("latitude"),
        longitude=new_report.get("longitude"),
        exclude_id=new_report.get("id"),
    )
    if match is None:
        return {"linked": False}

    return link_as_confirmation(conn, new_report["id"], match["report"], match["distance_m"])
