# Property Detail Ultra-Premium Restyle — Design

## Overview

`PropertyDetailScreen` is restyled from a Stitch mockup ("Renly - Property Detail (Ultra-Premium Co-Broking)", project `13581751397915601898`, screen `bf88fcc3a3524a3aad11fdf13d772d6d`, HTML fetched to `/tmp/stitch_property_detail/property_detail.html`). The mockup introduces many elements with no backing data today. Per this project's own never-fabricate-data convention (enforced repeatedly across every prior restyle this session), each element gets one of three treatments, decided explicitly with the user rather than assumed:

- **Real** — backed by an existing or newly-migrated real field, computed from real data, hidden when the backing value is null/false.
- **Reframed** — the mockup's copy is replaced with an honest statement about a mechanic that genuinely exists today.
- **Deferred** — the underlying capability doesn't exist and is large enough to be its own future sub-project; the element is omitted from this pass rather than faked.

## Scope Decomposition

This mockup's full ambition spans three independent sub-projects. Only #1 is designed and planned here; #2 and #3 are logged as backlog for future brainstorm→plan cycles, matching this project's own precedent (the Collaboration module was split into 3 sub-milestones the same way).

1. **Property Detail Ultra-Premium Restyle** (this spec) — the screen itself, new Listing property-attribute fields, real 98%-match badge, real rating reuse, honest reframes.
2. **Viewing Request/Booking subsystem** (future) — buyer requests a viewing slot, owner confirms/declines, real notification. A genuinely new subsystem (new table, new screens, new flow).
3. **Maps/Location integration** (future) — a real embedded map + landmark-distance callouts needs a maps SDK, an API key/billing decision, and geocoding. Out of scope until that infra decision is made separately.

## Data Model

New migration `supabase/migrations/0025_listing_property_details.sql`, adding to `listing`:

```sql
-- supabase/migrations/0025_listing_property_details.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0024.
--
-- New real property-attribute fields for the Property Detail Ultra-Premium
-- Restyle: maintenance fee, tenure, parking bays, floor level, furnishing
-- status (all owner-set, all nullable -- absent means the owner didn't set
-- it, never a fabricated/estimated fallback), plus two new self-attested
-- toggles (keys_on_hand, protected_co_broke_reg -- NOT third-party
-- verified, same honesty framing as title_verified/exclusive_mandate) and
-- a standalone total_agency_commission_percent (distinct from the existing
-- commission_split_percent, which is the OWNER's own advertised split of
-- that total to a co-broker).
--
-- Grants are restated in FULL here (not just the new columns), in the
-- SAME migration as the column adds -- this project hit two real live
-- bugs earlier this session (migrations 0010 and 0020) from not doing
-- this; this migration applies that lesson from the start.
alter table listing add column if not exists maintenance_fee_myr numeric(10,2)
  check (maintenance_fee_myr is null or maintenance_fee_myr >= 0);
alter table listing add column if not exists tenure text
  check (tenure is null or tenure in ('freehold', 'leasehold'));
alter table listing add column if not exists parking_bays integer
  check (parking_bays is null or parking_bays >= 0);
alter table listing add column if not exists floor_level integer;
alter table listing add column if not exists furnishing_status text
  check (furnishing_status is null or furnishing_status in ('furnished', 'partially_furnished', 'unfurnished'));
alter table listing add column if not exists keys_on_hand boolean not null default false;
alter table listing add column if not exists protected_co_broke_reg boolean not null default false;
alter table listing add column if not exists total_agency_commission_percent numeric(5,2)
  check (total_agency_commission_percent is null or (total_agency_commission_percent > 0 and total_agency_commission_percent <= 100));

revoke insert on listing from authenticated;
grant insert (
  negotiator_id, title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, built_up_sqft,
  commission_split_percent, title_verified, exclusive_mandate,
  maintenance_fee_myr, tenure, parking_bays, floor_level, furnishing_status,
  keys_on_hand, protected_co_broke_reg, total_agency_commission_percent
) on listing to authenticated;

revoke update on listing from authenticated;
grant update (
  title, description, property_type, transaction_type, state, area,
  price, bedrooms, bathrooms, built_up_sqft, photo_urls, status,
  commission_split_percent, title_verified, exclusive_mandate, bumped_at,
  maintenance_fee_myr, tenure, parking_bays, floor_level, furnishing_status,
  keys_on_hand, protected_co_broke_reg, total_agency_commission_percent
) on listing to authenticated;
```

