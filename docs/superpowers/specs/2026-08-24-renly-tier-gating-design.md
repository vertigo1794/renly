# renly — Tier-Gating Enforcement Design

## Goal

Enforce the Free-tier cap (max 3 active listings, max 3 active requirements, independently) now that `subscription_tier` is genuinely flippable end-to-end via the Subscription Core (Stripe) module. Professional tier: unlimited.

## Source of truth

Sub-milestone B of the Subscription/Billing feature (proposal build-order step 6, "posting limits" half — the "notification delay" half remains out of scope, deferred until FCM exists project-wide). The cap value (3) and the independent-per-table shape (3 listings AND separately 3 requirements, not a combined pool) were decided during Subscription Core's own brainstorm and confirmed again at the start of this design cycle.

## Architecture

Two layers, matching this project's established defense-in-depth precedent (Matching Engine's `before insert` trigger on `match`, which exists specifically because "scoring itself is deliberately client-side and untrusted"):

1. **A Postgres trigger on each table** (`listing`, `requirement`) — the actual, unbypassable enforcement. Fires on `before insert or update`, but only takes effect when a row is transitioning **into** the active state (`status = 'active'`/`'open'`) — a brand-new post, or a **reactivation** of a previously withdrawn one. It does nothing on other transitions (going inactive, staying active, editing unrelated fields).
2. **Client-side pre-checks** in Flutter — read-only counts + the current tier, used purely for UX (a live "2/3 active" indicator and blocking the submit button before a doomed request is even sent). These never substitute for the trigger; an authenticated client bypassing the UI entirely still hits the trigger.

## The reactivation path (found during this design's own research, not assumed)

`PropertyDetailScreen` already has a "Mark Active" button (shown whenever `listing.status != 'active'`) and `RequirementDetailScreen` has an equivalent "Mark Open" button — both call the same `_changeStatus` method already used for sold/fulfilled/withdrawn. This means a free-tier negotiator with 3 active listings and 2 withdrawn ones could reactivate a withdrawn one directly, without ever passing through `PostListingScreen`, landing at 4 active listings if this path isn't gated too. The trigger's `TG_OP = 'UPDATE'` branch exists specifically to close this — and the client-side pre-check needs to live on both detail screens' reactivate buttons, not just the two Post screens.

## Trigger logic (data model)

```sql
create or replace function check_listing_active_cap() returns trigger as $$
declare
  tier text;
  active_count int;
begin
  -- Only gate transitions INTO 'active' -- a brand new listing, or
  -- reactivation of a withdrawn one. Not fired when status stays active,
  -- moves OUT of active, or an unrelated field is edited.
  if new.status != 'active' or (TG_OP = 'UPDATE' and old.status = 'active') then
    return new;
  end if;

  select subscription_tier into tier from negotiator where negotiator_id = new.negotiator_id;
  if tier = 'professional' then
    return new;
  end if;

  select count(*) into active_count from listing where negotiator_id = new.negotiator_id and status = 'active';
  if active_count >= 3 then
    raise exception 'Free tier is limited to 3 active listings. Upgrade to Professional for unlimited listings.';
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists listing_active_cap_trigger on listing;
create trigger listing_active_cap_trigger
  before insert or update on listing for each row
  execute function check_listing_active_cap();
```

`requirement`'s trigger is the structural mirror (`status = 'open'`, `requirement` table, "3 active requirements" wording). No `security definer` needed — this trigger only ever reads `negotiator.subscription_tier` for the SAME negotiator who owns the row being inserted/updated (their own row, already visible to them under `negotiator_select_own`), unlike the cross-user cases that required it in Ratings/Listing — so it correctly runs as the invoking role with no RLS trap.

No RLS/grant changes needed on either table — this is purely a `before` trigger, transparent to the existing insert/update policies.

## Client-side

- `ListingRepository`/`RequirementRepository` each gain a `countActiveListings`/`countActiveRequirements`-shaped method (reusing the exact `.count(CountOption.exact)` pattern `ProfileRepository.countActiveListings` already established), or the existing `ProfileRepository` methods are reused directly where already in scope — the plan decides the exact placement, but the query shape is not reinvented.
- A small combining read (tier + active count) drives: (a) `PostListingScreen`/`PostRequirementScreen` — a live "X/3 active listings" text near the submit button, submit disabled with an upsell message when `tier == 'free' && count >= 3`; (b) `PropertyDetailScreen`'s/`RequirementDetailScreen`'s "Mark Active"/"Mark Open" button — same disabled-with-upsell treatment when at cap, professional tier always enabled.
- Error handling: the trigger's `raise exception` surfaces client-side as a `PostgrestException` with that message. Both submit paths catch this specific case and show it directly (it's already a clear, actionable, non-technical message) rather than falling through to the generic `listing_error_generic` — this is an expected, common condition for a free-tier user, not a random failure, and deserves to read that way.

## Testing approach

Trigger logic: no automated test (Supabase-boundary code, established convention) — verified manually per this project's existing README milestone-setup pattern (create 3 active listings as a free-tier negotiator, confirm a 4th is rejected with the expected message; confirm reactivating a withdrawn 4th is also rejected; confirm a Professional-tier negotiator is never blocked). Client-side count/tier composition and the Post-screen/Detail-screen UI states get widget tests via provider override, following established conventions.

## Explicitly deferred / out of scope

- The proposal's "notification delay for Free tier" — still blocked on FCM, unrelated to this sub-milestone.
- Any UI for a downgraded-over-cap negotiator beyond the trigger's natural grandfathering behavior (their existing over-cap active rows are never touched, they simply can't create/reactivate a new one until back under 3) — no special "you're over your limit" banner or forced cleanup flow.
- A combined listing+requirement pool — the cap is independently 3+3, not a shared 3, per explicit confirmation.
