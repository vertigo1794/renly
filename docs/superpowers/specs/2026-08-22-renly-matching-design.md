# renly — Matching Engine Design

Status: approved (2026-08-22). Fifth milestone, built on Listing (`docs/superpowers/specs/2026-08-17-renly-listing-design.md`) and Requirement (`docs/superpowers/specs/2026-08-17-renly-requirement-design.md`), both merged. Design/features still expected to evolve — this is the working spec, not a frozen contract.

## Goal

Rank each `listing` against every open `requirement` (and vice versa) using the weighted scoring algorithm from the project proposal (§6.4), persist qualifying pairs in a new `match` table, and let a negotiator view ranked matches for a specific listing/requirement or across all their own records.

## Source of truth

Verified directly against `Fakhrullah_Renly_Project_Proposal.pdf` §6.4 and the ERD (§6.3), not just the Milestone-1 summary in `2026-08-16-renly-mvp-design.md`. Quoted verbatim where it matters:

> "Two attributes act as mandatory filters: transaction type and state. A mismatch in either disqualifies the pair entirely... location or district contributes up to thirty points, price against the stated budget range contributes up to thirty-five points, property type contributes up to twenty-five points, and bedroom count contributes up to ten points. Pairs scoring below a defined threshold will be discarded rather than stored... A listing priced within the stated budget range receives the full weighting, one priced up to ten per cent above the maximum receives a reduced score, and one priced beyond that receives zero for this attribute."

The proposal does **not** specify: the exact threshold number, how "location or district" degrades when the schema has no separate district field (only `area`), or a graduated curve for bedroom count. These are filled in below as explicit, named decisions — not proposal requirements.

**Two deliberate departures from the proposal, both agreed with the user:**
- **Scoring runs client-side (Dart), not as a Postgres function** as §6.4/§8.4 architecture describes. Matches the pattern every prior milestone already uses (`ListingFormatting`, `RequirementStatusFilter`) — pure, cheap-to-test Dart, not a second implementation language. Trade-off: a client can theoretically insert a self-serving match row (see RLS below) — accepted for this project's risk profile, same class of trade-off as prior milestones' RLS decisions.
- **No push notification delivery.** The proposal's step 6 ("Notification: candidate matches... delivered to both negotiators as push notifications") needs Firebase Cloud Messaging, which nothing in this app has wired up through 4 milestones. Matches surface only when a negotiator opens the relevant screen. The project's own survey data (Appendix, B8) shows "Instant notifications" at 15.8% demand vs. "Automatic matching" at 32.9% — matching itself is the priority, notification delivery is a reasonable module to defer.

## Data model

```sql
create table match (
  match_id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listing(listing_id) on delete cascade,
  requirement_id uuid not null references requirement(requirement_id) on delete cascade,
  score integer not null check (score >= 0 and score <= 100),
  created_at timestamptz not null default now(),
  unique (listing_id, requirement_id)
);
```

Deviates from the ERD's field name `generated_at` → uses `created_at` instead, for consistency with every other table in this codebase (`listing`, `requirement` both use `created_at`). A deliberate, named deviation, not an oversight.

**No update path.** Neither `listing` nor `requirement` has an edit flow (Milestones 3-4 only ever built create + status-change + photo-attach) — every field the scorer reads (`propertyType`, `transactionType`, `state`, `area`, `price`/`budgetMin`/`budgetMax`, `bedrooms`) is immutable for a row's lifetime. A given `(listing_id, requirement_id)` pair's score therefore never changes once computed. Inserts use `on conflict (listing_id, requirement_id) do nothing` — never an update.

**Status changes do not touch `match`.** When a listing is marked sold/withdrawn or a requirement fulfilled/withdrawn, existing match rows are left alone (not deleted) — screens filter to only show matches where both sides are still `active`/`open` at query time. A side effect: reactivating a listing/requirement makes its old matches reappear automatically, with no recompute needed.

## RLS

```sql
alter table match enable row level security;

create policy match_select on match for select
  to authenticated using (
    exists (select 1 from listing l where l.listing_id = match.listing_id and l.negotiator_id = auth.uid())
    or exists (select 1 from requirement r where r.requirement_id = match.requirement_id and r.negotiator_id = auth.uid())
  );

create policy match_insert on match for insert
  to authenticated with check (
    exists (select 1 from listing l where l.listing_id = match.listing_id and l.negotiator_id = auth.uid())
    or exists (select 1 from requirement r where r.requirement_id = match.requirement_id and r.negotiator_id = auth.uid())
  );
```

