/// ترجمة قيم الحالة/الجهة/النوع القادمة من الباك-إند — يقابل lib/core/labels.dart في تطبيق Flutter.
export const departmentLabels: Record<string, string> = {
  Police: 'شرطة عُمان السلطانية',
  Ambulance: 'هيئة الإسعاف',
  'Civil Defense': 'الدفاع المدني',
  'Multiple Agencies': 'عدة جهات مختصة',
  'Manual Review': 'قيد المراجعة اليدوية',
};

export const statusLabels: Record<string, string> = {
  received: 'تم الاستلام',
  dispatched: 'قيد المعالجة',
  en_route: 'في الطريق',
  resolved: 'تم الحل',
};

export const statusOrder = ['received', 'dispatched', 'en_route', 'resolved'];

export const priorityLabels: Record<string, string> = {
  critical: 'حرجة',
  high: 'عالية',
  medium: 'متوسطة',
  low: 'منخفضة',
};

export const typeLabels: Record<string, string> = {
  fire: 'حريق',
  traffic_accident: 'حادث سير',
  flood: 'أمطار وأودية',
  weather: 'أمطار وأودية',
  medical: 'حالة صحية طارئة',
  road_block: 'إغلاق طريق',
  security: 'بلاغ أمني',
  other: 'أخرى',
};

export function priorityColor(priority: string): string {
  switch (priority) {
    case 'critical':
      return '#B42318';
    case 'high':
      return '#E8433D';
    case 'medium':
      return '#FFB86B';
    case 'low':
      return '#4CD07D';
    default:
      return '#3E8CF7';
  }
}
