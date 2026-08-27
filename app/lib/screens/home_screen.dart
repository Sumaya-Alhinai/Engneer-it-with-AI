import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../core/labels.dart';
import '../services/auth_service.dart';
import '../services/reports_service.dart';
import 'emergency_report_screen.dart';
import 'notifications_screen.dart';
import 'voice_report_screen.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  int _activeAlertsCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAlertsCount();
    ReportsService.refreshTick.addListener(_load);
  }

  @override
  void dispose() {
    ReportsService.refreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final reports = await ReportsService.myReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// عدد التنبيهات النشطة (حوادث/أمطار) من كل المستخدمين، لعرض نقطة حمراء
  /// على أيقونة الإشعارات. فشل الجلب لا يزعج المستخدم — يبقى العداد صفرًا.
  Future<void> _loadAlertsCount() async {
    try {
      final all = await ReportsService.allReports();
      final count = all.where((r) => r['status'] != 'resolved').length;
      if (mounted) setState(() => _activeAlertsCount = count);
    } catch (_) {
      // تجاهل صامت — الإشعارات ميزة ثانوية لا توقف الشاشة الرئيسية
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? activeReport;
    for (final r in _reports) {
      if (r['status'] != 'resolved') {
        activeReport = r;
        break;
      }
    }
    final previousReports = _reports.where((r) => r['report_id'] != activeReport?['report_id']).take(5).toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              _TopBar(alertsCount: _activeAlertsCount),
              const SizedBox(height: 20),
              _VoiceHeroCard(
                onVoiceTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
                ),
              ),
              const SizedBox(height: 18),
              _QuickCategoryRow(
                onSelect: (index) => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EmergencyReportScreen(initialCategoryIndex: index)),
                ),
              ),
              const SizedBox(height: 22),
              Text('بلاغ نشط', style: AppTextStyles.h3),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (activeReport != null)
                _ActiveReportCard(report: activeReport, onTap: () => widget.onNavigateToTab?.call(2))
              else
                const _EmptyHint(text: 'لا يوجد بلاغ نشط حالياً'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('البلاغات السابقة', style: AppTextStyles.h3),
                  if (previousReports.isNotEmpty)
                    Text('عرض الكل', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryBlue, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              if (!_loading && previousReports.isEmpty)
                const _EmptyHint(text: 'لا توجد بلاغات سابقة بعد')
              else
                ...previousReports.map((r) => _PreviousReportTile(report: r)),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconForType(String? type) {
  switch (type) {
    case 'fire':
      return Icons.local_fire_department_rounded;
    case 'traffic_accident':
      return Icons.car_crash_rounded;
    case 'weather':
    case 'flood':
      return Icons.water_drop_rounded;
    case 'medical':
      return Icons.medical_services_rounded;
    default:
      return Icons.report_problem_rounded;
  }
}

(Color, Color) _colorsForType(String? type) {
  switch (type) {
    case 'fire':
      return (AppColors.fireBlue, AppColors.fireBlueBg);
    case 'traffic_accident':
      return (AppColors.accidentRed, AppColors.accidentRedBg);
    case 'weather':
    case 'flood':
      return (AppColors.weatherOrange, AppColors.weatherOrangeBg);
    case 'medical':
      return (AppColors.healthGreen, AppColors.healthGreenBg);
    default:
      return (AppColors.skyBlue, AppColors.lightBlueBg);
  }
}

String _formatDate(String? iso) {
  if (iso == null) return '';
  final date = DateTime.tryParse(iso);
  if (date == null) return '';
  const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  return '${date.year} ${months[date.month - 1]} ${date.day}';
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      alignment: Alignment.center,
      child: Text(text, style: AppTextStyles.subtitle),
    );
  }
}

class _TopBar extends StatelessWidget {
  final int alertsCount;
  const _TopBar({required this.alertsCount});

  @override
  Widget build(BuildContext context) {
    final rawName = AuthService.instance.name?.trim();
    final displayName = (rawName == null || rawName.isEmpty) ? 'زائر' : rawName;

    return Row(
      textDirection: TextDirection.ltr,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(child: Icon(Icons.notifications_none_rounded, color: AppColors.textDark)),
                if (alertsCount > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.emergencyRed,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('أهلاً بك، $displayName', style: AppTextStyles.bodyMedium.copyWith(fontSize: 15)),
            Text('نتمنى أنك بخير 🌤️', style: AppTextStyles.caption),
          ],
        ),
        const SizedBox(width: 12),
        const CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.lightBlueBg,
          child: Icon(Icons.person, color: AppColors.primaryBlue),
        ),
      ],
    );
  }
}

