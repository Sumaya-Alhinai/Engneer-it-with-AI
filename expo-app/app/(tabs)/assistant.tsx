import { Ionicons } from '@expo/vector-icons';
import * as Speech from 'expo-speech';
import { router } from 'expo-router';
import { useRef, useState } from 'react';
import { FlatList, KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Brand } from '@/src/components';
import { colors, shadow } from '@/src/theme';

type Message = { id: string; text: string; user: boolean; type?: string };
const welcome: Message = { id: 'welcome', user: false, text: 'مرحباً! أنا مساعد أمان. صف لي الحالة وسأعطيك إرشاداً سريعاً وأفتح لك نموذج البلاغ المناسب.' };
const guides = [
  { words: ['حريق', 'دخان', 'نار'], type: 'fire', text: 'ابتعد عن مصدر الحريق ولا تستخدم المصعد. اتصل بالطوارئ فوراً إذا كان هناك خطر مباشر، ثم أرسل بلاغاً مع صورة من مكان آمن.' },
  { words: ['حادث', 'سيارة', 'اصطدام'], type: 'traffic_accident', text: 'ابتعد عن مسار المركبات وشغّل إشارات التحذير إن أمكن. لا تحرّك المصاب إلا عند وجود خطر مباشر، وأرسل الموقع بدقة.' },
  { words: ['مطر', 'وادي', 'سيل'], type: 'weather', text: 'لا تعبر مجرى الوادي حتى لو بدا مستوى الماء منخفضاً. ارجع إلى مكان مرتفع وآمن وأرسل موقع العائق.' },
  { words: ['مريض', 'إغماء', 'تنفس', 'إسعاف'], type: 'medical', text: 'اتصل بالإسعاف فوراً. تأكد أن المكان آمن وراقب التنفس، ولا تقدّم دواءً أو طعاماً لشخص فاقد الوعي.' },
];

export default function AssistantScreen() {
  const [messages, setMessages] = useState<Message[]>([welcome]);
  const [input, setInput] = useState('');
  const list = useRef<FlatList<Message>>(null);
  const send = (preset?: string) => {
    const value = (preset || input).trim(); if (!value) return;
    const guide = guides.find((item) => item.words.some((word) => value.includes(word)));
    const reply: Message = { id: `${Date.now()}-a`, user: false, type: guide?.type, text: guide?.text || 'إذا يوجد خطر مباشر اتصل برقم الطوارئ أولاً. اذكر نوع الحالة والموقع وما الذي تراه، ويمكنك فتح بلاغ وإضافة صورة الآن.' };
    setMessages((all) => [...all, { id: `${Date.now()}-u`, user: true, text: value }, reply]);
    setInput('');
    setTimeout(() => list.current?.scrollToEnd({ animated: true }), 50);
  };
  return <KeyboardAvoidingView style={styles.page} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={76}>
    <View style={styles.header}><Brand compact /><View style={styles.online}><View style={styles.onlineDot} /><Text style={styles.onlineText}>مساعد الإرشاد</Text></View></View>
    <View style={styles.chips}><Quick text="يوجد حريق" onPress={() => send('يوجد حريق')} /><Quick text="حادث سير" onPress={() => send('حادث سير')} /><Quick text="حالة صحية" onPress={() => send('حالة صحية')} /></View>
    <FlatList ref={list} data={messages} keyExtractor={(item) => item.id} contentContainerStyle={styles.messages} renderItem={({ item }) => <View style={[styles.message, item.user ? styles.userMessage : styles.botMessage]}>
      <Text style={[styles.messageText, item.user && { color: '#fff' }]}>{item.text}</Text>
      {!item.user && <View style={styles.messageActions}><Pressable onPress={() => Speech.speak(item.text, { language: 'ar-SA', rate: 0.9 })}><Ionicons name="volume-medium-outline" size={19} color={colors.muted} /></Pressable>{item.type && <Pressable onPress={() => router.push({ pathname: '/(tabs)/report', params: { type: item.type } })} style={styles.reportLink}><Ionicons name="megaphone-outline" size={16} color={colors.primary} /><Text style={styles.reportLinkText}>فتح بلاغ جاهز</Text></Pressable>}</View>}
    </View>} />
    <View style={styles.composer}><Pressable onPress={() => send()} style={styles.send}><Ionicons name="send" size={20} color="#fff" /></Pressable><TextInput value={input} onChangeText={setInput} onSubmitEditing={() => send()} returnKeyType="send" placeholder="صف الحالة هنا..." placeholderTextColor="#98A5B7" textAlign="right" style={styles.input} /></View>
  </KeyboardAvoidingView>;
}

function Quick({ text, onPress }: { text: string; onPress: () => void }) { return <Pressable onPress={onPress} style={styles.chip}><Text style={styles.chipText}>{text}</Text></Pressable>; }
const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: colors.background }, header: { paddingTop: 56, paddingHorizontal: 18, paddingBottom: 14, backgroundColor: '#fff', flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center' }, online: { flexDirection: 'row-reverse', alignItems: 'center', gap: 6 }, onlineDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: colors.success }, onlineText: { color: colors.muted, fontSize: 11 }, chips: { flexDirection: 'row-reverse', gap: 8, padding: 12 }, chip: { backgroundColor: '#fff', borderWidth: 1, borderColor: colors.border, borderRadius: 15, paddingHorizontal: 12, paddingVertical: 8 }, chipText: { color: colors.primary, fontSize: 11, fontWeight: '700' },
  messages: { paddingHorizontal: 16, paddingBottom: 20, gap: 11 }, message: { maxWidth: '84%', borderRadius: 19, padding: 14, ...shadow }, userMessage: { alignSelf: 'flex-start', backgroundColor: colors.primary, borderBottomLeftRadius: 5 }, botMessage: { alignSelf: 'flex-end', backgroundColor: '#fff', borderBottomRightRadius: 5, borderWidth: 1, borderColor: colors.border }, messageText: { color: colors.ink, textAlign: 'right', fontSize: 14, lineHeight: 22 }, messageActions: { marginTop: 10, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }, reportLink: { flexDirection: 'row-reverse', alignItems: 'center', gap: 5 }, reportLinkText: { color: colors.primary, fontSize: 11, fontWeight: '800' },
  composer: { backgroundColor: '#fff', borderTopWidth: 1, borderTopColor: colors.border, paddingHorizontal: 14, paddingTop: 10, paddingBottom: Platform.OS === 'ios' ? 96 : 90, flexDirection: 'row', alignItems: 'center', gap: 10 }, input: { flex: 1, height: 50, borderRadius: 16, backgroundColor: colors.background, paddingHorizontal: 14, color: colors.ink }, send: { width: 48, height: 48, borderRadius: 16, backgroundColor: colors.primary, alignItems: 'center', justifyContent: 'center' },
});

