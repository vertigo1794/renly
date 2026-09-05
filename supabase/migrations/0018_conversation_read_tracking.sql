-- supabase/migrations/0018_conversation_read_tracking.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0017.
--
-- Adds message read-tracking (Chat tab / Conversation List unread
-- indicator) and a new `notification` table (in-app Notification Center) --
-- both deferred from their originating designs (Messaging's 0008, and the
-- Push Notifications design's explicit "no inbox screen" scope line) until
-- this milestone needed them for real.
--
-- ROLLBACK NOTE: if this migration is ever reverted, do NOT undo the two
-- `revoke update ... from authenticated` statements below (on `message` and
-- on `notification`). They are standalone security fixes for a latent gap
-- inherited from 0008_messaging.sql -- Supabase's default blanket table-wide
-- UPDATE grant to `authenticated`, which was never revoked there -- and are
-- independent of this migration's own new schema. Re-granting blanket UPDATE
-- would let any accepted-request party rewrite `message.body`/`sent_at`.
-- A revert should drop ONLY the new view, table, columns and policies
-- (`conversation_last_message`, `notification`, `message.read_at`,
-- `message_update_read_at`, `notification_select_own`,
-- `notification_update_read_at`) and leave the revokes in place.

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

-- 0008_messaging.sql never revoked the default blanket UPDATE grant that
-- Supabase issues to `authenticated` on new tables (it only did a
-- revoke-then-regrant for INSERT). That dormant grant has covered every
-- column of `message` since 0008; 0018 is the first migration to add an
-- UPDATE RLS policy for `message`, which makes it live. A REVOKE-then-
-- column-grant is required here, unlike a case where no such dormant
-- blanket grant exists, otherwise any accepted-request recipient could
-- UPDATE `body`/`sent_at`, not just `read_at`.
revoke update on message from authenticated;
grant update (read_at) on message to authenticated;

-- Latest message per conversation. security_invoker = true is REQUIRED,
-- not optional decoration: since Postgres 15, a view without it runs RLS
-- as the VIEW OWNER, not the querying session (FORCE ROW LEVEL SECURITY
-- is not set anywhere in this schema, so ownership alone skips RLS) --
-- meaning every authenticated user would see the latest message of EVERY
-- conversation in the system, bypassing message_select's accepted-
-- request-party check entirely. With security_invoker = true, Postgres
-- evaluates the underlying `message` table's OWN RLS using the QUERYING
-- user's permissions instead, so this grants no new privilege beyond
-- what message_select already allows and cannot repeat this project's
-- prior security-definer RLS incidents (Co-Broke Request, Profile,
-- Ratings/Reviews).
create or replace view conversation_last_message with (security_invoker = true) as
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

-- Same dormant-blanket-grant gap as `message` above: `notification` is a
-- net-new table in this migration, so it still carries Supabase's default
-- table-wide UPDATE grant to `authenticated` until explicitly revoked.
-- WITH CHECK already pins recipient_id = auth.uid(), so without the
-- revoke a user could only rewrite their OWN notification rows -- but
-- could still rewrite title/body/category/deep_link_data via UPDATE, not
-- just read_at, breaking the intended immutability of those columns.
revoke update on notification from authenticated;
grant update (read_at) on notification to authenticated;

-- Deliberately NO insert policy/grant for `authenticated`. recipient_id is
-- caller-supplied, not derivable from auth.uid() the way every other
-- insert policy in this schema pins it -- an insert policy here would let
-- any signed-in user write into any OTHER user's notification feed. Rows
-- are written exclusively by the send-push-notification Edge Function's
-- service-role client, which bypasses RLS entirely (same pattern that
-- function already uses to read fcm_device_token across all recipients).
