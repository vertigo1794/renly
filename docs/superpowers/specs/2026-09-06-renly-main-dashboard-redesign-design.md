# renly — Main Dashboard Redesign Design

## Goal

Restyle `MainDashboardScreen` (never touched by any prior Urby Restyle pass — still a bare `Scaffold`+`AppBar`+plain buttons) from Stitch's "Renly - Main Dashboard (Redesigned Premium)" mockup (project `13581751397915601898`, screen `f559238d7634480786ba33920bcb2a43`), wiring every new element to this app's own already-existing matching/listing/collaboration backend — no new feature, only a new dashboard surface for data that already exists.

## Source of truth

Stitch mockup: brand header (wordmark + lime dot, REN-number verification pill w/ green pulse dot, notification bell w/ badge dot), a black "Market Pulse" strip ("LIVE" tag + "N New Matches in {area}" + chevron), a Quick Actions grid (Post Listing / Market / My Inventory, each with a count badge/subtext), a "Co-Broking Radar" section (a primary property card with match-score badge, split badge, agent footer, "Co-Broke" CTA, plus 1-2 compact secondary rows), and a restyled "Recent Listings" feed (thumbnail, status tag, relative timestamp). Bottom nav bar is the app's existing already-built shell — out of scope here.

**Visual language**: rendered through this app's existing Urby/neo-brutalist system (`BrutalistButton`/`BrutalistCard`/`AppColors`/`PhosphorIcons`/`RStarBadge`), not Stitch's own Tailwind/lime-glow look — this project's standing convention, not re-litigated here.

## Decisions made during brainstorming

