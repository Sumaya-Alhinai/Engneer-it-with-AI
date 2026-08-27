"""
معالجة صور البلاغات: حماية خصوصية من يظهر بالصورة + استخراج إشارات تحقق.

مبدأ التصميم: الخصوصية تُطبَّق قبل أي شيء آخر، وتفشل بأمان — لو تعذّر
التمويه الموجّه لأي سبب، تُموّه الصورة كاملة بدل أن تُقدَّم كما هي.
"""
import os
from datetime import datetime, timedelta
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

# دعم صور آيفون (HEIC/HEIF) — الصيغة الافتراضية لكاميرا Apple
try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    print("⚠️ pillow-heif غير مثبّت — صور HEIC لن تُعالَج")

TEMP_IMAGE_DIR = "uploads/temp_images"
RETENTION_DAYS = 2
os.makedirs(TEMP_IMAGE_DIR, exist_ok=True)

# قوة التمويه — يجب أن تكون فردية (OpenCV يرفض الأرقام الزوجية)
BLUR_STRENGTH = 31

# نسبة توسيع مربع الوجه قبل التمويه: الكاشف يعطي الوجه فقط، والشعر والأذنان
# والفك تبقى ظاهرة وقد تكفي للتعرف على الشخص، خاصة في مجتمع صغير.
FACE_PADDING = 0.25

# حد أدنى لحجم الوجه المكتشف (نسبة من عرض الصورة) — يقلل الإيجابيات الكاذبة
MIN_FACE_RATIO = 0.02


# ============== كشف الوجوه من كل الزوايا ==============

def _load_cascade(name: str):
    cascade = cv2.CascadeClassifier(cv2.data.haarcascades + name)
    return None if cascade.empty() else cascade


def _detect_faces(gray, img_width: int) -> list:
    """يجمع نتائج عدة كواشف بزوايا مختلفة.

    ⚠️ سبب هذا التعقيد: النسخة السابقة استخدمت haarcascade_frontalface_default
    وحده، وهو يكشف الوجه الأمامي فقط. في صور الحوادث الحقيقية أغلب الوجوه
    جانبية أو مائلة (المارّة يلتفتون للحادث، والمصاب ملقى على الأرض) — أي أن
    وعد الخصوصية كان يفشل بالضبط في الحالات التي يهم فيها أكثر.
    """
    min_size = max(int(img_width * MIN_FACE_RATIO), 20)
    boxes = []

    detectors = [
        ("haarcascade_frontalface_default.xml", False),
        ("haarcascade_frontalface_alt2.xml", False),
        ("haarcascade_profileface.xml", False),
        # الوجه الجانبي المتجه للجهة الأخرى: الكاشف مدرَّب على اتجاه واحد،
        # فنقلب الصورة أفقيًا ونعيد الكشف ثم نعكس الإحداثيات
        ("haarcascade_profileface.xml", True),
    ]

    for cascade_name, flip in detectors:
        cascade = _load_cascade(cascade_name)
        if cascade is None:
            continue
        target = cv2.flip(gray, 1) if flip else gray
        try:
            found = cascade.detectMultiScale(
                target, scaleFactor=1.1, minNeighbors=4, minSize=(min_size, min_size)
            )
        except Exception:
            continue
        for (x, y, w, h) in found:
            if flip:
                x = target.shape[1] - x - w
            boxes.append((int(x), int(y), int(w), int(h)))

    return _merge_boxes(boxes)


def _merge_boxes(boxes: list, overlap_threshold: float = 0.3) -> list:
    """يدمج المربعات المتداخلة — نفس الوجه قد تكتشفه عدة كواشف."""
    if not boxes:
        return []
    arr = np.array([[x, y, x + w, y + h] for x, y, w, h in boxes], dtype=float)
    areas = (arr[:, 2] - arr[:, 0]) * (arr[:, 3] - arr[:, 1])
    order = areas.argsort()[::-1]
    keep = []
    while order.size > 0:
        i = order[0]
        keep.append(i)
        xx1 = np.maximum(arr[i, 0], arr[order[1:], 0])
        yy1 = np.maximum(arr[i, 1], arr[order[1:], 1])
        xx2 = np.minimum(arr[i, 2], arr[order[1:], 2])
        yy2 = np.minimum(arr[i, 3], arr[order[1:], 3])
        inter = np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1)
        iou = inter / (areas[order[1:]] + 1e-6)
        order = order[1:][iou < overlap_threshold]
    return [
        (int(arr[i, 0]), int(arr[i, 1]), int(arr[i, 2] - arr[i, 0]), int(arr[i, 3] - arr[i, 1]))
        for i in keep
    ]


