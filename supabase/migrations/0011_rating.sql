-- supabase/migrations/0011_rating.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0010.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

create table if not exists rating (
  rating_id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references agreement(agreement_id) on delete cascade,
  rater_id uuid not null references negotiator(negotiator_id) on delete cascade,
  rated_id uuid not null references negotiator(negotiator_id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  review_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  check (rater_id != rated_id)
);

-- At most one rating per rater per agreement, for the life of the
-- agreement. Not a point-in-time cap -- editing (within 24h, see below)
-- already covers "I made a mistake," so there's no re-rate-after-decline
-- case to accommodate here, unlike cobroke_request/agreement's own
-- partial-unique-index pattern.
drop index if exists rating_one_per_rater_per_agreement;
create unique index rating_one_per_rater_per_agreement
  on rating(agreement_id, rater_id);

-- fetchRatingsForNegotiator filters on rated_id, queried on every Profile
-- and Reviews screen view. The unique index above is on
-- (agreement_id, rater_id) and can't serve this lookup.
drop index if exists rating_rated_id_created_at_idx;
create index rating_rated_id_created_at_idx on rating(rated_id, created_at desc);

create or replace function rating_set_updated_at() returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists rating_set_updated_at_trigger on rating;
create trigger rating_set_updated_at_trigger
  before update on rating for each row
  execute function rating_set_updated_at();

-- Checks whether p_negotiator_id is a genuine party (initiator, listing
-- owner, or requirement owner) to the cobroke_request underlying
-- p_agreement_id. Extracted as a reusable function rather than repeating
-- the agreement -> cobroke_request -> match -> listing/requirement join
-- chain inline for both rater_id and rated_id in the INSERT policy below.
-- Since every cobroke_request has exactly two parties, confirming BOTH
-- rater_id and rated_id are independently party members (and distinct
-- from each other, enforced separately) is sufficient to prove they are
-- the two opposite sides -- no explicit pairing logic needed.
--
-- SECURITY DEFINER is required, not stylistic: as SECURITY INVOKER (the
-- default) this function runs as the calling `authenticated` role, and
-- listing_select/requirement_select ("negotiator_id = auth.uid() or
-- status = 'active'/'open'") hide a listing/requirement the instant its
-- owner marks it sold/fulfilled/withdrawn -- exactly the moment a deal
-- is complete and rating becomes relevant. Without this, checking
-- whether rated_id is still a visible party would silently fail for the
-- non-initiator once their side of the deal closes, the same zero-rows
-- trap get_listing_owner_info was created to escape (0004_listing_hardening.sql).
create or replace function is_agreement_party(p_agreement_id uuid, p_negotiator_id uuid) returns boolean
language sql stable
security definer
set search_path = public as $$
  select exists (
    select 1 from agreement a
    join cobroke_request cr on cr.request_id = a.request_id
    join match m on m.match_id = cr.match_id
    where a.agreement_id = p_agreement_id
      and (
        cr.initiator_id = p_negotiator_id
        or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = p_negotiator_id)
        or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = p_negotiator_id)
      )
  );
$$;

revoke execute on function is_agreement_party(uuid, uuid) from public;
grant execute on function is_agreement_party(uuid, uuid) to authenticated;

alter table rating enable row level security;

-- Select: public. Ratings/reviews are a trust signal meant to be visible
-- to any authenticated negotiator, same reasoning as agency_select_all.
drop policy if exists rating_select on rating;
create policy rating_select on rating for select
  to authenticated using (true);

-- Insert: sender must be themselves, target must be someone else, the
-- underlying agreement must be accepted, and BOTH rater and rated must
-- genuinely be parties to it.
drop policy if exists rating_insert on rating;
create policy rating_insert on rating for insert
  to authenticated with check (
    rater_id = auth.uid()
    and rated_id != rater_id
    and exists (select 1 from agreement a where a.agreement_id = rating.agreement_id and a.status = 'accepted')
    and is_agreement_party(rating.agreement_id, rater_id)
    and is_agreement_party(rating.agreement_id, rated_id)
  );

-- Update: only the original rater, only within 24 hours of creation.
-- USING and WITH CHECK are IDENTICAL here -- unlike cobroke_request's
-- Critical bug (USING encoded a "before" status the update was designed
-- to move away from), the 24-hour window condition doesn't change between
-- the old and new row states, so there's no transition to gate
-- asymmetrically. rater_id/created_at are excluded from the UPDATE grant
-- entirely (see below), so neither can be touched to extend the window or
-- reassign the rating.
drop policy if exists rating_update_by_rater on rating;
create policy rating_update_by_rater on rating for update
  to authenticated using (
    rater_id = auth.uid()
    and now() - created_at < interval '24 hours'
  )
  with check (
    rater_id = auth.uid()
    and now() - created_at < interval '24 hours'
  );

revoke insert on rating from authenticated;
grant insert (agreement_id, rater_id, rated_id, stars, review_text) on rating to authenticated;

revoke update on rating from authenticated;
grant update (stars, review_text) on rating to authenticated;
