# أمان AI — React Native / Expo Go

نسخة مستقلة من تطبيق أمان AI مبنية بـ React Native وExpo SDK 54، ومتصلة مباشرةً بمشروع Supabase الإنتاجي عبر `mobile-api`.

## التشغيل على Expo Go

```bash
cd expo-app
npm install
npx expo start --tunnel
```

افتح Expo Go على الهاتف وامسح رمز QR. لا تحتاج إلى API key داخل التطبيق؛ الرابط العام الآمن مضبوط افتراضياً على:

`https://dwhvgxilxzmxatwejfmu.supabase.co/functions/v1/mobile-api`

يمكن تغييره عند الحاجة فقط:

```bash
EXPO_PUBLIC_API_BASE_URL=https://example.com/functions/v1/mobile-api npx expo start
```

## ما يعمل في Expo Go

- الدخول كضيف أو بالبريد مع حفظ الجلسة محلياً.
- إرسال بلاغ نصي أو بلاغ مع حتى 3 صور.
- التصوير بالكاميرا أو الاختيار من مكتبة الصور.
- تحديد GPS وكتابة وصف للموقع.
- تشغيل وكيل Aman AI في Supabase بعد حفظ البلاغ.
- متابعة حالة البلاغ والتحليل بالتحديث التلقائي.
- التنبيهات العامة والمساعد الإرشادي مع قراءة الرد صوتياً.

## التحقق

```bash
npm run typecheck
npm run lint
npm run export:web
npx expo-doctor
```

