import 'package:flutter_tts/flutter_tts.dart';

/// خدمة تحويل النص إلى كلام — تُستخدم في شاشات المساعد الذكي عشان تسهّل
/// الاستخدام على كبار السن والأطفال (ينطق الروبوت رسائله بدل ما يعتمدون
/// على القراءة فقط). تدعم النطق بالعربية أو الإنجليزية.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _muted = false;
  String _currentLanguage = 'ar-SA';

  bool get isMuted => _muted;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _tts.setLanguage(_currentLanguage);
    // سرعة أبطأ قليلاً من الافتراضي عشان يكون النطق أوضح لكبار السن والأطفال
    await _tts.setSpeechRate(0.42);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _initialized = true;
  }

  /// ينطق نصًا. يوقف أي نطق سابق قبل البدء بالجديد حتى لا تتداخل الأصوات.
  /// مرّر [language] بصيغة locale (مثل 'ar-SA' أو 'en-US') لنطق نص معيّن
  /// بلغة مختلفة عن اللغة الافتراضية الحالية لمرة واحدة فقط دون تغييرها.
  Future<void> speak(String text, {String? language}) async {
    if (_muted || text.trim().isEmpty) return;
    await _ensureInit();
    await _tts.setLanguage(language ?? _currentLanguage);
    await _tts.stop();
    await _tts.speak(text);
    if (language != null && language != _currentLanguage) {
      // نرجّع اللغة الافتراضية بعد النطق لمرة واحدة عشان ما تتأثر بقية
      // الرسائل اللي تُنطق باللغة المعتادة
      await _tts.setLanguage(_currentLanguage);
    }
  }

  /// يغيّر اللغة الافتراضية المستخدمة في كل نداءات speak() القادمة (بدون
  /// تمرير language صراحة). 'ar' أو 'en' كافي، تُحوَّل تلقائيًا لصيغة locale.
  Future<void> setDefaultLanguage(String languageCode) async {
    _currentLanguage = languageCode == 'en' ? 'en-US' : 'ar-SA';
    if (_initialized) {
      await _tts.setLanguage(_currentLanguage);
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  /// يبدّل بين تفعيل/كتم الصوت، ويوقف أي نطق جارٍ فور الكتم.
  Future<bool> toggleMute() async {
    _muted = !_muted;
    if (_muted) await _tts.stop();
    return _muted;
  }
}

