import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/reports_service.dart';
import '../services/tts_service.dart';
import 'case_tracking_screen.dart';
import 'map_location_picker_screen.dart';

enum _Step { intro, listening, confirmType, askInjuries, askLocation, askPhoto, review, sending, done }

class _TypeInfo {
  final String apiType;
  final String label;
  final String labelEn;
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _TypeInfo(this.apiType, this.label, this.labelEn, this.icon, this.color, this.bgColor);
}

const List<_TypeInfo> _types = [
  _TypeInfo('fire', 'حريق', 'Fire', Icons.local_fire_department_rounded, AppColors.fireBlue, AppColors.fireBlueBg),
  _TypeInfo('traffic_accident', 'حادث سير', 'Traffic accident', Icons.car_crash_rounded, AppColors.accidentRed, AppColors.accidentRedBg),
  _TypeInfo('weather', 'أمطار وفيضانات', 'Rain / flooding', Icons.water_drop_rounded, AppColors.weatherOrange, AppColors.weatherOrangeBg),
  _TypeInfo('medical', 'حالة صحية طارئة', 'Medical emergency', Icons.medical_services_rounded, AppColors.healthGreen, AppColors.healthGreenBg),
  _TypeInfo('other', 'خطر آخر', 'Other emergency', Icons.warning_rounded, AppColors.primaryBlue, AppColors.lightBlueBg),
];

/// شاشة "المساعد الذكي" الصوتية — تنفّذ مسار الإبلاغ الكامل بحوار طبيعي:
/// استماع → فهم نوع الحادث → سؤال عن المصابين → الموقع → صورة (اختياري) →
/// مراجعة → إرسال. كل خطوة فيها بديل باللمس أو الكتابة أيضًا (إمكانية
/// الوصول)، مو الصوت وحده.
class VoiceReportScreen extends StatefulWidget {
  const VoiceReportScreen({super.key});

  @override
  State<VoiceReportScreen> createState() => _VoiceReportScreenState();
}

class _VoiceReportScreenState extends State<VoiceReportScreen> {
  _Step _step = _Step.intro;
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _textController = TextEditingController();

