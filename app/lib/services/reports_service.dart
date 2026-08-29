import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image_picker/image_picker.dart' show XFile;
import '../core/api_config.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// يحدّد Content-Type الحقيقي للملف عشان الخادم ما يشوفه
/// application/octet-stream (القيمة الافتراضية بمكتبة http عند عدم تحديد
/// contentType) ويرفضه بخطأ "نوع ملف غير مدعوم" حتى لو كان صورة فعلية.
/// XFile.mimeType يكون null غالبًا على الويب، فنعتمد على الامتداد كخيار احتياطي.
MediaType? _resolveContentType(XFile file) {
  final raw = (file.mimeType ?? _mimeFromExtension(file.name))?.toLowerCase();
  if (raw == null) return null;
  final parts = raw.split('/');
  if (parts.length != 2) return null;
  return MediaType(parts[0], parts[1]);
}

String? _mimeFromExtension(String filename) {
  final ext = filename.toLowerCase().split('.').last;
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'wav':
      return 'audio/wav';
    case 'webm':
      return 'audio/webm';
    case 'ogg':
      return 'audio/ogg';
    default:
      return null;
  }
}

class ReportResult {
  final String reportId;
  final String department;
  final String priority;

  ReportResult({required this.reportId, required this.department, required this.priority});
}

/// يرسل البلاغ كنص ومرفقات إلى mobile-api؛ بعد الحفظ يشغّل Supabase
/// Edge Function المسماة report-agent تحليل Aman AI في الخلفية.
class ReportsService {
  ReportsService._();

  /// يتغيّر كلما نجح إرسال بلاغ جديد — تستمع له الشاشات (مثل الرئيسية) التي
  /// يُبقيها IndexedStack حيّة في الذاكرة ولا تُعاد بناؤها تلقائيًا عند العودة إليها.
  static final ValueNotifier<int> refreshTick = ValueNotifier(0);

  static Future<ReportResult> submitReport({
    required String type,
    required String description,
    double? latitude,
    double? longitude,
    String locationText = '',
    List<XFile> media = const [],
    XFile? voiceNote,
  }) async {
    final token = AuthService.instance.token;

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/reports');
    final request = http.MultipartRequest('POST', uri);
    // الهوية تُؤخذ من التوكن بالخادم. حقل user_id ما عاد يُرسل إطلاقًا:
    // كان الخادم يثق فيه كما هو، أي أن أي شخص يقدر يبلّغ باسم مستخدم آخر.
    // الإبلاغ بدون توكن يبقى مسموحًا (حالة طوارئ) ويُسجَّل كضيف يولّده الخادم.
    if (token != null) request.headers['x-user-token'] = token;
    request.fields['type'] = type;
    request
      ..fields['description'] = description
      ..fields['location_text'] = locationText;
    if (latitude != null) request.fields['latitude'] = latitude.toString();
    if (longitude != null) request.fields['longitude'] = longitude.toString();

    // نستخدم fromBytes بدل fromPath عشان يشتغل على الويب أيضًا — dart:io
    // MultipartFile.fromPath يحتاج نظام ملفات حقيقي غير متوفر بالمتصفح،
    // وهذا هو سبب خطأ "MultipartFile is only supported where dart:io is
    // available" اللي يظهر عند الإرسال من Chrome.
    for (final file in media) {
      final bytes = await file.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'media',
        bytes,
        filename: file.name,
        contentType: _resolveContentType(file),
      ));
    }
    if (voiceNote != null) {
      final bytes = await voiceNote.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'voice_note',
        bytes,
        filename: voiceNote.name,
        contentType: _resolveContentType(voiceNote),
      ));
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(body['message']?.toString() ?? 'تعذّر إرسال البلاغ، حاول مرة أخرى');
    }
    refreshTick.value++;
    return ReportResult(
      reportId: body['report_id'] as String,
      department: (body['department'] ?? '') as String,
      priority: (body['priority'] ?? '') as String,
    );
  }

  static Future<List<Map<String, dynamic>>> myReports() async {
    if (AuthService.instance.token == null) return [];
    // بدون ?user_id= — الخادم يحدد صاحب البلاغات من التوكن
    final list = await ApiClient.getJsonList('/api/reports');
    return list.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> getReport(String reportId) {
    return ApiClient.getJson('/api/reports/$reportId');
  }

  /// خلاصة الحوادث العامة — تُستخدم بشاشة التنبيهات لعرض حوادث وأمطار
  /// بأماكن ثانية وتقدير حالة الطرق.
  ///
  /// صارت تقرأ من /api/reports/public: نوع الحادث وأولويته وحالته وموقع
  /// تقريبي فقط. المسار القديم كان يرجع نص كل بلاغ ومعرّف صاحبه وإحداثياته
  /// الدقيقة لأي شخص — نص البلاغ قد يحمل أسماء ومعلومات صحية، والإحداثيات
  /// الدقيقة تكشف بيت المبلّغ.
  static Future<List<Map<String, dynamic>>> allReports() async {
    final list = await ApiClient.getJsonList('/api/reports/public');
    return list.cast<Map<String, dynamic>>();
  }
}
