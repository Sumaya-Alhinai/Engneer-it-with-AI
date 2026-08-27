import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// عنوان الباك-إند المحلي لـ Aman AI.
class ApiConfig {
  ApiConfig._();

  /// عدّل هذا الرابط يدويًا عند التشغيل على جهاز فعلي متصل بنفس شبكة الواي-فاي:
  /// استبدله بعنوان IP لجهاز الكمبيوتر الذي يشغّل الباك-إند، مثل: 'http://192.168.1.5:4000'
  static String? overrideBaseUrl;

  /// يُضبط وقت البناء عبر: flutter build web --dart-define=API_BASE_URL=https://...
  /// مفيد عند نشر التطبيق/مشاركته عبر رابط عام (نفق) والباك-إند على نطاق مختلف.
  static const String _defineBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (overrideBaseUrl != null) return overrideBaseUrl!;
    if (_defineBaseUrl.isNotEmpty) return _defineBaseUrl;
    if (kIsWeb) return 'http://localhost:4000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:4000'; // محاكي أندرويد
    } catch (_) {
      // Platform غير مدعوم (مثل بعض بيئات الاختبار) — استخدم الافتراضي أدناه
    }
    return 'http://localhost:4000'; // iOS Simulator / سطح المكتب
  }
}
