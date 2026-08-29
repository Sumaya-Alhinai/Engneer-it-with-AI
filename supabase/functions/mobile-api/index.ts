import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", { auth: { persistSession: false } });
const auth = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", { auth: { persistSession: false } });
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-user-token, x-webhook-secret",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
};
const mediaBucket = "report-media";
const maxMediaFiles = 5;
const maxImageBytes = 10 * 1024 * 1024;
const maxAudioBytes = 15 * 1024 * 1024;
const imageTypes = new Set(["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]);
const audioTypes = new Set(["audio/mpeg", "audio/mp4", "audio/aac", "audio/wav", "audio/webm", "audio/ogg"]);
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
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

async function signedPath(path: string) {
  const { data, error } = await admin.storage.from(mediaBucket).createSignedUrl(path, 60 * 60);
  return error ? "" : data.signedUrl;
}

async function appReport(report: Record<string, unknown>) {
  const storedMedia = Array.isArray(report.media_paths) ? report.media_paths.map(String) : [];
  const mediaPaths = (await Promise.all(storedMedia.map(signedPath))).filter(Boolean);
  const storedVoice = typeof report.voice_note_path === "string" ? report.voice_note_path : "";
  return {
    ...report,
    report_id: report.public_code,
    media_paths: mediaPaths,
    media_exif: report.media_exif ?? [],
    voice_note_path: storedVoice ? await signedPath(storedVoice) : null,
  };
}

function safeFilename(name: string) {
  const extension = name.toLowerCase().match(/\.[a-z0-9]{1,5}$/)?.[0] ?? "";
  return `${random(12)}${extension}`;
}

async function uploadFile(code: string, folder: "images" | "voice", file: File, allowed: Set<string>, maxBytes: number) {
  if (!allowed.has(file.type.toLowerCase())) throw new Error("UNSUPPORTED_MEDIA_TYPE");
  if (file.size > maxBytes) throw new Error("MEDIA_TOO_LARGE");
  const path = `${code}/${folder}/${safeFilename(file.name)}`;
  const { error } = await admin.storage.from(mediaBucket).upload(path, file, {
    contentType: file.type,
    upsert: false,
  });
  if (error) throw new Error(`UPLOAD_FAILED:${error.message}`);
  return path;
}

function constantTimeEqual(left: string, right: string) {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return difference === 0;
}

async function triggerPipeline(report: Record<string, unknown>) {
  const webhookUrl = Deno.env.get("N8N_WEBHOOK_URL") ?? "";
  if (!webhookUrl) {
    await admin.from("reports").update({ pipeline_status: "failed", pipeline_attempts: 0, pipeline_last_error: "N8N_WEBHOOK_URL غير مضبوط" }).eq("public_code", report.public_code);
    return;
  }
  await admin.from("reports").update({ pipeline_status: "processing", pipeline_attempts: 1, pipeline_last_error: null }).eq("public_code", report.public_code);
  const media = Array.isArray(report.media_paths) ? report.media_paths.map(String) : [];
  const imageUrl = media.length ? await signedPath(media[0]) : "";
  try {
    const response = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        report_id: report.public_code,
        user_id: report.user_id,
        type: report.type,
        description: report.description,
        location_text: report.location_text,
        latitude: report.latitude,
        longitude: report.longitude,
        image_url: imageUrl,
        has_camera_exif: false,
      }),
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) throw new Error(`n8n HTTP ${response.status}`);
    // وصول نتيجة الوكلاء عبر PATCH هو الذي يضع completed. إبقاؤها processing هنا
    // يمنع اعتبار مجرد قبول الـ webhook تصنيفًا ناجحًا.
  } catch (error) {
    const message = error instanceof Error ? error.message : "تعذر الوصول إلى n8n";
    await admin.from("reports").update({ pipeline_status: "failed", pipeline_attempts: 1, pipeline_last_error: message.slice(0, 500) }).eq("public_code", report.public_code);
  }
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

  const classification = path.match(/^\/api\/reports\/([^/]+)\/classification$/);
  if (request.method === "PATCH" && classification) {
    const secret = Deno.env.get("N8N_CALLBACK_SECRET") ?? "";
    if (!secret) return respond({ message: "N8N_CALLBACK_SECRET غير مضبوط" }, 503);
    if (!constantTimeEqual(request.headers.get("x-webhook-secret") ?? "", secret)) return respond({ message: "غير مصرّح" }, 401);
    const body = await request.json().catch(() => ({}));
    const allowed = ["confirmed_incident_type", "department", "priority", "risk_score", "verification_status", "location_status", "ai_reason", "image_is_plausible", "image_authenticity_reason", "image_ai_generated_suspected", "image_ai_generated_reason", "status"];
    const update: Record<string, unknown> = {};
    for (const key of allowed) if (body[key] !== undefined && body[key] !== null) update[key] = body[key];
    if (typeof update.risk_score === "number") update.risk_score = Math.max(0, Math.min(100, Math.round(update.risk_score)));
    if (!Object.keys(update).length) return respond({ message: "لا يوجد تحديث لتطبيقه" }, 400);
    Object.assign(update, { pipeline_status: "completed", pipeline_last_error: null, pipeline_next_retry_at: null, updated_at: new Date().toISOString() });
    const { data, error } = await admin.from("reports").update(update).eq("public_code", decodeURIComponent(classification[1])).select("*").maybeSingle();
    if (error) return respond({ message: "تعذر حفظ نتيجة الوكلاء" }, 500);
    return data ? respond(await appReport(data)) : respond({ message: "البلاغ غير موجود" }, 404);
  }

  const required = await requireUser(request);
  if (required.error) return required.error;

  if (request.method === "POST" && path === "/api/reports") {
    const form = await request.formData().catch(() => null);
    if (!form) return respond({ message: "صيغة البلاغ غير صالحة" }, 400);
    const code = reportCode();
    const userId = required.session.user_public_id;
    const media = form.getAll("media").filter((value): value is File => value instanceof File && value.size > 0);
    const voice = form.get("voice_note");
    const description = String(form.get("description") ?? "").trim();
    const type = String(form.get("type") ?? "").trim();
    if (!description && !type && media.length === 0) return respond({ message: "البلاغ فارغ — أضف وصفًا أو نوع الحادث أو صورة" }, 400);
    if (media.length > maxMediaFiles) return respond({ message: `الحد الأقصى ${maxMediaFiles} صور لكل بلاغ` }, 400);

    const uploaded: string[] = [];
    try {
      for (const file of media) uploaded.push(await uploadFile(code, "images", file, imageTypes, maxImageBytes));
      if (voice instanceof File && voice.size > 0) uploaded.push(await uploadFile(code, "voice", voice, audioTypes, maxAudioBytes));
    } catch (error) {
      if (uploaded.length) await admin.storage.from(mediaBucket).remove(uploaded);
      const reason = error instanceof Error ? error.message : "";
      if (reason === "UNSUPPORTED_MEDIA_TYPE") return respond({ message: "نوع الملف المرفوع غير مدعوم" }, 400);
      if (reason === "MEDIA_TOO_LARGE") return respond({ message: "حجم الملف المرفوع أكبر من الحد المسموح" }, 413);
      return respond({ message: "تعذر حفظ المرفق" }, 500);
    }
    const mediaPaths = uploaded.slice(0, media.length);
    const voiceNotePath = uploaded.length > media.length ? uploaded.at(-1) : null;
    const report = {
      public_code: code,
      user_id: userId,
      channel: "app",
      type: type || "other",
      description,
      location_text: String(form.get("location_text") ?? ""),
      latitude: form.get("latitude") ? Number(form.get("latitude")) : null,
      longitude: form.get("longitude") ? Number(form.get("longitude")) : null,
      media_paths: mediaPaths,
      voice_note_path: voiceNotePath,
      status: "received",
      pipeline_status: "pending",
    };
    const { error } = await admin.from("reports").insert(report);
    if (error) {
      if (uploaded.length) await admin.storage.from(mediaBucket).remove(uploaded);
      return respond({ message: "تعذر حفظ البلاغ" }, 500);
    }
    EdgeRuntime.waitUntil(triggerPipeline(report));
    return respond({ report_id: code, user_id: userId, department: "", priority: "" });
  }

  if (request.method === "GET" && path === "/api/reports") {
    const { data, error } = await admin.from("reports").select("*").eq("user_id", required.session.user_public_id).order("created_at", { ascending: false }).limit(100);
    if (error) return respond({ message: "تعذر جلب البلاغات" }, 500);
    return respond(await Promise.all((data ?? []).map(appReport)));
  }

  const oneReport = path.match(/^\/api\/reports\/([^/]+)$/);
  if (request.method === "GET" && oneReport) {
    const { data } = await admin.from("reports").select("*").eq("public_code", decodeURIComponent(oneReport[1])).eq("user_id", required.session.user_public_id).maybeSingle();
    return data ? respond(await appReport(data)) : respond({ message: "البلاغ غير موجود" }, 404);
  }

  return respond({ message: "المسار غير موجود" }, 404);
});
