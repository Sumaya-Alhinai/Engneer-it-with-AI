"""
أدوات أمان بسيطة تعتمد فقط على مكتبة بايثون القياسية (hashlib/secrets)
حتى لا نحتاج مكتبات تجميع إضافية (مثل bcrypt) قد تعقّد النشر على Render/Railway.
"""
import hashlib
import hmac
import os
import re
import secrets
import string
import unicodedata


def hash_password(password: str) -> str:
    """PBKDF2-HMAC-SHA256 مع salt عشوائي. الناتج: 'salt$hash' (hex)."""
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(salt), 200_000)
    return f"{salt}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        salt, hex_digest = stored.split("$")
    except ValueError:
        return False
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(salt), 200_000)
    return hmac.compare_digest(digest.hex(), hex_digest)


def generate_verification_code() -> str:
    """رمز تحقق من 6 أرقام."""
    return "".join(secrets.choice(string.digits) for _ in range(6))


def generate_session_token() -> str:
    return secrets.token_urlsafe(32)


def generate_public_id(prefix: str) -> str:
    """معرّف عام قصير مثل USR-4831."""
    return f"{prefix}-{secrets.randbelow(9000) + 1000}"


# أبجدية بلا أحرف متشابهة (0/O، 1/I/L) — الرمز يُقرأ بالهاتف أحيانًا
_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


def generate_report_code() -> str:
    """رمز بلاغ عشوائي مثل AMN-K7M2QX9P.

    ⚠️ يستبدل الصيغة السابقة 'AMN-' || (1000 + id) وهي متسلسلة ومتوقّعة:
    من يعرف رقم بلاغه AMN-1042 يعرف أن AMN-1041 و AMN-1043 موجودان، فيقدر
    يجرّبهما واحدًا واحدًا. المصادقة وحدها تكفي لمنع القراءة، لكن التسلسل
    يسرّب معلومة إضافية بلا مقابل: العدد الكلي للبلاغات ومعدّل ورودها
    (فرق الرقمين بين يومين = كم بلاغًا استقبل النظام) — وهذه معلومة تشغيلية
    لا يجب أن تكون متاحة لكل من قدّم بلاغًا واحدًا.
    31^8 ≈ 850 مليار احتمال، فالتخمين غير عملي.
    """
    return "AMN-" + "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))


def generate_guest_id() -> str:
    """معرّف ضيف يولّده الخادم (وليس التطبيق) حتى لا يقدر أحد ينتحل معرّف
    مستخدم مسجّل بمجرد كتابة USR-1234 بحقل نصي."""
    return f"GUEST-{secrets.token_hex(8)}"


def constant_time_eq(a: str, b: str) -> bool:
    return hmac.compare_digest(a or "", b or "")


# ============== تنظيف أسماء الملفات المرفوعة ==============
# ⚠️ الثغرة التي يعالجها هذا الجزء (Path Traversal):
# الكود السابق كان يبني مسار الحفظ من اسم الملف كما أرسله المستخدم حرفيًا:
#     safe_name = f"{prefix}_{timestamp}_{upload.filename}".replace(" ", "_")
#     dest = os.path.join("uploads/evidence", safe_name)
# استبدال المسافات لا يمنع الشرطات المائلة. مهاجم يرسل ملفًا اسمه
#     ../../app/main.py
# فيصبح المسار خارج مجلد uploads ويكتب فوق كود الخدمة نفسه.
# الحل: نتجاهل اسم المستخدم بالكامل كمسار، ونأخذ منه فقط جزءًا نصيًا نظيفًا
# للعرض، مع امتداد من قائمة بيضاء نحدّدها نحن حسب نوع المحتوى.

# نسمح بالحروف العربية إضافة للاتينية: اسم "حادث.jpg" كان يصير "file.jpg"،
# وهو تدهور غير مبرر لمشروع واجهته عربية. الخطر ليس بالحروف نفسها بل
# بمحارف المسار (/ \ ..) ومحارف التحكم — وهذه تُزال أدناه.
_SAFE_CHARS = re.compile(r"[^A-Za-z0-9\u0600-\u06FF._-]")

EXTENSION_BY_CONTENT_TYPE = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "audio/mpeg": ".mp3",
    "audio/mp4": ".m4a",
    "audio/aac": ".aac",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/webm": ".webm",
    "audio/ogg": ".ogg",
    "image/heic": ".heic",
    "image/heif": ".heif",
    "image/webp": ".webp",
}


def safe_filename_stem(original: str | None, max_len: int = 40) -> str:
    """يستخرج جزءًا نصيًا آمنًا فقط من اسم الملف الأصلي (بدون امتداد وبدون مسار).
    أي شيء غير [A-Za-z0-9._-] يُستبدل بشرطة سفلية، وأي محاولة مسار تُلغى."""
    if not original:
        return "file"
    # os.path.basename وحده لا يكفي على ويندوز/مسارات مختلطة — نقصّ من الاتجاهين
    base = os.path.basename(original.replace("\\", "/"))
    # NFC وليس NFKD: التطبيع التوافقي يفكّك الحروف العربية ويشوّهها
    base = unicodedata.normalize("NFC", base)
    # إزالة محارف التحكم والاتجاه (RLO/LRO) — تُستخدم لتزوير الامتداد بصريًا:
    # اسم يبدو "photo.jpg" وهو فعليًا "gpj.exe" بمحرف عكس اتجاه
    base = "".join(ch for ch in base if unicodedata.category(ch) not in ("Cc", "Cf"))
    stem, _ = os.path.splitext(base)
    stem = _SAFE_CHARS.sub("_", stem).strip("._-")
    stem = stem[:max_len]
    return stem or "file"


def extension_for(content_type: str | None, fallback: str = ".bin") -> str:
    """الامتداد يُشتق من نوع المحتوى المصرّح به (قائمة بيضاء) وليس من اسم
    الملف — حتى لا يُحفظ ملف باسم evidence.php أو evidence.html ويُقدَّم لاحقًا
    من مسار /media كصفحة قابلة للتنفيذ/الحقن."""
    return EXTENSION_BY_CONTENT_TYPE.get((content_type or "").lower(), fallback)
