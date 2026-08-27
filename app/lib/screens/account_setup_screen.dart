import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/auth_service.dart';
import '../services/tts_service.dart';
import 'main_shell.dart';

/// شاشة إعداد الحساب — تظهر مرة واحدة فقط بعد إنشاء الحساب/تفعيله أو
/// الدخول كضيف: اختيار اللغة، السماح بالموقع، السماح بالميكروفون، وتفعيل
/// الإشعارات. كل صلاحية اختيارية — المستخدم يقدر يكمل بدونها ويُطلب منه
/// لاحقًا عند الحاجة الفعلية (مثل فتح خريطة أو الضغط على المايك).
class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({super.key});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  String _language = 'ar';
  bool? _locationGranted;
  bool? _micGranted;
  bool _notificationsEnabled = true;
  bool _requestingLocation = false;
  bool _requestingMic = false;
  bool _finishing = false;

  Future<void> _requestLocation() async {
    setState(() => _requestingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted = permission == LocationPermission.always || permission == LocationPermission.whileInUse;
      if (mounted) setState(() => _locationGranted = granted);
    } catch (_) {
      if (mounted) setState(() => _locationGranted = false);
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
    }
  }

  Future<void> _requestMic() async {
    setState(() => _requestingMic = true);
    try {
      final speech = SpeechToText();
      final available = await speech.initialize();
      if (mounted) setState(() => _micGranted = available);
    } catch (_) {
      if (mounted) setState(() => _micGranted = false);
    } finally {
      if (mounted) setState(() => _requestingMic = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await AuthService.instance.markSetupDone(
      language: _language,
      locationGranted: _locationGranted ?? false,
      micGranted: _micGranted ?? false,
      notificationsEnabled: _notificationsEnabled,
    );
    await TtsService.instance.setDefaultLanguage(_language);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text('إعداد سريع', style: AppTextStyles.h2),
              const SizedBox(height: 6),
              Text('عشان Aman AI يخدمك بأفضل شكل', style: AppTextStyles.subtitle),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _sectionCard(
                      title: 'اللغة',
                      icon: Icons.language_rounded,
                      child: Row(
                        children: [
                          Expanded(child: _langChip('العربية', 'ar')),
                          const SizedBox(width: 10),
                          Expanded(child: _langChip('English', 'en')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _permissionCard(
                      title: 'الموقع',
                      description: 'يساعدنا نحدد موقعك تلقائيًا عند إرسال بلاغ',
                      icon: Icons.location_on_rounded,
                      granted: _locationGranted,
                      loading: _requestingLocation,
                      onTap: _requestLocation,
                    ),
                    const SizedBox(height: 14),
                    _permissionCard(
                      title: 'الميكروفون',
                      description: 'يخليك تبلّغ بصوتك بدل الكتابة — مفيد جدًا لكبار السن',
                      icon: Icons.mic_rounded,
                      granted: _micGranted,
                      loading: _requestingMic,
                      onTap: _requestMic,
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: 'الإشعارات',
                      icon: Icons.notifications_active_rounded,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'أعلمني بتحديثات حالة بلاغاتي',
                              textAlign: TextAlign.right,
                              style: AppTextStyles.body,
                            ),
                          ),
                          Switch(
                            value: _notificationsEnabled,
                            activeTrackColor: AppColors.primaryBlue,
                            onChanged: (v) => setState(() => _notificationsEnabled = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _finishing ? null : _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _finishing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                        )
                      : Text('متابعة', style: AppTextStyles.button),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.bodyMedium),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _langChip(String label, String value) {
    final selected = _language == value;
    return GestureDetector(
      onTap: () => setState(() => _language = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.lightBlueBg : AppColors.scaffoldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primaryBlue : Colors.transparent, width: 1.4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(color: selected ? AppColors.primaryBlue : AppColors.textMedium),
        ),
      ),
    );
  }

  Widget _permissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool? granted,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _permissionButton(granted: granted, loading: loading, onTap: onTap),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(title, style: AppTextStyles.bodyMedium),
                    const SizedBox(width: 8),
                    Icon(icon, color: AppColors.primaryBlue, size: 18),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description, textAlign: TextAlign.right, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionButton({required bool? granted, required bool loading, required VoidCallback onTap}) {
    if (loading) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (granted == true) {
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(color: AppColors.healthGreenBg, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: AppColors.healthGreen, size: 20),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.lightBlueBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          granted == false ? 'حاول مجددًا' : 'سماح',
          style: AppTextStyles.caption.copyWith(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
