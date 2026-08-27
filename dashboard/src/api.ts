import type { Report, StaffSession } from './types';

/// عنوان الباك-إند. اضبط VITE_API_BASE في dashboard/.env.local لتشغيله عبر رابط عام (نفق) أو جهاز مختلف.
export const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:4000';

export class AuthError extends Error {}

export async function staffLogin(code: string): Promise<StaffSession> {
  const res = await fetch(`${API_BASE}/api/auth/staff/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.message || 'تعذّر تسجيل الدخول');
  return { token: body.token, department: body.department, is_admin: body.is_admin, label: body.label };
}

export async function staffLogout(token: string): Promise<void> {
  await fetch(`${API_BASE}/api/auth/staff/logout`, {
    method: 'POST',
    headers: { 'x-staff-token': token },
  }).catch(() => {});
}

export async function fetchReports(token: string, department?: string): Promise<Report[]> {
  const url = new URL(`${API_BASE}/api/reports/staff`);
  if (department) url.searchParams.set('department', department);
  const res = await fetch(url, { headers: { 'x-staff-token': token } });
  if (res.status === 401) throw new AuthError('انتهت الجلسة، يرجى تسجيل الدخول مجددًا');
  if (!res.ok) throw new Error('تعذّر جلب البلاغات من الخادم');
  return res.json();
}

export async function updateReportStatus(token: string, reportId: string, status: string): Promise<Report> {
  const res = await fetch(`${API_BASE}/api/reports/${reportId}/status`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', 'x-staff-token': token },
    body: JSON.stringify({ status }),
  });
  if (res.status === 401) throw new AuthError('انتهت الجلسة، يرجى تسجيل الدخول مجددًا');
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.message || 'تعذّر تحديث حالة البلاغ');
  }
  return res.json();
}

/** البلاغات التي استنفدت محاولات خط الوكلاء وتحتاج مراجعة بشرية.
 *  لا تظهر بقائمة القسم لأن حقل department يبقى فارغًا عند فشل التصنيف. */
export async function fetchReportsNeedingReview(token: string): Promise<Report[]> {
  const res = await fetch(`${API_BASE}/api/reports/needs-review`, {
    headers: { 'x-staff-token': token },
  });
  if (res.status === 401) throw new AuthError('انتهت الجلسة، يرجى تسجيل الدخول مجددًا');
  if (!res.ok) throw new Error('تعذّر جلب البلاغات المتعثّرة');
  return res.json();
}

export function mediaUrl(path: string): string {
  return `${API_BASE}${path}`;
}
