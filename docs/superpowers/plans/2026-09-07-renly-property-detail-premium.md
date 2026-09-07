# Property Detail Ultra-Premium Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle `PropertyDetailScreen` to match the "Renly - Property Detail (Ultra-Premium Co-Broking)" Stitch mockup, backing every visual element with real data (new Listing fields, a real per-viewer match score, real rating reuse) or an honest reframe, and dropping anything requiring a subsystem too large for this pass (viewing booking, in-app maps).

**Architecture:** `PropertyDetailScreen` keeps its single `ConsumerStatefulWidget` shape but its `build()` is restructured into 6 extracted private card widgets, one per mockup section, matching this project's own per-section-widget extraction convention. 8 new nullable/defaulted `Listing` fields (one migration, full grant restatement) back the new property attributes and self-attested toggles. A new pure `LiveMatchPreview.bestScoreForListing` function (same zero-DB-write shape as the rest of that file) backs the real "N% MATCH" hero badge. The "Request Co-Broke" CTA reuses the already-real `sendCobrokeRequest` action against a real stored `Match` row (found by filtering the listing's own already-fetched `matchesForListingProvider` to the viewer's own requirement), not a new subsystem.

**Tech Stack:** Flutter + Riverpod + Supabase (Postgres/RLS), `share_plus` (already a dependency), `url_launcher` (already a dependency, unused until now).

## Global Constraints

- Every new field is nullable (or boolean defaulting `false`) — absent means the owner didn't set it, never a fabricated/estimated fallback. Every UI element reading a new field must hide itself (or its own row/cell) when the value is null/false, never show a placeholder.
- Migration grants must be restated in FULL (not just new columns) in the same migration as the column adds — this project has hit this exact bug twice already this session (migrations 0010, 0020).
- PhosphorIcons only, never `Icons.*`, for any newly-added icon (existing `Icons.close`/`Icons.add_a_photo_outlined` call sites elsewhere in this codebase are pre-existing and out of scope).
- Self-attestation toggles (`keysOnHand`, `protectedCoBrokeReg`) reuse the existing `listing_self_attestation_notice` l10n key verbatim (not duplicated) and follow the exact `SwitchListTile(title: ..., subtitle: ...)` shape already established for `titleVerified`/`exclusiveMandate`.
- No new Supabase-boundary repository method gets a unit test (project convention — manually verified later). Pure logic (the new match-score function) gets real unit tests.
- EN/MS l10n key parity maintained at every step — add both languages in the same step, never one without the other.
- Migration files are never applied by any task — tell the user to apply manually via the Supabase SQL Editor.

---

### Task 1: `Listing` model gains 8 new fields

**Files:**
- Modify: `app/lib/features/listing/models/listing.dart`
- Test: `app/test/features/listing/models/listing_test.dart` (create if it doesn't exist yet — check first)

**Interfaces:**
- Produces: `Listing.maintenanceFeeMyr` (`double?`), `Listing.tenure` (`String?`), `Listing.parkingBays` (`int?`), `Listing.floorLevel` (`int?`), `Listing.furnishingStatus` (`String?`), `Listing.keysOnHand` (`bool`, default `false`), `Listing.protectedCoBrokeReg` (`bool`, default `false`), `Listing.totalAgencyCommissionPercent` (`double?`) — all consumed by every later task.

- [ ] **Step 1: Check for an existing model test file**

Run: `ls app/test/features/listing/models/ 2>/dev/null`

If `listing_test.dart` doesn't exist, Step 2 creates it. If it exists, add the new test case to it instead of creating a new file.

- [ ] **Step 2: Write the failing test**

Create/edit `app/test/features/listing/models/listing_test.dart`:

```dart
// app/test/features/listing/models/listing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing.dart';

void main() {
  group('Listing.fromJson', () {
    Map<String, dynamic> _baseJson() => {
          'listing_id': 'l-1',
          'negotiator_id': 'n-1',
          'title': 't',
          'description': 'd',
          'property_type': 'apartment',
          'transaction_type': 'sale',
          'state': 'Selangor',
          'area': 'Petaling Jaya',
          'price': 500000,
          'photo_urls': <String>[],
          'status': 'active',
          'created_at': '2024-01-01T00:00:00.000Z',
        };

    test('populated new fields round-trip with correct types', () {
      final json = _baseJson()
        ..addAll({
          'maintenance_fee_myr': 580,
          'tenure': 'freehold',
          'parking_bays': 2,
          'floor_level': 38,
          'furnishing_status': 'furnished',
          'keys_on_hand': true,
          'protected_co_broke_reg': true,
          'total_agency_commission_percent': 3,
        });

      final listing = Listing.fromJson(json);

      expect(listing.maintenanceFeeMyr, 580.0);
      expect(listing.maintenanceFeeMyr, isA<double>());
      expect(listing.tenure, 'freehold');
      expect(listing.parkingBays, 2);
      expect(listing.floorLevel, 38);
      expect(listing.furnishingStatus, 'furnished');
      expect(listing.keysOnHand, true);
      expect(listing.protectedCoBrokeReg, true);
      expect(listing.totalAgencyCommissionPercent, 3.0);
      expect(listing.totalAgencyCommissionPercent, isA<double>());
    });

    test('omitted new fields default to null/false, never a fabricated fallback', () {
      final listing = Listing.fromJson(_baseJson());

      expect(listing.maintenanceFeeMyr, isNull);
      expect(listing.tenure, isNull);
      expect(listing.parkingBays, isNull);
      expect(listing.floorLevel, isNull);
      expect(listing.furnishingStatus, isNull);
      expect(listing.keysOnHand, false);
      expect(listing.protectedCoBrokeReg, false);
      expect(listing.totalAgencyCommissionPercent, isNull);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/features/listing/models/listing_test.dart`
Expected: FAIL — `maintenanceFeeMyr` (and the other 7 new members) undefined on `Listing`.

- [ ] **Step 4: Add the 8 new fields to the model**

In `app/lib/features/listing/models/listing.dart`, add after the existing `exclusiveMandate` field declaration:

```dart
  /// Monthly maintenance/service charge in MYR. Nullable -- absent if the
  /// owner didn't set one, never estimated.
  final double? maintenanceFeeMyr;

  /// 'freehold' or 'leasehold'. Nullable -- absent if unset.
  final String? tenure;

  /// Number of covered parking bays. Nullable -- absent if unset.
  final int? parkingBays;

  /// Floor number the unit is on. Nullable -- absent if unset. Deliberately
  /// a plain int, not validated against the property's actual floor count
  /// (which this app has no record of).
  final int? floorLevel;

  /// 'furnished', 'partially_furnished', or 'unfurnished'. Nullable --
  /// absent if unset.
  final String? furnishingStatus;

  /// Self-attested by the listing's own owner -- NOT third-party verified.
  /// Same framing as [titleVerified]/[exclusiveMandate].
  final bool keysOnHand;

  /// Self-attested by the listing's own owner -- NOT third-party verified.
  /// Same framing as [keysOnHand].
  final bool protectedCoBrokeReg;

  /// The deal's total agency commission rate, standalone from
  /// [commissionSplitPercent] (which is the owner's own advertised split
  /// OF this total to a co-broker). Nullable -- absent if unset.
  final double? totalAgencyCommissionPercent;
```

Update the constructor:

```dart
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
    this.builtUpSqft,
    required this.photoUrls,
    required this.status,
    required this.createdAt,
    this.bumpedAt,
    this.commissionSplitPercent,
    this.titleVerified = false,
    this.exclusiveMandate = false,
    this.maintenanceFeeMyr,
    this.tenure,
    this.parkingBays,
    this.floorLevel,
    this.furnishingStatus,
    this.keysOnHand = false,
    this.protectedCoBrokeReg = false,
    this.totalAgencyCommissionPercent,
  });
```

Update `fromJson`:

```dart
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
      builtUpSqft: json['built_up_sqft'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      bumpedAt: json['bumped_at'] == null ? null : DateTime.parse(json['bumped_at'] as String),
      commissionSplitPercent: (json['commission_split_percent'] as num?)?.toDouble(),
      titleVerified: json['title_verified'] as bool? ?? false,
      exclusiveMandate: json['exclusive_mandate'] as bool? ?? false,
      maintenanceFeeMyr: (json['maintenance_fee_myr'] as num?)?.toDouble(),
      tenure: json['tenure'] as String?,
      parkingBays: json['parking_bays'] as int?,
      floorLevel: json['floor_level'] as int?,
      furnishingStatus: json['furnishing_status'] as String?,
      keysOnHand: json['keys_on_hand'] as bool? ?? false,
      protectedCoBrokeReg: json['protected_co_broke_reg'] as bool? ?? false,
      totalAgencyCommissionPercent: (json['total_agency_commission_percent'] as num?)?.toDouble(),
    );
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/features/listing/models/listing_test.dart`
Expected: PASS (2/2).

- [ ] **Step 6: Confirm zero blast radius on existing fixtures**

Run: `cd app && flutter test`
Expected: same pass count as before this task (286/286 as of the last full run this session) — `Listing` is not `const`-constructible (has `DateTime createdAt`), so every existing `Listing(...)` fixture across the test suite compiles unchanged.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/listing/models/listing.dart app/test/features/listing/models/listing_test.dart
git commit -m "feat: add 8 property-attribute fields to Listing model"
```

---

### Task 2: Migration `0025_listing_property_details.sql`

**Files:**
- Create: `supabase/migrations/0025_listing_property_details.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: the 8 new `listing` columns Task 3 threads through the repository. This file is never applied by any task — tell the user to run it manually after this task's commit.

- [ ] **Step 1: Create the migration file**

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
-- this; this migration applies that lesson from the start. The current
-- authoritative grant lists were confirmed by reading 0023_listing_sqft.sql
-- (the most recent grant-restating migration on this table) directly --
-- INSERT does NOT include photo_urls/status (those are UPDATE-only,
-- set via separate calls), UPDATE includes bumped_at/photo_urls/status.
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
  price, bedrooms, bathrooms, built_up_sqft, photo_urls, status, bumped_at,
  commission_split_percent, title_verified, exclusive_mandate,
  maintenance_fee_myr, tenure, parking_bays, floor_level, furnishing_status,
  keys_on_hand, protected_co_broke_reg, total_agency_commission_percent
) on listing to authenticated;
```

- [ ] **Step 2: Commit (file-creation only, never applied by this task)**

```bash
git add supabase/migrations/0025_listing_property_details.sql
git commit -m "feat: add 0025 migration for new listing property-attribute fields"
```

Tell the user: "Migration `0025_listing_property_details.sql` created but NOT applied. Paste its contents into the Supabase SQL Editor and run it before the new fields will persist live."

---

### Task 3: Extend `get_negotiator_public_info` RPC + `ListingOwner` model with verification status

**Files:**
- Create: `supabase/migrations/0026_negotiator_public_info_verification_status.sql`
- Modify: `app/lib/features/listing/models/listing_owner.dart`
- Test: `app/test/features/listing/models/listing_owner_test.dart` (create if it doesn't exist)

**Interfaces:**
- Consumes: nothing new.
- Produces: `ListingOwner.verificationStatus` (`String?`), consumed by Task 9's Agent card for the real verified-checkmark.

**Context:** The design doc's Agent card reuses "the existing real `verificationStatus == 'approved'` check", but `ListingOwner` (the model `PropertyDetailScreen` actually reads) has no such field today — only `fullName`/`renNumber`/`agencyName`. The RPC backing it, `get_negotiator_public_info` (created in `0004_listing_hardening.sql`, renamed in `0015`, extended with `agency_name` in `0019`), needs the same drop-and-recreate treatment `0019` already used once (Postgres doesn't allow `CREATE OR REPLACE FUNCTION` to change a `RETURNS TABLE` shape).

- [ ] **Step 1: Create the migration file**

```sql
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
```

- [ ] **Step 2: Write the failing test**

Run: `ls app/test/features/listing/models/` to check whether `listing_owner_test.dart` already exists (Task 1 created the `models/` test directory for `listing_test.dart`, this is a sibling file).

Create `app/test/features/listing/models/listing_owner_test.dart`:

```dart
// app/test/features/listing/models/listing_owner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing_owner.dart';