# ============== كشف الأشخاص (تغطية ما يفوت كواشف الوجه) ==============

_hog = None


def _get_hog():
    global _hog
    if _hog is None:
        _hog = cv2.HOGDescriptor()
        _hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())
    return _hog


def _detect_person_heads(img) -> list:
    """يكتشف الأشخاص ثم يرجع منطقة الرأس التقديرية لكل واحد.

    ⚠️ لماذا نحتاج هذا رغم وجود كواشف الوجه: كواشف Haar تفشل على الوجه
    المائل بزاوية كبيرة، أو المغطى جزئيًا، أو المنحني للأسفل — وهذه هي
    الحالة الغالبة بصور الحوادث الحقيقية (المصاب ملقى، والمارّة منحنون
    فوقه). كاشف الأشخاص يتعرف على الشكل البشري كاملًا بغض النظر عن اتجاه
    الوجه، فنموّه الجزء العلوي من كل شخص (الرأس والرقبة).

    ملاحظة صريحة: هذه طبقة احتياطية وليست بديلًا مثاليًا. أدق حل هو نموذج
    عصبي (YuNet/BlazeFace)، لكنه يتطلب تنزيل ملف نموذج خارجي؛ HOG مدمج
    بـ OpenCV ويعمل بلا اتصال، وهو مقايضة مناسبة هنا.
    """
    heads = []
    try:
        # HOG يحتاج حجمًا معقولًا؛ نصغّر الصور الكبيرة للسرعة ثم نعيد القياس
        scale = 1.0
        work = img
        if img.shape[1] > 900:
            scale = 900 / img.shape[1]
            work = cv2.resize(img, (900, int(img.shape[0] * scale)))

        boxes, weights = _get_hog().detectMultiScale(
            work, winStride=(8, 8), padding=(16, 16), scale=1.05
        )
        for (x, y, w, h), weight in zip(boxes, weights):
            if weight < 0.5:      # تجاهل الاكتشافات ضعيفة الثقة
                continue
            # الرأس ≈ أعلى ٢٢٪ من صندوق الشخص، وعرضه ≈ نصف عرض الجسم بالمنتصف
            head_h = int(h * 0.22)
            head_w = int(w * 0.55)
            head_x = int(x + (w - head_w) / 2)
            heads.append((
                int(head_x / scale), int(y / scale),
                int(head_w / scale), int(head_h / scale),
            ))
    except Exception as e:
        print(f"⚠️ تعذّر كشف الأشخاص: {e}")
    return heads


# ============== كشف لوحات المركبات ==============

def _detect_plates(gray, img) -> list:
    """يكتشف لوحات المركبات المحتملة.

    ⚠️ لماذا هذا ضروري تحديدًا هنا: أكثر أنواع البلاغات شيوعًا هو الحادث
    المروري، وصورة الحادث تُظهر لوحة السيارة بوضوح. رقم اللوحة يقود مباشرة
    لهوية المالك — بيان شخصي بحساسية الوجه نفسها، وكان يُعرض بلا أي حماية.

    الطريقة: كاشف Haar للوحات + بحث شكلي عن مستطيلات بنسبة أبعاد لوحة.
    ليست مثالية، ولذلك يوجد التمويه الاحتياطي أدناه.
    """
    boxes = []

    cascade = _load_cascade("haarcascade_russian_plate_number.xml")
    if cascade is not None:
        try:
            for (x, y, w, h) in cascade.detectMultiScale(gray, 1.1, 4, minSize=(40, 15)):
                boxes.append((int(x), int(y), int(w), int(h)))
        except Exception:
            pass

    # بحث شكلي مكمّل: اللوحة مستطيل عالي التباين بنسبة عرض/ارتفاع 2:1 إلى 6:1
    try:
        edges = cv2.Canny(cv2.bilateralFilter(gray, 11, 17, 17), 30, 200)
        contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        img_area = img.shape[0] * img.shape[1]
        for c in sorted(contours, key=cv2.contourArea, reverse=True)[:30]:
            peri = cv2.arcLength(c, True)
            approx = cv2.approxPolyDP(c, 0.03 * peri, True)
            if len(approx) != 4:
                continue
            x, y, w, h = cv2.boundingRect(approx)
            if h == 0:
                continue
            if 2.0 <= w / h <= 6.0 and 0.001 <= (w * h) / img_area <= 0.15:
                boxes.append((x, y, w, h))
    except Exception:
        pass

    return _merge_boxes(boxes)


