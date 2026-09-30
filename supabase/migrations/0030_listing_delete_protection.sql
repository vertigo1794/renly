-- supabase/migrations/0030_listing_delete_protection.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0029.
--
-- Written to be re-runnable from the start, same pattern as
-- 0014_tier_gating.sql (create or replace function + drop trigger if
-- exists + create trigger).
--
-- 0022_listing_delete_policy.sql's own comment states plainly that the
-- app is "responsible for blocking Delete in the UI when a listing has an
-- ACCEPTED co-broke request ... this migration only adds the underlying
-- permission, it does not by itself protect that history." That client
-- side check (My Inventory's Delete menu item) is the ONLY thing standing
-- between a negotiator and deleting a listing that has a real accepted
-- deal (with chat/agreement history worth preserving) -- it can be
-- bypassed by any direct API call, and race conditions in the UI (e.g.
-- refreshing the accepted-requests list right before tapping Delete) can
-- momentarily make the client believe there's nothing to protect. This
-- trigger closes that gap at the DB layer, mirroring
-- match_enforce_mandatory_filters (0006_matching.sql) for a `before`
-- trigger that raises to block the operation outright.
create or replace function listing_block_delete_with_accepted_cobroke() returns trigger as $$
begin
  if exists (
    select 1 from cobroke_request cr
    join match m on m.match_id = cr.match_id
    where m.listing_id = old.listing_id and cr.status = 'accepted'
  ) then
    raise exception 'Cannot delete a listing with an accepted co-broke request. Withdraw it instead.';
  end if;
  return old;
end;
$$ language plpgsql;

drop trigger if exists listing_block_delete_with_accepted_cobroke_trigger on listing;
create trigger listing_block_delete_with_accepted_cobroke_trigger
  before delete on listing for each row
  execute function listing_block_delete_with_accepted_cobroke();
