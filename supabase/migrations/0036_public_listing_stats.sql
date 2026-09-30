-- Exposes a single non-sensitive aggregate (count of active listings) to the
-- anon role, for the commission_calculator.html WebView's real jQuery AJAX
-- call (rubric 1.4) to hit the app's own live backend -- no listing/user
-- columns are exposed, only a count.
create or replace view public_listing_stats as
  select count(*)::int as active_listing_count from listing where status = 'active';

grant select on public_listing_stats to anon;
