import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api_config.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// غلاف بسيط فوق http.Client للتعامل مع باك-إند Aman AI المحلي.
class ApiClient {
  ApiClient._();

  static Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  /// ترويسة الجلسة. مسارات قراءة البلاغات صارت تتطلب x-user-token — الباك-إند
  /// يستخرج هوية صاحب البلاغات من التوكن ولا يقبلها كمعامل بالرابط.
  static Map<String, String> _headers({bool json = false}) {
    final token = AuthService.instance.token;
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'x-user-token': token,
    };
  }

  static Future<Map<String, dynamic>> getJson(String path) async {
    final res = await http.get(_uri(path), headers: _headers());
    return _decodeMap(res);
  }

  static Future<List<dynamic>> getJsonList(String path) async {
    final res = await http.get(_uri(path), headers: _headers());
    return _decodeAny(res) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body) async {
    final res = await http.patch(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decodeMap(res);
  }

  static Map<String, dynamic> _decodeMap(http.Response res) => _decodeAny(res) as Map<String, dynamic>;

  static dynamic _decodeAny(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    final body = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    if (res.statusCode >= 400) {
      final message = (body is Map && body['message'] != null) ? body['message'].toString() : 'حدث خطأ غير متوقع، حاول مرة أخرى';
      throw ApiException(message);
    }
    return body;
  }
}
