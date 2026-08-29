import type { MediaAsset, PublicAlert, Report, Session } from './types';

export const API_BASE = process.env.EXPO_PUBLIC_API_BASE_URL?.replace(/\/$/, '') ||
  'https://dwhvgxilxzmxatwejfmu.supabase.co/functions/v1/mobile-api';

async function parse(response: Response) {
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body?.message || 'تعذر الاتصال بخدمة أمان AI');
  return body;
}

export async function createGuest(): Promise<Session> {
  const body = await parse(await fetch(`${API_BASE}/api/auth/guest`, { method: 'POST' }));
  return { token: body.token, userId: body.user_id, name: 'ضيف', isGuest: true };
}

export async function login(email: string, password: string): Promise<Session> {
  const body = await parse(await fetch(`${API_BASE}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  }));
  return { token: body.token, userId: body.user_id, name: body.name || 'مستخدم أمان', email: body.email, isGuest: false };
}

export async function register(name: string, email: string, password: string) {
  return parse(await fetch(`${API_BASE}/api/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, email, password }),
  }));
}

export async function verify(email: string, code: string): Promise<Session> {
  const body = await parse(await fetch(`${API_BASE}/api/auth/verify-email`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, code }),
  }));
  return { token: body.token, userId: body.user_id, name: body.name || 'مستخدم أمان', email: body.email, isGuest: false };
}

export async function logout(token: string) {
  await fetch(`${API_BASE}/api/auth/logout`, { method: 'POST', headers: { 'x-user-token': token } }).catch(() => null);
}

export async function listReports(token: string): Promise<Report[]> {
  return parse(await fetch(`${API_BASE}/api/reports`, { headers: { 'x-user-token': token } }));
}

export async function getReport(token: string, id: string): Promise<Report> {
  return parse(await fetch(`${API_BASE}/api/reports/${encodeURIComponent(id)}`, { headers: { 'x-user-token': token } }));
}

export async function publicAlerts(): Promise<PublicAlert[]> {
  return parse(await fetch(`${API_BASE}/api/reports/public`));
}

export async function submitReport(input: {
  token: string;
  type?: string;
  description: string;
  locationText: string;
  latitude?: number;
  longitude?: number;
  media: MediaAsset[];
}): Promise<{ report_id: string }> {
  const form = new FormData();
  form.append('type', input.type ?? '');
  form.append('description', input.description);
  form.append('location_text', input.locationText);
  if (input.latitude != null) form.append('latitude', String(input.latitude));
  if (input.longitude != null) form.append('longitude', String(input.longitude));
  form.append('media_metadata', JSON.stringify(input.media.map((asset) => asset.metadata ?? null)));
  for (const asset of input.media) {
    if (asset.file) form.append('media', asset.file, asset.name);
    else form.append('media', { uri: asset.uri, name: asset.name, type: asset.type } as unknown as Blob);
  }
  return parse(await fetch(`${API_BASE}/api/reports`, {
    method: 'POST',
    headers: { 'x-user-token': input.token },
    body: form,
  }));
}
