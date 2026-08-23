-- supabase/migrations/0013_subscription.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0012.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists stripe_customer_id text;
alter table negotiator add column if not exists stripe_subscription_id text;
alter table negotiator add column if not exists subscription_status text;
alter table negotiator add column if not exists current_period_end timestamptz;

-- Deliberately NO grant statement for these 4 columns, to authenticated or
-- anyone else -- unlike every other "new column" migration in this
-- project, these are never client-writable at all, not even narrowly.
-- They are written ONLY by the stripe-webhook Edge Function using the
-- Supabase service role key, which bypasses table grants and RLS entirely
-- (the established pattern for privileged server-side writes on this
-- table, alongside subscription_tier itself -- see 0002_rls_hardening.sql
-- for that column's own "never client-writable" precedent). SELECT
-- access for these 4 columns comes from the table's pre-existing default
-- grant (never revoked in this migration set, same as ic_number/
-- phone_number) -- a negotiator can read their own subscription details,
-- just never write them directly.
