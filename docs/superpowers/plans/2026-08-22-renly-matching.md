# renly Matching Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every new listing/requirement gets scored against all open opposing records (mandatory filters + weighted score from the project proposal §6.4), qualifying pairs persist in a new `match` table, and a negotiator can view ranked matches for a specific listing/requirement or across all their own records.

**Architecture:** `MatchingEngine` is a pure Dart scorer with zero Supabase dependency (mirrors `ListingFormatting`/`RequirementFormatting`). `MatchingRepository` composes `ListingRepository`/`RequirementRepository` — reuses their existing fetch/owner methods rather than duplicating queries — and is the sole Supabase touchpoint for `match`. Compute is triggered once, from `PostListingScreen`/`PostRequirementScreen`'s existing submit flow, right after the listing/requirement itself is created; there is no recompute path, because neither table has an edit flow, so a given pair's score never changes once computed.

**Tech Stack:** Flutter/Dart, Riverpod, `supabase_flutter`, `go_router`, `easy_localization` (all already dependencies).

## Global Constraints

- No screen calls `Supabase.instance.client` directly — always through `MatchingRepository`.
- `MatchingRepository` reuses `ListingRepository.fetchMarketplaceListings`/`fetchListingOwner` and `RequirementRepository.fetchBoardRequirements` (all already exist) instead of writing new queries for "opposing open records" or "owner info" — it takes both repositories as constructor dependencies.
- `currentNegotiatorIdProvider` is defined fresh in `matching_providers.dart` (same body as the copies in `listing_providers.dart`/`requirement_providers.dart`) — not imported from a sibling feature, same reasoning as the Requirement module's precedent.
- Every new UI string goes into BOTH `app/assets/translations/en.json` and `app/assets/translations/ms.json` with matching keys. Reuse `listing_error_generic` for error states (no new matching-scoped error key) and reuse `ListingFormatting.formatPrice`/`RequirementFormatting.formatBudgetRange` for money display — no new formatting helpers.
- **Every test file with 2+ `testWidgets` sharing `EasyLocalization` MUST include** `import 'package:flutter/services.dart';` + `setUp(() { rootBundle.clear(); });` right after `setUpAll`, plus `await tester.pumpAndSettle();` after every `pumpWidget` and before any `tap`.
- Test assertions/tap targets use hardcoded literal English strings, not `.tr()` calls.
- `MatchingEngine.score` mandatory filters: `transactionType` and `state` must match exactly, or the pair is disqualified (returns `null`, never scored, never inserted).
- Weights: location 30, price 35, property type 25, bedrooms 10 (sums to 100). `MatchingEngine.qualifyingThreshold = 40`.
- The `match` table has no UPDATE policy at all (RLS deny-by-default with no policy = blocked) — inserts use `upsert(..., onConflict: 'listing_id,requirement_id', ignoreDuplicates: true)`, never a plain insert or an update.
- Status changes on `listing`/`requirement` do **not** touch `match` rows — visibility of "stale" matches (where one side is no longer active/open and the viewer doesn't own that side) is enforced by `!inner` embedding in the fetch query, which relies on `listing`/`requirement`'s own existing RLS policies (owner sees their own regardless of status; everyone else sees only active/open) — not by any new filtering logic in `MatchingRepository` or the screens.
- The matching-compute call added to `PostListingScreen`/`PostRequirementScreen` must be wrapped in its own `try`/`catch` that swallows failure silently — it must never block navigation away from the form after the listing/requirement itself was already created successfully.
- SQL migration is a manual, user-performed step (Task 1) — this session has no DB credentials.
- Flutter is on PATH via `export PATH="$HOME/development/flutter/bin:$PATH"` — run first if `flutter` isn't found. All commands assume this has been run and `cd` is `app/` unless stated otherwise.

---

### Task 1: Supabase migration SQL (0006_matching.sql)

**Files:**
- Create: `supabase/migrations/0006_matching.sql`
- Modify: `app/README.md` (append a "Milestone 5 setup" section)

**Interfaces:**
- Produces: the `match` table that Task 3's `MatchingRepository` assumes exists.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0006_matching.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0005.
--
-- Written to be re-runnable from the start, same pattern as
-- 0005_requirement.sql (drop policy if exists, table guarded with `if not
-- exists`). No storage bucket, no column-scoped grants needed -- every
-- column on `match` (listing_id, requirement_id, score) is legitimately
-- insertable by the app; there's no auto-generated-only field like
-- negotiator_id to protect the way listing/requirement needed.

create table if not exists match (
  match_id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listing(listing_id) on delete cascade,
  requirement_id uuid not null references requirement(requirement_id) on delete cascade,
  score integer not null check (score >= 0 and score <= 100),
  created_at timestamptz not null default now(),
  unique (listing_id, requirement_id)
);

alter table match enable row level security;

-- `match` has no negotiator_id column of its own -- ownership is
-- determined by joining to listing/requirement, since a match inherently
-- touches two different negotiators' records. A negotiator sees/inserts a
-- row if they own EITHER side.
drop policy if exists match_select on match;
create policy match_select on match for select
  to authenticated using (
    exists (select 1 from listing l where l.listing_id = match.listing_id and l.negotiator_id = auth.uid())
    or exists (select 1 from requirement r where r.requirement_id = match.requirement_id and r.negotiator_id = auth.uid())
  );

drop policy if exists match_insert on match;
create policy match_insert on match for insert
  to authenticated with check (
    exists (select 1 from listing l where l.listing_id = match.listing_id and l.negotiator_id = auth.uid())
    or exists (select 1 from requirement r where r.requirement_id = match.requirement_id and r.negotiator_id = auth.uid())
  );

-- Deliberately no UPDATE or DELETE policy: RLS is deny-by-default, so with
-- no policy for those commands they are blocked entirely. Neither listing
-- nor requirement has an edit flow, so a match's score never needs to
-- change once inserted -- there is genuinely nothing to update.
```

- [ ] **Step 2: Verify the file is well-formed**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0006_matching.sql
grep -c "^create policy" supabase/migrations/0006_matching.sql
```
Expected: `1` (match) and `2` (match_select, match_insert).

- [ ] **Step 3: Append manual setup instructions to app/README.md**

Read the current `app/README.md` first (it has Milestone 1-4 setup sections). Append:

```markdown

## Milestone 5 setup (matching)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0006_matching.sql` (repo root) -> Run. This creates the `match` table and its two RLS policies. No storage bucket, no Auth-dashboard changes.
```

- [ ] **Step 4: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add supabase/migrations/0006_matching.sql app/README.md
git commit -m "feat: add matching Supabase migration and setup docs"
```

---

### Task 2: MatchingEngine (pure Dart scorer, TDD)

**Files:**
- Create: `app/lib/features/matching/matching_engine.dart`
- Test: `app/test/features/matching/matching_engine_test.dart`

**Interfaces:**
- Consumes: `Listing` (`../listing/models/listing.dart`), `Requirement` (`../requirement/models/requirement.dart`) — both already exist.
- Produces: `MatchingEngine.score(Listing listing, Requirement requirement)` → `int?` (`null` if a mandatory filter disqualifies the pair), `MatchingEngine.qualifyingThreshold` → `int` constant `40`. Task 3's `MatchingRepository` calls both.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/matching/matching_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/matching/matching_engine.dart';
import 'package:renly/features/requirement/models/requirement.dart';

const _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  bedrooms: 3,
  photoUrls: [],
  status: 'active',
);

