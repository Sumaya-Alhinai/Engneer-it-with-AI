-- Evidence is private. Only the service-role Edge Functions can upload/read it;
-- staff and report owners receive short-lived signed URLs after custom-session checks.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-media',
  'report-media',
  false,
  15728640,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/wav', 'audio/webm', 'audio/ogg'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