void main() {
  group('ListingOwner.fromJson', () {
    test('parses verification_status when present', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
        'agency_name': 'ESP Global',
        'verification_status': 'approved',
      });

      expect(owner.verificationStatus, 'approved');
    });

    test('verification_status is null when absent, never a fabricated fallback', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
      });

      expect(owner.verificationStatus, isNull);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/features/listing/models/listing_owner_test.dart`
Expected: FAIL — `verificationStatus` undefined on `ListingOwner`.

- [ ] **Step 4: Add the field to `ListingOwner`**

Replace the full contents of `app/lib/features/listing/models/listing_owner.dart`:

```dart
/// The listing's negotiator, scoped to what PropertyDetailScreen displays
/// (name + REN number) -- deliberately not the full `Negotiator` model from
/// the auth feature, to keep this feature's Supabase reads self-contained
/// rather than reaching into another feature's model. `agencyName` added
/// for the Main Dashboard's Co-Broking Radar card (shows the matched
/// agent's agency as a trust signal) -- nullable because the RPC's LEFT
/// JOIN on `agency` returns null for a negotiator with no `agency_id` set.
/// `verificationStatus` added for the Property Detail Ultra-Premium
/// Restyle's real verified-checkmark -- nullable for the same reason as
/// every other optional field here (absent means unknown, never assumed
/// approved).
class ListingOwner {
  final String fullName;
  final String renNumber;
  final String? agencyName;
  final String? verificationStatus;

  const ListingOwner({
    required this.fullName,
    required this.renNumber,
    this.agencyName,
    this.verificationStatus,
  });

