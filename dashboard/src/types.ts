export interface StaffSession {
  token: string;
  department: string | null; // null = يشوف كل الجهات (Admin)
  is_admin: boolean;
  label: string;
}

export interface MediaExif {
  path?: string;
  filename?: string;
  captured_at?: string;
  device?: string;
  device_make?: string;
  device_model?: string;
  age_hours?: number;
  captured_at_status?: string;
  location_match?: string;
  distance_from_report_meters?: number;
  gps_latitude?: number;
  gps_longitude?: number;
}

export interface AgentAnalysis {
  intake: { selected_incident_type: string | null; confidence: number; summary: string; location_text: string };
  classification: { confirmed_incident_type: string; type_match: boolean | null; confidence: number; reason: string };
  severity: { priority: string; risk_score: number; reason: string; evidence: string[]; uncertainty: string };
  triage: { is_incident_report: boolean; incident_relevance: string; confidence: number; reason: string };
  location: { status: string; accessibility: string; location_risk: string; note: string };
  verification: { verified: boolean; confidence: number; status: string; reason: string };
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
    metadata_status: string;
    captured_at_status: string;
    location_match: string;
    metadata_note: string;
  };
  final: { recommended_action: string; department: string; urgency: string; reason: string; notify_citizen: boolean };
  notification: { citizen_message: string; agency_message: string };
}

export interface Report {
  report_id: string;
  user_id: string;
  type: string;
  description: string;
  latitude: number | null;
  longitude: number | null;
  location_text: string;
  media_paths: string[];
  media_exif: MediaExif[];
  voice_note_path: string | null;
  image_is_plausible?: boolean | null;
  image_authenticity_reason?: string | null;
  image_ai_generated_suspected?: boolean | null;
  image_ai_generated_reason?: string | null;
  confirmed_incident_type: string;
  priority: string;
  risk_score: number;
  department: string;
  status: string;
  /** حالة خط أنابيب الوكلاء: pending | processing | completed | failed.
   *  'failed' يعني أن البلاغ محفوظ لكن الوكلاء لم يصنّفوه — يحتاج مراجعة يدوية. */
  pipeline_status?: string | null;
  pipeline_attempts?: number | null;
  pipeline_last_error?: string | null;
  agent_analysis?: AgentAnalysis | null;
  agent_model?: string | null;
  agent_completed_at?: string | null;
  /** الموقع الإداري الحقيقي من الاستعلام الجغرافي (لا تخمين النموذج) */
  geo_wilayat?: string | null;
  geo_governorate?: string | null;
  geo_neighbourhood?: string | null;
  /** عدد البلاغات المستقلة الأخرى عن نفس الحادث */
  confirmation_count?: number;
  credibility?: { level: string; label: string; note: string };
  is_confirmation?: boolean;
  /** إشارات التحقق من صور البلاغ */
  media_verification?: Array<{
    path: string;
    has_exif: boolean;
    consistency_score: number;
    flags: Array<{ level: 'ok' | 'warning' | 'info'; message: string }>;
  }>;
  created_at: string;
  updated_at: string;
}
