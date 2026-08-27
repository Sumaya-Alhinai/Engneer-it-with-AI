import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/auth_service.dart';
import 'account_setup_screen.dart';

/// شاشة تفعيل الحساب برمز مكوّن من 6 أرقام. تعمل مع البريد الإلكتروني **أو**
/// رقم الهاتف — مرّر واحدًا منهما بالضبط في [email] أو [phone].
class EmailVerificationScreen extends StatefulWidget {
  final String? email;
  final String? phone;

  /// إذا كانت الشاشة مفتوحة بعد تسجيل حساب جديد، الرمز أُرسل بالفعل ولا داعي
  /// لطلب إرسال جديد فورًا. إذا فُتحت من شاشة الدخول (حساب موجود غير مفعّل)،
  /// نطلب رمزًا جديدًا تلقائيًا لأن الرمز الأصلي قد تكون انتهت صلاحيته.
  final bool autoResend;

  const EmailVerificationScreen({super.key, this.email, this.phone, this.autoResend = false})
      : assert(email != null || phone != null, 'لازم تمرر email أو phone');

  bool get _isPhone => phone != null && phone!.isNotEmpty;
  String get _identifier => _isPhone ? phone! : (email ?? '');

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _secondsLeft = 59;
  Timer? _timer;
  bool _verifying = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    if (widget.autoResend) {
      _resend(silent: true);
    }
  }

  void _startTimer() {
    _secondsLeft = 59;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _resend({bool silent = false}) async {
    setState(() => _resending = true);
    try {
      await AuthService.instance.resendCode(email: widget.email, phone: widget.phone);
      _startTimer();
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أُعيد إرسال رمز التحقق')),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _confirm() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رمز التحقق المكوّن من 6 أرقام')),
      );
      return;
    }
    setState(() => _verifying = true);
    try {
      await AuthService.instance.verifyEmail(email: widget.email, phone: widget.phone, code: code);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountSetupScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 22),
              Text('تفعيل الحساب', style: AppTextStyles.h2),
              const SizedBox(height: 8),
              Text(
                widget._isPhone
                    ? 'أدخل رمز التحقق المرسل عبر رسالة نصية إلى ${widget._identifier}'
                    : 'أدخل رمز التحقق المرسل إلى ${widget._identifier}',
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 32),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      return SizedBox(
                        width: 48,
                        height: 58,
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: AppTextStyles.h2,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: AppColors.scaffoldBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                            ),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty && index < 5) {
                              _focusNodes[index + 1].requestFocus();
                            } else if (value.isEmpty && index > 0) {
                              _focusNodes[index - 1].requestFocus();
                            }
                            if (index == 5 && value.isNotEmpty) {
                              FocusScope.of(context).unfocus();
                            }
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Center(
                child: Column(
                  children: [
                    Text(
                      _secondsLeft > 0
                          ? 'إعادة إرسال الرمز خلال 00:$_secondsLeftText'
                          : 'لم يصلك الرمز؟',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: (_secondsLeft == 0 && !_resending) ? () => _resend() : null,
                      child: _resending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'إعادة إرسال الرمز',
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue),
                            ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _verifying ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                        )
                      : Text('تأكيد', style: AppTextStyles.button),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String get _secondsLeftText => _secondsLeft.toString().padLeft(2, '0');
}
