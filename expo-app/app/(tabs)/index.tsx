import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { publicAlerts } from '@/src/api';
import { useApp } from '@/src/app-context';
import { Brand, Card, ReportCard, SectionTitle } from '@/src/components';
import { colors, incidentLabel, shadow } from '@/src/theme';
import type { PublicAlert } from '@/src/types';

export default function HomeScreen() {
  const { session, reports, loadingReports, refreshReports, signOut } = useApp();
  const [alerts, setAlerts] = useState<PublicAlert[]>([]);
  useFocusEffect(useCallback(() => { refreshReports(); }, [refreshReports]));
  useEffect(() => { publicAlerts().then(setAlerts).catch(() => setAlerts([])); }, []);
  const latest = reports[0];

  return (
    <ScrollView style={styles.page} contentContainerStyle={styles.content} refreshControl={<RefreshControl refreshing={loadingReports} onRefresh={refreshReports} tintColor={colors.primary} />}>
      <View style={styles.header}>
        <Pressable onPress={() => Alert.alert('الحساب', session?.isGuest ? 'أنت تستخدم التطبيق كضيف على هذا الجهاز.' : session?.email || '', [{ text: 'إلغاء' }, { text: 'تسجيل الخروج', style: 'destructive', onPress: signOut }])} style={styles.avatar}>
          <Ionicons name="person-outline" size={20} color={colors.primary} />
        </Pressable>
        <Brand compact />
      </View>

      <View style={styles.greeting}>
        <Text style={styles.hello}>أهلاً {session?.isGuest ? 'بك' : session?.name} 👋</Text>
        <Text style={styles.prompt}>كيف نقدر نساعدك اليوم؟</Text>
      </View>

      <Pressable onPress={() => router.push('/(tabs)/report')}>
        <LinearGradient colors={['#E5484D', '#C92F39']} start={{ x: 1, y: 0 }} end={{ x: 0, y: 1 }} style={styles.emergency}>
          <View style={styles.emergencyIcon}><Ionicons name="megaphone" size={31} color="#fff" /></View>
          <View style={{ flex: 1 }}>
            <Text style={styles.emergencyTitle}>إرسال بلاغ طارئ</Text>
            <Text style={styles.emergencyText}>أضف صورة وموقعك ليصل البلاغ أوضح</Text>
          </View>
          <Ionicons name="chevron-back" size={22} color="#fff" />
        </LinearGradient>
      </Pressable>

      <View style={styles.quickGrid}>
        <Quick icon="camera-outline" label="بلاغ بصورة" onPress={() => router.push({ pathname: '/(tabs)/report', params: { camera: '1' } })} />
        <Quick icon="location-outline" label="إرسال الموقع" onPress={() => router.push('/(tabs)/report')} />
        <Quick icon="navigate-circle-outline" label="تتبع البلاغ" onPress={() => router.push('/(tabs)/tracking')} />
      </View>

      <SectionTitle title="آخر بلاغ" action={reports.length > 1 ? 'عرض الكل' : undefined} onAction={() => router.push('/(tabs)/tracking')} />
      {latest ? <ReportCard report={latest} onPress={() => router.push(`/report/${latest.report_id}`)} /> : (
        <Card><View style={styles.noReport}><Ionicons name="document-text-outline" size={28} color={colors.muted} /><View><Text style={styles.noReportTitle}>لا توجد بلاغات بعد</Text><Text style={styles.noReportText}>أول بلاغ سترسله سيظهر هنا</Text></View></View></Card>
      )}

      <View style={{ height: 24 }} />
      <SectionTitle title="تنبيهات قريبة وحديثة" />
      <Card>
        {alerts.slice(0, 4).map((item, index) => <View key={item.report_id} style={[styles.alertRow, index > 0 && styles.alertBorder]}>
          <View style={[styles.alertIcon, { backgroundColor: item.priority === 'high' ? colors.dangerSoft : colors.sky }]}><Ionicons name={item.type === 'weather' ? 'rainy-outline' : 'warning-outline'} size={20} color={item.priority === 'high' ? colors.danger : colors.primary} /></View>
          <View style={{ flex: 1 }}><Text style={styles.alertTitle}>{incidentLabel(item.type)}</Text><Text style={styles.alertLocation}>{item.wilayat || item.governorate || 'محافظة مسقط'} • تحديث حديث</Text></View>
        </View>)}
        {!alerts.length && <Text style={styles.noAlerts}>لا توجد تنبيهات عامة خلال الساعات الماضية</Text>}
      </Card>
      <View style={{ height: 24 }} />
      <Card style={styles.aiCard}><View style={styles.aiTop}><View style={styles.aiIcon}><Ionicons name="sparkles" size={24} color={colors.purple} /></View><View style={{ flex: 1 }}><Text style={styles.aiTitle}>وكيل أمان AI</Text><Text style={styles.aiText}>يحلل النص والصورة ويقدّم توصية للموظف، مع بقاء القرار النهائي بيد الجهة المختصة.</Text></View></View></Card>
    </ScrollView>
  );
}

