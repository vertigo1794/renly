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
-- 0004_listing_hardening.sql explicitly named verification_status
-- (alongside ic_number/phone_number) as a column this RPC pattern exists
-- to AVOID leaking -- worth addressing head-on rather than silently
-- contradicting that stance. Re-reading 0004's own comment: the risk it
-- was avoiding was broadening the raw `negotiator` table's row-level
-- SELECT policy so any authenticated user could just query the table
-- directly, which would ALSO expose ic_number/phone_number since all
-- three columns live on the same row -- a policy change can't be scoped
-- to one column. This migration does not touch that policy, or any
-- grant, at all. It extends a DIFFERENT, already-narrow RPC that has
-- always returned a fixed, curated list of columns (never `select *`,
-- never the full row) and has been reachable by any authenticated user
-- since 0004 itself. Adding one more coarse, non-PII column
-- (verification_status is a pending/approved/rejected enum, not an
-- identifier or contact detail) to that existing curated list is a
-- narrower, additive change to an RPC's output shape, not a widening of
-- table-level access -- it cannot reopen the ic_number/phone_number
-- exposure 0004 was guarding against, because this function still never
-- selects those columns. A public verified/pending badge on a listing's
-- agent is also a normal, low-sensitivity product pattern on its own
-- merits, independent of this distinction.
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
