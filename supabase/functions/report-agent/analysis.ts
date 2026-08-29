export type ReportAnalysis = {
  intake: {
    selected_incident_type: string;
    confidence: number;
    summary: string;
    location_text: string;
  };
  classification: {
    confirmed_incident_type: string;
    type_match: boolean;
    confidence: number;
    reason: string;
  };
  severity: {
    priority: "critical" | "high" | "medium" | "low";
    risk_score: number;
    reason: string;
  };
  location: {
    status: "valid" | "incomplete" | "invalid";
    accessibility: "easy" | "difficult" | "unknown";
    location_risk: "high" | "medium" | "low" | "unknown";
    note: string;
  };
  verification: {
    verified: boolean;
    confidence: number;
    status: "verified" | "needs_review" | "rejected";
    reason: string;
  };
  image: {
    analyzed: boolean;
    detected_incident_type: string | null;
    confidence: number | null;
    severity_indicators: string;
    is_photo_plausible: boolean | null;
    authenticity_reason: string;
    matches_reported_type: boolean | null;
    ai_generated_suspected: boolean | null;
    ai_generated_reason: string;
  };
  final: {
    recommended_action:
      | "dispatch"
      | "monitor"
      | "request_more_information"
      | "reject";
    department:
      | "Police"
      | "Ambulance"
      | "Civil Defense"
      | "Multiple Agencies"
      | "Manual Review";
    urgency: "critical" | "high" | "medium" | "low";
    reason: string;
    notify_citizen: boolean;
  };
  notification: {
    citizen_message: string;
    agency_message: string;
  };
};

export const reportAnalysisSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "intake",
    "classification",
    "severity",
    "location",
    "verification",
    "image",
    "final",
    "notification",
  ],
  properties: {
    intake: objectSchema({
      selected_incident_type: incidentTypeSchema(),
      confidence: scoreSchema(),
      summary: { type: "string" },
      location_text: { type: "string" },
    }),
    classification: objectSchema({
      confirmed_incident_type: incidentTypeSchema(),
      type_match: { type: "boolean" },
      confidence: scoreSchema(),
      reason: { type: "string" },
    }),
    severity: objectSchema({
      priority: { type: "string", enum: ["critical", "high", "medium", "low"] },
      risk_score: { type: "integer", minimum: 0, maximum: 100 },
      reason: { type: "string" },
    }),
    location: objectSchema({
      status: { type: "string", enum: ["valid", "incomplete", "invalid"] },
      accessibility: { type: "string", enum: ["easy", "difficult", "unknown"] },
      location_risk: {
        type: "string",
        enum: ["high", "medium", "low", "unknown"],
      },
      note: { type: "string" },
    }),
    verification: objectSchema({
      verified: { type: "boolean" },
      confidence: scoreSchema(),
      status: {
        type: "string",
        enum: ["verified", "needs_review", "rejected"],
      },
      reason: { type: "string" },
    }),
    image: objectSchema({
      analyzed: { type: "boolean" },
      detected_incident_type: {
        type: ["string", "null"],
        enum: [
          "traffic_accident",
          "fire",
          "medical",
          "flood",
          "road_block",
          "security",
          "other",
          null,
        ],
      },
      confidence: { type: ["number", "null"], minimum: 0, maximum: 1 },
      severity_indicators: { type: "string" },
      is_photo_plausible: { type: ["boolean", "null"] },
      authenticity_reason: { type: "string" },
      matches_reported_type: { type: ["boolean", "null"] },
      ai_generated_suspected: { type: ["boolean", "null"] },
      ai_generated_reason: { type: "string" },
    }),
    final: objectSchema({
      recommended_action: {
        type: "string",
        enum: ["dispatch", "monitor", "request_more_information", "reject"],
      },
      department: {
        type: "string",
        enum: [
          "Police",
          "Ambulance",
          "Civil Defense",
          "Multiple Agencies",
          "Manual Review",
        ],
      },
      urgency: { type: "string", enum: ["critical", "high", "medium", "low"] },
      reason: { type: "string" },
      notify_citizen: { type: "boolean" },
    }),
    notification: objectSchema({
      citizen_message: { type: "string" },
      agency_message: { type: "string" },
    }),
  },
};

function objectSchema(properties: Record<string, unknown>) {
  return {
    type: "object",
    additionalProperties: false,
    required: Object.keys(properties),
    properties,
  };
}

function scoreSchema() {
  return { type: "number", minimum: 0, maximum: 1 };
}

function incidentTypeSchema() {
  return {
    type: "string",
    enum: [
      "traffic_accident",
      "fire",
      "medical",
      "flood",
      "road_block",
      "security",
      "other",
    ],
  };
}

export function analysisToReportUpdate(
  analysis: ReportAnalysis,
  model: string,
  responseId: string,
) {
  return {
    confirmed_incident_type: analysis.classification.confirmed_incident_type,
    priority: analysis.severity.priority,
    risk_score: Math.max(
      0,
      Math.min(100, Math.round(analysis.severity.risk_score)),
    ),
    department: analysis.final.department,
    verification_status: analysis.verification.status,
    location_status: analysis.location.status,
    ai_reason: analysis.final.reason,
    image_is_plausible: analysis.image.is_photo_plausible,
    image_authenticity_reason: analysis.image.authenticity_reason || null,
    image_ai_generated_suspected: analysis.image.ai_generated_suspected,
    image_ai_generated_reason: analysis.image.ai_generated_reason || null,
    agent_analysis: analysis,
    agent_model: model,
    agent_response_id: responseId,
    agent_completed_at: new Date().toISOString(),
    pipeline_status: "completed",
    pipeline_last_error: null,
    pipeline_next_retry_at: null,
    updated_at: new Date().toISOString(),
  };
}
