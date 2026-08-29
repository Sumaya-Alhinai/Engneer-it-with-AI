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
  created_at?: string;
};

export type PublicAlert = Pick<Report, 'report_id' | 'type' | 'priority' | 'status' | 'department' | 'created_at'> & {
  wilayat?: string | null;
  governorate?: string | null;
};

