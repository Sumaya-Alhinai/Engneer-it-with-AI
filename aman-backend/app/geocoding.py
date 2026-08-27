"""
تحويل الإحداثيات إلى موقع إداري حقيقي (ولاية/محافظة/حي).

⚠️ لماذا هذه الوحدة موجودة: وكيل تحليل الموقع (Agent 4) كان يستقبل إحداثيات
مثل 23.5933, 58.2844 ويُطلب منه تحديد الولاية والحي. النماذج اللغوية لا تجري
تحويلًا جغرافيًا عكسيًا — هي تستدعي ما تتذكره، فتصيب في المشهور وتخترع في
غيره. النتيجة: بيانات موقع تبدو دقيقة وهي تخمين، وهذا أسوأ من عدم وجودها
لأن غرفة العمليات ستتصرف بناءً عليها.

الحل: Nominatim (خدمة OpenStreetMap) — مجانية، لا تحتاج مفتاحًا، وتعطي
الولاية والمحافظة والحي فعليًا من قاعدة بيانات جغرافية.

شروط استخدام Nominatim تفرض: ترويسة User-Agent معرِّفة، وحدًا أقصى طلب واحد
بالثانية. كلاهما مطبَّق أدناه. للإنتاج بحجم كبير يُفضل استضافة نسخة خاصة أو
استخدام مزود مدفوع.
"""
import os
import threading
import time

import httpx

NOMINATIM_URL = os.getenv("NOMINATIM_URL", "https://nominatim.openstreetmap.org/reverse")
NOMINATIM_USER_AGENT = os.getenv("NOMINATIM_USER_AGENT", "AmanAI-EmergencyPlatform/1.0")
GEOCODE_TIMEOUT = float(os.getenv("GEOCODE_TIMEOUT", "8"))
GEOCODE_ENABLED = os.getenv("GEOCODE_ENABLED", "true").lower() not in ("false", "0", "no")

# ذاكرة مؤقتة: البلاغات المتعددة من نفس الحادث تشترك بنفس الموقع تقريبًا،
# والتقريب لأربع منازل (~11 متر) يجعلها تصيب نفس المفتاح
_cache: dict[tuple, dict] = {}
_cache_lock = threading.Lock()
_last_request_at = 0.0
_rate_lock = threading.Lock()


def _respect_rate_limit():
    """طلب واحد بالثانية كحد أقصى — شرط استخدام Nominatim العامة."""
    global _last_request_at
    with _rate_lock:
        elapsed = time.monotonic() - _last_request_at
        if elapsed < 1.0:
            time.sleep(1.0 - elapsed)
        _last_request_at = time.monotonic()


def reverse_geocode(lat: float, lng: float) -> dict:
    """يحوّل إحداثيات إلى موقع إداري.

    يرجع dict فيه: wilayat, governorate, neighbourhood, road, display_name,
    source. عند أي فشل يرجع source='unavailable' مع الحقول فارغة — لا يرمي
    استثناء ولا يخمّن، لأن غياب المعلومة أوضح من معلومة مخترعة.
    """
    empty = {"wilayat": None, "governorate": None, "neighbourhood": None,
             "road": None, "display_name": None, "source": "unavailable"}

    if not GEOCODE_ENABLED or lat is None or lng is None:
        return empty

    key = (round(float(lat), 4), round(float(lng), 4))
    with _cache_lock:
        if key in _cache:
            return {**_cache[key], "source": "cache"}

    try:
        _respect_rate_limit()
        resp = httpx.get(
            NOMINATIM_URL,
            params={
                "lat": lat, "lon": lng, "format": "jsonv2",
                "zoom": 14,                 # مستوى الحي/القرية
                "accept-language": "ar,en",  # نفضّل العربية لواجهة عربية
            },
            headers={"User-Agent": NOMINATIM_USER_AGENT},
            timeout=GEOCODE_TIMEOUT,
        )
        if resp.status_code >= 400:
            print(f"⚠️ Nominatim رد بخطأ {resp.status_code}")
            return empty

        addr = resp.json().get("address", {})
        result = {
            # في عُمان تظهر الولاية غالبًا كـ county أو city أو town
            "wilayat": addr.get("county") or addr.get("city") or addr.get("town") or addr.get("village"),
            "governorate": addr.get("state") or addr.get("region"),
            "neighbourhood": addr.get("neighbourhood") or addr.get("suburb") or addr.get("quarter"),
            "road": addr.get("road"),
            "display_name": resp.json().get("display_name"),
            "source": "nominatim",
        }
        with _cache_lock:
            _cache[key] = {k: v for k, v in result.items() if k != "source"}
        return result

    except Exception as e:
        print(f"⚠️ تعذّر التحويل الجغرافي: {e}")
        return empty


def describe(geo: dict) -> str:
    """يبني وصفًا عربيًا مختصرًا للعرض بالداشبورد."""
    if not geo or geo.get("source") == "unavailable":
        return ""
    parts = [geo.get("neighbourhood"), geo.get("wilayat"), geo.get("governorate")]
    return "، ".join(p for p in parts if p)
