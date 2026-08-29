import { Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';
import type { Session } from './types';

const key = 'aman-ai-expo-session';

export async function loadSession(): Promise<Session | null> {
  try {
    const raw = Platform.OS === 'web' ? globalThis.localStorage?.getItem(key) : await SecureStore.getItemAsync(key);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}

export async function saveSession(session: Session | null) {
  if (Platform.OS === 'web') {
    if (session) globalThis.localStorage?.setItem(key, JSON.stringify(session));
    else globalThis.localStorage?.removeItem(key);
    return;
  }
  if (session) await SecureStore.setItemAsync(key, JSON.stringify(session));
  else await SecureStore.deleteItemAsync(key);
}

