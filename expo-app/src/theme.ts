import { Platform } from 'react-native';

export const colors = {
  ink: '#10233F',
  muted: '#718096',
  primary: '#155EEF',
  primaryDark: '#0B3A91',
  sky: '#EAF2FF',
  surface: '#FFFFFF',
  background: '#F4F7FB',
  border: '#E3EAF3',
  danger: '#E5484D',
  dangerSoft: '#FFF0F0',
  success: '#198754',
  successSoft: '#EAF8F0',
  warning: '#D97706',
  warningSoft: '#FFF7E6',
  purple: '#7357D9',
};

export const shadow = Platform.select({
  web: { boxShadow: '0 7px 16px rgba(16, 35, 63, 0.08)' },
  default: { shadowColor: '#10233F', shadowOpacity: 0.08, shadowRadius: 16, shadowOffset: { width: 0, height: 7 }, elevation: 3 },
}) ?? {};

export const incidentTypes = [
  { key: 'fire', label: 'حريق', icon: 'flame-outline', color: '#E5484D', soft: '#FFF0F0' },
  { key: 'traffic_accident', label: 'حادث سير', icon: 'car-sport-outline', color: '#D97706', soft: '#FFF7E6' },
  { key: 'weather', label: 'أمطار وأودية', icon: 'rainy-outline', color: '#155EEF', soft: '#EAF2FF' },
  { key: 'medical', label: 'حالة صحية', icon: 'medical-outline', color: '#198754', soft: '#EAF8F0' },
  { key: 'security', label: 'حالة أمنية', icon: 'shield-checkmark-outline', color: '#7357D9', soft: '#F1EEFF' },
  { key: 'other', label: 'أخرى', icon: 'ellipsis-horizontal-outline', color: '#64748B', soft: '#F1F5F9' },
] as const;

export const incidentLabel = (value?: string | null) =>
  incidentTypes.find((item) => item.key === value)?.label ?? ({
    road_block: 'عائق طريق',
    flood: 'تجمع مياه',
    crime: 'حالة أمنية',
    medical_emergency: 'حالة صحية',
  } as Record<string, string>)[value || ''] ?? value ?? 'بلاغ طارئ';

export const priorityLabel = (value?: string | null) => {
  if (value === 'none') return 'ليس بلاغاً طارئاً';
  if (value === 'critical') return 'حرجة';
  if (value === 'high') return 'عالية';
  if (value === 'medium') return 'متوسطة';
  if (value === 'low') return 'منخفضة';
  return 'قيد التحليل';
};

export const statusLabel = (value?: string | null) => {
  if (value === 'resolved' || value === 'closed') return 'تم الحل';
  if (value === 'on_scene') return 'في الموقع';
  if (value === 'dispatched' || value === 'assigned') return 'الفريق في الطريق';
  return 'تم الاستلام';
};
