import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';
import '../core/labels.dart';
import '../services/reports_service.dart';

class CaseTrackingScreen extends StatefulWidget {
  /// معرّف بلاغ محدد لعرضه. إذا تُرك فارغًا، تُعرض أحدث بلاغات المستخدم.
  final String? caseId;
  final bool isEmbedded;

  const CaseTrackingScreen({super.key, this.caseId, this.isEmbedded = false});

  @override
  State<CaseTrackingScreen> createState() => _CaseTrackingScreenState();
}

class _CaseTrackingScreenState extends State<CaseTrackingScreen> {
  Map<String, dynamic>? _report;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      Map<String, dynamic>? report;
      if (widget.caseId != null) {
        report = await ReportsService.getReport(widget.caseId!);
      } else {
        final list = await ReportsService.myReports();
        report = list.isNotEmpty ? list.first : null;
      }
      if (!mounted) return;
      setState(() {
        _report = report;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _error = e.toString());
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = _MessageState(icon: Icons.error_outline_rounded, message: _error!, onRetry: _load);
    } else if (_report == null) {
      content = const _MessageState(
        icon: Icons.assignment_outlined,
        message: 'لا يوجد بلاغ لعرضه حالياً',
      );
    } else {
      content = RefreshIndicator(
        onRefresh: () => _load(),
        child: _ReportDetails(report: _report!, isEmbedded: widget.isEmbedded),
      );
    }

    if (widget.isEmbedded) {
      return Scaffold(backgroundColor: AppColors.scaffoldBg, body: SafeArea(bottom: false, child: content));
    }
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        leading: const BackButton(color: AppColors.textDark),
      ),
      body: SafeArea(bottom: false, child: content),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  const _MessageState({required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.subtitle),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportDetails extends StatelessWidget {
  final Map<String, dynamic> report;
  final bool isEmbedded;
  const _ReportDetails({required this.report, required this.isEmbedded});

  @override
  Widget build(BuildContext context) {
    final status = (report['status'] as String?) ?? 'received';
    final activeStep = Labels.statusStepIndex(status);
    final department = Labels.departmentLabel(report['department'] as String?);
    final priority = Labels.priorityLabel(report['priority'] as String?);
    final riskScore = (report['risk_score'] as num?)?.toDouble();
    final description = (report['description'] as String?)?.trim();
    final reportId = report['report_id'] as String? ?? '';

    final steps = [
      ('تم استلام البلاغ ومعالجته آليًا', status != 'received'),
      ('تم توجيهه إلى $department', activeStep >= 1),
      ('الفريق في الطريق / بالموقع', activeStep >= 2),
      ('تم الحل', activeStep >= 3),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, isEmbedded ? 120 : 30),
      children: [
        Text('متابعة البلاغ #$reportId', style: AppTextStyles.h2),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: AppColors.lightBlueBg, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.report_problem_rounded, color: AppColors.skyBlue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (description?.isNotEmpty ?? false) ? description! : (report['location_text'] as String? ?? 'بلاغ طارئ'),
                      style: AppTextStyles.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.statusPendingBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      Labels.statusLabel(status),
                      style: AppTextStyles.caption.copyWith(color: AppColors.statusPendingText, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (riskScore != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primaryBlue),
                        const SizedBox(width: 2),
                        Text(
                          'درجة الخطورة: ${riskScore.round()}% · $priority',
                          style: AppTextStyles.caption.copyWith(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('خط المعالجة', style: AppTextStyles.h3),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: List.generate(steps.length, (index) {
              final (title, done) = steps[index];
              final isLast = index == steps.length - 1;
              final isCurrent = index == activeStep && !done;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done
                                ? AppColors.statusGreenDot
                                : (isCurrent ? AppColors.statusOrangeDot : AppColors.divider),
                          ),
                        ),
                        if (!isLast) Container(width: 2, height: 34, color: AppColors.divider),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: AppTextStyles.bodyMedium),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('رقم البلاغ $reportId — تم نسخ رابط مشاركة الحالة')),
              );
            },
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            label: Text('مشاركة الحالة', style: AppTextStyles.button),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