  bool _isListening = false;
  String _liveTranscript = '';
  String _description = '';
  _TypeInfo? _selectedType;
  bool? _hasInjuries;
  PickedLocation? _location;
  bool _locating = false;
  final List<XFile> _media = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _submitting = false;
  String? _reportId;
  String? _department;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TtsService.instance.speak('أهلًا، أخبرني ماذا حدث؟');
    });
  }

  @override
  void dispose() {
    if (_isListening) _speech.stop();
    TtsService.instance.stop();
    _textController.dispose();
    super.dispose();
  }

  // ------------------------- التعرّف على الكلام -------------------------

  Future<void> _startListening() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted && _isListening) {
          _stopListening();
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التعرف على الصوت غير متاح — تقدر تكتب بدل ما تتكلم')),
      );
      return;
    }
    setState(() {
      _step = _Step.listening;
      _isListening = true;
      _liveTranscript = '';
    });
    await _speech.listen(
      localeId: 'ar-SA',
      onResult: (result) {
        setState(() => _liveTranscript = result.recognizedWords);
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() => _isListening = false);
    if (_liveTranscript.trim().isNotEmpty) {
      _processUtterance(_liveTranscript.trim());
    } else {
      setState(() => _step = _Step.intro);
    }
  }

  void _submitTyped() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _processUtterance(text);
  }

  /// يفهم كلام المستخدم: يحدد نوع الحادث ويكتشف إذا ذكر إصابات، ثم ينتقل
  /// للخطوة المناسبة ويردّ بصوت الروبوت.
  void _processUtterance(String text) {
    setState(() => _description = _description.isEmpty ? text : '$_description. $text');

    final type = _detectType(text);
    final injuryMentioned = _detectInjuryKeyword(text);

    setState(() => _selectedType = type);

    if (type == null) {
      TtsService.instance.speak('لم أفهم نوع الحادث بالضبط، من فضلك اختر النوع من الخيارات.');
      setState(() => _step = _Step.confirmType);
      return;
    }

    if (injuryMentioned) {
      setState(() => _hasInjuries = true);
      TtsService.instance.speak('فهمت أن لديك ${type.label}، وذكرت وجود إصابة. هل أنت الآن بموقع الحادث؟ اضغط "استخدام موقعي الحالي" أو حدد الموقع يدويًا.');
      setState(() => _step = _Step.askLocation);
      return;
    }

    if (type.apiType == 'traffic_accident' || type.apiType == 'medical') {
      TtsService.instance.speak('فهمت أن لديك ${type.label}. هل يوجد مصابون؟');
      setState(() => _step = _Step.askInjuries);
      return;
    }

    TtsService.instance.speak('فهمت أن لديك ${type.label}. هل تسمح لي باستخدام موقعك الحالي؟');
    setState(() => _step = _Step.askLocation);
  }

  _TypeInfo? _detectType(String text) {
    final t = text;
    if (t.contains('حريق') || t.contains('نار') || t.contains('حرق')) return _types[0];
    if (t.contains('حادث') || t.contains('سياره') || t.contains('سيارة') || t.contains('تصادم')) return _types[1];
    if (t.contains('مطر') || t.contains('واد') || t.contains('سيل') || t.contains('فيضان')) return _types[2];
    if (t.contains('مريض') || t.contains('صحي') || t.contains('اسعاف') || t.contains('إسعاف') || t.contains('قلب') || t.contains('تنفس')) {
      return _types[3];
    }
    return null;
  }

  bool _detectInjuryKeyword(String text) {
    return text.contains('مصاب') || text.contains('إصاب') || text.contains('جرح') || text.contains('دم');
  }

  void _selectType(_TypeInfo type) {
    setState(() => _selectedType = type);
    if (type.apiType == 'traffic_accident' || type.apiType == 'medical') {
      TtsService.instance.speak('تمام، ${type.label}. هل يوجد مصابون؟');
      setState(() => _step = _Step.askInjuries);
    } else {
      TtsService.instance.speak('تمام، ${type.label}. هل تسمح لي باستخدام موقعك الحالي؟');
      setState(() => _step = _Step.askLocation);
    }
  }

  void _answerInjuries(bool yes) {
    setState(() => _hasInjuries = yes);
    TtsService.instance.speak('حسنًا. هل تسمح لي باستخدام موقعك الحالي؟');
    setState(() => _step = _Step.askLocation);
  }

  // ------------------------------ الموقع ------------------------------

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('صلاحية الموقع مرفوضة — حدد الموقع يدويًا من الخريطة')),
          );
        }
        return;
      }
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      );
      final address = await _reverseGeocode(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _location = PickedLocation(latitude: position.latitude, longitude: position.longitude, address: address);
      });
      TtsService.instance.speak('تم تحديد موقعك. هل تقدر ترفق صورة؟ تقدر تقول تخطي.');
      setState(() => _step = _Step.askPhoto);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديد الموقع تلقائيًا — جرّب تحديده يدويًا')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<String> _reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'format': 'jsonv2',
        'accept-language': 'ar',
      });
      final res = await http.get(uri, headers: {'User-Agent': 'AmanAI-CitizenApp/1.0'});
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final name = body['display_name']?.toString();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {
      // نتجاهل فشل الجلب العكسي ونستخدم الإحداثيات كنص بديل
    }
    return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  Future<void> _pickLocationManually() async {
    final result = await Navigator.of(context).push<PickedLocation>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.001),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const MapLocationPickerScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
    if (result != null && mounted) {
      setState(() => _location = result);
      TtsService.instance.speak('تم تحديد موقعك. هل تقدر ترفق صورة؟ تقدر تقول تخطي.');
      setState(() => _step = _Step.askPhoto);
    }
  }

  // ------------------------------ الصور ------------------------------

  Future<void> _pickPhoto(ImageSource source) async {
    final XFile? file = await _imagePicker.pickImage(source: source, imageQuality: 80);
    if (file != null && mounted) {
      setState(() => _media.add(file));
    }
    _goToReview();
  }

  void _skipPhoto() => _goToReview();

  void _goToReview() {
    TtsService.instance.speak(_summaryText());
    setState(() => _step = _Step.review);
  }

  String _summaryText() {
    final type = _selectedType?.label ?? 'غير محدد';
    final injuries = _hasInjuries == true ? 'يوجد مصابون' : (_hasInjuries == false ? 'لا يوجد مصابون' : 'غير محدد');
    final loc = _location?.address ?? 'غير محدد';
    final desc = _description.isNotEmpty ? ' التفاصيل: $_description.' : '';
    final media = _media.isEmpty ? 'بدون مرفقات' : '${_media.length} مرفق';
    return 'هذا ملخص بلاغك: النوع $type. $injuries. الموقع: $loc.$desc المرفقات: $media. هل تريد إرسال البلاغ الآن؟';
  }

  /// نسخة إنجليزية من ملخص البلاغ — تُقرأ صوتيًا فقط عند اختيار المستخدم
  /// "Read in English"، بدون التأثير على لغة واجهة التطبيق نفسها.
  String _summaryTextEn() {
    final type = _selectedType?.labelEn ?? 'Not specified';
    final injuries = _hasInjuries == true
        ? 'there are injuries'
        : (_hasInjuries == false ? 'there are no injuries' : 'injury status is unknown');
    final loc = _location?.address ?? 'not specified';
    final desc = _description.isNotEmpty ? ' Details: $_description.' : '';
    final media = _media.isEmpty ? 'no attachments' : '${_media.length} attachment(s)';
    return 'Here is your report summary. Type: $type. $injuries. Location: $loc.$desc Attachments: $media. Do you want to send this report now?';
  }

  // ------------------------------ الإرسال ------------------------------

  Future<void> _submit() async {
    if (_selectedType == null) return;
    setState(() => _step = _Step.sending);
    setState(() => _submitting = true);
    try {
      final fullDescription = [
        _description,
        if (_hasInjuries == true) 'يوجد مصابون.',
        if (_hasInjuries == false) 'لا يوجد مصابون.',
      ].where((s) => s.trim().isNotEmpty).join(' ');

      final result = await ReportsService.submitReport(
        type: _selectedType!.apiType,
        description: fullDescription,
        latitude: _location?.latitude,
        longitude: _location?.longitude,
        locationText: _location?.address ?? '',
        media: _media,
      );
      if (!mounted) return;
      setState(() {
        _reportId = result.reportId;
        _department = result.department;
        _step = _Step.done;
      });
      TtsService.instance.speak('تم استلام بلاغك بنجاح. رقم البلاغ ${result.reportId}. تم تحويل البلاغ للجهة المختصة.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      setState(() => _step = _Step.review);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ------------------------------ الواجهة ------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded, color: AppColors.textDark),
        ),
        title: Text('مساعد أمان', style: AppTextStyles.h3),
        centerTitle: true,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.intro:
        return _introView(key: const ValueKey('intro'));
      case _Step.listening:
        return _listeningView(key: const ValueKey('listening'));
      case _Step.confirmType:
        return _typePickerView(key: const ValueKey('confirmType'));
      case _Step.askInjuries:
        return _injuriesView(key: const ValueKey('askInjuries'));
      case _Step.askLocation:
        return _locationView(key: const ValueKey('askLocation'));
      case _Step.askPhoto:
        return _photoView(key: const ValueKey('askPhoto'));
      case _Step.review:
        return _reviewView(key: const ValueKey('review'));
      case _Step.sending:
        return _sendingView(key: const ValueKey('sending'));
      case _Step.done:
        return _doneView(key: const ValueKey('done'));
    }
  }

  Widget _introView({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('أخبرني ماذا حدث؟', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text('اضغط المايك وتكلم، أو اكتب بالأسفل', style: AppTextStyles.subtitle, textAlign: TextAlign.center),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: _startListening,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: AppColors.logoGradient,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.skyBlue.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 12))],
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 52),
            ),
          ),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: TextField(
              controller: _textController,
              textAlign: TextAlign.right,
              style: AppTextStyles.body,
              decoration: InputDecoration(
                hintText: 'أو اكتب هنا وش صار...',
                hintStyle: AppTextStyles.subtitle,
                border: InputBorder.none,
                suffixIcon: IconButton(
                  onPressed: _submitTyped,
                  icon: const Icon(Icons.send_rounded, color: AppColors.primaryBlue),
                ),
              ),
              onSubmitted: (_) => _submitTyped(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listeningView({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('أستمع إليك الآن...', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 30),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.15),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(color: AppColors.emergencyRed, shape: BoxShape.circle),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 52),
            ),
          ),
          const SizedBox(height: 30),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Text(
              _liveTranscript.isEmpty ? 'قل ماذا حدث...' : _liveTranscript,
              textAlign: TextAlign.right,
              style: AppTextStyles.body.copyWith(height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _stopListening,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: const Icon(Icons.stop_rounded, color: Colors.white),
              label: Text('انتهيت', style: AppTextStyles.button),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typePickerView({Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('اختر نوع البلاغ', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _types.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.3,
            ),
            itemBuilder: (context, index) {
              final t = _types[index];
              return GestureDetector(
                onTap: () => _selectType(t),
                child: Container(
                  decoration: BoxDecoration(color: t.bgColor, borderRadius: BorderRadius.circular(18)),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(t.icon, color: t.color, size: 30),
                      const SizedBox(height: 8),
                      Text(t.label, style: AppTextStyles.bodyMedium.copyWith(color: t.color)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _injuriesView({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.health_and_safety_rounded, color: AppColors.primaryBlue, size: 56),
          const SizedBox(height: 20),
          Text('هل يوجد مصابون؟', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => _answerInjuries(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emergencyRed,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text('نعم', style: AppTextStyles.button),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () => _answerInjuries(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primaryBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('لا', style: AppTextStyles.button.copyWith(color: AppColors.primaryBlue)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationView({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_on_rounded, color: AppColors.primaryBlue, size: 56),
          const SizedBox(height: 20),
          Text('هل تسمح لي باستخدام موقعك الحالي؟', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _locating ? null : _useCurrentLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: _locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded, color: Colors.white),
              label: Text('نعم، استخدم موقعي الحالي', style: AppTextStyles.button),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: _pickLocationManually,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.map_rounded, color: AppColors.primaryBlue),
              label: Text('تحديد الموقع يدويًا', style: AppTextStyles.button.copyWith(color: AppColors.primaryBlue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoView({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_rounded, color: AppColors.primaryBlue, size: 56),
          const SizedBox(height: 20),
          Text('هل تستطيع إرفاق صورة؟', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('اختياري — تقدر تتخطى هذي الخطوة', style: AppTextStyles.subtitle, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.camera),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: const Icon(Icons.photo_camera_rounded, color: Colors.white),
              label: Text('التقاط صورة', style: AppTextStyles.button),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.gallery),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.image_rounded, color: AppColors.primaryBlue),
              label: Text('اختيار من المعرض', style: AppTextStyles.button.copyWith(color: AppColors.primaryBlue)),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _skipPhoto,
            child: Text('تخطي', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textLight)),
          ),
        ],
      ),
    );
  }

  Widget _reviewView({Key? key}) {
    final type = _selectedType;
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('مراجعة البلاغ', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (type != null)
                  _reviewRow(icon: type.icon, iconColor: type.color, label: 'نوع البلاغ', value: type.label),
                _reviewRow(
                  icon: Icons.health_and_safety_rounded,
                  iconColor: AppColors.primaryBlue,
                  label: 'المصابون',
                  value: _hasInjuries == true ? 'يوجد مصابون' : (_hasInjuries == false ? 'لا يوجد مصابون' : 'غير محدد'),
                ),
                _reviewRow(
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.primaryBlue,
                  label: 'الموقع',
                  value: _location?.address ?? 'غير محدد',
                ),
                if (_description.isNotEmpty)
                  _reviewRow(icon: Icons.description_rounded, iconColor: AppColors.primaryBlue, label: 'الوصف', value: _description),
                _reviewRow(
                  icon: Icons.photo_library_rounded,
                  iconColor: AppColors.primaryBlue,
                  label: 'المرفقات',
                  value: _media.isEmpty ? 'لا يوجد' : '${_media.length} ملف',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('اقرأ الملخص بصوت عالٍ:', textAlign: TextAlign.center, style: AppTextStyles.caption),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => TtsService.instance.speak(_summaryText(), language: 'ar-SA'),
                icon: const Icon(Icons.volume_up_rounded, size: 18, color: AppColors.primaryBlue),
                label: Text('بالعربية', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => TtsService.instance.speak(_summaryTextEn(), language: 'en-US'),
                icon: const Icon(Icons.volume_up_rounded, size: 18, color: AppColors.primaryBlue),
                label: Text('English', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: (type == null || _submitting) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emergencyRed,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: const Icon(Icons.campaign_rounded, color: Colors.white),
              label: Text('إرسال البلاغ الآن', style: AppTextStyles.button),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(value, textAlign: TextAlign.right, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendingView({Key? key}) {
    return Center(
      key: key,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.primaryBlue),
          const SizedBox(height: 20),
          Text('جاري إرسال البلاغ...', style: AppTextStyles.h3),
        ],
      ),
    );
  }

  Widget _doneView({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: const BoxDecoration(color: AppColors.healthGreenBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: AppColors.healthGreen, size: 48),
          ),
          const SizedBox(height: 24),
          Text('تم استلام بلاغك بنجاح', style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          if (_reportId != null) Text('رقم البلاغ: $_reportId', style: AppTextStyles.subtitle),
          if (_department != null && _department!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('تم تحويل البلاغ إلى: $_department', style: AppTextStyles.subtitle),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (_reportId != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CaseTrackingScreen(caseId: _reportId)),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text('تتبع البلاغ', style: AppTextStyles.button),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('العودة للرئيسية', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textLight)),
          ),
        ],
      ),
    );
  }
}
