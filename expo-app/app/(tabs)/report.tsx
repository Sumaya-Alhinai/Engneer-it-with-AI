import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import * as ImagePicker from 'expo-image-picker';
import * as Location from 'expo-location';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { submitReport } from '@/src/api';
import { useApp } from '@/src/app-context';
import { Brand, PrimaryButton, SectionTitle } from '@/src/components';
import { colors, incidentTypes } from '@/src/theme';
import type { MediaAsset } from '@/src/types';

const exifText = (exif: Record<string, unknown> | null | undefined, ...keys: string[]) => {
  for (const key of keys) if (typeof exif?.[key] === 'string' && String(exif[key]).trim()) return String(exif[key]).trim();
  return null;
};

const gpsNumber = (value: unknown, ref?: unknown) => {
  let result: number | null = null;
  if (typeof value === 'number' && Number.isFinite(value)) result = value;
  if (Array.isArray(value) && value.length >= 3) {
    const parts = value.map(Number);
    if (parts.every(Number.isFinite)) result = parts[0] + parts[1] / 60 + parts[2] / 3600;
  }
  return result != null && (ref === 'S' || ref === 'W') ? -Math.abs(result) : result;
};

const assetFrom = (item: ImagePicker.ImagePickerAsset, source: 'camera' | 'library'): MediaAsset => {
  const exif = item.exif as Record<string, unknown> | null | undefined;
  return {
    uri: item.uri,
    name: item.fileName || `aman-${Date.now()}.jpg`,
    type: item.mimeType || 'image/jpeg',
    file: item.file,
    metadata: {
      filename: item.fileName,
      mime_type: item.mimeType,
      file_size: item.fileSize,
      width: item.width,
      height: item.height,
      device_make: exifText(exif, 'Make', 'make'),
      device_model: exifText(exif, 'Model', 'model'),
      software: exifText(exif, 'Software', 'software'),
      captured_at: exifText(exif, 'DateTimeOriginal', 'DateTimeDigitized', 'DateTime', 'datetime'),
      gps_latitude: gpsNumber(exif?.GPSLatitude, exif?.GPSLatitudeRef),
      gps_longitude: gpsNumber(exif?.GPSLongitude, exif?.GPSLongitudeRef),
      source,
    },
  };
};

