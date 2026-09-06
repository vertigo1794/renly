# Post Broadcast (Post Listing + Buyer Match Merge) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge `PostListingScreen` and `PostRequirementScreen` behind one real "Provide Listing / Buyer Match" toggle screen, and give `Requirement` real minimum-spec/commission-split/readiness fields plus a genuine live match preview on both forms before submission.

**Architecture:** A new `PostBroadcastScreen` owns shared chrome (header/ticker/toggle) and an `IndexedStack` of two extracted, Scaffold-less form bodies (`PostListingFormBody`, `PostRequirementFormBody`) that keep their own existing State/logic unchanged. A new pure `LiveMatchPreview` helper reuses the existing `MatchingEngine.score()` client-side, with zero new backend endpoint, to power a real pre-submission match preview on both forms.

**Tech Stack:** Flutter, Riverpod, Supabase (PostgREST), `go_router`, `easy_localization`, `phosphor_flutter`.

## Global Constraints

- `Requirement`'s 5 new fields must keep the class `const`-constructible — all are optional/defaulted, no `DateTime` or other non-const-safe type.
- `MatchingEngine`'s new bathroom/sqft filters are qualifying (disqualify via `null`), never added to the existing 100-point weighted formula (location 30 / price 35 / property type 25 / bedrooms 10), which stays untouched.
- The live match preview never writes to the DB and never sends notifications — it must not go through `MatchingRepository`. It reuses `MatchingEngine.score()` directly against an already-fetched candidate list.
- A live preview section (and its CTA subtext) must render nothing when its real match count is 0 — never a fabricated placeholder count or percentage.
- `PostListingFormBody`/`PostRequirementFormBody` preserve their existing State classes, controllers, validators, and `_submit()` logic byte-for-byte from the current `PostListingScreen`/`PostRequirementScreen` — only the outer `Scaffold`/`AppBar` wrapper is removed. No behavior change to create/edit/draft-resume flows.
- The toggle is hidden entirely when `editListingId != null`.
- Migration grants (INSERT/UPDATE column lists) are restated in full in the same migration file as the column adds — never split across two migrations (the lesson from this session's own `0020`/`0021` incident).
- All new/changed icons use `PhosphorIcons.x(PhosphorIconsStyle.bold)`, never `Icons.*`.
- `flutter analyze` and the full `flutter test` suite must stay clean throughout.
- No golden-image tests.
- EN/MS l10n key parity maintained; reuse `listing_self_attestation_notice` verbatim on the Requirement form's new toggles rather than duplicating it.
- Migration `0024_requirement_broadcast_fields.sql` is a file only — no task applies it; the user applies it manually via the Supabase SQL Editor, then it's independently verified via `supabase db query --linked`.

---

## Task 1: `Requirement` model gains 5 new fields

**Files:**
- Modify: `app/lib/features/requirement/models/requirement.dart`

**Interfaces:**
- Produces: `Requirement.bathroomsMin` (`int?`), `Requirement.builtUpSqftMin` (`int?`), `Requirement.desiredCommissionSplitPercent` (`double?`), `Requirement.loanReady` (`bool`, default `false`), `Requirement.urgentViewingRequired` (`bool`, default `false`). The class stays `const`-constructible.

- [ ] **Step 1: Read the current file**

```bash
cat "app/lib/features/requirement/models/requirement.dart"
```

Confirm it matches (already verified this session):
```dart
/// A row from the `requirement` table.
class Requirement {
  final String requirementId;
  final String negotiatorId;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final double budgetMin;
  final double budgetMax;
  final int? bedrooms;
  final List<String> photoUrls;
  final String status;

  const Requirement({
    required this.requirementId,
    required this.negotiatorId,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    required this.budgetMin,
    required this.budgetMax,
    this.bedrooms,
    required this.photoUrls,
    required this.status,
  });

  factory Requirement.fromJson(Map<String, dynamic> json) {
    return Requirement(
      requirementId: json['requirement_id'] as String,
      negotiatorId: json['negotiator_id'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      budgetMin: (json['budget_min'] as num).toDouble(),
      budgetMax: (json['budget_max'] as num).toDouble(),
      bedrooms: json['bedrooms'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
    );
  }
}
```

- [ ] **Step 2: Add the 5 new fields**

Replace the whole file with:

```dart
/// A row from the `requirement` table.
class Requirement {
  final String requirementId;
  final String negotiatorId;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final double budgetMin;
  final double budgetMax;
  final int? bedrooms;
  final List<String> photoUrls;
  final String status;

  /// Minimum bathroom count the buyer requires. Nullable -- unset means
  /// no minimum, so `MatchingEngine.score` never disqualifies on this
  /// dimension for this requirement.
  final int? bathroomsMin;

  /// Minimum built-up size (sqft) the buyer requires. Same null-means-
  /// unset semantics as [bathroomsMin].
  final int? builtUpSqftMin;

  /// The buyer's own advertised/desired co-broke split percentage --
  /// self-set by the requirement's own owner, standalone from
  /// `Listing.commissionSplitPercent` (the LISTING owner's own advertised
  /// split) and from `Agreement.splitInitiator`/`splitCounterparty`
  /// (which only exists once a deal is formalized). Null means the buyer
  /// didn't set one; UI must never show a fabricated fallback percentage.
  final double? desiredCommissionSplitPercent;

  /// Self-attested by the requirement's own owner -- NOT third-party
  /// verified. Defaults false so every existing call site compiles
  /// unchanged.
  final bool loanReady;

  /// Self-attested by the requirement's own owner -- NOT third-party
  /// verified. Same default-false reasoning as [loanReady].
  final bool urgentViewingRequired;

  const Requirement({
    required this.requirementId,
    required this.negotiatorId,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    required this.budgetMin,
    required this.budgetMax,
    this.bedrooms,
    required this.photoUrls,
    required this.status,
    this.bathroomsMin,
    this.builtUpSqftMin,
    this.desiredCommissionSplitPercent,
    this.loanReady = false,
    this.urgentViewingRequired = false,
  });

  factory Requirement.fromJson(Map<String, dynamic> json) {
    return Requirement(
      requirementId: json['requirement_id'] as String,
      negotiatorId: json['negotiator_id'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      budgetMin: (json['budget_min'] as num).toDouble(),
      budgetMax: (json['budget_max'] as num).toDouble(),
      bedrooms: json['bedrooms'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
      bathroomsMin: json['bathrooms_min'] as int?,
      builtUpSqftMin: json['built_up_sqft_min'] as int?,
      desiredCommissionSplitPercent: (json['desired_commission_split_percent'] as num?)?.toDouble(),
      loanReady: json['loan_ready'] as bool? ?? false,
      urgentViewingRequired: json['urgent_viewing_required'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 3: Verify zero test-fixture blast radius**

```bash
cd "app" && flutter analyze
```

Expected: `No issues found!` — every existing `const Requirement(...)` construction (matching_engine_test.dart, requirement feature tests) already omits the 5 new fields, which are all optional/defaulted, and the class is still `const`-constructible (all new field types — `int?`, `double?`, `bool`-with-default — are const-safe). If analyze reports anything, read the specific error and fix only what it names.

- [ ] **Step 4: Run the full test suite**

```bash
cd "app" && flutter test
```

Expected: all tests pass, same count as before this task.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/requirement/models/requirement.dart
git commit -m "feat: add bathroomsMin/builtUpSqftMin/desiredCommissionSplitPercent/loanReady/urgentViewingRequired to Requirement"
```

---

## Task 2: Migration `0024_requirement_broadcast_fields.sql`

**Files:**
- Create: `supabase/migrations/0024_requirement_broadcast_fields.sql`

**Interfaces:**
- Produces: `requirement.bathrooms_min` (`integer`, nullable, check `>= 0`), `requirement.built_up_sqft_min` (`integer`, nullable, check `>= 0`), `requirement.desired_commission_split_percent` (`numeric(5,2)`, nullable, check `> 0 and <= 100`), `requirement.loan_ready` (`boolean not null default false`), `requirement.urgent_viewing_required` (`boolean not null default false`). Task 3's repository changes read/write these exact column names.

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/0024_requirement_broadcast_fields.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0023.
--
-- Five new buyer-set fields for the Post Broadcast (Post Listing + Buyer
-- Match merge) milestone: bathrooms_min/built_up_sqft_min (real minimum
-- specs the buyer requires, used as MATCHING ENGINE QUALIFYING FILTERS,
-- not part of the existing 100-point weighted score), desired_commission_
-- split_percent (the buyer's own advertised/desired co-broke split,
-- self-set, standalone from Listing's own commission_split_percent and
-- from Agreement's post-deal formal split), and loan_ready/
-- urgent_viewing_required (self-attested by the requirement's own owner
-- -- NOT third-party verified; the in-app form's own caption makes this
-- explicit, this migration only adds the storage for it).
--
-- Grants are restated in FULL here (not just the new columns), in the
-- SAME migration as the column adds -- this project hit a real live bug
-- earlier this session (migration 0020) from adding columns without
-- extending the existing column-scoped INSERT/UPDATE grants in the same
-- migration; this migration applies that lesson from the start.
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

- [ ] **Step 2: Tell the user to apply it**

Print this exact message to the user (do not apply the migration yourself):

> Migration `0024_requirement_broadcast_fields.sql` created. Please apply it manually via the Supabase Dashboard's SQL Editor (same process as every prior migration), then let me know once it's done.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0024_requirement_broadcast_fields.sql
git commit -m "feat: add bathrooms_min/built_up_sqft_min/desired_commission_split_percent/loan_ready/urgent_viewing_required to requirement table"
```

---

## Task 3: `RequirementRepository` — `updateRequirementDetails`, `countOpenRequirements`, `createRequirement`'s new params

**Files:**
- Modify: `app/lib/features/requirement/requirement_repository.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Future<void> updateRequirementDetails({required String requirementId, required String propertyType, required String transactionType, required String state, required String area, required double budgetMin, required double budgetMax, int? bedrooms, int? bathroomsMin, int? builtUpSqftMin, double? desiredCommissionSplitPercent, required bool loanReady, required bool urgentViewingRequired})`, `Future<int> countOpenRequirements()`. `createRequirement(...)` gains 5 new optional named params: `int? bathroomsMin`, `int? builtUpSqftMin`, `double? desiredCommissionSplitPercent`, `bool loanReady = false`, `bool urgentViewingRequired = false`.

- [ ] **Step 1: Read the current file**

```bash
cat "app/lib/features/requirement/requirement_repository.dart"
```

(Full current content already reproduced in this plan's own research above.)

- [ ] **Step 2: Add the 5 new optional params to `createRequirement`**

Find:
```dart
  Future<Requirement> createRequirement({
    required String negotiatorId,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double budgetMin,
    required double budgetMax,
    int? bedrooms,
  }) async {
    final row = await _client
        .from('requirement')
        .insert({
          'negotiator_id': negotiatorId,
          'property_type': propertyType,
          'transaction_type': transactionType,
          'state': state,
          'area': area,
          'budget_min': budgetMin,
          'budget_max': budgetMax,
          'bedrooms': bedrooms,
        })
        .select()
        .single();
    return Requirement.fromJson(row);
  }
```

Replace with:
```dart
  Future<Requirement> createRequirement({
    required String negotiatorId,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double budgetMin,
    required double budgetMax,
    int? bedrooms,
    int? bathroomsMin,
    int? builtUpSqftMin,
    double? desiredCommissionSplitPercent,
    bool loanReady = false,
    bool urgentViewingRequired = false,
  }) async {
    final row = await _client
        .from('requirement')
        .insert({
          'negotiator_id': negotiatorId,
          'property_type': propertyType,
          'transaction_type': transactionType,
          'state': state,
          'area': area,
          'budget_min': budgetMin,
          'budget_max': budgetMax,
          'bedrooms': bedrooms,
          'bathrooms_min': bathroomsMin,
          'built_up_sqft_min': builtUpSqftMin,
          'desired_commission_split_percent': desiredCommissionSplitPercent,
          'loan_ready': loanReady,
          'urgent_viewing_required': urgentViewingRequired,
        })
        .select()
        .single();
    return Requirement.fromJson(row);
  }
```

- [ ] **Step 3: Add `updateRequirementDetails` and `countOpenRequirements`**

Find:
```dart
  Future<void> updateRequirementStatus({required String requirementId, required String status}) {
    return _client.from('requirement').update({'status': status}).eq('requirement_id', requirementId);
  }
```

Add immediately after it:
```dart

  /// General field update for a future Requirement edit flow. No screen
  /// calls this yet in this milestone (the Buyer Match mockup shows no
  /// edit mode) -- added for symmetry with ListingRepository's own
  /// updateListingDetails. Deliberately does NOT touch requirementId,
  /// negotiatorId, status, photoUrls, or createdAt -- each has its own
  /// dedicated update path or must never change after creation.
  Future<void> updateRequirementDetails({
    required String requirementId,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double budgetMin,
    required double budgetMax,
    int? bedrooms,
    int? bathroomsMin,
    int? builtUpSqftMin,
    double? desiredCommissionSplitPercent,
    required bool loanReady,
    required bool urgentViewingRequired,
  }) {
    return _client.from('requirement').update({
      'property_type': propertyType,
      'transaction_type': transactionType,
      'state': state,
      'area': area,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      'bedrooms': bedrooms,
      'bathrooms_min': bathroomsMin,
      'built_up_sqft_min': builtUpSqftMin,
      'desired_commission_split_percent': desiredCommissionSplitPercent,
      'loan_ready': loanReady,
      'urgent_viewing_required': urgentViewingRequired,
    }).eq('requirement_id', requirementId);
  }
```

- [ ] **Step 4: Add `countOpenRequirements`**

Find:
```dart
  Future<int> countActiveRequirements(String negotiatorId) async {
    final response = await _client
        .from('requirement')
        .select('requirement_id')
        .eq('negotiator_id', negotiatorId)
        .eq('status', 'open')
        .count(CountOption.exact);
    return response.count;
  }
```

Add immediately after it:
```dart

  /// Global count of ALL open requirements regardless of owner -- powers
  /// the Buyer Match mode's "N Buyer Demands Active" ticker. NOT the same
  /// as countActiveRequirements(negotiatorId) above, which is scoped to
  /// one negotiator's own requirements for the free-tier cap check.
  Future<int> countOpenRequirements() async {
    final response = await _client.from('requirement').select('requirement_id').eq('status', 'open').count(CountOption.exact);
    return response.count;
  }
```

- [ ] **Step 5: Run analyze and the full test suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean (this is Supabase-boundary code, not unit-tested per this project's convention — manually verified once migration 0024 is live).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/requirement/requirement_repository.dart
git commit -m "feat: add updateRequirementDetails/countOpenRequirements, createRequirement's new fields"
```

---

## Task 4: `MatchingEngine` — bathroom/sqft qualifying filters (TDD)

**Files:**
- Modify: `app/lib/features/matching/matching_engine.dart`
- Modify: `app/test/features/matching/matching_engine_test.dart`

**Interfaces:**
- Consumes: `Listing.bathrooms`/`Listing.builtUpSqft` (existing), `Requirement.bathroomsMin`/`Requirement.builtUpSqftMin` (Task 1).
- Produces: `MatchingEngine.score` now also disqualifies (returns `null`) when the requirement sets a minimum the listing doesn't meet or doesn't have data for. Task 5 (live preview helper) consumes this same `score` method unchanged.

- [ ] **Step 1: Read both current files fresh**

```bash
cat "app/lib/features/matching/matching_engine.dart"
cat "app/test/features/matching/matching_engine_test.dart"
```

(Both already reproduced in this plan's own research above — confirm no drift before editing.)

- [ ] **Step 2: Write the failing tests**

Add to `app/test/features/matching/matching_engine_test.dart`, inside the existing `group('MatchingEngine.score', ...)` block, after the existing `'mismatched bedroom count scores zero for bedrooms'` test and before the `'qualifyingThreshold is 40'` test:

```dart
    test('listing meeting the requirement\'s bathroomsMin still scores normally', () {
      final listing = Listing(
        listingId: 'l-5',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        bathrooms: 2,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-4',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        bathroomsMin: 2,
      );
      expect(MatchingEngine.score(listing, requirement), 100);
    });

    test('listing below the requirement\'s bathroomsMin is disqualified', () {
      final listing = Listing(
        listingId: 'l-6',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        bathrooms: 1,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-5',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        bathroomsMin: 2,
      );
      expect(MatchingEngine.score(listing, requirement), isNull);
    });

    test('listing with unset bathrooms is disqualified when requirement sets a minimum', () {
      const requirement = Requirement(
        requirementId: 'r-6',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        bathroomsMin: 2,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('requirement with no bathroomsMin never filters on bathrooms', () {
      final listing = Listing(
        listingId: 'l-7',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      expect(MatchingEngine.score(listing, _requirement), 100);
    });

    test('listing meeting the requirement\'s builtUpSqftMin still scores normally', () {
      final listing = Listing(
        listingId: 'l-8',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        builtUpSqft: 1200,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-7',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        builtUpSqftMin: 1000,
      );
      expect(MatchingEngine.score(listing, requirement), 100);
    });

    test('listing below the requirement\'s builtUpSqftMin is disqualified', () {
      final listing = Listing(
        listingId: 'l-9',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        builtUpSqft: 800,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-8',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        builtUpSqftMin: 1000,
      );
      expect(MatchingEngine.score(listing, requirement), isNull);
    });

    test('listing with unset builtUpSqft is disqualified when requirement sets a minimum', () {
      const requirement = Requirement(
        requirementId: 'r-9',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        builtUpSqftMin: 1000,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('requirement with no builtUpSqftMin never filters on built-up size', () {
      expect(MatchingEngine.score(_listing, _requirement), 100);
    });
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd "app" && flutter test test/features/matching/matching_engine_test.dart
```

Expected: FAIL — `Requirement`'s named params `bathroomsMin`/`builtUpSqftMin` don't exist yet if Task 1 wasn't merged first (it should already be merged), and/or the disqualifying checks don't exist yet in `MatchingEngine.score`, so the "disqualified" tests currently return a non-null score instead of `null`.

- [ ] **Step 4: Implement the 2 new qualifying filters**

Replace:
```dart
  static int? score(Listing listing, Requirement requirement) {
    if (listing.transactionType != requirement.transactionType) return null;
    if (listing.state != requirement.state) return null;

    final location = listing.area.toLowerCase() == requirement.area.toLowerCase() ? 30 : 0;
```

With:
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
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd "app" && flutter test test/features/matching/matching_engine_test.dart
```

Expected: PASS, all cases (9 existing + 8 new = 17).

- [ ] **Step 6: Run `flutter analyze` and the full suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/matching/matching_engine.dart app/test/features/matching/matching_engine_test.dart
git commit -m "feat: add bathroomsMin/builtUpSqftMin as MatchingEngine qualifying filters"
```

---

## Task 5: Pure `LiveMatchPreview` helper (TDD)

**Files:**
- Create: `app/lib/features/matching/live_match_preview.dart`
- Create: `app/test/features/matching/live_match_preview_test.dart`

**Interfaces:**
- Consumes: `MatchingEngine.score` (Task 4), `MatchingEngine.qualifyingThreshold` (existing), `Listing`, `Requirement`.
- Produces: `LiveMatchPreviewResult` (record-like class: `matchCount` int, `topMatchLabel` String?, `topMatchScore` int?), `LiveMatchPreview.forRequirement(Requirement draftRequirement, List<Listing> candidates) -> LiveMatchPreviewResult`, `LiveMatchPreview.forListing(Listing draftListing, List<Requirement> candidates) -> LiveMatchPreviewResult`. Tasks 6/7 (form bodies) call these two methods directly, after fetching `candidates` themselves — this helper does no fetching, no DB writes, no notifications.

- [ ] **Step 1: Write the failing test**

Create `app/test/features/matching/live_match_preview_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/matching/live_match_preview.dart';
import 'package:renly/features/requirement/models/requirement.dart';

Listing _listing(String id, {double price = 400000, String area = 'Petaling Jaya', String title = 't'}) {
  return Listing(
    listingId: id,
    negotiatorId: 'n-owner',
    title: title,
    description: 'd',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: area,
    price: price,
    bedrooms: 3,
    photoUrls: const [],
    status: 'active',
    createdAt: DateTime(2024, 1, 1),
  );
}

const _draftRequirement = Requirement(
  requirementId: 'preview',
  negotiatorId: 'n-buyer',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  bedrooms: 3,
  photoUrls: [],
  status: 'open',
);

void main() {
  group('LiveMatchPreview.forRequirement', () {
    test('counts only candidates at or above the qualifying threshold', () {
      final candidates = [
        _listing('l-1', title: 'The Vertex Residency'),
        _listing('l-2', area: 'Shah Alam', title: 'Mismatched Area Unit'),
      ];

      final result = LiveMatchPreview.forRequirement(_draftRequirement, candidates);

      expect(result.matchCount, 1);
      expect(result.topMatchLabel, 'The Vertex Residency');
      expect(result.topMatchScore, 100);
    });

    test('zero qualifying candidates returns a zero-count result with no top match', () {
      final candidates = [_listing('l-1', area: 'Shah Alam')];

      final result = LiveMatchPreview.forRequirement(_draftRequirement, candidates);

      expect(result.matchCount, 0);
      expect(result.topMatchLabel, isNull);
      expect(result.topMatchScore, isNull);
    });

    test('picks the highest-scoring candidate as the top match', () {
      final candidates = [
        _listing('l-1', price: 600000, title: 'Over Budget Unit'),
        _listing('l-2', price: 400000, title: 'Exact Budget Unit'),
      ];

      final result = LiveMatchPreview.forRequirement(_draftRequirement, candidates);

      expect(result.matchCount, 2);
      expect(result.topMatchLabel, 'Exact Budget Unit');
      expect(result.topMatchScore, 100);
    });
  });

  group('LiveMatchPreview.forListing', () {
    test('counts only candidates at or above the qualifying threshold', () {
      final draftListing = _listing('preview', title: 'Draft Listing');
      const requirements = [
        Requirement(
          requirementId: 'r-1',
          negotiatorId: 'n-buyer-1',
          propertyType: 'apartment',
          transactionType: 'sale',
          state: 'Selangor',
          area: 'Petaling Jaya',
          budgetMin: 300000,
          budgetMax: 500000,
          bedrooms: 3,
          photoUrls: [],
          status: 'open',
        ),
        Requirement(
          requirementId: 'r-2',
          negotiatorId: 'n-buyer-2',
          propertyType: 'apartment',
          transactionType: 'sale',
          state: 'Johor',
          area: 'Johor Bahru',
          budgetMin: 300000,
          budgetMax: 500000,
          bedrooms: 3,
          photoUrls: [],
          status: 'open',
        ),
      ];

      final result = LiveMatchPreview.forListing(draftListing, requirements);

      expect(result.matchCount, 1);
      expect(result.topMatchLabel, 'apartment buyer in Petaling Jaya');
      expect(result.topMatchScore, 100);
    });

    test('zero qualifying candidates returns a zero-count result with no top match', () {
      final draftListing = _listing('preview');
      const requirements = [
        Requirement(
          requirementId: 'r-1',
          negotiatorId: 'n-buyer-1',
          propertyType: 'house',
          transactionType: 'sale',
          state: 'Selangor',
          area: 'Petaling Jaya',
          budgetMin: 300000,
          budgetMax: 500000,
          photoUrls: [],
          status: 'open',
        ),
      ];

      final result = LiveMatchPreview.forListing(draftListing, requirements);

      expect(result.matchCount, 0);
      expect(result.topMatchLabel, isNull);
      expect(result.topMatchScore, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd "app" && flutter test test/features/matching/live_match_preview_test.dart
```

Expected: FAIL — `package:renly/features/matching/live_match_preview.dart` doesn't exist yet.

- [ ] **Step 3: Implement `LiveMatchPreview`**

Create `app/lib/features/matching/live_match_preview.dart`:

```dart
import '../listing/models/listing.dart';
import '../requirement/models/requirement.dart';
import 'matching_engine.dart';

/// Real, client-side, pre-submission match preview. Reuses the exact same
/// MatchingEngine.score() already used for real post-submission matching
/// (MatchingRepository), but performs NO database writes and sends NO
/// notifications -- purely in-memory, given an already-fetched candidate
/// list, so it's directly unit-testable with zero Supabase dependency.
/// The caller (a form body) is responsible for fetching the candidate
/// list and re-invoking this on a debounced timer as the draft changes.
class LiveMatchPreview {
  LiveMatchPreview._();

  /// Scores [candidates] (real, already-active listings) against a
  /// not-yet-submitted [draftRequirement] built from the current form
  /// values. [draftRequirement]'s requirementId/negotiatorId/status are
  /// never read by MatchingEngine.score, so placeholder values are fine.
  static LiveMatchPreviewResult forRequirement(Requirement draftRequirement, List<Listing> candidates) {
    Listing? topListing;
    int? topScore;
    var matchCount = 0;
    for (final listing in candidates) {
      final score = MatchingEngine.score(listing, draftRequirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      matchCount++;
      if (topScore == null || score > topScore) {
        topScore = score;
        topListing = listing;
      }
    }
    return LiveMatchPreviewResult(
      matchCount: matchCount,
      topMatchLabel: topListing?.title,
      topMatchScore: topScore,
    );
  }

  /// Scores [candidates] (real, open requirements) against a not-yet-
  /// submitted [draftListing]. Requirement has no natural "title" field
  /// (unlike Listing), so the top match's label is synthesized from its
  /// real propertyType + area -- e.g. "apartment buyer in Petaling Jaya"
  /// -- rather than fabricating a name.
  static LiveMatchPreviewResult forListing(Listing draftListing, List<Requirement> candidates) {
    Requirement? topRequirement;
    int? topScore;
    var matchCount = 0;
    for (final requirement in candidates) {
      final score = MatchingEngine.score(draftListing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      matchCount++;
      if (topScore == null || score > topScore) {
        topScore = score;
        topRequirement = requirement;
      }
    }
    return LiveMatchPreviewResult(
      matchCount: matchCount,
      topMatchLabel: topRequirement == null ? null : '${topRequirement.propertyType} buyer in ${topRequirement.area}',
      topMatchScore: topScore,
    );
  }
}

class LiveMatchPreviewResult {
  const LiveMatchPreviewResult({required this.matchCount, this.topMatchLabel, this.topMatchScore});

  final int matchCount;
  final String? topMatchLabel;
  final int? topMatchScore;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd "app" && flutter test test/features/matching/live_match_preview_test.dart
```

Expected: PASS, 5/5.

- [ ] **Step 5: Run `flutter analyze` and the full test suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/matching/live_match_preview.dart app/test/features/matching/live_match_preview_test.dart
git commit -m "feat: add pure LiveMatchPreview helper for pre-submission match preview"
```

---

## Task 6: Extract `PostListingScreen` into `PostListingFormBody` + real preview/ticker/copy fixes

**Files:**
- Modify: `app/lib/features/listing/post_listing_screen.dart`
- Modify: `app/test/features/listing/post_listing_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `LiveMatchPreview.forListing` (Task 5), `requirementRepositoryProvider`/`RequirementRepository.fetchBoardRequirements` (existing), `marketplaceListingsProvider` (existing — its `.length` already backs Marketplace's own ticker; reused here for "N Active Co-Broke Listings").
- Produces: `PostListingFormBody` widget (replaces the public `PostListingScreen` class — same constructor params `editListingId`/`initialDraft`, no `Scaffold`/`AppBar` of its own). Task 8 (`PostBroadcastScreen`) instantiates this directly inside its `IndexedStack`.

- [ ] **Step 1: Read the current file fresh**

```bash
cat "app/lib/features/listing/post_listing_screen.dart"
```

(Full current content already reproduced in this plan's own research above — 583 lines. Re-read now to confirm no drift.)

- [ ] **Step 2: Rename the class and remove its own `Scaffold`/`AppBar`**

Replace the file's class declaration and `build()` method's outer wrapper. Find:
```dart
class PostListingScreen extends ConsumerStatefulWidget {
  const PostListingScreen({super.key, this.editListingId, this.initialDraft});

  final String? editListingId;
  final ListingDraft? initialDraft;

  @override
  ConsumerState<PostListingScreen> createState() => _PostListingScreenState();
}

class _PostListingScreenState extends ConsumerState<PostListingScreen> {
```

Replace with:
```dart
class PostListingFormBody extends ConsumerStatefulWidget {
  const PostListingFormBody({super.key, this.editListingId, this.initialDraft});

  final String? editListingId;
  final ListingDraft? initialDraft;

  @override
  ConsumerState<PostListingFormBody> createState() => _PostListingFormBodyState();
}

class _PostListingFormBodyState extends ConsumerState<PostListingFormBody> {
```

Find the `build()` method's outer wrapper:
```dart
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
```

Replace with:
```dart
    if (_isEditMode) {
      final listingAsync = ref.watch(listingDetailProvider(widget.editListingId!));
      listingAsync.whenData(_prefillFromListing);
      if (listingAsync.isLoading && !_prefilledFromListing) {
        return const Center(child: CircularProgressIndicator());
      }
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
```

The `build()` method's final closing brackets need exactly one fewer closing paren, since the outer `Scaffold(...)` wrapper is gone (its `body:` param — `SafeArea(...)` — is now the directly-returned widget, which closes with `;` instead of a further `),` + `);` pair). Find the file's exact final lines:
```dart
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

Replace with:
```dart
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
      );
  }
}
```

(The old block has 6 closing lines after the children list's own `],`: `),` closes `Column`, `),` closes `Form`, `),` closes `SingleChildScrollView`, `),` closes `SafeArea`, `);` closes `Scaffold` — 5 closing constructs. The new block has 5 closing lines: `),`/`),`/`),`/`);` closing `Column`/`Form`/`SingleChildScrollView`/`SafeArea` — 4 closing constructs, exactly one fewer, matching the removed `Scaffold` wrapper. After this edit, run `flutter analyze` — a mismatched-paren error here is immediately obvious and easy to fix by re-counting against this exact explanation if the automatic edit tool's context match required adjusting surrounding lines slightly.)

- [ ] **Step 3: Add the location quick-fill pills**

Find the area field:
```dart
                TextFormField(
                  key: const Key('listing_area_field'),
                  controller: _areaController,
                  decoration: InputDecoration(labelText: 'listing_field_area'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
```

Replace with:
```dart
                TextFormField(
                  key: const Key('listing_area_field'),
                  controller: _areaController,
                  decoration: InputDecoration(labelText: 'listing_field_area'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final area in const ['Mont Kiara', 'KLCC', 'Bangsar', 'Petaling Jaya'])
                      ActionChip(
                        label: Text(area, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => _areaController.text = area),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
```

- [ ] **Step 4: Fix the self-attestation copy honesty (already correct in this file)**

Read the current toggle block:
```dart
                Text('listing_self_attestation_notice'.tr(), style: Theme.of(context).textTheme.labelSmall),
                SwitchListTile(
                  key: const Key('listing_title_verified_switch'),
```

This file's own self-attestation notice + first-person captions were ALREADY fixed correctly during the My Inventory Premium Restyle milestone earlier this session (the design doc's honesty-framing concern was about the STITCH MOCKUP's captions, not this file's own already-correct implementation) — **no change needed here**. Confirm this by re-reading the block and moving on; do not re-apply a fix that's already present.

- [ ] **Step 5: Add the real live match preview + real ticker**

Add new state fields near the top of `_PostListingFormBodyState`, right after the existing controller declarations:
```dart
  Timer? _previewDebounce;
  List<Requirement>? _previewCandidates;
  LiveMatchPreviewResult _previewResult = const LiveMatchPreviewResult(matchCount: 0);
```

Add the new imports at the top of the file:
```dart
import 'dart:async';

import '../matching/live_match_preview.dart';
import '../requirement/models/requirement.dart';
import '../requirement/requirement_providers.dart';
```

In `initState()`, after the existing draft-prefill logic, add:
```dart
    ref.read(requirementRepositoryProvider).fetchBoardRequirements().then((requirements) {
      if (!mounted) return;
      setState(() {
        _previewCandidates = requirements;
        _recomputePreview();
      });
    });
    for (final controller in [_areaController, _priceController, _bedroomsController, _bathroomsController, _sqftController]) {
      controller.addListener(_onPreviewFieldChanged);
    }
```

Add these 2 new methods right after `_saveAsDraft()`:
```dart
  void _onPreviewFieldChanged() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(_recomputePreview);
    });
  }

  void _recomputePreview() {
    final candidates = _previewCandidates;
    if (candidates == null) return;
    final price = double.tryParse(_priceController.text.trim());
    if (price == null) {
      _previewResult = const LiveMatchPreviewResult(matchCount: 0);
      return;
    }
    final draftListing = Listing(
      listingId: 'preview',
      negotiatorId: ref.read(currentNegotiatorIdProvider) ?? 'preview',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      propertyType: _propertyType,
      transactionType: _transactionType,
      state: _state,
      area: _areaController.text.trim(),
      price: price,
      bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.tryParse(_bedroomsController.text.trim()),
      bathrooms: _bathroomsController.text.trim().isEmpty ? null : int.tryParse(_bathroomsController.text.trim()),
      builtUpSqft: _sqftValue,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime.now(),
    );
    _previewResult = LiveMatchPreview.forListing(draftListing, candidates);
  }
```

Update `dispose()` to cancel the timer and remove the listeners:
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
    super.dispose();
  }
```

Add the preview card right before the submit button. Find:
```dart
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                BrutalistButton(
                  label: _isEditMode ? 'listing_save_changes'.tr() : 'listing_post_now'.tr(),
                  onPressed: (_submitting || atCap) ? null : _submit,
                ),
```

Replace with:
```dart
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (_previewResult.matchCount > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('listing_preview_radar_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          'listing_preview_match_count'.tr(namedArgs: {'count': '${_previewResult.matchCount}'}),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_previewResult.topMatchLabel != null)
                          Text(
                            _previewResult.topMatchLabel!,
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                BrutalistButton(
                  label: _isEditMode ? 'listing_save_changes'.tr() : 'listing_post_now'.tr(),
                  onPressed: (_submitting || atCap) ? null : _submit,
                ),
```

**Ticker:** the ticker itself is rendered by `PostBroadcastScreen` (Task 8), not this form body — this task only needs to make the real count SOURCE available, which it already is (`marketplaceListingsProvider`, existing, unchanged). No further action needed in this file for the ticker.

- [ ] **Step 6: Update `post_listing_screen_test.dart`**

Read the current file (already reproduced in this plan's own research above). Every `PostListingScreen(...)` route-builder construction needs to become `Scaffold(body: PostListingFormBody(...))`, since `PostListingFormBody` no longer provides its own `Scaffold`. Apply this replacement at all 5 route-builder call sites in the file:

Find (appears once, in `'renders all required fields'`):
```dart
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
```
Replace with:
```dart
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
```

Apply the identical replacement in `'submitting with empty required fields shows validation errors'`, `'shows active count and disables submit at the free-tier cap'`, and `'does not block submit for a professional-tier negotiator even at 3 active listings'` (4 occurrences total of the plain no-param case).

Find (in `'edit mode pre-fills fields...'`):
```dart
      GoRoute(
        path: '/',
        builder: (context, state) => const PostListingScreen(editListingId: 'l-1'),
      ),
```
Replace with:
```dart
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: PostListingFormBody(editListingId: 'l-1')),
      ),
```

Update the import at the top of the file:
```dart
import 'package:renly/features/listing/post_listing_screen.dart';
```
stays the same import path (the file wasn't renamed, only the class inside it) — `PostListingFormBody` is exported from the same `post_listing_screen.dart` file, no import change needed.

- [ ] **Step 7: Add the new l10n keys**

In `app/assets/translations/en.json`, find `"listing_field_sqft": "Built-up Size (sqft)",` and add nearby:
```json
  "listing_preview_radar_label": "Preliminary Match Radar",
  "listing_preview_match_count": "Matches {count} buyer requirement(s)",
```

In `app/assets/translations/ms.json`, add the mirrored keys:
```json
  "listing_preview_radar_label": "Radar Padanan Awal",
  "listing_preview_match_count": "Sepadan dengan {count} keperluan pembeli",
```

(Check the exact neighboring line via `grep -n "listing_field_sqft" app/assets/translations/en.json app/assets/translations/ms.json` first — insert at that position.)

- [ ] **Step 8: Run `flutter analyze` and the test file**

```bash
cd "app" && flutter analyze && flutter test test/features/listing/post_listing_screen_test.dart
```

Expected: both clean, all 5 existing tests pass unchanged (they test fields by `Key`, unaffected by the `Scaffold` wrapper move).

- [ ] **Step 9: Run the full suite**

```bash
cd "app" && flutter test
```

Expected: all pass. (`app_router.dart` still references the old `PostListingScreen` class name at this point in the plan — Task 8 updates the router; until then, `flutter analyze` on the whole app will show an error on `app_router.dart`'s existing `PostListingScreen(...)` call sites since that class no longer exists. **This is expected and acceptable for this one task** — Task 8, immediately next, fixes the router. If your environment insists on a fully-green `flutter analyze` before every commit, temporarily rename `app_router.dart`'s 3 call sites from `PostListingScreen(...)`/`PostRequirementScreen(...)` to placeholder text is NOT an option per this plan's no-placeholders rule — instead, do Task 6, Task 7, and Task 8 as one continuous work session before running the full-app `flutter analyze`, OR accept that `flutter analyze` shows exactly 3 known errors in `app_router.dart` between Task 6 and Task 8's completion, and verify this task's own test file passes in isolation via `flutter test test/features/listing/post_listing_screen_test.dart` instead of the whole-app command.)

- [ ] **Step 10: Commit**

```bash
git add app/lib/features/listing/post_listing_screen.dart app/test/features/listing/post_listing_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: extract PostListingScreen into Scaffold-less PostListingFormBody, add live match preview + quick-fill pills"
```

---

## Task 7: Build `PostRequirementFormBody` — new fields + real preview/ticker

**Files:**
- Modify: `app/lib/features/requirement/post_requirement_screen.dart`
- Modify: `app/test/features/requirement/post_requirement_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `LiveMatchPreview.forRequirement` (Task 5), `listingRepositoryProvider`/`ListingRepository.fetchMarketplaceListings` (existing), `RequirementRepository.createRequirement`'s new params (Task 3).
- Produces: `PostRequirementFormBody` widget (replaces the public `PostRequirementScreen` class, no `Scaffold`/`AppBar` of its own). Task 8 instantiates this directly inside its `IndexedStack`.

- [ ] **Step 1: Read the current file fresh**

```bash
cat "app/lib/features/requirement/post_requirement_screen.dart"
```

(Full current content already reproduced in this plan's own research above — 341 lines.)

- [ ] **Step 2: Add the new l10n keys**

In `app/assets/translations/en.json`, find `"requirement_photos_max": "Max 3",` and add nearby:
```json
  "requirement_field_bathrooms_min": "Min Bathrooms",
  "requirement_field_sqft_min": "Min Built-up (sqft)",
  "requirement_field_commission_split": "Desired Co-Broke Split (%)",
  "requirement_field_loan_ready": "I confirm I am pre-approved for a loan or a cash-ready buyer",
  "requirement_field_urgent_viewing": "I confirm I need viewings within 48 hours",
  "requirement_preview_radar_label": "Preliminary Match Radar",
  "requirement_preview_match_count": "Matches {count} active listing(s)",
```

In `app/assets/translations/ms.json`, add the mirrored keys:
```json
  "requirement_field_bathrooms_min": "Min Bilik Air",
  "requirement_field_sqft_min": "Min Binaan (kaki persegi)",
  "requirement_field_commission_split": "Split Co-Broke Dikehendaki (%)",
  "requirement_field_loan_ready": "Saya sahkan saya sudah pra-lulus pinjaman atau pembeli tunai bersedia",
  "requirement_field_urgent_viewing": "Saya sahkan saya perlukan tayangan dalam masa 48 jam",
  "requirement_preview_radar_label": "Radar Padanan Awal",
  "requirement_preview_match_count": "Sepadan dengan {count} senarai aktif",
```

- [ ] **Step 3: Rename the class, remove its own `Scaffold`/`AppBar`, add the new fields**

Replace the whole file:

```dart
// app/lib/features/requirement/post_requirement_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/malaysian_states.dart';
import '../../core/widgets/brutalist_button.dart';
import '../listing/listing_providers.dart';
import '../listing/models/listing.dart';
import '../matching/live_match_preview.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import 'models/requirement.dart';
import 'requirement_providers.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

class PostRequirementFormBody extends ConsumerStatefulWidget {
  const PostRequirementFormBody({super.key});

  @override
  ConsumerState<PostRequirementFormBody> createState() => _PostRequirementFormBodyState();
}

class _PostRequirementFormBodyState extends ConsumerState<PostRequirementFormBody> {
  static const _maxPhotos = 3;

  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();
  final _budgetMinController = TextEditingController();
  final _budgetMaxController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsMinController = TextEditingController();
  final _sqftMinController = TextEditingController();
  final _commissionSplitController = TextEditingController();
  String _propertyType = 'apartment';
  String _transactionType = 'sale';
  String _state = malaysianStates.first;
  bool _loanReady = false;
  bool _urgentViewingRequired = false;
  final List<XFile> _photos = [];
  bool _submitting = false;
  String? _submitError;

  /// Same retry-safety as PostListingFormBody: set once createRequirement()
  /// succeeds, so a retry after a failed photo upload resumes from the
  /// upload step instead of inserting a second row.
  String? _createdRequirementId;

  Timer? _previewDebounce;
  List<Listing>? _previewCandidates;
  LiveMatchPreviewResult _previewResult = const LiveMatchPreviewResult(matchCount: 0);

  @override
  void initState() {
    super.initState();
    ref.read(listingRepositoryProvider).fetchMarketplaceListings().then((listings) {
      if (!mounted) return;
      setState(() {
        _previewCandidates = listings;
        _recomputePreview();
      });
    });
    for (final controller in [_areaController, _budgetMinController, _budgetMaxController, _bedroomsController, _bathroomsMinController, _sqftMinController]) {
      controller.addListener(_onPreviewFieldChanged);
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    for (final controller in [_areaController, _budgetMinController, _budgetMaxController, _bedroomsController, _bathroomsMinController, _sqftMinController]) {
      controller.removeListener(_onPreviewFieldChanged);
    }
    _areaController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    _bedroomsController.dispose();
    _bathroomsMinController.dispose();
    _sqftMinController.dispose();
    _commissionSplitController.dispose();
    super.dispose();
  }

  void _onPreviewFieldChanged() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(_recomputePreview);
    });
  }

  void _recomputePreview() {
    final candidates = _previewCandidates;
    if (candidates == null) return;
    final budgetMin = double.tryParse(_budgetMinController.text.trim());
    final budgetMax = double.tryParse(_budgetMaxController.text.trim());
    if (budgetMin == null || budgetMax == null) {
      _previewResult = const LiveMatchPreviewResult(matchCount: 0);
      return;
    }
    final draftRequirement = Requirement(
      requirementId: 'preview',
      negotiatorId: ref.read(currentNegotiatorIdProvider) ?? 'preview',
      propertyType: _propertyType,
      transactionType: _transactionType,
      state: _state,
      area: _areaController.text.trim(),
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.tryParse(_bedroomsController.text.trim()),
      photoUrls: const [],
      status: 'open',
      bathroomsMin: _bathroomsMinController.text.trim().isEmpty ? null : int.tryParse(_bathroomsMinController.text.trim()),
      builtUpSqftMin: _sqftMinController.text.trim().isEmpty ? null : int.tryParse(_sqftMinController.text.trim()),
    );
    _previewResult = LiveMatchPreview.forRequirement(draftRequirement, candidates);
  }

  Future<void> _pickPhotos() async {
    final remaining = _maxPhotos - _photos.length;
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

  /// Keyed on XFile.path rather than the list index -- same reasoning as
  /// PostListingFormBody's cache: removing a photo shouldn't shift every
  /// later thumbnail onto the wrong cached bytes.
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final repository = ref.read(requirementRepositoryProvider);
    try {
      if (_createdRequirementId == null) {
        final requirement = await repository.createRequirement(
          negotiatorId: negotiatorId,
          propertyType: _propertyType,
          transactionType: _transactionType,
          state: _state,
          area: _areaController.text.trim(),
          budgetMin: double.parse(_budgetMinController.text.trim()),
          budgetMax: double.parse(_budgetMaxController.text.trim()),
          bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.parse(_bedroomsController.text.trim()),
          bathroomsMin: _bathroomsMinController.text.trim().isEmpty ? null : int.parse(_bathroomsMinController.text.trim()),
          builtUpSqftMin: _sqftMinController.text.trim().isEmpty ? null : int.parse(_sqftMinController.text.trim()),
          desiredCommissionSplitPercent: _commissionSplitValue,
          loanReady: _loanReady,
          urgentViewingRequired: _urgentViewingRequired,
        );
        _createdRequirementId = requirement.requirementId;
      }
      final requirementId = _createdRequirementId!;

      final photoUrls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        final path = await repository.uploadRequirementPhoto(
          negotiatorId: negotiatorId,
          requirementId: requirementId,
          index: i,
          bytes: bytes,
        );
        photoUrls.add(path);
      }
      if (photoUrls.isNotEmpty) {
        await repository.updateRequirementPhotos(requirementId: requirementId, photoUrls: photoUrls);
      }

      ref.invalidate(boardRequirementsProvider);
      ref.invalidate(myRequirementsProvider(negotiatorId));
      ref.invalidate(activeRequirementCountProvider(negotiatorId));

      try {
        final createdRequirement = await repository.fetchRequirementById(requirementId);
        await ref.read(matchingRepositoryProvider).computeAndStoreMatchesForRequirement(createdRequirement);
        ref.invalidate(myMatchesProvider);
        ref.invalidate(matchesForListingProvider);
        ref.invalidate(matchesForRequirementProvider);
      } catch (_) {
        // Best-effort, same reasoning as PostListingFormBody.
      }

      if (!mounted) return;
      context.go('/my-requirements');
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
        : ref.watch(activeRequirementCountProvider(negotiatorId));
    final activeCount = countAsync.valueOrNull ?? 0;
    final atCap = tierAsync.valueOrNull?.tier == 'free' && activeCount >= 3;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('requirement_property_type_field'),
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
                key: const Key('requirement_transaction_type_field'),
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
                key: const Key('requirement_state_field'),
                initialValue: _state,
                decoration: InputDecoration(labelText: 'listing_field_state'.tr()),
                items: [
                  for (final state in malaysianStates) DropdownMenuItem(value: state, child: Text(state)),
                ],
                onChanged: (value) => setState(() => _state = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('requirement_area_field'),
                controller: _areaController,
                decoration: InputDecoration(labelText: 'listing_field_area'.tr()),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final area in const ['Mont Kiara', 'KLCC', 'Bangsar', 'Petaling Jaya'])
                    ActionChip(
                      label: Text(area, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _areaController.text = area),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('requirement_budget_min_field'),
                controller: _budgetMinController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'requirement_field_budget_min'.tr()),
                validator: (value) {
                  final requiredError = _requiredValidator(value);
                  if (requiredError != null) return requiredError;
                  if (double.tryParse(value!.trim()) == null) return 'validation_required'.tr();
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('requirement_budget_max_field'),
                controller: _budgetMaxController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'requirement_field_budget_max'.tr()),
                validator: (value) {
                  final requiredError = _requiredValidator(value);
                  if (requiredError != null) return requiredError;
                  final max = double.tryParse(value!.trim());
                  if (max == null) return 'validation_required'.tr();
                  final min = double.tryParse(_budgetMinController.text.trim());
                  if (min != null && max < min) return 'requirement_budget_max_below_min'.tr();
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
                      key: const Key('requirement_bathrooms_min_field'),
                      controller: _bathroomsMinController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'requirement_field_bathrooms_min'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('requirement_sqft_min_field'),
                      controller: _sqftMinController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'requirement_field_sqft_min'.tr()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('requirement_commission_split_field'),
                controller: _commissionSplitController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'requirement_field_commission_split'.tr()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null || parsed <= 0 || parsed > 100) return 'validation_required'.tr();
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text('listing_self_attestation_notice'.tr(), style: Theme.of(context).textTheme.labelSmall),
              SwitchListTile(
                key: const Key('requirement_loan_ready_switch'),
                contentPadding: EdgeInsets.zero,
                title: Text('requirement_field_loan_ready'.tr()),
                value: _loanReady,
                onChanged: (value) => setState(() => _loanReady = value),
              ),
              SwitchListTile(
                key: const Key('requirement_urgent_viewing_switch'),
                contentPadding: EdgeInsets.zero,
                title: Text('requirement_field_urgent_viewing'.tr()),
                value: _urgentViewingRequired,
                onChanged: (value) => setState(() => _urgentViewingRequired = value),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('listing_photos_label'.tr()),
                  Text('requirement_photos_max'.tr()),
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
                  if (_photos.length < _maxPhotos)
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
              if (tierAsync.valueOrNull?.tier == 'free') ...[
                const SizedBox(height: 12),
                Text('$activeCount/3 ${'requirement_active_count_label'.tr()}'),
              ],
              if (atCap) ...[
                const SizedBox(height: 8),
                Text(
                  'requirement_cap_reached_message'.tr(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_previewResult.matchCount > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('requirement_preview_radar_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Text(
                        'requirement_preview_match_count'.tr(namedArgs: {'count': '${_previewResult.matchCount}'}),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (_previewResult.topMatchLabel != null)
                        Text(
                          _previewResult.topMatchLabel!,
                          style: Theme.of(context).textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              BrutalistButton(
                label: 'requirement_post_now'.tr(),
                onPressed: (_submitting || atCap) ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Update `post_requirement_screen_test.dart`**

Read the current file (already reproduced in this plan's own research above). Every `PostRequirementScreen()` route-builder construction becomes `Scaffold(body: PostRequirementFormBody())`.

Find (appears 5 times across the file's 5 tests):
```dart
      GoRoute(path: '/', builder: (context, state) => const PostRequirementScreen()),
```
Replace ALL 5 occurrences with:
```dart
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
```

The import stays the same path:
```dart
import 'package:renly/features/requirement/post_requirement_screen.dart';
```

Two of the 5 existing tests (`'submitting with empty required fields shows validation errors'` and `'shows inline error when max budget is below min budget'`) scroll via `tester.drag(scrollable, const Offset(0, -600))` before tapping the submit button — this form is now noticeably taller (3 new fields + 2 new toggles + the notice text), so this fixed-offset drag may under-scroll and miss the button, the same class of problem `post_listing_screen_test.dart` already hit and fixed with `ensureVisible` earlier this session. Replace both occurrences of:
```dart
    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Post Requirement'));
```
with:
```dart
    await tester.ensureVisible(find.widgetWithText(BrutalistButton, 'Post Requirement'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Post Requirement'));
```

- [ ] **Step 5: Run `flutter analyze` and the test file**

```bash
cd "app" && flutter analyze && flutter test test/features/requirement/post_requirement_screen_test.dart
```

Expected: the test file's own 5 tests pass. `flutter analyze` on the whole app still shows the same 3 known `app_router.dart` errors described in Task 6 Step 9 (both `PostListingScreen` and `PostRequirementScreen` no longer exist) — expected until Task 8.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/requirement/post_requirement_screen.dart app/test/features/requirement/post_requirement_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: extract PostRequirementScreen into Scaffold-less PostRequirementFormBody, add min-specs/split/readiness fields + live match preview"
```

---

## Task 8: `PostBroadcastScreen` wrapper + router update

**Files:**
- Create: `app/lib/features/listing/post_broadcast_screen.dart`
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `PostListingFormBody` (Task 6), `PostRequirementFormBody` (Task 7), `marketplaceListingsProvider` (existing, its `.length` backs "N Active Co-Broke Listings"), `RequirementRepository.countOpenRequirements` (Task 3, backs "N Buyer Demands Active").
- Produces: `PostBroadcastScreen` widget (`initialMode`, `editListingId`, `initialDraft` constructor params), `PostBroadcastMode` enum. Every route in `app_router.dart` that used to build `PostListingScreen`/`PostRequirementScreen` now builds this instead.

- [ ] **Step 1: Add the new l10n keys**

In `app/assets/translations/en.json`, find `"listing_post_title": "Post a Listing",` and add nearby:
```json
  "broadcast_provide_listing_tab": "Provide Listing",
  "broadcast_buyer_match_tab": "Buyer Match",
  "broadcast_active_listings_ticker": "{count} Active Co-Broke Listings",
  "broadcast_buyer_demands_ticker": "{count} Buyer Demands Active",
```

In `app/assets/translations/ms.json`, add the mirrored keys:
```json
  "broadcast_provide_listing_tab": "Sedia Senarai",
  "broadcast_buyer_match_tab": "Padanan Pembeli",
  "broadcast_active_listings_ticker": "{count} Senarai Co-Broke Aktif",
  "broadcast_buyer_demands_ticker": "{count} Permintaan Pembeli Aktif",
```

- [ ] **Step 2: Add a provider for the open-requirements count**

In `app/lib/features/requirement/requirement_providers.dart`, read the current file first:

```bash
cat "app/lib/features/requirement/requirement_providers.dart"
```

Find the existing `boardRequirementsProvider` declaration (already confirmed this session: `final boardRequirementsProvider = FutureProvider<List<Requirement>>((ref) { ... });`) and add immediately after it:

```dart
final openRequirementsCountProvider = FutureProvider<int>((ref) {
  return ref.watch(requirementRepositoryProvider).countOpenRequirements();
});
```

- [ ] **Step 3: Create `PostBroadcastScreen`**

Create `app/lib/features/listing/post_broadcast_screen.dart`:

```dart
// app/lib/features/listing/post_broadcast_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/r_star_badge.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import '../requirement/post_requirement_screen.dart';
import '../requirement/requirement_providers.dart';
import 'listing_providers.dart';
import 'models/listing_draft.dart';
import 'post_listing_screen.dart';

enum PostBroadcastMode { listing, requirement }

/// Merges PostListingFormBody and PostRequirementFormBody behind a real
/// "Provide Listing / Buyer Match" toggle, per the Post Broadcast design
/// doc. Each form body keeps its OWN State object (created once, kept
/// alive by IndexedStack) -- this screen owns only the shared chrome
/// (header/ticker/toggle), never either form's fields/validation/submit
/// logic, to avoid any regression risk to the already-tested forms.
class PostBroadcastScreen extends ConsumerStatefulWidget {
  const PostBroadcastScreen({
    super.key,
    this.initialMode = PostBroadcastMode.listing,
    this.editListingId,
    this.initialDraft,
  });

  final PostBroadcastMode initialMode;
  final String? editListingId;
  final ListingDraft? initialDraft;

  @override
  ConsumerState<PostBroadcastScreen> createState() => _PostBroadcastScreenState();
}

class _PostBroadcastScreenState extends ConsumerState<PostBroadcastScreen> {
  late PostBroadcastMode _mode = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.editListingId == null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
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
          ],
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final profileAsync = ref.watch(myProfileProvider);
              return profileAsync.maybeWhen(
                data: (profile) => profile.renNumber == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Container(
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
                              Text('REN ${profile.renNumber}', style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final unreadCount = ref.watch(unreadNotificationCountProvider);
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(PhosphorIcons.bellSimple(PhosphorIconsStyle.bold)),
                    onPressed: () {},
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
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (showToggle) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _ModeToggle(mode: _mode, onChanged: (mode) => setState(() => _mode = mode)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _mode == PostBroadcastMode.listing ? const _ActiveListingsTicker() : const _BuyerDemandsTicker(),
            ),
          ],
          Expanded(
            child: IndexedStack(
              index: _mode == PostBroadcastMode.listing ? 0 : 1,
              children: [
                PostListingFormBody(editListingId: widget.editListingId, initialDraft: widget.initialDraft),
                const PostRequirementFormBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final PostBroadcastMode mode;
  final ValueChanged<PostBroadcastMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEBECE7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(child: _ToggleButton(
            label: 'broadcast_provide_listing_tab'.tr(),
            icon: PhosphorIcons.building(PhosphorIconsStyle.bold),
            selected: mode == PostBroadcastMode.listing,
            onTap: () => onChanged(PostBroadcastMode.listing),
          )),
          Expanded(child: _ToggleButton(
            label: 'broadcast_buyer_match_tab'.tr(),
            icon: PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
            selected: mode == PostBroadcastMode.requirement,
            onTap: () => onChanged(PostBroadcastMode.requirement),
          )),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? AppColors.primary : const Color(0xFF4B5563)),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? AppColors.primary : const Color(0xFF4B5563),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveListingsTicker extends ConsumerWidget {
  const _ActiveListingsTicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final count = listingsAsync.valueOrNull?.length ?? 0;
    return _TickerBar(text: 'broadcast_active_listings_ticker'.tr(namedArgs: {'count': '$count'}));
  }
}

class _BuyerDemandsTicker extends ConsumerWidget {
  const _BuyerDemandsTicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(openRequirementsCountProvider);
    final count = countAsync.valueOrNull ?? 0;
    return _TickerBar(text: 'broadcast_buyer_demands_ticker'.tr(namedArgs: {'count': '$count'}));
  }
}

class _TickerBar extends StatelessWidget {
  const _TickerBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Update `app_router.dart`'s 3 routes**

Find:
```dart
      GoRoute(
        path: '/post-listing',
        builder: (context, state) => PostListingScreen(initialDraft: state.extra as ListingDraft?),
      ),
      GoRoute(
        path: '/property/:listingId/edit',
        builder: (context, state) => PostListingScreen(editListingId: state.pathParameters['listingId']),
      ),
```

Replace with:
```dart
      GoRoute(
        path: '/post-listing',
        builder: (context, state) => PostBroadcastScreen(initialDraft: state.extra as ListingDraft?),
      ),
      GoRoute(
        path: '/property/:listingId/edit',
        builder: (context, state) => PostBroadcastScreen(editListingId: state.pathParameters['listingId']),
      ),
```

Find:
```dart
      GoRoute(path: '/post-requirement', builder: (context, state) => const PostRequirementScreen()),
```

Replace with:
```dart
      GoRoute(
        path: '/post-requirement',
        builder: (context, state) => const PostBroadcastScreen(initialMode: PostBroadcastMode.requirement),
      ),
```

Update the imports at the top of `app_router.dart`. Find:
```dart
import '../../features/listing/post_listing_screen.dart';
```

Replace with:
```dart
import '../../features/listing/post_broadcast_screen.dart';
```

Find:
```dart
import '../../features/requirement/post_requirement_screen.dart';
```

This import is no longer needed directly in the router (the router now only builds `PostBroadcastScreen`, which internally imports `post_requirement_screen.dart` itself) — **delete this import line** if `PostRequirementScreen`/`PostRequirementFormBody` has no other direct reference remaining in `app_router.dart` (grep to confirm before deleting):
```bash
grep -n "PostRequirementScreen\|PostRequirementFormBody" app/lib/core/router/app_router.dart
```
If the grep returns only the import line itself (no other usage), delete it. `post_listing_screen.dart`'s import is also no longer directly needed by the router for the SAME reason — check with:
```bash
grep -n "PostListingScreen\|PostListingFormBody" app/lib/core/router/app_router.dart
```
If that grep returns nothing after the 2 route replacements above, this import can also be removed (replaced entirely by the `post_broadcast_screen.dart` import already added).

- [ ] **Step 5: Run `flutter analyze`**

```bash
cd "app" && flutter analyze
```

Expected: `No issues found!` — this is the first point since Task 6 where the whole app should analyze clean again (both known `app_router.dart` errors from Tasks 6/7 are now fixed).

- [ ] **Step 6: Run the full test suite**

```bash
cd "app" && flutter test
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/listing/post_broadcast_screen.dart app/lib/features/requirement/requirement_providers.dart app/lib/core/router/app_router.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add PostBroadcastScreen (Provide Listing/Buyer Match toggle), wire into router"
```

---

## Task 9: Widget tests for `PostBroadcastScreen`

**Files:**
- Create: `app/test/features/listing/post_broadcast_screen_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-8.
- Produces: nothing for later tasks — this is the final task.

- [ ] **Step 1: Write the test file**

Create `app/test/features/listing/post_broadcast_screen_test.dart`:

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
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/post_broadcast_screen.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';
import 'package:renly/features/requirement/requirement_providers.dart';

Future<void> _pumpScreen(WidgetTester tester, {required List<Override> overrides, PostBroadcastMode initialMode = PostBroadcastMode.listing, String? editListingId}) async {
  // Widened for the same reason every other tall-card/tall-form screen this
  // session needed it: the default 800x600 test surface is too short to
  // mount this screen's genuinely long form content.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => PostBroadcastScreen(initialMode: initialMode, editListingId: editListingId),
    ),
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

List<Override> _baseOverrides() => [
      myProfileProvider.overrideWith((ref) async => const Profile(
            negotiatorId: 'n-1',
            fullName: 'Aiman Yusof',
            verificationStatus: 'approved',
          )),
      unreadNotificationCountProvider.overrideWith((ref) => 0),
      marketplaceListingsProvider.overrideWith((ref) async => []),
      openRequirementsCountProvider.overrideWith((ref) async => 0),
      boardRequirementsProvider.overrideWith((ref) async => []),
    ];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('defaults to the Provide Listing tab and shows the listing form', (tester) async {
    await _pumpScreen(tester, overrides: _baseOverrides());

    expect(find.byKey(const Key('listing_title_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_property_type_field')), findsNothing);
  });

  testWidgets('initialMode requirement shows the Buyer Match form instead', (tester) async {
    await _pumpScreen(tester, overrides: _baseOverrides(), initialMode: PostBroadcastMode.requirement);

    expect(find.byKey(const Key('requirement_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_title_field')), findsNothing);
  });

  testWidgets('tapping the toggle switches the visible form and preserves typed text', (tester) async {
    await _pumpScreen(tester, overrides: _baseOverrides());

    await tester.enterText(find.byKey(const Key('listing_title_field')), 'My Draft Title');
    await tester.pumpAndSettle();

    await tester.tap(find.text('broadcast_buyer_match_tab'.tr()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('requirement_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_title_field')), findsNothing);

    await tester.tap(find.text('broadcast_provide_listing_tab'.tr()));
    await tester.pumpAndSettle();

    final titleField = tester.widget<TextFormField>(find.byKey(const Key('listing_title_field')));
    expect(titleField.controller?.text, 'My Draft Title');
  });

  testWidgets('toggle is hidden entirely in edit mode', (tester) async {
    await _pumpScreen(
      tester,
      overrides: [
        ..._baseOverrides(),
        currentNegotiatorIdProvider.overrideWith((ref) => 'n-1'),
        listingDetailProvider('l-1').overrideWith((ref) async => Listing(
              listingId: 'l-1',
              negotiatorId: 'n-1',
              title: 'Existing',
              description: 'd',
              propertyType: 'apartment',
              transactionType: 'sale',
              state: 'Selangor',
              area: 'Shah Alam',
              price: 500000,
              photoUrls: const [],
              status: 'active',
              createdAt: DateTime(2024, 1, 1),
            )),
      ],
      editListingId: 'l-1',
    );

    expect(find.text('broadcast_provide_listing_tab'.tr()), findsNothing);
    expect(find.text('broadcast_buyer_match_tab'.tr()), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test file**

```bash
cd "app" && flutter test test/features/listing/post_broadcast_screen_test.dart
```

Expected: PASS, 4/4. If the toggle-switch test fails because `IndexedStack` doesn't actually preserve `TextEditingController` state the way expected (it should, since the `State` object itself is preserved, only the `RenderObject` visibility changes) — if it does fail, read the actual error before assuming the cause; this is exactly the property the whole `IndexedStack` design choice depends on, so a failure here means investigating that design point directly, not just patching the test.

- [ ] **Step 3: Run `flutter analyze` and the full suite**

```bash
cd "app" && flutter analyze && flutter test
```

Expected: both clean.

- [ ] **Step 4: Commit**

```bash
git add app/test/features/listing/post_broadcast_screen_test.dart
git commit -m "test: add widget tests for PostBroadcastScreen toggle/state-preservation/edit-mode"
```

---

## Manual verification (after all tasks, and after migration 0024 is applied)

1. Confirm migration `0024` was applied (ask the user, or run `supabase db query --linked` to check the 5 new columns + grants independently).
2. Open Post Listing (Dashboard FAB or bottom-nav Post button) — confirm it opens on the "Provide Listing" tab with the full existing create form, plus the new location quick-fill pills and a live match preview once a price + at least one open requirement matches.
3. Tap "Buyer Match" — confirm the form switches to the Requirement form, the ticker switches to "N Buyer Demands Active", and any previously-typed listing title is preserved when switching back.
4. Fill in the Buyer Match form's new fields (Min Bathrooms, Min Built-up, Desired Split, both readiness toggles) and submit — confirm the created requirement's new columns are set correctly (verify via `supabase db query --linked` or by editing... actually Requirement has no edit screen, so verify via a direct DB query).
5. Post a listing with `bathrooms: 1` and a requirement with `bathroomsMin: 2` in the same area/state/transaction type — confirm they do NOT match (Requirement Board / My Matches should not show this pair), verifying the qualifying filter works end-to-end against the real database, not just in the unit test.
6. Navigate to My Inventory → Edit an existing listing — confirm the toggle is absent and only the listing form shows, prefilled correctly (no regression from the extraction).
7. Confirm the Chat tab's "New Co-Broke" FAB still lands on the Buyer Match tab (per its existing `/post-requirement` push).
