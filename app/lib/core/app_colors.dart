import 'package:flutter/material.dart';

/// المخطط اللوني الموحّد لتطبيق Aman AI
class AppColors {
  AppColors._();

  // درجات الأزرق الأساسية (الهوية البصرية)
  static const Color navyDark = Color(0xFF0A1A33);
  static const Color navy = Color(0xFF0F2A52);
  static const Color primaryBlue = Color(0xFF1B57D6);
  static const Color skyBlue = Color(0xFF3E8CF7);
  static const Color lightBlueBg = Color(0xFFEAF2FF);

  // الأحمر (الطوارئ)
  static const Color emergencyRed = Color(0xFFE8433D);
  static const Color emergencyRedDark = Color(0xFFC62828);
  static const Color softRedBg = Color(0xFFFDE8E7);

  // ألوان فئات البلاغ
  static const Color fireBlue = Color(0xFF4A7DFF);
  static const Color fireBlueBg = Color(0xFFE3EBFF);

  static const Color accidentRed = Color(0xFFFF6B6B);
  static const Color accidentRedBg = Color(0xFFFFE6E6);

  static const Color weatherOrange = Color(0xFFFFB86B);
  static const Color weatherOrangeBg = Color(0xFFFFEEDC);

  static const Color healthGreen = Color(0xFF4CD07D);
  static const Color healthGreenBg = Color(0xFFE0F8E9);

  // حالات ونصوص
  static const Color textDark = Color(0xFF1B1F2A);
  static const Color textMedium = Color(0xFF5B6478);
  static const Color textLight = Color(0xFF9AA3B2);
  static const Color divider = Color(0xFFE7EAF0);
  static const Color scaffoldBg = Color(0xFFF5F7FB);
  static const Color cardBg = Colors.white;

  static const Color statusPendingBg = Color(0xFFFFF1D6);
  static const Color statusPendingText = Color(0xFFB8860B);
  static const Color statusDoneBg = Color(0xFFE0F8E9);
  static const Color statusDoneText = Color(0xFF2E9F5C);
  static const Color statusOrangeDot = Color(0xFFFF9F43);
  static const Color statusGreenDot = Color(0xFF2ECC71);

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [navyDark, Color(0xFF14345F), primaryBlue],
  );

  static const LinearGradient logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A6BF0), Color(0xFF8FC0FF)],
  );
}
