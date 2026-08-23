-- supabase/migrations/0012_settings.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0011.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists notify_match boolean not null default true;
alter table negotiator add column if not exists notify_message boolean not null default true;
alter table negotiator add column if not exists notify_cobroke_request boolean not null default true;

-- Additive only -- no prior REVOKE statement.
-- Postgres GRANT is additive (it does not replace or reset prior column
-- grants); only the revoke operation resets a privilege set. 0010_profile.sql's own
-- migration comment documents exactly why a revoke+narrower-regrant pair
-- is dangerous on this table: it silently stripped 5 pre-existing UPDATE
-- columns in that milestone's Critical bug (revoking UPDATE revokes ALL
-- existing column-level UPDATE privileges, not just the ones a subsequent
-- narrower grant re-covers). This migration sidesteps the entire bug class
-- by never revoking at all -- the existing 7-column UPDATE grant
-- (full_name, ic_number, phone_number, ren_number, agency_id, territory,
-- property_specialisation) from 0010_profile.sql is left untouched, and
-- these 3 columns are simply added on top of it. No RLS policy change is
-- needed either: negotiator_update_own/negotiator_select_own (from 0001)
-- already gate which ROW can be touched (auth.uid() = negotiator_id) --
-- this grant only controls which COLUMNS, same division of labour as
-- every prior grant on this table.
grant update (notify_match, notify_message, notify_cobroke_request) on negotiator to authenticated;
