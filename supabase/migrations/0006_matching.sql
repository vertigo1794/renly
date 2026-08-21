-- supabase/migrations/0006_matching.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0005.
--
-- Written to be re-runnable from the start, same pattern as
-- 0005_requirement.sql (drop policy if exists, table guarded with `if not
-- exists`). No storage bucket needed. Column-scoped grants below follow
-- the same hardening pattern as 0004_listing_hardening.sql/
-- 0005_requirement.sql: every column on `match` (listing_id,
-- requirement_id, score) is legitimately insertable by the app -- there's
-- no auto-generated-only field like negotiator_id to protect the way
-- listing/requirement needed -- but privileges are still granted
-- explicitly rather than relying on Supabase's default ALL-to-role grant.

create table if not exists match (
  match_id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listing(listing_id) on delete cascade,
  requirement_id uuid not null references requirement(requirement_id) on delete cascade,
  score integer not null check (score >= 0 and score <= 100),
  created_at timestamptz not null default now(),
  unique (listing_id, requirement_id)
);

alter table match enable row level security;

-- `match` has no negotiator_id column of its own -- ownership is
-- determined by joining to listing/requirement, since a match inherently
-- touches two different negotiators' records. A negotiator sees/inserts a
-- row if they own EITHER side.
drop policy if exists match_select on match;
create policy match_select on match for select
  to authenticated using (
    exists (select 1 from listing l where l.listing_id = match.listing_id and l.negotiator_id = auth.uid())
    or exists (select 1 from requirement r where r.requirement_id = match.requirement_id and r.negotiator_id = auth.uid())
  );

drop policy if exists match_insert on match;
create policy match_insert on match for insert
  to authenticated with check (
    exists (select 1 from listing l where l.listing_id = match.listing_id and l.negotiator_id = auth.uid())
    or exists (select 1 from requirement r where r.requirement_id = match.requirement_id and r.negotiator_id = auth.uid())
  );

-- Deliberately no UPDATE or DELETE policy: RLS is deny-by-default, so with
-- no policy for those commands they are blocked entirely. Neither listing
-- nor requirement has an edit flow, so a match's score never needs to
-- change once inserted -- there is genuinely nothing to update.

-- Scoring itself is intentionally client-side and therefore untrusted;
-- match_insert only requires owning one side, with no server-side check
-- that the two rows actually satisfy the mandatory filters or belong to
-- different negotiators -- this trigger guards those two binary
-- conditions (transaction_type/state match, non-self-match) at the DB
-- layer, closing the same gap as the Dart-side guard in
-- MatchingRepository, without re-implementing the weighted scoring.
create or replace function match_enforce_mandatory_filters() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from listing l join requirement r on true
    where l.listing_id = new.listing_id and r.requirement_id = new.requirement_id
      and l.transaction_type = r.transaction_type and l.state = r.state
      and l.negotiator_id <> r.negotiator_id
  ) then
    raise exception 'match violates mandatory filters';
  end if;
  return new;
end $$;

drop trigger if exists match_enforce_mandatory_filters_trigger on match;
create trigger match_enforce_mandatory_filters_trigger
  before insert on match
  for each row execute function match_enforce_mandatory_filters();

revoke all on match from anon;
revoke insert on match from authenticated;
grant insert (listing_id, requirement_id, score) on match to authenticated;
grant select on match to authenticated;
