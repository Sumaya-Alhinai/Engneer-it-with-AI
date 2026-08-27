"""
تحديد معدّل الطلبات (Rate Limiting) بنافذة منزلقة.

يستخدم Redis إن كان REDIS_URL مضبوطًا، وإلا يرجع تلقائيًا لعدّاد بالذاكرة.

لماذا يهم Redis هنا: العدّاد بالذاكرة خاص بكل عملية. مع
`uvicorn --workers 4` أو أكثر من نسخة على Render، يصير الحد الفعلي مضروبًا
بعدد العمليات — أي أن حد "5 بلاغات كل 5 دقائق" يصبح عمليًا 20، ويُصفَّر
كليًا مع كل نشر جديد. مع Redis العدّاد مشترك بين كل النسخ ويبقى بعد النشر.

يبقى قيد واحد بالحالتين: الحد على IP، وشبكات كاملة قد تخرج من IP واحد
(شبكة جامعة أو مشغّل هاتف)، فلا تضيّقي الحد على مسارات القراءة.
"""
import os
import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request

REDIS_URL = os.getenv("REDIS_URL", "").strip()
_redis = None
_redis_failed = False

if REDIS_URL:
    try:
        import redis as _redis_lib
        _redis = _redis_lib.from_url(REDIS_URL, socket_timeout=2, socket_connect_timeout=2)
        _redis.ping()
        print("✅ تحديد معدّل الطلبات يستخدم Redis (مشترك بين كل النسخ)")
    except Exception as e:
        print(f"⚠️ تعذّر الاتصال بـ Redis ({e}) — الرجوع لعدّاد الذاكرة")
        _redis = None

_hits: dict[str, deque] = defaultdict(deque)
_lock = threading.Lock()
_last_cleanup = time.monotonic()
CLEANUP_EVERY_SECONDS = 300


def client_ip(request: Request) -> str:
    """يقرأ IP الحقيقي من X-Forwarded-For لأن Render/Railway/أي عاكس أمامي
    يخفي عنوان العميل خلف عنوان العاكس نفسه."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _cleanup(now: float) -> None:
    """يحذف المفاتيح الخاملة حتى لا يكبر القاموس بلا حدود (تسريب ذاكرة)."""
    global _last_cleanup
    if now - _last_cleanup < CLEANUP_EVERY_SECONDS:
        return
    _last_cleanup = now
    for key in list(_hits.keys()):
        bucket = _hits[key]
        while bucket and bucket[0] < now - 3600:
            bucket.popleft()
        if not bucket:
            del _hits[key]


def _hit_redis(key: str, limit: int, window_seconds: int) -> tuple[bool, int]:
    """نافذة منزلقة بـ Redis عبر sorted set. عند أي عطل بـ Redis نسمح بالطلب
    (fail-open) بدل تعطيل الخدمة كاملة — منع إساءة الاستخدام أقل أهمية من
    إبقاء خط الإبلاغ عن الطوارئ يعمل."""
    global _redis_failed
    now = time.time()
    member = f"{now}:{os.urandom(4).hex()}"
    try:
        pipe = _redis.pipeline()
        pipe.zremrangebyscore(key, 0, now - window_seconds)
        pipe.zcard(key)
        pipe.zadd(key, {member: now})
        pipe.expire(key, window_seconds + 60)
        _, count, _, _ = pipe.execute()
        if count >= limit:
            _redis.zrem(key, member)
            oldest = _redis.zrange(key, 0, 0, withscores=True)
            retry_after = int(oldest[0][1] + window_seconds - now) + 1 if oldest else window_seconds
            return False, max(retry_after, 1)
        return True, 0
    except Exception as e:
        if not _redis_failed:
            _redis_failed = True
            print(f"⚠️ عطل بـ Redis أثناء تحديد المعدّل ({e}) — السماح بالطلبات مؤقتًا")
        return True, 0


def hit(key: str, limit: int, window_seconds: int) -> tuple[bool, int]:
    """يسجّل محاولة ويرجع (مسموح؟، ثواني الانتظار المتبقية عند الرفض)."""
    if _redis is not None:
        return _hit_redis(f"ratelimit:{key}", limit, window_seconds)
    now = time.monotonic()
    with _lock:
        _cleanup(now)
        bucket = _hits[key]
        cutoff = now - window_seconds
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= limit:
            retry_after = int(bucket[0] + window_seconds - now) + 1
            return False, max(retry_after, 1)
        bucket.append(now)
        return True, 0


def limiter(name: str, limit: int, window_seconds: int):
    """ينتج Dependency لـ FastAPI: Depends(limiter("reports_create", 5, 60)).
    الحدود قابلة للضبط بمتغيرات بيئة مثل RATE_REPORTS_CREATE=5/60."""
    env_key = f"RATE_{name.upper()}"
    configured = os.getenv(env_key)
    if configured and "/" in configured:
        try:
            raw_limit, raw_window = configured.split("/", 1)
            limit, window_seconds = int(raw_limit), int(raw_window)
        except ValueError:
            print(f"⚠️ قيمة {env_key} غير صالحة ({configured}) — استخدام الافتراضي")

    def dependency(request: Request) -> None:
        if os.getenv("RATE_LIMIT_ENABLED", "true").lower() in ("false", "0", "no"):
            return
        allowed, retry_after = hit(f"{name}:{client_ip(request)}", limit, window_seconds)
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail={
                    "code": "RATE_LIMITED",
                    "message": f"طلبات كثيرة خلال وقت قصير. حاول بعد {retry_after} ثانية.",
                    "retry_after": retry_after,
                },
                headers={"Retry-After": str(retry_after)},
            )

    return dependency
