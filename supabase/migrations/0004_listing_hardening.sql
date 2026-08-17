-- supabase/migrations/0004_listing_hardening.sql
-- Run this AFTER 0003_listing.sql, in the same Supabase SQL Editor.
--
-- Written to be re-runnable (drop policy if exists / create or replace /
-- guarded constraint adds), same as 0002 -- a manual copy-paste-into-the-
-- SQL-Editor workflow needs to survive a half-applied or retried paste.
--
-- Fixes found in whole-branch code review:
-- - listing table policies had no `to authenticated`, so the anon role
--   (the key shipped inside the app) could read every active listing --
--   the exact gap 0002_rls_hardening.sql already closed for `agency`,
--   reintroduced here.
-- - PropertyDetailScreen needs the listing owner's name + REN number, but
--   negotiator_select_own (0001) only lets a user read their OWN row --
--   any other negotiator's info silently failed to load. Exposed via a
--   security-definer RPC returning only the two safe columns, rather than
--   broadening the negotiator SELECT policy (which would leak ic_number,
--   phone_number, verification_status to any viewer).
-- - listing_update_own permitted updating every column including
--   created_at (the marketplace's sort key) and listing_id/negotiator_id
--   -- column-scoped per the same pattern 0002 applied to `negotiator`.
-- - bedrooms/bathrooms had no non-negative CHECK.

-- Scope the listing policies to signed-in users (they were `to public`,
-- i.e. also the anon role).
drop policy if exists listing_select on listing;
create policy listing_select on listing for select
  to authenticated using (negotiator_id = auth.uid() or status = 'active');

drop policy if exists listing_insert_own on listing;
create policy listing_insert_own on listing for insert
  to authenticated with check (negotiator_id = auth.uid());

drop policy if exists listing_update_own on listing;
create policy listing_update_own on listing for update
  to authenticated using (negotiator_id = auth.uid());

-- Column-scoped INSERT: listing_id, photo_urls, status and created_at stay
-- at their table defaults on insert (photos are attached by a follow-up
-- UPDATE once they have been uploaded under the new listing_id).
revoke insert on listing from authenticated;
grant insert (
  negotiator_id, title, description, property_type, transaction_type,
  state, area, price, bedrooms, bathrooms
) on listing to authenticated;

-- Column-scoped UPDATE: listing_id, negotiator_id and created_at (the
-- marketplace's sort key) are deliberately excluded -- RLS restricts which
-- ROW may be updated, only GRANT/REVOKE can restrict which COLUMNS.
revoke update on listing from authenticated;
grant update (
  title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, photo_urls, status
) on listing to authenticated;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'listing_bedrooms_nonnegative') then
    alter table listing add constraint listing_bedrooms_nonnegative check (bedrooms is null or bedrooms >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'listing_bathrooms_nonnegative') then
    alter table listing add constraint listing_bathrooms_nonnegative check (bathrooms is null or bathrooms >= 0);
  end if;
end $$;

-- Security-definer RPC: exposes only full_name/ren_number for any
-- negotiator, so PropertyDetailScreen can show a listing's owner without
-- widening the negotiator table's row-level SELECT policy (which would
-- also leak ic_number, phone_number and verification_status).
--
-- The body qualifies every column with the `n` alias on purpose: the
-- RETURNS TABLE output names (full_name, ren_number) are parameters as far
-- as the SQL body is concerned, so an unqualified `select full_name` would
-- fail with "column reference full_name is ambiguous" (42702).
create or replace function get_listing_owner_info(p_negotiator_id uuid)
returns table (full_name text, ren_number text)
language sql
security definer
set search_path = public
as $$
  select n.full_name, n.ren_number from negotiator n where n.negotiator_id = p_negotiator_id;
$$;

revoke execute on function get_listing_owner_info(uuid) from public;
grant execute on function get_listing_owner_info(uuid) to authenticated;
