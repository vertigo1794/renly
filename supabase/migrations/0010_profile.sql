-- supabase/migrations/0010_profile.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0009.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists property_specialisation text;

-- IMPORTANT: 0002_rls_hardening.sql did NOT fully revoke UPDATE on
-- negotiator -- it revoked-then-re-granted a 6-column set:
-- (full_name, ic_number, phone_number, ren_number, agency_id, territory).
-- REVOKE UPDATE on a table also revokes ALL existing column-level UPDATE
-- privileges on it (documented Postgres behaviour, not scoped to only the
-- columns being re-granted) -- so a bare revoke here followed by a grant
-- covering only (territory, property_specialisation) would silently strip
-- the other 5 columns' write access, including ren_number/agency_id,
-- which registration Step 2's completeProfessionalDetails() depends on.
-- This grant restates the FULL desired column set, not just the two new
-- ones. No RLS policy change is needed: negotiator_update_own (from 0001)
-- already gates which ROW can be touched (auth.uid() = negotiator_id);
-- this grant controls which COLUMNS.
revoke update on negotiator from authenticated;
grant update (full_name, ic_number, phone_number, ren_number, agency_id, territory, property_specialisation)
  on negotiator to authenticated;
