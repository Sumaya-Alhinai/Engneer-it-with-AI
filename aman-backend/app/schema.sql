-- ============================================================
-- Aman AI — Database Schema
-- يُطبَّق تلقائيًا عند إقلاع الباك-إند (idempotent: IF NOT EXISTS)
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    public_id       TEXT UNIQUE NOT NULL,           -- USR-1000 ... يُستخدم بالتطبيق كـ user_id
    name            TEXT NOT NULL,
    email           TEXT UNIQUE,
    phone           TEXT UNIQUE,
    password_hash   TEXT NOT NULL,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    language        TEXT NOT NULL DEFAULT 'ar',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_email_or_phone CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS verification_codes (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code            TEXT NOT NULL,
    channel         TEXT NOT NULL,                  -- 'email' | 'phone'
    attempts        INTEGER NOT NULL DEFAULT 0,     -- محاولات خاطئة؛ يُلغى الرمز بعد 5
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- جلسات المواطنين (مسجّلين وضيوف). user_public_id نصّي وليس مفتاحًا خارجيًا
-- لأن الضيف لا يملك صفًّا بجدول users.
CREATE TABLE IF NOT EXISTS user_sessions (
    token           TEXT PRIMARY KEY,
    user_public_id  TEXT NOT NULL,
    is_guest        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_user_sessions_public_id ON user_sessions(user_public_id);

CREATE TABLE IF NOT EXISTS staff (
    id              SERIAL PRIMARY KEY,
    access_code     TEXT UNIQUE NOT NULL,            -- كود دخول الموظف (بسيط بدل username/password)
    label           TEXT NOT NULL,                    -- اسم يظهر بالداشبورد، مثل "غرفة عمليات الشرطة"
    department      TEXT,                             -- NULL = يشوف كل الجهات (Admin)
    is_admin        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS staff_sessions (
    token           TEXT PRIMARY KEY,
    staff_id        INTEGER NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS reports (
    id                      SERIAL PRIMARY KEY,
    public_code             TEXT UNIQUE NOT NULL DEFAULT 'PENDING',   -- report_id بالتطبيق/الداشبورد، مثل AMN-1001
    user_id                 TEXT NOT NULL,             -- public_id لليوزر أو GUEST-...
    channel                 TEXT NOT NULL DEFAULT 'app',
    type                    TEXT,                       -- نوع البلاغ الأولي من المستخدم
    report_text             TEXT,                       -- alias قديم يبقى لتوافق /reports القديم
    description             TEXT,
    location_text           TEXT,
    latitude                DOUBLE PRECISION,
    longitude               DOUBLE PRECISION,
    media_paths             JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- بيانات EXIF المستخرجة من الصور (GPS/وقت الالتقاط/الجهاز) — للتحقق الداخلي
    -- من صحة البلاغ فقط (مثلاً: هل موقع GPS بالصورة يطابق location_text المُدخل؟).
    -- لا تُعرض بمسارات المواطن العامة، فقط بمسارات /api/reports/staff وما شابه.
    media_exif              JSONB NOT NULL DEFAULT '[]'::jsonb,
    voice_note_path         TEXT,
    image_file_id           TEXT,
    image_processed         BOOLEAN NOT NULL DEFAULT FALSE,
    privacy_level           TEXT NOT NULL DEFAULT 'none',
    -- نتائج خط أنابيب الوكلاء الثمانية (n8n) — تُملأ لاحقًا عبر /api/reports/{id}/classification
    confirmed_incident_type TEXT,
    priority                TEXT,                       -- low | medium | high | critical
    risk_score              INTEGER,
    department              TEXT,                       -- Police | Ambulance | Civil Defense | ...
    verification_status     TEXT,
    location_status         TEXT,
    ai_reason               TEXT,
    -- نتائج فحص صحة الصورة (وكيل8 + إشارة EXIF) — احتمالية وليست يقينًا، راجع
    -- image_ai_generated_reason قبل اتخاذ أي قرار بناءً عليها
    image_is_plausible      BOOLEAN,
    image_authenticity_reason TEXT,
    image_ai_generated_suspected BOOLEAN,
    image_ai_generated_reason TEXT,
    -- القيم بالإنجليزية عمدًا لتطابق Labels.statusOrder بتطبيق Flutter وlabels.ts بالداشبورد:
    -- received (تم الاستلام) -> dispatched (قيد المعالجة/أُرسل للجهة) -> en_route (بالطريق) -> resolved (تم الحل)
    status                  TEXT NOT NULL DEFAULT 'received',
    expiry_date             DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reports_user_id ON reports(user_id);
CREATE INDEX IF NOT EXISTS idx_reports_department ON reports(department);
CREATE INDEX IF NOT EXISTS idx_reports_public_code ON reports(public_code);

CREATE TABLE IF NOT EXISTS response_units (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    unit_type       TEXT NOT NULL,                     -- Police | Ambulance | Civil Defense
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    is_available    BOOLEAN NOT NULL DEFAULT TRUE
);

-- بيانات أولية اختبارية لفرق الاستجابة (احذفها/عدّلها لبياناتك الحقيقية)
INSERT INTO response_units (name, unit_type, latitude, longitude, is_available)
SELECT * FROM (VALUES
    ('دورية شرطة الخوض', 'Police', 23.5933, 58.2844, TRUE),
    ('إسعاف مستشفى السلطان قابوس', 'Ambulance', 23.6108, 58.2778, TRUE),
    ('الدفاع المدني مسقط', 'Civil Defense', 23.6140, 58.5450, TRUE)
) AS v(name, unit_type, latitude, longitude, is_available)
WHERE NOT EXISTS (SELECT 1 FROM response_units);

-- ⚠️ أكواد الموظفين الافتراضية لم تعد تُزرع تلقائيًا هنا.
-- السبب: هذا الملف بمستودع Git، وأي شخص يقرأه يعرف أن ADMIN-0000 يفتح
-- الداشبورد كاملًا على كل البلاغات — بما فيها الصور والإحداثيات الدقيقة.
-- الباك-إند يزرع الأكواد عند الإقلاع فقط إذا ضبطتِ SEED_STAFF_CODES بمتغيرات
-- البيئة (وضع التطوير)، أو أنشئيها يدويًا بأمر واحد:
--   INSERT INTO staff (access_code, label, department, is_admin)
--   VALUES ('<كود-عشوائي-طويل>', 'غرفة عمليات الشرطة', 'Police', FALSE);
-- لتوليد كود قوي:  python -c "import secrets; print(secrets.token_urlsafe(16))"


-- ============================================================
-- تتبّع خط أنابيب الوكلاء
-- ============================================================
-- pipeline_status: pending → processing → completed | failed
-- بدون هذه الأعمدة كان البلاغ الذي يفشل استدعاء n8n معه يبقى محفوظًا
-- بقاعدة البيانات لكن بلا تصنيف ولا جهة مسؤولة، ولا أحد يعرف — لا المواطن
-- (يرى "تم استلام البلاغ") ولا الموظف (لا يظهر بقائمة قسمه لأن department فارغ).
ALTER TABLE reports ADD COLUMN IF NOT EXISTS pipeline_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE reports ADD COLUMN IF NOT EXISTS pipeline_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS pipeline_last_error TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS pipeline_next_retry_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_reports_pipeline_retry
    ON reports(pipeline_status, pipeline_next_retry_at)
    WHERE pipeline_status IN ('pending', 'failed');

-- ============================================================
-- ترقيات للقواعد الموجودة مسبقًا
-- CREATE TABLE IF NOT EXISTS لا يضيف أعمدة لجدول موجود، فأي قاعدة أُنشئت
-- بنسخة سابقة تحتاج هذه الأوامر (آمنة للتكرار).
-- ============================================================
ALTER TABLE verification_codes ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0;

-- تنظيف الجلسات المنتهية عند كل إقلاع حتى لا يكبر الجدول بلا حدود
DELETE FROM user_sessions WHERE expires_at < now();
DELETE FROM staff_sessions WHERE expires_at < now();
DELETE FROM verification_codes WHERE expires_at < now() - INTERVAL '1 day';

-- ============================================================
-- ربط البلاغات المكررة + الموقع الجغرافي الحقيقي
-- ============================================================
-- parent_report_id: البلاغ الأصل الذي يمثل الحادث، ويبقى NULL للبلاغ الأصل نفسه
ALTER TABLE reports ADD COLUMN IF NOT EXISTS parent_report_id INTEGER REFERENCES reports(id);
ALTER TABLE reports ADD COLUMN IF NOT EXISTS confirmation_count INTEGER NOT NULL DEFAULT 0;

-- الموقع الإداري من Nominatim (بيانات حقيقية، لا تخمين النموذج)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS geo_wilayat TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS geo_governorate TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS geo_neighbourhood TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS geo_source TEXT;

-- نتيجة تحليل البيانات الوصفية للصور (إشارات تحقق للموظف)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS media_verification JSONB DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_reports_parent ON reports(parent_report_id);
-- فهرس يخدم بحث التكرار: الحالة + الوقت + الإحداثيات
CREATE INDEX IF NOT EXISTS idx_reports_dedup ON reports(status, created_at, latitude, longitude);
