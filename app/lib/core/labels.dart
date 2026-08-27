/// ترجمة قيم الحالة/الجهة القادمة من الباك-إند إلى نصوص عربية لعرضها بالواجهة.
class Labels {
  Labels._();

  static const Map<String, String> department = {
    'Police': 'شرطة عُمان السلطانية',
    'Ambulance': 'هيئة الإسعاف',
    'Civil Defense': 'الدفاع المدني',
    'Multiple Agencies': 'عدة جهات مختصة',
    'Manual Review': 'قيد المراجعة اليدوية',
  };

  static const Map<String, String> status = {
    'received': 'تم الاستلام',
    'dispatched': 'قيد المعالجة',
    'en_route': 'في الطريق',
    'resolved': 'تم الحل',
  };

  /// ترتيب الحالات لعرضها كخط زمني (Timeline)
  static const List<String> statusOrder = ['received', 'dispatched', 'en_route', 'resolved'];

  static int statusStepIndex(String status) {
    final i = statusOrder.indexOf(status);
    return i < 0 ? 0 : i;
  }

  static const Map<String, String> priority = {
    'high': 'أولوية عالية',
    'medium': 'أولوية متوسطة',
    'low': 'أولوية منخفضة',
  };

  static String departmentLabel(String? value) => department[value] ?? (value ?? '');
  static String statusLabel(String? value) => status[value] ?? (value ?? '');
  static String priorityLabel(String? value) => priority[value] ?? (value ?? '');
}
