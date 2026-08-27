# نشر التطبيق على App Store (iOS)

## ⚠️ مهم: هذا المشروع حاليًا Android + Web فقط

فحصت المشروع ولا يوجد مجلد `ios/` إطلاقًا — يعني `flutter create` الأصلي
اتعمل بدون دعم iOS، أو انحذف لاحقًا. **هذا قيد تقني حقيقي:**

- بناء تطبيقات iOS يتطلب **macOS + Xcode** دائمًا مهما كانت الأداة
  (حتى لو استخدمت CI/CD مثل Codemagic، الخادم نفسه لازم يكون Mac).
  ما فيه طريقة تلتف حول هذا القيد من بيئة Linux.
- ما أقدر أفبرك ملفات مشروع Xcode (`.pbxproj`) يدويًا بشكل موثوق — هذا
  ملف بصيغة معقدة وأي خطأ فيه يكسر المشروع بالكامل بدون تحذير واضح.

## الخطوات الصحيحة (على جهاز Mac)

```bash
cd app
flutter create --platforms=ios .
```

هذا يضيف مجلد `ios/` كامل ومربوط تلقائيًا بكل حزم pubspec.yaml الحالية
(http, geolocator, image_picker, speech_to_text, flutter_tts...).

### بعدها:

1. **افتح `ios/Runner.xcworkspace` بـ Xcode** (وليس `.xcodeproj`)
2. اضبط **Bundle Identifier** (مثل `com.amanai.app` — نفس القيمة المستخدمة
   بـ Android للتناسق، أو أي معرّف تختاره)
3. أضف أذونات الخصوصية بـ `ios/Runner/Info.plist` (مطلوبة إجباريًا وإلا
   يرفض Apple التطبيق تلقائيًا عند المراجعة):
   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>نحتاج موقعك لتحديد أقرب فرقة استجابة لبلاغك</string>
   <key>NSCameraUsageDescription</key>
   <string>نحتاج الكاميرا لإرفاق صورة بالبلاغ</string>
   <key>NSMicrophoneUsageDescription</key>
   <string>نحتاج الميكروفون لتسجيل بلاغ صوتي</string>
   <key>NSSpeechRecognitionUsageDescription</key>
   <string>نحتاج التعرف الصوتي لتحويل بلاغك المنطوق إلى نص</string>
   ```
4. **حساب Apple Developer** (اشتراك سنوي 99$) على
   https://developer.apple.com — بدونه ما تقدر توقّع التطبيق أو ترفعه إطلاقًا
5. بـ Xcode: **Signing & Capabilities** → اختر فريقك (Team) → يولّد شهادة توقيع تلقائيًا
6. **Product → Archive** → **Distribute App** → **App Store Connect**
7. أكمل بيانات المتجر على https://appstoreconnect.apple.com (اسم، وصف،
   أيقونات، لقطات شاشة لكل مقاس جهاز، سياسة الخصوصية كرابط عام)
8. أرسل للمراجعة (App Review) — عادة تاخذ 1-3 أيام

## بديل أسرع لو ما عندك Mac

خدمات CI/CD سحابية تشغّل macOS runners وتقدر تبني وتوقّع من عندك بدون
شراء جهاز Mac، مثل **Codemagic** (له خطة مجانية محدودة، ومصمم خصيصًا
لـ Flutter) أو GitHub Actions مع `macos-latest` runner.
