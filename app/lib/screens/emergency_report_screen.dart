import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/reports_service.dart';
import 'map_location_picker_screen.dart';
import 'case_tracking_screen.dart';

class ReportCategory {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String apiType;

  const ReportCategory({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.apiType,
  });
}

class EmergencyReportScreen extends StatefulWidget {
  final bool isEmbedded;
  /// فهرس فئة مختارة مسبقًا (مثلاً قادم من شاشة روبوت الإرشاد) — يُحدَّد تلقائيًا عند فتح الشاشة.
  final int? initialCategoryIndex;
  const EmergencyReportScreen({super.key, this.isEmbedded = false, this.initialCategoryIndex});

  @override
  State<EmergencyReportScreen> createState() => _EmergencyReportScreenState();
}

class _EmergencyReportScreenState extends State<EmergencyReportScreen> {
  static const List<ReportCategory> categories = [
    ReportCategory(
      label: 'حرائق',
      icon: Icons.local_fire_department_rounded,
      color: AppColors.fireBlue,
      bgColor: AppColors.fireBlueBg,
      apiType: 'fire',
    ),
    ReportCategory(
      label: 'حادث سير-عوائق طريق',
      icon: Icons.car_crash_rounded,
      color: AppColors.accidentRed,
      bgColor: AppColors.accidentRedBg,
      apiType: 'traffic_accident',
    ),
    ReportCategory(
      label: 'أمطار وأودية',
      icon: Icons.water_drop_rounded,
      color: AppColors.weatherOrange,
      bgColor: AppColors.weatherOrangeBg,
      apiType: 'weather',
    ),
    ReportCategory(
      label: 'حالة صحية طارئة',
      icon: Icons.medical_services_rounded,
      color: AppColors.healthGreen,
      bgColor: AppColors.healthGreenBg,
      apiType: 'medical',
    ),
  ];

  int? _selectedCategory;
  final TextEditingController _detailsController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final SpeechToText _speech = SpeechToText();

  PickedLocation? _pickedLocation;
  // نخزّن XFile مباشرة بدل dart:io File عشان يشتغل صح على الويب أيضًا
  // (dart:io File ما يدعم قراءة/رفع الملفات بالمتصفح).
  final List<XFile> _mediaFiles = [];