`Listing` model gains the 8 new fields (all nullable except the 2 booleans, which default `false` — same pattern as `titleVerified`/`exclusiveMandate`, zero blast radius on existing `const`-free constructor call sites since `Listing` is already not `const`-constructible).

`ListingRepository.createListing`/`updateListingDetails` gain the 8 new optional params, threaded straight into the insert/update maps — same mechanical pattern as every prior field addition this session.

## Post Listing Form Additions

`PostListingFormBody` gains, after the existing sqft/commission-split section:
- A second `SpecStatField` row (reusing the shared widget from `broadcast_badge.dart`): Parking Bays, Floor Level, Furnishing (furnishing rendered as a 3-option dropdown inline in the stat card, not free text — the only stat field that isn't a plain number).
- A `Tenure` dropdown (Freehold/Leasehold, unset by default) next to Property Type.
- A `Maintenance Fee (RM/month)` text field next to Price.
- A `Total Agency Commission (%)` text field, plain number input — distinct field from the existing Commission Split preset-chip section, since it represents a different concept (the deal's total commission rate vs. the owner's own advertised split of it).
- Two new `SwitchListTile`s for `keysOnHand`/`protectedCoBrokeReg`, reusing the existing `listing_self_attestation_notice` line and caption pattern already established for `titleVerified`/`exclusiveMandate`.

## Screen Layout — Card by Card

Structure mirrors the mockup's own visual sectioning exactly; each card becomes one extracted private widget in `property_detail_screen.dart`, matching this project's own per-section-widget extraction convention (e.g. Post Broadcast's `_TickerBar`).

**1. Hero header** (`_HeroHeader`) — existing `PageView` photo carousel, unchanged. Floating frosted-glass back/share/favorite buttons (new visual treatment, same real actions). Floating badges top-left: real `N% MATCH` pill (see Match Badge below, hidden if not applicable) + real `Exclusive Mandate` pill (shown only when `listing.exclusiveMandate`). Bottom-right: real photo-counter pill `N/M Photos` (`photoUrls.length`, hidden if 0).

**2. Dark Deal-Terms banner** (`_DealTermsBanner`) — dark card (`#0f172a`), lime accents, matching mockup's exact visual style. Top row: `CO-BROKE READY` label shown only when `commissionSplitPercent != null` (real condition) — `INSTANT PAYOUT` and `BOVAEA Verified` dropped entirely (no backing, no reframe possible — these implied a payment/escrow system and a third-party verification body that don't exist). Price row: real price, real `RM {price/builtUpSqft} / sqft` (shown only when both set), real `Maint. RM {maintenanceFeeMyr}/mo` (hidden if null). Right pill: real `{commissionSplitPercent}/{100-commissionSplitPercent}` split display + real fee (`price * commissionSplitPercent / 100`).

**3. Main Overview card** (`_OverviewCard`) — top row: property-type + tenure tag (`CONDOMINIUM • FREEHOLD`, tenure segment hidden if null) + `ID: #{listingId short}` (first 8 chars of the real UUID, uppercased — real data, not a fabricated reference-number scheme). Title (existing). Location row: existing area/state text + a real "Map" button that opens the device's own maps app via `url_launcher` with the address as a search query (this is NOT the deferred in-app embedded map — it's a one-line external-intent launch, genuinely trivial, no SDK/API key needed). Key-specs bento grid: 6 cells, Beds/Baths/Built-up (existing) + Parking/Floor/Furnishing (new, each cell hidden individually when its value is null — grid reflows from 6 to fewer cells rather than showing empty boxes). Description (existing). Badges row: Exclusive Mandate (existing field, reused — not duplicated from the hero badge) + Keys on Hand (new) + Protected Co-Broke Reg (new), each hidden when false.