`match` has no `negotiator_id` column of its own — ownership is determined by joining to `listing`/`requirement`, since a match inherently touches two different negotiators' records (that's the whole point of co-broking). A negotiator sees a match if they own **either** side.

INSERT uses the same ownership check: a client can only insert a match row that touches at least one of their own listings/requirements — the auto-compute flow always satisfies this, since it always runs against the negotiator's own newly-created row. **Named trade-off:** since scoring happens client-side, a negotiator could theoretically insert a fabricated score for a pair touching their own row. Low severity for this project (no payment/reputation data at stake yet, and the only person who could be misled by an inflated match score is the negotiator who forged it or their counterparty who'd notice a nonsensical pairing) — accepted rather than moving scoring into a `security definer` RPC, which would reopen the client-vs-Postgres-function decision the user already settled.

## Algorithm

Pure Dart, in `lib/features/matching/matching_engine.dart` — zero Flutter/Supabase dependency, fully unit-testable, mirrors the `ListingFormatting`/`RequirementFormatting` precedent.

**Mandatory filters (from proposal, verbatim):** `listing.transactionType == requirement.transactionType` and `listing.state == requirement.state`. Mismatch on either → not a match, score not computed, no row.

**Weighted score (max 100), decisions not in the proposal marked *(assumed)*:**

