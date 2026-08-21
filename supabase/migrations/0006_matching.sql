-- supabase/migrations/0006_matching.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0005.
--
-- Written to be re-runnable from the start, same pattern as
-- 0005_requirement.sql (drop policy if exists, table guarded with `if not
-- exists`). No storage bucket, no column-scoped grants needed -- every
-- column on `match` (listing_id, requirement_id, score) is legitimately
-- insertable by the app; there's no auto-generated-only field like
-- negotiator_id to protect the way listing/requirement needed.

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
