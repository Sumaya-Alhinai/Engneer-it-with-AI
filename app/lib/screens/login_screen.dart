import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/auth_service.dart';
import 'account_setup_screen.dart';
import 'email_verification_screen.dart';
import 'main_shell.dart';
import 'signup_screen.dart';

enum _LoginMode { email, phone }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _LoginMode _mode = _LoginMode.email;
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(_LoginMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _identifierController.clear();
    });
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mode == _LoginMode.email
            ? 'يرجى إدخال البريد الإلكتروني وكلمة المرور'
            : 'يرجى إدخال رقم الهاتف وكلمة المرور')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.login(
        email: _mode == _LoginMode.email ? identifier : null,
        phone: _mode == _LoginMode.phone ? identifier : null,
        password: password,
      );
      if (!mounted) return;
      final setupDone = await AuthService.instance.isSetupDone();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => setupDone ? const MainShell() : const AccountSetupScreen()),
        (route) => false,
      );
    } on EmailNotVerifiedException catch (e) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EmailVerificationScreen(email: e.email, phone: e.phone, autoResend: true)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmail = _mode == _LoginMode.email;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.logoGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Text('A',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 22),
                Text('مرحباً بك في Aman AI', style: AppTextStyles.h2),
                const SizedBox(height: 8),
                Text(
                  'سجّل الدخول لمتابعة البلاغات والحالات الطارئة',
                  style: AppTextStyles.subtitle,
                ),
                const SizedBox(height: 24),
                _buildModeToggle(),
                const SizedBox(height: 22),
                Text(isEmail ? 'البريد الإلكتروني' : 'رقم الهاتف', style: AppTextStyles.bodyMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _identifierController,
                  keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.phone,
                  textAlign: TextAlign.right,
                  textDirection: isEmail ? TextDirection.ltr : TextDirection.ltr,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: isEmail ? 'example@email.com' : '+968 9xxxxxxx',
                    hintStyle: AppTextStyles.subtitle,
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('كلمة المرور', style: AppTextStyles.bodyMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.body,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: 'ادخل كلمة المرور',
                    hintStyle: AppTextStyles.subtitle,
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: AppColors.textLight,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                          )
                        : Text('تسجيل الدخول', style: AppTextStyles.button),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      );
                    },
                    child: Text.rich(
                      TextSpan(
                        text: 'ليس لديك حساب؟ ',
                        style: AppTextStyles.subtitle,
                        children: [
                          TextSpan(
                            text: 'إنشاء حساب جديد',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _modeButton('البريد الإلكتروني', Icons.email_rounded, _LoginMode.email)),
          Expanded(child: _modeButton('رقم الهاتف', Icons.phone_iphone_rounded, _LoginMode.phone)),
        ],
      ),
    );
  }

  Widget _modeButton(String label, IconData icon, _LoginMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? AppColors.primaryBlue : AppColors.textLight),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: selected ? AppColors.primaryBlue : AppColors.textLight,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