export default function ReportScreen() {
  const { camera, type: initialType } = useLocalSearchParams<{ camera?: string; type?: string }>();
  const openedCamera = useRef(false);
  const { session, refreshReports } = useApp();
  const [type, setType] = useState(initialType || '');
  const [description, setDescription] = useState('');
  const [locationText, setLocationText] = useState('');
  const [coordinates, setCoordinates] = useState<{ latitude: number; longitude: number } | null>(null);
  const [media, setMedia] = useState<MediaAsset[]>([]);
  const [locating, setLocating] = useState(false);
  const [sending, setSending] = useState(false);

  const choosePhotos = async () => {
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) return Alert.alert('نحتاج إذن الصور', 'اسمح لأمان AI بالوصول إلى الصور التي تختارها للبلاغ.');
    const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: true, selectionLimit: 3, quality: 0.78, exif: true });
    if (!result.canceled) setMedia((current) => [...current, ...result.assets.map((asset) => assetFrom(asset, 'library'))].slice(0, 3));
  };

  const takePhoto = useCallback(async () => {
    const permission = await ImagePicker.requestCameraPermissionsAsync();
    if (!permission.granted) return Alert.alert('نحتاج إذن الكاميرا', 'اسمح لأمان AI باستخدام الكاميرا لتوثيق البلاغ.');
    const result = await ImagePicker.launchCameraAsync({ mediaTypes: ['images'], quality: 0.78, exif: true });
    if (!result.canceled) setMedia((current) => [...current, assetFrom(result.assets[0], 'camera')].slice(0, 3));
  }, []);

  useEffect(() => { if (camera === '1' && !openedCamera.current) { openedCamera.current = true; void takePhoto(); } }, [camera, takePhoto]);
  useEffect(() => { if (initialType) setType(initialType); }, [initialType]);

  const locate = async () => {
    setLocating(true);
    try {
      const permission = await Location.requestForegroundPermissionsAsync();
      if (!permission.granted) throw new Error('اسمح بالوصول إلى الموقع من إعدادات الجهاز.');
      const value = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      setCoordinates({ latitude: value.coords.latitude, longitude: value.coords.longitude });
      setLocationText(`موقعي الحالي (${value.coords.latitude.toFixed(5)}, ${value.coords.longitude.toFixed(5)})`);
      await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } catch (error) { Alert.alert('تعذر تحديد الموقع', error instanceof Error ? error.message : 'حاول مرة أخرى'); }
    finally { setLocating(false); }
  };

  const send = async () => {
    if (!description.trim() && !media.length) return Alert.alert('أضف تفاصيل أو صورة', 'لا يمكن إرسال بلاغ فارغ.');
    if (!session) return;
    setSending(true);
    try {
      const result = await submitReport({ token: session.token, type, description: description.trim(), locationText, latitude: coordinates?.latitude, longitude: coordinates?.longitude, media });
      void refreshReports();
      await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      setType(''); setDescription(''); setLocationText(''); setCoordinates(null); setMedia([]);
      Alert.alert('تم استلام البلاغ', `رقم البلاغ ${result.report_id}\nبدأ وكيل أمان AI بتحليل النص والصور.`, [
        { text: 'بلاغ جديد' },
        { text: 'متابعة البلاغ', onPress: () => router.push(`/report/${result.report_id}`) },
      ]);
    } catch (error) { Alert.alert('تعذر إرسال البلاغ', error instanceof Error ? error.message : 'تحقق من الاتصال وحاول مجدداً'); }
    finally { setSending(false); }
  };

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.page} keyboardShouldPersistTaps="handled" contentContainerStyle={styles.content}>
        <Brand compact />
        <View style={styles.heading}><Text style={styles.title}>إرسال بلاغ</Text><Text style={styles.subtitle}>كل معلومة واضحة تساعد فرق الاستجابة</Text></View>

        <SectionTitle title="نوع الحالة (اختياري)" />
        <View style={styles.aiTypeHint}><Ionicons name="sparkles" size={18} color={colors.purple} /><Text style={styles.aiTypeHintText}>اتركه بدون اختيار وسيحدده وكيل أمان AI من النص أو الصورة.</Text></View>
        <View style={styles.typeGrid}>{incidentTypes.map((item) => {
          const selected = item.key === type;
          return <Pressable key={item.key} onPress={() => { setType(selected ? '' : item.key); void Haptics.selectionAsync(); }} style={[styles.typeCard, selected && { borderColor: item.color, backgroundColor: item.soft }]}>
            <View style={[styles.typeIcon, { backgroundColor: item.soft }]}><Ionicons name={item.icon} size={24} color={item.color} /></View>
            <Text style={[styles.typeText, selected && { color: item.color }]}>{item.label}</Text>
            {selected && <Ionicons style={styles.check} name="checkmark-circle" size={18} color={item.color} />}
          </Pressable>;
        })}</View>

        <SectionTitle title="صف ما حدث" />
        <View style={styles.textArea}><TextInput value={description} onChangeText={setDescription} textAlign="right" multiline maxLength={1200} placeholder="مثال: يوجد دخان كثيف في الطابق الثاني..." placeholderTextColor="#98A5B7" style={styles.textInput} /><Text style={styles.counter}>{description.length}/1200</Text></View>

        <SectionTitle title="الصورة أو الدليل" />
        <View style={styles.mediaActions}>
          <Pressable onPress={takePhoto} style={styles.mediaButton}><Ionicons name="camera-outline" size={24} color={colors.primary} /><Text style={styles.mediaButtonText}>التقاط صورة</Text></Pressable>
          <Pressable onPress={choosePhotos} style={styles.mediaButton}><Ionicons name="images-outline" size={24} color={colors.primary} /><Text style={styles.mediaButtonText}>اختيار صور</Text></Pressable>
        </View>
        {!!media.length && <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.previews}>{media.map((item, index) => <View key={`${item.uri}-${index}`}><Image source={{ uri: item.uri }} style={styles.preview} /><Pressable onPress={() => setMedia((all) => all.filter((_, i) => i !== index))} style={styles.remove}><Ionicons name="close" color="#fff" size={15} /></Pressable></View>)}</ScrollView>}
        <View style={styles.privacyHint}><Ionicons name="eye-off-outline" size={17} color={colors.success} /><Text style={styles.privacyHintText}>تُطمس وجوه الأشخاص تلقائياً قبل حفظ الصورة في المنصة.</Text></View>
        <Text style={styles.mediaHint}>حتى 3 صور • يحلل الوكيل محتواها ووقت الالتقاط والجهاز وGPS إن كانت محفوظة</Text>

        <SectionTitle title="الموقع" />
        <Pressable onPress={locate} style={styles.locationCard}>
          <View style={[styles.locationIcon, coordinates && { backgroundColor: colors.successSoft }]}>{locating ? <ActivityIndicator color={colors.primary} /> : <Ionicons name={coordinates ? 'checkmark-circle' : 'locate-outline'} size={25} color={coordinates ? colors.success : colors.primary} />}</View>
          <View style={{ flex: 1 }}><Text style={styles.locationTitle}>{coordinates ? 'تم تحديد موقعك' : 'استخدم موقعي الحالي'}</Text><Text numberOfLines={1} style={styles.locationText}>{locationText || 'اضغط للسماح بالوصول إلى GPS'}</Text></View>
        </Pressable>
        <TextInput value={locationText} onChangeText={setLocationText} textAlign="right" placeholder="أو اكتب اسم المكان / أقرب معلم" placeholderTextColor="#98A5B7" style={styles.locationInput} />

        <View style={styles.notice}><Ionicons name="information-circle-outline" size={20} color={colors.primary} /><Text style={styles.noticeText}>الذكاء الاصطناعي يساند التقييم فقط. البلاغ لا يعني إرسال فرقة تلقائياً قبل مراجعة الجهة المختصة.</Text></View>
        <PrimaryButton title="إرسال البلاغ الآن" icon="send" loading={sending} onPress={send} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: colors.background }, content: { paddingHorizontal: 18, paddingTop: 58, paddingBottom: 120 },
  heading: { alignItems: 'flex-end', marginTop: 28, marginBottom: 26 }, title: { color: colors.ink, fontSize: 27, fontWeight: '900' }, subtitle: { color: colors.muted, marginTop: 5 },
  aiTypeHint: { flexDirection: 'row-reverse', alignItems: 'center', gap: 8, backgroundColor: '#F1EEFF', borderRadius: 14, padding: 11, marginBottom: 12 }, aiTypeHintText: { flex: 1, color: '#5B46B2', fontSize: 11, lineHeight: 17, textAlign: 'right', fontWeight: '700' },
  typeGrid: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 10, marginBottom: 28 }, typeCard: { width: '31%', minHeight: 112, borderWidth: 1, borderColor: colors.border, borderRadius: 19, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', gap: 8 }, typeIcon: { width: 44, height: 44, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }, typeText: { color: colors.ink, fontSize: 12, fontWeight: '800' }, check: { position: 'absolute', top: 7, right: 7 },
  textArea: { minHeight: 145, backgroundColor: '#fff', borderWidth: 1, borderColor: colors.border, borderRadius: 19, padding: 14, marginBottom: 28 }, textInput: { minHeight: 102, color: colors.ink, fontSize: 15, lineHeight: 23, textAlignVertical: 'top' }, counter: { color: colors.muted, fontSize: 10 },
  mediaActions: { flexDirection: 'row-reverse', gap: 10 }, mediaButton: { flex: 1, minHeight: 88, backgroundColor: '#fff', borderWidth: 1, borderStyle: 'dashed', borderColor: '#B9CDEE', borderRadius: 18, alignItems: 'center', justifyContent: 'center', gap: 7 }, mediaButtonText: { color: colors.primary, fontSize: 12, fontWeight: '800' }, mediaHint: { color: colors.muted, fontSize: 10, textAlign: 'right', marginTop: 8, marginBottom: 28 }, previews: { flexDirection: 'row-reverse', gap: 10, paddingTop: 12 }, preview: { width: 86, height: 86, borderRadius: 16 }, remove: { position: 'absolute', top: -6, right: -5, width: 25, height: 25, borderRadius: 13, backgroundColor: colors.danger, alignItems: 'center', justifyContent: 'center' },
  privacyHint: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7, backgroundColor: colors.successSoft, borderRadius: 13, paddingHorizontal: 11, paddingVertical: 9, marginTop: 10 }, privacyHintText: { flex: 1, color: colors.success, fontSize: 11, fontWeight: '800', textAlign: 'right' },
  locationCard: { flexDirection: 'row-reverse', alignItems: 'center', gap: 12, backgroundColor: '#fff', borderWidth: 1, borderColor: colors.border, borderRadius: 18, padding: 14 }, locationIcon: { width: 48, height: 48, borderRadius: 15, backgroundColor: colors.sky, alignItems: 'center', justifyContent: 'center' }, locationTitle: { color: colors.ink, fontWeight: '800', textAlign: 'right' }, locationText: { color: colors.muted, fontSize: 11, textAlign: 'right', marginTop: 4 }, locationInput: { height: 52, borderRadius: 15, borderWidth: 1, borderColor: colors.border, backgroundColor: '#fff', marginTop: 10, paddingHorizontal: 14, color: colors.ink },
  notice: { flexDirection: 'row-reverse', alignItems: 'flex-start', gap: 9, backgroundColor: colors.sky, borderRadius: 16, padding: 13, marginVertical: 22 }, noticeText: { flex: 1, textAlign: 'right', color: '#3B5B89', fontSize: 11, lineHeight: 18 },
});
