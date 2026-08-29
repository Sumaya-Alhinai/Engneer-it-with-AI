alter table public.reports
  add column if not exists agent_analysis jsonb,
  add column if not exists agent_model text,
  add column if not exists agent_response_id text,
  add column if not exists agent_completed_at timestamptz;

comment on column public.reports.agent_analysis is
  'Structured Aman AI triage results. Recommendations only; not proof of dispatch or notification.';

create index if not exists idx_reports_agent_completed_at
  on public.reports (agent_completed_at desc)
  where agent_completed_at is not null;
