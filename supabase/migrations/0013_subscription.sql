-- supabase/migrations/0013_subscription.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0012.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists stripe_customer_id text;
alter table negotiator add column if not exists stripe_subscription_id text;
alter table negotiator add column if not exists subscription_status text;
alter table negotiator add column if not exists current_period_end timestamptz;

-- One Stripe customer maps to exactly one negotiator. The webhook updates
-- rows with `.eq("stripe_customer_id", ...)`, which has no row limit -- a
-- duplicated customer id would silently flip SEVERAL negotiators' tiers on
-- a single webhook delivery. create-subscription's create-once logic
-- already avoids producing duplicates, but nothing enforced it at the DB
-- layer until now. Partial `where ... is not null` because the column is
-- nullable and most rows (every negotiator who never subscribed) hold
-- NULL: Postgres already permits unlimited NULLs in a plain unique index,
-- so the predicate changes no behaviour -- it just states the intent
-- explicitly. `drop index if exists` first keeps this migration
-- re-runnable, same as the `add column if not exists` statements above.
drop index if exists negotiator_stripe_customer_id_idx;
create unique index negotiator_stripe_customer_id_idx
  on negotiator (stripe_customer_id)
  where stripe_customer_id is not null;

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

-- Enable Realtime delivery for this table. Without this, .stream()
-- subscriptions receive the initial row set but never see live updates.
-- Same guarded pattern as 0008_messaging.sql used for `message`.
--
-- This is load-bearing for the whole live tier-flip feature:
-- SubscriptionRepository.subscriptionStream watches this row so the
-- Subscription screen swaps out of "Processing..." the moment
-- stripe-webhook writes subscription_tier = 'professional'. Without the
-- table in the publication the stream delivers its initial snapshot once
-- and then never emits again -- the database value would be correct, but
-- every paying user would sit on "This is taking longer than expected"
-- until they manually tapped Refresh.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'negotiator'
  ) then
    alter publication supabase_realtime add table negotiator;
  end if;
end $$;
