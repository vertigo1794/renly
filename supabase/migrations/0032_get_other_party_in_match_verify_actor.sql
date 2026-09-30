-- supabase/migrations/0032_get_other_party_in_match_verify_actor.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0031.
--
-- get_other_party_in_match (0017) is SECURITY DEFINER and granted to
-- authenticated, but never checked that p_actor_id is genuinely one of
-- the two negotiators on p_match_id -- it just returned "whichever side
-- isn't p_actor_id" unconditionally. A caller who already knows a real
-- match_id could pass any other negotiator's id as p_actor_id and get
-- back a real negotiator_id for a match they're not actually part of.
--
-- Same fix shape as is_agreement_party (0011_rating.sql): verify
-- p_actor_id matches the match's listing.negotiator_id or
-- requirement.negotiator_id before returning anything.
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
  where m.match_id = p_match_id
    and p_actor_id in (l.negotiator_id, r.negotiator_id);
$$;

revoke execute on function get_other_party_in_match(uuid, uuid) from public;
grant execute on function get_other_party_in_match(uuid, uuid) to authenticated;