class _VoiceHeroCard extends StatelessWidget {
  final VoidCallback onVoiceTap;
  const _VoiceHeroCard({required this.onVoiceTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.splashGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppColors.primaryBlue.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('👋 مرحبًا بك في Aman AI', style: AppTextStyles.h3.copyWith(color: Colors.white), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('كيف يمكننا مساعدتك؟', style: AppTextStyles.caption.copyWith(color: Colors.white70), textAlign: TextAlign.center),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onVoiceTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: AppColors.emergencyRed, shape: BoxShape.circle),
                    child: const Icon(Icons.mic_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text('بلّغ بالصوت', style: AppTextStyles.h3),
                  const SizedBox(height: 2),
                  Text('اضغط وتحدث وسأساعدك خطوة بخطوة', style: AppTextStyles.caption, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCategoryRow extends StatelessWidget {
  final ValueChanged<int?> onSelect;
  const _QuickCategoryRow({required this.onSelect});

  static const List<(String, IconData, Color, Color, int?)> _items = [
    ('حريق', Icons.local_fire_department_rounded, AppColors.fireBlue, AppColors.fireBlueBg, 0),
    ('حادث سير', Icons.car_crash_rounded, AppColors.accidentRed, AppColors.accidentRedBg, 1),
    ('أمطار وفيضانات', Icons.water_drop_rounded, AppColors.weatherOrange, AppColors.weatherOrangeBg, 2),
    ('حالة صحية طارئة', Icons.medical_services_rounded, AppColors.healthGreen, AppColors.healthGreenBg, 3),
    ('خطر آخر', Icons.warning_rounded, AppColors.primaryBlue, AppColors.lightBlueBg, null),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('أو اختر نوع البلاغ', style: AppTextStyles.bodyMedium),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final (label, icon, color, bg, index) = _items[i];
              return GestureDetector(
                onTap: () => onSelect(index),
                child: Container(
                  width: 84,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color, size: 24),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActiveReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onTap;
  const _ActiveReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = _colorsForType(report['confirmed_incident_type'] as String? ?? report['type'] as String?);
    final title = (report['description'] as String?)?.trim().isNotEmpty == true
        ? report['description'] as String
        : (report['location_text'] as String? ?? 'بلاغ طارئ');
    final activeStep = Labels.statusStepIndex(report['status'] as String? ?? 'received');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                  child: Icon(_iconForType(report['confirmed_incident_type'] as String? ?? report['type'] as String?), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textLight),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              (report['location_text'] as String?) ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: AppColors.textLight),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.statusPendingBg, borderRadius: BorderRadius.circular(8)),
              child: Text(
                Labels.statusLabel(report['status'] as String?),
                style: AppTextStyles.caption.copyWith(color: AppColors.statusPendingText, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 14),
            _MiniTimeline(activeStep: activeStep),
          ],
        ),
      ),
    );
  }
}

class _MiniTimeline extends StatelessWidget {
  final int activeStep;
  const _MiniTimeline({required this.activeStep});
  final List<String> steps = const ['تم الاستلام', 'في الطريق', 'في الموقع', 'تم الحل'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftDone = (i ~/ 2) < activeStep;
          return Expanded(
            child: Container(height: 2, color: leftDone ? AppColors.statusGreenDot : AppColors.divider),
          );
        }
        final index = i ~/ 2;
        final done = index < activeStep;
        final isCurrent = index == activeStep;
        return Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.statusGreenDot : (isCurrent ? AppColors.primaryBlue : AppColors.divider),
              ),
              child: Icon(done ? Icons.check : Icons.circle, size: done ? 14 : 8, color: Colors.white),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 60,
              child: Text(steps[index], textAlign: TextAlign.center, style: AppTextStyles.caption.copyWith(fontSize: 10)),
            ),
          ],
        );
      }),
    );
  }
}

class _PreviousReportTile extends StatelessWidget {
  final Map<String, dynamic> report;
  const _PreviousReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = _colorsForType(report['confirmed_incident_type'] as String? ?? report['type'] as String?);
    final title = (report['description'] as String?)?.trim().isNotEmpty == true
        ? report['description'] as String
        : (report['location_text'] as String? ?? 'بلاغ');
    final isResolved = report['status'] == 'resolved';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(_iconForType(report['confirmed_incident_type'] as String? ?? report['type'] as String?), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(report['created_at'] as String?)}  ·  ${report['location_text'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isResolved ? AppColors.statusDoneBg : AppColors.statusPendingBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              Labels.statusLabel(report['status'] as String?),
              style: AppTextStyles.caption.copyWith(
                color: isResolved ? AppColors.statusDoneText : AppColors.statusPendingText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
