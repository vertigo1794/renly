-- supabase/migrations/0026_negotiator_public_info_verification_status.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0025.
--
-- Extends get_negotiator_public_info (0004_listing_hardening.sql, renamed
-- in 0015, extended with agency_name in 0019) to also return
-- verification_status, needed by the Property Detail Ultra-Premium
-- Restyle's Agent card real verified-checkmark. Same SECURITY DEFINER
-- justification as 0019's own addition: callers can already see
-- full_name/ren_number/agency_name for any negotiator party to a
-- listing/requirement/match they're a legitimate counterparty to;
-- verification_status is no more sensitive than those.
--
-- Postgres does NOT allow CREATE OR REPLACE FUNCTION to change a
-- function's return type (RETURNS TABLE compiles to OUT parameters) --
-- the function must be dropped and recreated instead, same as 0019 had
-- to do. Dropping a function discards its existing grants, so they are
-- explicitly restated below.
drop function if exists get_negotiator_public_info(uuid);

create function get_negotiator_public_info(p_negotiator_id uuid)
returns table (full_name text, ren_number text, agency_name text, verification_status text)
language sql
security definer
set search_path = public
as $$
  select n.full_name, n.ren_number, a.firm_name, n.verification_status
  from negotiator n
  left join agency a on a.agency_id = n.agency_id
  where n.negotiator_id = p_negotiator_id;
$$;

revoke execute on function get_negotiator_public_info(uuid) from public;
grant execute on function get_negotiator_public_info(uuid) to authenticated;
