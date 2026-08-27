import './AppLanding.css';

export default function AppLanding() {
  return (
    <main className="app-landing" dir="rtl">
      <nav className="app-landing__nav">
        <a className="app-landing__brand" href="/app" aria-label="Aman AI">
          <span className="app-landing__brand-mark">A</span>
          <span>Aman AI</span>
        </a>
        <a className="app-landing__dashboard-link" href="/">
          دخول لوحة التحكم
          <span aria-hidden="true">←</span>
        </a>
      </nav>

      <section className="app-landing__hero">
        <div className="app-landing__copy">
          <span className="app-landing__eyebrow">الأمان يبدأ بخطوة</span>
          <h1>بلّغ بسرعة،<br /><em>ووصل صوتك.</em></h1>
          <p>
            تطبيق Aman AI يساعدك على إرسال البلاغات والحالات الطارئة بسهولة،
            مع مشاركة موقعك وتفاصيل الحالة مع الجهة المختصة.
          </p>
          <div className="app-landing__actions">
            <a
              className="app-landing__download"
              href="https://github.com/Sumaya-Alhinai/Engneer-it-with-AI/releases/latest/download/aman-ai.apk"
            >
              <span className="app-landing__download-icon" aria-hidden="true">↓</span>
              <span>
                <small>متوفر لنظام Android</small>
                تنزيل التطبيق APK
              </span>
            </a>
            <span className="app-landing__version">الإصدار 1.0.0 · تنزيل مجاني</span>
          </div>
        </div>

        <div className="app-landing__visual" aria-label="معاينة تطبيق Aman AI">
          <div className="app-landing__glow" />
          <div className="app-landing__phone">
            <div className="app-landing__phone-top"><span /> <b>Aman AI</b> <span /></div>
            <div className="app-landing__phone-content">
              <span className="app-landing__welcome">مرحباً بك في</span>
              <strong>Aman AI</strong>
              <div className="app-landing__emergency-card">
                <span className="app-landing__emergency-icon">!</span>
                <span><b>بلاغ طارئ</b><small>نحن هنا لمساعدتك</small></span>
              </div>
              <div className="app-landing__mini-row"><span /> <span /> <span /></div>
              <div className="app-landing__phone-button">إرسال بلاغ جديد</div>
            </div>
          </div>
          <div className="app-landing__floating app-landing__floating--top">موقعك محفوظ بدقة <b>✓</b></div>
          <div className="app-landing__floating app-landing__floating--bottom"><b>24/7</b> دعم متواصل</div>
        </div>
      </section>

      <section className="app-landing__features" aria-label="مميزات التطبيق">
        <div><b>01</b><strong>إبلاغ فوري</strong><span>أرسل تفاصيل الحالة في ثوانٍ</span></div>
        <div><b>02</b><strong>موقع دقيق</strong><span>شارك موقعك مع الجهة المختصة</span></div>
        <div><b>03</b><strong>متابعة واضحة</strong><span>تابع حالة بلاغك خطوة بخطوة</span></div>
      </section>
    </main>
  );
}