| Attribute | Max | Logic |
|---|---|---|
| Location | 30 | *(assumed)* `listing.area.toLowerCase() == requirement.area.toLowerCase()` → 30, else 0. Binary, not graduated — the proposal's "location or district" implies a structured district field this schema doesn't have; `area` is free text, so partial/fuzzy matching isn't attempted. |
| Price | 35 | From proposal, exact: `listing.price` inside `[requirement.budgetMin, requirement.budgetMax]` → 35. Above `budgetMax`, linear reduction to 0 at `budgetMax * 1.10`; beyond that, 0. *(assumed)* Below `budgetMin` → 35 (still affordable; proposal only defines a penalty for being over budget). |
| Property type | 25 | From proposal: exact `propertyType` match → 25, else 0. |
| Bedrooms | 10 | *(assumed)* `requirement.bedrooms == null` (client didn't specify) → 10. Both set and equal → 10. Both set and different → 0. Binary — proposal gives no curve. |

**Threshold:** *(assumed)* total score `>= 40` to qualify as a match and be inserted. Not specified anywhere in the proposal ("a defined threshold" is never given a number) — chosen to cast a reasonably wide discovery net without surfacing near-zero pairs. Tunable later; not wired to any settings UI in this milestone.

**Rounding:** score rounded to the nearest integer before storage (the price curve can produce fractional intermediate values; `match.score` is `integer`).

```dart
class MatchingEngine {
  MatchingEngine._();

  static const qualifyingThreshold = 40;

  /// Returns null if a mandatory filter disqualifies the pair.
  static int? score(Listing listing, Requirement requirement) {
    if (listing.transactionType != requirement.transactionType) return null;
    if (listing.state != requirement.state) return null;

    final location = listing.area.toLowerCase() == requirement.area.toLowerCase() ? 30 : 0;
    final price = _priceScore(listing.price, requirement.budgetMin, requirement.budgetMax);
    final propertyType = listing.propertyType == requirement.propertyType ? 25 : 0;
    final bedrooms = _bedroomScore(listing.bedrooms, requirement.bedrooms);

    return (location + price + propertyType + bedrooms).round();
  }

  static double _priceScore(double price, double budgetMin, double budgetMax) {
    if (price <= budgetMax) return 35;
    final overMax = budgetMax * 1.10;
    if (price >= overMax) return 0;
    final fraction = (overMax - price) / (overMax - budgetMax);
    return 35 * fraction;
  }

  static int _bedroomScore(int? listingBedrooms, int? requirementBedrooms) {
    if (requirementBedrooms == null) return 10;
    if (listingBedrooms == requirementBedrooms) return 10;
    return 0;
  }
}
```

## Screens

All under `lib/features/matching/`.

1. **`MatchesForListingScreen`** and **`MatchesForRequirementScreen`** — near-mirror screens (swap which side is "known from context" vs. "the other side being ranked"). List of `MatchCandidate`s sorted by score descending, each row showing the other side's key facts (property type/transaction, price or budget range, area, bedrooms, owner name+REN) and the score. Tap → the other side's existing detail screen (`PropertyDetailScreen`/`RequirementDetailScreen`). Reached via a new "View Matches" button added to `PropertyDetailScreen` (owner-only, alongside the existing status actions) and `RequirementDetailScreen`.
2. **`MyMatchesScreen`** — every match touching the negotiator's own listings or requirements (either side), most-recent or highest-score first. For each row, determines whether the negotiator owns the listing or the requirement side, and displays the **other** side's info the same way the per-item screens do. Tap → the other side's detail screen. Reached via a new "My Matches" link on `HomePlaceholderScreen`.

`HomePlaceholderScreen` gains one more navigation link (My Matches), alongside the existing four.

## File structure

```
lib/
  features/
    matching/
      matching_engine.dart          # pure scoring, no Supabase
      matching_repository.dart      # sole Supabase touchpoint: compute+store, fetch x3
      matching_providers.dart       # Riverpod: matchingRepositoryProvider, matchesForListingProvider, matchesForRequirementProvider, myMatchesProvider
      matches_for_listing_screen.dart
      matches_for_requirement_screen.dart
      my_matches_screen.dart
      models/
        match.dart                  # raw `match` row: matchId, listingId, requirementId, score, createdAt
        match_candidate.dart        # repository-composed view: matchId, score, listing, requirement, listingOwner, requirementOwner
```

`MatchCandidate` always carries **both** sides' full `Listing`/`Requirement`/`ListingOwner` objects, even on the per-item screens where one side is already known from context (a small, deliberate over-fetch: one shared model and one shared list-row widget across all three screens, instead of three near-duplicate models). Reuses `Listing`/`Requirement`/`ListingOwner` from the listing/requirement features directly — no new owner or entity model, same reuse precedent as Requirement reusing `ListingOwner`.

`MatchingRepository` reuses `RequirementRepository.fetchBoardRequirements()` and `ListingRepository.fetchMarketplaceListings()` to get the "opposing open records" side of a compute pass — cross-feature reads, acceptable here since matching is inherently cross-feature (unlike the `currentNegotiatorIdProvider` duplication precedent, which existed specifically to avoid a needless cross-feature dependency for something session-local).

## Router

New routes, all requiring a session: `/property/:listingId/matches` → `MatchesForListingScreen`, `/requirement-board/:requirementId/matches` → `MatchesForRequirementScreen`, `/my-matches` → `MyMatchesScreen`.

## Compute trigger

`PostListingScreen._submit()` and `PostRequirementScreen._submit()` each gain one call after their existing create-then-upload-then-attach flow succeeds: `matchingRepository.computeAndStoreMatchesForListing(listing)` / `computeAndStoreMatchesForRequirement(requirement)`. This is the **only** trigger point — no recompute on status change (see Data model), and no edit flow exists to recompute from. If the compute call fails, it must not block navigation away from the form (the listing/requirement itself was already created successfully) — caught and swallowed silently, matching-on-create is a best-effort enhancement, not a requirement for the create flow to succeed.

## Manual setup

`supabase/migrations/0006_matching.sql` — single file, same re-runnable-from-the-start pattern as `0005_requirement.sql` (`drop policy if exists`, `on conflict do nothing`). No Storage bucket, no Auth-dashboard changes.

## Testing approach

`MatchingEngine.score` is fully unit-tested (pure Dart) — mandatory filter cases, all four scoring dimensions independently, the price curve's three zones, the threshold boundary. `MatchingRepository` untested directly (Supabase-calling code, same boundary as every other repository). Screens get widget tests following the established pattern. The two "hook into an existing shipped screen" edits (`PostListingScreen`/`PostRequirementScreen`) get their existing test suites re-run to confirm zero regression, same discipline as Requirement's `SignedPhoto` extraction task.

## Explicitly deferred / out of scope for this milestone

- Push notification delivery on new match (needs Firebase Cloud Messaging, not wired anywhere in this app yet).
- `cobroke_request` — proposal's ERD already links `match_id` 1:0..1 to a future `cobroke_request` table; that's the Collaboration milestone, not this one.
- Recompute/re-threshold tuning UI (the `qualifyingThreshold` constant is not exposed anywhere).
- Fuzzy/partial location matching (`area` is exact-match-or-nothing).
- Any change to `PostListingScreen`/`PostRequirementScreen` beyond the single added compute call — no other refactor of those already-reviewed files.
