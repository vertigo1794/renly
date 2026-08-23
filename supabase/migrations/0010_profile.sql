-- supabase/migrations/0010_profile.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0009.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists property_specialisation text;

-- Territory and property_specialisation are the only user-editable fields
-- on this table. UPDATE was fully revoked from negotiator during
-- Auth+Verification's Critical self-approval fix (0002_rls_hardening.sql)
-- -- this is the first UPDATE access the client has had on this table
-- since, and it's scoped to exactly these two columns. No RLS policy
-- change is needed: negotiator_update_own (from 0001) already gates which
-- ROW can be touched (auth.uid() = negotiator_id); this grant is what
-- makes any UPDATE possible at all again, restricted to which COLUMNS.
revoke update on negotiator from authenticated;
grant update (territory, property_specialisation) on negotiator to authenticated;
