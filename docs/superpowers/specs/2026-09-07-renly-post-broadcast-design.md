# Post Broadcast (Post Listing + Buyer Match Merge) Design

## Goal

Merge `PostListingScreen` and `PostRequirementScreen` behind a single "Provide Listing / Buyer Match" toggle screen, sourced from two Stitch mockups ("Renly - Post Listing (Premium Co-Broking Hub)" and "Renly - Buyer Match (Smart Co-Broking Radar)", project 13581751397915601898). Along the way, give `Requirement` real minimum-spec fields (bathrooms, built-up sqft), a real self-declared commission-split preference, two real buyer-readiness self-attestation flags, and a genuine live match preview on both forms before submission — replacing every fabricated stat the mockups show with either a real equivalent or an outright drop.

## Background

This project's Milestone 4 design doc (`2026-08-17-renly-requirement-design.md`) deliberately kept `PostListingScreen` and `PostRequirementScreen` as two separate screens rather than retrofitting the original mockup's tab toggle, specifically to avoid regression risk on the already-shipped, already-tested Listing form. That reasoning still holds. This design revisits the decision because the user explicitly wants the literal merged-screen UX this time, not because the original reasoning was wrong — the approach below is chosen specifically to preserve that original regression-safety property while still delivering a real single-screen toggle.

Both mockups also introduce several elements this app cannot currently support for real: a "Desired Co-Broke Commission Split" field on Requirement, a "Minimum Specs Required" row (bathrooms + built-up sqft) that Requirement doesn't track at all today, two new buyer-readiness toggles, and a "Preliminary Match Radar" pre-submission match preview. Per this project's own repeatedly-confirmed convention (build real function rather than drop or decorate, established across the Dashboard/Marketplace/Messages/My-Inventory restyles this session), every one of these gets built for real in this design, not faked.

## Screen Architecture

A new top-level widget, `PostBroadcastScreen`, owns the shared chrome: header (RStarBadge + wordmark + REN pill + bell, matching every other restyled screen this session), the real ticker, and the "Provide Listing / Buyer Match" segmented toggle. It does **not** own either form's state or logic.

```dart
class PostBroadcastScreen extends StatefulWidget {
  const PostBroadcastScreen({
    super.key,
    this.initialMode = PostBroadcastMode.listing,
    this.editListingId,
    this.initialDraft,
  });

  final PostBroadcastMode initialMode;
  final String? editListingId;
  final ListingDraft? initialDraft;
}

enum PostBroadcastMode { listing, requirement }
```

Internally, `_PostBroadcastScreenState` renders:

```dart
IndexedStack(
  index: _mode == PostBroadcastMode.listing ? 0 : 1,
  children: [
    PostListingFormBody(editListingId: widget.editListingId, initialDraft: widget.initialDraft),
    const PostRequirementFormBody(),
  ],
)
```

`PostListingFormBody` and `PostRequirementFormBody` are the **existing** `PostListingScreen`/`PostRequirementScreen` bodies, extracted with their `State` classes unchanged — every field controller, validator, `_submit()` method, retry-safety guard, and existing test all keep working exactly as today. Only the outer `Scaffold`/`AppBar` wrapper is removed from each (since `PostBroadcastScreen` now owns the single shared `Scaffold`), and each becomes a plain `Widget` returning its own form content. `IndexedStack` keeps both mounted simultaneously, so toggling back and forth preserves whatever the user typed in either form — no data loss on an accidental tap.

**Toggle visibility:** hidden entirely when `editListingId != null` (editing an existing listing is not a "post new X" flow, and the mockups show no equivalent toggle for it). Shown in every other case, including draft-resume.

**Routing:** both existing routes point at the same screen:

```dart
GoRoute(
  path: '/post-listing',
  builder: (context, state) => PostBroadcastScreen(
    initialMode: PostBroadcastMode.listing,
    initialDraft: state.extra as ListingDraft?,
  ),
),
GoRoute(
  path: '/post-requirement',
  builder: (context, state) => const PostBroadcastScreen(initialMode: PostBroadcastMode.requirement),
),
GoRoute(
  path: '/property/:listingId/edit',
  builder: (context, state) => PostBroadcastScreen(editListingId: state.pathParameters['listingId']),
),
```

