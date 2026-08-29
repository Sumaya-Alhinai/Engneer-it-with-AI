export type Session = {
  token: string;
  userId: string;
  name: string;
  email?: string | null;
  isGuest: boolean;
};

export type MediaAsset = {
  uri: string;
  name: string;
  type: string;
  file?: Blob;
  metadata?: {
    filename?: string | null;
    mime_type?: string | null;
    file_size?: number | null;
    width?: number | null;
    height?: number | null;
    device_make?: string | null;
    device_model?: string | null;
    software?: string | null;
    captured_at?: string | null;
    gps_latitude?: number | null;
    gps_longitude?: number | null;
    source: 'camera' | 'library';
  };
};

export type MediaMetadata = {
  filename?: string | null;
  mime_type?: string | null;
  file_size?: number | null;
  width?: number | null;
  height?: number | null;
  device_make?: string | null;
  device_model?: string | null;
  captured_at?: string | null;
  age_hours?: number | null;
  gps_latitude?: number | null;
  gps_longitude?: number | null;
  distance_from_report_meters?: number | null;
  location_match?: 'match' | 'mismatch' | 'unknown';
  captured_at_status?: 'recent' | 'old' | 'future' | 'unknown';
};

export type MediaBlur = {
  success: boolean;
  processed: boolean;
  people_visible: boolean | null;
  faces: number;
  method: 'targeted' | 'full_image_fallback' | 'not_needed';
  reason: string;
};

export type CitizenAi = {
  triage?: { is_incident_report: boolean; incident_relevance: string; confidence: number; reason: string } | null;
  classification?: { confirmed_incident_type: string; confidence: number; reason: string } | null;
  severity?: { priority: string; risk_score: number; reason: string; evidence: string[]; uncertainty: string } | null;
  image?: { authenticity_reason: string; metadata_note: string; captured_at_status: string; location_match: string } | null;
  final?: { recommended_action: string; urgency: string; reason: string } | null;
};

export type Report = {
  report_id: string;
  public_code?: string;
  type?: string | null;
  confirmed_incident_type?: string | null;
  description?: string | null;
  location_text?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  status?: string | null;
  pipeline_status?: 'pending' | 'processing' | 'completed' | 'failed' | string;
  priority?: string | null;
  risk_score?: number | null;
  department?: string | null;
  ai_reason?: string | null;
  agent_completed_at?: string | null;
  media_paths?: string[];
  media_exif?: MediaMetadata[];
  media_blur?: MediaBlur[];
  citizen_ai?: CitizenAi | null;
  created_at?: string;
};

export type PublicAlert = Pick<Report, 'report_id' | 'type' | 'priority' | 'status' | 'department' | 'created_at'> & {
  wilayat?: string | null;
  governorate?: string | null;
};
