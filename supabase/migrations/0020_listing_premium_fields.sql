-- supabase/migrations/0020_listing_premium_fields.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0019.
--
-- Three new negotiator-set fields for the My Inventory Premium Restyle:
-- bumped_at (a real "resurface to top of feed" signal, kept separate from
-- created_at so a bump never falsifies a listing's true age elsewhere in
-- the app -- e.g. Dashboard's Recent Listings relative timestamp),
-- commission_split_percent (the owner's own advertised co-broke split,
-- standalone from Agreement's post-deal formal split), and
-- title_verified/exclusive_mandate (self-attested by the owner -- NOT
-- third-party verified; the in-app posting form's own caption makes this
-- explicit, this migration only adds the storage for it).
alter table listing add column if not exists bumped_at timestamptz;
alter table listing add column if not exists commission_split_percent numeric(5,2)
  check (commission_split_percent is null or (commission_split_percent > 0 and commission_split_percent <= 100));
alter table listing add column if not exists title_verified boolean not null default false;
alter table listing add column if not exists exclusive_mandate boolean not null default false;
