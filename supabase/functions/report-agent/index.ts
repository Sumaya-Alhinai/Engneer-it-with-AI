import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { analysisToReportUpdate } from "./analysis.ts";
import { analyzeReport } from "./openai.ts";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const admin = createClient(
  url,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const mediaBucket = "report-media";
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });

function isServiceRoleRequest(request: Request) {
  const provided = (request.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const a = new TextEncoder().encode(provided);
  const b = new TextEncoder().encode(expected);
  let difference = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return expected.length > 0 && difference === 0;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ message: "الطريقة غير مدعومة" }, 405);
  }
  // Gateway JWT verification alone only proves that *a* Supabase user exists.
  // This function can spend OpenAI credits and read private evidence, so only
  // the service-role caller (mobile-api/staff-api) may invoke it.
  if (!isServiceRoleRequest(request)) return json({ message: "غير مصرّح" }, 401);
  const body = await request.json().catch(() => ({}));
  const reportId = typeof body.report_id === "string"
    ? body.report_id.trim()
    : "";
  if (!reportId) return json({ message: "report_id مطلوب" }, 400);

  const { data: report, error: readError } = await admin.from("reports").select(
    "*",
  ).eq("public_code", reportId).maybeSingle();
  if (readError) return json({ message: "تعذر قراءة البلاغ" }, 500);
  if (!report) return json({ message: "البلاغ غير موجود" }, 404);
  if (report.pipeline_status === "completed" && !body.force) {
    return json({
      report_id: reportId,
      pipeline_status: "completed",
      already_processed: true,
    });
  }

  const attempts = Number(report.pipeline_attempts ?? 0) + 1;
  await admin.from("reports").update({
    pipeline_status: "processing",
    pipeline_attempts: attempts,
    pipeline_last_error: null,
    updated_at: new Date().toISOString(),
  }).eq("public_code", reportId);

  try {
    const storedMedia = Array.isArray(report.media_paths)
      ? report.media_paths.map(String)
      : [];
    const imageUrls = (await Promise.all(
      storedMedia.slice(0, 3).map(async (path: string) => {
        const { data } = await admin.storage.from(mediaBucket)
          .createSignedUrl(path, 15 * 60);
        return data?.signedUrl ?? "";
      }),
    )).filter(Boolean);
    const exif = Array.isArray(report.media_exif) ? report.media_exif : [];
    const coordinates = report.latitude != null && report.longitude != null
      ? { latitude: Number(report.latitude), longitude: Number(report.longitude) }
      : null;
    const result = await analyzeReport({
      report_id: report.public_code,
      user_id: report.user_id,
      selected_type: report.type || null,
      description: report.description || report.report_text || "",
      location_text: report.location_text || "",
      has_coordinates: coordinates !== null,
      coordinates,
      image_urls: imageUrls,
      image_metadata: exif.slice(0, 3),
    });
    const update = analysisToReportUpdate(
      result.analysis,
      result.model,
      result.responseId,
    );
    const { error: updateError } = await admin.from("reports").update(update)
      .eq("public_code", reportId);
    if (updateError) throw new Error("DATABASE_UPDATE_FAILED");
    return json({
      report_id: reportId,
      pipeline_status: "completed",
      recommended_action: result.analysis.final.recommended_action,
    });
  } catch (error) {
    const raw = error instanceof Error ? error.message : "AGENT_FAILED";
    const safeError = raw.replace(/sk-[A-Za-z0-9_-]+/g, "[redacted]").slice(
      0,
      500,
    );
    await admin.from("reports").update({
      pipeline_status: "failed",
      pipeline_attempts: attempts,
      pipeline_last_error: safeError,
      updated_at: new Date().toISOString(),
    }).eq("public_code", reportId);
    return json({ message: "تعذر تشغيل وكيل Aman AI", code: safeError }, 502);
  }
});
