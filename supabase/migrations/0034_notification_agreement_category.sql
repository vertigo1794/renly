-- supabase/migrations/0034_notification_agreement_category.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0033.
--
-- Agreements (propose/accept/decline) currently send NO push notification
-- at all -- the notification.category CHECK constraint (0018) only allows
-- 'match' | 'message' | 'cobroke_request'. Add 'agreement' as one more
-- category, same one-category-covers-a-few-sub-events shape as the
-- existing three (e.g. 'match' covers both listing-side and
-- requirement-side matches, distinguished by title/body text set at the
-- call site, not by a separate category per sub-event).
alter table notification drop constraint if exists notification_category_check;
alter table notification add constraint notification_category_check
  check (category in ('match', 'message', 'cobroke_request', 'agreement'));