  bool _isListening = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategoryIndex;
  }

  @override
  void dispose() {
    _detailsController.dispose();
    if (_isListening) _speech.stop();
    super.dispose();
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.of(context).push<PickedLocation>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.001),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const MapLocationPickerScreen(),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
    if (result != null) {
      setState(() => _pickedLocation = result);
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التعرف على الصوت غير متاح — تأكد من السماح بالوصول إلى الميكروفون')),
      );
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'ar-SA',
      onResult: (result) {
        setState(() {
          _detailsController.text = result.recognizedWords;
          _detailsController.selection = TextSelection.collapsed(offset: _detailsController.text.length);
        });
      },
    );
  }

  // ملاحظة: لا يوجد خيار "تسجيل فيديو" هنا عمدًا — الباك-إند بأكمله (فحص
  // نوع الملف، استخراج EXIF، تمويه الوجوه، وتحليل الصورة بالذكاء الاصطناعي
  // عبر n8n) مبني على الصور فقط ولا يقبل الفيديو إطلاقًا. عرض خيار فيديو
  // بالواجهة كان يقود لخطأ "نوع ملف غير مدعوم" دائمًا مهما كان الإصلاح.
  Future<void> _pickMedia(ImageSource source) async {
    Navigator.of(context).pop(); // إغلاق القائمة السفلية
    // ⚠️ لا نمرر imageQuality: إعادة الضغط تمسح بيانات EXIF بالكامل (وقت
    // الالتقاط، الجهاز، إحداثيات الكاميرا) — وهي أساس التحقق من صحة البلاغ
    // بالداشبورد. بدونها يظهر دائمًا "لا توجد بيانات وصفية بالصورة" مهما كانت
    // الصورة أصلية. نكتفي بتحديد أبعاد قصوى، وهو يقلل الحجم دون مسح البيانات.
    final XFile? file = await _imagePicker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (file != null) {
      setState(() => _mediaFiles.add(file));
    }
  }

  void _showAttachOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppColors.primaryBlue),
              title: Text('التقاط صورة', textAlign: TextAlign.right, style: AppTextStyles.bodyMedium),
              onTap: () => _pickMedia(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_rounded, color: AppColors.primaryBlue),
              title: Text('اختيار صورة من المعرض', textAlign: TextAlign.right, style: AppTextStyles.bodyMedium),
              onTap: () => _pickMedia(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_selectedCategory == null) return;
    if (_pickedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدّد موقع البلاغ على الخريطة أولاً')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final category = categories[_selectedCategory!];
      final result = await ReportsService.submitReport(
        type: category.apiType,
        description: _detailsController.text.trim(),
        latitude: _pickedLocation!.latitude,
        longitude: _pickedLocation!.longitude,
        locationText: _pickedLocation!.address,
        media: _mediaFiles,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CaseTrackingScreen(caseId: result.reportId)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, widget.isEmbedded ? 120 : 30),
        children: [
          Text('إرسال بلاغ طارئ', style: AppTextStyles.h2),
          const SizedBox(height: 6),
          Text('اختر نوع الحالة وأضف تفاصيل مختصرة', style: AppTextStyles.subtitle),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.7,
            ),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final selected = _selectedCategory == index;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: cat.bgColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected ? cat.color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(cat.icon, color: cat.color, size: 26),
                      const SizedBox(height: 8),
                      Text(
                        cat.label,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(color: cat.color, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _openLocationPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Icon(
                    _pickedLocation != null ? Icons.location_on_rounded : Icons.my_location_rounded,
                    color: _pickedLocation != null ? AppColors.emergencyRed : AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pickedLocation?.address ?? 'اضغط لتحديد موقع البلاغ على الخريطة',
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _pickedLocation != null
                          ? AppTextStyles.body
                          : AppTextStyles.subtitle.copyWith(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _detailsController,
            maxLines: 4,
            textAlign: TextAlign.right,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: _isListening ? 'جارٍ الاستماع... تحدّث الآن' : 'اكتبي تفاصيل البلاغ هنا، أو استخدمي الميكروفون بالأسفل',
              hintStyle: AppTextStyles.subtitle,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.divider),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _toggleListening,
              icon: Icon(
                _isListening ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                color: _isListening ? AppColors.emergencyRed : AppColors.primaryBlue,
              ),
              label: Text(
                _isListening ? 'جارٍ الاستماع... اضغط للإيقاف' : 'أملِ الوصف صوتيًا بدل الكتابة',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _isListening ? AppColors.emergencyRed : AppColors.primaryBlue,
                  fontSize: 13,
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: _isListening ? AppColors.softRedBg : AppColors.lightBlueBg,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _showAttachOptions,
              icon: Icon(
                _mediaFiles.isNotEmpty ? Icons.check_circle_rounded : Icons.attach_file_rounded,
                color: AppColors.primaryBlue,
              ),
              label: Text(
                _mediaFiles.isEmpty ? 'إرفاق صورة أو فيديو للتحقق الآلي' : 'تم إرفاق ${_mediaFiles.length} ملف — إضافة المزيد',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.lightBlueBg,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_mediaFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _mediaFiles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final file = _mediaFiles[i];
                  final isImage = RegExp(r'\.(jpg|jpeg|png|heic|webp)$', caseSensitive: false).hasMatch(file.path);
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: isImage
                            ? (kIsWeb
                                ? Image.network(file.path, width: 72, height: 72, fit: BoxFit.cover)
                                : Image.file(File(file.path), width: 72, height: 72, fit: BoxFit.cover))
                            : Container(
                                width: 72,
                                height: 72,
                                color: AppColors.lightBlueBg,
                                child: const Icon(Icons.videocam_rounded, color: AppColors.primaryBlue),
                              ),
                      ),
                      Positioned(
                        top: 2,
                        left: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _mediaFiles.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_selectedCategory != null && !_submitting) ? _submitReport : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emergencyRed,
                disabledBackgroundColor: AppColors.emergencyRed.withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                    )
                  : Text('إرسال البلاغ الآن', style: AppTextStyles.button),
            ),
          ),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return Scaffold(backgroundColor: AppColors.scaffoldBg, body: body);
    }
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        leading: const BackButton(color: AppColors.textDark),
      ),
      body: body,
    );
  }
}