const _requirement = Requirement(
  requirementId: 'r-1',
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
);

void main() {
  group('MatchingEngine.score', () {
    test('full match on every dimension scores 100', () {
      expect(MatchingEngine.score(_listing, _requirement), 100);
    });

    test('transaction type mismatch disqualifies the pair', () {
      final requirement = Requirement(
        requirementId: _requirement.requirementId,
        negotiatorId: _requirement.negotiatorId,
        propertyType: _requirement.propertyType,
        transactionType: 'rent',
        state: _requirement.state,
        area: _requirement.area,
        budgetMin: _requirement.budgetMin,
        budgetMax: _requirement.budgetMax,
        bedrooms: _requirement.bedrooms,
        photoUrls: _requirement.photoUrls,
        status: _requirement.status,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('state mismatch disqualifies the pair', () {
      final requirement = Requirement(
        requirementId: _requirement.requirementId,
        negotiatorId: _requirement.negotiatorId,
        propertyType: _requirement.propertyType,
        transactionType: _requirement.transactionType,
        state: 'Johor',
        area: _requirement.area,
        budgetMin: _requirement.budgetMin,
        budgetMax: _requirement.budgetMax,
        bedrooms: _requirement.bedrooms,
        photoUrls: _requirement.photoUrls,
        status: _requirement.status,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('area mismatch loses the 30 location points', () {
      final requirement = Requirement(
        requirementId: _requirement.requirementId,
        negotiatorId: _requirement.negotiatorId,
        propertyType: _requirement.propertyType,
        transactionType: _requirement.transactionType,
        state: _requirement.state,
        area: 'Shah Alam',
        budgetMin: _requirement.budgetMin,
        budgetMax: _requirement.budgetMax,
        bedrooms: _requirement.bedrooms,
        photoUrls: _requirement.photoUrls,
        status: _requirement.status,
      );
      expect(MatchingEngine.score(_listing, requirement), 70);
    });

    test('price 5 percent over max gets half the graduated band', () {
      const listing = Listing(
        listingId: 'l-2',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 525000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
      );
      expect(MatchingEngine.score(listing, _requirement), 83);
    });

    test('price beyond 10 percent over max scores zero for price', () {
      const listing = Listing(
        listingId: 'l-3',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 600000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
      );
      expect(MatchingEngine.score(listing, _requirement), 65);
    });

    test('price below budget minimum still scores full price weight', () {
      const listing = Listing(
        listingId: 'l-4',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 250000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
      );
      expect(MatchingEngine.score(listing, _requirement), 100);
    });

    test('unspecified requirement bedrooms scores full bedroom weight', () {
      const requirement = Requirement(
        requirementId: 'r-2',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        photoUrls: [],
        status: 'open',
      );
      expect(MatchingEngine.score(_listing, requirement), 100);
    });

    test('mismatched bedroom count scores zero for bedrooms', () {
      const requirement = Requirement(
        requirementId: 'r-3',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 2,
        photoUrls: [],
        status: 'open',
      );
      expect(MatchingEngine.score(_listing, requirement), 90);
    });

    test('qualifyingThreshold is 40', () {
      expect(MatchingEngine.qualifyingThreshold, 40);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/matching/matching_engine_test.dart
```
Expected: FAIL — `package:renly/features/matching/matching_engine.dart` not found.

- [ ] **Step 3: Implement MatchingEngine**

```dart
// app/lib/features/matching/matching_engine.dart
import '../listing/models/listing.dart';
import '../requirement/models/requirement.dart';

/// Pure weighted-scoring algorithm from the project proposal §6.4. No
/// Flutter/Supabase dependency -- fully unit-testable, mirrors the
/// ListingFormatting/RequirementFormatting precedent.
class MatchingEngine {
  MatchingEngine._();

  static const qualifyingThreshold = 40;

  /// Returns null if a mandatory filter disqualifies the pair (transaction
  /// type or state mismatch). Otherwise returns the weighted score
  /// (0-100), rounded to the nearest integer -- callers decide whether it
  /// clears [qualifyingThreshold].
  static int? score(Listing listing, Requirement requirement) {
    if (listing.transactionType != requirement.transactionType) return null;
    if (listing.state != requirement.state) return null;

    final location = listing.area.toLowerCase() == requirement.area.toLowerCase() ? 30 : 0;
    final price = _priceScore(listing.price, requirement.budgetMin, requirement.budgetMax);
    final propertyType = listing.propertyType == requirement.propertyType ? 25 : 0;
    final bedrooms = _bedroomScore(listing.bedrooms, requirement.bedrooms);

    return (location + price + propertyType + bedrooms).round();
  }

  /// Full weight within [budgetMin, budgetMax] and below budgetMin (still
  /// affordable). Linearly reduced from 35 to 0 between budgetMax and
  /// budgetMax * 1.10. Zero beyond that.
  static double _priceScore(double price, double budgetMin, double budgetMax) {
    if (price <= budgetMax) return 35;
    final overMax = budgetMax * 1.10;
    if (price >= overMax) return 0;
    final fraction = (overMax - price) / (overMax - budgetMax);
    return 35 * fraction;
  }

  /// Binary, not graduated -- the proposal gives no curve for this
  /// attribute. Unset requirement bedrooms (client didn't specify) scores
  /// full weight regardless of the listing's value.
  static int _bedroomScore(int? listingBedrooms, int? requirementBedrooms) {
    if (requirementBedrooms == null) return 10;
    if (listingBedrooms == requirementBedrooms) return 10;
    return 0;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/matching/matching_engine_test.dart
```
Expected: `00:0X +9: All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/matching/matching_engine.dart app/test/features/matching/matching_engine_test.dart
git commit -m "feat: add MatchingEngine pure scoring algorithm"
```

---

### Task 3: Match/MatchCandidate models + MatchingRepository

**Files:**
- Create: `app/lib/features/matching/models/match.dart`
- Create: `app/lib/features/matching/models/match_candidate.dart`
- Create: `app/lib/features/matching/matching_repository.dart`

**Interfaces:**
- Consumes: `MatchingEngine` (Task 2), `ListingRepository`/`Listing`/`ListingOwner` (`../listing/`), `RequirementRepository`/`Requirement` (`../requirement/`) — all already exist.
- Produces: `Match` (fields `matchId`, `listingId`, `requirementId`, `score` (`int`), `createdAt`) with `Match.fromJson`. `MatchCandidate` (fields `matchId`, `score`, `listing` (`Listing`), `requirement` (`Requirement`), `listingOwner` (`ListingOwner`), `requirementOwner` (`ListingOwner`)) — a repository-composed view, not built from a single JSON row. `MatchingRepository(SupabaseClient client, ListingRepository listingRepository, RequirementRepository requirementRepository)` with methods `computeAndStoreMatchesForListing`, `computeAndStoreMatchesForRequirement`, `fetchMatchesForListing`, `fetchMatchesForRequirement`, `fetchMyMatches` — every later task uses these.

No TDD for this task (same documented boundary as every other repository — Supabase-calling code isn't unit-tested in this project). Verify with `flutter analyze` only.

**A design note worth reading before implementing:** the design doc says stale matches (where one side is no longer active/open) are "filtered at display" rather than deleted. This task implements that concretely: the fetch queries below use `!inner` embedding (`listing!inner(*)`, `requirement!inner(*)`) rather than the default left-join embedding. PostgREST's `!inner` drops the whole parent row if the embedded resource fails to match **or fails its own RLS policy** — and `listing`/`requirement`'s existing RLS already says "owner sees their own regardless of status; everyone else sees only active/open". So a match touching your own now-sold listing still shows up for you (you're the owner, RLS lets you through regardless of status), while the same match is silently dropped for a viewer who owns neither side and can no longer see that listing under its own RLS. The embed IS the filter — no separate status-checking code is needed in `MatchingRepository` or any screen.

- [ ] **Step 1: Implement Match**

```dart
// app/lib/features/matching/models/match.dart

/// A row from the `match` table.
class Match {
  final String matchId;
  final String listingId;
  final String requirementId;
  final int score;
  final DateTime createdAt;

  const Match({
    required this.matchId,
    required this.listingId,
    required this.requirementId,
    required this.score,
    required this.createdAt,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      matchId: json['match_id'] as String,
      listingId: json['listing_id'] as String,
      requirementId: json['requirement_id'] as String,
      score: json['score'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 2: Implement MatchCandidate**

```dart
// app/lib/features/matching/models/match_candidate.dart
import '../../listing/models/listing.dart';
import '../../listing/models/listing_owner.dart';
import '../../requirement/models/requirement.dart';

/// A match row joined with both full sides and both owners. Always carries
/// both sides even on screens where one side is already known from
/// context -- one shared model and one shared list-row shape across all
/// three matching screens, instead of three near-duplicate view models.
class MatchCandidate {
  final String matchId;
  final int score;
  final Listing listing;
  final Requirement requirement;
  final ListingOwner listingOwner;
  final ListingOwner requirementOwner;

  const MatchCandidate({
    required this.matchId,
    required this.score,
    required this.listing,
    required this.requirement,
    required this.listingOwner,
    required this.requirementOwner,
  });
}
```

- [ ] **Step 3: Implement MatchingRepository**

```dart
// app/lib/features/matching/matching_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing.dart';
import '../listing/models/listing_owner.dart';
import '../requirement/models/requirement.dart';
import '../requirement/requirement_repository.dart';
import 'matching_engine.dart';
import 'models/match.dart';
import 'models/match_candidate.dart';

/// The only file in this app that talks to Supabase for the matching
/// feature. Composes ListingRepository/RequirementRepository rather than
/// duplicating their queries (fetching opposing open records, fetching
/// owner info) -- matching is inherently cross-feature.
class MatchingRepository {
  MatchingRepository(this._client, this._listingRepository, this._requirementRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;
  final RequirementRepository _requirementRepository;

  Future<void> computeAndStoreMatchesForListing(Listing listing) async {
    final requirements = await _requirementRepository.fetchBoardRequirements();
    final rows = <Map<String, dynamic>>[];
    for (final requirement in requirements) {
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      rows.add({
        'listing_id': listing.listingId,
        'requirement_id': requirement.requirementId,
        'score': score,
      });
    }
    await _store(rows);
  }

  Future<void> computeAndStoreMatchesForRequirement(Requirement requirement) async {
    final listings = await _listingRepository.fetchMarketplaceListings();
    final rows = <Map<String, dynamic>>[];
    for (final listing in listings) {
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      rows.add({
        'listing_id': listing.listingId,
        'requirement_id': requirement.requirementId,
        'score': score,
      });
    }
    await _store(rows);
  }

  Future<void> _store(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('match').upsert(
          rows,
          onConflict: 'listing_id,requirement_id',
          ignoreDuplicates: true,
        );
  }

  Future<List<MatchCandidate>> fetchMatchesForListing(String listingId) async {
    final rows = await _client
        .from('match')
        .select('*, listing!inner(*), requirement!inner(*)')
        .eq('listing_id', listingId)
        .order('score', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<MatchCandidate>> fetchMatchesForRequirement(String requirementId) async {
    final rows = await _client
        .from('match')
        .select('*, listing!inner(*), requirement!inner(*)')
        .eq('requirement_id', requirementId)
        .order('score', ascending: false);
    return _toCandidates(rows as List);
  }

  /// RLS on `match` already restricts rows to ones touching the caller's
  /// own listing or requirement -- no negotiatorId filter needed here.
  Future<List<MatchCandidate>> fetchMyMatches() async {
    final rows = await _client
        .from('match')
        .select('*, listing!inner(*), requirement!inner(*)')
        .order('score', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<MatchCandidate>> _toCandidates(List rows) async {
    // Cached as Futures (not resolved values) so concurrent lookups for the
    // same negotiator id across multiple match rows share one in-flight
    // request instead of firing the RPC once per row.
    final ownerFutures = <String, Future<ListingOwner>>{};
    Future<ListingOwner> ownerFor(String negotiatorId) {
      return ownerFutures.putIfAbsent(negotiatorId, () => _listingRepository.fetchListingOwner(negotiatorId));
    }

    final candidates = <MatchCandidate>[];
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final match = Match.fromJson(map);
      final listing = Listing.fromJson(map['listing'] as Map<String, dynamic>);
      final requirement = Requirement.fromJson(map['requirement'] as Map<String, dynamic>);
      final listingOwner = await ownerFor(listing.negotiatorId);
      final requirementOwner = await ownerFor(requirement.negotiatorId);
      candidates.add(MatchCandidate(
        matchId: match.matchId,
        score: match.score,
        listing: listing,
        requirement: requirement,
        listingOwner: listingOwner,
        requirementOwner: requirementOwner,
      ));
    }
    return candidates;
  }
}
```

- [ ] **Step 4: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/matching/models/match.dart lib/features/matching/models/match_candidate.dart lib/features/matching/matching_repository.dart
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/matching/models/match.dart app/lib/features/matching/models/match_candidate.dart app/lib/features/matching/matching_repository.dart
git commit -m "feat: add Match/MatchCandidate models and MatchingRepository"
```

---

### Task 4: matching_providers.dart

**Files:**
- Create: `app/lib/features/matching/matching_providers.dart`

**Interfaces:**
- Consumes: `MatchingRepository` (Task 3), `listingRepositoryProvider` (`../listing/listing_providers.dart`), `requirementRepositoryProvider` (`../requirement/requirement_providers.dart`), `authStateProvider` (`../auth/auth_providers.dart`) — all already exist.
- Produces: `matchingRepositoryProvider` (`Provider<MatchingRepository>`), `currentNegotiatorIdProvider` (`Provider<String?>`), `matchesForListingProvider` (`FutureProvider.family<List<MatchCandidate>, String>`), `matchesForRequirementProvider` (`FutureProvider.family<List<MatchCandidate>, String>`), `myMatchesProvider` (`FutureProvider<List<MatchCandidate>>`) — every screen task uses these.

No TDD for this task (Riverpod wiring, same boundary as `listing_providers.dart`/`requirement_providers.dart`). Verify with `flutter analyze`.

- [ ] **Step 1: Implement matching_providers.dart**

```dart
// app/lib/features/matching/matching_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import '../requirement/requirement_providers.dart';
import 'matching_repository.dart';
import 'models/match_candidate.dart';

final matchingRepositoryProvider = Provider<MatchingRepository>((ref) {
  return MatchingRepository(
    Supabase.instance.client,
    ref.watch(listingRepositoryProvider),
    ref.watch(requirementRepositoryProvider),
  );
});

/// Same session-state read as listing_providers.dart/requirement_providers.dart's
/// currentNegotiatorIdProvider -- duplicated here rather than imported from
/// a sibling feature, so this feature only depends on auth for something
/// this basic.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

final matchesForListingProvider = FutureProvider.family<List<MatchCandidate>, String>((ref, listingId) {
  return ref.watch(matchingRepositoryProvider).fetchMatchesForListing(listingId);
});

final matchesForRequirementProvider = FutureProvider.family<List<MatchCandidate>, String>((ref, requirementId) {
  return ref.watch(matchingRepositoryProvider).fetchMatchesForRequirement(requirementId);
});

final myMatchesProvider = FutureProvider<List<MatchCandidate>>((ref) {
  return ref.watch(matchingRepositoryProvider).fetchMyMatches();
});
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/matching/matching_providers.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/matching/matching_providers.dart
git commit -m "feat: add matching Riverpod providers"
```

---

### Task 5: Hook compute-on-create into PostListingScreen and PostRequirementScreen

**Files:**
- Modify: `app/lib/features/listing/post_listing_screen.dart`
- Modify: `app/lib/features/requirement/post_requirement_screen.dart`

**Interfaces:**
- Consumes: `matchingRepositoryProvider` (Task 4).
- Produces: no new public interface — both screens' existing `_submit()` success paths gain one best-effort call each.

This is the highest-regression-risk task in this plan, same class as the Requirement plan's `SignedPhoto` extraction — it edits two already-shipped, already-tested screens. No TDD (the change is inside an existing method, not a new testable unit) — instead, this task's own verification is re-running BOTH screens' full existing test suites to confirm zero regression, plus a manual read-through confirming the new call is placed after the existing invalidate calls and before `context.go(...)`.

- [ ] **Step 1: Edit PostListingScreen**

Read the current `app/lib/features/listing/post_listing_screen.dart` first. Add the import alongside the existing ones:

```dart
import '../matching/matching_providers.dart';
```

In `_submit()`, find this exact block:

```dart
      ref.invalidate(marketplaceListingsProvider);
      ref.invalidate(myListingsProvider(negotiatorId));

      if (!mounted) return;
      context.go('/my-inventory');
```

Replace it with:

```dart
      ref.invalidate(marketplaceListingsProvider);
      ref.invalidate(myListingsProvider(negotiatorId));

      try {
        await ref.read(matchingRepositoryProvider).computeAndStoreMatchesForListing(listing);
      } catch (_) {
        // Best-effort: matching is an enhancement, not a requirement for
        // the listing itself to have been created successfully. A failure
        // here must not trap the user on a form whose real submission
        // already succeeded.
      }

      if (!mounted) return;
      context.go('/my-inventory');
```

- [ ] **Step 2: Edit PostRequirementScreen**

Read the current `app/lib/features/requirement/post_requirement_screen.dart` first. Add the import alongside the existing ones:

```dart
import '../matching/matching_providers.dart';
```

In `_submit()`, find this exact block:

```dart
      ref.invalidate(boardRequirementsProvider);
      ref.invalidate(myRequirementsProvider(negotiatorId));

      if (!mounted) return;
      context.go('/my-requirements');
```

Replace it with:

```dart
      ref.invalidate(boardRequirementsProvider);
      ref.invalidate(myRequirementsProvider(negotiatorId));

      try {
        await ref.read(matchingRepositoryProvider).computeAndStoreMatchesForRequirement(requirement);
      } catch (_) {
        // Best-effort, same reasoning as PostListingScreen.
      }

      if (!mounted) return;
      context.go('/my-requirements');
```

- [ ] **Step 3: Run both screens' full existing test suites to confirm zero regression**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/listing/post_listing_screen_test.dart test/features/requirement/post_requirement_screen_test.dart
```
Expected: same pass counts as before this task (3 tests each) — neither existing test file exercises `_submit()`'s success path (they only test field rendering and validation-blocks-submission), so the new calls are never actually reached by these tests. If anything fails, the import or exact-block match was wrong; check against the file as it exists on disk before assuming the test itself needs to change.

- [ ] **Step 4: Verify static analysis is clean**

```bash
flutter analyze lib/features/listing/post_listing_screen.dart lib/features/requirement/post_requirement_screen.dart
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/post_listing_screen.dart app/lib/features/requirement/post_requirement_screen.dart
git commit -m "feat: compute matches on listing/requirement creation"
```

---

### Task 6: MatchesForListingScreen + MatchesForRequirementScreen

**Files:**
- Create: `app/lib/features/matching/matches_for_listing_screen.dart`
- Create: `app/lib/features/matching/matches_for_requirement_screen.dart`
- Test: `app/test/features/matching/matches_for_listing_screen_test.dart`
- Test: `app/test/features/matching/matches_for_requirement_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `matchesForListingProvider`, `matchesForRequirementProvider` (Task 4), `MatchCandidate` (Task 3), `RequirementFormatting`/`ListingFormatting` (already exist).
- Produces: `MatchesForListingScreen({required String listingId})` and `MatchesForRequirementScreen({required String requirementId})` — Task 8's router uses them for `/property/:listingId/matches` and `/requirement-board/:requirementId/matches`.

Bundled into one task — the two screens are near-mirrors (swap which side is "known from context" vs. "the side being ranked"), the same pattern a reviewer can sensibly approve or reject together.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/features/matching/matches_for_listing_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/matches_for_listing_screen.dart';
import 'package:renly/features/matching/matching_providers.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

const _fixtureListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  photoUrls: [],
  status: 'active',
);

const _fixtureRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  photoUrls: [],
  status: 'open',
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

final _fixtureMatches = [
  const MatchCandidate(
    matchId: 'm-1',
    score: 90,
    listing: _fixtureListing,
    requirement: _fixtureRequirement,
    listingOwner: _fixtureOwner,
    requirementOwner: _fixtureOwner,
  ),
];

Widget _wrap(GoRouter router, {List<MatchCandidate>? matches}) {
  return ProviderScope(
    overrides: [
      matchesForListingProvider.overrideWith((ref, listingId) async => matches ?? _fixtureMatches),
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
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders score, budget range, area, and owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForListingScreen(listingId: 'l-1')),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('90/100'), findsOneWidget);
    expect(find.text('RM 300,000 - RM 500,000'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Aiman Yusof (REN: 12345)'), findsOneWidget);
  });

  testWidgets('tapping a match navigates to the requirement detail route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForListingScreen(listingId: 'l-1')),
      GoRoute(
        path: '/requirement-board/:requirementId',
        builder: (context, state) => Text('detail-${state.pathParameters['requirementId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90/100'));
    await tester.pumpAndSettle();

    expect(find.text('detail-r-1'), findsOneWidget);
  });

  testWidgets('renders empty state when no matches', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForListingScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, matches: []));
    await tester.pumpAndSettle();

    expect(find.text('No matches yet'), findsOneWidget);
  });
}
```

```dart
// app/test/features/matching/matches_for_requirement_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/matches_for_requirement_screen.dart';
import 'package:renly/features/matching/matching_providers.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

const _fixtureListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  photoUrls: [],
  status: 'active',
);

const _fixtureRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  photoUrls: [],
  status: 'open',
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

final _fixtureMatches = [
  const MatchCandidate(
    matchId: 'm-1',
    score: 90,
    listing: _fixtureListing,
    requirement: _fixtureRequirement,
    listingOwner: _fixtureOwner,
    requirementOwner: _fixtureOwner,
  ),
];

Widget _wrap(GoRouter router, {List<MatchCandidate>? matches}) {
  return ProviderScope(
    overrides: [
      matchesForRequirementProvider.overrideWith((ref, requirementId) async => matches ?? _fixtureMatches),
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
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders score, price, area, and owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForRequirementScreen(requirementId: 'r-1')),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('90/100'), findsOneWidget);
    expect(find.text('RM 400,000'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Aiman Yusof (REN: 12345)'), findsOneWidget);
  });

  testWidgets('tapping a match navigates to the property detail route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForRequirementScreen(requirementId: 'r-1')),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => Text('detail-${state.pathParameters['listingId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90/100'));
    await tester.pumpAndSettle();

    expect(find.text('detail-l-1'), findsOneWidget);
  });

  testWidgets('renders empty state when no matches', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForRequirementScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router, matches: []));
    await tester.pumpAndSettle();

    expect(find.text('No matches yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/matching/matches_for_listing_screen_test.dart test/features/matching/matches_for_requirement_screen_test.dart
```
Expected: FAIL — screen files not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "matching_matches_title": "Matches",
  "matching_empty": "No matches yet"
```

`app/assets/translations/ms.json` additions:
```json
  "matching_matches_title": "Padanan",
  "matching_empty": "Tiada padanan lagi"
```

- [ ] **Step 4: Implement MatchesForListingScreen**

```dart
// app/lib/features/matching/matches_for_listing_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../requirement/requirement_formatting.dart';
import 'matching_providers.dart';

/// Ranked requirement matches for one listing. Reached via "View Matches"
/// on PropertyDetailScreen.
class MatchesForListingScreen extends ConsumerWidget {
  const MatchesForListingScreen({super.key, required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesForListingProvider(listingId));

    return Scaffold(
      appBar: AppBar(title: Text('matching_matches_title'.tr())),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (matches) {
          if (matches.isEmpty) {
            return Center(child: Text('matching_empty'.tr()));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final candidate = matches[index];
              final requirement = candidate.requirement;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate.score}/100',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          RequirementFormatting.formatBudgetRange(
                            requirement.budgetMin,
                            requirement.budgetMax,
                            requirement.transactionType,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(requirement.area, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Implement MatchesForRequirementScreen**

```dart
// app/lib/features/matching/matches_for_requirement_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../listing/listing_formatting.dart';
import 'matching_providers.dart';

/// Ranked listing matches for one requirement. Reached via "View Matches"
/// on RequirementDetailScreen.
class MatchesForRequirementScreen extends ConsumerWidget {
  const MatchesForRequirementScreen({super.key, required this.requirementId});

  final String requirementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesForRequirementProvider(requirementId));

    return Scaffold(
      appBar: AppBar(title: Text('matching_matches_title'.tr())),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (matches) {
          if (matches.isEmpty) {
            return Center(child: Text('matching_empty'.tr()));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final candidate = matches[index];
              final listing = candidate.listing;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => context.push('/property/${listing.listingId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate.score}/100',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(ListingFormatting.formatPrice(listing.price, listing.transactionType)),
                        const SizedBox(height: 4),
                        Text(listing.area, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
flutter test test/features/matching/matches_for_listing_screen_test.dart test/features/matching/matches_for_requirement_screen_test.dart
```
Expected: `00:0X +6: All tests passed!` (3 + 3).

- [ ] **Step 7: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/matching/matches_for_listing_screen.dart app/lib/features/matching/matches_for_requirement_screen.dart app/test/features/matching/matches_for_listing_screen_test.dart app/test/features/matching/matches_for_requirement_screen_test.dart app/assets/translations/
git commit -m "feat: add MatchesForListingScreen and MatchesForRequirementScreen"
```

---

### Task 7: MyMatchesScreen

**Files:**
- Create: `app/lib/features/matching/my_matches_screen.dart`
- Test: `app/test/features/matching/my_matches_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `myMatchesProvider`, `currentNegotiatorIdProvider` (Task 4), `MatchCandidate` (Task 3).
- Produces: `MyMatchesScreen` — Task 8's router uses it as `/my-matches`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/matching/my_matches_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/matching_providers.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/matching/my_matches_screen.dart';
import 'package:renly/features/requirement/models/requirement.dart';

const _myListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'My Listing',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  photoUrls: [],
  status: 'active',
);

const _theirRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  photoUrls: [],
  status: 'open',
);

const _theirListing = Listing(
  listingId: 'l-2',
  negotiatorId: 'n-3',
  title: 'Their Listing',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Johor',
  area: 'Iskandar Puteri',
  price: 800000,
  photoUrls: [],
  status: 'active',
);

const _myRequirement = Requirement(
  requirementId: 'r-2',
  negotiatorId: 'n-1',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Johor',
  area: 'Iskandar Puteri',
  budgetMin: 700000,
  budgetMax: 900000,
  photoUrls: [],
  status: 'open',
);

const _owner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

final _fixtureMatches = [
  const MatchCandidate(
    matchId: 'm-1',
    score: 90,
    listing: _myListing,
    requirement: _theirRequirement,
    listingOwner: _owner,
    requirementOwner: _owner,
  ),
  const MatchCandidate(
    matchId: 'm-2',
    score: 80,
    listing: _theirListing,
    requirement: _myRequirement,
    listingOwner: _owner,
    requirementOwner: _owner,
  ),
];

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myMatchesProvider.overrideWith((ref) async => _fixtureMatches),
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
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('shows the other side for both my-listing and my-requirement matches', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyMatchesScreen()),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 300,000 - RM 500,000'), findsOneWidget);
    expect(find.text('RM 800,000'), findsOneWidget);
  });

  testWidgets('tapping a my-listing match navigates to the requirement route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyMatchesScreen()),
      GoRoute(
        path: '/requirement-board/:requirementId',
        builder: (context, state) => Text('req-detail-${state.pathParameters['requirementId']}'),
      ),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90/100'));
    await tester.pumpAndSettle();

    expect(find.text('req-detail-r-1'), findsOneWidget);
  });

  testWidgets('tapping a my-requirement match navigates to the property route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyMatchesScreen()),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => Text('property-detail-${state.pathParameters['listingId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80/100'));
    await tester.pumpAndSettle();

    expect(find.text('property-detail-l-2'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/matching/my_matches_screen_test.dart
```
Expected: FAIL — `package:renly/features/matching/my_matches_screen.dart` not found.

- [ ] **Step 3: Add the translation key**

`app/assets/translations/en.json` addition:
```json
  "matching_my_matches_title": "My Matches"
```

`app/assets/translations/ms.json` addition:
```json
  "matching_my_matches_title": "Padanan Saya"
```

- [ ] **Step 4: Implement MyMatchesScreen**

```dart
// app/lib/features/matching/my_matches_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../listing/listing_formatting.dart';
import '../requirement/requirement_formatting.dart';
import 'matching_providers.dart';

/// All matches touching the negotiator's own listings or requirements,
/// either side. Reached via "My Matches" on HomePlaceholderScreen.
class MyMatchesScreen extends ConsumerWidget {
  const MyMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(myMatchesProvider);
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('matching_my_matches_title'.tr())),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (matches) {
          if (matches.isEmpty) {
            return Center(child: Text('matching_empty'.tr()));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final candidate = matches[index];
              final isMyListing = candidate.listing.negotiatorId == currentNegotiatorId;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => isMyListing
                      ? context.push('/requirement-board/${candidate.requirement.requirementId}')
                      : context.push('/property/${candidate.listing.listingId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate.score}/100',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        if (isMyListing) ...[
                          Text(
                            RequirementFormatting.formatBudgetRange(
                              candidate.requirement.budgetMin,
                              candidate.requirement.budgetMax,
                              candidate.requirement.transactionType,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(candidate.requirement.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ] else ...[
                          Text(ListingFormatting.formatPrice(candidate.listing.price, candidate.listing.transactionType)),
                          const SizedBox(height: 4),
                          Text(candidate.listing.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/matching/my_matches_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/matching/my_matches_screen.dart app/test/features/matching/my_matches_screen_test.dart app/assets/translations/
git commit -m "feat: add MyMatchesScreen"
```

---

### Task 8: Wire routes, add View Matches buttons, My Matches nav link

**Files:**
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/lib/features/listing/property_detail_screen.dart`
- Modify: `app/lib/features/requirement/requirement_detail_screen.dart`
- Modify: `app/lib/features/auth/home_placeholder_screen.dart`
- Test: `app/test/core/router/app_router_test.dart` (add 3 new `test()` cases inside the existing `group`, keep the existing 15 untouched)
- Test: `app/test/features/auth/home_placeholder_screen_test.dart` (full replace — keeps the existing 5 tests, adds 1 more)
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `MatchesForListingScreen`, `MatchesForRequirementScreen`, `MyMatchesScreen` (Tasks 6-7).
- Produces: 3 new routes (`/property/:listingId/matches`, `/requirement-board/:requirementId/matches`, `/my-matches`), all requiring a session. `PropertyDetailScreen`/`RequirementDetailScreen` gain an owner-only "View Matches" button. `HomePlaceholderScreen` gains one more navigation link.

This is the integration task — after this, `flutter test` (full suite) and `flutter analyze` must both be clean.

- [ ] **Step 1: Write the failing computeAuthRedirect tests for the new routes**

Read the existing `app/test/core/router/app_router_test.dart` first (it has 15 tests). Add 3 new tests inside the existing `group('computeAuthRedirect', () { ... })` block:

```dart
    test('unauthenticated user on /property/l-1/matches is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/property/l-1/matches'), '/');
    });

    test('unauthenticated user on /requirement-board/r-1/matches is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/requirement-board/r-1/matches'), '/');
    });

    test('unauthenticated user on /my-matches is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-matches'), '/');
    });
```

- [ ] **Step 2: Run test to verify it passes immediately**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/router/app_router_test.dart
```
Expected: `00:0X +18: All tests passed!` — these should already pass since the new paths aren't in `_publicRoutes`. If it unexpectedly fails, `_publicRoutes` has changed since this plan was written; stop and check `app_router.dart` before proceeding.

- [ ] **Step 3: Add the 3 routes to app_router.dart**

Read the current `app/lib/core/router/app_router.dart` first. Add these imports alongside the existing screen imports:

```dart
import '../../features/matching/matches_for_listing_screen.dart';
import '../../features/matching/matches_for_requirement_screen.dart';
import '../../features/matching/my_matches_screen.dart';
```

Add these 3 routes to the `routes:` list inside `appRouterProvider`:

```dart
      GoRoute(
        path: '/property/:listingId/matches',
        builder: (context, state) =>
            MatchesForListingScreen(listingId: state.pathParameters['listingId']!),
      ),
      GoRoute(
        path: '/requirement-board/:requirementId/matches',
        builder: (context, state) =>
            MatchesForRequirementScreen(requirementId: state.pathParameters['requirementId']!),
      ),
      GoRoute(path: '/my-matches', builder: (context, state) => const MyMatchesScreen()),
```

Do not add any of these 3 paths to `_publicRoutes`.

- [ ] **Step 4: Add the translation keys for the View Matches / My Matches link labels**

`app/assets/translations/en.json` additions:
```json
  "matching_view_matches": "View Matches",
  "matching_my_matches_link": "My Matches"
```

`app/assets/translations/ms.json` additions:
```json
  "matching_view_matches": "Lihat Padanan",
  "matching_my_matches_link": "Padanan Saya"
```

- [ ] **Step 5: Add the View Matches button to PropertyDetailScreen**

Read the current `app/lib/features/listing/property_detail_screen.dart` first. Add the import alongside the existing ones (it does not currently import `go_router`):

```dart
import 'package:go_router/go_router.dart';
```

Find the `if (isOwner) ...[` block and add the new button as its first child, before the existing status-change buttons:

```dart
                  if (isOwner) ...[
                    OutlinedButton(
                      onPressed: () => context.push('/property/${widget.listingId}/matches'),
                      child: Text('matching_view_matches'.tr()),
                    ),
                    const SizedBox(height: 8),
                    if (listing.status != 'sold')
```

(the rest of the existing `if (isOwner)` block — the `sold`/`withdrawn`/`active` status buttons — stays exactly as it is, just now preceded by the new button and its `SizedBox`.)

- [ ] **Step 6: Add the View Matches button to RequirementDetailScreen**

Read the current `app/lib/features/requirement/requirement_detail_screen.dart` first. Add the import alongside the existing ones (it does not currently import `go_router`):

```dart
import 'package:go_router/go_router.dart';
```

Find the `if (isOwner) ...[` block and add the new button as its first child, before the existing status-change buttons:

```dart
                  if (isOwner) ...[
                    OutlinedButton(
                      onPressed: () => context.push('/requirement-board/${widget.requirementId}/matches'),
                      child: Text('matching_view_matches'.tr()),
                    ),
                    const SizedBox(height: 8),
                    if (requirement.status != 'fulfilled')
```

(the rest of the existing `if (isOwner)` block stays exactly as it is.)

- [ ] **Step 7: Write the failing HomePlaceholderScreen navigation test**

Read the existing `app/test/features/auth/home_placeholder_screen_test.dart` first (it has 5 tests from Milestones 3-4). Replace the whole file — keeps the 5 existing tests, adds 1 more for the new link, and adds the new route to every router in the file:

```dart
// app/test/features/auth/home_placeholder_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/home_placeholder_screen.dart';

Widget _wrap(GoRouter router) {
  return EasyLocalization(
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
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders verified placeholder copy', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text("You're verified"), findsOneWidget);
    expect(find.text('Dashboard coming soon.'), findsOneWidget);
  });

  testWidgets('tapping the marketplace link navigates to /marketplace', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Text('marketplace-screen')),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('marketplace_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('marketplace-screen'), findsOneWidget);
  });

  testWidgets('tapping the my inventory link navigates to /my-inventory', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Text('inventory-screen')),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inventory_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('inventory-screen'), findsOneWidget);
  });

  testWidgets('tapping the requirement board link navigates to /requirement-board', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Text('requirement-board-screen')),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('requirement_board_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('requirement-board-screen'), findsOneWidget);
  });

  testWidgets('tapping the my requirements link navigates to /my-requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Text('my-requirements-screen')),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('my_requirements_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-requirements-screen'), findsOneWidget);
  });

  testWidgets('tapping the my matches link navigates to /my-matches', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Text('my-matches-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('matching_my_matches_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-matches-screen'), findsOneWidget);
  });
}
```

- [ ] **Step 8: Run test to verify it fails**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: FAIL — `HomePlaceholderScreen` doesn't have the new link yet.

- [ ] **Step 9: Update HomePlaceholderScreen**

Read the current `app/lib/features/auth/home_placeholder_screen.dart` first. Add one more button below the existing four:

```dart
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-requirements'),
                  child: Text('my_requirements_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-matches'),
                  child: Text('matching_my_matches_link'.tr()),
                ),
```

(this replaces the previous last button + closing of the `Column`'s `children` — the new button is appended after the existing "My Requirements" button, before the `],` that closes `children`.)

- [ ] **Step 10: Run test to verify it passes**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: `00:0X +6: All tests passed!`

- [ ] **Step 11: Run the full test suite**

```bash
flutter test
```
Expected: every test passes, zero failures.

- [ ] **Step 12: Run static analysis**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 13: Verify translation key parity**

```bash
flutter test test/l10n/translations_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 14: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/core/router/app_router.dart app/lib/features/listing/property_detail_screen.dart app/lib/features/requirement/requirement_detail_screen.dart app/lib/features/auth/home_placeholder_screen.dart app/test/core/router/app_router_test.dart app/test/features/auth/home_placeholder_screen_test.dart app/assets/translations/
git commit -m "feat: wire matching routes, add View Matches buttons and My Matches nav link"
```

---

## Definition of Done

- `flutter test` (run from `app/`) passes with zero failures across the whole suite.
- `flutter analyze` reports no issues.
- `flutter run` on the user's Android emulator shows: posting a new listing or requirement silently computes matches against all opposing open records; `PropertyDetailScreen`/`RequirementDetailScreen` show a "View Matches" button when viewed as the owner, reaching a ranked list of the other side; `HomePlaceholderScreen`'s "My Matches" link reaches a combined list showing the other side of every match touching the negotiator's own records, correctly distinguishing "my listing matched their requirement" from "my requirement matched their listing".
- The SQL migration (`0006_matching.sql`) has been run in the user's Supabase project (Task 1's manual step) — without this, every matching read/write fails with Postgrest errors even though all code is correct.
- All 8 tasks committed individually.

## Explicitly not in this plan

Push notification delivery on new match (needs Firebase Cloud Messaging, not wired anywhere in this app). `cobroke_request`/Collaboration module (the proposal's ERD links `match_id` to a future `cobroke_request` table — next milestone, not this one). Recompute/re-threshold tuning UI. Fuzzy/partial location matching. Any change to `PostListingScreen`/`PostRequirementScreen` beyond the single added compute call in Task 5.
