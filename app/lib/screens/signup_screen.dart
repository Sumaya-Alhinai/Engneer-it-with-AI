import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/auth_service.dart';
import 'email_verification_screen.dart';

enum _SignupMode { email, phone }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  _SignupMode _mode = _SignupMode.email;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(_SignupMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _identifierController.clear();
    });
  }

  bool get _isEmail => _mode == _SignupMode.email;

  Future<void> _signup() async {
    final name = _nameController.text.trim();
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تعبئة جميع الحقول')),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمة المرور يجب ألا تقل عن 6 أحرف')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.register(
        name: name,
        email: _isEmail ? identifier : null,
        phone: _isEmail ? null : identifier,
        password: password,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(
            email: _isEmail ? identifier : null,
            phone: _isEmail ? null : identifier,
          ),
        ),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                ),
                const SizedBox(height: 6),
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
                Text('إنشاء حساب جديد', style: AppTextStyles.h2),
                const SizedBox(height: 8),
                Text(
                  'أنشئ حسابك للإبلاغ عن الحوادث ومتابعتها',
                  style: AppTextStyles.subtitle,
                ),
                const SizedBox(height: 22),
                Text('الاسم', style: AppTextStyles.bodyMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'ادخل اسمك الكامل',
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
                _buildModeToggle(),
                const SizedBox(height: 18),
                Text(_isEmail ? 'البريد الإلكتروني' : 'رقم الهاتف', style: AppTextStyles.bodyMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _identifierController,
                  keyboardType: _isEmail ? TextInputType.emailAddress : TextInputType.phone,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: _isEmail ? 'example@email.com' : '+968 9xxxxxxx',
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
                  onSubmitted: (_) => _signup(),
                  decoration: InputDecoration(
                    hintText: '6 أحرف على الأقل',
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
                    onPressed: _loading ? null : _signup,
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
                        : Text('إنشاء حساب', style: AppTextStyles.button),
                  ),
                ),
                const SizedBox(height: 20),
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
          Expanded(child: _modeButton('البريد الإلكتروني', Icons.email_rounded, _SignupMode.email)),
          Expanded(child: _modeButton('رقم الهاتف', Icons.phone_iphone_rounded, _SignupMode.phone)),
        ],
      ),
    );
  }

  Widget _modeButton(String label, IconData icon, _SignupMode mode) {
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
