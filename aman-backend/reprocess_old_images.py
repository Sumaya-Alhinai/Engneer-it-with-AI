"""
يعالج كل الصور الموجودة مسبقًا بمجلد uploads/evidence بتمويه الوجوه —
لإصلاح الصور التي رُفعت قبل تصحيح باگ BLUR_STRENGTH (كانت قيمة زوجية 30
تُسقط GaussianBlur بصمت، فتصل الصور بدون أي تمويه رغم نجاح كشف الوجه).

الاستخدام (من داخل مجلد aman-backend، وبعد تفعيل نفس بيئة الباك-إند):
    python3 reprocess_old_images.py

آمن للتشغيل أكثر من مرة: لو الوجه انطمس مسبقًا، تمويه فوق تمويه لا يضر
(تمويه إضافي بسيط على منطقة مموّهة أصلًا، لا يكشف الوجه من جديد).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from image_processor import blur_faces  # noqa: E402

EVIDENCE_DIR = "uploads/evidence"
IMAGE_EXTS = {".jpg", ".jpeg", ".png"}


def main():
    if not os.path.isdir(EVIDENCE_DIR):
        print(f"⚠️ المجلد غير موجود: {EVIDENCE_DIR} — شغّل هذا السكربت من نفس مجلد aman-backend")
        return

    files = [
        f for f in os.listdir(EVIDENCE_DIR)
        if os.path.splitext(f)[1].lower() in IMAGE_EXTS
    ]
    if not files:
        print("لا توجد صور بمجلد uploads/evidence.")
        return

    print(f"وجدت {len(files)} صورة. بدء إعادة المعالجة...\n")
    ok, failed = 0, 0
    for f in files:
        path = os.path.join(EVIDENCE_DIR, f)
        success = blur_faces(path)
        if success:
            ok += 1
            print(f"  ✅ {f}")
        else:
            failed += 1
            print(f"  ❌ فشلت: {f}")

    print(f"\nتم: {ok} نجحت، {failed} فشلت من أصل {len(files)}.")


if __name__ == "__main__":
    main()
