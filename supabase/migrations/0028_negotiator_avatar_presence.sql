-- supabase/migrations/0028_negotiator_avatar_presence.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0027.
--
-- avatar_url: public URL (not a path -- ProfileRepository.uploadAvatar
-- resolves and stores the full public URL at upload time, since the
-- avatar-photos bucket below is public, unlike listing-photos/
-- requirement-photos which store paths and resolve them via a short-lived
-- signed URL on read). Nullable -- absent means no photo uploaded yet, UI
-- falls back to an initials avatar, never a fabricated placeholder image.
--
-- last_seen_at: updated by the client itself (on app resume + a periodic
-- heartbeat while active, see Task 5). Nullable -- a negotiator who has
-- never triggered a heartbeat reads as offline, never "online" by default.
alter table negotiator add column if not exists avatar_url text;
alter table negotiator add column if not exists last_seen_at timestamptz;

-- Additive only -- no prior REVOKE statement, per 0012_settings.sql's own
-- established reasoning: Postgres GRANT is additive and does not reset
-- prior column grants, so there is no need to (and real danger in trying
-- to) restate the full existing UPDATE column list. The existing 10-column
-- grant (full_name, ic_number, phone_number, ren_number, agency_id,
-- territory, property_specialisation, notify_match, notify_message,
-- notify_cobroke_request) is left untouched; these 2 columns are simply
-- added on top of it. No RLS policy change needed -- negotiator_update_own
-- (0001) already gates which ROW can be touched.
grant update (avatar_url, last_seen_at) on negotiator to authenticated;

-- Storage: path convention {negotiator_id}/avatar.jpg. PUBLIC bucket
-- (unlike listing-photos/requirement-photos, both private) -- avatars are
-- low-sensitivity and need broad, simple display across 9 screens without
-- managing signed-URL expiry at each one.
insert into storage.buckets (id, name, public) values ('avatar-photos', 'avatar-photos', true)
  on conflict (id) do nothing;

create policy avatar_photos_select_public on storage.objects for select
  to public using (bucket_id = 'avatar-photos');

create policy avatar_photos_insert_own on storage.objects for insert
  to authenticated with check (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_photos_update_own on storage.objects for update
  to authenticated using (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_photos_delete_own on storage.objects for delete
  to authenticated using (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text);

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'avatar-photos';

-- Postgres does NOT allow CREATE OR REPLACE FUNCTION to change a
-- function's return type (RETURNS TABLE compiles to OUT parameters) --
-- the function must be dropped and recreated, same as 0019 and 0026 both
-- had to do. Dropping a function discards its existing grants, so they
-- are explicitly restated below.
drop function if exists get_negotiator_public_info(uuid);

create function get_negotiator_public_info(p_negotiator_id uuid)
returns table (
  full_name text, ren_number text, agency_name text, verification_status text,
  avatar_url text, is_online boolean
)
language sql
security definer
set search_path = public
as $$
  select n.full_name, n.ren_number, a.firm_name, n.verification_status,
         n.avatar_url, (n.last_seen_at is not null and now() - n.last_seen_at < interval '2 minutes')
  from negotiator n
  left join agency a on a.agency_id = n.agency_id
  where n.negotiator_id = p_negotiator_id;
$$;

revoke execute on function get_negotiator_public_info(uuid) from public;
grant execute on function get_negotiator_public_info(uuid) to authenticated;
