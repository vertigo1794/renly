-- supabase/migrations/0027_requirement_property_preferences.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0026.
--
-- Adds 4 buyer-set property-preference fields to requirement, mirroring
-- the 4 property-attribute fields the Property Detail Ultra-Premium
-- Restyle just added to listing (tenure/parking_bays/floor_level/
-- furnishing_status). All nullable -- absent means the buyer didn't set
-- a preference, never a fabricated/estimated fallback.
--
-- Unlike listing's own fields (plain display data), these 4 are REAL
-- MATCHING ENGINE QUALIFYING FILTERS: tenure_preference/
-- furnishing_preference require an EXACT match against the listing's
-- own tenure/furnishing_status when set (categorical preferences, same
-- shape as transaction_type/state's existing mandatory filters);
-- parking_bays_min/floor_level_min are MINIMUM thresholds, same shape
-- as the existing bathrooms_min/built_up_sqft_min filters added in
-- 0024_requirement_broadcast_fields.sql.
--
-- Grants are restated in FULL here (not just the new columns), in the
-- SAME migration as the column adds -- the lesson from migrations 0010/
-- 0020 earlier this session, applied from the start. Current
-- authoritative grant lists confirmed by reading 0024's own grant
-- statement directly.
alter table requirement add column if not exists tenure_preference text
  check (tenure_preference is null or tenure_preference in ('freehold', 'leasehold'));
alter table requirement add column if not exists parking_bays_min integer
  check (parking_bays_min is null or parking_bays_min >= 0);
alter table requirement add column if not exists floor_level_min integer;
alter table requirement add column if not exists furnishing_preference text
  check (furnishing_preference is null or furnishing_preference in ('furnished', 'partially_furnished', 'unfurnished'));

revoke insert on requirement from authenticated;
grant insert (
  negotiator_id, property_type, transaction_type, state, area,
  budget_min, budget_max, bedrooms, bathrooms_min, built_up_sqft_min,
  desired_commission_split_percent, loan_ready, urgent_viewing_required,
  tenure_preference, parking_bays_min, floor_level_min, furnishing_preference
) on requirement to authenticated;

revoke update on requirement from authenticated;
grant update (
  property_type, transaction_type, state, area, budget_min, budget_max,
  bedrooms, bathrooms_min, built_up_sqft_min, desired_commission_split_percent,
  loan_ready, urgent_viewing_required, status, photo_urls,
  tenure_preference, parking_bays_min, floor_level_min, furnishing_preference
) on requirement to authenticated;
