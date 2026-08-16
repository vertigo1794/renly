-- supabase/migrations/0002_rls_hardening.sql
-- Run this AFTER 0001_auth_verification.sql, in the same Supabase SQL Editor.
--
-- Fixes found in code review:
-- - negotiator_update_own (0001) restricts which ROW a user can update but
--   not which COLUMNS -- RLS can't do column-level restriction, only
--   GRANT/REVOKE can. Without this, any signed-up user can self-approve
--   their own verification_status and subscription_tier via a direct PATCH
--   to the REST API, which defeats the entire verification gate.
-- - verification_record_insert_own has the same gap: a user could insert
--   their own row with outcome='approved' and a forged reviewed_at.
-- - agency_select_all had no `to authenticated`, so it was also readable
--   by the anon role.
-- - ren-tags storage bucket had no UPDATE policy, so upsert:true uploads
--   (retries) failed, and no size/type limits, so it accepted arbitrary
--   files.

-- Column-scoped UPDATE on negotiator: verification_status and
-- subscription_tier are deliberately excluded -- only a privileged
-- reviewer (service_role / admin tooling) may move those.
revoke update on negotiator from authenticated;
grant update (full_name, ic_number, phone_number, ren_number, agency_id, territory)
  on negotiator to authenticated;

-- Column-scoped INSERT on negotiator: verification_status and
-- subscription_tier must only ever be set via their table defaults
-- ('pending', 'free') on insert -- never client-supplied, or a user could
-- self-approve their own verification on their first write.
revoke insert on negotiator from authenticated;
grant insert (negotiator_id, full_name, ic_number, phone_number) on negotiator to authenticated;

-- Column-scoped INSERT on verification_record: outcome, reviewed_at and
-- submitted_at stay at their column defaults and cannot be forged.
revoke insert on verification_record from authenticated;
grant insert (negotiator_id, method, tag_photo_url) on verification_record to authenticated;

-- Scope agency reads to signed-in users (was implicitly readable by anon).
drop policy if exists agency_select_all on agency;
create policy agency_select_all on agency for select to authenticated using (true);

-- uploadTagPhoto() uses FileOptions(upsert: true); without an UPDATE policy
-- every retry after the first successful upload fails with an RLS 403.
drop policy if exists ren_tags_update_own on storage.objects;
create policy ren_tags_update_own on storage.objects for update to authenticated
  using (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text);

update storage.buckets
set file_size_limit = 5242880, -- 5MB
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'ren-tags';
