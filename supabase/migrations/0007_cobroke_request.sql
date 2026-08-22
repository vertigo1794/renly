-- supabase/migrations/0007_cobroke_request.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0006.
--
-- Written to be re-runnable from the start, same pattern as
-- 0006_matching.sql (create table if not exists, drop policy if exists
-- before each create policy).

create table if not exists cobroke_request (
  request_id uuid primary key default gen_random_uuid(),
  match_id uuid not null references match(match_id) on delete cascade,
  initiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now()
);

-- At most one PENDING request per match at a time. A prior request on the
-- same match that was declined has status 'declined', not 'pending', so it
-- doesn't collide with this index -- this is what makes "re-request after
-- decline" possible, deliberately, per the design doc's resolution of the
-- proposal ERD's ambiguous "1 match : at most 1 request" wording.
drop index if exists cobroke_request_one_pending_per_match;
create unique index cobroke_request_one_pending_per_match
  on cobroke_request(match_id) where status = 'pending';

alter table cobroke_request enable row level security;

-- Both parties to the underlying match can see a request: the initiator,
-- or whichever of the match's listing/requirement they own.
drop policy if exists cobroke_request_select on cobroke_request;
create policy cobroke_request_select on cobroke_request for select
  to authenticated using (
    initiator_id = auth.uid()
    or exists (
      select 1 from match m
      join listing l on l.listing_id = m.listing_id
      where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
    )
    or exists (
      select 1 from match m
      join requirement r on r.requirement_id = m.requirement_id
      where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
    )
  );

-- Insert: must be the initiator, and must actually be a party to the match
-- (own the listing or requirement side) -- not an uninvolved third party
-- inserting a request on someone else's match.
drop policy if exists cobroke_request_insert on cobroke_request;
create policy cobroke_request_insert on cobroke_request for insert
  to authenticated with check (
    initiator_id = auth.uid()
    and (
      exists (
        select 1 from match m
        join listing l on l.listing_id = m.listing_id
        where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
      )
      or exists (
        select 1 from match m
        join requirement r on r.requirement_id = m.requirement_id
        where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
      )
    )
  );

-- Update: ONLY the receiving party (never the initiator) may change status,
-- and only while it's still pending. The initiator cannot accept/decline
-- their own request.
drop policy if exists cobroke_request_update_by_recipient on cobroke_request;
create policy cobroke_request_update_by_recipient on cobroke_request for update
  to authenticated using (
    status = 'pending'
    and initiator_id != auth.uid()
    and (
      exists (
        select 1 from match m
        join listing l on l.listing_id = m.listing_id
        where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
      )
      or exists (
        select 1 from match m
        join requirement r on r.requirement_id = m.requirement_id
        where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
      )
    )
  );

revoke insert on cobroke_request from authenticated;
grant insert (match_id, initiator_id) on cobroke_request to authenticated;

revoke update on cobroke_request from authenticated;
grant update (status) on cobroke_request to authenticated;
