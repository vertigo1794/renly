-- supabase/migrations/0019_negotiator_public_info_agency_name.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0018.
--
-- Extends get_negotiator_public_info (0004_listing_hardening.sql, renamed
-- in 0015) to also return the negotiator's agency firm_name, needed by the
-- Main Dashboard redesign's Co-Broking Radar card (shows the matched
-- agent's agency as a trust signal, per the Stitch mockup). Same
-- SECURITY DEFINER justification as the original: callers can already see
-- full_name/ren_number for any negotiator party to a listing/requirement/
-- match they're a legitimate counterparty to; agency_name is no more
-- sensitive than those two.
create or replace function get_negotiator_public_info(p_negotiator_id uuid)
returns table (full_name text, ren_number text, agency_name text)
language sql
security definer
set search_path = public
as $$
  select n.full_name, n.ren_number, a.firm_name
  from negotiator n
  left join agency a on a.agency_id = n.agency_id
  where n.negotiator_id = p_negotiator_id;
$$;

-- ren_number/full_name grants already exist from 0004; re-stating the
-- function signature via create-or-replace does not require re-granting
-- since the signature (arg types) is unchanged and REVOKE/GRANT is on the
-- function identity, not its return type.
