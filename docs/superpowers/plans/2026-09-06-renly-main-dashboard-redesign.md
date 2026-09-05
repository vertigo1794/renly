# Main Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle `MainDashboardScreen` from the Stitch "Renly - Main Dashboard (Redesigned Premium)" mockup, wiring every new section (Market Pulse strip, Co-Broking Radar, real Quick Actions badges) to this app's already-existing matching/listing/collaboration backend.

**Architecture:** No new backend feature — one new repository method (`fetchTopMatchAreaLast24h`), one small RPC extension (agency name), two small model field additions, one new pure formatter, and a full restyle of one screen (`MainDashboardScreen`) reusing existing widgets (`PropertyCard`, `ListingPhoto`, `StatusBadge`, `BrutalistCard`, `BrutalistButton`, `RStarBadge`) and existing actions (`sendCobrokeRequest`).

**Tech Stack:** Flutter, Riverpod (`FutureProvider`/`FutureProvider.family`), Supabase (PostgREST + one SECURITY DEFINER RPC), `easy_localization`, `phosphor_flutter`.

## Global Constraints

- Co-Broking Radar is filtered to `candidate.listing.negotiatorId == currentNegotiatorId` only (matches on the negotiator's OWN listings) — never render the unfiltered `myMatchesProvider` result directly.
- The split badge is always the static copy `'dashboard_radar_standard_split'.tr()` ("Standard Split · 50/50") — never computed from `Agreement` data (no such data exists pre-agreement, at match stage).
- Market Pulse strip, Co-Broking Radar section, and every Quick Actions badge/subtext must render nothing (not a placeholder "0" or fabricated value) on loading, error, or zero-qualifying-data states.
- The notification bell's unread badge stays **red** (`Colors.red`, unchanged) — do NOT switch to lime.
- No "Exclusive" badge anywhere (no backing data for it — not built).
- No "sqft" figure anywhere (no such field exists on `Listing` — not built).
- Recent Listings keeps `PropertyCard`'s own existing real `status`-gated `StatusBadge` (already conditional on `listing.status == 'active'`) — never the mockup's "Open Co-Broke"/"Buyer Matched" semantic copy.
- All new icons use `PhosphorIcons.x(PhosphorIconsStyle.bold)`, never `Icons.*`.
- `flutter analyze` and the full `flutter test` suite must stay clean after every task.
- No golden-image tests.
- EN/MS l10n key parity maintained in every task that adds copy (`app/assets/translations/en.json` and `ms.json`).
- Migration `0019_negotiator_public_info_agency_name.sql` is created as a **file only** — no task applies it. The user applies it manually via the Supabase SQL Editor, same as every prior migration in this project.

---

## Task 1: `Listing.createdAt` + `ListingOwner.agencyName` model fields

**Files:**
- Modify: `app/lib/features/listing/models/listing.dart`
- Modify: `app/lib/features/listing/models/listing_owner.dart`
- Modify (remove `const`, add `createdAt:` argument to every `Listing(...)` fixture): `app/test/core/widgets/property_card_test.dart`, `app/test/features/matching/matching_engine_test.dart` (2 call sites), `app/test/features/matching/matches_for_listing_screen_test.dart`, `app/test/features/matching/matches_for_requirement_screen_test.dart`, `app/test/features/matching/my_matches_screen_test.dart` (2 call sites), `app/test/features/collaboration/conversation_list_screen_test.dart`, `app/test/features/collaboration/my_requests_screen_test.dart`, `app/test/features/listing/my_inventory_screen_test.dart` (2 call sites), `app/test/features/listing/marketplace_screen_test.dart` (2 call sites), `app/test/features/listing/listing_status_filter_test.dart`, `app/test/features/listing/property_detail_screen_test.dart` (2 call sites), `app/test/features/home/main_dashboard_screen_test.dart`

**Interfaces:**
- Produces: `Listing.createdAt` (`DateTime`, required, non-const-constructible field), `ListingOwner.agencyName` (`String?`, nullable). Task 5/6/7 read `listing.createdAt` and `owner.agencyName`.

**Why `Listing` loses its `const` constructor:** Dart's `DateTime` class has no `const` constructor at all — adding a `DateTime` field to a class makes every existing `const Listing(...)` call site a compile error. This task removes `const` from the class's own constructor declaration and from every call site listed above (11 test files, ~16 constructions total) — this is the correct, standard fix (not a workaround), and every call site gets a fixed `createdAt: DateTime(2024, 1, 1)` test fixture value (an arbitrary but valid date — test fixtures are allowed a fixed value; this is not "faking production data").

- [ ] **Step 1: Read the current `Listing` model**

Confirm current content matches (already verified this session):
```dart
class Listing {
  final String listingId;
  final String negotiatorId;
  final String title;
  final String description;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final double price;
  final int? bedrooms;
  final int? bathrooms;
  final List<String> photoUrls;
  final String status;

  const Listing({
    required this.listingId,
    required this.negotiatorId,
    required this.title,
    required this.description,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    required this.price,
    this.bedrooms,
    this.bathrooms,
    required this.photoUrls,
    required this.status,
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      listingId: json['listing_id'] as String,
      negotiatorId: json['negotiator_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      price: (json['price'] as num).toDouble(),
      bedrooms: json['bedrooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
    );
  }
}
```

- [ ] **Step 2: Add `createdAt`, remove `const`**

Replace the whole file `app/lib/features/listing/models/listing.dart` with:

```dart
/// A row from the `listing` table.
class Listing {
  final String listingId;
  final String negotiatorId;
  final String title;
  final String description;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final double price;
  final int? bedrooms;
  final int? bathrooms;
  final List<String> photoUrls;
  final String status;
  final DateTime createdAt;

  Listing({
    required this.listingId,
    required this.negotiatorId,
    required this.title,
    required this.description,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    required this.price,
    this.bedrooms,
    this.bathrooms,
    required this.photoUrls,
    required this.status,
    required this.createdAt,
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      listingId: json['listing_id'] as String,
      negotiatorId: json['negotiator_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      price: (json['price'] as num).toDouble(),
      bedrooms: json['bedrooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 3: Add `agencyName` to `ListingOwner`**

Replace the whole file `app/lib/features/listing/models/listing_owner.dart` with:

```dart
/// The listing's negotiator, scoped to what PropertyDetailScreen displays
/// (name + REN number) -- deliberately not the full `Negotiator` model from
/// the auth feature, to keep this feature's Supabase reads self-contained
/// rather than reaching into another feature's model. `agencyName` added
/// for the Main Dashboard's Co-Broking Radar card (shows the matched
/// agent's agency as a trust signal) -- nullable because the RPC's LEFT
/// JOIN on `agency` returns null for a negotiator with no `agency_id` set.
class ListingOwner {
  final String fullName;
  final String renNumber;
  final String? agencyName;

  const ListingOwner({required this.fullName, required this.renNumber, this.agencyName});

  factory ListingOwner.fromJson(Map<String, dynamic> json) {
    return ListingOwner(
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String? ?? '',
      agencyName: json['agency_name'] as String?,
    );
  }
}
```

(`ListingOwner` keeps its `const` constructor — `agencyName` is a `String?`, which IS const-constructible, unlike `DateTime`.)

- [ ] **Step 4: Fix every existing `Listing(...)` test fixture**

For each file below, remove the `const` keyword immediately before `Listing(` (and before the variable assignment, e.g. `const _listing = Listing(` becomes `final _listing = Listing(`), and add a `createdAt: DateTime(2024, 1, 1),` line inside the constructor call (anywhere among the named arguments — after `status:` is consistent with this task's own model field order).

`app/test/core/widgets/property_card_test.dart` — change:
```dart
const _listing = Listing(
```
to:
```dart
final _listing = Listing(
```
and add `createdAt: DateTime(2024, 1, 1),` after the `status: 'active',` line. Add `import 'dart:core';` is not needed (`DateTime` is already in `dart:core`, always available).

`app/test/features/matching/matching_engine_test.dart` — two call sites (`const _listing = Listing(` at the top, and `const listing = Listing(` inside a test body around line 93) — apply the same fix to both (`const` → `final`/none, add `createdAt: DateTime(2024, 1, 1),`).

`app/test/features/matching/matches_for_listing_screen_test.dart` — `const _fixtureListing = Listing(` → `final _fixtureListing = Listing(`, add the `createdAt:` line.

`app/test/features/matching/matches_for_requirement_screen_test.dart` — same fix, `_fixtureListing`.

`app/test/features/matching/my_matches_screen_test.dart` — two call sites (`_myListing`, `_theirListing`) — same fix on both.

`app/test/features/collaboration/conversation_list_screen_test.dart` — `_listing` — same fix.

`app/test/features/collaboration/my_requests_screen_test.dart` — `_myListing` — same fix.

`app/test/features/listing/my_inventory_screen_test.dart` — two `const Listing(` call sites inside a list literal (`'Active One'`, `'Sold One'`) — remove `const` from each individual `Listing(` (the surrounding list literal itself can keep being a plain non-const `[...]` if it already isn't `const [...]` — check the enclosing brackets; if the list itself is declared `const [`, change that to a plain `[` too, since a non-const element can't live inside a const list), add `createdAt: DateTime(2024, 1, 1),` to each.

`app/test/features/listing/marketplace_screen_test.dart` — two `const Listing(` call sites (`'The Vertex Residency'`, `'City Loft'`) — same fix as above (check and fix the enclosing list literal's `const` too if present).

`app/test/features/listing/listing_status_filter_test.dart` — the helper function `Listing _makeListing(...)` already returns `Listing(...)` without `const` (it's a function body, not a const context) — just add a `createdAt: DateTime(2024, 1, 1),` line inside its constructor call, no `const` removal needed here.

`app/test/features/listing/property_detail_screen_test.dart` — two call sites (`_fixtureListing`, `_withdrawnListingOwnedByN1`) — same fix as above.

`app/test/features/home/main_dashboard_screen_test.dart` — `const _listing = Listing(` → `final _listing = Listing(`, add the `createdAt:` line.

- [ ] **Step 5: Run `flutter analyze` and fix any remaining const-context errors**

```bash
cd "app" && flutter analyze
```

Expected: no errors from `Listing`/`ListingOwner` changes. If the analyzer reports a remaining `const` error (e.g. a `const [ _listing ]` list literal somewhere not listed above, or a `const SomeWidget(listing: _listing)` call), remove that `const` keyword too — this is a mechanical const-propagation fix, not a design change.

- [ ] **Step 6: Run the full test suite**

```bash
cd "app" && flutter test
```

Expected: all tests pass (no behavior changed, only fixture values added).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/listing/models/listing.dart app/lib/features/listing/models/listing_owner.dart app/test/core/widgets/property_card_test.dart app/test/features/matching/matching_engine_test.dart app/test/features/matching/matches_for_listing_screen_test.dart app/test/features/matching/matches_for_requirement_screen_test.dart app/test/features/matching/my_matches_screen_test.dart app/test/features/collaboration/conversation_list_screen_test.dart app/test/features/collaboration/my_requests_screen_test.dart app/test/features/listing/my_inventory_screen_test.dart app/test/features/listing/marketplace_screen_test.dart app/test/features/listing/listing_status_filter_test.dart app/test/features/listing/property_detail_screen_test.dart app/test/features/home/main_dashboard_screen_test.dart
git commit -m "feat: add Listing.createdAt and ListingOwner.agencyName fields"
```

---

## Task 2: Migration for `agency_name` on `get_negotiator_public_info`

**Files:**
- Create: `supabase/migrations/0019_negotiator_public_info_agency_name.sql`

**Interfaces:**
- Produces: the RPC `get_negotiator_public_info(uuid)` now returns `(full_name text, ren_number text, agency_name text)` instead of `(full_name text, ren_number text)`. Task 1's `ListingOwner.fromJson` (already merged) reads the new `agency_name` key.

- [ ] **Step 1: Create the migration file**

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

- [ ] **Step 2: Tell the user to apply it**

Print this exact message to the user (do not apply the migration yourself):

> Migration `0019_negotiator_public_info_agency_name.sql` created. Please apply it manually via the Supabase Dashboard's SQL Editor (same process as every prior migration), then let me know once it's done so I can continue.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0019_negotiator_public_info_agency_name.sql
git commit -m "feat: add agency_name to get_negotiator_public_info RPC"
```

---

## Task 3: `MatchingRepository.fetchTopMatchAreaLast24h` + `marketPulseProvider`

**Files:**
- Modify: `app/lib/features/matching/matching_repository.dart`
- Modify: `app/lib/features/matching/matching_providers.dart`

**Interfaces:**
- Consumes: nothing new (uses the existing `SupabaseClient _client` already held by `MatchingRepository`).
- Produces: `Future<({String area, int count})?> fetchTopMatchAreaLast24h(String negotiatorId)` on `MatchingRepository`; `final marketPulseProvider = FutureProvider.family<({String area, int count})?, String>(...)` in `matching_providers.dart`. Task 6 watches `marketPulseProvider(negotiatorId)`.

- [ ] **Step 1: Add the repository method**

In `app/lib/features/matching/matching_repository.dart`, add this method inside the `MatchingRepository` class (after `fetchMyMatches`, before `_toCandidates`):

```dart
  /// Top area by match count in the last 24h, among matches on the
  /// negotiator's OWN listings only (Co-Broking Radar's own filter,
  /// mirrored here for the Market Pulse strip's "N New Matches in {area}"
  /// copy). Returns null when there are zero qualifying matches -- the
  /// caller hides the whole strip rather than showing a fabricated "0".
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

- [ ] **Step 2: Add the provider**

In `app/lib/features/matching/matching_providers.dart`, add after `myMatchesProvider`:

```dart
final marketPulseProvider = FutureProvider.family<({String area, int count})?, String>((ref, negotiatorId) {
  return ref.watch(matchingRepositoryProvider).fetchTopMatchAreaLast24h(negotiatorId);
});
```

- [ ] **Step 3: Run `flutter analyze`**

```bash
cd "app" && flutter analyze
```

Expected: clean (this is Supabase-boundary code, not unit-tested per this project's convention — manually verified in Task 6's live check).

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/matching/matching_repository.dart app/lib/features/matching/matching_providers.dart
git commit -m "feat: add fetchTopMatchAreaLast24h for the dashboard Market Pulse strip"
```

---

## Task 4: `DashboardFormatting.formatRelativeTime`

**Files:**
- Create: `app/lib/features/home/dashboard_formatting.dart`
- Create: `app/test/features/home/dashboard_formatting_test.dart`

**Interfaces:**
- Produces: `DashboardFormatting.formatRelativeTime(DateTime createdAt, DateTime now) -> String`. Task 7 calls this with `listing.createdAt` and `DateTime.now()`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/features/home/dashboard_formatting_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/home/dashboard_formatting.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12, 0, 0);

  test('formats under a minute as "just now"', () {
    final createdAt = now.subtract(const Duration(seconds: 30));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), 'just now');
  });

  test('formats minutes ago', () {
    final createdAt = now.subtract(const Duration(minutes: 18));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '18m ago');
  });

  test('formats hours ago', () {
    final createdAt = now.subtract(const Duration(hours: 2));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '2h ago');
  });

  test('formats days ago', () {
    final createdAt = now.subtract(const Duration(days: 3));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '3d ago');
  });

  test('boundary: exactly 60 minutes rolls over to hours', () {
    final createdAt = now.subtract(const Duration(minutes: 60));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '1h ago');
  });

  test('boundary: exactly 24 hours rolls over to days', () {
    final createdAt = now.subtract(const Duration(hours: 24));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '1d ago');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "app" && flutter test test/features/home/dashboard_formatting_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:renly/features/home/dashboard_formatting.dart'`.

- [ ] **Step 3: Write the implementation**

Create `app/lib/features/home/dashboard_formatting.dart`:

```dart
/// Pure relative-time-display formatting for the dashboard's Recent
/// Listings feed. No Flutter/Supabase -- fully unit-testable, same style
/// as ListingFormatting/RequirementFormatting.
class DashboardFormatting {
  DashboardFormatting._();

  static String formatRelativeTime(DateTime createdAt, DateTime now) {
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd "app" && flutter test test/features/home/dashboard_formatting_test.dart
```

Expected: PASS, 6/6.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/home/dashboard_formatting.dart app/test/features/home/dashboard_formatting_test.dart
git commit -m "feat: add DashboardFormatting.formatRelativeTime"
```

---

## Task 5: Dashboard header restyle + real Quick Actions badges

**Files:**
- Modify: `app/lib/features/home/main_dashboard_screen.dart`
- Modify: `app/test/features/home/main_dashboard_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `myProfileProvider` (existing, `Profile.renNumber`), `marketplaceListingsProvider` (existing), `myListingsProvider(negotiatorId)` (existing `family`), `receivedRequestsProvider` (existing, `CobrokeRequestCandidate.request.status`), `unreadNotificationCountProvider` (existing), `currentNegotiatorIdProvider` (existing, from `matching_providers.dart` or `listing_providers.dart` — same value, either import works; use the one already imported by this file's neighbors — `listing_providers.dart`'s copy, since this screen already imports that file).
- Produces: nothing new for later tasks — this task only changes `MainDashboardScreen`'s header + Quick Actions section. Task 6 and Task 7 further modify the same file's body (different sections), so read the current file state before editing in those tasks.

- [ ] **Step 1: Add new l10n keys**

In `app/assets/translations/en.json`, add after `"dashboard_quick_action_my_inventory": "My Inventory",` (keep existing `dashboard_recent_listings_*` keys where they are, just insert these before them):

```json
  "dashboard_quick_action_market_active": "{} Active",
  "dashboard_quick_action_my_inventory_count": "{} Listings",
  "dashboard_quick_action_pending_requests": "{} Co-broke requests waiting",
```

In `app/assets/translations/ms.json`, add the mirrored keys at the same relative position (check the existing `dashboard_*` keys' neighboring translations for style first):

```json
  "dashboard_quick_action_market_active": "{} Aktif",
  "dashboard_quick_action_my_inventory_count": "{} Penyenaraian",
  "dashboard_quick_action_pending_requests": "{} permintaan co-broke menunggu",
```

(`easy_localization`'s `{}` placeholder syntax — confirm the exact placeholder style already used elsewhere in this project's `.tr(args: [...])` calls by checking one existing interpolated key, e.g. `dashboard_welcome_back`'s usage in `main_dashboard_screen.dart` — that key is NOT interpolated (`'${'dashboard_welcome_back'.tr()} ${profile.fullName}.'` concatenates outside `.tr()`), so grep for `.tr(args:` across `app/lib/` to confirm the project's actual interpolation convention before using it here; if no prior `args:` usage exists, use the same plain-concatenation style as `dashboard_welcome_back` instead: keep the JSON values as plain labels without `{}` and build the full string in Dart via string interpolation, e.g. `'${count} ${'dashboard_quick_action_market_active'.tr()}'`. Use whichever convention the grep confirms as this project's real established pattern — do not guess.)

- [ ] **Step 2: Read the current full file before editing**

```bash
cat "app/lib/features/home/main_dashboard_screen.dart"
```

(Already read this session — reproduced in this plan's context above. Re-read now to confirm no other task has changed it first, per this project's own multi-task-same-file convention.)

- [ ] **Step 3: Replace the header + Quick Actions section**

Replace the whole file `app/lib/features/home/main_dashboard_screen.dart` with (this step's version omits the Market Pulse strip and Co-Broking Radar sections, which Task 6 adds — the `// TASK 6` and `// TASK 7` comments mark exactly where those tasks insert their sections, so this task's diff is reviewable on its own):

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
import '../../core/widgets/property_card.dart';
import '../../core/widgets/r_star_badge.dart';
import '../listing/listing_providers.dart';
import '../collaboration/cobroke_request_providers.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart';

/// The Home branch's root screen in the bottom-nav shell. Restyled from
/// the Stitch "Renly - Main Dashboard (Redesigned Premium)" mockup
/// (docs/superpowers/specs/2026-09-06-renly-main-dashboard-redesign-design.md):
/// a custom brand header (not a standard AppBar -- the mockup's
/// left-aligned wordmark + right-aligned REN pill/bell doesn't fit a
/// centered-title AppBar), real count badges on the Quick Actions grid,
/// a Market Pulse strip and Co-Broking Radar section (both added by a
/// later task in the same plan), and a restyled Recent Listings feed.
class MainDashboardScreen extends ConsumerWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final myListingsAsync = negotiatorId == null
        ? const AsyncValue<List<dynamic>>.data([])
        : ref.watch(myListingsProvider(negotiatorId));
    final receivedRequestsAsync = ref.watch(receivedRequestsProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand header row: wordmark + REN verification pill + bell.
              Row(
                children: [
                  const RStarBadge(size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'app_name'.tr(),
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: AppColors.ink,
                          fontSize: 20,
                          letterSpacing: -1.0,
                          height: 1,
                        ),
                  ),
                  const Spacer(),
                  profileAsync.maybeWhen(
                    data: (profile) => profile.renNumber == null
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'REN ${profile.renNumber}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  Stack(
                    children: [
                      IconButton(
                        icon: Icon(PhosphorIcons.bellSimple(PhosphorIconsStyle.bold)),
                        onPressed: () => context.push('/notifications'),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              profileAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stack) => const SizedBox.shrink(),
                data: (profile) => Text(
                  '${'dashboard_welcome_back'.tr()} ${profile.fullName}.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text('dashboard_subtitle'.tr()),
              // TASK 6: Market Pulse strip inserted here.
              const SizedBox(height: 24),
              Text('dashboard_quick_actions_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: BrutalistButton(
                      label: 'dashboard_quick_action_post_listing'.tr(),
                      icon: PhosphorIcons.plusCircle(PhosphorIconsStyle.bold),
                      onPressed: () => context.push('/post-listing'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BrutalistButton(
                      label: listingsAsync.maybeWhen(
                        data: (listings) =>
                            '${'dashboard_quick_action_market'.tr()} · ${listings.length} ${'dashboard_quick_action_market_active'.tr()}',
                        orElse: () => 'dashboard_quick_action_market'.tr(),
                      ),
                      variant: BrutalistButtonVariant.secondary,
                      icon: PhosphorIcons.storefront(PhosphorIconsStyle.bold),
                      onPressed: () => context.go('/marketplace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BrutalistButton(
                label: myListingsAsync.maybeWhen(
                  data: (listings) =>
                      '${'dashboard_quick_action_my_inventory'.tr()} · ${listings.length} ${'dashboard_quick_action_my_inventory_count'.tr()}',
                  orElse: () => 'dashboard_quick_action_my_inventory'.tr(),
                ),
                variant: BrutalistButtonVariant.secondary,
                icon: PhosphorIcons.listBullets(PhosphorIconsStyle.bold),
                onPressed: () => context.push('/my-inventory'),
              ),
              receivedRequestsAsync.maybeWhen(
                data: (requests) {
                  final pending = requests.where((c) => c.request.status == 'pending').length;
                  if (pending == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      '$pending ${'dashboard_quick_action_pending_requests'.tr()}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              // TASK 6: Co-Broking Radar section inserted here.
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('dashboard_recent_listings_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.go('/marketplace'),
                    child: Text('dashboard_view_all'.tr()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: listingsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                  data: (listings) {
                    if (listings.isEmpty) {
                      return Center(child: Text('dashboard_recent_listings_empty'.tr()));
                    }
                    final recent = listings.take(10).toList();
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final listing = recent[index];
                        return SizedBox(
                          width: 260,
                          child: PropertyCard(
                            listing: listing,
                            onTap: () => context.push('/property/${listing.listingId}'),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Note on `myListingsAsync`'s placeholder type**: the `AsyncValue<List<dynamic>>.data([])` fallback when `negotiatorId == null` is a temporary typing shim for this task's diff only — Task 6 (which also touches this file) tightens this once the Radar section's own negotiator-scoped logic is added alongside it in the same build method. If `flutter analyze` in Step 4 below reports a type mismatch between `AsyncValue<List<dynamic>>` and the `myListingsProvider`'s real `AsyncValue<List<Listing>>` in the `.maybeWhen` call, change the fallback to `const AsyncValue<List<Listing>>.data(<Listing>[])` and add `import '../listing/models/listing.dart';` — use whichever the analyzer actually requires.

- [ ] **Step 4: Run `flutter analyze` and fix any reported type errors**

```bash
cd "app" && flutter analyze
```

Expected: clean, or one `List<dynamic>`/`List<Listing>` mismatch as described above — fix per that note, then re-run until clean.

- [ ] **Step 5: Update the existing widget test for the new header + badges**

Replace `app/test/features/home/main_dashboard_screen_test.dart`'s test body to also override the new providers this task reads. Read the file's current full content first (already shown in this plan's context), then replace the whole file with:

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/home/main_dashboard_screen.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';
import 'package:renly/features/collaboration/cobroke_request_providers.dart';

final _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'Modern Villa',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Downtown',
  price: 2450000,
  bedrooms: 4,
  bathrooms: 3,
  photoUrls: [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (context, state) => const MainDashboardScreen()),
    GoRoute(path: '/post-listing', builder: (context, state) => const Text('post-listing-screen')),
  ]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ms')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp.router(
            theme: AppTheme.light,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('renders welcome header, quick actions, and a listing card', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              renNumber: '48210',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => [_listing]),
        myListingsProvider.overrideWith((ref, negotiatorId) async => [_listing]),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 2),
      ],
    );

    expect(find.textContaining('Aiman Yusof'), findsOneWidget);
    expect(find.textContaining('REN 48210'), findsOneWidget);
    expect(find.text('Modern Villa'), findsOneWidget);
    expect(find.textContaining('1 Listings'), findsOneWidget);

    await tester.tap(find.text('dashboard_quick_action_post_listing'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('post-listing-screen'), findsOneWidget);
  });

  testWidgets('hides REN pill when profile has no renNumber', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => []),
        myListingsProvider.overrideWith((ref, negotiatorId) async => []),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
      ],
    );

    expect(find.textContaining('REN'), findsNothing);
  });
}
```

(This overrides `myListingsProvider` — a `.family` provider — via `overrideWith((ref, negotiatorId) async => ...)`, the standard Riverpod family-override syntax; confirm this exact syntax compiles against this project's pinned `flutter_riverpod` version by running the test in the next step, and adjust only if the analyzer/test runner reports a syntax mismatch for this Riverpod version.)

- [ ] **Step 6: Run the test**

```bash
cd "app" && flutter test test/features/home/main_dashboard_screen_test.dart
```

Expected: PASS, 2/2.

- [ ] **Step 7: Run the full suite and analyzer**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/home/main_dashboard_screen.dart app/test/features/home/main_dashboard_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: restyle dashboard header with REN pill and real Quick Actions badges"
```

---

## Task 6: Market Pulse strip + Co-Broking Radar section

**Files:**
- Modify: `app/lib/features/home/main_dashboard_screen.dart`
- Modify: `app/test/features/home/main_dashboard_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `marketPulseProvider(negotiatorId)` (Task 3), `myMatchesProvider` (existing), `MatchCandidate` (existing, `matchId`/`score`/`listing`/`requirement`/`listingOwner`/`requirementOwner`), `sendCobrokeRequest(context, ref, matchId)` (existing action, `app/lib/features/collaboration/send_cobroke_request_action.dart`), `ListingPhoto` (existing widget, `app/lib/features/listing/listing_photo.dart`), `ListingFormatting.formatPrice` (existing, `app/lib/features/listing/listing_formatting.dart`).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Add new l10n keys**

In `app/assets/translations/en.json`, add (near the other `dashboard_*`/`cobroke_*` keys):

```json
  "dashboard_market_pulse_live": "LIVE",
  "dashboard_market_pulse_new_matches": "New Matches in",
  "dashboard_radar_title": "Co-Broking Radar",
  "dashboard_radar_subtitle": "Buyer agents seeking inventory",
  "dashboard_radar_view_all": "View All",
  "dashboard_radar_match_percent": "MATCH",
  "dashboard_radar_standard_split": "Standard Split · 50/50",
```

In `app/assets/translations/ms.json`, add the mirrored keys:

```json
  "dashboard_market_pulse_live": "LANGSUNG",
  "dashboard_market_pulse_new_matches": "Padanan Baru di",
  "dashboard_radar_title": "Radar Co-Broking",
  "dashboard_radar_subtitle": "Ejen pembeli mencari inventori",
  "dashboard_radar_view_all": "Lihat Semua",
  "dashboard_radar_match_percent": "PADAN",
  "dashboard_radar_standard_split": "Split Standard · 50/50",
```

(`cobroke_request_send`.tr() — "Request Co-Broke" — is reused verbatim for the Radar card's CTA button; no new key needed for that button's label.)

- [ ] **Step 2: Read the current file (post-Task-5) before editing**

```bash
cat "app/lib/features/home/main_dashboard_screen.dart"
```

- [ ] **Step 3: Insert the Market Pulse strip and Co-Broking Radar section**

In `main_dashboard_screen.dart`:

Add these imports at the top (alongside the existing ones):
```dart
import '../collaboration/send_cobroke_request_action.dart';
import '../listing/listing_formatting.dart';
import '../listing/listing_photo.dart';
import '../matching/matching_providers.dart';
```

Inside `build`, add after the existing `receivedRequestsAsync` line:
```dart
    final myMatchesAsync = ref.watch(myMatchesProvider);
    final marketPulseAsync =
        negotiatorId == null ? const AsyncValue.data(null) : ref.watch(marketPulseProvider(negotiatorId));
```

Replace the `// TASK 6: Market Pulse strip inserted here.` comment line with:
```dart
              marketPulseAsync.maybeWhen(
                data: (pulse) {
                  if (pulse == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InkWell(
                      onTap: () => context.push('/my-matches'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'dashboard_market_pulse_live'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${pulse.count} ${'dashboard_market_pulse_new_matches'.tr()} ${pulse.area}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.bold), color: AppColors.primary, size: 16),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
```

Replace the `// TASK 6: Co-Broking Radar section inserted here.` comment line with:
```dart
              myMatchesAsync.maybeWhen(
                data: (matches) {
                  final myListingMatches = negotiatorId == null
                      ? const <dynamic>[]
                      : matches.where((c) => c.listing.negotiatorId == negotiatorId).toList();
                  if (myListingMatches.isEmpty) return const SizedBox.shrink();
                  final primary = myListingMatches.first;
                  final secondary = myListingMatches.skip(1).take(2).toList();
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('dashboard_radar_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                                Text('dashboard_radar_subtitle'.tr(), style: Theme.of(context).textTheme.labelSmall),
                              ],
                            ),
                            TextButton(
                              onPressed: () => context.push('/my-matches'),
                              child: Text('${'dashboard_radar_view_all'.tr()} (${myListingMatches.length})'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        BrutalistCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (primary.listing.photoUrls.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 64,
                                        height: 64,
                                        child: ListingPhoto(path: primary.listing.photoUrls.first),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                border: Border.all(color: AppColors.ink),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${primary.score}% ${'dashboard_radar_match_percent'.tr()}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          ListingFormatting.formatPrice(
                                            primary.listing.price,
                                            primary.listing.transactionType,
                                          ),
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        Text(
                                          primary.listing.area,
                                          style: Theme.of(context).textTheme.labelSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'dashboard_radar_standard_split'.tr(),
                                          style: Theme.of(context).textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          primary.requirementOwner.fullName,
                                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        Text(
                                          [
                                            if (primary.requirementOwner.agencyName != null)
                                              primary.requirementOwner.agencyName!,
                                            'REN ${primary.requirementOwner.renNumber}',
                                          ].join(' · '),
                                          style: Theme.of(context).textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  BrutalistButton(
                                    label: 'cobroke_request_send'.tr(),
                                    fullWidth: false,
                                    onPressed: () => sendCobrokeRequest(context, ref, primary.matchId),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        for (final candidate in secondary) ...[
                          const SizedBox(height: 8),
                          BrutalistCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        candidate.listing.area,
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      Text(
                                        ListingFormatting.formatPrice(
                                          candidate.listing.price,
                                          candidate.listing.transactionType,
                                        ),
                                        style: Theme.of(context).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.bold)),
                                  onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
```

- [ ] **Step 4: Run `flutter analyze` and fix any type errors**

```bash
cd "app" && flutter analyze
```

Expected: clean, or a `dynamic`-vs-`MatchCandidate` type error on `myListingMatches` if the analyzer can't infer it from `const <dynamic>[]` — if so, change that fallback to `const <MatchCandidate>[]` and add `import '../matching/models/match_candidate.dart';`.

- [ ] **Step 5: Extend the widget test for the Radar section**

Add `import 'package:renly/features/matching/matching_providers.dart';`, `import 'package:renly/features/matching/models/match_candidate.dart';`, `import 'package:renly/features/requirement/models/requirement.dart';`, and `import 'package:renly/features/listing/models/listing_owner.dart';` to the top of `main_dashboard_screen_test.dart`, add a fixture:

```dart
final _requirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Downtown',
  budgetMin: 2000000,
  budgetMax: 3000000,
  photoUrls: [],
  status: 'open',
);

final _matchCandidate = MatchCandidate(
  matchId: 'm-1',
  score: 92,
  listing: _listing,
  requirement: _requirement,
  listingOwner: const ListingOwner(fullName: 'Aiman Yusof', renNumber: '48210'),
  requirementOwner: const ListingOwner(fullName: 'Julian Danial', renNumber: '34812', agencyName: 'IQI Global'),
);
```

(Check `Requirement`'s actual constructor field names/requiredness by reading `app/lib/features/requirement/models/requirement.dart` before finalizing this fixture — this plan's earlier research read this file and confirmed the fields shown above; re-verify if the analyzer reports a mismatch.)

Add `myMatchesProvider.overrideWith((ref) async => [_matchCandidate])` and `marketPulseProvider.overrideWith((ref, negotiatorId) async => (area: 'Mont Kiara', count: 3))` to both existing test cases' `overrides:` lists, then add a new test:

```dart
  testWidgets('shows Co-Broking Radar for matches on my own listings only', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              renNumber: '48210',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => []),
        myListingsProvider.overrideWith((ref, negotiatorId) async => []),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
        myMatchesProvider.overrideWith((ref) async => [_matchCandidate]),
        marketPulseProvider.overrideWith((ref, negotiatorId) async => (area: 'Mont Kiara', count: 3)),
      ],
    );

    expect(find.text('dashboard_radar_title'.tr()), findsOneWidget);
    expect(find.textContaining('92%'), findsOneWidget);
    expect(find.textContaining('IQI Global'), findsOneWidget);
    expect(find.textContaining('Mont Kiara'), findsWidgets);
  });

  testWidgets('hides Co-Broking Radar and Market Pulse when there are no matches', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => []),
        myListingsProvider.overrideWith((ref, negotiatorId) async => []),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
        myMatchesProvider.overrideWith((ref) async => []),
        marketPulseProvider.overrideWith((ref, negotiatorId) async => null),
      ],
    );

    expect(find.text('dashboard_radar_title'.tr()), findsNothing);
    expect(find.text('dashboard_market_pulse_live'.tr()), findsNothing);
  });
```

- [ ] **Step 6: Run the tests**

```bash
cd "app" && flutter test test/features/home/main_dashboard_screen_test.dart
```

Expected: PASS, 4/4.

- [ ] **Step 7: Run the full suite and analyzer**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/home/main_dashboard_screen.dart app/test/features/home/main_dashboard_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add Market Pulse strip and Co-Broking Radar section to dashboard"
```

---

## Task 7: Recent Listings relative timestamp

**Files:**
- Modify: `app/lib/core/widgets/property_card.dart`
- Modify: `app/lib/features/home/main_dashboard_screen.dart`
- Modify: `app/test/core/widgets/property_card_test.dart`
- Modify: `app/test/features/home/main_dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `DashboardFormatting.formatRelativeTime` (Task 4), `Listing.createdAt` (Task 1).
- Produces: `PropertyCard` gains an optional `trailing` slot — `const PropertyCard({required listing, required onTap, this.trailing, super.key})` — nullable, defaults to `null`, so every OTHER existing caller of `PropertyCard` (marketplace_screen.dart, etc.) is unaffected.

- [ ] **Step 1: Add the optional `trailing` slot to `PropertyCard`**

In `app/lib/core/widgets/property_card.dart`, change the constructor and the `title` `Row` to accommodate an optional trailing widget. Replace:

```dart
class PropertyCard extends StatelessWidget {
  const PropertyCard({required this.listing, required this.onTap, super.key});

  final Listing listing;
  final VoidCallback onTap;
```

with:

```dart
class PropertyCard extends StatelessWidget {
  const PropertyCard({required this.listing, required this.onTap, this.trailing, super.key});

  final Listing listing;
  final VoidCallback onTap;

  /// Optional small trailing content shown under the title (e.g. a
  /// relative timestamp on the Dashboard's Recent Listings feed). Null by
  /// default -- every other existing caller of this widget is unaffected.
  final Widget? trailing;
```

Then, inside `build`, change the `Row(children: [Expanded(child: Text(listing.title...)), if (listing.status == 'active') StatusBadge(...)])` block to also render `trailing` beneath it — replace:

```dart
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (listing.status == 'active')
                          StatusBadge(label: 'listing_status_available'.tr()),
                      ],
                    ),
                    const SizedBox(height: 4),
```

with:

```dart
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (listing.status == 'active')
                          StatusBadge(label: 'listing_status_available'.tr()),
                      ],
                    ),
                    if (trailing != null) ...[
                      const SizedBox(height: 2),
                      trailing!,
                    ],
                    const SizedBox(height: 4),
```

- [ ] **Step 2: Pass a relative-timestamp `trailing` from the dashboard**

In `app/lib/features/home/main_dashboard_screen.dart`, add `import 'dashboard_formatting.dart';` at the top, then in the Recent Listings `ListView.separated`'s `itemBuilder`, change:

```dart
                        return SizedBox(
                          width: 260,
                          child: PropertyCard(
                            listing: listing,
                            onTap: () => context.push('/property/${listing.listingId}'),
                          ),
                        );
```

to:

```dart
                        return SizedBox(
                          width: 260,
                          child: PropertyCard(
                            listing: listing,
                            onTap: () => context.push('/property/${listing.listingId}'),
                            trailing: Text(
                              DashboardFormatting.formatRelativeTime(listing.createdAt, DateTime.now()),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
                            ),
                          ),
                        );
```

- [ ] **Step 3: Run `flutter analyze`**

```bash
cd "app" && flutter analyze
```

Expected: clean.

- [ ] **Step 4: Add a widget test for `PropertyCard`'s `trailing` slot**

In `app/test/core/widgets/property_card_test.dart`, read the current full file first, then add a new test case (alongside the existing one(s)) asserting that:
1. When `trailing` is omitted, no extra text renders beyond the card's existing content (regression guard — existing callers unaffected).
2. When `trailing: Text('18m ago')` is passed, `find.text('18m ago')` finds it.

```dart
  testWidgets('renders trailing widget when provided', (tester) async {
    await tester.pumpWidget(
      // Reuse this file's existing pump helper/MaterialApp+EasyLocalization
      // wrapper from the test(s) above it -- read the current file to copy
      // its exact wrapping widget tree here, this snippet only shows the
      // PropertyCard itself:
      Builder(
        builder: (context) => PropertyCard(
          listing: _listing,
          onTap: () {},
          trailing: const Text('18m ago'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('18m ago'), findsOneWidget);
  });
```

(This snippet is deliberately partial on the wrapping widget tree — copy the exact `MaterialApp`/`EasyLocalization`/`ProviderScope` scaffolding this file's existing test(s) already use around `PropertyCard`, since that scaffolding was already read once this session and must match exactly, not be re-invented here.)

- [ ] **Step 5: Run the tests**

```bash
cd "app" && flutter test test/core/widgets/property_card_test.dart test/features/home/main_dashboard_screen_test.dart
```

Expected: all PASS.

- [ ] **Step 6: Run the full suite and analyzer**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add app/lib/core/widgets/property_card.dart app/lib/features/home/main_dashboard_screen.dart app/test/core/widgets/property_card_test.dart app/test/features/home/main_dashboard_screen_test.dart
git commit -m "feat: show relative timestamp on dashboard Recent Listings cards"
```

---

## Manual verification (after all tasks, and after migration 0019 is applied)

1. Confirm migration `0019` was applied (ask the user, or run `supabase db query --linked` to check the RPC's new return signature independently).
2. Live-run the app: confirm the header shows wordmark + REN pill (when the signed-in negotiator has a `ren_number`) + bell.
3. Confirm Quick Actions badges show real counts (Market's active count, My Inventory's listing count, pending co-broke subtext) and hide gracefully while loading.
4. Confirm the Market Pulse strip appears only when there's a real match on one of the negotiator's own listings within the last 24h, and links to `/my-matches`.
5. Confirm the Co-Broking Radar section only shows matches on the negotiator's OWN listings (post a listing as one test account, post a matching requirement as a second test account, confirm it appears only on the FIRST account's dashboard, not the second's), the primary card's agency name renders (once migration 0019 is live), and "Co-Broke" successfully calls `sendCobrokeRequest` (check `cobroke_request` table gains a row).
6. Confirm Recent Listings cards show a real relative timestamp.
