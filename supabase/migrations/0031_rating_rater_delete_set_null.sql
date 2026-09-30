-- supabase/migrations/0031_rating_rater_delete_set_null.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0030.
--
-- rating.rater_id currently references negotiator(negotiator_id) on
-- delete cascade (0011_rating.sql). If the RATER's negotiator account is
-- ever deleted (e.g. via the Supabase Admin API -- there's no in-app
-- delete-account feature today, so this isn't exploitable yet, but it's
-- a landmine for whenever one ships), the cascade deletes the entire
-- rating row, wiping out the reputation the RATED party legitimately
-- earned through no fault of their own.
--
-- rated_id is left as ON DELETE CASCADE (unchanged): if the RATED party
-- is deleted, there's no one left to show that reputation entry for, so
-- cascading that column is still correct. Only rater_id changes, from
-- CASCADE to SET NULL, which requires making it nullable first.
alter table rating alter column rater_id drop not null;

alter table rating drop constraint if exists rating_rater_id_fkey;
alter table rating
  add constraint rating_rater_id_fkey
  foreign key (rater_id) references negotiator(negotiator_id) on delete set null;
