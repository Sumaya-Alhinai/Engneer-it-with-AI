import os
import threading
from pathlib import Path

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from dotenv import load_dotenv

load_dotenv()

# ============== تجمّع الاتصالات (Connection Pool) ==============
# قبل: كل طلب HTTP يفتح اتصال PostgreSQL جديد ويقفله (psycopg.connect لكل طلب).
# فتح الاتصال نفسه يكلّف ~20-50ms (TCP + TLS + مصادقة)، وأخطر من ذلك أن خطة
# Render/Railway المجانية تسمح بعدد اتصالات محدود جدًا (غالبًا 20-25): مع 30
# مستخدمًا متزامنًا يبدأ الرفض بـ "too many connections" ويسقط الباك-إند كامل.
# الآن: مجموعة اتصالات جاهزة تُعاد للاستخدام، بحد أقصى مضبوط بمتغير بيئة.
_pool: ConnectionPool | None = None
_pool_lock = threading.Lock()

POOL_MIN = int(os.getenv("DB_POOL_MIN", "1"))
POOL_MAX = int(os.getenv("DB_POOL_MAX", "10"))


def _get_pool() -> ConnectionPool:
    """ينشئ المجموعة عند أول استخدام فقط (كسول) حتى لا يفشل استيراد الوحدة
    إذا لم يكن DATABASE_URL جاهزًا بعد وقت الاستيراد."""
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                dsn = os.getenv("DATABASE_URL")
                if not dsn:
                    raise RuntimeError(
                        "DATABASE_URL غير مضبوط — انسخ .env.example إلى .env واملأ رابط قاعدة البيانات"
                    )
                _pool = ConnectionPool(
                    dsn,
                    min_size=POOL_MIN,
                    max_size=POOL_MAX,
                    kwargs={"row_factory": dict_row},
                    open=True,
                )
    return _pool


def get_conn():
    """يرجع اتصالًا من المجموعة كـ context manager.

    الاستخدام لم يتغيّر إطلاقًا عن السابق:
        with get_conn() as conn:
            conn.execute(...)
            conn.commit()

    الفرق أن الخروج من الـ with يُعيد الاتصال للمجموعة بدل إغلاقه.
    """
    return _get_pool().connection()


def close_pool() -> None:
    """يُستدعى عند إطفاء الخدمة لإغلاق الاتصالات بنظافة."""
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def init_db():
    """يطبّق schema.sql عند إقلاع الخدمة (آمن للتكرار: IF NOT EXISTS)."""
    schema_path = Path(__file__).parent / "schema.sql"
    sql = schema_path.read_text(encoding="utf-8")
    with get_conn() as conn:
        conn.execute(sql)
        conn.commit()
