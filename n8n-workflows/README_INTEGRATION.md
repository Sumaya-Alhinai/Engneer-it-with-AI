# ربط وكلاء n8n بالباك-إند — دليل الإعداد

## ما الذي تغيّر في `Aman_AI_Master_Workflow.json`؟

1. **عقدة `Edit Fields`**: كانت تولّد `report_id` جديدًا بنفسها (`R-...`) بدل استخدام
   رقم البلاغ (`AMN-1001`) اللي ينشئه الباك-إند. عدّلتها لتقرأ `body.report_id` مباشرة —
   هذا ضروري حتى تقدر عقدة الحفظ الأخيرة تحدّث نفس البلاغ الصحيح بقاعدة البيانات.

2. **عقدة جديدة `HTTP Request - حفظ نتيجة الوكلاء بالباك-إند`**: أضفتها بين
   `Final Status` و `Respond to Webhook - نجاح`. هذي هي الحلقة المفقودة —
   بدونها، الوكلاء الثمانية كانوا يحللون البلاغ لكن النتيجة توصل لباك-إند أبدًا،
   وتضيع بمجرد انتهاء تنفيذ الوركفلو.
   ترسل `PATCH {AMAN_BACKEND_URL}/api/reports/{report_id}/classification` بالحقول:
   `confirmed_incident_type`, `department`, `priority`, `risk_score`,
   `verification_status`, `location_status`, `ai_reason`, `status`.

## خطوات الاستيراد على n8n

1. **استورد الوكلاء الفرعيين أولًا** (Agent1 إلى Agent8) كل واحد وركفلو مستقل،
   ثم افتح `Aman_AI_Master_Workflow.json` واستورده.
2. بعقدة **`Call Agent8(تحليل الصورة)`** — اختر وركفلو Agent8 من القائمة المنسدلة
   (workflowId فارغ افتراضيًا لأن n8n يربط الوركفلوز الفرعية بمعرّف داخلي يختلف
   من نسخة تثبيت لأخرى).
3. اضبط **بيانات اعتماد OpenAI** (Credentials) على عقد `OpenAI Chat Model 1-6`
   بمفتاح API الخاص بك.
4. **أضف متغيرَي بيئة على n8n نفسه** (Settings → Environment Variables، أو
   `.env` لو مستضاف بنفسك):
   - `AMAN_BACKEND_URL` = رابط الباك-إند العام بدون `/` بالنهاية،
     مثل `https://aman-ai-backend.onrender.com`
   - `N8N_CALLBACK_SECRET` = نفس القيمة المضبوطة بـ `N8N_CALLBACK_SECRET`
     بملف `.env` الخاص بالباك-إند (سر مشترك يمنع أي طرف خارجي من التلاعب
     بتصنيف البلاغات عبر تخمين رابط الـ endpoint).
5. **فعّل الوركفلو (Active)** وانسخ رابط الويب هوك الحقيقي (Production URL)
   من عقدة `Webhook` — ضعه بمتغير `N8N_WEBHOOK_URL` بملف `.env` الخاص بالباك-إند.

## اختبار سريع للحلقة كاملة

```bash
curl -X POST "$AMAN_BACKEND_URL/api/reports" \
  -F "user_id=USR-1000" -F "type=حريق" \
  -F "description=حريق بمخزن قرب دوار الخوض" \
  -F "latitude=23.59" -F "longitude=58.28"
```

راقب سجلات الباك-إند (يجب أن تشغّل الوكلاء بالخلفية)، ثم بعد ثوانٍ (المدة تعتمد
على عدد استدعاءات OpenAI):

```bash
curl "$AMAN_BACKEND_URL/api/reports/AMN-1001"
```

يجب أن تشوف `department` و `priority` و `confirmed_incident_type` معبّأة —
هذا دليل إن الحلقة (تطبيق → باك-إند → n8n → باك-إند → داشبورد) شغّالة كاملة.
