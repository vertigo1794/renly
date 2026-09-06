-- supabase/migrations/0024_requirement_broadcast_fields.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0023.
--
-- Five new buyer-set fields for the Post Broadcast (Post Listing + Buyer
-- Match merge) milestone: bathrooms_min/built_up_sqft_min (real minimum
-- specs the buyer requires, used as MATCHING ENGINE QUALIFYING FILTERS,
-- not part of the existing 100-point weighted score), desired_commission_
-- split_percent (the buyer's own advertised/desired co-broke split,
-- self-set, standalone from Listing's own commission_split_percent and
-- from Agreement's post-deal formal split), and loan_ready/
-- urgent_viewing_required (self-attested by the requirement's own owner
-- -- NOT third-party verified; the in-app form's own caption makes this
-- explicit, this migration only adds the storage for it).
--
-- Grants are restated in FULL here (not just the new columns), in the
-- SAME migration as the column adds -- this project hit a real live bug
-- earlier this session (migration 0020) from adding columns without
-- extending the existing column-scoped INSERT/UPDATE grants in the same
-- migration; this migration applies that lesson from the start.
alter table requirement add column if not exists bathrooms_min integer
  check (bathrooms_min is null or bathrooms_min >= 0);
alter table requirement add column if not exists built_up_sqft_min integer
  check (built_up_sqft_min is null or built_up_sqft_min >= 0);
alter table requirement add column if not exists desired_commission_split_percent numeric(5,2)
  check (desired_commission_split_percent is null or (desired_commission_split_percent > 0 and desired_commission_split_percent <= 100));
alter table requirement add column if not exists loan_ready boolean not null default false;
alter table requirement add column if not exists urgent_viewing_required boolean not null default false;

revoke insert on requirement from authenticated;
grant insert (
  negotiator_id, property_type, transaction_type, state, area,
  budget_min, budget_max, bedrooms, bathrooms_min, built_up_sqft_min,
  desired_commission_split_percent, loan_ready, urgent_viewing_required
) on requirement to authenticated;

revoke update on requirement from authenticated;
grant update (
  property_type, transaction_type, state, area, budget_min, budget_max,
  bedrooms, bathrooms_min, built_up_sqft_min, desired_commission_split_percent,
  loan_ready, urgent_viewing_required, status, photo_urls
) on requirement to authenticated;
