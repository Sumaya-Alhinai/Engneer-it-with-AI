import { Redirect } from 'expo-router';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { Brand } from '@/src/components';
import { useApp } from '@/src/app-context';
import { colors } from '@/src/theme';

export default function Index() {
  const { ready, session } = useApp();
  if (ready) return <Redirect href={session ? '/(tabs)' : '/welcome'} />;
  return <View style={styles.root}><Brand /><ActivityIndicator style={{ marginTop: 30 }} color={colors.primary} /></View>;
}
const styles = StyleSheet.create({ root: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background } });

