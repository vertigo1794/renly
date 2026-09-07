-- supabase/migrations/0025_listing_property_details.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0024.
--
-- New real property-attribute fields for the Property Detail Ultra-Premium
-- Restyle: maintenance fee, tenure, parking bays, floor level, furnishing
-- status (all owner-set, all nullable -- absent means the owner didn't set
-- it, never a fabricated/estimated fallback), plus two new self-attested
-- toggles (keys_on_hand, protected_co_broke_reg -- NOT third-party
-- verified, same honesty framing as title_verified/exclusive_mandate) and
-- a standalone total_agency_commission_percent (distinct from the existing
-- commission_split_percent, which is the OWNER's own advertised split of
-- that total to a co-broker).
--
-- Grants are restated in FULL here (not just the new columns), in the
-- SAME migration as the column adds -- this project hit two real live
-- bugs earlier this session (migrations 0010 and 0020) from not doing
-- this; this migration applies that lesson from the start. The current
-- authoritative grant lists were confirmed by reading 0023_listing_sqft.sql
-- (the most recent grant-restating migration on this table) directly --
-- INSERT does NOT include photo_urls/status (those are UPDATE-only,
-- set via separate calls), UPDATE includes bumped_at/photo_urls/status.
alter table listing add column if not exists maintenance_fee_myr numeric(10,2)
  check (maintenance_fee_myr is null or maintenance_fee_myr >= 0);
alter table listing add column if not exists tenure text
  check (tenure is null or tenure in ('freehold', 'leasehold'));
alter table listing add column if not exists parking_bays integer
  check (parking_bays is null or parking_bays >= 0);
alter table listing add column if not exists floor_level integer;
alter table listing add column if not exists furnishing_status text
  check (furnishing_status is null or furnishing_status in ('furnished', 'partially_furnished', 'unfurnished'));
alter table listing add column if not exists keys_on_hand boolean not null default false;
alter table listing add column if not exists protected_co_broke_reg boolean not null default false;
alter table listing add column if not exists total_agency_commission_percent numeric(5,2)
  check (total_agency_commission_percent is null or (total_agency_commission_percent > 0 and total_agency_commission_percent <= 100));

revoke insert on listing from authenticated;
grant insert (
  negotiator_id, title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, built_up_sqft,
  commission_split_percent, title_verified, exclusive_mandate,
  maintenance_fee_myr, tenure, parking_bays, floor_level, furnishing_status,
  keys_on_hand, protected_co_broke_reg, total_agency_commission_percent
) on listing to authenticated;

revoke update on listing from authenticated;
grant update (
  title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, built_up_sqft, photo_urls, status, bumped_at,
  commission_split_percent, title_verified, exclusive_mandate,
  maintenance_fee_myr, tenure, parking_bays, floor_level, furnishing_status,
  keys_on_hand, protected_co_broke_reg, total_agency_commission_percent
) on listing to authenticated;
