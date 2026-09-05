-- supabase/migrations/0018_conversation_read_tracking.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0017.
--
-- Adds message read-tracking (Chat tab / Conversation List unread
-- indicator) and a new `notification` table (in-app Notification Center) --
-- both deferred from their originating designs (Messaging's 0008, and the
-- Push Notifications design's explicit "no inbox screen" scope line) until
-- this milestone needed them for real.

alter table message add column if not exists read_at timestamptz;

-- Only the RECIPIENT of a message (never the sender) may mark it read --
-- mirrors message_select/message_insert's exact accepted-request-party
-- check from 0008_messaging.sql, plus excluding the sender.
drop policy if exists message_update_read_at on message;
create policy message_update_read_at on message for update
  to authenticated using (
    sender_id != auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = message.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  )
  with check (sender_id != auth.uid());

-- No existing UPDATE grant on `message` (0008 only granted insert) -- this
-- is a net-new grant, not a REVOKE-then-regrant, so it cannot repeat the
-- Profile milestone's column-grant-stripping incident.
grant update (read_at) on message to authenticated;

-- Latest message per conversation. A PLAIN view (no `security definer`) --
-- Postgres evaluates the underlying `message` table's OWN RLS using the
-- QUERYING user's permissions for a plain view, so this grants no new
-- privilege beyond what message_select already allows and cannot repeat
-- this project's prior security-definer RLS incidents (Co-Broke Request,
-- Profile, Ratings/Reviews).
create or replace view conversation_last_message as
select distinct on (request_id) request_id, sender_id, body, sent_at, read_at
from message
order by request_id, sent_at desc;

create table if not exists notification (
  notification_id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references negotiator(negotiator_id) on delete cascade,
  category text not null check (category in ('match', 'message', 'cobroke_request')),
  title text not null,
  body text not null,
  deep_link_data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notification_recipient_id_created_at_idx
  on notification(recipient_id, created_at desc);

alter table notification enable row level security;

drop policy if exists notification_select_own on notification;
create policy notification_select_own on notification for select
  to authenticated using (recipient_id = auth.uid());

drop policy if exists notification_update_read_at on notification;
create policy notification_update_read_at on notification for update
  to authenticated using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

grant update (read_at) on notification to authenticated;

-- Deliberately NO insert policy/grant for `authenticated`. recipient_id is
-- caller-supplied, not derivable from auth.uid() the way every other
-- insert policy in this schema pins it -- an insert policy here would let
-- any signed-in user write into any OTHER user's notification feed. Rows
-- are written exclusively by the send-push-notification Edge Function's
-- service-role client, which bypasses RLS entirely (same pattern that
-- function already uses to read fcm_device_token across all recipients).
