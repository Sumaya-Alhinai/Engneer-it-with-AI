import { Ionicons } from '@expo/vector-icons';
import type { PropsWithChildren, ReactNode } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, incidentLabel, priorityLabel, shadow, statusLabel } from './theme';
import type { Report } from './types';

export function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <View style={styles.brand}>
      <View style={[styles.brandIcon, compact && { width: 38, height: 38, borderRadius: 12 }]}>
        <Ionicons name="shield-checkmark" size={compact ? 22 : 28} color="#fff" />
      </View>
      <View>
        <Text style={[styles.brandName, compact && { fontSize: 19 }]}>أمان AI</Text>
        {!compact && <Text style={styles.brandTag}>بلاغ أسرع، استجابة أوضح</Text>}
      </View>
    </View>
  );
}

export function SectionTitle({ title, action, onAction }: { title: string; action?: string; onAction?: () => void }) {
  return (
    <View style={styles.sectionTitle}>
      {action ? <Pressable onPress={onAction}><Text style={styles.action}>{action}</Text></Pressable> : <View />}
      <Text style={styles.sectionText}>{title}</Text>
    </View>
  );
}

export function Card({ children, style }: PropsWithChildren<{ style?: object }>) {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function PrimaryButton({ title, onPress, loading, icon = 'arrow-back' }: { title: string; onPress: () => void; loading?: boolean; icon?: keyof typeof Ionicons.glyphMap }) {
  return (
    <Pressable disabled={loading} onPress={onPress} style={({ pressed }) => [styles.primaryButton, pressed && { opacity: 0.86 }, loading && { opacity: 0.65 }]}>
      {loading ? <ActivityIndicator color="#fff" /> : <Ionicons name={icon} size={20} color="#fff" />}
      <Text style={styles.primaryButtonText}>{title}</Text>
    </Pressable>
  );
}

export function ReportCard({ report, onPress }: { report: Report; onPress?: () => void }) {
  const pipeline = report.pipeline_status;
  const complete = pipeline === 'completed';
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.reportCard, pressed && { opacity: 0.85 }]}>
      <View style={styles.reportTop}>
        <View style={[styles.pipelineBadge, { backgroundColor: complete ? colors.successSoft : colors.warningSoft }]}>
          <View style={[styles.dot, { backgroundColor: complete ? colors.success : colors.warning }]} />
          <Text style={[styles.pipelineText, { color: complete ? colors.success : colors.warning }]}>{complete ? 'اكتمل التحليل' : 'قيد التحليل'}</Text>
        </View>
        <View style={styles.reportTypeRow}>
          <View>
            <Text style={styles.reportType}>{incidentLabel(report.confirmed_incident_type || report.type)}</Text>
            <Text style={styles.reportId}>{report.report_id}</Text>
          </View>
          <View style={styles.reportIcon}><Ionicons name="alert-circle-outline" size={22} color={colors.primary} /></View>
        </View>
      </View>
      <Text numberOfLines={2} style={styles.reportDescription}>{report.description || report.location_text || 'بلاغ طارئ'}</Text>
      <View style={styles.reportMeta}>
        <Text style={styles.metaText}>{priorityLabel(report.priority)}</Text>
        <Text style={styles.metaDivider}>•</Text>
        <Text style={styles.metaText}>{statusLabel(report.status)}</Text>
        <View style={{ flex: 1 }} />
        <Ionicons name="chevron-back" size={18} color={colors.muted} />
      </View>
    </Pressable>
  );
}

export function EmptyState({ icon, title, detail, action }: { icon: keyof typeof Ionicons.glyphMap; title: string; detail: string; action?: ReactNode }) {
  return (
    <View style={styles.empty}>
      <View style={styles.emptyIcon}><Ionicons name={icon} size={30} color={colors.primary} /></View>
      <Text style={styles.emptyTitle}>{title}</Text>
      <Text style={styles.emptyDetail}>{detail}</Text>
      {action}
    </View>
  );
}

const styles = StyleSheet.create({
  brand: { flexDirection: 'row-reverse', alignItems: 'center', gap: 12 },
  brandIcon: { width: 50, height: 50, borderRadius: 16, backgroundColor: colors.primary, alignItems: 'center', justifyContent: 'center', ...shadow },
  brandName: { color: colors.ink, fontSize: 25, fontWeight: '900', textAlign: 'right' },
  brandTag: { color: colors.muted, fontSize: 12, marginTop: 1, textAlign: 'right' },
  sectionTitle: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 },
  sectionText: { fontSize: 19, color: colors.ink, fontWeight: '800', textAlign: 'right' },
  action: { fontSize: 13, color: colors.primary, fontWeight: '700' },
  card: { backgroundColor: colors.surface, borderRadius: 22, padding: 18, borderWidth: 1, borderColor: colors.border, ...shadow },
  primaryButton: { minHeight: 56, borderRadius: 17, backgroundColor: colors.primary, paddingHorizontal: 20, flexDirection: 'row', gap: 10, alignItems: 'center', justifyContent: 'center', ...shadow },
  primaryButtonText: { color: '#fff', fontSize: 16, fontWeight: '800' },
  reportCard: { backgroundColor: colors.surface, borderRadius: 20, padding: 16, borderWidth: 1, borderColor: colors.border, marginBottom: 12, ...shadow },
  reportTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' },
  pipelineBadge: { paddingHorizontal: 9, height: 26, borderRadius: 13, flexDirection: 'row', gap: 6, alignItems: 'center' },
  pipelineText: { fontSize: 10, fontWeight: '800' },
  dot: { width: 6, height: 6, borderRadius: 3 },
  reportTypeRow: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  reportIcon: { width: 40, height: 40, borderRadius: 13, backgroundColor: colors.sky, alignItems: 'center', justifyContent: 'center' },
  reportType: { fontSize: 16, fontWeight: '800', color: colors.ink, textAlign: 'right' },
  reportId: { fontSize: 11, color: colors.muted, textAlign: 'right', marginTop: 2 },
  reportDescription: { color: '#40516A', lineHeight: 21, fontSize: 13, textAlign: 'right', marginVertical: 12 },
  reportMeta: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7, borderTopWidth: 1, borderTopColor: colors.border, paddingTop: 12 },
  metaText: { color: colors.muted, fontSize: 11, fontWeight: '600' },
  metaDivider: { color: '#B9C4D3' },
  empty: { alignItems: 'center', paddingVertical: 48, paddingHorizontal: 30 },
  emptyIcon: { width: 66, height: 66, borderRadius: 22, backgroundColor: colors.sky, alignItems: 'center', justifyContent: 'center', marginBottom: 16 },
  emptyTitle: { color: colors.ink, fontWeight: '800', fontSize: 18, marginBottom: 6 },
  emptyDetail: { color: colors.muted, textAlign: 'center', lineHeight: 21, marginBottom: 18 },
});

