import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", { auth: { persistSession: false } });
const auth = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", { auth: { persistSession: false } });
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-user-token",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const random = (length = 16) => Array.from(crypto.getRandomValues(new Uint8Array(length)), (n) => n.toString(16).padStart(2, "0")).join("");
const reportCode = () => `AMN-${random(5).toUpperCase()}`;
const publicId = () => `USR-${random(6).toUpperCase()}`;
const guestId = () => `GUEST-${random(6).toUpperCase()}`;

async function issueSession(userPublicId: string, isGuest: boolean) {
  const token = random(32);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const { error } = await admin.from("user_sessions").insert({ token, user_public_id: userPublicId, is_guest: isGuest, expires_at: expiresAt });
  if (error) throw new Error("تعذر إنشاء جلسة التطبيق");
  return token;
}

async function requireUser(request: Request) {
  const token = request.headers.get("x-user-token");
  if (!token) return { error: respond({ message: "مطلوب تسجيل الدخول" }, 401) };
  const { data } = await admin.from("user_sessions").select("user_public_id, is_guest, expires_at").eq("token", token).maybeSingle();
  if (!data || new Date(data.expires_at) <= new Date()) return { error: respond({ message: "انتهت الجلسة، سجّل الدخول مجددًا" }, 401) };
  return { session: data };
}

