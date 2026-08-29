import { analysisToReportUpdate } from "./analysis.ts";

Deno.test("maps structured analysis without self-authorizing dispatch", () => {
  const analysis = {
    intake: {
      selected_incident_type: "fire",
      confidence: 0.9,
      summary: "حريق",
      location_text: "السيب",
    },
    classification: {
      confirmed_incident_type: "fire",
      type_match: true,
      confidence: 0.95,
      reason: "متسق",
    },
    severity: {
      priority: "critical" as const,
      risk_score: 120,
      reason: "خطر مباشر",
    },
    location: {
      status: "valid" as const,
      accessibility: "easy" as const,
      location_risk: "high" as const,
      note: "واضح",
    },
    verification: {
      verified: true,
      confidence: 0.9,
      status: "verified" as const,
      reason: "أدلة كافية",
    },
    image: {
      analyzed: false,
      detected_incident_type: null,
      confidence: null,
      severity_indicators: "",
      is_photo_plausible: null,
      authenticity_reason: "",
      matches_reported_type: null,
      ai_generated_suspected: null,
      ai_generated_reason: "",
    },
    final: {
      recommended_action: "dispatch" as const,
      department: "Civil Defense" as const,
      urgency: "critical" as const,
      reason: "يحتاج استجابة",
      notify_citizen: true,
    },
    notification: {
      citizen_message: "تم استلام البلاغ",
      agency_message: "بلاغ جديد",
    },
  };
  const update = analysisToReportUpdate(analysis, "test-model", "resp_test");
  if (update.risk_score !== 100) throw new Error("risk_score must be clamped");
  if ("status" in update) {
    throw new Error("AI recommendation must not change operational status");
  }
  if (update.pipeline_status !== "completed") {
    throw new Error("pipeline should complete");
  }
});