  factory ListingOwner.fromJson(Map<String, dynamic> json) {
    return ListingOwner(
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String? ?? '',
      agencyName: json['agency_name'] as String?,
      verificationStatus: json['verification_status'] as String?,
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/features/listing/models/listing_owner_test.dart`
Expected: PASS (2/2).

- [ ] **Step 6: Confirm zero blast radius**

Run: `cd app && flutter test`
Expected: same pass count as after Task 1 plus 2 — `ListingOwner` stays `const`-constructible and the new field is optional, so every existing `const ListingOwner(...)` fixture (e.g. `property_detail_screen_test.dart`'s `_fixtureOwner`) compiles unchanged.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0026_negotiator_public_info_verification_status.sql app/lib/features/listing/models/listing_owner.dart app/test/features/listing/models/listing_owner_test.dart
git commit -m "feat: add verification_status to get_negotiator_public_info RPC and ListingOwner"
```

Tell the user: "Migration `0026_negotiator_public_info_verification_status.sql` created but NOT applied. Paste its contents into the Supabase SQL Editor and run it AFTER 0025."

---

### Task 4: `ListingRepository` — thread the 8 new fields through create/update

**Files:**
- Modify: `app/lib/features/listing/listing_repository.dart`

**Interfaces:**
- Consumes: `Listing`'s 8 new fields (Task 1).
- Produces: `createListing(...)` and `updateListingDetails(...)` each gain 8 new optional params (`maintenanceFeeMyr`, `tenure`, `parkingBays`, `floorLevel`, `furnishingStatus`, `keysOnHand = false`, `protectedCoBrokeReg = false`, `totalAgencyCommissionPercent`), consumed by Task 5's Post Listing form additions.

**Context:** This is a Supabase-boundary method — no unit test, per this project's own convention (manually verified later, once the migration is live).

- [ ] **Step 1: Update `createListing`**

In `app/lib/features/listing/listing_repository.dart`, replace the `createListing` method:

```dart
  /// Creates the listing row WITHOUT photos (photo_urls defaults to '{}').
  /// Photos are uploaded after this returns, using the new listing_id in
  /// their Storage path, then attached via updateListingPhotos.
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
    int? builtUpSqft,
    double? commissionSplitPercent,
    bool titleVerified = false,
    bool exclusiveMandate = false,
    double? maintenanceFeeMyr,
    String? tenure,
    int? parkingBays,
    int? floorLevel,
    String? furnishingStatus,
    bool keysOnHand = false,
    bool protectedCoBrokeReg = false,
    double? totalAgencyCommissionPercent,
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
          'built_up_sqft': builtUpSqft,
          'commission_split_percent': commissionSplitPercent,
          'title_verified': titleVerified,
          'exclusive_mandate': exclusiveMandate,
          'maintenance_fee_myr': maintenanceFeeMyr,
          'tenure': tenure,
          'parking_bays': parkingBays,
          'floor_level': floorLevel,
          'furnishing_status': furnishingStatus,
          'keys_on_hand': keysOnHand,
          'protected_co_broke_reg': protectedCoBrokeReg,
          'total_agency_commission_percent': totalAgencyCommissionPercent,
        })
        .select()
        .single();
    return Listing.fromJson(row);
  }
```

- [ ] **Step 2: Update `updateListingDetails`**

Replace the `updateListingDetails` method:

```dart
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
    int? builtUpSqft,
    double? commissionSplitPercent,
    required bool titleVerified,
    required bool exclusiveMandate,
    double? maintenanceFeeMyr,
    String? tenure,
    int? parkingBays,
    int? floorLevel,
    String? furnishingStatus,
    bool keysOnHand = false,
    bool protectedCoBrokeReg = false,
    double? totalAgencyCommissionPercent,
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
      'built_up_sqft': builtUpSqft,
      'commission_split_percent': commissionSplitPercent,
      'title_verified': titleVerified,
      'exclusive_mandate': exclusiveMandate,
      'maintenance_fee_myr': maintenanceFeeMyr,
      'tenure': tenure,
      'parking_bays': parkingBays,
      'floor_level': floorLevel,
      'furnishing_status': furnishingStatus,
      'keys_on_hand': keysOnHand,
      'protected_co_broke_reg': protectedCoBrokeReg,
      'total_agency_commission_percent': totalAgencyCommissionPercent,
    }).eq('listing_id', listingId);
  }
```

- [ ] **Step 3: Run the full suite (no new tests for this Supabase-boundary task)**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze` clean, same pass count as after Task 3.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/listing/listing_repository.dart
git commit -m "feat: thread 8 new property-attribute params through ListingRepository"
```

---

### Task 5: `LiveMatchPreview.bestScoreForListing` — real per-viewer match score

**Files:**
- Modify: `app/lib/features/matching/live_match_preview.dart`
- Test: `app/test/features/matching/live_match_preview_test.dart`

**Interfaces:**
- Consumes: `MatchingEngine.score(Listing, Requirement)` and `MatchingEngine.qualifyingThreshold` (both already exist, unchanged).
- Produces: `LiveMatchPreview.bestScoreForListing(Listing listing, List<Requirement> viewerRequirements) -> int?` — returns the highest qualifying score, or `null` if `viewerRequirements` is empty or none qualify. Consumed by Task 8's hero-badge widget.

- [ ] **Step 1: Write the failing test**

Add to `app/test/features/matching/live_match_preview_test.dart` (inside the existing `void main()`, as a new top-level `group`, reusing the file's own existing `_listing` helper — read the file fresh first to confirm its exact current fixture-helper signatures before pasting, since this session has touched it before):

```dart
  group('LiveMatchPreview.bestScoreForListing', () {
    final matchingListing = _listing('l-1', title: 'The Vertex Residency');

    test('returns the highest qualifying score across multiple own requirements', () {
      const lowerScoring = Requirement(
        requirementId: 'r-1',
        negotiatorId: 'n-viewer',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Shah Alam',
        budgetMin: 300000,
        budgetMax: 500000,
        photoUrls: [],
        status: 'open',
      );
      const higherScoring = Requirement(
        requirementId: 'r-2',
        negotiatorId: 'n-viewer',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        photoUrls: [],
        status: 'open',
      );

      final score = LiveMatchPreview.bestScoreForListing(matchingListing, [lowerScoring, higherScoring]);

      expect(score, 100);
    });

    test('returns null when the viewer has no open requirements', () {
      final score = LiveMatchPreview.bestScoreForListing(matchingListing, []);

      expect(score, isNull);
    });

    test('returns null when no requirement clears the qualifying threshold', () {
      const belowThreshold = Requirement(
        requirementId: 'r-3',
        negotiatorId: 'n-viewer',
        propertyType: 'house',
        transactionType: 'rent',
        state: 'Johor',
        area: 'Shah Alam',
        budgetMin: 300000,
        budgetMax: 500000,
        photoUrls: [],
        status: 'open',
      );

      final score = LiveMatchPreview.bestScoreForListing(matchingListing, [belowThreshold]);

      expect(score, isNull);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/matching/live_match_preview_test.dart`
Expected: FAIL — `bestScoreForListing` undefined.

- [ ] **Step 3: Implement**

In `app/lib/features/matching/live_match_preview.dart`, add a new static method to the `LiveMatchPreview` class (alongside `forRequirement`/`forListing`):

```dart
  /// The real per-viewer match score for the Property Detail screen's
  /// hero "N% MATCH" badge -- the highest MatchingEngine.score() between
  /// [listing] and any of [viewerRequirements] (the CURRENT VIEWER's own
  /// open requirements, not the listing owner's), or null if none clear
  /// qualifyingThreshold (including the trivial empty-list case). Zero DB
  /// writes, same reasoning as forRequirement/forListing -- this is a
  /// pure read-time computation, not a stored Match row.
  static int? bestScoreForListing(Listing listing, List<Requirement> viewerRequirements) {
    int? best;
    for (final requirement in viewerRequirements) {
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      if (best == null || score > best) best = score;
    }
    return best;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/features/matching/live_match_preview_test.dart`
Expected: PASS (all cases, including the 3 new ones).

- [ ] **Step 5: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: clean, same pass count as after Task 4 plus 3.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/matching/live_match_preview.dart app/test/features/matching/live_match_preview_test.dart
git commit -m "feat: add LiveMatchPreview.bestScoreForListing for the real per-viewer match badge"
```

---

### Task 6: `PostListingFormBody` — new property-attribute fields

**Files:**
- Modify: `app/lib/features/listing/post_listing_screen.dart`
- Modify: `app/lib/features/listing/broadcast_badge.dart` (extend `SpecStatField` with an optional dropdown mode)
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`
- Test: `app/test/features/listing/post_listing_screen_test.dart`

**Interfaces:**
- Consumes: `Listing`'s 8 new fields (Task 1), `ListingRepository.createListing`/`updateListingDetails`'s 8 new params (Task 4).
- Produces: nothing new consumed by later tasks — Task 7-9 restyle `PropertyDetailScreen`, a read-only consumer of whatever these form fields write.

**Context:** `SpecStatField` (in `broadcast_badge.dart`) is a shared widget already used by 3 existing stat cells here (Beds/Baths/Sqft) and by `PostRequirementFormBody`. It must NOT change behavior for existing callers — add an optional `dropdownItems`/`dropdownValue`/`onDropdownChanged` trio that, when null (the default), falls through to today's `TextFormField` exactly as before.

- [ ] **Step 1: Extend `SpecStatField` with an optional dropdown mode**

In `app/lib/features/listing/broadcast_badge.dart`, replace the `SpecStatField` class:

```dart
/// A single editable spec field styled as a bordered "stat card" (icon on
/// top, the real value centered, a short unit label underneath) -- shared
/// by both PostListingFormBody's and PostRequirementFormBody's
/// bedrooms/bathrooms/built-up rows. Stays a real, editable TextFormField
/// by default; passing [dropdownItems] switches it to a compact dropdown
/// instead (used for Furnishing Status, the one stat cell that's an enum
/// rather than a free-typed number) -- every other existing caller leaves
/// [dropdownItems] null and sees no behavior change.
class SpecStatField extends StatelessWidget {
  const SpecStatField({
    super.key,
    required this.icon,
    required this.controller,
    required this.label,
    this.fieldKey,
    this.dropdownItems,
    this.dropdownValue,
    this.onDropdownChanged,
  });

  final IconData icon;
  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final List<DropdownMenuItem<String>>? dropdownItems;
  final String? dropdownValue;
  final ValueChanged<String?>? onDropdownChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(height: 4),
          if (dropdownItems != null)
            DropdownButton<String>(
              key: fieldKey,
              value: dropdownValue,
              items: dropdownItems,
              onChanged: onDropdownChanged,
              isDense: true,
              underline: const SizedBox.shrink(),
              hint: Text('-', style: Theme.of(context).textTheme.titleMedium),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
            )
          else
            TextFormField(
              key: fieldKey,
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '-',
              ),
            ),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add l10n keys**

In `app/assets/translations/en.json`, add after `"listing_key_specs_label": "Property Key Specs",`:

```json
  "listing_field_maintenance_fee": "Maintenance Fee (RM/month)",
  "listing_field_tenure": "Tenure",
  "listing_tenure_freehold": "Freehold",
  "listing_tenure_leasehold": "Leasehold",
  "listing_stat_parking": "Parking",
  "listing_stat_floor": "Floor",
  "listing_stat_furnishing": "Furnishing",
  "listing_furnishing_furnished": "Furnished",
  "listing_furnishing_partially_furnished": "Partial",
  "listing_furnishing_unfurnished": "Unfurnished",
  "listing_field_total_commission": "Total Agency Commission (%)",
  "listing_field_keys_on_hand": "Keys on Hand",
  "listing_keys_on_hand_caption": "Agent has physical access to the unit",
  "listing_field_protected_co_broke_reg": "Protected Co-Broke Registration",
  "listing_protected_co_broke_reg_caption": "Owner confirms this listing's co-broke registration is exclusive to Renly negotiators",
```

In `app/assets/translations/ms.json`, add the same keys at the same position:

```json
  "listing_field_maintenance_fee": "Yuran Penyelenggaraan (RM/bulan)",
  "listing_field_tenure": "Pegangan",
  "listing_tenure_freehold": "Hak Milik Bebas",
  "listing_tenure_leasehold": "Pajakan",
  "listing_stat_parking": "Parking",
  "listing_stat_floor": "Tingkat",
  "listing_stat_furnishing": "Perabot",
  "listing_furnishing_furnished": "Berperabot",
  "listing_furnishing_partially_furnished": "Sebahagian",
  "listing_furnishing_unfurnished": "Tanpa Perabot",
  "listing_field_total_commission": "Jumlah Komisen Agensi (%)",
  "listing_field_keys_on_hand": "Kunci Di Tangan",
  "listing_keys_on_hand_caption": "Ejen ada akses fizikal kepada unit",
  "listing_field_protected_co_broke_reg": "Pendaftaran Co-Broke Dilindungi",
  "listing_protected_co_broke_reg_caption": "Pemilik sahkan pendaftaran co-broke senarai ini eksklusif kepada negotiator Renly",
```

Run: `cd app && python3 -c "
import json
en=json.load(open('assets/translations/en.json'))
ms=json.load(open('assets/translations/ms.json'))
assert set(en) == set(ms), (set(en)-set(ms), set(ms)-set(en))
print('parity ok', len(en))
"`
Expected: `parity ok <N>` with no assertion error.

- [ ] **Step 3: Add the new form state fields**

In `app/lib/features/listing/post_listing_screen.dart`, add new controllers/state alongside the existing ones (after `final _commissionSplitController = TextEditingController();` and its `_splitPreset`/`_presetForSplitValue` block):

```dart
  final _maintenanceFeeController = TextEditingController();
  final _parkingBaysController = TextEditingController();
  final _floorLevelController = TextEditingController();
  final _totalCommissionController = TextEditingController();
  String? _tenure;
  String? _furnishingStatus;
  bool _keysOnHand = false;
  bool _protectedCoBrokeReg = false;
```

- [ ] **Step 4: Thread the new fields through draft prefill, listing prefill, dispose, and submit**

In `initState`'s draft-prefill branch, add after the existing `_exclusiveMandate = draft.exclusiveMandate;` line — note `ListingDraft` does NOT gain these 8 fields in this plan (drafts are a local-only, lower-fidelity save; the design doc doesn't ask for draft parity here, so the new fields simply don't survive a draft save/resume, matching the same scope boundary as any other feature that predates `ListingDraft`'s own field list). No draft-prefill code is needed for the new fields.

In `dispose()`, add the 3 new controllers to both the listener-removal loop and the explicit dispose calls:

```dart
  @override
  void dispose() {
    _previewDebounce?.cancel();
    for (final controller in [_areaController, _priceController, _bedroomsController, _bathroomsController, _sqftController]) {
      controller.removeListener(_onPreviewFieldChanged);
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _areaController.dispose();
    _priceController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    _sqftController.dispose();
    _commissionSplitController.dispose();
    _maintenanceFeeController.dispose();
    _parkingBaysController.dispose();
    _floorLevelController.dispose();
    _totalCommissionController.dispose();
    super.dispose();
  }
```

(The 3 new numeric controllers are deliberately NOT added to the live-preview listener loop -- none of the 8 new fields participate in `MatchingEngine.score()`, so recomputing the preview on their change would be pointless churn.)

In `_prefillFromListing`, add after the existing `_exclusiveMandate = listing.exclusiveMandate;` line:

```dart
    _maintenanceFeeController.text = listing.maintenanceFeeMyr?.toString() ?? '';
    _tenure = listing.tenure;
    _parkingBaysController.text = listing.parkingBays?.toString() ?? '';
    _floorLevelController.text = listing.floorLevel?.toString() ?? '';
    _furnishingStatus = listing.furnishingStatus;
    _totalCommissionController.text = listing.totalAgencyCommissionPercent?.toString() ?? '';
    _keysOnHand = listing.keysOnHand;
    _protectedCoBrokeReg = listing.protectedCoBrokeReg;
```

Add 3 new getters after the existing `_sqftValue` getter:

```dart
  double? get _maintenanceFeeValue {
    final text = _maintenanceFeeController.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  int? get _parkingBaysValue {
    final text = _parkingBaysController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  int? get _floorLevelValue {
    final text = _floorLevelController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  double? get _totalCommissionValue {
    final text = _totalCommissionController.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }
```

In `_submit()`, add the 8 new named args to BOTH the `updateListingDetails(...)` call and the `createListing(...)` call:

```dart
          maintenanceFeeMyr: _maintenanceFeeValue,
          tenure: _tenure,
          parkingBays: _parkingBaysValue,
          floorLevel: _floorLevelValue,
          furnishingStatus: _furnishingStatus,
          keysOnHand: _keysOnHand,
          protectedCoBrokeReg: _protectedCoBrokeReg,
          totalAgencyCommissionPercent: _totalCommissionValue,
```

(Insert this block right after the existing `exclusiveMandate: _exclusiveMandate,` line in each of the two calls.)

- [ ] **Step 5: Add the new UI**

In `build()`, insert a Tenure dropdown right after the existing Property Type dropdown's `const SizedBox(height: 12),` and before the Transaction Type dropdown:

```dart
                DropdownButtonFormField<String>(
                  key: const Key('listing_tenure_field'),
                  initialValue: _tenure,
                  decoration: InputDecoration(labelText: 'listing_field_tenure'.tr()),
                  hint: Text('-'),
                  items: [
                    DropdownMenuItem(value: 'freehold', child: Text('listing_tenure_freehold'.tr())),
                    DropdownMenuItem(value: 'leasehold', child: Text('listing_tenure_leasehold'.tr())),
                  ],
                  onChanged: (value) => setState(() => _tenure = value),
                ),
                const SizedBox(height: 12),
```

Insert a Maintenance Fee field right after the existing Price field's validator closing (`),` after the Price `TextFormField`), before the `Property Key Specs` label:

```dart
                TextFormField(
                  key: const Key('listing_maintenance_fee_field'),
                  controller: _maintenanceFeeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'listing_field_maintenance_fee'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    if (double.tryParse(value.trim()) == null) return 'validation_required'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
```

Add a second `SpecStatField` row (Parking/Floor/Furnishing) right after the existing Beds/Baths/Sqft `Row(...)` and its `const SizedBox(height: 12),`:

```dart
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SpecStatField(
                        fieldKey: const Key('listing_parking_field'),
                        icon: PhosphorIcons.car(PhosphorIconsStyle.bold),
                        controller: _parkingBaysController,
                        label: 'listing_stat_parking'.tr(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SpecStatField(
                        fieldKey: const Key('listing_floor_field'),
                        icon: PhosphorIcons.stackSimple(PhosphorIconsStyle.bold),
                        controller: _floorLevelController,
                        label: 'listing_stat_floor'.tr(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SpecStatField(
                        fieldKey: const Key('listing_furnishing_field'),
                        icon: PhosphorIcons.armchair(PhosphorIconsStyle.bold),
                        controller: TextEditingController(),
                        label: 'listing_stat_furnishing'.tr(),
                        dropdownValue: _furnishingStatus,
                        dropdownItems: [
                          DropdownMenuItem(value: 'furnished', child: Text('listing_furnishing_furnished'.tr())),
                          DropdownMenuItem(value: 'partially_furnished', child: Text('listing_furnishing_partially_furnished'.tr())),
                          DropdownMenuItem(value: 'unfurnished', child: Text('listing_furnishing_unfurnished'.tr())),
                        ],
                        onDropdownChanged: (value) => setState(() => _furnishingStatus = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
```

(The Furnishing cell's `controller: TextEditingController()` is a throwaway instance -- `SpecStatField` only reads `controller` in its `else` branch, which never executes when `dropdownItems` is non-null, so this satisfies the required positional-equivalent param without being used.)

Add a Total Agency Commission field right after the existing Commission Split section's closing `],` (the `if (_splitPreset == 'custom') ...[` block) and before the Title-Verified `SwitchListTile`:

```dart
                TextFormField(
                  key: const Key('listing_total_commission_field'),
                  controller: _totalCommissionController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'listing_field_total_commission'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final parsed = double.tryParse(value.trim());
                    if (parsed == null || parsed <= 0 || parsed > 100) return 'validation_required'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
```

Add 2 new `SwitchListTile`s right after the existing Exclusive Mandate switch:

```dart
                SwitchListTile(
                  key: const Key('listing_keys_on_hand_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('listing_field_keys_on_hand'.tr()),
                  subtitle: Text('listing_keys_on_hand_caption'.tr()),
                  value: _keysOnHand,
                  onChanged: (value) => setState(() => _keysOnHand = value),
                ),
                SwitchListTile(
                  key: const Key('listing_protected_co_broke_reg_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('listing_field_protected_co_broke_reg'.tr()),
                  subtitle: Text('listing_protected_co_broke_reg_caption'.tr()),
                  value: _protectedCoBrokeReg,
                  onChanged: (value) => setState(() => _protectedCoBrokeReg = value),
                ),
```

- [ ] **Step 6: Write the failing test**

Add to `app/test/features/listing/post_listing_screen_test.dart` (a new `testWidgets`, alongside the existing ones):

```dart
  testWidgets('renders the new property-attribute fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listing_tenure_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_maintenance_fee_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_parking_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_floor_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_furnishing_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_total_commission_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_keys_on_hand_switch')), findsOneWidget);
    expect(find.byKey(const Key('listing_protected_co_broke_reg_switch')), findsOneWidget);
  });

  testWidgets('edit mode pre-fills the new property-attribute fields', (tester) async {
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
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      maintenanceFeeMyr: 580,
      tenure: 'freehold',
      parkingBays: 2,
      floorLevel: 38,
      furnishingStatus: 'furnished',
      keysOnHand: true,
      protectedCoBrokeReg: true,
      totalAgencyCommissionPercent: 3,
    );

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: PostListingFormBody(editListingId: 'l-1')),
      ),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      listingDetailProvider('l-1').overrideWith((ref) async => existingListing),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'professional')),
      ),
    ]));
    await tester.pumpAndSettle();

    final maintenanceField = tester.widget<TextFormField>(find.byKey(const Key('listing_maintenance_fee_field')));
    expect(maintenanceField.controller?.text, '580.0');
    final keysOnHandSwitch = tester.widget<SwitchListTile>(find.byKey(const Key('listing_keys_on_hand_switch')));
    expect(keysOnHandSwitch.value, true);
  });
```

- [ ] **Step 7: Run test to verify it fails**

Run: `cd app && flutter test test/features/listing/post_listing_screen_test.dart`
Expected: FAIL — the new keys don't exist yet (if Step 5 hasn't been applied first; if applying steps in order, this instead verifies the widgets from Step 5 are wired correctly).

- [ ] **Step 8: Run test to verify it passes**

Run: `cd app && flutter test test/features/listing/post_listing_screen_test.dart`
Expected: PASS (all cases, including the 2 new ones).

- [ ] **Step 9: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: clean, same pass count as after Task 5 plus 2.

- [ ] **Step 10: Commit**

```bash
git add app/lib/features/listing/post_listing_screen.dart app/lib/features/listing/broadcast_badge.dart app/assets/translations/en.json app/assets/translations/ms.json app/test/features/listing/post_listing_screen_test.dart
git commit -m "feat: add property-attribute fields to Post Listing form"
```

---

### Task 7: `PropertyDetailScreen` — Hero header + Deal Terms banner

**Files:**
- Modify: `app/lib/features/listing/property_detail_screen.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`
- Test: `app/test/features/listing/property_detail_screen_test.dart`

**Interfaces:**
- Consumes: `Listing`'s 8 new fields (Task 1), `LiveMatchPreview.bestScoreForListing` (Task 5), `RequirementRepository.fetchOwnRequirements(negotiatorId)` (already exists).
- Produces: `_HeroHeader` and `_DealTermsBanner` private widgets, and a `_bestMatchScore` state field on `_PropertyDetailScreenState` that Task 9 also reads for CTA gating logic if needed (it does not — Task 9's CTA uses the separately-fetched `matchesForListingProvider`, not this score).

**Context:** Read `app/lib/features/listing/property_detail_screen.dart` fresh before starting — this task restructures its `build()` method, and the exact current line numbers may have shifted from other work this session (confirmed 256 lines as of the last read this session; verify before editing).

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, add after the last `broadcast_*` key added in an earlier milestone (search for `"broadcast_high_demand_badge"` to find the neighborhood):

```json
  "property_match_badge": "{score}% MATCH",
  "property_photo_counter": "{current}/{total} Photos",
  "property_price_per_sqft": "RM {value} / sqft",
  "property_maintenance_suffix": "Maint. RM {value}/mo",
  "property_co_broke_ready": "CO-BROKE READY",
```

In `app/assets/translations/ms.json`, add the same keys:

```json
  "property_match_badge": "{score}% PADAN",
  "property_photo_counter": "{current}/{total} Gambar",
  "property_price_per_sqft": "RM {value} / kps",
  "property_maintenance_suffix": "Penyelenggaraan RM {value}/bulan",
  "property_co_broke_ready": "SEDIA CO-BROKE",
```

Run: `cd app && python3 -c "
import json
en=json.load(open('assets/translations/en.json'))
ms=json.load(open('assets/translations/ms.json'))
assert set(en) == set(ms), (set(en)-set(ms), set(ms)-set(en))
print('parity ok', len(en))
"`
Expected: `parity ok <N>` with no assertion error.

- [ ] **Step 2: Add imports and new state to `_PropertyDetailScreenState`**

In `app/lib/features/listing/property_detail_screen.dart`, add imports (the file's current imports have no `AppColors` import at all -- confirmed by reading the file fresh; `AppColors.primary` is used starting in this task's `_HeroHeader`/`_DealTermsBanner` widgets):

```dart
import '../../core/theme/app_colors.dart';
import '../matching/live_match_preview.dart';
import '../requirement/models/requirement.dart';
import '../requirement/requirement_providers.dart' hide currentNegotiatorIdProvider;
```

Add a new state field and `initState` to `_PropertyDetailScreenState` (this class is currently `ConsumerState<PropertyDetailScreen>` with no `initState` override — add one):

```dart
  int? _bestMatchScore;

  @override
  void initState() {
    super.initState();
    _loadBestMatchScore();
  }

  /// Best-effort, same reasoning as every other live-preview fetch this
  /// session: the hero match badge is a real enhancement, never a
  /// requirement for the screen to render. A failure here (offline,
  /// backend hiccup, or an uninitialized Supabase client in tests) must
  /// not crash the screen; `_bestMatchScore` simply stays null and the
  /// badge's own null-check keeps it hidden.
  Future<void> _loadBestMatchScore() async {
    final viewerId = ref.read(currentNegotiatorIdProvider);
    if (viewerId == null) return;
    try {
      final listing = await ref.read(listingRepositoryProvider).fetchListingById(widget.listingId);
      if (listing.negotiatorId == viewerId) return; // never score your own listing
      final ownRequirements = await ref.read(requirementRepositoryProvider).fetchOwnRequirements(viewerId);
      final score = LiveMatchPreview.bestScoreForListing(listing, ownRequirements);
      if (!mounted) return;
      setState(() => _bestMatchScore = score);
    } catch (e) {
      debugPrint('_loadBestMatchScore failed: $e');
    }
  }
```

- [ ] **Step 3: Extract `_HeroHeader`**

Replace the existing photo `PageView` block (the `if (listing.photoUrls.isNotEmpty) SizedBox(height: 220, child: PageView(...))` section) with a call to a new extracted widget, and add that widget at the end of the file (after the `_PropertyDetailScreenState` class's closing `}`):

In `build()`'s `data: (listing) { ... }` branch, replace the existing photo section with:

```dart
                  _HeroHeader(
                    listing: listing,
                    bestMatchScore: _bestMatchScore,
                  ),
                  const SizedBox(height: 16),
```

Add the new widget class:

```dart
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.listing, required this.bestMatchScore});

  final Listing listing;
  final int? bestMatchScore;

  @override
  Widget build(BuildContext context) {
    if (listing.photoUrls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView(
              children: [
                for (final photoPath in listing.photoUrls)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListingPhoto(path: photoPath),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Wrap(
              spacing: 6,
              children: [
                if (bestMatchScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black),
                    ),
                    child: Text(
                      'property_match_badge'.tr(namedArgs: {'score': '$bestMatchScore'}),
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                if (listing.exclusiveMandate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'inventory_badge_exclusive_mandate'.tr(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'property_photo_counter'.tr(namedArgs: {'current': '1', 'total': '${listing.photoUrls.length}'}),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

(The `PageView`'s own scroll position isn't tracked here for a live "current" photo index -- `property_photo_counter` shows a static `1/{total}`, matching this project's own "don't build state you don't need yet" restraint; a real live-updating counter would need a `PageController` + listener, out of scope for a badge whose main job is showing the real total count.)

- [ ] **Step 4: Extract `_DealTermsBanner`**

Add the widget class after `_HeroHeader`:

```dart
class _DealTermsBanner extends StatelessWidget {
  const _DealTermsBanner({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final pricePerSqft = listing.builtUpSqft != null && listing.builtUpSqft! > 0
        ? (listing.price / listing.builtUpSqft!).round()
        : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.commissionSplitPercent != null) ...[
            Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  'property_co_broke_ready'.tr(),
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ListingFormatting.formatPrice(listing.price, listing.transactionType),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
                    ),
                    if (pricePerSqft != null || listing.maintenanceFeeMyr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (pricePerSqft != null) 'property_price_per_sqft'.tr(namedArgs: {'value': '$pricePerSqft'}),
                          if (listing.maintenanceFeeMyr != null)
                            'property_maintenance_suffix'.tr(namedArgs: {'value': '${listing.maintenanceFeeMyr!.round()}'}),
                        ].join(' • '),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              if (listing.commissionSplitPercent != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${listing.commissionSplitPercent!.round()}/${100 - listing.commissionSplitPercent!.round()}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      Text(
                        'RM ${(listing.price * listing.commissionSplitPercent! / 100).round()}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

In `build()`, add `_DealTermsBanner(listing: listing)` right after `_HeroHeader(...)`'s `const SizedBox(height: 16),`:

```dart
                  _DealTermsBanner(listing: listing),
                  const SizedBox(height: 16),
```

- [ ] **Step 5: Write the failing tests**

Add to `app/test/features/listing/property_detail_screen_test.dart`:

```dart
  testWidgets('shows the real match badge when the viewer has a qualifying open requirement', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    const matchingRequirement = Requirement(
      requirementId: 'r-1',
      negotiatorId: 'n-2',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      budgetMin: 1000000,
      budgetMax: 1500000,
      bedrooms: 3,
      photoUrls: [],
      status: 'open',
    );

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-2',
      extraOverrides: [
        ownRequirementsProvider('n-2').overrideWith((ref) async => [matchingRequirement]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('property_match_badge'.tr(namedArgs: {'score': '100'})), findsOneWidget);
  });

  testWidgets('hides the match badge for the listing owner viewing their own listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('MATCH'), findsNothing);
  });

  testWidgets('shows real commission split and price-per-sqft in the deal terms banner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final listingWithSplit = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1000000,
      builtUpSqft: 1000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      commissionSplitPercent: 50,
    );

    await tester.pumpWidget(_wrap(router, listing: listingWithSplit));
    await tester.pumpAndSettle();

    expect(find.text('50/50'), findsOneWidget);
    expect(find.text('property_price_per_sqft'.tr(namedArgs: {'value': '1000'})), findsOneWidget);
  });
```

`_loadBestMatchScore` reads `requirementRepositoryProvider` and `listingRepositoryProvider` directly (not through a family provider like `myRequirementsProvider`), so the test overrides must be fake repositories, matching the exact `_FakeRequirementRepository`/`_FakeListingRepository`/`_FakeSupabaseClient` pattern already established in `post_broadcast_screen_test.dart` this session. Add these at the top of `property_detail_screen_test.dart` (after its existing imports, before `_fixtureListing`):

```dart
/// Never actually invoked -- see the identical class in
/// post_broadcast_screen_test.dart, which this mirrors.
class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// _loadBestMatchScore reads listingRepositoryProvider.fetchListingById
/// directly (not listingDetailProvider, which _wrap already overrides for
/// the main widget tree) -- this fake makes that second, independent
/// fetch resolve instead of throwing on the uninitialized Supabase client.
class _FakeListingRepositoryForMatchScore extends ListingRepository {
  _FakeListingRepositoryForMatchScore(this._listing) : super(_FakeSupabaseClient());

  final Listing _listing;

  @override
  Future<Listing> fetchListingById(String listingId) async => _listing;
}

/// Symmetric fake for _loadBestMatchScore's fetchOwnRequirements call.
class _FakeRequirementRepositoryForMatchScore extends RequirementRepository {
  _FakeRequirementRepositoryForMatchScore([this._requirements = const []]) : super(_FakeSupabaseClient());

  final List<Requirement> _requirements;

  @override
  Future<List<Requirement>> fetchOwnRequirements(String negotiatorId) async => _requirements;
}
```

Add the corresponding imports to the test file: `package:supabase_flutter/supabase_flutter.dart`, `package:renly/features/listing/listing_repository.dart`, `package:renly/features/requirement/requirement_repository.dart`, `package:renly/features/requirement/models/requirement.dart`.

Rewrite the two tests from Step 5 to use these fakes instead of a bare `ownRequirementsProvider` override:

```dart
  testWidgets('shows the real match badge when the viewer has a qualifying open requirement', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    const matchingRequirement = Requirement(
      requirementId: 'r-1',
      negotiatorId: 'n-2',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      budgetMin: 1000000,
      budgetMax: 1500000,
      bedrooms: 3,
      photoUrls: [],
      status: 'open',
    );

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-2',
      extraOverrides: [
        listingRepositoryProvider.overrideWithValue(_FakeListingRepositoryForMatchScore(_fixtureListing)),
        requirementRepositoryProvider.overrideWithValue(_FakeRequirementRepositoryForMatchScore([matchingRequirement])),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('property_match_badge'.tr(namedArgs: {'score': '100'})), findsOneWidget);
  });

  testWidgets('hides the match badge for the listing owner viewing their own listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      extraOverrides: [
        listingRepositoryProvider.overrideWithValue(_FakeListingRepositoryForMatchScore(_fixtureListing)),
        requirementRepositoryProvider.overrideWithValue(_FakeRequirementRepositoryForMatchScore()),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('MATCH'), findsNothing);
  });
```

`requirementRepositoryProvider` needs `hide currentNegotiatorIdProvider` on its import in the test file (the same ambiguous-import collision this session hit 5+ times already, since `listing_providers.dart` also declares a `currentNegotiatorIdProvider`) — import it as `import 'package:renly/features/requirement/requirement_providers.dart' hide currentNegotiatorIdProvider;`.

- [ ] **Step 6: Run test to verify it fails, then implement/adjust until passing**

Run: `cd app && flutter test test/features/listing/property_detail_screen_test.dart`

Iterate on Step 5's exact fixture wiring (per the note above) until all tests pass. Expected final state: PASS (8/8 — 5 existing + 3 new).

- [ ] **Step 7: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: clean, same pass count as after Task 6 plus 3.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/listing/property_detail_screen.dart app/assets/translations/en.json app/assets/translations/ms.json app/test/features/listing/property_detail_screen_test.dart
git commit -m "feat: restyle Property Detail hero header and deal-terms banner with real data"
```

---

### Task 8: `PropertyDetailScreen` — Overview card + Co-Broking Terms card

**Files:**
- Modify: `app/lib/features/listing/property_detail_screen.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`
- Modify: `app/pubspec.yaml` is NOT touched — `url_launcher` is already a dependency (confirmed via `pubspec.yaml` grep this session), just unused until this task.
- Test: `app/test/features/listing/property_detail_screen_test.dart`

**Interfaces:**
- Consumes: `Listing`'s 8 new fields (Task 1), `url_launcher`'s `launchUrl`/`Uri` (already a dependency).
- Produces: `_OverviewCard` and `_CoBrokingTermsCard` private widgets.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`:

```json
  "property_id_prefix": "ID: #{id}",
  "property_map_button": "Map",
  "property_badge_keys_on_hand": "Keys on Hand",
  "property_badge_protected_co_broke_reg": "Protected Co-Broke Reg",
  "property_co_broking_terms_title": "Co-Broking Terms",
  "property_split_badge": "{split}",
  "property_total_commission_row": "Total Agency Commission ({percent}%)",
  "property_your_share_row": "Your Co-Broke Share ({percent}%)",
  "property_registration_guarantee": "Renly protects your registration: only one active co-broke request per match.",
```

In `app/assets/translations/ms.json`:

```json
  "property_id_prefix": "ID: #{id}",
  "property_map_button": "Peta",
  "property_badge_keys_on_hand": "Kunci Di Tangan",
  "property_badge_protected_co_broke_reg": "Pendaftaran Co-Broke Dilindungi",
  "property_co_broking_terms_title": "Terma Co-Broking",
  "property_split_badge": "{split}",
  "property_total_commission_row": "Jumlah Komisen Agensi ({percent}%)",
  "property_your_share_row": "Bahagian Co-Broke Anda ({percent}%)",
  "property_registration_guarantee": "Renly melindungi pendaftaran anda: hanya satu permintaan co-broke aktif setiap padanan.",
```

Run the same parity check command as Task 7 Step 1.

- [ ] **Step 2: Add the `url_launcher` import**

In `app/lib/features/listing/property_detail_screen.dart`:

```dart
import 'package:url_launcher/url_launcher.dart';
```

- [ ] **Step 3: Extract `_OverviewCard`**

Replace the existing title/badges/price/bed-bath-sqft-row/description/location block (everything from the `Text(listing.title, ...)` line through the `Text('${listing.area}, ${listing.state}', ...)` line) with a call to a new widget, keeping the existing `Wrap` of `StatusBadge`+titleVerified+exclusiveMandate badges' logic (moved into the new widget, not duplicated):

```dart
                  _OverviewCard(listing: listing, statusLabel: _statusLabel(listing.status)),
                  const SizedBox(height: 16),
```

Add the new widget class:

```dart
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.listing, required this.statusLabel});

  final Listing listing;
  final String statusLabel;

  Future<void> _openMap(BuildContext context) async {
    final query = Uri.encodeComponent('${listing.area}, ${listing.state}');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('listing_error_generic'.tr())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortId = listing.listingId.length >= 8 ? listing.listingId.substring(0, 8).toUpperCase() : listing.listingId.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  listing.tenure == null ? listing.propertyType.toUpperCase() : '${listing.propertyType.toUpperCase()} • ${listing.tenure!.toUpperCase()}',
                  style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
              Text(
                'property_id_prefix'.tr(namedArgs: {'id': shortId}),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(listing.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('${listing.area}, ${listing.state}', style: Theme.of(context).textTheme.bodyMedium),
              ),
              TextButton(
                onPressed: () => _openMap(context),
                child: Text('property_map_button'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge(label: statusLabel),
              if (listing.titleVerified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.bold), size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'inventory_badge_title_verified'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              if (listing.exclusiveMandate)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.crown(PhosphorIconsStyle.bold), size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'inventory_badge_exclusive_mandate'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              if (listing.keysOnHand)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.key(PhosphorIconsStyle.bold), size: 12, color: const Color(0xFF2563EB)),
                      const SizedBox(width: 4),
                      Text(
                        'property_badge_keys_on_hand'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              if (listing.protectedCoBrokeReg)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.lockKey(PhosphorIconsStyle.bold), size: 12, color: const Color(0xFF7C3AED)),
                      const SizedBox(width: 4),
                      Text(
                        'property_badge_protected_co_broke_reg'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (listing.bedrooms != null) ...[
                const Icon(Icons.bed),
                const SizedBox(width: 4),
                Text('${listing.bedrooms}'),
                const SizedBox(width: 16),
              ],
              if (listing.bathrooms != null) ...[
                const Icon(Icons.bathtub),
                const SizedBox(width: 4),
                Text('${listing.bathrooms}'),
                const SizedBox(width: 16),
              ],
              if (listing.builtUpSqft != null) ...[
                Icon(PhosphorIcons.ruler(PhosphorIconsStyle.bold)),
                const SizedBox(width: 4),
                Text('${ListingFormatting.formatSqft(listing.builtUpSqft!)} ${'inventory_stat_sqft'.tr()}'),
                const SizedBox(width: 16),
              ],
              if (listing.parkingBays != null) ...[
                Icon(PhosphorIcons.car(PhosphorIconsStyle.bold)),
                const SizedBox(width: 4),
                Text('${listing.parkingBays}'),
                const SizedBox(width: 16),
              ],
              if (listing.floorLevel != null) ...[
                Icon(PhosphorIcons.stackSimple(PhosphorIconsStyle.bold)),
                const SizedBox(width: 4),
                Text('${listing.floorLevel}'),
              ],
            ],
          ),
          if (listing.furnishingStatus != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(PhosphorIcons.armchair(PhosphorIconsStyle.bold)),
                const SizedBox(width: 4),
                Text(listing.furnishingStatus == 'furnished'
                    ? 'listing_furnishing_furnished'.tr()
                    : listing.furnishingStatus == 'partially_furnished'
                        ? 'listing_furnishing_partially_furnished'.tr()
                        : 'listing_furnishing_unfurnished'.tr()),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('property_overview'.tr(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(listing.description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Extract `_CoBrokingTermsCard`**

Add the widget class after `_OverviewCard`:

```dart
class _CoBrokingTermsCard extends StatelessWidget {
  const _CoBrokingTermsCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    if (listing.commissionSplitPercent == null && listing.totalAgencyCommissionPercent == null) {
      return const SizedBox.shrink();
    }
    final split = listing.commissionSplitPercent?.round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(PhosphorIcons.handshake(PhosphorIconsStyle.bold), size: 18),
                  const SizedBox(width: 6),
                  Text('property_co_broking_terms_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              if (split != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black)),
                  child: Text(
                    'property_split_badge'.tr(namedArgs: {'split': '$split/${100 - split}'}),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF7F8F5), borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                if (listing.totalAgencyCommissionPercent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'property_total_commission_row'.tr(namedArgs: {'percent': '${listing.totalAgencyCommissionPercent!.round()}'}),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          'RM ${(listing.price * listing.totalAgencyCommissionPercent! / 100).round()}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (split != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'property_your_share_row'.tr(namedArgs: {'percent': '$split'}),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        'RM ${(listing.price * split / 100).round()}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF047857)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(PhosphorIcons.shieldCheck(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF047857)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'property_registration_guarantee'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

In `build()`, add `_CoBrokingTermsCard(listing: listing)` right after `_OverviewCard(...)`'s `const SizedBox(height: 16),`:

```dart
                  _CoBrokingTermsCard(listing: listing),
                  const SizedBox(height: 16),
```

- [ ] **Step 5: Write the failing tests**

Add to `app/test/features/listing/property_detail_screen_test.dart`:

```dart
  testWidgets('shows the real Co-Broking Terms card when a split or total commission is set', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final listingWithTerms = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1250000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      commissionSplitPercent: 50,
      totalAgencyCommissionPercent: 3,
    );

    await tester.pumpWidget(_wrap(router, listing: listingWithTerms));
    await tester.pumpAndSettle();

    expect(find.text('property_co_broking_terms_title'.tr()), findsOneWidget);
    expect(find.text('property_total_commission_row'.tr(namedArgs: {'percent': '3'})), findsOneWidget);
    expect(find.text('RM 37500'), findsOneWidget);
  });

  testWidgets('hides the Co-Broking Terms card when neither split nor total commission is set', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('property_co_broking_terms_title'.tr()), findsNothing);
  });

  testWidgets('shows keys-on-hand and protected-co-broke-reg badges only when true', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final listingWithBadges = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1250000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      keysOnHand: true,
    );

    await tester.pumpWidget(_wrap(router, listing: listingWithBadges));
    await tester.pumpAndSettle();

    expect(find.text('property_badge_keys_on_hand'.tr()), findsOneWidget);
    expect(find.text('property_badge_protected_co_broke_reg'.tr()), findsNothing);
  });
```

- [ ] **Step 6: Run test to verify it fails, then implement until passing**

Run: `cd app && flutter test test/features/listing/property_detail_screen_test.dart`
Expected, after implementing Steps 1-4: PASS (11/11 — 8 from Task 7 + 3 new).

- [ ] **Step 7: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: clean, same pass count as after Task 7 plus 3.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/listing/property_detail_screen.dart app/assets/translations/en.json app/assets/translations/ms.json app/test/features/listing/property_detail_screen_test.dart
git commit -m "feat: restyle Property Detail overview and co-broking terms cards with real data"
```

---

### Task 9: `PropertyDetailScreen` — Agent card + real CTA bar + owner actions

**Files:**
- Modify: `app/lib/features/listing/property_detail_screen.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`
- Test: `app/test/features/listing/property_detail_screen_test.dart`

**Interfaces:**
- Consumes: `ListingOwner.verificationStatus` (Task 3), `ratingsForNegotiatorProvider` (existing, from `app/lib/features/ratings/rating_providers.dart`), `matchesForListingProvider` (existing, from `app/lib/features/matching/matching_providers.dart`), `sendCobrokeRequest` (existing, from `app/lib/features/collaboration/send_cobroke_request_action.dart`), `share_plus`'s `SharePlus`/`ShareParams` (already a dependency, already used in `my_inventory_screen.dart` — read that file's exact call site fresh to match its pattern before writing this task's Share button).
- Produces: `_AgentCard` and `_ActionBar` private widgets, completing the screen restructure. This is the final task — no later task depends on this one.

**Context:** This task also resolves where the EXISTING owner-only management buttons (View Matches / Mark Sold / Withdraw / Reactivate) go: the mockup is buyer-facing only and shows none of them, so they move into the bottom bar's owner branch, replacing the buyer-facing `_ActionBar` when `isOwner` is true — exactly mirroring the `if (isOwner)` gate the current code already has, just relocated to the bottom instead of inline mid-scroll.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`:

```json
  "property_message_button": "Message",
  "property_no_ratings_short": "New Agent",
  "property_client_share_label": "Client",
  "property_request_co_broke_disabled_reason": "No qualifying match yet for your requirements",
```

In `app/assets/translations/ms.json`:

```json
  "property_message_button": "Mesej",
  "property_no_ratings_short": "Ejen Baharu",
  "property_client_share_label": "Klien",
  "property_request_co_broke_disabled_reason": "Belum ada padanan layak untuk keperluan anda",
```

Run the same parity check command as Task 7 Step 1.

- [ ] **Step 2: Check the exact existing Share pattern**

Run: `grep -n -B2 -A15 "SharePlus.instance.share" app/lib/features/listing/my_inventory_screen.dart`

Match that exact call shape (constructor args, import) in this task's `_ActionBar`.

- [ ] **Step 3: Add imports**

In `app/lib/features/listing/property_detail_screen.dart`, add:

```dart
import 'package:share_plus/share_plus.dart';

import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import '../collaboration/models/cobroke_request_candidate.dart';
import '../collaboration/send_cobroke_request_action.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../matching/models/match_candidate.dart';
import '../ratings/rating_providers.dart';
```

- [ ] **Step 4: Extract `_AgentCard`**

Replace the existing `Builder(builder: (context) { final ownerAsync = ...})` block with:

```dart
                  _AgentCard(listingId: listing.listingId, negotiatorId: listing.negotiatorId),
                  const SizedBox(height: 16),
```

Add the new widget class (a `ConsumerWidget`, since it needs to watch several providers). Chat in this app is hard-gated behind an ACCEPTED `cobroke_request` (confirmed via `conversation_list_screen.dart`'s own real navigation, `context.push('/messages/$requestId')` where `requestId` is a `cobroke_request.request_id`, not a bare negotiator id) — there is no "start a conversation with an arbitrary stranger" flow anywhere in this app. The Message button is therefore only enabled when the viewer already has an accepted `cobroke_request` (as either initiator or recipient) whose match is against THIS listing — found by scanning the viewer's own `sentRequestsProvider`/`receivedRequestsProvider` (both already real, already fetched elsewhere in the app) for one whose `match.listing.listingId` equals this listing's id and whose `request.status == 'accepted'`, written as a plain loop rather than adding a new `collection` package dependency for a single `.firstWhereOrNull` call:

```dart
class _AgentCard extends ConsumerWidget {
  const _AgentCard({required this.listingId, required this.negotiatorId});

  final String listingId;
  final String negotiatorId;

  /// Plain-loop equivalent of `.firstWhereOrNull` -- avoids adding the
  /// `collection` package as a new direct dependency for one call site
  /// (it's currently only a transitive dependency via pubspec.lock).
  static CobrokeRequestCandidate? _acceptedRequestForThisListing(List<CobrokeRequestCandidate> candidates, String listingId) {
    for (final candidate in candidates) {
      if (candidate.match.listing.listingId == listingId && candidate.request.status == 'accepted') {
        return candidate;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerAsync = ref.watch(listingOwnerProvider(negotiatorId));
    final ratingsAsync = ref.watch(ratingsForNegotiatorProvider(negotiatorId));
    final sentAsync = ref.watch(sentRequestsProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final acceptedCandidate = _acceptedRequestForThisListing(
      [...?sentAsync.valueOrNull, ...?receivedAsync.valueOrNull],
      listingId,
    );

    return ownerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (owner) {
        final ratingText = ratingsAsync.valueOrNull == null || ratingsAsync.valueOrNull!.isEmpty
            ? 'property_no_ratings_short'.tr()
            : '${(ratingsAsync.valueOrNull!.map((c) => c.rating.stars).reduce((a, b) => a + b) / ratingsAsync.valueOrNull!.length).toStringAsFixed(1)} (${ratingsAsync.valueOrNull!.length})';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(owner.fullName, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                        if (owner.verificationStatus == 'approved') ...[
                          const SizedBox(width: 4),
                          Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill), size: 15, color: const Color(0xFF059669)),
                        ],
                      ],
                    ),
                    Text(
                      owner.agencyName == null ? 'REN: ${owner.renNumber}' : 'REN: ${owner.renNumber} • ${owner.agencyName}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), size: 13, color: const Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(ratingText, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: acceptedCandidate == null
                    ? null
                    : () => context.push('/messages/${acceptedCandidate.request.requestId}'),
                icon: Icon(PhosphorIcons.chatCircle(PhosphorIconsStyle.bold), size: 16),
                label: Text('property_message_button'.tr()),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

Add the required imports for `CobrokeRequestCandidate`, `sentRequestsProvider`/`receivedRequestsProvider`: `import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;` and `import '../collaboration/models/cobroke_request_candidate.dart';` (both new imports for this file; the `hide` is needed for the same ambiguous-`currentNegotiatorIdProvider`-across-feature-files reason this session has hit repeatedly).

- [ ] **Step 5: Extract `_ActionBar`**

Replace the existing `if (isOwner) [...]` action-buttons block (View Matches / Mark Sold / Withdraw / Reactivate) with a call to a new widget that internally branches on `isOwner`:

```dart
                  _ActionBar(
                    listing: listing,
                    isOwner: isOwner,
                    atCap: atCap,
                    onMarkSold: () => _changeStatus(listing, 'sold'),
                    onWithdraw: () => _changeStatus(listing, 'withdrawn'),
                    onReactivate: () => _changeStatus(listing, 'active'),
                  ),
```

Add the new widget class:

```dart
class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.listing,
    required this.isOwner,
    required this.atCap,
    required this.onMarkSold,
    required this.onWithdraw,
    required this.onReactivate,
  });

  final Listing listing;
  final bool isOwner;
  final bool atCap;
  final VoidCallback onMarkSold;
  final VoidCallback onWithdraw;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isOwner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalistButton(
            label: 'matching_view_matches'.tr(),
            onPressed: () => context.push('/property/${listing.listingId}/matches'),
            variant: BrutalistButtonVariant.secondary,
          ),
          const SizedBox(height: 8),
          if (listing.status != 'sold') ...[
            BrutalistButton(
              label: 'property_mark_sold'.tr(),
              onPressed: onMarkSold,
              variant: BrutalistButtonVariant.secondary,
            ),
            const SizedBox(height: 8),
          ],
          if (listing.status != 'withdrawn') ...[
            BrutalistButton(
              label: 'property_withdraw'.tr(),
              onPressed: onWithdraw,
              variant: BrutalistButtonVariant.secondary,
            ),
            const SizedBox(height: 8),
          ],
          if (listing.status != 'active') ...[
            if (atCap) ...[
              Text(
                'listing_cap_reached_message'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            BrutalistButton(
              label: 'property_reactivate'.tr(),
              onPressed: atCap ? null : onReactivate,
              variant: BrutalistButtonVariant.secondary,
            ),
          ],
        ],
      );
    }

    final viewerId = ref.watch(currentNegotiatorIdProvider);
    final matchesAsync = viewerId == null
        ? const AsyncValue<List<MatchCandidate>>.data([])
        : ref.watch(matchesForListingProvider(listing.listingId));
    MatchCandidate? ownMatch;
    for (final candidate in matchesAsync.valueOrNull ?? const <MatchCandidate>[]) {
      if (candidate.requirement.negotiatorId == viewerId) {
        ownMatch = candidate;
        break;
      }
    }

    return Row(
      children: [
        OutlinedButton(
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: '${listing.title} - ${ListingFormatting.formatPrice(listing.price, listing.transactionType)} - ${listing.area}, ${listing.state}'),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.paperPlaneTilt(PhosphorIconsStyle.bold)),
              Text('property_client_share_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Tooltip(
            message: ownMatch == null ? 'property_request_co_broke_disabled_reason'.tr() : '',
            child: BrutalistButton(
              label: 'cobroke_request_send'.tr(),
              icon: PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
              onPressed: ownMatch == null ? null : () => sendCobrokeRequest(context, ref, ownMatch.matchId),
            ),
          ),
        ),
      ],
    );
  }
}
```

The `_AgentCard` import list added in Step 3 already covers `MatchCandidate`'s import path for this widget too.

- [ ] **Step 6: Write the failing tests**

Add to `app/test/features/listing/property_detail_screen_test.dart`:

```dart
  testWidgets('shows the real rating and Message button on the agent card', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, extraOverrides: [
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => []),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('property_no_ratings_short'.tr()), findsOneWidget);
    expect(find.text('property_message_button'.tr()), findsOneWidget);
  });

  testWidgets('disables Request Co-Broke when the viewer has no qualifying match for this listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-2',
      extraOverrides: [
        matchesForListingProvider('l-1').overrideWith((ref) async => []),
        ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => []),
      ],
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<BrutalistButton>(find.widgetWithText(BrutalistButton, 'cobroke_request_send'.tr()));
    expect(button.onPressed, isNull);
  });
```

- [ ] **Step 7: Run test to verify it fails, then implement until passing**

Run: `cd app && flutter test test/features/listing/property_detail_screen_test.dart`
Expected, after implementing Steps 2-5: PASS (13/13 — 11 from Task 8 + 2 new).

- [ ] **Step 8: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: clean, same pass count as after Task 8 plus 2.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/listing/property_detail_screen.dart app/assets/translations/en.json app/assets/translations/ms.json app/test/features/listing/property_detail_screen_test.dart
git commit -m "feat: restyle Property Detail agent card and action bar, add real Request Co-Broke CTA"
```

---

## Manual verification (after all tasks, and after migrations 0025 and 0026 are applied)

1. Confirm migrations `0025` and `0026` were applied (ask the user, or run `supabase db query --linked` to check the 8 new `listing` columns + the extended RPC's return shape independently).
2. Post a listing with maintenance fee, tenure, parking, floor, furnishing, total commission, and both new toggles set — open its Property Detail screen as the owner, confirm every new field renders in the Overview card's stat grid and badges.
3. View the same listing as a DIFFERENT negotiator who has an open requirement that qualifies against it (matching property type/transaction type/state/budget) — confirm the real "N% MATCH" badge appears on the hero image, and that "Request Co-Broke" is enabled and actually sends a real request when tapped.
4. View the same listing as a different negotiator with NO qualifying requirement — confirm the match badge is absent and "Request Co-Broke" is disabled with the tooltip reason.
5. Confirm the "Map" button opens the device's real maps app with the listing's address pre-filled.
6. Confirm the "Client" share button opens the real OS share sheet with genuine listing text (title/price/location), not a placeholder.
7. Confirm the owner's own view of their own listing shows the existing View Matches/Mark Sold/Withdraw/Reactivate buttons (unchanged behavior) instead of the buyer-facing action bar, and shows NO match badge on the hero image.
8. Confirm a listing with no commission split AND no total agency commission set shows no Co-Broking Terms card at all (not an empty one).