function appReport(report: Record<string, unknown>) {
  return { ...report, report_id: report.public_code, media_paths: report.media_paths ?? [], media_exif: report.media_exif ?? [] };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: cors });
  const urlObject = new URL(request.url);
  const path = urlObject.pathname.replace(/^\/mobile-api/, "");

  if (request.method === "POST" && path === "/api/auth/guest") {
    const userId = guestId();
    const token = await issueSession(userId, true);
    return respond({ token, user_id: userId, is_guest: true });
  }

  if (request.method === "POST" && path === "/api/auth/register") {
    const body = await request.json().catch(() => ({}));
    if (!body.email || !body.name || !body.password) return respond({ message: "التسجيل بالبريد الإلكتروني مطلوب حاليًا" }, 400);
    if (String(body.password).length < 8) return respond({ message: "كلمة المرور يجب أن تكون 8 أحرف على الأقل" }, 400);
    const { data: existing } = await admin.from("users").select("id, is_verified").eq("email", String(body.email).toLowerCase()).maybeSingle();
    if (existing?.is_verified) return respond({ message: "هذا الحساب مسجل مسبقًا" }, 409);
    if (!existing) {
      const created = await admin.auth.admin.createUser({ email: String(body.email).toLowerCase(), password: String(body.password), email_confirm: false, user_metadata: { name: String(body.name) } });
      if (created.error) return respond({ message: created.error.message }, 400);
      const { error } = await admin.from("users").insert({ public_id: publicId(), name: String(body.name), email: String(body.email).toLowerCase(), password_hash: "supabase-auth", is_verified: false });
      if (error) return respond({ message: "تعذر إنشاء الحساب" }, 500);
    }
    const resend = await auth.auth.resend({ type: "signup", email: String(body.email).toLowerCase() });
    if (resend.error) return respond({ message: "تعذر إرسال رمز التحقق" }, 502);
    return respond({ message: "تم إنشاء الحساب، تحقق من رمز التفعيل" });
  }

  if (request.method === "POST" && path === "/api/auth/verify-email") {
    const body = await request.json().catch(() => ({}));
    if (!body.email || !body.code) return respond({ message: "البريد ورمز التحقق مطلوبان" }, 400);
    const verified = await auth.auth.verifyOtp({ email: String(body.email).toLowerCase(), token: String(body.code), type: "email" });
    if (verified.error) return respond({ message: "رمز التحقق غير صحيح أو منتهي" }, 400);
    const { data: user } = await admin.from("users").update({ is_verified: true }).eq("email", String(body.email).toLowerCase()).select("public_id, name, email, phone").maybeSingle();
    if (!user) return respond({ message: "الحساب غير موجود" }, 404);
    const token = await issueSession(user.public_id, false);
    return respond({ token, user_id: user.public_id, name: user.name, email: user.email, phone: user.phone });
  }

  if (request.method === "POST" && path === "/api/auth/resend-code") {
    const body = await request.json().catch(() => ({}));
    if (!body.email) return respond({ message: "البريد الإلكتروني مطلوب" }, 400);
    const result = await auth.auth.resend({ type: "signup", email: String(body.email).toLowerCase() });
    return result.error ? respond({ message: "تعذر إرسال رمز جديد" }, 502) : respond({ message: "تم إرسال رمز جديد" });
  }

  if (request.method === "POST" && path === "/api/auth/login") {
    const body = await request.json().catch(() => ({}));
    if (!body.email || !body.password) return respond({ message: "البريد الإلكتروني وكلمة المرور مطلوبان" }, 400);
    const signedIn = await auth.auth.signInWithPassword({ email: String(body.email).toLowerCase(), password: String(body.password) });
    if (signedIn.error) return respond({ message: "بيانات الدخول غير صحيحة" }, 400);
    const { data: user } = await admin.from("users").select("public_id, name, email, phone, is_verified").eq("email", String(body.email).toLowerCase()).maybeSingle();
    if (!user) return respond({ message: "الحساب غير موجود" }, 404);
    if (!user.is_verified) return respond({ code: "EMAIL_NOT_VERIFIED", email: user.email, phone: user.phone, message: "الحساب غير مفعل بعد" }, 403);
    const token = await issueSession(user.public_id, false);
    return respond({ token, user_id: user.public_id, name: user.name, email: user.email, phone: user.phone });
  }

  if (request.method === "POST" && path === "/api/auth/logout") {
    const token = request.headers.get("x-user-token");
    if (token) await admin.from("user_sessions").delete().eq("token", token);
    return respond({ message: "تم تسجيل الخروج" });
  }

  if (request.method === "GET" && path === "/api/reports/public") {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { data, error } = await admin.from("reports").select("public_code, confirmed_incident_type, type, priority, status, department, geo_wilayat, geo_governorate, created_at").gte("created_at", since).order("created_at", { ascending: false }).limit(50);
    if (error) return respond({ message: "تعذر جلب التنبيهات" }, 500);
    return respond((data ?? []).map((r) => ({ report_id: r.public_code, type: r.confirmed_incident_type ?? r.type, priority: r.priority, status: r.status, department: r.department, wilayat: r.geo_wilayat, governorate: r.geo_governorate, created_at: r.created_at })));
  }

  const required = await requireUser(request);
  if (required.error) return required.error;

  if (request.method === "POST" && path === "/api/reports") {
    const form = await request.formData();
    const code = reportCode();
    const userId = required.session.user_public_id;
    const { error } = await admin.from("reports").insert({
      public_code: code,
      user_id: userId,
      channel: "app",
      type: String(form.get("type") ?? "other"),
      description: String(form.get("description") ?? ""),
      location_text: String(form.get("location_text") ?? ""),
      latitude: form.get("latitude") ? Number(form.get("latitude")) : null,
      longitude: form.get("longitude") ? Number(form.get("longitude")) : null,
      status: "received",
      pipeline_status: "pending",
    });
    if (error) return respond({ message: "تعذر حفظ البلاغ" }, 500);
    return respond({ report_id: code, user_id: userId, department: "", priority: "" });
  }

  if (request.method === "GET" && path === "/api/reports") {
    const { data, error } = await admin.from("reports").select("*").eq("user_id", required.session.user_public_id).order("created_at", { ascending: false }).limit(100);
    if (error) return respond({ message: "تعذر جلب البلاغات" }, 500);
    return respond((data ?? []).map(appReport));
  }

  const oneReport = path.match(/^\/api\/reports\/([^/]+)$/);
  if (request.method === "GET" && oneReport) {
    const { data } = await admin.from("reports").select("*").eq("public_code", decodeURIComponent(oneReport[1])).eq("user_id", required.session.user_public_id).maybeSingle();
    return data ? respond(appReport(data)) : respond({ message: "البلاغ غير موجود" }, 404);
  }

  return respond({ message: "المسار غير موجود" }, 404);
});
