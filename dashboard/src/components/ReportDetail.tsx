import type { Report } from '../types';
import { departmentLabels, priorityLabels, statusLabels, statusOrder, typeLabels } from '../labels';
import { mediaUrl } from '../api';

interface Props {
  report: Report | null;
  onUpdateStatus: (reportId: string, status: string) => Promise<void>;
  updating: boolean;
}

const isImage = (p: string) => /\.(jpg|jpeg|png|webp|heic|gif)$/i.test(p);

/** المسافة بين نقطتين (كم) — لمقارنة موقع GPS المستخرج من الصورة بالموقع الذي أدخله المُبلِّغ. */
function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export default function ReportDetail({ report, onUpdateStatus, updating }: Props) {
  if (!report) {
    return (
      <section className="report-detail report-detail--empty">
        <p>اختر بلاغًا من القائمة أو الخريطة لعرض تفاصيله</p>
      </section>
    );
  }

  return (
    <section className="report-detail">
      <h2>{typeLabels[report.confirmed_incident_type] ?? report.confirmed_incident_type}</h2>
      <p className="report-detail__id">رقم البلاغ: {report.report_id}</p>

      {report.pipeline_status === 'failed' && (
        /* تحذير صريح: الحقول أدناه (الجهة/الأولوية/الخطورة) فارغة أو افتراضية
           لأن الوكلاء لم يعالجوا البلاغ — لا لأنهم قيّموه بأنه منخفض الخطورة.
           الفرق بين الحالتين حرج بقرار طوارئ. */
        <div className="pipeline-banner">
          ⚠︎ لم يُصنَّف هذا البلاغ آليًا{report.pipeline_attempts ? ` بعد ${report.pipeline_attempts} محاولات` : ''} —
          الجهة والأولوية ودرجة الخطورة أدناه <strong>غير مُقيَّمة</strong> وتحتاج مراجعة بشرية.
          {report.pipeline_last_error && (
            <div style={{ marginTop: 6, fontSize: 12, opacity: 0.85 }}>{report.pipeline_last_error}</div>
          )}
        </div>
      )}

      {(report.confirmation_count ?? 0) > 0 && report.credibility && (
        /* تعدد المصادر المستقلة أقوى دليل مصداقية متاح: بلاغ منفرد قد يكون
           كاذبًا، لكن عدة بلاغات من أجهزة مختلفة عن نفس الموقع خلال دقائق
           يصعب تزويرها. نعرضها بارزة لأنها تغيّر قرار الموظف فعليًا. */
        <div className="credibility-banner">
          <strong>✓ {report.credibility.label}</strong>
          <span>{report.credibility.note}</span>
        </div>
      )}

      <div className="report-detail__grid">
        <div>
          <span>الجهة المسؤولة</span>
          <strong>{departmentLabels[report.department] ?? report.department}</strong>
        </div>
        <div>
          <span>الأولوية</span>
          <strong>{priorityLabels[report.priority] ?? report.priority}</strong>
        </div>
        <div>
          <span>درجة الخطورة</span>
          <strong>{Math.round(report.risk_score ?? 0)}%</strong>
        </div>
        <div>
          <span>الموقع</span>
          <strong>{report.location_text || '—'}</strong>
        </div>
        {(report.geo_wilayat || report.geo_neighbourhood) && (
          <div>
            <span>الموقع الإداري</span>
            <strong>
              {[report.geo_neighbourhood, report.geo_wilayat, report.geo_governorate]
                .filter(Boolean)
                .join('، ')}
            </strong>
          </div>
        )}
      </div>

      {report.description && (
        <div className="report-detail__section">
          <h3>الوصف</h3>
          <p>{report.description}</p>
        </div>
      )}

      {report.voice_note_path && (
        <div className="report-detail__section">
          <h3>ملاحظة صوتية</h3>
          <audio controls src={mediaUrl(report.voice_note_path)} />
        </div>
      )}

      {report.media_paths.length > 0 && (
        <div className="report-detail__section">
          <h3>الوسائط المرفقة</h3>
          <div className="report-detail__media">
            {report.media_paths.map((p) =>
              isImage(p) ? (
                <img key={p} src={mediaUrl(p)} alt="مرفق البلاغ" />
              ) : (
                <video key={p} src={mediaUrl(p)} controls />
              )
            )}
          </div>
        </div>
      )}

      {report.media_verification && report.media_verification.length > 0 && (
        <div className="report-detail__section">
          <h4>فحص صحة الصور</h4>
          {report.media_verification.map((check, i) => (
            <div key={check.path ?? i} className="verification-card">
              <div className="verification-card__score">
                درجة الاتساق: <strong>{check.consistency_score}%</strong>
              </div>
              {check.flags.map((flag, j) => (
                <div key={j} className={`verification-flag verification-flag--${flag.level}`}>
                  {flag.level === 'ok' ? '✓' : flag.level === 'warning' ? '⚠︎' : 'ℹ'} {flag.message}
                </div>
              ))}
            </div>
          ))}
        </div>
      )}

      {report.media_exif && report.media_exif.length > 0 && (
        <div className="report-detail__section">
          <h3>تفاصيل الصور (للتحقق الداخلي)</h3>
          {report.media_exif.map((exif) => {
            const hasGps = exif.gps_latitude != null && exif.gps_longitude != null;
            return (
              <div key={exif.path} className="report-detail__exif">
                <div className="report-detail__exif-row">
                  <span>تاريخ/وقت الالتقاط</span>
                  <strong>{exif.captured_at ?? 'غير متوفر بالصورة'}</strong>
                </div>
                <div className="report-detail__exif-row">
                  <span>الجهاز</span>
                  <strong>{exif.device ?? 'غير متوفر'}</strong>
                </div>
                <div className="report-detail__exif-row">
                  <span>موقع GPS المُلتقط بالصورة</span>
                  {hasGps ? (
                    <a
                      href={`https://www.google.com/maps?q=${exif.gps_latitude},${exif.gps_longitude}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {exif.gps_latitude!.toFixed(5)}, {exif.gps_longitude!.toFixed(5)} (افتح بالخريطة)
                    </a>
                  ) : (
                    <strong>غير متوفر بالصورة</strong>
                  )}
                </div>
                {hasGps && report.latitude != null && report.longitude != null && (
                  <div className="report-detail__exif-row report-detail__exif-warning">
                    <span>الفرق عن الموقع المُبلَّغ به</span>
                    <strong>
                      {haversineKm(report.latitude, report.longitude, exif.gps_latitude!, exif.gps_longitude!).toFixed(2)} كم
                    </strong>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {(report.image_ai_generated_suspected != null || report.image_is_plausible != null) && (
        <div className="report-detail__section">
          <h3>تقييم صحة الصورة (بالذكاء الاصطناعي — احتمالي وليس قاطعًا)</h3>
          <div className={`report-detail__exif ${report.image_ai_generated_suspected ? 'report-detail__exif--alert' : ''}`}>
            <div className="report-detail__exif-row">
              <span>صورة حقيقية من موقع الحادث؟</span>
              <strong>{report.image_is_plausible === false ? '⚠️ مشكوك بها' : report.image_is_plausible === true ? '✅ يبدو نعم' : 'غير محدد'}</strong>
            </div>
            {report.image_authenticity_reason && (
              <div className="report-detail__exif-row">
                <span>السبب</span>
                <strong>{report.image_authenticity_reason}</strong>
              </div>
            )}
            <div className="report-detail__exif-row">
              <span>يُحتمل توليدها بالذكاء الاصطناعي؟</span>
              <strong>{report.image_ai_generated_suspected ? '⚠️ نعم، يوجد مؤشرات' : 'لا'}</strong>
            </div>
            {report.image_ai_generated_reason && (
              <div className="report-detail__exif-row">
                <span>المؤشرات</span>
                <strong>{report.image_ai_generated_reason}</strong>
              </div>
            )}
          </div>
        </div>
      )}

      <div className="report-detail__section">
        <h3>تحديث الحالة</h3>
        <div className="report-detail__status-actions">
          {statusOrder.map((s) => (
            <button
              key={s}
              disabled={updating || report.status === s}
              className={`status-btn${report.status === s ? ' status-btn--active' : ''}`}
              onClick={() => onUpdateStatus(report.report_id, s)}
            >
              {statusLabels[s]}
            </button>
          ))}
        </div>
      </div>
    </section>
  );
}
