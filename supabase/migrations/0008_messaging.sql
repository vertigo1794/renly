-- supabase/migrations/0008_messaging.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0007.
--
-- Written to be re-runnable from the start, same pattern as
-- 0006_matching.sql / 0007_cobroke_request.sql (create table if not
-- exists, drop policy if exists before each create policy).

create table if not exists message (
  message_id uuid primary key default gen_random_uuid(),
  request_id uuid not null references cobroke_request(request_id) on delete cascade,
  sender_id uuid not null references negotiator(negotiator_id) on delete cascade,
  body text not null check (char_length(trim(body)) > 0),
  sent_at timestamptz not null default now()
);

alter table message enable row level security;

-- Select: viewer must be a party to the underlying cobroke_request (its
-- initiator, or whichever side of the match's listing/requirement they
-- own), AND the request must be status = 'accepted'. This is the RLS-level
-- enforcement of "messaging opens upon acceptance" -- not just a UI gate.
drop policy if exists message_select on message;
create policy message_select on message for select
  to authenticated using (
    exists (
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
  );

-- Insert: sender must be the current user, and the same accepted-request
-- party check as select.
drop policy if exists message_insert on message;
create policy message_insert on message for insert
  to authenticated with check (
    sender_id = auth.uid()
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
  );

revoke insert on message from authenticated;
grant insert (request_id, sender_id, body) on message to authenticated;

-- Enable Realtime delivery for this table. Without this, .stream()
-- subscriptions receive the initial row set but never see live inserts.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message'
  ) then
    alter publication supabase_realtime add table message;
  end if;
end $$;
