# My Inventory Premium Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle `MyInventoryScreen` from the Stitch "My Inventory (Premium Co-Broking Management)" mockup, building every interactive element with real function: a real Drafts system (local persistence), real Bump-to-top, real Edit flow, real Share, real status-action menu, and 3 new negotiator-set listing fields.

**Architecture:** One migration (3 new nullable/defaulted `listing` columns + a `bumped_at` ordering change), a handful of new pure helpers/models, a dual-mode `PostListingScreen` (create and edit share one form), a new local-only Drafts subsystem, and a full restyle of `MyInventoryScreen` reusing the header/ticker/card conventions already established this session for Dashboard/Marketplace/Messages.

**Tech Stack:** Flutter, Riverpod, Supabase (PostgREST), `share_plus` (new dependency), `shared_preferences` (already a dependency), `easy_localization`, `phosphor_flutter`.

## Global Constraints

- `bumpedAt` ordering never affects "N Days on Market" (always computed from `createdAt`, never `bumpedAt`).
- Self-attestation badges (`titleVerified`/`exclusiveMandate`) render ONLY when `true` — never a placeholder/implied-false state — and the posting-form caption must make clear these are self-declared by the owner, not third-party-verified.
- `commissionSplitPercent` renders only when non-null — never a fabricated fallback percentage.
- The Active / Co-Broke-in-Review / Closed-Sold tab partition is mutually exclusive and must sum to the real total (no listing counted twice, none silently dropped).
- Drafts are never counted in the "N Units" header pill (drafts aren't `Listing` rows) and never touch the `listing` table until real submission from the resumed form.
- The more-menu's status actions reuse `property_detail_screen.dart`'s exact current gating (mark-sold/withdraw/reactivate visibility + atCap-disables-reactivate), duplicated locally — not imported/shared via a new abstraction (too small, ~15 lines, to warrant one).
- All new/changed icons use `PhosphorIcons.x(PhosphorIconsStyle.bold)`, never `Icons.*`.
- `flutter analyze` and the full `flutter test` suite must stay clean throughout every task.
- No golden-image tests.
- EN/MS l10n key parity maintained throughout; reuse the existing `property_mark_sold`/`property_withdraw`/`property_reactivate` keys verbatim in the more-menu rather than duplicating them.
- Migration `0020_listing_premium_fields.sql` is created as a **file only** — no task applies it. The user applies it manually via the Supabase SQL Editor after Task 2, same as every prior migration in this project.
- `share_plus`'s version is resolved by running `flutter pub add share_plus` at execution time, never hardcoded to a version guessed while writing this plan.

---

## Task 1: `Listing` model gains 4 new fields (zero test-fixture blast radius)

**Files:**
- Modify: `app/lib/features/listing/models/listing.dart`

**Interfaces:**
- Produces: `Listing.bumpedAt` (`DateTime?`), `Listing.commissionSplitPercent` (`double?`), `Listing.titleVerified` (`bool`, defaults `false`), `Listing.exclusiveMandate` (`bool`, defaults `false`). All four are either nullable-optional or defaulted — no existing `Listing(...)` construction anywhere in the codebase needs to change to keep compiling.

- [ ] **Step 1: Read the current file**

```bash
cat "app/lib/features/listing/models/listing.dart"
```

Confirm it matches (already verified this session — `Listing` lost its `const` constructor in an earlier plan when `createdAt` was added, so it is a plain, non-const class today):
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

- [ ] **Step 2: Add the 4 new fields**

Replace the whole file with:

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

  /// Set only by the "Bump Listing" action (My Inventory Premium
  /// Restyle) -- kept SEPARATE from [createdAt] deliberately: createdAt is
  /// this listing's true age (backs "N Days on Market" and the
  /// Dashboard's Recent Listings relative timestamp) and must never
  /// change after creation. A bump changes ordering, never age.
  final DateTime? bumpedAt;

  /// The percentage of the eventual transaction commission this
  /// listing's owner is offering to whichever co-broker brings a
  /// qualifying buyer. Standalone from `Agreement.splitInitiator`/
  /// `splitCounterparty`, which only exists once a specific co-broke
  /// request is formalized into a deal -- this is the owner's own
  /// upfront, self-set advertised split. Null means the owner didn't set
  /// one; UI must never show a fabricated fallback percentage.
  final double? commissionSplitPercent;

  /// Self-attested by the listing's own owner -- NOT third-party
  /// verified. Defaults false so every existing call site (11+ test
  /// fixtures, `createListing`) compiles unchanged.
  final bool titleVerified;

  /// Self-attested by the listing's own owner -- NOT third-party
  /// verified. Same default-false reasoning as [titleVerified].
  final bool exclusiveMandate;

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
    this.bumpedAt,
    this.commissionSplitPercent,
    this.titleVerified = false,
    this.exclusiveMandate = false,
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
      bumpedAt: json['bumped_at'] == null ? null : DateTime.parse(json['bumped_at'] as String),
      commissionSplitPercent: (json['commission_split_percent'] as num?)?.toDouble(),
      titleVerified: json['title_verified'] as bool? ?? false,
      exclusiveMandate: json['exclusive_mandate'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 3: Verify zero test-fixture blast radius**

```bash
cd "app" && flutter analyze
```

Expected: `No issues found!` — every existing `Listing(...)` construction (in `app/test/features/listing/`, `app/test/features/matching/`, `app/test/features/collaboration/`, `app/test/features/home/`, `app/test/core/widgets/`) already omits `const` (from the earlier `createdAt` plan) and none of them need to pass the 4 new fields, since all 4 are optional/defaulted. If the analyzer reports anything, it means a fixture is doing something unexpected — read the specific error and fix only what it names, don't preemptively touch files the analyzer doesn't flag.

- [ ] **Step 4: Run the full test suite**

```bash
cd "app" && flutter test
```

Expected: all tests pass, same count as before this task (no behavior changed, only new optional fields added).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/listing/models/listing.dart
git commit -m "feat: add bumpedAt/commissionSplitPercent/titleVerified/exclusiveMandate to Listing"
```

---

## Task 2: Migration `0020_listing_premium_fields.sql`

**Files:**
- Create: `supabase/migrations/0020_listing_premium_fields.sql`

**Interfaces:**
- Produces: `listing.bumped_at` (`timestamptz`, nullable), `listing.commission_split_percent` (`numeric(5,2)`, nullable, checked `> 0 and <= 100` when set), `listing.title_verified` (`boolean not null default false`), `listing.exclusive_mandate` (`boolean not null default false`). Task 3's repository changes and Task 1's model (already merged) both read/write these exact column names.

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/0020_listing_premium_fields.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0019.
--
-- Three new negotiator-set fields for the My Inventory Premium Restyle:
-- bumped_at (a real "resurface to top of feed" signal, kept separate from
-- created_at so a bump never falsifies a listing's true age elsewhere in
-- the app -- e.g. Dashboard's Recent Listings relative timestamp),
-- commission_split_percent (the owner's own advertised co-broke split,
-- standalone from Agreement's post-deal formal split), and
-- title_verified/exclusive_mandate (self-attested by the owner -- NOT
-- third-party verified; the in-app posting form's own caption makes this
-- explicit, this migration only adds the storage for it).
alter table listing add column if not exists bumped_at timestamptz;
alter table listing add column if not exists commission_split_percent numeric(5,2)
  check (commission_split_percent is null or (commission_split_percent > 0 and commission_split_percent <= 100));
alter table listing add column if not exists title_verified boolean not null default false;
alter table listing add column if not exists exclusive_mandate boolean not null default false;
```

- [ ] **Step 2: Tell the user to apply it**

Print this exact message to the user (do not apply the migration yourself):

> Migration `0020_listing_premium_fields.sql` created. Please apply it manually via the Supabase Dashboard's SQL Editor (same process as every prior migration), then let me know once it's done.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0020_listing_premium_fields.sql
git commit -m "feat: add bumped_at/commission_split_percent/title_verified/exclusive_mandate to listing table"
```

---

## Task 3: `ListingRepository` — bump, edit, create's new params, bump-aware ordering

**Files:**
- Modify: `app/lib/features/listing/listing_repository.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Future<void> bumpListing(String listingId)`, `Future<void> updateListingDetails({required String listingId, required String title, required String description, required String propertyType, required String transactionType, required String state, required String area, required double price, int? bedrooms, int? bathrooms, double? commissionSplitPercent, required bool titleVerified, required bool exclusiveMandate})`. `createListing(...)` gains 3 new optional named params: `double? commissionSplitPercent`, `bool titleVerified = false`, `bool exclusiveMandate = false`.

- [ ] **Step 1: Read the current file**

```bash
cat "app/lib/features/listing/listing_repository.dart"
```

- [ ] **Step 2: Add bump-aware ordering to the two fetch methods**

Find:
```dart
  Future<List<Listing>> fetchMarketplaceListings() async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<List<Listing>> fetchOwnListings(String negotiatorId) async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('negotiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }
```

Replace with:
```dart
  /// Ordered by bumped_at first (nulls last, so a never-bumped listing
  /// doesn't outrank a genuinely just-bumped one), then created_at --
  /// composing two .order() calls into one multi-key ORDER BY. A listing
  /// that was never bumped sorts purely by its real creation time; a
  /// bumped listing jumps to the top by its bump time. createdAt itself
  /// is never touched by a bump, so "N Days on Market" stays accurate.
  Future<List<Listing>> fetchMarketplaceListings() async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('status', 'active')
        .order('bumped_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<List<Listing>> fetchOwnListings(String negotiatorId) async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('negotiator_id', negotiatorId)
        .order('bumped_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }
```

- [ ] **Step 3: Add the 3 new optional params to `createListing`**

Find:
```dart
  Future<Listing> createListing({
    required String negotiatorId,
    required String title,
    required String description,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double price,
    int? bedrooms,
    int? bathrooms,
  }) async {
    final row = await _client
        .from('listing')
        .insert({
          'negotiator_id': negotiatorId,
          'title': title,
          'description': description,
          'property_type': propertyType,
          'transaction_type': transactionType,
          'state': state,
          'area': area,
          'price': price,
          'bedrooms': bedrooms,
          'bathrooms': bathrooms,
        })
        .select()
        .single();
    return Listing.fromJson(row);
  }
```

Replace with:
```dart
  Future<Listing> createListing({
    required String negotiatorId,
    required String title,
    required String description,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double price,
    int? bedrooms,
    int? bathrooms,
    double? commissionSplitPercent,
    bool titleVerified = false,
    bool exclusiveMandate = false,
  }) async {
    final row = await _client
        .from('listing')
        .insert({
          'negotiator_id': negotiatorId,
          'title': title,
          'description': description,
          'property_type': propertyType,
          'transaction_type': transactionType,
          'state': state,
          'area': area,
          'price': price,
          'bedrooms': bedrooms,
          'bathrooms': bathrooms,
          'commission_split_percent': commissionSplitPercent,
          'title_verified': titleVerified,
          'exclusive_mandate': exclusiveMandate,
        })
        .select()
        .single();
    return Listing.fromJson(row);
  }
```

- [ ] **Step 4: Add `bumpListing` and `updateListingDetails`**

Find:
```dart
  Future<void> updateListingStatus({required String listingId, required String status}) {
    return _client.from('listing').update({'status': status}).eq('listing_id', listingId);
  }
```

Add immediately after it:
```dart

  /// Real "resurface to top of feed" action -- sets bumped_at to now,
  /// which fetchMarketplaceListings/fetchOwnListings's own ordering
  /// already accounts for. Never touches created_at.
  Future<void> bumpListing(String listingId) {
    return _client.from('listing').update({'bumped_at': DateTime.now().toIso8601String()}).eq('listing_id', listingId);
  }

  /// General field update for the Edit Listing flow. Deliberately does
  /// NOT touch negotiator_id, status, photo_urls, created_at, or
  /// bumped_at -- each of those has its own dedicated update path
  /// (updateListingPhotos, updateListingStatus, bumpListing) or must
  /// never change after creation.
  Future<void> updateListingDetails({
    required String listingId,
    required String title,
    required String description,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double price,
    int? bedrooms,
    int? bathrooms,
    double? commissionSplitPercent,
    required bool titleVerified,
    required bool exclusiveMandate,
  }) {
    return _client.from('listing').update({
      'title': title,
      'description': description,
      'property_type': propertyType,
      'transaction_type': transactionType,
      'state': state,
      'area': area,
      'price': price,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'commission_split_percent': commissionSplitPercent,
      'title_verified': titleVerified,
      'exclusive_mandate': exclusiveMandate,
    }).eq('listing_id', listingId);
  }
```

- [ ] **Step 5: Run analyze and the full test suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean (this is Supabase-boundary code, not unit-tested per this project's convention — manually verified once migration 0020 is live).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/listing/listing_repository.dart
git commit -m "feat: add bumpListing/updateListingDetails, bump-aware ordering, createListing's new fields"
```

---

## Task 4: Pure mutually-exclusive tab-partition helper

**Files:**
- Modify: `app/lib/features/listing/listing_status_filter.dart`
- Modify: `app/test/features/listing/listing_status_filter_test.dart`

**Interfaces:**
- Consumes: `Listing` (existing), `CobrokeRequestCandidate` (existing, `app/lib/features/collaboration/models/cobroke_request_candidate.dart` — has `.request.status` and `.match.listing.listingId`).
- Produces: `ListingStatusFilter.partition(List<Listing> listings, List<CobrokeRequestCandidate> receivedRequests) -> ({List<Listing> active, List<Listing> coBrokeInReview, List<Listing> closedSold})`. Task 7 (screen restyle) calls this once per build and reads the 3 named-record fields for its tab contents/counts.

- [ ] **Step 1: Read the current file and its test**

```bash
cat "app/lib/features/listing/listing_status_filter.dart"
cat "app/test/features/listing/listing_status_filter_test.dart"
```

(Already read this session — reproduced above in this plan's own research. `byStatus` stays as-is; this task ADDS a new static method alongside it, doesn't replace it, since `byStatus` may still be referenced elsewhere — confirm via `grep -rn "ListingStatusFilter.byStatus" app/lib app/test` and if the only caller is `my_inventory_screen.dart` itself (which Task 7 rewrites to use `partition` instead), it's fine to leave `byStatus` in place unused-by-the-app but still covered by its own existing tests — do not delete it, this task's job is additive only.)

- [ ] **Step 2: Write the failing test**

Add to `app/test/features/listing/listing_status_filter_test.dart` (append inside the existing `void main()`, after the existing `group('ListingStatusFilter.byStatus', ...)` block — add a new top-level `import` for `CobrokeRequestCandidate` and its dependencies, and a new fixture helper + group):

```dart
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';
```
(add these imports at the top of the file, alongside the existing ones)

```dart
CobrokeRequestCandidate _pendingRequestFor(String listingId) {
  final listing = _listing(listingId, 'active');
  const requirement = Requirement(
    requirementId: 'r-1',
    negotiatorId: 'n-2',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'PJ',
    budgetMin: 100000,
    budgetMax: 200000,
    photoUrls: [],
    status: 'open',
  );
  const owner = ListingOwner(fullName: 'Owner', renNumber: '12345');
  return CobrokeRequestCandidate(
    request: CobrokeRequest(
      requestId: 'req-$listingId',
      matchId: 'm-$listingId',
      initiatorId: 'n-2',
      status: 'pending',
      createdAt: DateTime(2026, 9, 6),
    ),
    match: MatchCandidate(
      matchId: 'm-$listingId',
      score: 90,
      listing: listing,
      requirement: requirement,
      listingOwner: owner,
      requirementOwner: owner,
    ),
  );
}

void main() {
  group('ListingStatusFilter.byStatus', () {
    // ... existing tests unchanged ...
  });

  group('ListingStatusFilter.partition', () {
    test('splits active listings into Active vs Co-Broke in Review by pending requests', () {
      final listings = [_listing('1', 'active'), _listing('2', 'active')];
      final received = [_pendingRequestFor('2')];

      final result = ListingStatusFilter.partition(listings, received);

      expect(result.active.map((l) => l.listingId), ['1']);
      expect(result.coBrokeInReview.map((l) => l.listingId), ['2']);
      expect(result.closedSold, isEmpty);
    });

    test('groups sold and withdrawn together under closedSold', () {
      final listings = [_listing('1', 'sold'), _listing('2', 'withdrawn'), _listing('3', 'active')];

      final result = ListingStatusFilter.partition(listings, const []);

      expect(result.closedSold.map((l) => l.listingId).toSet(), {'1', '2'});
      expect(result.active.map((l) => l.listingId), ['3']);
    });

    test('a DECLINED request on a listing does not move it into coBrokeInReview', () {
      final listings = [_listing('1', 'active')];
      final declined = _pendingRequestFor('1');
      final declinedRequest = CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: declined.request.requestId,
          matchId: declined.request.matchId,
          initiatorId: declined.request.initiatorId,
          status: 'declined',
          createdAt: declined.request.createdAt,
        ),
        match: declined.match,
      );

      final result = ListingStatusFilter.partition(listings, [declinedRequest]);

      expect(result.active.map((l) => l.listingId), ['1']);
      expect(result.coBrokeInReview, isEmpty);
    });

    test('partition is mutually exclusive and sums to the input total', () {
      final listings = [
        _listing('1', 'active'),
        _listing('2', 'active'),
        _listing('3', 'sold'),
        _listing('4', 'withdrawn'),
      ];
      final received = [_pendingRequestFor('2')];

      final result = ListingStatusFilter.partition(listings, received);

      final totalPartitioned = result.active.length + result.coBrokeInReview.length + result.closedSold.length;
      expect(totalPartitioned, listings.length);
    });
  });
}
```

(Note: the existing `group('ListingStatusFilter.byStatus', ...)` block and its two tests stay exactly as they are today — only ADD the new imports, the new `_pendingRequestFor` helper function, and the new `group('ListingStatusFilter.partition', ...)` block alongside them in the same file.)

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd "app" && flutter test test/features/listing/listing_status_filter_test.dart
```

Expected: FAIL — `ListingStatusFilter.partition` isn't defined yet.

- [ ] **Step 4: Implement `partition`**

Replace the whole file `app/lib/features/listing/listing_status_filter.dart` with:

```dart
import '../collaboration/models/cobroke_request_candidate.dart';
import 'models/listing.dart';

/// Pure client-side tab filters for My Inventory.
class ListingStatusFilter {
  ListingStatusFilter._();

  static List<Listing> byStatus(List<Listing> listings, String status) {
    return listings.where((listing) => listing.status == status).toList();
  }

  /// Mutually-exclusive 3-way split for the My Inventory Premium Restyle's
  /// Active / Co-Broke in Review / Closed·Sold tabs -- every input listing
  /// appears in exactly one output list, so the three lengths always sum
  /// to listings.length. `receivedRequests` is the negotiator's own
  /// receivedRequestsProvider result (requests where they are NOT the
  /// initiator, i.e. inquiries on their own listings) -- a listing moves
  /// into coBrokeInReview only when it has at least one PENDING (not
  /// accepted, not declined) request against it.
  static ({List<Listing> active, List<Listing> coBrokeInReview, List<Listing> closedSold}) partition(
    List<Listing> listings,
    List<CobrokeRequestCandidate> receivedRequests,
  ) {
    final listingIdsWithPendingRequest = receivedRequests
        .where((c) => c.request.status == 'pending')
        .map((c) => c.match.listing.listingId)
        .toSet();

    final active = <Listing>[];
    final coBrokeInReview = <Listing>[];
    final closedSold = <Listing>[];

    for (final listing in listings) {
      if (listing.status == 'sold' || listing.status == 'withdrawn') {
        closedSold.add(listing);
      } else if (listingIdsWithPendingRequest.contains(listing.listingId)) {
        coBrokeInReview.add(listing);
      } else {
        active.add(listing);
      }
    }

    return (active: active, coBrokeInReview: coBrokeInReview, closedSold: closedSold);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd "app" && flutter test test/features/listing/listing_status_filter_test.dart
```

Expected: PASS, 6/6 (2 existing `byStatus` tests + 4 new `partition` tests).

- [ ] **Step 6: Run `flutter analyze` and the full suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/listing/listing_status_filter.dart app/test/features/listing/listing_status_filter_test.dart
git commit -m "feat: add ListingStatusFilter.partition for the 3-way My Inventory tab split"
```

---

## Task 5: Drafts subsystem (local-only, real function)

**Files:**
- Create: `app/lib/features/listing/models/listing_draft.dart`
- Create: `app/lib/features/listing/listing_drafts_provider.dart`
- Create: `app/test/features/listing/models/listing_draft_test.dart`

**Interfaces:**
- Produces: `ListingDraft` (model: `draftId`, `savedAt`, `title`, `description`, `propertyType`, `transactionType`, `state`, `area`, `price` (`String?`, stored as the raw text field value since a draft may have an incomplete/unparseable price while mid-edit), `bedrooms`/`bathrooms` (`String?`, same reasoning), `commissionSplitPercent` (`String?`), `titleVerified`/`exclusiveMandate` (`bool`), with `toJson()`/`ListingDraft.fromJson(Map)`). `listingDraftsProvider = StateNotifierProvider<ListingDraftsNotifier, List<ListingDraft>>`, with `ListingDraftsNotifier.add(ListingDraft draft)` and `ListingDraftsNotifier.remove(String draftId)`. Task 6 (PostListingScreen) calls `add`/`remove`; Task 7 (screen restyle) watches `listingDraftsProvider` for the Drafts tab.

- [ ] **Step 1: Write the failing test**

Create `app/test/features/listing/models/listing_draft_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing_draft.dart';

void main() {
  test('toJson/fromJson round-trips every field', () {
    final draft = ListingDraft(
      draftId: 'd-1',
      savedAt: DateTime(2026, 9, 6, 12, 0, 0),
      title: 'Test Condo',
      description: 'A nice place',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: '450000',
      bedrooms: '3',
      bathrooms: '2',
      commissionSplitPercent: '1.5',
      titleVerified: true,
      exclusiveMandate: false,
    );

    final roundTripped = ListingDraft.fromJson(draft.toJson());

    expect(roundTripped.draftId, draft.draftId);
    expect(roundTripped.savedAt, draft.savedAt);
    expect(roundTripped.title, draft.title);
    expect(roundTripped.description, draft.description);
    expect(roundTripped.propertyType, draft.propertyType);
    expect(roundTripped.transactionType, draft.transactionType);
    expect(roundTripped.state, draft.state);
    expect(roundTripped.area, draft.area);
    expect(roundTripped.price, draft.price);
    expect(roundTripped.bedrooms, draft.bedrooms);
    expect(roundTripped.bathrooms, draft.bathrooms);
    expect(roundTripped.commissionSplitPercent, draft.commissionSplitPercent);
    expect(roundTripped.titleVerified, draft.titleVerified);
    expect(roundTripped.exclusiveMandate, draft.exclusiveMandate);
  });

  test('nullable fields round-trip as null when omitted', () {
    final draft = ListingDraft(
      draftId: 'd-2',
      savedAt: DateTime(2026, 9, 6),
      title: 'Bare Draft',
      description: '',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: '',
      price: null,
      bedrooms: null,
      bathrooms: null,
      commissionSplitPercent: null,
      titleVerified: false,
      exclusiveMandate: false,
    );

    final roundTripped = ListingDraft.fromJson(draft.toJson());

    expect(roundTripped.price, isNull);
    expect(roundTripped.bedrooms, isNull);
    expect(roundTripped.bathrooms, isNull);
    expect(roundTripped.commissionSplitPercent, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd "app" && flutter test test/features/listing/models/listing_draft_test.dart
```

Expected: FAIL — `package:renly/features/listing/models/listing_draft.dart` doesn't exist yet.

- [ ] **Step 3: Implement `ListingDraft`**

Create `app/lib/features/listing/models/listing_draft.dart`:

```dart
/// A locally-saved, in-progress Post Listing form -- never touches the
/// `listing` table (no half-validated row belongs there). Text-field
/// values are stored as raw strings (not parsed num/int) since a draft
/// may be mid-edit with an incomplete or unparseable value; parsing only
/// happens for real when the resumed form is actually submitted.
class ListingDraft {
  final String draftId;
  final DateTime savedAt;
  final String title;
  final String description;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final String? price;
  final String? bedrooms;
  final String? bathrooms;
  final String? commissionSplitPercent;
  final bool titleVerified;
  final bool exclusiveMandate;

  const ListingDraft({
    required this.draftId,
    required this.savedAt,
    required this.title,
    required this.description,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    this.price,
    this.bedrooms,
    this.bathrooms,
    this.commissionSplitPercent,
    required this.titleVerified,
    required this.exclusiveMandate,
  });

  Map<String, dynamic> toJson() {
    return {
      'draft_id': draftId,
      'saved_at': savedAt.toIso8601String(),
      'title': title,
      'description': description,
      'property_type': propertyType,
      'transaction_type': transactionType,
      'state': state,
      'area': area,
      'price': price,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'commission_split_percent': commissionSplitPercent,
      'title_verified': titleVerified,
      'exclusive_mandate': exclusiveMandate,
    };
  }

  factory ListingDraft.fromJson(Map<String, dynamic> json) {
    return ListingDraft(
      draftId: json['draft_id'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      price: json['price'] as String?,
      bedrooms: json['bedrooms'] as String?,
      bathrooms: json['bathrooms'] as String?,
      commissionSplitPercent: json['commission_split_percent'] as String?,
      titleVerified: json['title_verified'] as bool,
      exclusiveMandate: json['exclusive_mandate'] as bool,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd "app" && flutter test test/features/listing/models/listing_draft_test.dart
```

Expected: PASS, 2/2.

- [ ] **Step 5: Implement the SharedPreferences-backed provider**

Create `app/lib/features/listing/listing_drafts_provider.dart`:

```dart
// app/lib/features/listing/listing_drafts_provider.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/listing_draft.dart';

/// Locally-saved in-progress Post Listing forms -- mirrors
/// conversation_list_screen.dart's _ArchivedConversations StateNotifier
/// pattern exactly (SharedPreferences-backed, loaded async at
/// construction). A draft never becomes a real Listing row until the
/// resumed form is actually submitted.
class ListingDraftsNotifier extends StateNotifier<List<ListingDraft>> {
  ListingDraftsNotifier() : super(const []) {
    _load();
  }

  static const _prefsKey = 'listing_drafts';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    state = raw.map((s) => ListingDraft.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
  }

  Future<void> add(ListingDraft draft) async {
    state = [...state, draft];
    await _persist();
  }

  Future<void> remove(String draftId) async {
    state = state.where((d) => d.draftId != draftId).toList();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state.map((d) => jsonEncode(d.toJson())).toList());
  }
}

final listingDraftsProvider = StateNotifierProvider<ListingDraftsNotifier, List<ListingDraft>>((ref) {
  return ListingDraftsNotifier();
});
```

- [ ] **Step 6: Run `flutter analyze` and the full test suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/listing/models/listing_draft.dart app/lib/features/listing/listing_drafts_provider.dart app/test/features/listing/models/listing_draft_test.dart
git commit -m "feat: add local-only ListingDraft model and SharedPreferences-backed provider"
```

---

## Task 6: `PostListingScreen` dual create/edit mode + Save as Draft + edit route

**Files:**
- Modify: `app/lib/features/listing/post_listing_screen.dart`
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/test/features/listing/post_listing_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `Listing` (Task 1's new fields), `ListingRepository.updateListingDetails` (Task 3), `ListingDraft`/`listingDraftsProvider` (Task 5), `listingDetailProvider` (existing, `app/lib/features/listing/listing_providers.dart`).
- Produces: `PostListingScreen({String? editListingId, ListingDraft? initialDraft})` — both optional, mutually exclusive in practice (a screen instance is either create/plain, edit, or draft-resume). Task 7/8/9 (My Inventory restyle) push `/property/:listingId/edit` for Edit and pass a draft's own resume action for Drafts tab rows.

- [ ] **Step 1: Read the current file fresh**

```bash
cat "app/lib/features/listing/post_listing_screen.dart"
```

(Full current content already reproduced in this plan's own research above — 376 lines. Re-read now to confirm no other task has touched it first.)

- [ ] **Step 2: Add new l10n keys**

In `app/assets/translations/en.json`, find `"listing_post_now": "Post Now",` and add after it:
```json
  "listing_edit_title": "Edit Listing",
  "listing_save_changes": "Save Changes",
  "listing_save_as_draft": "Save as Draft",
  "listing_field_commission_split": "Commission Split Offered (%)",
  "listing_field_title_verified": "I confirm I hold clear, verified title to this property",
  "listing_field_exclusive_mandate": "I confirm this is an exclusive mandate",
  "listing_self_attestation_notice": "This is a declaration you make yourself, not a third-party verification.",
```

In `app/assets/translations/ms.json`, find `"listing_post_now": "Siarkan Sekarang",` and add after it:
```json
  "listing_edit_title": "Sunting Senarai",
  "listing_save_changes": "Simpan Perubahan",
  "listing_save_as_draft": "Simpan sebagai Draf",
  "listing_field_commission_split": "Split Komisen Ditawarkan (%)",
  "listing_field_title_verified": "Saya sahkan saya memegang hak milik yang jelas dan disahkan untuk hartanah ini",
  "listing_field_exclusive_mandate": "Saya sahkan ini adalah mandat eksklusif",
  "listing_self_attestation_notice": "Ini adalah pengisytiharan yang anda buat sendiri, bukan pengesahan pihak ketiga.",
```

(Check the exact neighboring line in each file first via `grep -n "listing_post_now" app/assets/translations/en.json app/assets/translations/ms.json` — insert at that exact position, matching this project's established per-task l10n convention.)

- [ ] **Step 3: Replace the whole file with the dual-mode version**

```dart
// app/lib/features/listing/post_listing_screen.dart
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/malaysian_states.dart';
import '../../core/widgets/brutalist_button.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import 'listing_drafts_provider.dart';
import 'listing_providers.dart';
import 'models/listing.dart';
import 'models/listing_draft.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Ports stitch_renly_property_agent_network/post_listing's "Sediakan
/// Listing" branch, now in 3 modes (My Inventory Premium Restyle):
/// plain create (both params null), edit (editListingId set -- loads and
/// pre-fills from the real Listing, submits via updateListingDetails),
/// and draft-resume (initialDraft set -- pre-fills from a local,
/// never-submitted draft). editListingId and initialDraft are mutually
/// exclusive in practice; passing both is not a supported combination.
class PostListingScreen extends ConsumerStatefulWidget {
  const PostListingScreen({super.key, this.editListingId, this.initialDraft});

  final String? editListingId;
  final ListingDraft? initialDraft;

  @override
  ConsumerState<PostListingScreen> createState() => _PostListingScreenState();
}

class _PostListingScreenState extends ConsumerState<PostListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _areaController = TextEditingController();
  final _priceController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsController = TextEditingController();
  final _commissionSplitController = TextEditingController();
  String _propertyType = 'apartment';
  String _transactionType = 'sale';
  String _state = malaysianStates.first;
  bool _titleVerified = false;
  bool _exclusiveMandate = false;
  final List<XFile> _photos = [];
  bool _submitting = false;
  String? _submitError;

  /// Set as soon as createListing() succeeds. _submit() is three separate
  /// network calls (create -> upload photos -> attach urls); if it fails
  /// partway, the natural user response is to tap "Post Now" again, which
  /// without this would insert a SECOND listing row. Remembering the id
  /// makes the retry resume from the upload step instead. Also set
  /// immediately in edit mode (from widget.editListingId) so _submit's
  /// branch logic has one single "do we have an id" check.
  String? _createdListingId;

  bool get _isEditMode => widget.editListingId != null;

  /// One-shot guard: the loaded Listing (edit mode) arrives asynchronously
  /// via listingDetailProvider, but the form's controllers must only be
  /// populated ONCE, not on every rebuild while that provider re-emits.
  bool _prefilledFromListing = false;

  @override
  void initState() {
    super.initState();
    _createdListingId = widget.editListingId;
    final draft = widget.initialDraft;
    if (draft != null) {
      _titleController.text = draft.title;
      _descriptionController.text = draft.description;
      _propertyType = draft.propertyType;
      _transactionType = draft.transactionType;
      _state = draft.state;
      _areaController.text = draft.area;
      _priceController.text = draft.price ?? '';
      _bedroomsController.text = draft.bedrooms ?? '';
      _bathroomsController.text = draft.bathrooms ?? '';
      _commissionSplitController.text = draft.commissionSplitPercent ?? '';
      _titleVerified = draft.titleVerified;
      _exclusiveMandate = draft.exclusiveMandate;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _areaController.dispose();
    _priceController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    _commissionSplitController.dispose();
    super.dispose();
  }

  void _prefillFromListing(Listing listing) {
    if (_prefilledFromListing) return;
    _prefilledFromListing = true;
    _titleController.text = listing.title;
    _descriptionController.text = listing.description;
    _propertyType = listing.propertyType;
    _transactionType = listing.transactionType;
    _state = listing.state;
    _areaController.text = listing.area;
    _priceController.text = listing.price.toString();
    _bedroomsController.text = listing.bedrooms?.toString() ?? '';
    _bathroomsController.text = listing.bathrooms?.toString() ?? '';
    _commissionSplitController.text = listing.commissionSplitPercent?.toString() ?? '';
    _titleVerified = listing.titleVerified;
    _exclusiveMandate = listing.exclusiveMandate;
  }

  Future<void> _pickPhotos() async {
    final remaining = 10 - _photos.length;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85, limit: remaining);
    if (picked.isEmpty) return;
    setState(() {
      _photos.addAll(picked.take(remaining));
    });
  }

  void _removePhoto(int index) {
    final removed = _photos[index];
    setState(() => _photos.removeAt(index));
    _photoBytesCache.remove(removed.path);
  }

  /// Keyed on XFile.path rather than the list index so that removing a
  /// photo doesn't shift every later thumbnail onto the wrong bytes. Cached
  /// because a FutureBuilder re-runs its future on every rebuild otherwise,
  /// re-reading the whole image each frame.
  final Map<String, Future<Uint8List>> _photoBytesCache = {};

  Future<Uint8List> _photoBytes(int index) {
    final photo = _photos[index];
    return _photoBytesCache.putIfAbsent(photo.path, photo.readAsBytes);
  }

  double? get _commissionSplitValue {
    final text = _commissionSplitController.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  Future<void> _saveAsDraft() async {
    if (_titleController.text.trim().isEmpty) return;
    final draft = ListingDraft(
      draftId: widget.initialDraft?.draftId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      savedAt: DateTime.now(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      propertyType: _propertyType,
      transactionType: _transactionType,
      state: _state,
      area: _areaController.text.trim(),
      price: _priceController.text.trim().isEmpty ? null : _priceController.text.trim(),
      bedrooms: _bedroomsController.text.trim().isEmpty ? null : _bedroomsController.text.trim(),
      bathrooms: _bathroomsController.text.trim().isEmpty ? null : _bathroomsController.text.trim(),
      commissionSplitPercent:
          _commissionSplitController.text.trim().isEmpty ? null : _commissionSplitController.text.trim(),
      titleVerified: _titleVerified,
      exclusiveMandate: _exclusiveMandate,
    );
    // Resuming an existing draft and saving again replaces it (same
    // draftId) rather than creating a duplicate entry.
    if (widget.initialDraft != null) {
      await ref.read(listingDraftsProvider.notifier).remove(widget.initialDraft!.draftId);
    }
    await ref.read(listingDraftsProvider.notifier).add(draft);
    if (!mounted) return;
    context.go('/my-inventory');
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final repository = ref.read(listingRepositoryProvider);
    try {
      if (_isEditMode) {
        await repository.updateListingDetails(
          listingId: widget.editListingId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          propertyType: _propertyType,
          transactionType: _transactionType,
          state: _state,
          area: _areaController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.parse(_bedroomsController.text.trim()),
          bathrooms: _bathroomsController.text.trim().isEmpty ? null : int.parse(_bathroomsController.text.trim()),
          commissionSplitPercent: _commissionSplitValue,
          titleVerified: _titleVerified,
          exclusiveMandate: _exclusiveMandate,
        );
        ref.invalidate(listingDetailProvider(widget.editListingId!));
        ref.invalidate(marketplaceListingsProvider);
        ref.invalidate(myListingsProvider(negotiatorId));
        if (!mounted) return;
        context.go('/my-inventory');
        return;
      }

      // Only create the row on the first attempt -- a retry after a failed
      // photo upload reuses the id created last time.
      if (_createdListingId == null) {
        final listing = await repository.createListing(
          negotiatorId: negotiatorId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          propertyType: _propertyType,
          transactionType: _transactionType,
          state: _state,
          area: _areaController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.parse(_bedroomsController.text.trim()),
          bathrooms: _bathroomsController.text.trim().isEmpty ? null : int.parse(_bathroomsController.text.trim()),
          commissionSplitPercent: _commissionSplitValue,
          titleVerified: _titleVerified,
          exclusiveMandate: _exclusiveMandate,
        );
        _createdListingId = listing.listingId;
      }
      final listingId = _createdListingId!;

      final photoUrls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        final path = await repository.uploadListingPhoto(
          negotiatorId: negotiatorId,
          listingId: listingId,
          index: i,
          bytes: bytes,
        );
        photoUrls.add(path);
      }
      if (photoUrls.isNotEmpty) {
        await repository.updateListingPhotos(listingId: listingId, photoUrls: photoUrls);
      }

      ref.invalidate(marketplaceListingsProvider);
      ref.invalidate(myListingsProvider(negotiatorId));
      // activeListingCountProvider is deliberately not autoDispose, so it
      // caches for the whole process lifetime unless invalidated here. Without
      // this, a free-tier user who posts (or later withdraws) a listing keeps
      // seeing a stale count and a falsely disabled submit button. Invalidated
      // only after the create + photo-upload sequence has fully succeeded, so a
      // retry after a photo-upload failure isn't handed a fresh (now higher)
      // count that would disable the submit button it needs.
      ref.invalidate(activeListingCountProvider(negotiatorId));

      // A draft that was just successfully posted is no longer a draft.
      if (widget.initialDraft != null) {
        await ref.read(listingDraftsProvider.notifier).remove(widget.initialDraft!.draftId);
      }

      try {
        final createdListing = await repository.fetchListingById(listingId);
        await ref.read(matchingRepositoryProvider).computeAndStoreMatchesForListing(createdListing);
        ref.invalidate(myMatchesProvider);
        ref.invalidate(matchesForListingProvider);
        ref.invalidate(matchesForRequirementProvider);
      } catch (_) {
        // Best-effort: matching is an enhancement, not a requirement for
        // the listing itself to have been created successfully. A failure
        // here must not trap the user on a form whose real submission
        // already succeeded. Re-fetched by id (rather than reusing the
        // `listing` local from the retry-safety branch above) because that
        // variable only exists inside `if (_createdListingId == null)` --
        // a retried submit that skips re-creating the row wouldn't have it.
      }

      if (!mounted) return;
      context.go('/my-inventory');
    } catch (e) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final tierAsync = ref.watch(subscriptionStatusProvider);
    final countAsync = negotiatorId == null
        ? const AsyncValue<int>.data(0)
        : ref.watch(activeListingCountProvider(negotiatorId));
    final activeCount = countAsync.valueOrNull ?? 0;
    final atCap = !_isEditMode && tierAsync.valueOrNull?.tier == 'free' && activeCount >= 3;

    if (_isEditMode) {
      final listingAsync = ref.watch(listingDetailProvider(widget.editListingId!));
      listingAsync.whenData(_prefillFromListing);
      if (listingAsync.isLoading && !_prefilledFromListing) {
        return Scaffold(
          appBar: AppBar(title: Text('listing_edit_title'.tr())),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? 'listing_edit_title'.tr() : 'listing_post_title'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('listing_title_field'),
                  controller: _titleController,
                  decoration: InputDecoration(labelText: 'listing_field_title'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('listing_description_field'),
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: 'listing_field_description'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('listing_property_type_field'),
                  initialValue: _propertyType,
                  decoration: InputDecoration(labelText: 'listing_field_property_type'.tr()),
                  items: [
                    DropdownMenuItem(value: 'apartment', child: Text('listing_property_type_apartment'.tr())),
                    DropdownMenuItem(value: 'house', child: Text('listing_property_type_house'.tr())),
                    DropdownMenuItem(value: 'commercial', child: Text('listing_property_type_commercial'.tr())),
                    DropdownMenuItem(value: 'land', child: Text('listing_property_type_land'.tr())),
                  ],
                  onChanged: (value) => setState(() => _propertyType = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('listing_transaction_type_field'),
                  initialValue: _transactionType,
                  decoration: InputDecoration(labelText: 'listing_field_transaction_type'.tr()),
                  items: [
                    DropdownMenuItem(value: 'sale', child: Text('listing_transaction_type_sale'.tr())),
                    DropdownMenuItem(value: 'rent', child: Text('listing_transaction_type_rent'.tr())),
                  ],
                  onChanged: (value) => setState(() => _transactionType = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('listing_state_field'),
                  initialValue: _state,
                  decoration: InputDecoration(labelText: 'listing_field_state'.tr()),
                  items: [
                    for (final state in malaysianStates) DropdownMenuItem(value: state, child: Text(state)),
                  ],
                  onChanged: (value) => setState(() => _state = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('listing_area_field'),
                  controller: _areaController,
                  decoration: InputDecoration(labelText: 'listing_field_area'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('listing_price_field'),
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'listing_field_price'.tr()),
                  validator: (value) {
                    final requiredError = _requiredValidator(value);
                    if (requiredError != null) return requiredError;
                    if (double.tryParse(value!.trim()) == null) return 'validation_required'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bedroomsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'listing_field_bedrooms'.tr()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _bathroomsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'listing_field_bathrooms'.tr()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('listing_commission_split_field'),
                  controller: _commissionSplitController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'listing_field_commission_split'.tr()),
                ),
                const SizedBox(height: 12),
                Text('listing_self_attestation_notice'.tr(), style: Theme.of(context).textTheme.labelSmall),
                SwitchListTile(
                  key: const Key('listing_title_verified_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('listing_field_title_verified'.tr()),
                  value: _titleVerified,
                  onChanged: (value) => setState(() => _titleVerified = value),
                ),
                SwitchListTile(
                  key: const Key('listing_exclusive_mandate_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('listing_field_exclusive_mandate'.tr()),
                  value: _exclusiveMandate,
                  onChanged: (value) => setState(() => _exclusiveMandate = value),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('listing_photos_label'.tr()),
                    Text('listing_photos_max'.tr()),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    ...List.generate(_photos.length, (index) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FutureBuilder<Uint8List>(
                                future: _photoBytes(index),
                                builder: (context, snapshot) {
                                  final bytes = snapshot.data;
                                  if (bytes == null) {
                                    return Container(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    );
                                  }
                                  return Image.memory(bytes, fit: BoxFit.cover);
                                },
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removePhoto(index),
                              child: const CircleAvatar(
                                radius: 12,
                                child: Icon(Icons.close, size: 16),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    if (_photos.length < 10)
                      OutlinedButton(
                        onPressed: _pickPhotos,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo),
                            Text('listing_add_photo'.tr(), style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ),
                  ],
                ),
                if (!_isEditMode && tierAsync.valueOrNull?.tier == 'free') ...[
                  const SizedBox(height: 12),
                  Text('$activeCount/3 ${'listing_active_count_label'.tr()}'),
                ],
                if (atCap) ...[
                  const SizedBox(height: 8),
                  Text(
                    'listing_cap_reached_message'.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                BrutalistButton(
                  label: _isEditMode ? 'listing_save_changes'.tr() : 'listing_post_now'.tr(),
                  onPressed: (_submitting || atCap) ? null : _submit,
                ),
                if (!_isEditMode) ...[
                  const SizedBox(height: 12),
                  BrutalistButton(
                    label: 'listing_save_as_draft'.tr(),
                    variant: BrutalistButtonVariant.secondary,
                    onPressed: _submitting ? null : _saveAsDraft,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the edit route**

In `app/lib/core/router/app_router.dart`, find:
```dart
      GoRoute(path: '/post-listing', builder: (context, state) => const PostListingScreen()),
```

Add immediately after it:
```dart
      GoRoute(
        path: '/property/:listingId/edit',
        builder: (context, state) => PostListingScreen(editListingId: state.pathParameters['listingId']),
      ),
```

- [ ] **Step 5: Update the existing test file**

Read `app/test/features/listing/post_listing_screen_test.dart` first (already exists with real tests for the create-mode flow). Its existing tests construct `PostListingScreen()` with no params — since `editListingId`/`initialDraft` are both optional, every existing test compiles and passes unchanged. Add one new test to the same file (after its existing tests, inside the same `void main()`):

```dart
  testWidgets('edit mode pre-fills fields from the existing listing and shows Save Changes', (tester) async {
    final existingListing = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'Existing Title',
      description: 'Existing description',
      propertyType: 'house',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Shah Alam',
      price: 500000,
      bedrooms: 4,
      bathrooms: 3,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PostListingScreen(editListingId: 'l-1'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentNegotiatorIdProvider.overrideWith((ref) => 'n-1'),
          listingDetailProvider('l-1').overrideWith((ref) async => existingListing),
          subscriptionStatusProvider.overrideWith((ref) async => const SubscriptionStatus(tier: 'professional')),
        ],
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

    expect(find.widgetWithText(TextFormField, 'Title'), findsNothing); // sanity: label not value
    final titleField = tester.widget<TextFormField>(find.byKey(const Key('listing_title_field')));
    expect(titleField.controller?.text, 'Existing Title');
    expect(find.text('listing_save_changes'.tr()), findsOneWidget);
    expect(find.text('listing_post_now'.tr()), findsNothing);
  });
```

(Check the existing test file's actual current imports/helper-wrap function first — reuse whatever `ProviderScope`/`EasyLocalization`/`MaterialApp.router` wrapping pattern it already establishes rather than inventing a second one; the snippet above shows the full wrapping inline in case the file doesn't already have a shared `_wrap` helper, but if it does, use that helper with its `overrides:` param instead, matching this project's own established per-file convention of reusing whatever pump helper already exists in a test file rather than duplicating boilerplate.)

- [ ] **Step 6: Run `flutter analyze` and the test file**

```bash
cd "app" && flutter analyze && flutter test test/features/listing/post_listing_screen_test.dart
```

Expected: both clean, all tests (existing + 1 new) pass.

- [ ] **Step 7: Run the full suite**

```bash
cd "app" && flutter test
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/listing/post_listing_screen.dart app/lib/core/router/app_router.dart app/test/features/listing/post_listing_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add edit/draft-resume dual mode to PostListingScreen, new edit route"
```

---

## Task 7: `MyInventoryScreen` header + ticker + tabs + search restyle

**Files:**
- Modify: `app/lib/features/listing/my_inventory_screen.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `myListingsProvider` (existing), `receivedRequestsProvider` (existing, `app/lib/features/collaboration/cobroke_request_providers.dart`), `myProfileProvider`/`unreadNotificationCountProvider` (existing, same header pattern as Dashboard/Marketplace/Messages), `ListingStatusFilter.partition` (Task 4), `listingDraftsProvider` (Task 5).
- Produces: nothing new for later tasks — Task 8 further modifies this same file's body (the card rendering), so read the current file state before editing in that task.

- [ ] **Step 1: Add new l10n keys**

In `app/assets/translations/en.json`, add near the existing `inventory_*` keys:
```json
  "inventory_units_label": "Units",
  "inventory_post_property": "Post Property",
  "inventory_ticker_inquiries": "Co-Broke Inquiries waiting for your verification",
  "inventory_ticker_review": "Review",
  "inventory_search_hint": "Search your units by building, street or ID...",
  "inventory_tab_co_broke_review": "Co-Broke in Review",
  "inventory_tab_closed_sold": "Closed / Sold",
  "inventory_tab_drafts": "Drafts",
  "inventory_drafts_empty": "No saved drafts.",
```

In `app/assets/translations/ms.json`, add the mirrored keys:
```json
  "inventory_units_label": "Unit",
  "inventory_post_property": "Siarkan Hartanah",
  "inventory_ticker_inquiries": "Pertanyaan Co-Broke menunggu pengesahan anda",
  "inventory_ticker_review": "Semak",
  "inventory_search_hint": "Cari unit anda mengikut bangunan, jalan atau ID...",
  "inventory_tab_co_broke_review": "Co-Broke Dalam Semakan",
  "inventory_tab_closed_sold": "Ditutup / Terjual",
  "inventory_tab_drafts": "Draf",
  "inventory_drafts_empty": "Tiada draf disimpan.",
```

- [ ] **Step 2: Read the current file**

```bash
cat "app/lib/features/listing/my_inventory_screen.dart"
```

- [ ] **Step 3: Replace the whole file with the header/ticker/tabs restyle**

This step's version renders each tab's contents via a `// TASK 8:` placeholder comment marker for the premium card (Task 8 replaces that marker with the real card widget) — this keeps this task's own diff reviewable independently of Task 8's card design.

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/r_star_badge.dart';
import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'listing_drafts_provider.dart';
import 'listing_providers.dart';
import 'listing_status_filter.dart';
import 'models/listing.dart';
import 'models/listing_draft.dart';

enum _InventoryTab { active, coBrokeReview, closedSold, drafts }

/// Restyled from the Stitch "My Inventory (Premium Co-Broking
/// Management)" mockup: a branded header (matching Dashboard/Marketplace/
/// Messages), a real live-stats ticker, 4 real tabs (Active/Co-Broke in
/// Review/Closed·Sold/Drafts -- the first 3 are a mutually-exclusive
/// partition via ListingStatusFilter.partition, Drafts is local-only),
/// and premium cards (added by a later task in the same plan -- see the
/// `// TASK 8:` marker below).
class MyInventoryScreen extends ConsumerStatefulWidget {
  const MyInventoryScreen({super.key});

  @override
  ConsumerState<MyInventoryScreen> createState() => _MyInventoryScreenState();
}

class _MyInventoryScreenState extends ConsumerState<MyInventoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _InventoryTab _tab = _InventoryTab.active;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Listing> _search(List<Listing> listings) {
    if (_query.trim().isEmpty) return listings;
    final q = _query.toLowerCase();
    return listings.where((l) => l.title.toLowerCase().contains(q) || l.area.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final drafts = ref.watch(listingDraftsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
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
            ),
            Expanded(
              child: negotiatorId == null
                  ? const Center(child: CircularProgressIndicator())
                  : Consumer(
                      builder: (context, ref, _) {
                        final listingsAsync = ref.watch(myListingsProvider(negotiatorId));
                        return listingsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                          data: (listings) {
                            final received = receivedAsync.maybeWhen(data: (r) => r, orElse: () => const []);
                            final partition = ListingStatusFilter.partition(listings, received);
                            final pendingOnMyListings = received.where((c) => c.request.status == 'pending').length;

                            final visible = switch (_tab) {
                              _InventoryTab.active => _search(partition.active),
                              _InventoryTab.coBrokeReview => _search(partition.coBrokeInReview),
                              _InventoryTab.closedSold => _search(partition.closedSold),
                              _InventoryTab.drafts => const <Listing>[],
                            };

                            return RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(myListingsProvider(negotiatorId));
                                ref.invalidate(receivedRequestsProvider);
                              },
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'inventory_title'.tr(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.0),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration:
                                                BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                                            child: Text(
                                              '${listings.length} ${'inventory_units_label'.tr()}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      InkWell(
                                        onTap: () => context.push('/post-listing'),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            border: Border.all(color: Colors.black, width: 2),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold), size: 14),
                                              const SizedBox(width: 4),
                                              Text(
                                                'inventory_post_property'.tr(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'inventory_subtitle'.tr(),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFE5E7EB)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '$pendingOnMyListings ',
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                TextSpan(text: 'inventory_ticker_inquiries'.tr()),
                                              ],
                                            ),
                                            style: Theme.of(context).textTheme.labelSmall,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => context.push('/my-requests'),
                                          child: Text(
                                            '${'inventory_ticker_review'.tr()} →',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      hintText: 'inventory_search_hint'.tr(),
                                      prefixIcon: const Icon(Icons.search),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                      ),
                                    ),
                                    onChanged: (value) => setState(() => _query = value),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 36,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: [
                                        _TabPill(
                                          label: '${'inventory_tab_active'.tr()} (${partition.active.length})',
                                          selected: _tab == _InventoryTab.active,
                                          onTap: () => setState(() => _tab = _InventoryTab.active),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label:
                                              '${'inventory_tab_co_broke_review'.tr()} (${partition.coBrokeInReview.length})',
                                          selected: _tab == _InventoryTab.coBrokeReview,
                                          onTap: () => setState(() => _tab = _InventoryTab.coBrokeReview),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label: '${'inventory_tab_closed_sold'.tr()} (${partition.closedSold.length})',
                                          selected: _tab == _InventoryTab.closedSold,
                                          onTap: () => setState(() => _tab = _InventoryTab.closedSold),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label: 'inventory_tab_drafts'.tr(),
                                          selected: _tab == _InventoryTab.drafts,
                                          onTap: () => setState(() => _tab = _InventoryTab.drafts),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_tab == _InventoryTab.drafts)
                                    if (drafts.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 60),
                                        child: Center(child: Text('inventory_drafts_empty'.tr())),
                                      )
                                    else
                                      for (final draft in drafts) ...[
                                        _DraftRow(draft: draft),
                                        const SizedBox(height: 10),
                                      ]
                                  else if (visible.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 60),
                                      child: Center(child: Text('inventory_empty'.tr())),
                                    )
                                  else
                                    // TASK 8: premium listing cards inserted here.
                                    for (final listing in visible) ...[
                                      Text(listing.title), // placeholder, replaced by Task 8
                                      const SizedBox(height: 10),
                                    ],
                                ],
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
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.black : const Color(0xFFE5E7EB)),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? AppColors.primary : const Color(0xFF4B5563),
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ),
    );
  }
}

class _DraftRow extends ConsumerWidget {
  const _DraftRow({required this.draft});

  final ListingDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.title.isEmpty ? '(untitled)' : draft.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  draft.price == null ? '' : 'RM ${draft.price}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIcons.trash(PhosphorIconsStyle.bold), size: 18),
            onPressed: () => ref.read(listingDraftsProvider.notifier).remove(draft.draftId),
          ),
          BrutalistButtonSmall(
            label: 'listing_save_changes'.tr(),
            onTap: () => GoRouter.of(context).push('/post-listing', extra: draft),
          ),
        ],
      ),
    );
  }
}
```

**Note on `_DraftRow`'s resume action**: the code above references a `BrutalistButtonSmall` helper and `GoRouter.of(context).push('/post-listing', extra: draft)` that do not exist yet — this is intentionally left for you to correct against the actual current `BrutalistButton` API (which does not take an `extra` route param; `go_router`'s `extra` mechanism requires the receiving `GoRoute` to read `state.extra`, which `/post-listing`'s current route builder does not do). Fix this before running any test: change the `/post-listing` `GoRoute` builder to `(context, state) => PostListingScreen(initialDraft: state.extra as ListingDraft?)`, and replace the `_DraftRow`'s trailing widget with a plain `TextButton`/`InkWell` (matching this file's own established small-button style elsewhere, e.g. the ticker's "Review →" `InkWell`) reading `'listing_edit_title'.tr()` or a new short "Resume" label — use your judgment for the exact copy, add an `l10n` key if you introduce new copy (e.g. `"inventory_resume_draft": "Resume"`), and keep the JSON parity rule.

- [ ] **Step 4: Fix the `/post-listing` route to accept a resumed draft**

In `app/lib/core/router/app_router.dart`, find:
```dart
      GoRoute(path: '/post-listing', builder: (context, state) => const PostListingScreen()),
```

Replace with:
```dart
      GoRoute(
        path: '/post-listing',
        builder: (context, state) => PostListingScreen(initialDraft: state.extra as ListingDraft?),
      ),
```

Add the import `import '../../features/listing/models/listing_draft.dart';` alongside this router file's other feature imports.

- [ ] **Step 5: Run `flutter analyze` and fix the placeholder issues Step 3 flagged**

```bash
cd "app" && flutter analyze
```

Expected: errors pointing at `BrutalistButtonSmall` (undefined) and the `Text(listing.title)` placeholder loop — fix both per the notes in Step 3 (replace `BrutalistButtonSmall` with a plain button widget, add the `inventory_resume_draft` l10n key if you introduce that copy) and leave the `// TASK 8:` placeholder loop exactly as `Text(listing.title)` for now (Task 8 replaces it) — the analyzer will NOT flag that loop as an error (it's valid, just visually incomplete), only the `_DraftRow` issue is a real compile error to fix in this task.

- [ ] **Step 6: Run the full test suite**

```bash
cd "app" && flutter test
```

Expected: all pass (the existing `my_inventory_screen_test.dart`, if any exists, may need provider overrides for `receivedRequestsProvider`/`myProfileProvider`/`unreadNotificationCountProvider`/`listingDraftsProvider` added — check `app/test/features/listing/` for an existing test file for this screen first; if none exists yet, this task does not need to create one, Task 10 does).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/listing/my_inventory_screen.dart app/lib/core/router/app_router.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: restyle My Inventory header/ticker/tabs, wire drafts resume route"
```

---

## Task 8: Premium listing card

**Files:**
- Modify: `app/lib/features/listing/my_inventory_screen.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `Listing` (Task 1's new fields), `receivedRequestsProvider`/`myMatchesProvider`/`agreementForRequestProvider` (existing), `ListingPhoto` (existing).
- Produces: `_InventoryCard` widget, used by Task 9 which adds the action row to it.

- [ ] **Step 1: Add new l10n keys**

In `app/assets/translations/en.json`:
```json
  "inventory_badge_co_broking_active": "Co-Broking Active",
  "inventory_badge_deal_review": "In Deal Review",
  "inventory_days_on_market": "Days on Market",
  "inventory_badge_title_verified": "Verified Title",
  "inventory_badge_exclusive_mandate": "Exclusive Mandate",
  "inventory_insight_inquiries": "Inquiries from Co-Brokers",
  "inventory_insight_buyer_match": "Buyer Match: Agent",
  "inventory_split_suffix": "Split",
```

In `app/assets/translations/ms.json`:
```json
  "inventory_badge_co_broking_active": "Co-Broking Aktif",
  "inventory_badge_deal_review": "Dalam Semakan Urusan",
  "inventory_days_on_market": "Hari di Pasaran",
  "inventory_badge_title_verified": "Hak Milik Disahkan",
  "inventory_badge_exclusive_mandate": "Mandat Eksklusif",
  "inventory_insight_inquiries": "Pertanyaan daripada Co-Broker",
  "inventory_insight_buyer_match": "Padanan Pembeli: Ejen",
  "inventory_split_suffix": "Split",
```

- [ ] **Step 2: Read the current file (post-Task-7)**

```bash
cat "app/lib/features/listing/my_inventory_screen.dart"
```

- [ ] **Step 3: Replace the `// TASK 8:` placeholder with the real card**

Add these imports at the top:
```dart
import '../listing/listing_formatting.dart';
import '../listing/listing_photo.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../collaboration/agreement_providers.dart' hide currentNegotiatorIdProvider;
```

Replace:
```dart
                                  else
                                    // TASK 8: premium listing cards inserted here.
                                    for (final listing in visible) ...[
                                      Text(listing.title), // placeholder, replaced by Task 8
                                      const SizedBox(height: 10),
                                    ],
```

with:
```dart
                                  else
                                    for (final listing in visible) ...[
                                      _InventoryCard(listing: listing, received: received),
                                      const SizedBox(height: 12),
                                    ],
```

Add the `_InventoryCard` widget at the bottom of the file (after `_DraftRow`):

```dart
class _InventoryCard extends ConsumerWidget {
  const _InventoryCard({required this.listing, required this.received});

  final Listing listing;
  final List<dynamic> received;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myPendingRequests =
        received.where((c) => c.match.listing.listingId == listing.listingId && c.request.status == 'pending').toList();
    final myAcceptedRequests =
        received.where((c) => c.match.listing.listingId == listing.listingId && c.request.status == 'accepted').toList();

    final daysOnMarket = DateTime.now().difference(listing.createdAt).inDays;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: listing.photoUrls.isNotEmpty
                      ? ListingPhoto(path: listing.photoUrls.first, fit: BoxFit.cover)
                      : Container(color: const Color(0xFFF3F4F1)),
                ),
              ),
              if (myAcceptedRequests.isNotEmpty)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final requestId = myAcceptedRequests.first.request.requestId as String;
                      final agreementAsync = ref.watch(agreementForRequestProvider(requestId));
                      final inDealReview = agreementAsync.valueOrNull?.status == 'pending';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: inDealReview ? Colors.amber.shade300 : AppColors.primary,
                          border: Border.all(color: Colors.black, width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          inDealReview ? 'inventory_badge_deal_review'.tr() : 'inventory_badge_co_broking_active'.tr(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$daysOnMarket ${'inventory_days_on_market'.tr()}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (listing.titleVerified || listing.exclusiveMandate)
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      listing.titleVerified
                          ? 'inventory_badge_title_verified'.tr()
                          : 'inventory_badge_exclusive_mandate'.tr(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      ListingFormatting.formatPrice(listing.price, listing.transactionType),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        listing.propertyType,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        listing.area,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      if (listing.bedrooms != null) ...[
                        Icon(PhosphorIcons.bed(PhosphorIconsStyle.bold), size: 15, color: const Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text('${listing.bedrooms}', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                      ],
                      if (listing.bathrooms != null) ...[
                        Icon(PhosphorIcons.bathtub(PhosphorIconsStyle.bold), size: 15, color: const Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text('${listing.bathrooms}', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
                if (myPendingRequests.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${myPendingRequests.length} ${'inventory_insight_inquiries'.tr()}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: const Color(0xFF065F46), fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (listing.commissionSplitPercent != null)
                          Text(
                            '${listing.commissionSplitPercent}% ${'inventory_split_suffix'.tr()}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: const Color(0xFF047857), fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ] else
                  Consumer(
                    builder: (context, ref, _) {
                      final matchesAsync = ref.watch(myMatchesProvider);
                      final topMatch = matchesAsync.maybeWhen(
                        data: (matches) {
                          final forThisListing = matches.where((m) => m.listing.listingId == listing.listingId).toList();
                          if (forThisListing.isEmpty) return null;
                          forThisListing.sort((a, b) => b.score.compareTo(a.score));
                          return forThisListing.first;
                        },
                        orElse: () => null,
                      );
                      if (topMatch == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  '${topMatch.score}%',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${'inventory_insight_buyer_match'.tr()} ${topMatch.requirementOwner.fullName}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                // TASK 9: action row (Edit/Bump/Share/more-menu) inserted here.
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

**Note**: `received` is typed `List<dynamic>` in `_InventoryCard`'s constructor above deliberately loose to avoid this task needing to import `CobrokeRequestCandidate` just to name the type — if `flutter analyze` reports a type error on `c.match.listing.listingId`/`c.request.status` (dynamic member access should actually work fine in Dart without static analysis errors, since `dynamic` suppresses type checking), leave it as `List<dynamic>`; if you prefer static typing, import `CobrokeRequestCandidate` from `../collaboration/models/cobroke_request_candidate.dart` and change the param type to `List<CobrokeRequestCandidate>` — either compiles, pick whichever the analyzer prefers with zero warnings.

- [ ] **Step 4: Run `flutter analyze`**

```bash
cd "app" && flutter analyze
```

Expected: clean (fix the `received` typing per the note above if anything is flagged).

- [ ] **Step 5: Run the full test suite**

```bash
cd "app" && flutter test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/listing/my_inventory_screen.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add premium listing card to My Inventory (photo, status badge, insight pill)"
```

---

## Task 9: Card action row — Edit / Bump / Share / more-menu

**Files:**
- Modify: `app/lib/features/listing/my_inventory_screen.dart`
- Modify: `app/pubspec.yaml`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `ListingRepository.bumpListing` (Task 3), `ListingRepository.updateListingStatus` (existing), `share_plus`'s `Share.share`.
- Produces: nothing new for later tasks — this is the last content task before test updates.

- [ ] **Step 1: Add the `share_plus` dependency**

```bash
cd "app" && flutter pub add share_plus
```

Expected output: a line confirming `share_plus` was added to `pubspec.yaml` at whatever the current latest stable version resolves to.

- [ ] **Step 2: Add new l10n keys**

In `app/assets/translations/en.json`:
```json
  "inventory_action_edit": "Edit",
  "inventory_action_bump": "Bump Listing",
  "inventory_action_bumped_confirmation": "Listing bumped to the top.",
  "inventory_action_share": "Share",
```

In `app/assets/translations/ms.json`:
```json
  "inventory_action_edit": "Sunting",
  "inventory_action_bump": "Naikkan Senarai",
  "inventory_action_bumped_confirmation": "Senarai dinaikkan ke atas.",
  "inventory_action_share": "Kongsi",
```

- [ ] **Step 3: Read the current file (post-Task-8)**

```bash
cat "app/lib/features/listing/my_inventory_screen.dart"
```

- [ ] **Step 4: Replace the `// TASK 9:` marker with the real action row**

Add this import at the top:
```dart
import 'package:share_plus/share_plus.dart';
```

Replace:
```dart
                // TASK 9: action row (Edit/Bump/Share/more-menu) inserted here.
```

with:
```dart
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                const SizedBox(height: 10),
                Consumer(
                  builder: (context, ref, _) {
                    return Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.push('/property/${listing.listingId}/edit'),
                            icon: Icon(PhosphorIcons.pencilSimple(PhosphorIconsStyle.bold), size: 16),
                            label: Text('inventory_action_edit'.tr()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                            onPressed: () async {
                              await ref.read(listingRepositoryProvider).bumpListing(listing.listingId);
                              ref.invalidate(myListingsProvider(listing.negotiatorId));
                              ref.invalidate(marketplaceListingsProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('inventory_action_bumped_confirmation'.tr())));
                              }
                            },
                            icon: Icon(PhosphorIcons.lightning(PhosphorIconsStyle.bold), size: 16),
                            label: Text('inventory_action_bump'.tr()),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Share.share(
                            '${listing.title} - ${ListingFormatting.formatPrice(listing.price, listing.transactionType)} - ${listing.area}, ${listing.state}',
                          ),
                          icon: Icon(PhosphorIcons.shareNetwork(PhosphorIconsStyle.bold), size: 18),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(PhosphorIcons.dotsThreeVertical(PhosphorIconsStyle.bold)),
                          onSelected: (status) async {
                            final repository = ref.read(listingRepositoryProvider);
                            try {
                              await repository.updateListingStatus(listingId: listing.listingId, status: status);
                              ref.invalidate(listingDetailProvider(listing.listingId));
                              ref.invalidate(marketplaceListingsProvider);
                              ref.invalidate(myListingsProvider(listing.negotiatorId));
                              ref.invalidate(activeListingCountProvider(listing.negotiatorId));
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('listing_error_generic'.tr())));
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            if (listing.status != 'sold')
                              PopupMenuItem(value: 'sold', child: Text('property_mark_sold'.tr())),
                            if (listing.status != 'withdrawn')
                              PopupMenuItem(value: 'withdrawn', child: Text('property_withdraw'.tr())),
                            if (listing.status != 'active')
                              PopupMenuItem(value: 'active', child: Text('property_reactivate'.tr())),
                          ],
                        ),
                      ],
                    );
                  },
                ),
```

**Note on the Reactivate/atCap gating**: `property_detail_screen.dart`'s own version disables Reactivate when the negotiator is at their free-tier cap. Replicating that exact check here requires watching `subscriptionStatusProvider`/`activeListingCountProvider(listing.negotiatorId)` inside this same `Consumer` — add:
```dart
final tierAsync = ref.watch(subscriptionStatusProvider);
final countAsync = ref.watch(activeListingCountProvider(listing.negotiatorId));
final atCap = tierAsync.valueOrNull?.tier == 'free' && (countAsync.valueOrNull ?? 0) >= 3;
```
inside the `Consumer`'s `builder` (before the `return Row(...)`), and change the Reactivate `PopupMenuItem` to:
```dart
if (listing.status != 'active')
  PopupMenuItem(
    value: 'active',
    enabled: !atCap,
    child: Text(atCap ? '${'property_reactivate'.tr()} (${'listing_cap_reached_message'.tr()})' : 'property_reactivate'.tr()),
  ),
```
Add the necessary imports (`subscription_providers.dart` hiding `currentNegotiatorIdProvider`, matching every other file in this feature that already imports it the same way).

- [ ] **Step 5: Run `flutter analyze`**

```bash
cd "app" && flutter analyze
```

Expected: clean.

- [ ] **Step 6: Run the full test suite**

```bash
cd "app" && flutter test
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/listing/my_inventory_screen.dart app/pubspec.yaml app/pubspec.lock app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add Edit/Bump/Share/more-menu action row to My Inventory cards"
```

---

## Task 10: Widget tests for the restyled `MyInventoryScreen`

**Files:**
- Modify or create: `app/test/features/listing/my_inventory_screen_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-9.
- Produces: nothing for later tasks — this is the final task.

- [ ] **Step 1: Check whether the test file already exists**

```bash
ls app/test/features/listing/my_inventory_screen_test.dart 2>&1
```

If it exists, read its current content first and extend it (adding the new provider overrides this restyle needs) rather than replacing it wholesale, per this project's own established per-task convention. If it doesn't exist, create it fresh per Step 2 below.

- [ ] **Step 2: Write/extend the test file**

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
import 'package:renly/features/collaboration/cobroke_request_providers.dart';
import 'package:renly/features/listing/listing_drafts_provider.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/my_inventory_screen.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';

final _activeListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'Active Listing',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 500000,
  photoUrls: const [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

Future<void> _pumpScreen(WidgetTester tester, {required List<Override> overrides}) async {
  // The default 800x600 test surface is too short to mount every card in
  // this restyled premium feed (~350dp+ each) -- ListView virtualizes via
  // the sliver machinery regardless of the plain-list vs .builder
  // delegate, so an off-screen card's Elements genuinely never mount and
  // find.byType/find.text can't see them (confirmed the hard way during
  // this session's Marketplace restyle). Widen the surface proactively.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
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

  testWidgets('shows real unit count and the active listing on the Active tab', (tester) async {
    await _pumpScreen(
      tester,
      overrides: [
        currentNegotiatorIdProvider.overrideWith((ref) => 'n-1'),
        myListingsProvider.overrideWith((ref, negotiatorId) async => [_activeListing]),
        receivedRequestsProvider.overrideWith((ref) async => []),
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              verificationStatus: 'approved',
            )),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
      ],
    );

    expect(find.textContaining('1 Units'), findsOneWidget);
    expect(find.textContaining('Active Listing'), findsOneWidget);
  });

  testWidgets('shows empty Drafts state when no drafts are saved', (tester) async {
    await _pumpScreen(
      tester,
      overrides: [
        currentNegotiatorIdProvider.overrideWith((ref) => 'n-1'),
        myListingsProvider.overrideWith((ref, negotiatorId) async => []),
        receivedRequestsProvider.overrideWith((ref) async => []),
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              verificationStatus: 'approved',
            )),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
        listingDraftsProvider.overrideWith((ref) => _EmptyDraftsNotifier()),
      ],
    );

    await tester.tap(find.text('inventory_tab_drafts'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('inventory_drafts_empty'.tr()), findsOneWidget);
  });
}

class _EmptyDraftsNotifier extends ListingDraftsNotifier {}
```

**Note**: `_EmptyDraftsNotifier extends ListingDraftsNotifier` relies on the real notifier's constructor already initializing `state` to `const []` and kicking off an async `_load()` that (with `SharedPreferences.setMockInitialValues({})` set in `setUpAll`) resolves to an empty list anyway — if this doesn't produce a clean empty state in practice (e.g. because the async `_load()` races the test's own `pumpAndSettle`), override with a simpler inline approach instead: `listingDraftsProvider.overrideWith((ref) => ListingDraftsNotifier())` directly (no subclass needed, since `SharedPreferences.setMockInitialValues({})` already guarantees an empty stored list, so the real notifier naturally loads to empty) — verify which approach the analyzer/test run actually needs and use that one.

- [ ] **Step 3: Run the test file**

```bash
cd "app" && flutter test test/features/listing/my_inventory_screen_test.dart
```

Expected: PASS, 2/2 (or however many tests result after resolving the note above).

- [ ] **Step 4: Run `flutter analyze` and the full suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 5: Commit**

```bash
git add app/test/features/listing/my_inventory_screen_test.dart
git commit -m "test: add widget tests for restyled My Inventory screen"
```

---

## Manual verification (after all tasks, and after migration 0020 is applied)

1. Confirm migration `0020` was applied (ask the user, or run `supabase db query --linked` to check the 4 new columns independently).
2. Post a real listing, confirm it appears under Active with 0 pending inquiries, no self-attestation badges (none were set).
3. Post a listing with both self-attestation switches on and a commission split value — confirm both badges + the split figure render on the card.
4. From a second test account, post a matching requirement and send a co-broke request on the first account's listing — confirm the listing moves from Active to "Co-Broke in Review" and the ticker's count increments.
5. Tap "Bump Listing" — confirm a snackbar confirms it, and the listing now sorts above other listings in both My Inventory and the Marketplace feed, while its own "Days on Market" figure is unchanged.
6. Tap "Edit" — confirm the form pre-fills with the listing's real current values, change the price, save, confirm the updated price shows on return to My Inventory.
7. Tap "Share" — confirm the OS share sheet opens with the listing's real title/price/location as the shared text.
8. Use the "⋮" menu — confirm Mark Sold/Withdraw/Reactivate options match the listing's current status (e.g. an active listing offers Mark Sold + Withdraw but not Reactivate), and confirm the listing moves to the Closed/Sold tab after marking sold.
9. From Post Listing, fill some fields and tap "Save as Draft" — confirm it appears under the Drafts tab, tap to resume, confirm the form is pre-filled, then either discard (trash icon, confirm it disappears from Drafts) or complete and submit it (confirm it becomes a real listing AND disappears from Drafts).
