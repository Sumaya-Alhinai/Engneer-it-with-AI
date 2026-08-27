import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../services/reports_service.dart';

const Set<String> _roadAffectingTypes = {'traffic_accident', 'weather', 'flood'};

IconData _alertIcon(String? type) {
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

(Color, Color) _alertColors(String? type) {
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

String _typeLabel(String? type) {
  switch (type) {
    case 'fire':
      return 'حريق';
    case 'traffic_accident':
      return 'حادث سير';
    case 'weather':
    case 'flood':
      return 'أمطار / سيول';
    case 'medical':
      return 'حالة صحية طارئة';
    default:
      return 'بلاغ';
  }
}

String _relativeTime(String? iso) {
  if (iso == null) return '';
  final date = DateTime.tryParse(iso);
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
  return 'قبل ${diff.inDays} يوم';
}

/// شاشة التنبيهات — تعرض بلاغات نشطة قريبة (حرائق/حوادث/أمطار...) من كل
/// المستخدمين، مع ملخص سريع لحالة الطرق (سالكة أو متأثرة) مبني على أحدث
/// البلاغات. هذا تقدير مبني على البلاغات الواردة وليس بيانات مرورية حية.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await ReportsService.allReports();
      final active = all.where((r) => r['status'] != 'resolved').toList()
        ..sort((a, b) => (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? ''));
      if (!mounted) return;
      setState(() {
        _alerts = active;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل التنبيهات';
        _loading = false;
      });
    }
  }

  bool get _roadsAffected => _alerts.any((r) => _roadAffectingTypes.contains(r['confirmed_incident_type'] ?? r['type']));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        title: Text('التنبيهات', style: AppTextStyles.h3),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  children: [
                    _RoadStatusCard(affected: _roadsAffected, activeCount: _alerts.length),
                    const SizedBox(height: 20),
                    Text('آخر التنبيهات', style: AppTextStyles.h3),
                    const SizedBox(height: 12),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        alignment: Alignment.center,
                        child: Text(_error!, style: AppTextStyles.subtitle),
                      )
                    else if (_alerts.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            const Icon(Icons.notifications_off_outlined, color: AppColors.textLight, size: 32),
                            const SizedBox(height: 8),
                            Text('لا توجد تنبيهات حاليًا', style: AppTextStyles.subtitle),
                          ],
                        ),
                      )
                    else
                      ..._alerts.map((r) => _AlertTile(report: r)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RoadStatusCard extends StatelessWidget {
  final bool affected;
  final int activeCount;
  const _RoadStatusCard({required this.affected, required this.activeCount});

  @override
  Widget build(BuildContext context) {
    final color = affected ? AppColors.weatherOrange : AppColors.healthGreen;
    final bg = affected ? AppColors.weatherOrangeBg : AppColors.healthGreenBg;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), shape: BoxShape.circle),
            child: Icon(affected ? Icons.warning_rounded : Icons.check_circle_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  affected ? 'قد يكون هناك تأخير على بعض الطرق' : 'الطرق سالكة حاليًا',
                  style: AppTextStyles.bodyMedium.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  affected
                      ? 'بناءً على $activeCount بلاغ نشط (حوادث/أمطار) — تجنّب مناطق البلاغات أدناه'
                      : 'لا توجد بلاغات حوادث أو أمطار نشطة حاليًا',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final Map<String, dynamic> report;
  const _AlertTile({required this.report});

  @override
  Widget build(BuildContext context) {
    final type = report['confirmed_incident_type'] as String? ?? report['type'] as String?;
    final (color, bg) = _alertColors(type);
    final roadAffecting = _roadAffectingTypes.contains(type);
    final location = (report['location_text'] as String?) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(_alertIcon(type), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(_relativeTime(report['created_at'] as String?), style: AppTextStyles.caption),
                    const SizedBox(width: 6),
                    Text(_typeLabel(type), style: AppTextStyles.bodyMedium),
                  ],
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(location, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                ],
                if (roadAffecting) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.weatherOrangeBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'قد يؤثر على حركة السير',
                      style: AppTextStyles.caption.copyWith(color: AppColors.weatherOrange, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
