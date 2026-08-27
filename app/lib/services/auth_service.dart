import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_config.dart';

/// يُرمى من [AuthService.login] عندما يكون الحساب موجودًا وكلمة المرور صحيحة
/// لكن الحساب لم يُفعَّل بعد — تلتقطه شاشة الدخول لتوجيه المستخدم لشاشة
/// إدخال رمز التحقق بدل عرض رسالة خطأ عامة. يحمل البريد أو الهاتف (أيهما
/// استُخدم للتسجيل) عشان شاشة التحقق تعرف ترسل الرمز لأي قناة.
class EmailNotVerifiedException implements Exception {
  final String? email;
  final String? phone;
  EmailNotVerifiedException({this.email, this.phone});
}

/// تسجيل دخول/حساب عبر البريد الإلكتروني **أو** رقم الهاتف مع كلمة المرور،
/// مرتبط بالباك-إند (جدول users). الحساب يتطلب تفعيل بكود يُرسل مرة واحدة
/// عند إنشاء الحساب (للبريد: إيميل حقيقي أو مطبوع بالطرفية بوضع تجريبي، وللهاتف:
/// SMS تجريبي مطبوع بالطرفية لحين ربط مزود حقيقي). الجلسة تُحفظ محليًا على
/// الجهاز بعد نجاح التفعيل/الدخول.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kUserId = 'auth_user_id';
  static const _kToken = 'auth_token';
  static const _kName = 'auth_name';
  static const _kEmail = 'auth_email';
  static const _kPhone = 'auth_phone';
  static const _kLoggedIn = 'auth_logged_in';
  static const _kIsGuest = 'auth_is_guest';
  static const _kLanguage = 'auth_language';
  static const _kLocationGranted = 'auth_location_granted';
  static const _kMicGranted = 'auth_mic_granted';
  static const _kNotificationsEnabled = 'auth_notifications_enabled';
  static const _kSetupDone = 'auth_setup_done';

  String? _userId;
  /// توكن الجلسة من الباك-إند — يُرسل بترويسة x-user-token مع كل طلب.
  /// بدونه ترفض مسارات قراءة البلاغات الطلب بـ 401.
  String? _token;
  String? _name;
  String? _email;
  String? _phone;
  bool _isGuest = false;
  String _language = 'ar';

  String? get userId => _userId;
  String? get token => _token;
  String? get name => _name;
  String? get email => _email;
  String? get phone => _phone;
  bool get isGuest => _isGuest;
  bool get isLoggedIn => _userId != null;
  /// اللغة المفضّلة اللي اختارها المستخدم بشاشة إعداد الحساب ('ar' أو 'en').
  String get language => _language;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString(_kLanguage) ?? 'ar';
    if (prefs.getBool(_kLoggedIn) == true) {
      _userId = prefs.getString(_kUserId);
      _token = prefs.getString(_kToken);
      _name = prefs.getString(_kName);
      _email = prefs.getString(_kEmail);
      _phone = prefs.getString(_kPhone);
      _isGuest = prefs.getBool(_kIsGuest) ?? false;
    }
  }

  /// يدخل المستخدم كضيف بدون حساب — يقدر يبلّغ فقط، بدون متابعة بلاغاته
  /// لاحقًا من جهاز آخر. يُنشأ معرّف محلي فريد ويُحفظ على الجهاز.
  /// يدخل المستخدم كضيف بدون حساب — يقدر يبلّغ فقط، بدون متابعة بلاغاته
  /// لاحقًا من جهاز آخر.
  ///
  /// المعرّف صار يجي من الخادم مع توكن جلسة، بدل ما يولّده التطبيق محليًا:
  /// المعرّف المحلي كان مجرد نص يُرسل بحقل، أي شخص يقدر يكتب مكانه معرّف
  /// مستخدم مسجّل (USR-1234) وينتحله ويقرأ بلاغاته.
  Future<void> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http.post(Uri.parse('${ApiConfig.baseUrl}/api/auth/guest'));
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(body['message']?.toString() ?? 'تعذّر الدخول كضيف');
    }
    _userId = body['user_id'] as String;
    _token = body['token'] as String;
    _name = 'ضيف';
    _email = null;
    _phone = null;
    _isGuest = true;
    await prefs.setString(_kUserId, _userId!);
    await prefs.setString(_kToken, _token!);
    await prefs.setString(_kName, _name!);
    await prefs.setString(_kEmail, '');
    await prefs.setString(_kPhone, '');
    await prefs.setBool(_kIsGuest, true);
    await prefs.setBool(_kLoggedIn, true);
  }

  /// هل أنهى المستخدم شاشة إعداد الحساب (لغة/صلاحيات) قبل؟ تُعرض مرة وحدة.
  Future<bool> isSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSetupDone) ?? false;
  }

  Future<void> markSetupDone({
    required String language,
    required bool locationGranted,
    required bool micGranted,
    required bool notificationsEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSetupDone, true);
    await prefs.setString(_kLanguage, language);
    await prefs.setBool(_kLocationGranted, locationGranted);
    await prefs.setBool(_kMicGranted, micGranted);
    await prefs.setBool(_kNotificationsEnabled, notificationsEnabled);
    _language = language;
  }

  /// يغيّر اللغة المفضّلة لاحقًا (مثلًا من إعدادات الحساب) بدون المرور
  /// بشاشة الإعداد الكاملة من جديد.
  Future<void> setLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, language);
    _language = language;
  }

  /// ينشئ الحساب ويرسل رمز تحقق للبريد أو الهاتف (حسب المُرسَل) — لا يسجّل
  /// الدخول بعد؛ استخدم [verifyEmail] بعد إدخال المستخدم الرمز لإكمال الدخول.
  /// مرّر إما [email] أو [phone] (وليس الاثنين فارغَين معًا).
  Future<void> register({
    required String name,
    String? email,
    String? phone,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'password': password,
      }),
    );
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(body['message']?.toString() ?? 'تعذّر إنشاء الحساب');
    }
  }

  Future<void> verifyEmail({String? email, String? phone, required String code}) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-email'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'code': code,
      }),
    );
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(body['message']?.toString() ?? 'تعذّر التحقق من الرمز');
    }
    await _saveSession(
      userId: body['user_id'] as String,
      token: body['token'] as String,
      name: (body['name'] ?? '') as String,
      email: body['email'] as String?,
      phone: body['phone'] as String?,
    );
  }

  Future<void> resendCode({String? email, String? phone}) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/resend-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      }),
    );
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(body['message']?.toString() ?? 'تعذّر إعادة إرسال الرمز');
    }
  }

  /// يرمي [EmailNotVerifiedException] إذا كان الحساب صحيحًا لكن غير مفعّل بعد.
  /// مرّر إما [email] أو [phone].
  Future<void> login({String? email, String? phone, required String password}) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'password': password,
      }),
    );
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode == 403 && body['code'] == 'EMAIL_NOT_VERIFIED') {
      throw EmailNotVerifiedException(
        email: (body['email'] as String?) ?? email,
        phone: (body['phone'] as String?) ?? phone,
      );
    }
    if (response.statusCode >= 400) {
      throw Exception(body['message']?.toString() ?? 'تعذّر تسجيل الدخول');
    }
    await _saveSession(
      userId: body['user_id'] as String,
      token: body['token'] as String,
      name: (body['name'] ?? '') as String,
      email: body['email'] as String?,
      phone: body['phone'] as String?,
    );
  }

  Future<void> _saveSession({
    required String userId,
    required String token,
    required String name,
    String? email,
    String? phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _userId = userId;
    _token = token;
    await prefs.setString(_kToken, token);
    _name = name;
    _email = (email != null && email.isNotEmpty) ? email : null;
    _phone = (phone != null && phone.isNotEmpty) ? phone : null;
    _isGuest = false;
    await prefs.setString(_kUserId, userId);
    await prefs.setString(_kName, name);
    await prefs.setString(_kEmail, _email ?? '');
    await prefs.setString(_kPhone, _phone ?? '');
    await prefs.setBool(_kIsGuest, false);
    await prefs.setBool(_kLoggedIn, true);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // نُبطل الجلسة بالخادم أيضًا، وإلا يبقى التوكن صالحًا 30 يومًا بعد الخروج
    if (_token != null) {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/logout'),
        headers: {'x-user-token': _token!},
      ).catchError((_) => http.Response('', 200));
    }
    await prefs.setBool(_kLoggedIn, false);
    await prefs.remove(_kToken);
    _token = null;
    _userId = null;
    _name = null;
    _email = null;
    _phone = null;
    _isGuest = false;
  }
}
