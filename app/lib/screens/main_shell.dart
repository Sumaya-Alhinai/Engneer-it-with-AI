import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../widgets/custom_bottom_nav.dart';
import 'home_screen.dart';
import 'emergency_report_screen.dart';
import 'case_tracking_screen.dart';
import 'assistant_screen.dart';
import 'voice_report_screen.dart';

const double _kAssistantBtnWidth = 150;
const double _kAssistantBtnHeight = 46;
const String _kPosXKey = 'assistant_btn_x';
const String _kPosYKey = 'assistant_btn_y';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  // موقع الزاوية العلوية اليسرى لزر "مساعد أمان" العائم. null يعني لم
  // يُحمَّل بعد أو المستخدم لم يحرّكه من قبل، فنستخدم موقعًا افتراضيًا.
  Offset? _btnPosition;

  void goToTab(int index) => setState(() => _currentIndex = index);

  @override
  void initState() {
    super.initState();
    _loadButtonPosition();
  }

  Future<void> _loadButtonPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_kPosXKey);
    final y = prefs.getDouble(_kPosYKey);
    if (x != null && y != null && mounted) {
      setState(() => _btnPosition = Offset(x, y));
    }
  }

  Future<void> _saveButtonPosition(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPosXKey, offset.dx);
    await prefs.setDouble(_kPosYKey, offset.dy);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onNavigateToTab: goToTab),
      const EmergencyReportScreen(isEmbedded: true),
      const CaseTrackingScreen(isEmbedded: true),
      const AssistantScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxX = (constraints.maxWidth - _kAssistantBtnWidth - 8).clamp(8.0, double.infinity);
          // نبقيه فوق شريط التنقل السفلي العائم بمسافة كافية
          final maxY = (constraints.maxHeight - _kAssistantBtnHeight - 90).clamp(8.0, double.infinity);
          final position = _btnPosition ?? Offset(maxX, maxY);
          final clampedX = position.dx.clamp(8.0, maxX);
          final clampedY = position.dy.clamp(8.0, maxY);

          return Stack(
            children: [
              IndexedStack(index: _currentIndex, children: pages),
              // زر "مساعد أمان" العائم — يبقى ظاهر بكل الصفحات (الموقع،
              // الصور، المراجعة...) وقابل للسحب، يتذكّر آخر مكان حطّه
              // فيه المستخدم عشان يتحكم بمكانه بنفسه.
              Positioned(
                left: clampedX,
                top: clampedY,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      final newX = (clampedX + details.delta.dx).clamp(8.0, maxX);
                      final newY = (clampedY + details.delta.dy).clamp(8.0, maxY);
                      _btnPosition = Offset(newX, newY);
                    });
                  },
                  onPanEnd: (_) {
                    if (_btnPosition != null) _saveButtonPosition(_btnPosition!);
                  },
                  child: _FloatingAssistantButton(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: goToTab,
      ),
    );
  }
}

class _FloatingAssistantButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FloatingAssistantButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.logoGradient,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(color: AppColors.primaryBlue.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('مساعد أمان', style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
            const SizedBox(width: 4),
            Icon(Icons.drag_indicator_rounded, color: Colors.white.withOpacity(0.6), size: 16),
          ],
        ),
      ),
    );
  }
}
