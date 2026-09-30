-- supabase/migrations/0035_listing_requirement_geolocation.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0034.
--
-- Adds real GPS coordinates to listing and requirement, captured via the
-- device's Geolocator on Post Listing/Post Requirement ("Use my current
-- location" button). Nullable on both -- absent means the negotiator
-- didn't use the GPS capture (typed area/state manually instead), never
-- a fabricated/estimated fallback. Standard lat/lng range CHECKs guard
-- against garbage values reaching the DB regardless of client-side bugs.
--
-- Grants are restated in FULL here (not just the new columns), in the
-- SAME migration as the column adds -- the lesson from migrations 0010/
-- 0020 earlier this session, applied from the start. Current
-- authoritative grant lists confirmed by reading 0025_listing_property_details.sql
-- and 0027_requirement_property_preferences.sql directly.
alter table listing add column if not exists latitude double precision
  check (latitude is null or (latitude >= -90 and latitude <= 90));
alter table listing add column if not exists longitude double precision
  check (longitude is null or (longitude >= -180 and longitude <= 180));

alter table requirement add column if not exists latitude double precision
  check (latitude is null or (latitude >= -90 and latitude <= 90));
alter table requirement add column if not exists longitude double precision
  check (longitude is null or (longitude >= -180 and longitude <= 180));

revoke insert on listing from authenticated;
grant insert (
  negotiator_id, title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, built_up_sqft,
  commission_split_percent, title_verified, exclusive_mandate,
  maintenance_fee_myr, tenure, parking_bays, floor_level, furnishing_status,
  keys_on_hand, protected_co_broke_reg, total_agency_commission_percent,
  latitude, longitude
) on listing to authenticated;

revoke update on listing from authenticated;
grant update (
  title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, built_up_sqft, photo_urls, status, bumped_at,
  commission_split_percent, title_verified, exclusive_mandate,
  maintenance_fee_myr, tenure, parking_bays, floor_level, furnishing_status,
  keys_on_hand, protected_co_broke_reg, total_agency_commission_percent,
  latitude, longitude
) on listing to authenticated;

revoke insert on requirement from authenticated;
grant insert (
  negotiator_id, property_type, transaction_type, state, area,
  budget_min, budget_max, bedrooms, bathrooms_min, built_up_sqft_min,
  desired_commission_split_percent, loan_ready, urgent_viewing_required,
  tenure_preference, parking_bays_min, floor_level_min, furnishing_preference,
  latitude, longitude
) on requirement to authenticated;

revoke update on requirement from authenticated;
grant update (
  property_type, transaction_type, state, area, budget_min, budget_max,
  bedrooms, bathrooms_min, built_up_sqft_min, desired_commission_split_percent,
  loan_ready, urgent_viewing_required, status, photo_urls,
  tenure_preference, parking_bays_min, floor_level_min, furnishing_preference,
  latitude, longitude
) on requirement to authenticated;
