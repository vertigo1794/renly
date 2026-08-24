-- supabase/migrations/0016_fcm_device_token.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0015.
--
-- Stores one row per (negotiator, FCM device token) pair. A separate table
-- rather than a column on negotiator -- a negotiator can be logged in on
-- more than one device and should get a push on all of them, per this
-- module's design doc.
--
-- No UPDATE policy: a token is either current (present) or stale (deleted,
-- by its owner or by send-push-notification's self-cleaning path when FCM
-- reports it invalid), never edited in place.
create table if not exists fcm_device_token (
  token_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  token text not null,
  created_at timestamptz not null default now(),
  unique (negotiator_id, token)
);

alter table fcm_device_token enable row level security;

drop policy if exists fcm_device_token_select_own on fcm_device_token;
create policy fcm_device_token_select_own on fcm_device_token
  for select to authenticated using (negotiator_id = auth.uid());

drop policy if exists fcm_device_token_insert_own on fcm_device_token;
create policy fcm_device_token_insert_own on fcm_device_token
  for insert to authenticated with check (negotiator_id = auth.uid());

drop policy if exists fcm_device_token_delete_own on fcm_device_token;
create policy fcm_device_token_delete_own on fcm_device_token
  for delete to authenticated using (negotiator_id = auth.uid());