- **Co-Broking Radar scope**: filtered to matches on the negotiator's OWN listings only (`candidate.listing.negotiatorId == me`), matching the mockup's own subtitle "Buyer agents seeking inventory" — i.e., other agents' buyer requirements matched against listings this negotiator posted. Matches where the negotiator is the requirement side (they're the buyer) are excluded from this section (they already have `MyMatchesScreen` for the unfiltered view).
- **Split badge**: shown as a static "Standard Split · 50/50" badge, not real per-match data — `Agreement.splitInitiator`/`splitCounterparty` only exist after a `CobrokeRequest` is accepted, which hasn't happened yet at the match/radar stage. The badge is industry-convention copy, not a claim about an actual agreed split.
- **Market Pulse strip**: built for real. A new `MatchingRepository.fetchTopMatchAreaLast24h(negotiatorId)` query (matches on the negotiator's own listings, `match.created_at` within the last 24 hours, grouped by `listing.area`, top area by count) backs the "N New Matches in {area}" copy. If there are zero qualifying matches, the entire strip is hidden (no fabricated "0 new matches" copy).
- **Notification bell badge**: stays red (existing semantic "unread" color), not switched to the mockup's lime — red is the clearer alert signal and lime is reserved for brand/CTA accents elsewhere in this app.
- **Agency name on Radar card**: built for real. `get_negotiator_public_info` RPC is extended to also return `agency_name` (joined from `agency.firm_name`), via a new migration `0019_negotiator_public_info_agency_name.sql`. `ListingOwner` gains a nullable `agencyName` field.
- **"Exclusive" badge** (mockup's black pill on the radar card): dropped — no backing data (`Listing` has no "exclusive" flag), and this project's convention is to never fabricate a badge with no real data behind it.
- **Recent Listings status tags**: use the listing's own real `status` field (via the existing `StatusBadge` widget already used elsewhere), not the mockup's "Open Co-Broke"/"Buyer Matched" semantic labels — those would require a per-listing match/request lookup (N+1 queries) this redesign doesn't otherwise need. Scope kept to what's already fetched.

## Gaps requiring new code (beyond pure restyle)

- **`Listing.createdAt`**: the model doesn't currently expose this field (even though the underlying query already orders by it) — needed for Recent Listings' relative timestamp ("18m ago"). Add `final DateTime createdAt;`, parsed from `json['created_at']`, non-breaking addition.
- **`ListingOwner.agencyName`**: new nullable field, parsed from the RPC's new `agency_name` column.
- **`MatchingRepository.fetchTopMatchAreaLast24h`**: new query (see below).
- **A pure relative-time formatter**: no existing helper in this codebase formats "Xm/Xh ago" — new `DashboardFormatting.formatRelativeTime(DateTime createdAt, DateTime now)` (pure, unit-testable, same style as `ListingFormatting`/`RequirementFormatting`).
- **Migration `0019_negotiator_public_info_agency_name.sql`**: extends the RPC's return type to include `agency_name`. Applied manually by the user via the Supabase SQL Editor, per this project's established convention — Claude never applies migrations directly.

## Screen layout (Urby adaptation)

- **Header**: a custom `Row` (not a standard `AppBar` — the mockup's left-aligned wordmark + right-aligned pill/bell doesn't fit a centered-title `AppBar`): `RStarBadge(28)` + `app_name` wordmark + lime dot (consistent sizing/style with every other screen's header badge), then a `Spacer`, then the REN verification pill (`BrutalistCard`-style small pill, green pulse dot + `'REN {profile.renNumber}'`, hidden while `myProfileProvider` is loading/errored — no placeholder REN number), then the existing notification bell `IconButton` + red unread dot (unchanged logic, just repositioned into this new header row).
- **Market Pulse strip**: a `BrutalistCard` with `AppColors.ink` background, white text, "LIVE" tag (lime background, black text), `'{count} New Matches in {area}'`, and a chevron — tapping it pushes `/my-matches`. Wrapped in a `.when()` — `loading`/`error`/`null` (zero qualifying matches) all render `SizedBox.shrink()`.
- **Quick Actions grid**: same 3 actions (Post Listing / Market / My Inventory), restyled as `BrutalistCard`-bordered tappable tiles with icons:
  - Post Listing: unchanged action (`context.push('/post-listing')`), "Instant" static tag (this one's genuinely instant — posting doesn't depend on any count).
  - Market: `context.go('/marketplace')`, badge `'{marketplaceListingsProvider.length} Active'` (falls back to no badge while loading/erroring).
  - My Inventory: `context.push('/my-inventory')`, badge `'{myListingsProvider(negotiatorId).length} Listings'` + subtext `'{pendingCount} Co-broke requests waiting'` where `pendingCount` is `receivedRequestsProvider`'s results filtered to `status == 'pending'` — both hidden (not zeroed) while loading/erroring.
- **Co-Broking Radar**: `.when()` over `myMatchesProvider`, client-side filtered to `candidate.listing.negotiatorId == currentNegotiatorId`, already sorted by score descending (repository's own `.order('score', ascending: false)`). Section renders nothing if the filtered list is empty. Otherwise:
  - Section header: "Co-Broking Radar" + "Buyer agents seeking inventory" subtitle + `'View All ({filtered.length})'` → `context.push('/my-matches')` (existing route/screen, already built — no new screen needed).
  - Primary card (first/highest-score match): `BrutalistCard`, `ListingPhoto` (existing widget, handles the signed-URL resolution already used by `PropertyCard`) from `listing.photoUrls.first` if present, `'{score}% MATCH'` badge, "Standard Split · 50/50" badge, `ListingFormatting.formatPrice`, bed/sqft/area line, requirement owner footer (`requirementOwner.fullName`, `requirementOwner.renNumber`, `requirementOwner.agencyName` if non-null), "Co-Broke" `BrutalistButton` → existing `sendCobrokeRequest(context, ref, candidate.matchId)` action (already shared across the 3 existing match screens — reused verbatim, not reimplemented).
  - Up to 2 secondary compact rows (next-highest-score matches, if present): smaller `BrutalistCard` row, area + price + score, same `sendCobrokeRequest` action behind a compact icon button.
- **Recent Listings**: unchanged data source (`marketplaceListingsProvider`), restyled `PropertyCard`-based feed items gain: real `StatusBadge(listing.status)` (existing widget) and the new relative-timestamp formatter reading `listing.createdAt`.

## Data flow / providers

- `matchingRepositoryProvider.fetchTopMatchAreaLast24h(negotiatorId)` — new repository method, new `marketPulseProvider = FutureProvider.family<({String area, int count})?, String>` in `matching_providers.dart`.
- No new provider needed for the Radar section — reuses `myMatchesProvider`, filtered inline in the widget (a `FutureProvider` returning already-fetched data; filtering client-side avoids adding a second near-duplicate query for what is the same underlying `match` rows).
- Quick Actions badges reuse `marketplaceListingsProvider`, `myListingsProvider(negotiatorId)` (`family` already exists), `receivedRequestsProvider` (already exists) — no new providers.
- Header's REN pill reuses `myProfileProvider` (already exists).

## New repository method (exact query)

```dart
// MatchingRepository
Future<({String area, int count})?> fetchTopMatchAreaLast24h(String negotiatorId) async {
  final since = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
  final rows = await _client
      .from('match')
      .select('listing!inner(area, negotiator_id)')
      .eq('listing.negotiator_id', negotiatorId)
      .gte('created_at', since);
  final counts = <String, int>{};
  for (final row in rows as List) {
    final area = (row as Map<String, dynamic>)['listing']['area'] as String;
    counts[area] = (counts[area] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return (area: top.key, count: top.value);
}
```

## Migration (0019)

```sql
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
```

## Error handling

Every section is independently `.when()`-gated on its own provider: `loading`/`error` both render an empty/hidden state for that section only (no error banners stacking up on a dashboard with 5 independent async sections). A section with no qualifying data (Market Pulse's null, Radar's empty filtered list, badges' loading/error state) hides itself or its badge rather than showing a zero/placeholder value.

## Testing approach

Following this project's established convention: Supabase-boundary calls are not unit-tested (manual verification instead); pure logic and widget rendering get real tests.

- Unit tests for the new `DashboardFormatting.formatRelativeTime` (minutes/hours/days boundaries).
- Widget tests for `MainDashboardScreen`: provider overrides for each section (`myProfileProvider`, `marketplaceListingsProvider`, `myListingsProvider`, `receivedRequestsProvider`, `myMatchesProvider`, the new `marketPulseProvider`) covering populated / empty / error states per section, confirming each section hides correctly when its data is absent.
- `fetchTopMatchAreaLast24h` and the RPC's new `agency_name` column: manually verified against the live Supabase project (per this project's standing Supabase-boundary convention).

## Explicitly deferred / out of scope

- Real-time push updates to the Market Pulse strip or Radar section (both are pull-on-load, matching every other provider in this app — no new realtime infrastructure).
- The mockup's "Exclusive" badge (no backing data).
- "Open Co-Broke"/"Buyer Matched" semantic status tags on Recent Listings (uses real `status` instead, avoiding N+1 queries).
- Redesigning the bottom navigation bar (already built, out of scope).
- Any change to `MyMatchesScreen`, `MatchesForListingScreen`, `MatchesForRequirementScreen`, or the `sendCobrokeRequest` action's own behavior — all reused as-is.
