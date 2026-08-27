export interface StaffSession {
  token: string;
  department: string | null; // null = يشوف كل الجهات (Admin)
  is_admin: boolean;
  label: string;
}

export interface MediaExif {
  path: string;
  captured_at?: string;
  device?: string;
  gps_latitude?: number;
  gps_longitude?: number;
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
