import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-staff-token",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
};
const mediaBucket = "report-media";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});

function sessionToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function signedPath(path: string) {
  const { data, error } = await supabase.storage.from(mediaBucket).createSignedUrl(path, 60 * 60);
  return error ? "" : data.signedUrl;
}

async function reportForDashboard(report: Record<string, unknown>) {
  const storedMedia = Array.isArray(report.media_paths) ? report.media_paths.map(String) : [];
  const mediaPaths = (await Promise.all(storedMedia.map(signedPath))).filter(Boolean);
  const storedVoice = typeof report.voice_note_path === "string" ? report.voice_note_path : "";
  return {
    ...report,
    report_id: report.public_code,
    media_paths: mediaPaths,
    media_exif: report.media_exif ?? [],
    media_verification: report.media_verification ?? [],
    voice_note_path: storedVoice ? await signedPath(storedVoice) : null,
  };
}

async function requireStaff(request: Request) {
  const token = request.headers.get("x-staff-token");
  if (!token) return { error: json({ message: "مطلوب تسجيل دخول الموظف" }, 401) };

  const { data: session } = await supabase
    .from("staff_sessions")
    .select("staff_id, expires_at")
    .eq("token", token)
    .maybeSingle();

  if (!session || new Date(session.expires_at) <= new Date()) {
    return { error: json({ message: "انتهت الجلسة، يرجى تسجيل الدخول مجددًا" }, 401) };
  }

  const { data: staff } = await supabase
    .from("staff")
    .select("id, department, is_admin, label")
    .eq("id", session.staff_id)
    .maybeSingle();
  if (!staff) return { error: json({ message: "الجلسة غير صالحة" }, 401) };
  return { staff };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const url = new URL(request.url);
  const path = url.pathname.replace(/^\/staff-api/, "");

  if (request.method === "POST" && path === "/login") {
    const { code } = await request.json().catch(() => ({}));
    if (!code || typeof code !== "string") return json({ message: "أدخل رمز الدخول" }, 400);
    const { data: staff } = await supabase
      .from("staff")
      .select("id, department, is_admin, label")
      .eq("access_code", code.trim())
      .maybeSingle();
    if (!staff) return json({ message: "كود الدخول غير صحيح" }, 401);

    const token = sessionToken();
    const expiresAt = new Date(Date.now() + 12 * 60 * 60 * 1000).toISOString();
    const { error } = await supabase.from("staff_sessions").insert({
      token,
      staff_id: staff.id,
      expires_at: expiresAt,
    });
    if (error) return json({ message: "تعذر إنشاء جلسة الدخول" }, 500);
    return json({ token, department: staff.department, is_admin: staff.is_admin, label: staff.label });
  }

  if (request.method === "POST" && path === "/logout") {
    const token = request.headers.get("x-staff-token");
    if (token) await supabase.from("staff_sessions").delete().eq("token", token);
    return json({ message: "تم تسجيل الخروج" });
  }

  const { staff, error } = await requireStaff(request);
  if (error) return error;

  if (request.method === "GET" && path === "/reports") {
    const requestedDepartment = url.searchParams.get("department");
    const department = staff.is_admin ? requestedDepartment : staff.department;
    let query = supabase.from("reports").select("*").is("parent_report_id", null).order("created_at", { ascending: false });
    if (department) query = query.eq("department", department);
    const { data, error: queryError } = await query;
    if (queryError) return json({ message: "تعذر جلب البلاغات" }, 500);
    return json(await Promise.all((data ?? []).map(reportForDashboard)));
  }

  if (request.method === "GET" && path === "/reports/needs-review") {
    const { data, error: queryError } = await supabase
      .from("reports")
      .select("*")
      .eq("pipeline_status", "failed")
      .gte("pipeline_attempts", 5)
      .order("created_at", { ascending: false })
      .limit(100);
    if (queryError) return json({ message: "تعذر جلب البلاغات" }, 500);
    return json(await Promise.all((data ?? []).map(reportForDashboard)));
  }

  const statusMatch = path.match(/^\/reports\/([^/]+)\/status$/);
  if (request.method === "PATCH" && statusMatch) {
    const { status } = await request.json().catch(() => ({}));
    const allowed = new Set(["received", "verified", "dispatched", "in_progress", "resolved", "rejected", "flag_for_review"]);
    if (!allowed.has(status)) return json({ message: "حالة غير معروفة" }, 400);
    const { data, error: updateError } = await supabase
      .from("reports")
      .update({ status, updated_at: new Date().toISOString() })
      .eq("public_code", decodeURIComponent(statusMatch[1]))
      .select("*")
      .maybeSingle();
    if (updateError) return json({ message: "تعذر تحديث البلاغ" }, 500);
    if (!data) return json({ message: "البلاغ غير موجود" }, 404);
    return json(await reportForDashboard(data));
  }

  return json({ message: "المسار غير موجود" }, 404);
});
