import { Ionicons } from '@expo/vector-icons';
import { Redirect, Tabs } from 'expo-router';
import { ActivityIndicator, View } from 'react-native';
import { useApp } from '@/src/app-context';
import { colors, shadow } from '@/src/theme';

const icons: Record<string, keyof typeof Ionicons.glyphMap> = {
  index: 'home-outline', report: 'megaphone-outline', tracking: 'navigate-circle-outline', assistant: 'sparkles-outline',
};

export default function TabsLayout() {
  const { ready, session } = useApp();
  if (!ready) return <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator color={colors.primary} /></View>;
  if (!session) return <Redirect href="/welcome" />;
  return (
    <Tabs screenOptions={({ route }) => ({
      headerShown: false,
      tabBarActiveTintColor: colors.primary,
      tabBarInactiveTintColor: '#8793A5',
      tabBarLabelStyle: { fontSize: 10, fontWeight: '700', marginTop: 2 },
      tabBarStyle: { height: 76, paddingBottom: 10, paddingTop: 8, borderTopWidth: 0, backgroundColor: '#fff', ...shadow },
      tabBarIcon: ({ color, focused }) => <Ionicons name={(focused ? icons[route.name]?.replace('-outline', '') : icons[route.name]) as keyof typeof Ionicons.glyphMap} size={24} color={color} />,
    })}>
      <Tabs.Screen name="index" options={{ title: 'الرئيسية' }} />
      <Tabs.Screen name="report" options={{ title: 'بلاغ' }} />
      <Tabs.Screen name="tracking" options={{ title: 'تتبع' }} />
      <Tabs.Screen name="assistant" options={{ title: 'المساعد' }} />
    </Tabs>
  );
}
