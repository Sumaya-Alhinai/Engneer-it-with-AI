import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", { auth: { persistSession: false } });
const auth = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", { auth: { persistSession: false } });
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-user-token",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
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
  const citizenReport = { ...report };
  for (const internal of ["agent_analysis", "agent_model", "agent_response_id", "media_exif", "media_verification"]) delete citizenReport[internal];
  const analysis = report.agent_analysis && typeof report.agent_analysis === "object"
    ? report.agent_analysis as Record<string, Record<string, unknown>>
    : null;
  const citizenAi = analysis
    ? {
      triage: analysis.triage ?? null,
      classification: analysis.classification ?? null,
      severity: analysis.severity ?? null,
      image: analysis.image ?? null,
      final: analysis.final
        ? {
          recommended_action: analysis.final.recommended_action,
          urgency: analysis.final.urgency,
          reason: analysis.final.reason,
        }
        : null,
    }
    : null;
  return {
    ...citizenReport,
    report_id: report.public_code,
    media_paths: mediaPaths,
    media_exif: report.media_exif ?? [],
    citizen_ai: citizenAi,
    voice_note_path: storedVoice ? await signedPath(storedVoice) : null,
  };
}

function finiteNumber(value: unknown) {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : null;
}

function normalizedCaptureTime(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  const exifDate = value.trim().replace(
    /^(\d{4}):(\d{2}):(\d{2})\s/,
    "$1-$2-$3T",
  );
  const parsed = new Date(exifDate);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function distanceMeters(aLat: number, aLng: number, bLat: number, bLng: number) {
  const toRad = (value: number) => value * Math.PI / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(6_371_000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h)));
}

function sanitizeMediaMetadata(raw: unknown, reportLat: number | null, reportLng: number | null) {
  if (!raw || typeof raw !== "object") return null;
  const value = raw as Record<string, unknown>;
  const capturedAt = normalizedCaptureTime(value.captured_at);
  const gpsLatitude = finiteNumber(value.gps_latitude);
  const gpsLongitude = finiteNumber(value.gps_longitude);
  const capturedAtMs = capturedAt ? new Date(capturedAt).getTime() : null;
  const ageHours = capturedAtMs == null ? null : Math.round((Date.now() - capturedAtMs) / 3_600_000);
  const distance = reportLat != null && reportLng != null && gpsLatitude != null && gpsLongitude != null
    ? distanceMeters(reportLat, reportLng, gpsLatitude, gpsLongitude)
    : null;
  const text = (key: string, max = 120) =>
    typeof value[key] === "string" && value[key].trim()
      ? value[key].trim().slice(0, max)
      : null;
  return {
    filename: text("filename"),
    mime_type: text("mime_type", 60),
    file_size: finiteNumber(value.file_size),
    width: finiteNumber(value.width),
    height: finiteNumber(value.height),
    device_make: text("device_make", 80),
    device_model: text("device_model", 100),
    software: text("software", 100),
    captured_at: capturedAt,
    age_hours: ageHours,
    gps_latitude: gpsLatitude,
    gps_longitude: gpsLongitude,
    distance_from_report_meters: distance,
    location_match: distance == null ? "unknown" : distance <= 500 ? "match" : "mismatch",
    captured_at_status: ageHours == null ? "unknown" : ageHours < -1 ? "future" : ageHours <= 72 ? "recent" : "old",
    source: text("source", 40) ?? "expo_image_picker",
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

async function triggerPipeline(report: Record<string, unknown>) {
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  try {
    const response = await fetch(`${url}/functions/v1/report-agent`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${serviceRoleKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ report_id: report.public_code }),
      signal: AbortSignal.timeout(70_000),
    });
    // report-agent writes its own detailed/sanitized failure state before a
    // non-2xx response, so do not overwrite its attempt count or error here.
    if (!response.ok) return;
  } catch (error) {
    const message = error instanceof Error ? error.message : "تعذر تشغيل وكيل Aman AI";
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
    const { data, error } = await admin.from("reports").select("public_code, confirmed_incident_type, type, priority, status, department, geo_wilayat, geo_governorate, created_at").gte("created_at", since).not("priority", "is", null).neq("priority", "none").order("created_at", { ascending: false }).limit(50);
    if (error) return respond({ message: "تعذر جلب التنبيهات" }, 500);
    return respond((data ?? []).map((r) => ({ report_id: r.public_code, type: r.confirmed_incident_type ?? r.type, priority: r.priority, status: r.status, department: r.department, wilayat: r.geo_wilayat, governorate: r.geo_governorate, created_at: r.created_at })));
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
    if (!description && media.length === 0) return respond({ message: "البلاغ فارغ — أضف وصفًا أو صورة" }, 400);
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
    const latitude = form.get("latitude") ? Number(form.get("latitude")) : null;
    const longitude = form.get("longitude") ? Number(form.get("longitude")) : null;
    const rawMetadata = (() => {
      try {
        return JSON.parse(String(form.get("media_metadata") ?? "[]"));
      } catch {
        return [];
      }
    })();
    const mediaExif = Array.isArray(rawMetadata)
      ? rawMetadata.slice(0, media.length).map((entry) => sanitizeMediaMetadata(entry, latitude, longitude)).filter(Boolean)
      : [];
    const report = {
      public_code: code,
      user_id: userId,
      channel: "app",
      type: type || null,
      description,
      location_text: String(form.get("location_text") ?? ""),
      latitude,
      longitude,
      media_paths: mediaPaths,
      media_exif: mediaExif,
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