Every existing call site that pushes `/post-listing`, `/post-requirement`, or `/property/:id/edit` (the Dashboard FAB, the bottom-nav Post button, the Chat tab's "New Co-Broke" FAB, My Inventory's Edit button, Marketplace's "Request Co-Broke" flow if any) needs no change — the route paths and their param contracts stay identical.

## Data Model: Requirement's New Fields

Migration `0024_requirement_broadcast_fields.sql`:

```sql
alter table requirement add column if not exists bathrooms_min integer
  check (bathrooms_min is null or bathrooms_min >= 0);
alter table requirement add column if not exists built_up_sqft_min integer
  check (built_up_sqft_min is null or built_up_sqft_min >= 0);
alter table requirement add column if not exists desired_commission_split_percent numeric(5,2)
  check (desired_commission_split_percent is null or (desired_commission_split_percent > 0 and desired_commission_split_percent <= 100));
alter table requirement add column if not exists loan_ready boolean not null default false;
alter table requirement add column if not exists urgent_viewing_required boolean not null default false;

revoke insert on requirement from authenticated;
grant insert (
  negotiator_id, property_type, transaction_type, state, area,
  budget_min, budget_max, bedrooms, bathrooms_min, built_up_sqft_min,
  desired_commission_split_percent, loan_ready, urgent_viewing_required
) on requirement to authenticated;

revoke update on requirement from authenticated;
grant update (
  property_type, transaction_type, state, area, budget_min, budget_max,
  bedrooms, bathrooms_min, built_up_sqft_min, desired_commission_split_percent,
  loan_ready, urgent_viewing_required, status, photo_urls
) on requirement to authenticated;
```

Grants are restated in full, in the same migration as the column adds — this project hit a real live bug earlier this session (migration `0020`) from adding columns without extending the existing column-scoped INSERT/UPDATE grants in the same migration; this design applies that lesson from the start rather than needing a follow-up fix migration.

`Requirement` model gains `bathroomsMin` (`int?`), `builtUpSqftMin` (`int?`), `desiredCommissionSplitPercent` (`double?`), `loanReady` (`bool`, default `false`), `urgentViewingRequired` (`bool`, default `false`) — all optional/defaulted, zero blast radius on existing `Requirement(...)` construction sites (mirrors the exact requiredness reasoning used for `Listing`'s equivalent fields earlier this session).

`RequirementRepository.createRequirement` gains the 5 new optional params, inserted into the existing insert map. A new `RequirementRepository.updateRequirementDetails(...)` method is added, mirroring `ListingRepository.updateListingDetails` exactly (general field update, excluding `requirementId`/`negotiatorId`/`status`/`photoUrls`/`createdAt` — each has its own dedicated path or must never change). This method has no caller yet in this design (Requirement still has no edit flow, matching the mockups which show no edit mode for Buyer Match) — it exists for symmetry and because `PostRequirementFormBody`'s validator/field wiring is written once and shared conceptually with Listing's edit-capable form, but is not wired to any UI path this design adds. **If this turns out to be dead code with zero callers by the end of implementation, it should be cut** — this is flagged explicitly so the plan doesn't silently ship an unused method.

## Matching Engine: Bathrooms/Sqft as Qualifying Filters

`MatchingEngine.score()` gains two new mandatory disqualifying checks, alongside the existing `transactionType`/`state` checks — **not** added to the 100-point weighted formula (location 30 / price 35 / property type 25 / bedrooms 10), which stays untouched:

```dart
static int? score(Listing listing, Requirement requirement) {
  if (listing.transactionType != requirement.transactionType) return null;
  if (listing.state != requirement.state) return null;
  if (requirement.bathroomsMin != null &&
      (listing.bathrooms == null || listing.bathrooms! < requirement.bathroomsMin!)) {
    return null;
  }
  if (requirement.builtUpSqftMin != null &&
      (listing.builtUpSqft == null || listing.builtUpSqft! < requirement.builtUpSqftMin!)) {
    return null;
  }

  final location = listing.area.toLowerCase() == requirement.area.toLowerCase() ? 30 : 0;
  final price = _priceScore(listing.price, requirement.budgetMin, requirement.budgetMax);
  final propertyType = listing.propertyType == requirement.propertyType ? 25 : 0;
  final bedrooms = _bedroomScore(listing.bedrooms, requirement.bedrooms);

  return (location + price + propertyType + bedrooms).round();
}
```

Semantics: an unset requirement minimum (`null`) never filters — matches the existing `bedrooms`-unset-scores-full-weight convention, just expressed as "skip the check" instead of "score full marks." A listing with no `bathrooms`/`builtUpSqft` value is disqualified only if the requirement actually set a minimum for that attribute (a genuinely unknown listing attribute can't be confirmed to meet a real minimum, so it's correctly excluded rather than optimistically passed).

`matching_engine_test.dart` gains cases: requirement with `bathroomsMin` set + listing meets it (passes), listing below it (disqualified), listing `bathrooms: null` + requirement `bathroomsMin` set (disqualified), requirement `bathroomsMin: null` + any listing value (never filtered) — same 4-case shape repeated for `builtUpSqftMin`.

## Live Match Preview (Both Forms, Symmetric, Real)

Both `PostListingFormBody` and `PostRequirementFormBody` get a "Preliminary Match Radar"-equivalent section, computed **client-side, before submission**, reusing the exact same `MatchingEngine.score()` already used for real post-submission matching — no new backend endpoint.

**Buyer Match side:** on relevant field change (debounced 500ms), build a scratch `Requirement` object from the current form values (`requirementId: 'preview'`, `negotiatorId` from `currentNegotiatorIdProvider`, `status: 'open'` — placeholder values `MatchingEngine.score()` never reads), fetch `listingRepository.fetchMarketplaceListings()` (existing method, already used by Marketplace), score every listing against the scratch requirement, keep those `>= MatchingEngine.qualifyingThreshold`. Show the real count and the single highest-scoring listing's title + score in a small card. Zero qualifying listings → the whole preview section renders nothing (never a fabricated "0 matches" or placeholder percentage).

**Post Listing side:** the mirror image — a scratch `Listing` built from current form values, scored against `requirementRepository.fetchBoardRequirements()` (existing method, already used by the Requirement Board), same threshold/display/hide-on-zero rules.

Because `IndexedStack` mounts both forms immediately (that's what preserves their state across toggles), each form's own opposing-side fetch (`fetchMarketplaceListings()` for Buyer Match, `fetchBoardRequirements()` for Post Listing) runs once in its own `initState`, not gated on the toggle's visibility — a form fetches its match candidates as soon as `PostBroadcastScreen` builds, whether or not that tab is currently shown. This is a deliberate, minor eagerness cost (one extra background fetch for whichever tab isn't initially active) in exchange for the toggle being instant and stateful in both directions; re-scoring against the already-fetched list on every debounced field change afterward is pure and fast (an in-memory loop), so the only real network cost is that one extra fetch.

Each form's submit-button subtext reads the *same* live-preview count computed for its own side (e.g., "Bakal padan dengan N ejen" for Buyer Match, mirrored copy for Post Listing) — hidden whenever the count is 0, exactly like the preview card itself. This guarantees the subtext and the preview card can never show two different numbers, since both read the identical computed value.

## Real Tickers

- **Post Listing mode:** "N Active Co-Broke Listings" — reuses the existing active-listing count query already backing Marketplace's own ticker.
- **Buyer Match mode:** "N Buyer Demands Active" — a new `RequirementRepository.countOpenRequirements()` method (global count of `status = 'open'` rows, not scoped to the current negotiator — mirrors `fetchBoardRequirements`'s own `eq('status', 'open')` filter, just as a count instead of a full fetch).

## Dropped Elements (No Real Equivalent, Out of Scope)

- "Broadcast to 8,500+ verified Malaysian co-broking negotiators" tagline — no real negotiator-count feature exists or is in scope here.
- "High Demand" badge on the Property Type field — would require a genuinely new demand-scoring subsystem; out of scope.
- The "Instant Auto-Matching... checks 1,420+ verified exclusive listings" banner — fully superseded by the real Preliminary Match Radar section described above; the banner itself (with its fabricated numbers) is not built.

## Self-Attestation Copy: Honesty Framing

Post Listing's existing "Exclusive Mandate Signed" / "Direct Owner / Strata Title Verified" toggles currently read (per the mockup) "Qualifies for 98% Buyer Match Radar" / "Priority visibility to Top 5% Renly Agents" — both imply a third-party-verified outcome the toggle doesn't actually establish. These get the same honest self-declaration framing already shipped for My Inventory's `titleVerified`/`exclusiveMandate` fields: a small notice ("This is a declaration you make yourself, not a third-party verification.") plus first-person caption text ("I confirm..."). The two new Buyer Match toggles (`loanReady`, `urgentViewingRequired`) use the same framing pattern from the start — no mockup captions to correct, since these are brand new fields, but the same honesty principle applies going in.

## Quick-Fill Location Pills

Both forms get a row of tappable location suggestion pills (e.g., Mont Kiara / KLCC / Bangsar / Petaling Jaya) beneath the area text field — tapping one fills the area field with that value. Pure UX convenience, no claimed statistic, so no real-vs-fabricated question applies; included on both forms to match the mockups.

## Testing Approach

- `MatchingEngine`'s new qualifying filters: pure unit tests in `matching_engine_test.dart` (8 new cases per the section above).
- `Requirement`/`ListingDraft`-equivalent model round-trip tests for the 5 new fields (mirrors the `Listing`/`ListingDraft` test pattern from the My Inventory milestone).
- `RequirementRepository`/`ListingRepository` changes are Supabase-boundary code — not unit-tested, per this project's established convention (manually verified once the migration is live).
- `PostBroadcastScreen`: widget tests confirming the toggle switches the visible `IndexedStack` child, both forms' state persists across a toggle-away-and-back, the toggle is absent in edit mode, and each route's `initialMode` renders the correct starting tab.
- Live match preview: since it depends on real Supabase fetches, its debounce/scoring/hide-on-zero LOGIC is extracted into small pure-enough helper functions the tests can exercise directly with fixture listings/requirements, rather than trying to test the full debounced-widget-triggers-a-network-call path end-to-end.
- No golden-image tests, matching every prior restyle this session.

## Explicitly Deferred

- A Requirement edit flow (the mockups show no edit mode for Buyer Match; `updateRequirementDetails` is added for model symmetry only, not wired to any screen — cut it if it ends up unused).
- Any negotiator-count or demand-scoring subsystem needed to make "8,500+ negotiators" / "High Demand" real — these stay dropped, not built, per the section above.
