import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/app_colors.dart';
import 'screens/splash_screen.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/tts_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.loadSession();
  await TtsService.instance.setDefaultLanguage(AuthService.instance.language);
  runApp(const AmanAIApp());
}

class AmanAIApp extends StatelessWidget {
  const AmanAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aman AI',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.scaffoldBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          primary: AppColors.primaryBlue,
        ),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      builder: (context, child) {
        // فرض اتجاه الكتابة من اليمين لليسار في كل التطبيق
        final mq = MediaQuery.of(context);
        // التطبيق مصمّم كواجهة موبايل بعرض ضيق. على شاشة كمبيوتر/متصفح
        // واسعة (Chrome على ديسكتوب مثلاً) نحصر عرض المحتوى بعرض يشابه
        // الموبايل ونحاذيه بالنص، بدل ما يتمدد ويتشوّه على كامل الشاشة.
        // بدون هذا، أحجام العناصر والشبكات تتضخم بشكل غير طبيعي على
        // الشاشات الواسعة.
        const double maxMobileWidth = 480;
        final double targetWidth = mq.size.width > maxMobileWidth ? maxMobileWidth : mq.size.width;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            color: AppColors.navyDark,
            alignment: Alignment.topCenter,
            child: MediaQuery(
              // نحدّث MediaQuery عشان أي حساب مبني على عرض الشاشة (مثل
              // MediaQuery.of(context).size.width) يطابق العرض الفعلي
              // المعروض، مو عرض نافذة المتصفح الكامل.
              data: mq.copyWith(size: Size(targetWidth, mq.size.height)),
              child: SizedBox(
                width: targetWidth,
                height: mq.size.height,
                child: child!,
              ),
            ),
          ),
        );
      },
      home: AuthService.instance.isLoggedIn ? const MainShell() : const SplashScreen(),
    );
  }
}
