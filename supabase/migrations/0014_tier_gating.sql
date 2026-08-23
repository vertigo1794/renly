-- supabase/migrations/0014_tier_gating.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0013.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

-- Only gates transitions INTO 'active' -- a brand new listing, or
-- reactivation of a withdrawn one via PropertyDetailScreen's "Mark
-- Active" button (which calls the same updateListingStatus path as
-- PostListingScreen's initial create). Does nothing when status stays
-- active, moves OUT of active (sold/withdrawn), or an unrelated field
-- (price, description, photos) is edited on an already-active row.
--
-- No SECURITY DEFINER needed -- this only ever reads
-- negotiator.subscription_tier for the SAME negotiator who owns the row
-- being inserted/updated (their own row, already visible to them under
-- negotiator_select_own), unlike the cross-user cases elsewhere in this
-- project (get_listing_owner_info, is_agreement_party) that needed it.
create or replace function check_listing_active_cap() returns trigger as $$
declare
  tier text;
  active_count int;
begin
  if new.status != 'active' or (TG_OP = 'UPDATE' and old.status = 'active') then
    return new;
  end if;

  select subscription_tier into tier from negotiator where negotiator_id = new.negotiator_id;
  if tier = 'professional' then
    return new;
  end if;

  select count(*) into active_count from listing where negotiator_id = new.negotiator_id and status = 'active';
  if active_count >= 3 then
    raise exception 'Free tier is limited to 3 active listings. Upgrade to Professional for unlimited listings.';
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists listing_active_cap_trigger on listing;
create trigger listing_active_cap_trigger
  before insert or update on listing for each row
  execute function check_listing_active_cap();

-- Structural mirror of the listing trigger above -- same reasoning, same
-- shape, 'requirement'/'open' instead of 'listing'/'active'.
create or replace function check_requirement_active_cap() returns trigger as $$
declare
  tier text;
  active_count int;
begin
  if new.status != 'open' or (TG_OP = 'UPDATE' and old.status = 'open') then
    return new;
  end if;

  select subscription_tier into tier from negotiator where negotiator_id = new.negotiator_id;
  if tier = 'professional' then
    return new;
  end if;

  select count(*) into active_count from requirement where negotiator_id = new.negotiator_id and status = 'open';
  if active_count >= 3 then
    raise exception 'Free tier is limited to 3 active requirements. Upgrade to Professional for unlimited requirements.';
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists requirement_active_cap_trigger on requirement;
create trigger requirement_active_cap_trigger
  before insert or update on requirement for each row
  execute function check_requirement_active_cap();