function Quick({ icon, label, onPress }: { icon: keyof typeof Ionicons.glyphMap; label: string; onPress: () => void }) {
  return <Pressable onPress={onPress} style={styles.quick}><View style={styles.quickIcon}><Ionicons name={icon} size={22} color={colors.primary} /></View><Text style={styles.quickText}>{label}</Text></Pressable>;
}

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: colors.background }, content: { paddingTop: 58, paddingHorizontal: 18, paddingBottom: 115 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }, avatar: { width: 42, height: 42, borderRadius: 14, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.border },
  greeting: { marginTop: 28, marginBottom: 20, alignItems: 'flex-end' }, hello: { color: colors.ink, fontWeight: '900', fontSize: 24 }, prompt: { color: colors.muted, fontSize: 14, marginTop: 5 },
  emergency: { borderRadius: 24, padding: 18, flexDirection: 'row-reverse', alignItems: 'center', gap: 13, ...shadow }, emergencyIcon: { width: 56, height: 56, borderRadius: 18, backgroundColor: 'rgba(255,255,255,.18)', alignItems: 'center', justifyContent: 'center' }, emergencyTitle: { color: '#fff', fontSize: 19, fontWeight: '900', textAlign: 'right' }, emergencyText: { color: 'rgba(255,255,255,.84)', fontSize: 12, textAlign: 'right', marginTop: 4 },
  quickGrid: { flexDirection: 'row-reverse', gap: 10, marginVertical: 22 }, quick: { flex: 1, backgroundColor: '#fff', borderRadius: 18, paddingVertical: 14, alignItems: 'center', borderWidth: 1, borderColor: colors.border }, quickIcon: { width: 40, height: 40, borderRadius: 13, backgroundColor: colors.sky, alignItems: 'center', justifyContent: 'center', marginBottom: 7 }, quickText: { color: colors.ink, fontSize: 11, fontWeight: '700', textAlign: 'center' },
  noReport: { flexDirection: 'row-reverse', alignItems: 'center', gap: 13 }, noReportTitle: { textAlign: 'right', color: colors.ink, fontWeight: '800' }, noReportText: { textAlign: 'right', color: colors.muted, fontSize: 12, marginTop: 4 },
  alertRow: { flexDirection: 'row-reverse', gap: 12, alignItems: 'center', paddingVertical: 10 }, alertBorder: { borderTopWidth: 1, borderTopColor: colors.border }, alertIcon: { width: 42, height: 42, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }, alertTitle: { color: colors.ink, textAlign: 'right', fontWeight: '800' }, alertLocation: { color: colors.muted, textAlign: 'right', fontSize: 11, marginTop: 3 }, noAlerts: { textAlign: 'center', color: colors.muted, paddingVertical: 16 },
  aiCard: { backgroundColor: '#F6F3FF', borderColor: '#E7DEFF' }, aiTop: { flexDirection: 'row-reverse', gap: 13 }, aiIcon: { width: 46, height: 46, borderRadius: 15, backgroundColor: '#EAE3FF', alignItems: 'center', justifyContent: 'center' }, aiTitle: { color: colors.ink, fontWeight: '900', textAlign: 'right' }, aiText: { color: '#615D70', fontSize: 12, lineHeight: 19, textAlign: 'right', marginTop: 3 },
});

