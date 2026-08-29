import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect } from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useApp } from '@/src/app-context';
import { Brand, EmptyState, ReportCard, SectionTitle } from '@/src/components';
import { colors } from '@/src/theme';

export default function TrackingScreen() {
  const { reports, loadingReports, refreshReports } = useApp();
  useFocusEffect(useCallback(() => { refreshReports(); }, [refreshReports]));
  useEffect(() => { const timer = setInterval(refreshReports, 8000); return () => clearInterval(timer); }, [refreshReports]);
  return (
    <ScrollView style={styles.page} contentContainerStyle={styles.content} refreshControl={<RefreshControl refreshing={loadingReports} onRefresh={refreshReports} tintColor={colors.primary} />}>
      <Brand compact />
      <View style={styles.heading}><Text style={styles.title}>متابعة البلاغات</Text><Text style={styles.subtitle}>تتحدث الحالات تلقائياً كل بضع ثوانٍ</Text></View>
      <SectionTitle title={`بلاغاتي (${reports.length})`} />
      {reports.length ? reports.map((report) => <ReportCard key={report.report_id} report={report} onPress={() => router.push(`/report/${report.report_id}`)} />) : <EmptyState icon="navigate-circle-outline" title="لا توجد بلاغات" detail="بعد إرسال أول بلاغ ستتمكن من متابعة التحليل والحالة من هنا." />}
    </ScrollView>
  );
}
const styles = StyleSheet.create({ page: { flex: 1, backgroundColor: colors.background }, content: { paddingHorizontal: 18, paddingTop: 58, paddingBottom: 115 }, heading: { alignItems: 'flex-end', marginTop: 28, marginBottom: 28 }, title: { color: colors.ink, fontWeight: '900', fontSize: 27 }, subtitle: { color: colors.muted, marginTop: 5 } });

