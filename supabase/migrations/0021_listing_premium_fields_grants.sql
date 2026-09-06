-- supabase/migrations/0021_listing_premium_fields_grants.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0020.
--
-- 0020 added 4 new listing columns (bumped_at, commission_split_percent,
-- title_verified, exclusive_mandate) but never extended 0004's
-- column-scoped INSERT/UPDATE grants to cover them. A newly-added column
-- is NOT automatically covered by an existing narrower column-list
-- grant -- Postgres checks the exact column list named in the original
-- GRANT statement, so createListing (which always names
-- commission_split_percent/title_verified/exclusive_mandate in its
-- insert map, even when the value is null) and
-- bumpListing/updateListingDetails (which write bumped_at/
-- commission_split_percent/title_verified/exclusive_mandate) were both
-- silently rejected with a column-privilege error, surfaced in the app
-- as the generic "Something went wrong" message -- caught via live
-- manual testing right after 0020 was applied.
--
-- Restating the FULL grant list here, not just the new columns, since
-- `revoke ... from authenticated` wipes every existing column grant on
-- the table -- exactly the lesson already learned the hard way in
-- 0010_profile.sql's negotiator-table grant, just a fresh instance of
-- "a table with a non-empty grant history needs its full grant list
-- restated on any future change, never assumed to auto-extend."

revoke insert on listing from authenticated;
grant insert (
  negotiator_id, title, description, property_type, transaction_type,
  state, area, price, bedrooms, bathrooms,
  commission_split_percent, title_verified, exclusive_mandate
) on listing to authenticated;

revoke update on listing from authenticated;
grant update (
  title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, photo_urls, status,
  bumped_at, commission_split_percent, title_verified, exclusive_mandate
) on listing to authenticated;
