import { Ionicons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Image, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { getReport } from '@/src/api';
import { useApp } from '@/src/app-context';
import { Card } from '@/src/components';
import { colors, incidentLabel, priorityLabel, statusLabel } from '@/src/theme';
import type { Report } from '@/src/types';

const operational = ['received', 'assigned', 'dispatched', 'resolved'];

export default function ReportDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useApp();
  const [report, setReport] = useState<Report | null>(null);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    if (!session || !id) return;
    try { setReport(await getReport(session.token, id)); } finally { setLoading(false); }
  }, [id, session]);
  useEffect(() => { void load(); const timer = setInterval(load, 6000); return () => clearInterval(timer); }, [load]);
  const current = report ? Math.max(0, operational.indexOf(report.status || 'received')) : 0;

  return <View style={styles.page}>
    <View style={styles.header}><Pressable onPress={() => router.back()} style={styles.back}><Ionicons name="arrow-forward" size={22} color={colors.ink} /></Pressable><Text style={styles.headerTitle}>تفاصيل البلاغ</Text><View style={{ width: 42 }} /></View>
    {loading && !report ? <ActivityIndicator style={{ flex: 1 }} color={colors.primary} /> : report ? <ScrollView refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />} contentContainerStyle={styles.content}>
      <Card style={styles.hero}>
        <View style={styles.heroTop}><View style={styles.icon}><Ionicons name="alert-circle" size={28} color={colors.primary} /></View><View style={{ flex: 1 }}><Text style={styles.type}>{incidentLabel(report.confirmed_incident_type || report.type)}</Text><Text style={styles.id}>{report.report_id}</Text></View></View>
        <Text style={styles.description}>{report.description || 'بلاغ طارئ'}</Text>
        <View style={styles.badges}><Badge text={statusLabel(report.status)} color={colors.primary} bg={colors.sky} /><Badge text={priorityLabel(report.priority)} color={report.priority === 'high' ? colors.danger : colors.warning} bg={report.priority === 'high' ? colors.dangerSoft : colors.warningSoft} /></View>
      </Card>

      {report.pipeline_status !== 'completed' ? <View style={styles.processing}><ActivityIndicator color={colors.purple} /><View style={{ flex: 1 }}><Text style={styles.processingTitle}>وكيل أمان AI يحلل البلاغ</Text><Text style={styles.processingText}>يقرأ النص والصورة ويقارن مؤشرات الخطورة. ستتحدث الصفحة تلقائياً.</Text></View></View> : <View style={[styles.processing, { backgroundColor: colors.successSoft }]}><Ionicons name="checkmark-circle" size={25} color={colors.success} /><View style={{ flex: 1 }}><Text style={[styles.processingTitle, { color: colors.success }]}>اكتمل التحليل الأولي</Text><Text style={styles.processingText}>أصبحت النتيجة متاحة للجهة المختصة للمراجعة.</Text></View></View>}

      {!!report.media_paths?.length && <><Text style={styles.section}>المرفقات</Text><ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 10 }}>{report.media_paths.map((uri) => <Image key={uri} source={{ uri }} style={styles.image} />)}</ScrollView></>}
      <Text style={styles.section}>مسار البلاغ</Text>
      <Card>{operational.map((status, index) => <View key={status} style={styles.step}><View style={styles.stepLine}>{index < operational.length - 1 && <View style={[styles.line, index < current && { backgroundColor: colors.primary }]} />}<View style={[styles.stepDot, index <= current && { backgroundColor: colors.primary, borderColor: colors.primary }]}>{index <= current && <Ionicons name="checkmark" size={13} color="#fff" />}</View></View><View style={{ flex: 1 }}><Text style={[styles.stepTitle, index <= current && { color: colors.ink }]}>{statusLabel(status)}</Text><Text style={styles.stepText}>{index === 0 ? 'تم حفظ البلاغ والصور بأمان' : index === 1 ? 'مراجعة البلاغ وتحديد الجهة' : index === 2 ? 'تحديث ميداني من فريق الاستجابة' : 'إغلاق الحالة بعد المعالجة'}</Text></View></View>)}</Card>
      {!!report.location_text && <><Text style={styles.section}>الموقع</Text><Card><View style={styles.location}><Ionicons name="location" size={24} color={colors.danger} /><Text style={styles.locationText}>{report.location_text}</Text></View></Card></>}
      <View style={styles.disclaimer}><Ionicons name="shield-checkmark-outline" size={19} color={colors.muted} /><Text style={styles.disclaimerText}>نتيجة الذكاء الاصطناعي دعم قرار وليست تأكيداً لإرسال فريق أو إشعار جهة.</Text></View>
    </ScrollView> : <View style={styles.center}><Text>تعذر العثور على البلاغ</Text></View>}
  </View>;
}