**4. Co-Broking Terms card** (`_CoBrokingTermsCard`) — "Standard 50/50" header badge becomes real, computed from `commissionSplitPercent` (shows the actual split, not a hardcoded "50/50"). Total Agency Commission row: real `totalAgencyCommissionPercent` + real RM amount (`price * totalAgencyCommissionPercent / 100`), hidden entirely if unset. Your Co-Broke Share row: same real split%/fee as the hero banner. "Next Available Viewing" row: **omitted** (sub-project 2). Guarantee line: reframed from the fabricated "60 days" claim to `Renly protects your registration: only one active co-broke request per match` — a real, already-enforced mechanic (the partial unique index from the Co-Broke Request milestone).

**5. Agent card** (`_AgentCard`) — name/REN/agency (existing, real). Real rating display `X.X (N Deals)` reusing `ratingsForNegotiatorProvider` + the exact average formula already used by Profile's `_TrustScoreCard` (`stars.reduce(+)/length`, one decimal), hidden (shows nothing, not a fake "New Agent" placeholder) when the candidate list is empty — matches this project's own hide-on-null convention. Verified checkmark reuses the existing real `verificationStatus == 'approved'` check. Call button **removed** (calling it would require exposing `phone_number` through the public listing-owner RPC, a deliberate privacy boundary this project drew on purpose in the Profile milestone). Chat button becomes a labeled `Message` button (not icon-only), routing to the existing real chat/co-broke-request flow unchanged.

**6. Bottom CTA bar** (`_ActionBar`) — "Client" button: real OS share sheet via `share_plus`, reusing the exact pattern My Inventory's own Share action already established. Main CTA relabeled `Request Co-Broke` (drops "& Viewing" — honest until sub-project 2 ships), routes to the existing real co-broke-request flow unchanged.

## Match Badge Computation

A new pure function, mirroring `LiveMatchPreview`'s own zero-DB-write pattern: given the current listing and the viewer's own fetched open requirements (via `fetchOwnRequirements(viewerNegotiatorId)`, called once in `initState`, best-effort try/catch matching every other preview-fetch in this codebase), compute `MatchingEngine.score()` against each, keep the highest. Rendered only when: viewer is not the listing's owner, the viewer has at least one open requirement, and the best score clears `MatchingEngine.qualifyingThreshold` (40) — matching the same qualifying-threshold semantics already established for every other match computation in this app. Lives in `live_match_preview.dart` as a small new top-level function (not a new file), since it's a single pure calculation, not a stateful subsystem.

## Testing

- `PropertyDetailScreen`'s Supabase-boundary repository calls stay untested by convention (manually verified later, matching every prior milestone).
- The new match-badge pure function gets real unit tests in `matching_engine_test.dart` or a new small test file, mirroring `live_match_preview_test.dart`'s own fixture style — including a case proving a single non-owner viewer with no qualifying requirement correctly yields no badge (never a fabricated fallback).
- Widget tests extend the existing `property_detail_screen_test.dart` fixtures with the new field-hidden-when-null cases (parking/floor/furnishing/maintenance/tenure/total-commission all individually optional) and the two new toggle badges' hidden-when-false cases.

## Explicitly Deferred

- Viewing Request/Booking subsystem (sub-project 2, above).
- Maps/Location integration (sub-project 3, above).
- Agent reply-time stat (`Replies < 5m`) — dropped; no backing data, and computing it would need a new cross-conversation average-reply-latency query unrelated to this screen's own purpose.
- Call Agent button — dropped; would require exposing `phone_number` through the public listing-owner RPC, breaking a deliberate privacy boundary.
