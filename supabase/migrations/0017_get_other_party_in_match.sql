-- supabase/migrations/0017_get_other_party_in_match.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0016.
--
-- push-notification recipient resolution (CobrokeRequestRepository,
-- MessageRepository) was querying match->listing/requirement directly
-- from the client, relying on listing_select/requirement_select's RLS
-- (own row OR active/open status) to see both parties' negotiator_id.
-- The instant either side marks their listing sold/withdrawn or
-- requirement fulfilled/withdrawn, the OTHER party's client can no
-- longer see that row at all -- the query silently returns zero rows and
-- push notifications for that conversation permanently stop. Same
-- failure class this project already solved for get_negotiator_public_info
-- (0004_listing_hardening.sql, renamed in 0015) and is_agreement_party
-- (0011_rating.sql):
-- a narrowly-scoped SECURITY DEFINER function that only ever returns a
-- negotiator_id already implicitly visible to the caller via the match
-- they're a legitimate party to.
create or replace function get_other_party_in_match(p_match_id uuid, p_actor_id uuid)
returns uuid
language sql
security definer
set search_path = public
as $$
  select case
    when l.negotiator_id != p_actor_id then l.negotiator_id
    else r.negotiator_id
  end
  from match m
  join listing l on l.listing_id = m.listing_id
  join requirement r on r.requirement_id = m.requirement_id
  where m.match_id = p_match_id;
$$;

revoke execute on function get_other_party_in_match(uuid, uuid) from public;
grant execute on function get_other_party_in_match(uuid, uuid) to authenticated;
