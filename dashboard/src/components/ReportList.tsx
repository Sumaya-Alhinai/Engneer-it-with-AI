import type { Report } from '../types';
import { departmentLabels, priorityColor, statusLabels, typeLabels } from '../labels';

export interface Filters {
  status: string;
  department: string;
}

interface Props {
  reports: Report[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  filters: Filters;
  onFiltersChange: (f: Filters) => void;
  /// يظهر فلتر "الجهة" فقط لمن يشوف كل الجهات (الإدارة العامة) — لموظف جهة
  /// واحدة، النتائج مقصورة على جهته أصلاً من الخادم فلا داعي لفلتر إضافي.
  showDepartmentFilter?: boolean;
}

export default function ReportList({
  reports,
  selectedId,
  onSelect,
  filters,
  onFiltersChange,
  showDepartmentFilter = true,
}: Props) {
  const filtered = reports.filter(
    (r) =>
      (filters.status === 'all' || r.status === filters.status) &&
      (filters.department === 'all' || r.department === filters.department)
  );

  return (
    <aside className="report-list">
      <div className="report-list__filters">
        <select value={filters.status} onChange={(e) => onFiltersChange({ ...filters, status: e.target.value })}>
          <option value="all">كل الحالات</option>
          {Object.entries(statusLabels).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </select>
        {showDepartmentFilter && (
          <select value={filters.department} onChange={(e) => onFiltersChange({ ...filters, department: e.target.value })}>
            <option value="all">كل الجهات</option>
            {Object.entries(departmentLabels).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        )}
      </div>

      <div className="report-list__items">
        {filtered.length === 0 && <p className="empty-hint">لا توجد بلاغات مطابقة</p>}
        {filtered.map((r) => (
          <button
            key={r.report_id}
            className={`report-item${r.report_id === selectedId ? ' report-item--active' : ''}`}
            onClick={() => onSelect(r.report_id)}
          >
            <span className="report-item__dot" style={{ background: priorityColor(r.priority) }} />
            <span className="report-item__body">
              <span className="report-item__title">{typeLabels[r.confirmed_incident_type] ?? r.confirmed_incident_type}</span>
              <span className="report-item__meta">{r.location_text || '—'}</span>
            </span>
            {(r.confirmation_count ?? 0) > 0 && (
              <span className="report-item__confirm" title={`${r.confirmation_count} بلاغات مستقلة عن نفس الحادث`}>
                ✓{r.confirmation_count! + 1}
              </span>
            )}
            {r.pipeline_status === 'failed' && (
              /* بلاغ لم يُصنّفه الذكاء الاصطناعي — بدون هذه الشارة يبدو
                 للموظف بلاغًا عاديًا منخفض الأولوية بينما هو غير مُقيَّم أصلًا */
              <span className="report-item__warn" title="لم يُصنَّف آليًا — يحتاج مراجعة يدوية">⚠︎</span>
            )}
            <span className="report-item__status">{statusLabels[r.status] ?? r.status}</span>
          </button>
        ))}
      </div>
    </aside>
  );
}
