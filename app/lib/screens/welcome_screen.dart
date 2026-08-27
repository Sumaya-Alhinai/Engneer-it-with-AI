import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/auth_service.dart';
import 'account_setup_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

/// شاشة الترحيب — الخطوة الثانية بعد Splash. تعطي المستخدم 3 خيارات:
/// تسجيل الدخول، إنشاء حساب جديد، أو المتابعة كضيف للإبلاغ عن طارئ مباشرة
/// بدون حساب (يفقد إمكانية متابعة بلاغاته لاحقًا من جهاز آخر).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _guestLoading = false;

  Future<void> _continueAsGuest() async {
    setState(() => _guestLoading = true);
    await AuthService.instance.continueAsGuest();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountSetupScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: AppColors.logoGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: AppColors.skyBlue.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('A', style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(height: 22),
              Text('أهلاً بك في Aman AI', style: AppTextStyles.h1, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                'كيف تحب تبدأ؟',
                style: AppTextStyles.subtitle,
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text('تسجيل الدخول', style: AppTextStyles.button),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SignupScreen()),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryBlue, width: 1.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('إنشاء حساب جديد', style: AppTextStyles.button.copyWith(color: AppColors.primaryBlue)),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _guestLoading ? null : _continueAsGuest,
                child: _guestLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text.rich(
                        TextSpan(
                          text: 'أو ',
                          style: AppTextStyles.subtitle,
                          children: [
                            TextSpan(
                              text: 'تابع كضيف للإبلاغ عن طارئ الآن',
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.emergencyRed),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                'ملاحظة: كضيف تقدر ترسل بلاغ فورًا، لكن ما تقدر تتابع حالته لاحقًا من جهاز ثاني',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