function Badge({ text, color, bg }: { text: string; color: string; bg: string }) { return <View style={[styles.badge, { backgroundColor: bg }]}><Text style={[styles.badgeText, { color }]}>{text}</Text></View>; }

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: colors.background }, header: { paddingTop: 56, paddingHorizontal: 18, paddingBottom: 14, backgroundColor: '#fff', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }, back: { width: 42, height: 42, borderRadius: 14, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' }, headerTitle: { color: colors.ink, fontSize: 18, fontWeight: '900' }, content: { padding: 18, paddingBottom: 50 },
  hero: { marginBottom: 14 }, heroTop: { flexDirection: 'row-reverse', alignItems: 'center', gap: 12 }, icon: { width: 50, height: 50, borderRadius: 16, backgroundColor: colors.sky, alignItems: 'center', justifyContent: 'center' }, type: { color: colors.ink, fontSize: 20, fontWeight: '900', textAlign: 'right' }, id: { color: colors.muted, textAlign: 'right', marginTop: 3, fontSize: 12 }, description: { color: '#42526A', textAlign: 'right', lineHeight: 22, marginTop: 16 }, badges: { flexDirection: 'row-reverse', gap: 8, marginTop: 16 }, badge: { borderRadius: 12, paddingHorizontal: 11, paddingVertical: 7 }, badgeText: { fontSize: 11, fontWeight: '800' },
  processing: { backgroundColor: '#F1EEFF', borderRadius: 18, padding: 15, flexDirection: 'row-reverse', alignItems: 'center', gap: 12, marginBottom: 22 }, processingTitle: { color: colors.purple, fontWeight: '900', textAlign: 'right' }, processingText: { color: colors.muted, fontSize: 11, lineHeight: 17, textAlign: 'right', marginTop: 3 }, section: { color: colors.ink, textAlign: 'right', fontSize: 18, fontWeight: '900', marginTop: 8, marginBottom: 12 }, image: { width: 220, height: 150, borderRadius: 18, backgroundColor: '#E8EDF4' },
  step: { flexDirection: 'row-reverse', gap: 13, minHeight: 72 }, stepLine: { width: 28, alignItems: 'center' }, line: { position: 'absolute', top: 22, bottom: -4, width: 2, backgroundColor: colors.border }, stepDot: { width: 24, height: 24, borderRadius: 12, borderWidth: 2, borderColor: '#C7D1DE', backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' }, stepTitle: { color: colors.muted, fontWeight: '800', textAlign: 'right' }, stepText: { color: colors.muted, fontSize: 11, textAlign: 'right', marginTop: 4 }, location: { flexDirection: 'row-reverse', gap: 10, alignItems: 'center' }, locationText: { flex: 1, color: colors.ink, textAlign: 'right', lineHeight: 21 }, disclaimer: { flexDirection: 'row-reverse', gap: 8, padding: 16, alignItems: 'center' }, disclaimerText: { flex: 1, color: colors.muted, fontSize: 11, textAlign: 'right' }, center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