# ============== التمويه ==============

def _blur_region(img, x, y, w, h, padding: float = 0.0):
    """يموّه منطقة بتمويه غير قابل للعكس (بكسلة ثم جاوس)."""
    ph, pw = int(h * padding), int(w * padding)
    x1, y1 = max(x - pw, 0), max(y - ph, 0)
    x2, y2 = min(x + w + pw, img.shape[1]), min(y + h + ph, img.shape[0])
    if x2 <= x1 or y2 <= y1:
        return
    roi = img[y1:y2, x1:x2]
    # البكسلة أولًا: التمويه الجاوسي وحده يمكن عكسه جزئيًا بخوارزميات
    # deconvolution، أما التصغير ثم التكبير فيُفقد المعلومة نهائيًا.
    small = cv2.resize(roi, (max((x2 - x1) // 12, 1), max((y2 - y1) // 12, 1)),
                       interpolation=cv2.INTER_LINEAR)
    pixelated = cv2.resize(small, (x2 - x1, y2 - y1), interpolation=cv2.INTER_NEAREST)
    img[y1:y2, x1:x2] = cv2.GaussianBlur(pixelated, (BLUR_STRENGTH, BLUR_STRENGTH), 0)


def blur_faces(image_path: str) -> dict:
    """يموّه الوجوه ولوحات المركبات ويرجع تقريرًا عمّا تم."""
    report = {"faces": 0, "plates": 0, "method": "targeted", "success": False}
    try:
        img = cv2.imread(image_path)
        if img is None:
            return report

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        # موازنة الإضاءة: صور الحوادث كثيرًا ما تكون ليلية أو بإضاءة قوية،
        # والكواشف تفشل عليها بدون هذه الخطوة
        gray = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(gray)

        faces = _detect_faces(gray, img.shape[1])
        heads = _detect_person_heads(img)
        # ندمج الوجوه مع رؤوس الأشخاص: التداخل يعني نفس الشخص، والمتبقي
        # هو شخص اكتُشف جسمه ولم يُكتشف وجهه (الحالة التي كانت تفلت سابقًا)
        all_regions = _merge_boxes(faces + heads)
        for (x, y, w, h) in all_regions:
            _blur_region(img, x, y, w, h, padding=FACE_PADDING)

        plates = _detect_plates(gray, img)
        for (x, y, w, h) in plates:
            _blur_region(img, x, y, w, h, padding=0.1)

        cv2.imwrite(image_path, img)
        report.update({
            "faces": len(faces),
            "people": len(heads),
            "regions_blurred": len(all_regions),
            "plates": len(plates),
            "success": True,
        })
        return report

    except Exception as e:
        print(f"❌ فشل التمويه الموجّه ({e}) — تطبيق التمويه الاحتياطي")
        return _blur_entire_image(image_path, report)


def _blur_entire_image(image_path: str, report: dict) -> dict:
    """تمويه احتياطي للصورة كاملة عند فشل الكشف.

    قرار مقصود: صورة مموّهة كليًا تفقد بعض قيمتها للموظف، لكن صورة غير مموّهة
    تنشر وجوه أشخاص لم يوافقوا. الخصوصية تسبق الوضوح.
    """
    try:
        img = cv2.imread(image_path)
        if img is None:
            return report
        cv2.imwrite(image_path, cv2.GaussianBlur(img, (51, 51), 0))
        report.update({"method": "full_image_fallback", "success": True})
    except Exception as e:
        print(f"❌ فشل التمويه الاحتياطي أيضًا: {e}")
    return report


# ============== توحيد صيغة الصور ==============

def normalize_to_jpeg(image_path: str) -> str:
    """يحوّل أي صورة مدعومة إلى JPEG ويرجع المسار الجديد.

    ⚠️ سبب وجود هذه الدالة ثغرة خصوصية حقيقية: OpenCV لا يستطيع كتابة ملف
    بامتداد ‎.heic، فكان التمويه يفشل، ثم يفشل التمويه الاحتياطي للسبب نفسه،
    فتُحفظ صورة آيفون **بلا أي تمويه** بينما يرد الخادم بنجاح. أي أن أخطر
    حالة ممكنة — فشل صامت للخصوصية — كانت تمر دون أن يلاحظها أحد.

    بيانات EXIF تُنقل مع التحويل لأنها أساس التحقق من صحة البلاغ.
    """
    ext = os.path.splitext(image_path)[1].lower()
    if ext in (".jpg", ".jpeg"):
        return image_path

    target = os.path.splitext(image_path)[0] + ".jpg"
    with Image.open(image_path) as img:
        exif_bytes = img.info.get("exif")
        rgb = img.convert("RGB")
        if exif_bytes:
            rgb.save(target, "JPEG", quality=92, exif=exif_bytes)
        else:
            rgb.save(target, "JPEG", quality=92)
    if target != image_path and os.path.exists(image_path):
        os.remove(image_path)
    return target


# ============== استخراج EXIF ==============

def extract_exif(image_path: str) -> dict:
    """يستخرج وقت الالتقاط والجهاز وإحداثيات الصورة — للتحقق الداخلي فقط."""
    result = {}
    try:
        img = Image.open(image_path)
        result["image_width"], result["image_height"] = img.size
        exif_raw = img._getexif()
        if not exif_raw:
            return result

        from PIL.ExifTags import TAGS, GPSTAGS
        tags = {TAGS.get(k, k): v for k, v in exif_raw.items()}

        if "DateTimeOriginal" in tags:
            result["captured_at"] = str(tags["DateTimeOriginal"])
        if "Make" in tags or "Model" in tags:
            result["device"] = f"{tags.get('Make', '')} {tags.get('Model', '')}".strip()
        if "Software" in tags:
            # اسم برنامج تحرير في البيانات إشارة على تعديل محتمل
            result["software"] = str(tags["Software"])

        gps_info = tags.get("GPSInfo")
        if gps_info:
            gps = {GPSTAGS.get(k, k): v for k, v in gps_info.items()}

            def _to_decimal(dms, ref):
                degrees, minutes, seconds = (float(x) for x in dms)
                value = degrees + minutes / 60 + seconds / 3600
                return -value if ref in ("S", "W") else value

            if "GPSLatitude" in gps and "GPSLongitude" in gps:
                try:
                    result["gps_latitude"] = _to_decimal(gps["GPSLatitude"], gps.get("GPSLatitudeRef", "N"))
                    result["gps_longitude"] = _to_decimal(gps["GPSLongitude"], gps.get("GPSLongitudeRef", "E"))
                except Exception:
                    pass
    except Exception as e:
        print(f"⚠️ تعذّر استخراج EXIF: {e}")
    return result


# ============== تحليل EXIF تلقائيًا ==============

EDITING_SOFTWARE = ("photoshop", "gimp", "lightroom", "snapseed", "picsart", "facetune")


def _haversine_km(lat1, lon1, lat2, lon2) -> float:
    from math import radians, sin, cos, asin, sqrt
    lat1, lon1, lat2, lon2 = map(radians, (lat1, lon1, lat2, lon2))
    a = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2
    return 6371 * 2 * asin(sqrt(a))


def analyse_exif(exif: dict, report_lat=None, report_lng=None, reported_at=None) -> dict:
    """يحوّل بيانات EXIF الخام إلى إشارات تحقق مقروءة للموظف.

    ⚠️ الفجوة التي يسدّها هذا: النظام كان يخزّن وقت الالتقاط والإحداثيات
    ويعرضها كأرقام خام، لكن لا أحد يقارنها بشيء. الموظف مطالَب أن يلاحظ بنفسه
    أن صورة "الحادث الآن" التُقطت قبل ثلاثة أيام — وهو لن يفعل تحت ضغط غرفة
    عمليات. هنا تجري المقارنة آليًا وتُقدَّم كتحذير صريح.

    مهم: هذه إشارات وليست أحكامًا. غياب EXIF شائع جدًا (واتساب وأغلب التطبيقات
    تحذفه)، فلا يجوز رفض بلاغ بسببه — ولذلك النبرة "يحتاج انتباه" لا "مزيّف".
    """
    flags = []
    score = 100  # درجة اتساق مبدئية تنقص مع كل إشارة

    if not exif or (not exif.get("captured_at") and not exif.get("gps_latitude")):
        flags.append({
            "level": "info",
            "message": "لا توجد بيانات وصفية بالصورة — شائع عند الإرسال عبر واتساب أو لقطة شاشة",
        })
        return {"flags": flags, "consistency_score": 85, "has_exif": False}

    # ١) فرق الوقت بين التقاط الصورة وإرسال البلاغ
    if exif.get("captured_at") and reported_at:
        try:
            shot = datetime.strptime(str(exif["captured_at"]), "%Y:%m:%d %H:%M:%S")
            ref = reported_at.replace(tzinfo=None) if reported_at.tzinfo else reported_at
            hours = (ref - shot).total_seconds() / 3600
            if hours < -1:
                flags.append({"level": "warning",
                              "message": "تاريخ التقاط الصورة في المستقبل — ساعة الجهاز غير مضبوطة أو الصورة معدّلة"})
                score -= 25
            elif hours > 72:
                flags.append({"level": "warning",
                              "message": f"الصورة التُقطت قبل {int(hours / 24)} يوم — قد تكون معاد استخدامها"})
                score -= 35
            elif hours > 6:
                flags.append({"level": "warning",
                              "message": f"الصورة التُقطت قبل {int(hours)} ساعة من الإبلاغ"})
                score -= 20
            else:
                flags.append({"level": "ok",
                              "message": f"الصورة التُقطت قبل {max(int(hours * 60), 0)} دقيقة من الإبلاغ"})
        except Exception:
            pass

    # ٢) المسافة بين موقع الصورة وموقع البلاغ
    gps_lat, gps_lng = exif.get("gps_latitude"), exif.get("gps_longitude")
    if gps_lat is not None and report_lat is not None:
        try:
            km = _haversine_km(float(gps_lat), float(gps_lng), float(report_lat), float(report_lng))
            if km > 50:
                flags.append({"level": "warning",
                              "message": f"موقع الصورة يبعد {km:.0f} كم عن موقع البلاغ — تحقق مطلوب"})
                score -= 40
            elif km > 5:
                flags.append({"level": "warning",
                              "message": f"موقع الصورة يبعد {km:.1f} كم عن موقع البلاغ"})
                score -= 20
            else:
                flags.append({"level": "ok",
                              "message": f"موقع الصورة يطابق موقع البلاغ (فرق {km * 1000:.0f} متر)"})
        except Exception:
            pass
    elif gps_lat is None and exif.get("captured_at"):
        flags.append({"level": "info", "message": "الصورة بلا إحداثيات — خدمة الموقع كانت مغلقة بالكاميرا"})
        score -= 10

    # ٣) أثر برنامج تحرير
    software = (exif.get("software") or "").lower()
    if any(name in software for name in EDITING_SOFTWARE):
        flags.append({"level": "warning", "message": f"الصورة مرّت ببرنامج تحرير ({exif['software']})"})
        score -= 25

    # ٤) وجود جهاز التقاط
    if exif.get("device"):
        flags.append({"level": "ok", "message": f"التُقطت بجهاز: {exif['device']}"})
    else:
        flags.append({"level": "info", "message": "لا يوجد اسم جهاز بالبيانات الوصفية"})
        score -= 10

    return {"flags": flags, "consistency_score": max(score, 0), "has_exif": True}


# ============== التنظيف الدوري ==============

async def cleanup_old_images():
    cutoff = datetime.now() - timedelta(days=RETENTION_DAYS)
    for image_file in Path(TEMP_IMAGE_DIR).glob("*"):
        if image_file.is_file() and datetime.fromtimestamp(image_file.stat().st_mtime) < cutoff:
            try:
                os.remove(image_file)
                print(f"🗑️ تم حذف: {image_file.name}")
            except Exception as e:
                print(f"❌ خطأ في الحذف: {e}")


def process_image(image_path: str, report_lat=None, report_lng=None, reported_at=None) -> dict:
    """المعالجة الكاملة: استخراج EXIF ثم تحليله ثم تمويه ما يجب تمويهه."""
    path = normalize_to_jpeg(image_path)
    exif = extract_exif(path)   # قبل التمويه — التمويه يعيد كتابة الملف
    analysis = analyse_exif(exif, report_lat, report_lng, reported_at)
    blur_report = blur_faces(path)
    return {"path": path, "success": blur_report["success"], "exif": exif,
            "analysis": analysis, "blur": blur_report}
