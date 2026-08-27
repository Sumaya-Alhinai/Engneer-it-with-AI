# توقيع تطبيق أندرويد للنشر على Google Play

Google Play يرفض أي APK/AAB موقّع بمفتاح debug. اتبع هذي الخطوات **مرة واحدة**
على جهازك (تحتاج Flutter SDK مثبت محليًا؛ لا تُنفَّذ هذي الخطوات هنا):

## 1) أنشئ مفتاح التوقيع

```bash
keytool -genkey -v -keystore ~/aman-ai-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias aman_ai_key
```

راح يطلب منك كلمة مرور للـ keystore وأخرى للمفتاح (يمكن نفس الكلمة) —
**احفظهم بمكان آمن**. لو ضاع هذا الملف لاحقًا، ما تقدر تحدّث نفس التطبيق
بمتجر Google Play أبدًا؛ لازم تنشر تطبيق جديد بمعرّف مختلف.

## 2) أنشئ `android/key.properties` (لا يُرفع لـ git — موجود بـ .gitignore بالفعل)

```properties
storePassword=<كلمة مرور الـ keystore>
keyPassword=<كلمة مرور المفتاح>
keyAlias=aman_ai_key
storeFile=/المسار/الكامل/لـ/aman-ai-release.jks
```

`android/app/build.gradle.kts` بهذا المشروع مُعدّ مسبقًا ليقرأ هذا الملف
تلقائيًا ويوقّع نسخة release به إذا كان موجودًا (راجع `signingConfigs`).

## 3) ابنِ نسخة الإصدار

```bash
cd app
flutter build appbundle --release   # الصيغة المطلوبة لمتجر Google Play (.aab)
# أو لتجربة APK مباشرة على جهاز:
flutter build apk --release --split-per-abi
```

الناتج: `app/build/app/outputs/bundle/release/app-release.aab`

## 4) ارفعه على Google Play Console

1. أنشئ حساب مطوّر (رسم لمرة واحدة ~25$) على https://play.google.com/console
2. أنشئ تطبيقًا جديدًا → املأ بيانات المتجر (اسم، وصف، أيقونة 512×512،
   لقطات شاشة، سياسة الخصوصية — استخدم `/privacy-policy` بالباك-إند كمرجع
   وحوّلها لصفحة ويب فعلية منشورة برابط عام، Google يطلب رابطًا وليس JSON)
3. ارفع ملف `.aab` بقسم Production أو Internal testing للتجربة أولًا
4. أكمل استبيان "Data safety" (بما إن التطبيق يجمع موقعًا وصورًا، صرّح بذلك بدقة)
