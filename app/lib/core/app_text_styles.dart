import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// أنماط النصوص الموحّدة - نستخدم خط Tajawal المناسب للعربية
class AppTextStyles {
  AppTextStyles._();

  static TextStyle _base({
    double size = 14,
    FontWeight weight = FontWeight.normal,
    Color color = AppColors.textDark,
    double? height,
  }) {
    return GoogleFonts.tajawal(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  static TextStyle h1 = _base(size: 26, weight: FontWeight.bold);
  static TextStyle h2 = _base(size: 22, weight: FontWeight.bold);
  static TextStyle h3 = _base(size: 18, weight: FontWeight.bold);
  static TextStyle subtitle =
      _base(size: 14, weight: FontWeight.w500, color: AppColors.textMedium);
  static TextStyle body = _base(size: 14, color: AppColors.textDark);
  static TextStyle bodyMedium =
      _base(size: 14, weight: FontWeight.w600, color: AppColors.textDark);
  static TextStyle caption = _base(size: 12, color: AppColors.textLight);
  static TextStyle button =
      _base(size: 16, weight: FontWeight.bold, color: Colors.white);
}
