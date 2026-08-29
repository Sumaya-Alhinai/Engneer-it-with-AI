alter table public.reports
  drop constraint if exists reports_priority_check;

alter table public.reports
  add constraint reports_priority_check
  check (
    priority is null
    or priority in ('critical', 'high', 'medium', 'low', 'none')
  );

comment on column public.reports.priority is
  'Agent-recommended urgency. none means the evidence is not an incident report; it never changes operational status automatically.';
