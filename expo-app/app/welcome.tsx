import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { Redirect } from 'expo-router';
import { ComponentProps, useState } from 'react';
import { ActivityIndicator, Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useApp } from '@/src/app-context';
import { Brand } from '@/src/components';
import { colors, shadow } from '@/src/theme';

type Mode = 'start' | 'login' | 'register' | 'verify';

export default function Welcome() {
  const { session, continueAsGuest, signIn, signUp, confirmEmail } = useApp();
  const [mode, setMode] = useState<Mode>('start');
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  if (session) return <Redirect href="/(tabs)" />;

  const act = async (fn: () => Promise<void>) => {
    setBusy(true);
    try { await fn(); } catch (error) { Alert.alert('تعذر إكمال العملية', error instanceof Error ? error.message : 'حاول مرة أخرى'); }
    finally { setBusy(false); }
  };
  const submit = () => act(async () => {
    if (mode === 'login') await signIn(email.trim(), password);
    if (mode === 'register') { await signUp(name.trim(), email.trim(), password); setMode('verify'); }
    if (mode === 'verify') await confirmEmail(email.trim(), code.trim());
  });

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.root}>
        <LinearGradient colors={['#EAF2FF', '#F7FAFF']} style={styles.heroGlow} />
        <Brand />
        <View style={styles.illustration}>
          <View style={styles.ring}><Ionicons name="shield-checkmark" size={70} color="#fff" /></View>
          <View style={[styles.signal, { right: 14, top: 30 }]}><Ionicons name="location" size={18} color={colors.danger} /></View>
          <View style={[styles.signal, { left: 8, bottom: 26 }]}><Ionicons name="sparkles" size={18} color={colors.primary} /></View>
        </View>
        <Text style={styles.headline}>{mode === 'start' ? 'السلامة تبدأ ببلاغ واضح' : mode === 'verify' ? 'تحقق من بريدك' : mode === 'register' ? 'أنشئ حساب أمان' : 'مرحباً بعودتك'}</Text>
        <Text style={styles.subhead}>{mode === 'start' ? 'أرسل البلاغ مع الصورة والموقع، ويتولى وكيل أمان AI تحليله وتوجيهه للجهة المناسبة.' : mode === 'verify' ? 'أدخل رمز التحقق الذي أرسلناه إلى بريدك.' : 'استخدم بريدك للوصول إلى بلاغاتك من أي جهاز.'}</Text>

        {mode === 'start' ? <View style={styles.actions}>
          <Pressable onPress={() => act(continueAsGuest)} disabled={busy} style={styles.mainButton}>
            {busy ? <ActivityIndicator color="#fff" /> : <Ionicons name="flash" size={20} color="#fff" />}
            <Text style={styles.mainText}>ابدأ الآن كضيف</Text>
          </Pressable>
          <Pressable onPress={() => setMode('login')} style={styles.secondaryButton}><Text style={styles.secondaryText}>تسجيل الدخول</Text></Pressable>
          <Pressable onPress={() => setMode('register')}><Text style={styles.link}>ليس لديك حساب؟ أنشئ حساباً</Text></Pressable>
        </View> : <View style={styles.form}>
          {mode === 'register' && <Input icon="person-outline" placeholder="الاسم الكامل" value={name} onChangeText={setName} />}
          {mode !== 'verify' && <Input icon="mail-outline" placeholder="البريد الإلكتروني" value={email} onChangeText={setEmail} keyboardType="email-address" />}
          {mode !== 'verify' && <Input icon="lock-closed-outline" placeholder="كلمة المرور" value={password} onChangeText={setPassword} secureTextEntry />}
          {mode === 'verify' && <Input icon="keypad-outline" placeholder="رمز التحقق" value={code} onChangeText={setCode} keyboardType="number-pad" />}
          <Pressable disabled={busy} onPress={submit} style={styles.mainButton}>{busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.mainText}>{mode === 'verify' ? 'تأكيد الرمز' : mode === 'register' ? 'إنشاء الحساب' : 'دخول'}</Text>}</Pressable>
          <Pressable onPress={() => setMode('start')}><Text style={styles.link}>العودة</Text></Pressable>
        </View>}
        <View style={styles.privacy}><Ionicons name="lock-closed" size={14} color={colors.success} /><Text style={styles.privacyText}>الصور خاصة وتظهر للجهة المختصة بروابط مؤقتة فقط</Text></View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function Input(props: ComponentProps<typeof TextInput> & { icon: keyof typeof Ionicons.glyphMap }) {
  const { icon, ...inputProps } = props;
  return <View style={styles.inputWrap}><Ionicons name={icon} size={19} color={colors.muted} /><TextInput {...inputProps} autoCapitalize="none" textAlign="right" style={styles.input} placeholderTextColor="#98A5B7" /></View>;
}

const styles = StyleSheet.create({
  root: { flexGrow: 1, alignItems: 'center', paddingHorizontal: 24, paddingTop: 72, paddingBottom: 34, backgroundColor: colors.background },
  heroGlow: { position: 'absolute', top: 0, left: 0, right: 0, height: 370, borderBottomLeftRadius: 60, borderBottomRightRadius: 60 },
  illustration: { width: 190, height: 190, alignItems: 'center', justifyContent: 'center', marginTop: 32 },
  ring: { width: 136, height: 136, borderRadius: 68, backgroundColor: colors.primary, alignItems: 'center', justifyContent: 'center', borderWidth: 10, borderColor: '#D7E6FF', ...shadow },
  signal: { position: 'absolute', width: 42, height: 42, borderRadius: 14, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', ...shadow },
  headline: { fontSize: 27, fontWeight: '900', color: colors.ink, textAlign: 'center', marginTop: 6 },
  subhead: { fontSize: 14, color: colors.muted, textAlign: 'center', lineHeight: 23, maxWidth: 360, marginTop: 10 },
  actions: { width: '100%', gap: 12, marginTop: 28 }, form: { width: '100%', gap: 12, marginTop: 24 },
  mainButton: { height: 56, borderRadius: 17, backgroundColor: colors.primary, flexDirection: 'row', gap: 9, justifyContent: 'center', alignItems: 'center', ...shadow },
  mainText: { color: '#fff', fontSize: 16, fontWeight: '800' },
  secondaryButton: { height: 54, borderRadius: 17, backgroundColor: '#fff', borderWidth: 1, borderColor: colors.border, justifyContent: 'center', alignItems: 'center' },
  secondaryText: { color: colors.ink, fontSize: 15, fontWeight: '800' }, link: { color: colors.primary, fontWeight: '700', textAlign: 'center', paddingVertical: 8 },
  inputWrap: { height: 55, borderWidth: 1, borderColor: colors.border, backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, flexDirection: 'row', alignItems: 'center', gap: 10 },
  input: { flex: 1, fontSize: 15, color: colors.ink },
  privacy: { marginTop: 24, flexDirection: 'row-reverse', alignItems: 'center', gap: 7 }, privacyText: { color: colors.muted, fontSize: 11 },
});

