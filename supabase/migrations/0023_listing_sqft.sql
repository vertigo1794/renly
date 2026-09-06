-- supabase/migrations/0023_listing_sqft.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0022.
--
-- Adds a real built-up size field (previously missing entirely, and
-- deliberately dropped from every earlier restyle this session per the
-- app's own never-fabricate-data convention) so the My Inventory card's
-- Beds/Baths/sqft stat pill can show a genuine value instead of omitting
-- it. Nullable + non-negative, matching the existing bedrooms/bathrooms
-- convention exactly.
--
-- Grants are restated in FULL here (not just the new column) in the same
-- migration as the column add, to avoid repeating 0020's mistake of
-- adding a column without extending the column-scoped INSERT/UPDATE
-- grants that already existed on this table.
alter table listing add column if not exists built_up_sqft integer
  check (built_up_sqft is null or built_up_sqft >= 0);

revoke insert on listing from authenticated;
grant insert (
  negotiator_id, title, description, property_type, transaction_type,
  state, area, price, bedrooms, bathrooms, built_up_sqft,
  commission_split_percent, title_verified, exclusive_mandate
) on listing to authenticated;

revoke update on listing from authenticated;
grant update (
  title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, built_up_sqft, photo_urls, status,
  bumped_at, commission_split_percent, title_verified, exclusive_mandate
) on listing to authenticated;
