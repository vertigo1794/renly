-- supabase/migrations/0009_agreement.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0008.
--
-- Written to be re-runnable from the start, same pattern as
-- 0006_matching.sql / 0007_cobroke_request.sql / 0008_messaging.sql
-- (create table if not exists, drop policy/trigger/index if exists before
-- each create).

create table if not exists agreement (
  agreement_id uuid primary key default gen_random_uuid(),
  request_id uuid not null references cobroke_request(request_id) on delete cascade,
  initiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  split_initiator numeric(5,2) not null check (split_initiator > 0 and split_initiator < 100),
  split_counterparty numeric(5,2) not null check (split_counterparty > 0 and split_counterparty < 100),
  terms text,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  check (split_initiator + split_counterparty = 100)
);

-- At most one OPEN (pending or accepted) agreement per request at a time.
-- A declined agreement's status is neither 'pending' nor 'accepted', so it
-- doesn't collide with this index -- re-proposing after a decline is
-- possible, deliberately, same point-in-time pattern as
-- cobroke_request_one_open_per_match.
drop index if exists agreement_one_open_per_request;
create unique index agreement_one_open_per_request
  on agreement(request_id) where status in ('pending', 'accepted');

-- accepted_at is set by the database, never supplied by the client --
-- "recorded immutably with a timestamp" per the proposal means the
-- timestamp itself must be trustworthy, not just the row's existence.
create or replace function agreement_set_accepted_at() returns trigger as $$
begin
  if new.status = 'accepted' and old.status != 'accepted' then
    new.accepted_at := now();
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists agreement_set_accepted_at_trigger on agreement;
create trigger agreement_set_accepted_at_trigger
  before update on agreement for each row
  execute function agreement_set_accepted_at();

alter table agreement enable row level security;

-- Select: viewer must be a party to the underlying cobroke_request (its
-- initiator, or whichever side of the match's listing/requirement they
-- own), AND the request must be status = 'accepted'. Same pattern as
-- message_select.
drop policy if exists agreement_select on agreement;
create policy agreement_select on agreement for select
  to authenticated using (
    exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

-- Insert: initiator must be the current user, and the same accepted-request
-- party check as select.
drop policy if exists agreement_insert on agreement;
create policy agreement_insert on agreement for insert
  to authenticated with check (
    initiator_id = auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

-- Update: ONLY the receiving party (never the agreement's own initiator)
-- may accept/decline, and only while it's still pending. USING gates
-- which EXISTING rows can be touched (must still be pending). WITH CHECK
-- gates what the PROPOSED NEW ROW must look like -- these must be
-- separate, per the lesson from cobroke_request_update_by_recipient's
-- Critical bug: a FOR UPDATE policy that omits WITH CHECK has Postgres
-- reuse USING against the new row too, and the whole point of an
-- accept/decline is to move status AWAY from 'pending' -- so a
-- USING-only policy would reject every one.
drop policy if exists agreement_update_by_recipient on agreement;
create policy agreement_update_by_recipient on agreement for update
  to authenticated using (
    status = 'pending'
    and initiator_id != auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  )
  with check (
    status in ('accepted', 'declined')
    and initiator_id != auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

revoke insert on agreement from authenticated;
grant insert (request_id, initiator_id, split_initiator, split_counterparty, terms) on agreement to authenticated;

revoke update on agreement from authenticated;
grant update (status) on agreement to authenticated;
