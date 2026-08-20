# renly Requirement Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A verified negotiator can post an anonymised client requirement (with up to 3 optional reference photos), browse the requirement board of other negotiators' open requirements, manage their own requirements (open/fulfilled/withdrawn), and view a single requirement's detail page.

**Architecture:** Screens under `lib/features/requirement/` call a single `RequirementRepository` for every Supabase read/write, same pattern as `ListingRepository`. `Requirement.fromJson` and small pure helpers (`RequirementFormatting`, `RequirementStatusFilter`) are dependency-free Dart, unit-testable without Supabase. Photo upload is create-row-then-upload-then-attach, identical shape to Listing. Signed-URL photo display is extracted out of the Listing feature into a bucket-agnostic `SignedPhoto` widget so both features can use it without one depending on the other's repository.

**Tech Stack:** Flutter/Dart, Riverpod, `supabase_flutter`, `go_router`, `easy_localization`, `image_picker` (all already dependencies from Milestones 2-3).

## Global Constraints

- No screen calls `Supabase.instance.client` directly — always through `RequirementRepository`. Session-user-id reads go through a `currentNegotiatorIdProvider` defined fresh in `requirement_providers.dart` (Task 5) — deliberately **not** imported from `listing_providers.dart`, even though a provider of the same name and body already exists there, so the requirement feature only depends on the auth feature, not on a sibling feature, for something as basic as "who is logged in".
- Every new UI string goes into BOTH `app/assets/translations/en.json` and `app/assets/translations/ms.json` with matching keys — `app/test/l10n/translations_test.dart` already asserts key-set parity. Where a Listing-feature key's text is literally identical to what a Requirement screen needs (e.g. `listing_field_area` → "Area", `listing_property_type_apartment` → "Apartment"), **reuse the existing key** — don't create a duplicate. New keys are only added where the text is genuinely different (budget fields, photo cap of 3 vs 10, requirement-specific status actions).
- **Every test file with 2+ `testWidgets` sharing `EasyLocalization` MUST include, from the start:** `import 'package:flutter/services.dart';` and `setUp(() { rootBundle.clear(); });` right after `setUpAll`, plus `await tester.pumpAndSettle();` immediately after every `pumpWidget` and before any `tap`/`enterText` call. Real, previously-diagnosed bug: `rootBundle`'s `CachingAssetBundle` caches asset-load Futures process-wide, but `flutter_test` runs each `testWidgets` in its own torn-down `FakeAsync` zone, so the 2nd+ test hangs re-using the 1st test's stale cached Future.
- **Never swap a text-based test finder for a `Key`-based one because of an unverified "too many elements" guess.** If a test's tap/finder fails, scroll the `SingleChildScrollView` into view first (pattern is in Task 8) and diagnose for real before touching the finder strategy.
- Test assertions and tap targets use **hardcoded literal English strings** (e.g. `find.text('Post Requirement')`), not `.tr()` calls — matching the majority precedent across the Listing test suite (`marketplace_screen_test.dart`, `my_inventory_screen_test.dart`, `post_listing_screen_test.dart`, `property_detail_screen_test.dart` all do this).
- Currency is **RM** everywhere, with a `/mo` suffix for rentals — `RequirementFormatting.formatBudgetRange` takes `transactionType` as a third argument for exactly this reason, mirroring `ListingFormatting.formatPrice`.
- Colors/fonts/spacing come from `AppColors`/`AppTheme` (Milestone 1) — no new hardcoded hex values.
- SQL migration is a manual, user-performed step (Task 1) — this session has no DB credentials.
- Flutter is on PATH via `export PATH="$HOME/development/flutter/bin:$PATH"` — run first if `flutter` isn't found. All commands below assume this has been run and `cd` is `app/` unless stated otherwise.
- The `get_listing_owner_info(p_negotiator_id uuid)` RPC (already live from `0004_listing_hardening.sql`) is reused as-is for `fetchRequirementOwner` — it's already generic. No new RPC, no migration change needed for this.

---

### Task 1: Supabase migration SQL (0005_requirement.sql)

**Files:**
- Create: `supabase/migrations/0005_requirement.sql`
- Modify: `app/README.md` (append a "Milestone 4 setup" section)

**Interfaces:**
- Produces: the `requirement` table and `requirement-photos` storage bucket that Task 3's `RequirementRepository` calls assume exist.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0005_requirement.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0004.
--
-- Written to be re-runnable from the start (drop policy if exists / on
-- conflict do nothing / guarded constraint adds) -- 0003_listing.sql
-- shipped without `to authenticated` and column-scoped grants, and needed
-- a follow-up 0004_listing_hardening.sql to fix both. Those lessons are
-- folded in here directly instead of being deferred to a 0006.

create table if not exists requirement (
  requirement_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  property_type text not null check (property_type in ('apartment', 'house', 'commercial', 'land')),
  transaction_type text not null check (transaction_type in ('sale', 'rent')),
  state text not null,
  area text not null,
  budget_min numeric not null check (budget_min > 0),
  budget_max numeric not null check (budget_max >= budget_min),
  bedrooms integer,
  photo_urls text[] not null default '{}',
  status text not null default 'open' check (status in ('open', 'fulfilled', 'withdrawn')),
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'requirement_bedrooms_nonnegative') then
    alter table requirement add constraint requirement_bedrooms_nonnegative check (bedrooms is null or bedrooms >= 0);
  end if;
end $$;

alter table requirement enable row level security;

-- Owner sees all of their own requirements regardless of status; everyone
-- else (browsing the board) sees only open ones.
drop policy if exists requirement_select on requirement;
create policy requirement_select on requirement for select
  to authenticated using (negotiator_id = auth.uid() or status = 'open');

drop policy if exists requirement_insert_own on requirement;
create policy requirement_insert_own on requirement for insert
  to authenticated with check (negotiator_id = auth.uid());

drop policy if exists requirement_update_own on requirement;
create policy requirement_update_own on requirement for update
  to authenticated using (negotiator_id = auth.uid());

-- Column-scoped INSERT: requirement_id, photo_urls, status and created_at
-- stay at their table defaults on insert (photos are attached by a
-- follow-up UPDATE once they have been uploaded under the new
-- requirement_id).
revoke insert on requirement from authenticated;
grant insert (
  negotiator_id, property_type, transaction_type, state, area,
  budget_min, budget_max, bedrooms
) on requirement to authenticated;

-- Column-scoped UPDATE: requirement_id, negotiator_id and created_at are
-- deliberately excluded -- RLS restricts which ROW may be updated, only
-- GRANT/REVOKE can restrict which COLUMNS. photo_urls IS included here
-- (not in the insert grant) because photos are attached via UPDATE after
-- the row already exists.
revoke update on requirement from authenticated;
grant update (
  property_type, transaction_type, state, area, budget_min, budget_max,
  bedrooms, status, photo_urls
) on requirement to authenticated;

-- Storage: path convention {negotiator_id}/{requirement_id}/{n}.jpg
insert into storage.buckets (id, name, public) values ('requirement-photos', 'requirement-photos', false)
  on conflict (id) do nothing;

drop policy if exists requirement_photos_select_authenticated on storage.objects;
create policy requirement_photos_select_authenticated on storage.objects for select
  to authenticated using (bucket_id = 'requirement-photos');

drop policy if exists requirement_photos_insert_own on storage.objects;
create policy requirement_photos_insert_own on storage.objects for insert
  to authenticated with check (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists requirement_photos_update_own on storage.objects;
create policy requirement_photos_update_own on storage.objects for update
  to authenticated using (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists requirement_photos_delete_own on storage.objects;
create policy requirement_photos_delete_own on storage.objects for delete
  to authenticated using (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text);

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'requirement-photos';
```

- [ ] **Step 2: Verify the file is well-formed**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0005_requirement.sql
grep -c "^create policy" supabase/migrations/0005_requirement.sql
```
Expected: `1` (requirement) and `7` (requirement_select, requirement_insert_own, requirement_update_own, requirement_photos_select_authenticated, requirement_photos_insert_own, requirement_photos_update_own, requirement_photos_delete_own).

- [ ] **Step 3: Append manual setup instructions to app/README.md**

Read the current `app/README.md` first (it has Milestone 1-3 setup sections). Append:

```markdown

## Milestone 4 setup (requirement)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0005_requirement.sql` (repo root) -> Run. This creates the `requirement` table, its RLS policies (scoped to `authenticated` and column-grant hardened from the start this time), and the `requirement-photos` storage bucket. No Auth-dashboard changes needed. Unlike Milestone 3, there's no separate hardening file to run afterwards -- everything is in this one file.
```

- [ ] **Step 4: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add supabase/migrations/0005_requirement.sql app/README.md
git commit -m "feat: add requirement Supabase migration and setup docs"
```

---

### Task 2: Requirement model + pure helpers (TDD)

**Files:**
- Create: `app/lib/features/requirement/models/requirement.dart`
- Create: `app/lib/features/requirement/requirement_formatting.dart`
- Create: `app/lib/features/requirement/requirement_status_filter.dart`
- Test: `app/test/features/requirement/models/requirement_test.dart`
- Test: `app/test/features/requirement/requirement_formatting_test.dart`
- Test: `app/test/features/requirement/requirement_status_filter_test.dart`

**Interfaces:**
- Produces: `Requirement` (fields: `requirementId`, `negotiatorId`, `propertyType`, `transactionType`, `state`, `area`, `budgetMin` (`double`), `budgetMax` (`double`), `bedrooms` (`int?`), `photoUrls` (`List<String>`), `status`, all `final`) with `Requirement.fromJson(Map<String, dynamic>)`. `RequirementFormatting.formatBudgetRange(num min, num max, String transactionType)` → `String`. `RequirementStatusFilter.byStatus(List<Requirement>, String status)` → `List<Requirement>`. Every later task imports these. Reuses `malaysianStates` from `app/lib/core/constants/malaysian_states.dart` (Milestone 3) — no new states constant needed.

- [ ] **Step 1: Write the failing Requirement model test**

```dart
// app/test/features/requirement/models/requirement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/requirement/models/requirement.dart';

void main() {
  group('Requirement.fromJson', () {
    test('parses a full row', () {
      final requirement = Requirement.fromJson({
        'requirement_id': 'r-1',
        'negotiator_id': 'n-1',
        'property_type': 'apartment',
        'transaction_type': 'sale',
        'state': 'Selangor',
        'area': 'Petaling Jaya',
        'budget_min': 300000,
        'budget_max': 500000,
        'bedrooms': 3,
        'photo_urls': ['n-1/r-1/0.jpg'],
        'status': 'open',
      });

      expect(requirement.requirementId, 'r-1');
      expect(requirement.negotiatorId, 'n-1');
      expect(requirement.propertyType, 'apartment');
      expect(requirement.transactionType, 'sale');
      expect(requirement.state, 'Selangor');
      expect(requirement.area, 'Petaling Jaya');
      expect(requirement.budgetMin, 300000.0);
      expect(requirement.budgetMax, 500000.0);
      expect(requirement.bedrooms, 3);
      expect(requirement.photoUrls, ['n-1/r-1/0.jpg']);
      expect(requirement.status, 'open');
    });

    test('handles null bedrooms and empty photo_urls', () {
      final requirement = Requirement.fromJson({
        'requirement_id': 'r-2',
        'negotiator_id': 'n-1',
        'property_type': 'land',
        'transaction_type': 'sale',
        'state': 'Johor',
        'area': 'Iskandar Puteri',
        'budget_min': 100000,
        'budget_max': 200000,
        'bedrooms': null,
        'photo_urls': null,
        'status': 'open',
      });

      expect(requirement.bedrooms, isNull);
      expect(requirement.photoUrls, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/requirement/models/requirement_test.dart
```
Expected: FAIL — `package:renly/features/requirement/models/requirement.dart` not found.

- [ ] **Step 3: Implement Requirement**

```dart
// app/lib/features/requirement/models/requirement.dart

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

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/requirement/models/requirement_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 5: Write the failing RequirementFormatting test**

```dart
// app/test/features/requirement/requirement_formatting_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/requirement/requirement_formatting.dart';

void main() {
  group('RequirementFormatting.formatBudgetRange', () {
    test('formats a sale range with thousands separators, no suffix', () {
      expect(RequirementFormatting.formatBudgetRange(300000, 500000, 'sale'), 'RM 300,000 - RM 500,000');
    });

    test('formats a rent range with /mo suffix', () {
      expect(RequirementFormatting.formatBudgetRange(2000, 3500, 'rent'), 'RM 2,000 - RM 3,500 /mo');
    });

    test('formats a range under 1000 with no separator', () {
      expect(RequirementFormatting.formatBudgetRange(500, 900, 'sale'), 'RM 500 - RM 900');
    });
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

```bash
flutter test test/features/requirement/requirement_formatting_test.dart
```
Expected: FAIL — `package:renly/features/requirement/requirement_formatting.dart` not found.

- [ ] **Step 7: Implement RequirementFormatting**

```dart
// app/lib/features/requirement/requirement_formatting.dart

/// Pure budget-range-display formatting. No Flutter/Supabase -- fully
/// unit-testable. Mirrors ListingFormatting.formatPrice's /mo-for-rent
/// convention -- a rental requirement's budget is a monthly figure too.
class RequirementFormatting {
  RequirementFormatting._();

  static String formatBudgetRange(num min, num max, String transactionType) {
    final suffix = transactionType == 'rent' ? ' /mo' : '';
    return '${_formatAmount(min)} - ${_formatAmount(max)}$suffix';
  }

  static String _formatAmount(num amount) {
    // Same NaN/Infinity guard as ListingFormatting: Postgres' `> 0` CHECK
    // does not reject 'NaN'::numeric, so one malformed row would otherwise
    // crash every client rendering the board.
    if (!amount.isFinite) return 'RM —';
    final rounded = amount.round();
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return 'RM $buffer';
  }
}
```

- [ ] **Step 8: Run test to verify it passes**

```bash
flutter test test/features/requirement/requirement_formatting_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 9: Write the failing RequirementStatusFilter test**

```dart
// app/test/features/requirement/requirement_status_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_status_filter.dart';

Requirement _requirement(String id, String status) {
  return Requirement(
    requirementId: id,
    negotiatorId: 'n-1',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'PJ',
    budgetMin: 100000,
    budgetMax: 200000,
    photoUrls: const [],
    status: status,
  );
}

void main() {
  group('RequirementStatusFilter.byStatus', () {
    test('returns only requirements matching the given status', () {
      final requirements = [_requirement('1', 'open'), _requirement('2', 'fulfilled'), _requirement('3', 'open')];
      final result = RequirementStatusFilter.byStatus(requirements, 'open');
      expect(result.map((r) => r.requirementId), ['1', '3']);
    });

    test('returns empty list when nothing matches', () {
      final requirements = [_requirement('1', 'open')];
      expect(RequirementStatusFilter.byStatus(requirements, 'withdrawn'), isEmpty);
    });
  });
}
```

- [ ] **Step 10: Run test to verify it fails**

```bash
flutter test test/features/requirement/requirement_status_filter_test.dart
```
Expected: FAIL — `package:renly/features/requirement/requirement_status_filter.dart` not found.

- [ ] **Step 11: Implement RequirementStatusFilter**

```dart
// app/lib/features/requirement/requirement_status_filter.dart
import 'models/requirement.dart';

/// Pure client-side tab filter for My Requirements (open/fulfilled/withdrawn).
class RequirementStatusFilter {
  RequirementStatusFilter._();

  static List<Requirement> byStatus(List<Requirement> requirements, String status) {
    return requirements.where((requirement) => requirement.status == status).toList();
  }
}
```

- [ ] **Step 12: Run test to verify it passes**

```bash
flutter test test/features/requirement/requirement_status_filter_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 13: Run the full requirement test directory to confirm everything from this task passes together**

```bash
flutter test test/features/requirement/
```
Expected: `00:0X +7: All tests passed!` (2 Requirement + 3 RequirementFormatting + 2 RequirementStatusFilter).

- [ ] **Step 14: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/requirement/models/requirement.dart app/lib/features/requirement/requirement_formatting.dart app/lib/features/requirement/requirement_status_filter.dart app/test/features/requirement/
git commit -m "feat: add Requirement model and pure formatting/filter helpers"
```

---

### Task 3: RequirementRepository (Supabase I/O)

**Files:**
- Create: `app/lib/features/requirement/requirement_repository.dart`

**Interfaces:**
- Consumes: `Requirement` (Task 2), `ListingOwner` (`../listing/models/listing_owner.dart`, Milestone 3 — reused as-is, no new owner model).
- Produces: `RequirementRepository(SupabaseClient client)` with methods `fetchBoardRequirements`, `fetchOwnRequirements`, `fetchRequirementById`, `fetchRequirementOwner`, `createSignedUrl`, `uploadRequirementPhoto`, `createRequirement`, `updateRequirementPhotos`, `updateRequirementStatus` — every later screen task calls these.

No TDD for this task (same documented boundary as `ListingRepository` — Supabase-calling code isn't unit-tested in this project). Verify with `flutter analyze` only.

- [ ] **Step 1: Implement RequirementRepository**

```dart
// app/lib/features/requirement/requirement_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/models/listing_owner.dart';
import 'models/requirement.dart';

/// The only file in this app that talks to Supabase for the requirement
/// feature. Screens call these methods; nothing else touches
/// `SupabaseClient` for requirements.
class RequirementRepository {
  RequirementRepository(this._client);

  final SupabaseClient _client;

  Future<List<Requirement>> fetchBoardRequirements() async {
    final rows = await _client
        .from('requirement')
        .select()
        .eq('status', 'open')
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Requirement.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<List<Requirement>> fetchOwnRequirements(String negotiatorId) async {
    final rows = await _client
        .from('requirement')
        .select()
        .eq('negotiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Requirement.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<Requirement> fetchRequirementById(String requirementId) async {
    final row = await _client.from('requirement').select().eq('requirement_id', requirementId).single();
    return Requirement.fromJson(row);
  }

  /// Reuses the get_listing_owner_info security-definer RPC
  /// (0004_listing_hardening.sql) rather than a new requirement-specific
  /// one -- it already takes any negotiator id and returns only
  /// full_name/ren_number, nothing listing-specific about its logic. The
  /// name is a minor accepted naming debt (see the design doc).
  Future<ListingOwner> fetchRequirementOwner(String negotiatorId) async {
    final rows = await _client.rpc(
      'get_listing_owner_info',
      params: {'p_negotiator_id': negotiatorId},
    ) as List;
    if (rows.isEmpty) {
      throw StateError('Negotiator not found: $negotiatorId');
    }
    return ListingOwner.fromJson(rows.first as Map<String, dynamic>);
  }

  /// The `requirement-photos` bucket is private, so photos can only be
  /// rendered through a short-lived signed URL (1 hour).
  Future<String> createSignedUrl(String path) {
    return _client.storage.from('requirement-photos').createSignedUrl(path, 3600);
  }

  Future<String> uploadRequirementPhoto({
    required String negotiatorId,
    required String requirementId,
    required int index,
    required Uint8List bytes,
  }) async {
    final path = '$negotiatorId/$requirementId/$index.jpg';
    await _client.storage.from('requirement-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  /// Creates the requirement row WITHOUT photos (photo_urls defaults to
  /// '{}'). Photos are uploaded after this returns, using the new
  /// requirement_id in their Storage path, then attached via
  /// updateRequirementPhotos.
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

  Future<void> updateRequirementPhotos({required String requirementId, required List<String> photoUrls}) {
    return _client.from('requirement').update({'photo_urls': photoUrls}).eq('requirement_id', requirementId);
  }

  Future<void> updateRequirementStatus({required String requirementId, required String status}) {
    return _client.from('requirement').update({'status': status}).eq('requirement_id', requirementId);
  }
}
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/requirement/requirement_repository.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/requirement/requirement_repository.dart
git commit -m "feat: add RequirementRepository"
```

---

### Task 4: Extract SignedPhoto widget, refactor ListingPhoto to use it

**Files:**
- Create: `app/lib/core/widgets/signed_photo.dart`
- Modify: `app/lib/features/listing/listing_photo.dart`

**Interfaces:**
- Produces: `SignedPhoto({required String path, required Future<String> Function(String) signedUrlFetcher, BoxFit fit})` — a `StatefulWidget`, no Riverpod dependency of its own. Tasks 6 and 9 use this directly with `ref.read(requirementRepositoryProvider).createSignedUrl`.
- Consumes (for the refactor): the existing `listingRepositoryProvider` (Milestone 3).

**Why this task exists:** the current `ListingPhoto` widget (`app/lib/features/listing/listing_photo.dart`) is not actually bucket-generic — it calls `ref.read(listingRepositoryProvider).createSignedUrl(path)` internally, hardcoded to the `listing-photos` bucket. Reusing it as-is for `requirement-photos` would silently fetch from the wrong bucket. This was caught while writing this plan, not during the original Listing review. `ListingPhoto`'s public API (`ListingPhoto({path, fit})`) stays exactly the same, so its two existing call sites (`marketplace_screen.dart`, `property_detail_screen.dart`) need zero changes — this task is a pure internal refactor plus one new shared file.

No TDD for this task — `ListingPhoto`/`SignedPhoto` are Supabase-adjacent (fetch through a repository), the same untested boundary as the repositories themselves; their loading/placeholder states are already implicitly covered by `marketplace_screen_test.dart` and `property_detail_screen_test.dart` (both use fixtures with empty `photoUrls`, so the signed-URL fetch path itself was never exercised even before this refactor — this task does not change that existing boundary). Verify with `flutter analyze` plus a full re-run of the existing Listing test suite to catch any regression.

- [ ] **Step 1: Implement SignedPhoto**

```dart
// app/lib/core/widgets/signed_photo.dart
import 'package:flutter/material.dart';

/// Displays a single photo by fetching a short-lived signed URL through the
/// given [signedUrlFetcher]. Shows a placeholder while loading or on error
/// (e.g. a photo whose upload never completed). Bucket-agnostic: callers
/// pass in whichever repository method knows which private bucket to sign
/// against (ListingRepository.createSignedUrl, RequirementRepository's
/// equivalent, etc.) -- this widget itself has no Supabase/Riverpod
/// dependency.
class SignedPhoto extends StatefulWidget {
  const SignedPhoto({super.key, required this.path, required this.signedUrlFetcher, this.fit = BoxFit.cover});

  final String path;
  final Future<String> Function(String path) signedUrlFetcher;
  final BoxFit fit;

  @override
  State<SignedPhoto> createState() => _SignedPhotoState();
}

class _SignedPhotoState extends State<SignedPhoto> {
  // Held in State, not created inline in build(): a FutureBuilder whose
  // future is rebuilt every frame would re-request a signed URL on every
  // rebuild (and never settle in widget tests).
  late Future<String> _signedUrl;

  @override
  void initState() {
    super.initState();
    _signedUrl = widget.signedUrlFetcher(widget.path);
  }

  @override
  void didUpdateWidget(SignedPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _signedUrl = widget.signedUrlFetcher(widget.path);
    }
  }

  Widget _placeholder(BuildContext context) {
    return Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _signedUrl,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
          return _placeholder(context);
        }
        return Image.network(
          snapshot.data!,
          fit: widget.fit,
          errorBuilder: (context, error, stack) => _placeholder(context),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Refactor ListingPhoto into a thin wrapper**

Read the current `app/lib/features/listing/listing_photo.dart` first. Replace its entire contents:

```dart
// app/lib/features/listing/listing_photo.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/signed_photo.dart';
import 'listing_providers.dart';

/// Thin wrapper binding SignedPhoto to the listing-photos bucket via
/// ListingRepository.createSignedUrl. Extracted this way (rather than
/// SignedPhoto reading listingRepositoryProvider itself) so the
/// requirement feature can reuse SignedPhoto against its own bucket
/// without depending on the listing feature's repository.
class ListingPhoto extends ConsumerWidget {
  const ListingPhoto({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SignedPhoto(
      path: path,
      fit: fit,
      signedUrlFetcher: ref.read(listingRepositoryProvider).createSignedUrl,
    );
  }
}
```

- [ ] **Step 3: Run the full existing Listing test suite to confirm zero regressions**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/listing/
```
Expected: every test still passes, same pass count as before this task (this refactor changes `ListingPhoto`'s internals but not its public API, and neither `marketplace_screen.dart` nor `property_detail_screen.dart` needed edits — if this fails, check whether `ListingPhoto`'s constructor signature was accidentally changed).

- [ ] **Step 4: Verify static analysis is clean**

```bash
flutter analyze lib/core/widgets/signed_photo.dart lib/features/listing/listing_photo.dart
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/core/widgets/signed_photo.dart app/lib/features/listing/listing_photo.dart
git commit -m "refactor: extract bucket-agnostic SignedPhoto widget out of ListingPhoto"
```

---

### Task 5: requirement_providers.dart

**Files:**
- Create: `app/lib/features/requirement/requirement_providers.dart`

**Interfaces:**
- Consumes: `RequirementRepository` (Task 3), `authStateProvider` (from `../auth/auth_providers.dart`, Milestone 2), `ListingOwner` (`../listing/models/listing_owner.dart`).
- Produces: `requirementRepositoryProvider` (`Provider<RequirementRepository>`), `currentNegotiatorIdProvider` (`Provider<String?>`), `boardRequirementsProvider` (`FutureProvider<List<Requirement>>`), `myRequirementsProvider` (`FutureProvider.family<List<Requirement>, String>`), `requirementDetailProvider` (`FutureProvider.family<Requirement, String>`), `requirementOwnerProvider` (`FutureProvider.family<ListingOwner, String>`, keyed by `negotiatorId`) — every screen task uses these.

No TDD for this task (Riverpod wiring around Supabase singletons, same boundary as `listing_providers.dart`). Verify with `flutter analyze`.

- [ ] **Step 1: Implement requirement_providers.dart**

```dart
// app/lib/features/requirement/requirement_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/models/listing_owner.dart';
import 'models/requirement.dart';
import 'requirement_repository.dart';

final requirementRepositoryProvider = Provider<RequirementRepository>((ref) {
  return RequirementRepository(Supabase.instance.client);
});

/// Same session-state read as listing_providers.dart's
/// currentNegotiatorIdProvider -- duplicated here rather than imported from
/// the listing feature, so the requirement feature only depends on auth,
/// not on a sibling feature, for something this basic.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

final boardRequirementsProvider = FutureProvider<List<Requirement>>((ref) {
  return ref.watch(requirementRepositoryProvider).fetchBoardRequirements();
});

final myRequirementsProvider = FutureProvider.family<List<Requirement>, String>((ref, negotiatorId) {
  return ref.watch(requirementRepositoryProvider).fetchOwnRequirements(negotiatorId);
});

final requirementDetailProvider = FutureProvider.family<Requirement, String>((ref, requirementId) {
  return ref.watch(requirementRepositoryProvider).fetchRequirementById(requirementId);
});

final requirementOwnerProvider = FutureProvider.family<ListingOwner, String>((ref, negotiatorId) {
  return ref.watch(requirementRepositoryProvider).fetchRequirementOwner(negotiatorId);
});
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/requirement/requirement_providers.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/requirement/requirement_providers.dart
git commit -m "feat: add requirement Riverpod providers"
```

---

### Task 6: RequirementBoardScreen

**Files:**
- Create: `app/lib/features/requirement/requirement_board_screen.dart`
- Test: `app/test/features/requirement/requirement_board_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `boardRequirementsProvider`, `requirementOwnerProvider`, `requirementRepositoryProvider` (Task 5), `Requirement`/`RequirementFormatting` (Task 2), `SignedPhoto` (Task 4).
- Produces: `RequirementBoardScreen` (`ConsumerStatefulWidget`) — Task 10's router uses it as `/requirement-board`. Navigates via `context.push('/requirement-board/${requirement.requirementId}')`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/requirement/requirement_board_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_board_screen.dart';
import 'package:renly/features/requirement/requirement_providers.dart';

final _fixtureRequirements = [
  const Requirement(
    requirementId: 'r-1',
    negotiatorId: 'n-1',
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
  const Requirement(
    requirementId: 'r-2',
    negotiatorId: 'n-2',
    propertyType: 'apartment',
    transactionType: 'rent',
    state: 'W.P. Kuala Lumpur',
    area: 'Bukit Bintang',
    budgetMin: 2000,
    budgetMax: 3500,
    bedrooms: 1,
    photoUrls: [],
    status: 'open',
  ),
];

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {List<Requirement>? requirements}) {
  return ProviderScope(
    overrides: [
      boardRequirementsProvider.overrideWith((ref) async => requirements ?? _fixtureRequirements),
      requirementOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
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

  testWidgets('renders formatted budget range, criteria, area, and owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementBoardScreen()),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 300,000 - RM 500,000'), findsOneWidget);
    expect(find.text('RM 2,000 - RM 3,500 /mo'), findsOneWidget);
    expect(find.text('Apartment · Sale'), findsOneWidget);
    expect(find.text('Apartment · Rent'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Bukit Bintang'), findsOneWidget);
    expect(find.text('Aiman Yusof (REN: 12345)'), findsNWidgets(2));
  });

  testWidgets('tapping a requirement card navigates to its detail route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementBoardScreen()),
      GoRoute(
        path: '/requirement-board/:requirementId',
        builder: (context, state) => Text('detail-${state.pathParameters['requirementId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RM 300,000 - RM 500,000'));
    await tester.pumpAndSettle();

    expect(find.text('detail-r-1'), findsOneWidget);
  });

  testWidgets('renders empty state when no requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementBoardScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, requirements: []));
    await tester.pumpAndSettle();

    expect(find.text('No requirements yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/requirement/requirement_board_screen_test.dart
```
Expected: FAIL — `package:renly/features/requirement/requirement_board_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "requirement_board_title": "Requirement Board",
  "requirement_board_search_hint": "Search location...",
  "requirement_board_empty": "No requirements yet"
```

`app/assets/translations/ms.json` additions:
```json
  "requirement_board_title": "Papan Keperluan",
  "requirement_board_search_hint": "Cari lokasi...",
  "requirement_board_empty": "Tiada keperluan lagi"
```

- [ ] **Step 4: Implement RequirementBoardScreen**

```dart
// app/lib/features/requirement/requirement_board_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/signed_photo.dart';
import 'models/requirement.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';

/// Browse all open requirements across negotiators -- same shape as
/// MarketplaceScreen, but for requirement criteria instead of listings.
class RequirementBoardScreen extends ConsumerStatefulWidget {
  const RequirementBoardScreen({super.key});

  @override
  ConsumerState<RequirementBoardScreen> createState() => _RequirementBoardScreenState();
}

class _RequirementBoardScreenState extends ConsumerState<RequirementBoardScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Requirement> _filter(List<Requirement> requirements) {
    if (_query.trim().isEmpty) return requirements;
    final q = _query.toLowerCase();
    return requirements
        .where((r) => r.area.toLowerCase().contains(q) || r.state.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final requirementsAsync = ref.watch(boardRequirementsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('requirement_board_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'requirement_board_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: requirementsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
              data: (requirements) {
                final filtered = _filter(requirements);
                if (filtered.isEmpty) {
                  return Center(child: Text('requirement_board_empty'.tr()));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(boardRequirementsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final requirement = filtered[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (requirement.photoUrls.isNotEmpty) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: SignedPhoto(
                                        path: requirement.photoUrls.first,
                                        signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        RequirementFormatting.formatBudgetRange(
                                          requirement.budgetMin,
                                          requirement.budgetMax,
                                          requirement.transactionType,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: AppColors.primary),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${'listing_property_type_${requirement.propertyType}'.tr()} · '
                                        '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (requirement.bedrooms != null) ...[
                                            const Icon(Icons.bed, size: 16),
                                            const SizedBox(width: 4),
                                            Text('${requirement.bedrooms}'),
                                            const SizedBox(width: 12),
                                          ],
                                          Flexible(
                                            child: Text(
                                              requirement.area,
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Builder(builder: (context) {
                                        final ownerAsync =
                                            ref.watch(requirementOwnerProvider(requirement.negotiatorId));
                                        return ownerAsync.when(
                                          loading: () => const SizedBox.shrink(),
                                          error: (error, stack) => const SizedBox.shrink(),
                                          data: (owner) => Text(
                                            '${owner.fullName} (REN: ${owner.renNumber})',
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/requirement/requirement_board_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/requirement/requirement_board_screen.dart app/test/features/requirement/requirement_board_screen_test.dart app/assets/translations/
git commit -m "feat: add RequirementBoardScreen"
```

---

### Task 7: MyRequirementsScreen

**Files:**
- Create: `app/lib/features/requirement/my_requirements_screen.dart`
- Test: `app/test/features/requirement/my_requirements_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `myRequirementsProvider`, `currentNegotiatorIdProvider` (Task 5), `RequirementStatusFilter`, `RequirementFormatting` (Task 2). Navigates via `context.push('/post-requirement')` and `context.push('/requirement-board/${requirement.requirementId}')`.
- Produces: `MyRequirementsScreen` (`ConsumerStatefulWidget`) — Task 10's router uses it as `/my-requirements`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/requirement/my_requirements_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/my_requirements_screen.dart';
import 'package:renly/features/requirement/requirement_providers.dart';

final _fixtureRequirements = [
  const Requirement(
    requirementId: 'r-1',
    negotiatorId: 'n-1',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    budgetMin: 500000,
    budgetMax: 700000,
    photoUrls: [],
    status: 'open',
  ),
  const Requirement(
    requirementId: 'r-2',
    negotiatorId: 'n-1',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    budgetMin: 800000,
    budgetMax: 900000,
    photoUrls: [],
    status: 'fulfilled',
  ),
];

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myRequirementsProvider.overrideWith((ref, negotiatorId) async => _fixtureRequirements),
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

  testWidgets('Open tab shows only open requirements by default', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequirementsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 500,000 - RM 700,000'), findsOneWidget);
    expect(find.text('RM 800,000 - RM 900,000'), findsNothing);
  });

  testWidgets('switching to Fulfilled tab shows only fulfilled requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequirementsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fulfilled'));
    await tester.pumpAndSettle();

    expect(find.text('RM 800,000 - RM 900,000'), findsOneWidget);
    expect(find.text('RM 500,000 - RM 700,000'), findsNothing);
  });

  testWidgets('tapping Post New Requirement navigates to /post-requirement', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequirementsScreen()),
      GoRoute(path: '/post-requirement', builder: (context, state) => const Text('post-requirement-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('post-requirement-screen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/requirement/my_requirements_screen_test.dart
```
Expected: FAIL — `package:renly/features/requirement/my_requirements_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "requirement_my_title": "My Requirements",
  "requirement_tab_open": "Open",
  "requirement_tab_fulfilled": "Fulfilled",
  "requirement_post_new": "Post New Requirement",
  "requirement_my_empty": "No requirements in this tab yet"
```

`app/assets/translations/ms.json` additions:
```json
  "requirement_my_title": "Keperluan Saya",
  "requirement_tab_open": "Terbuka",
  "requirement_tab_fulfilled": "Dipenuhi",
  "requirement_post_new": "Siarkan Keperluan Baharu",
  "requirement_my_empty": "Tiada keperluan dalam tab ini lagi"
```

- [ ] **Step 4: Implement MyRequirementsScreen**

```dart
// app/lib/features/requirement/my_requirements_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'requirement_formatting.dart';
import 'requirement_providers.dart';
import 'requirement_status_filter.dart';

/// Ports the my_inventory shape for requirements -- open/fulfilled/withdrawn
/// tabs instead of active/sold/withdrawn.
class MyRequirementsScreen extends ConsumerStatefulWidget {
  const MyRequirementsScreen({super.key});

  @override
  ConsumerState<MyRequirementsScreen> createState() => _MyRequirementsScreenState();
}

class _MyRequirementsScreenState extends ConsumerState<MyRequirementsScreen> {
  String _selectedStatus = 'open';

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('requirement_my_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'open', label: Text('requirement_tab_open'.tr())),
                ButtonSegment(value: 'fulfilled', label: Text('requirement_tab_fulfilled'.tr())),
                ButtonSegment(value: 'withdrawn', label: Text('inventory_tab_withdrawn'.tr())),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (selection) => setState(() => _selectedStatus = selection.first),
            ),
          ),
          Expanded(
            // A null negotiatorId here is a brief startup race (the auth
            // redirect already guarantees a session reaches this route),
            // so it reads as "still loading", not as an error state.
            child: negotiatorId == null
                ? const Center(child: CircularProgressIndicator())
                : Consumer(
                    builder: (context, ref, _) {
                      final requirementsAsync = ref.watch(myRequirementsProvider(negotiatorId));
                      return requirementsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                        data: (requirements) {
                          final filtered = RequirementStatusFilter.byStatus(requirements, _selectedStatus);
                          if (filtered.isEmpty) {
                            return Center(child: Text('requirement_my_empty'.tr()));
                          }
                          return RefreshIndicator(
                            onRefresh: () async =>
                                ref.invalidate(myRequirementsProvider(negotiatorId)),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final requirement = filtered[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: ListTile(
                                    onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                                    title: Text(
                                      RequirementFormatting.formatBudgetRange(
                                        requirement.budgetMin,
                                        requirement.budgetMax,
                                        requirement.transactionType,
                                      ),
                                    ),
                                    subtitle: Text('${requirement.area}, ${requirement.state}'),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              onPressed: () => context.push('/post-requirement'),
              child: Text('requirement_post_new'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/requirement/my_requirements_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/requirement/my_requirements_screen.dart app/test/features/requirement/my_requirements_screen_test.dart app/assets/translations/
git commit -m "feat: add MyRequirementsScreen"
```

---

### Task 8: PostRequirementScreen (photo upload capped at 3, budget validation)

**Files:**
- Create: `app/lib/features/requirement/post_requirement_screen.dart`
- Test: `app/test/features/requirement/post_requirement_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `requirementRepositoryProvider`, `currentNegotiatorIdProvider`, `boardRequirementsProvider`, `myRequirementsProvider` (Task 5), `malaysianStates` (`../../core/constants/malaysian_states.dart`, Milestone 3).
- Produces: `PostRequirementScreen` (`ConsumerStatefulWidget`) — on success, calls `context.go('/my-requirements')`. Task 10's router uses it as `/post-requirement`.

Same retry-safe create-then-upload-then-attach flow as `PostListingScreen`, capped at 3 photos instead of 10. The `budget_max` field validates `>= budget_min` inline (reading `_budgetMinController.text` from within `budget_max`'s own `TextFormField.validator`) — this is the addition the user asked to fold into the design after reviewing it, giving immediate feedback instead of a failed-insert round trip against the DB's `budget_max >= budget_min` CHECK. If this screen's tests need to tap a submit button below the fold, scroll the `SingleChildScrollView` into view first — do NOT swap the finder for a `Key` on an unverified guess (see Global Constraints).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/requirement/post_requirement_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/requirement/post_requirement_screen.dart';

Widget _wrap(GoRouter router) {
  return ProviderScope(
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

  testWidgets('renders all required fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostRequirementScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('requirement_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_transaction_type_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_state_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_area_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_budget_min_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_budget_max_field')), findsOneWidget);
  });

  testWidgets('submitting with empty required fields shows validation errors', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostRequirementScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('shows inline error when max budget is below min budget', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostRequirementScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('requirement_area_field')), 'Petaling Jaya');
    await tester.enterText(find.byKey(const Key('requirement_budget_min_field')), '500000');
    await tester.enterText(find.byKey(const Key('requirement_budget_max_field')), '300000');

    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('Maximum budget must be at least the minimum'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/requirement/post_requirement_screen_test.dart
```
Expected: FAIL — `package:renly/features/requirement/post_requirement_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "requirement_post_title": "Post a Requirement",
  "requirement_field_budget_min": "Minimum Budget (RM)",
  "requirement_field_budget_max": "Maximum Budget (RM)",
  "requirement_budget_max_below_min": "Maximum budget must be at least the minimum",
  "requirement_photos_max": "Max 3",
  "requirement_post_now": "Post Requirement"
```

`app/assets/translations/ms.json` additions:
```json
  "requirement_post_title": "Siarkan Keperluan",
  "requirement_field_budget_min": "Bajet Minimum (RM)",
  "requirement_field_budget_max": "Bajet Maksimum (RM)",
  "requirement_budget_max_below_min": "Bajet maksimum mestilah sekurang-kurangnya sama dengan minimum",
  "requirement_photos_max": "Maksimum 3",
  "requirement_post_now": "Siarkan Keperluan"
```

Note: `property_type`/`transaction_type`/`state`/`area`/`bedrooms` field labels and the `Add Photo`/`Photos` labels reuse Listing's existing `listing_field_*`/`listing_photos_label`/`listing_add_photo`/`listing_property_type_*`/`listing_transaction_type_*` keys — identical text, no duplicates added.

- [ ] **Step 4: Implement PostRequirementScreen**

```dart
// app/lib/features/requirement/post_requirement_screen.dart
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/malaysian_states.dart';
import 'requirement_providers.dart';

/// Separate screen from PostListingScreen -- see the design doc for why the
/// mockup's tab toggle isn't retrofitted into the shared, already-tested
/// listing form.
class PostRequirementScreen extends ConsumerStatefulWidget {
  const PostRequirementScreen({super.key});

  @override
  ConsumerState<PostRequirementScreen> createState() => _PostRequirementScreenState();
}

class _PostRequirementScreenState extends ConsumerState<PostRequirementScreen> {
  static const _maxPhotos = 3;

  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();
  final _budgetMinController = TextEditingController();
  final _budgetMaxController = TextEditingController();
  final _bedroomsController = TextEditingController();
  String _propertyType = 'apartment';
  String _transactionType = 'sale';
  String _state = malaysianStates.first;
  final List<XFile> _photos = [];
  bool _submitting = false;
  String? _submitError;

  /// Same retry-safety as PostListingScreen: set once createRequirement()
  /// succeeds, so a retry after a failed photo upload resumes from the
  /// upload step instead of inserting a second row.
  String? _createdRequirementId;

  @override
  void dispose() {
    _areaController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    _bedroomsController.dispose();
    super.dispose();
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
  /// PostListingScreen's cache: removing a photo shouldn't shift every
  /// later thumbnail onto the wrong cached bytes.
  final Map<String, Future<Uint8List>> _photoBytesCache = {};

  Future<Uint8List> _photoBytes(int index) {
    final photo = _photos[index];
    return _photoBytesCache.putIfAbsent(photo.path, photo.readAsBytes);
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
    return Scaffold(
      appBar: AppBar(title: Text('requirement_post_title'.tr())),
      body: SafeArea(
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
                TextFormField(
                  controller: _bedroomsController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'listing_field_bedrooms'.tr()),
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
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('requirement_post_now'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/requirement/post_requirement_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/requirement/post_requirement_screen.dart app/test/features/requirement/post_requirement_screen_test.dart app/assets/translations/
git commit -m "feat: add PostRequirementScreen with capped photo upload and budget validation"
```

---

### Task 9: RequirementDetailScreen

**Files:**
- Create: `app/lib/features/requirement/requirement_detail_screen.dart`
- Test: `app/test/features/requirement/requirement_detail_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `requirementDetailProvider`, `requirementOwnerProvider`, `currentNegotiatorIdProvider`, `requirementRepositoryProvider`, `boardRequirementsProvider`, `myRequirementsProvider` (Task 5), `SignedPhoto` (Task 4).
- Produces: `RequirementDetailScreen` (`ConsumerStatefulWidget`, constructor `{required this.requirementId}`) — Task 10's router uses it for `/requirement-board/:requirementId`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/requirement/requirement_detail_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_detail_screen.dart';
import 'package:renly/features/requirement/requirement_providers.dart';

const _fixtureRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-1',
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

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2'}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      requirementDetailProvider.overrideWith((ref, requirementId) async => _fixtureRequirement),
      requirementOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
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

  testWidgets('renders budget range, criteria, location, and owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 300,000 - RM 500,000'), findsOneWidget);
    expect(find.text('Apartment · Sale'), findsOneWidget);
    expect(find.text('Petaling Jaya, Selangor'), findsOneWidget);
    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('REN: 12345'), findsOneWidget);
  });

  testWidgets('shows status-change actions when viewer is the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-1'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Fulfilled'), findsOneWidget);
  });

  testWidgets('hides status-change actions when viewer is not the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-2'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Fulfilled'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/requirement/requirement_detail_screen_test.dart
```
Expected: FAIL — `package:renly/features/requirement/requirement_detail_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "requirement_mark_fulfilled": "Mark as Fulfilled",
  "requirement_withdraw": "Withdraw Requirement",
  "requirement_reactivate": "Reactivate Requirement"
```

`app/assets/translations/ms.json` additions:
```json
  "requirement_mark_fulfilled": "Tanda Dipenuhi",
  "requirement_withdraw": "Tarik Balik Keperluan",
  "requirement_reactivate": "Aktifkan Semula Keperluan"
```

Note: the "Location" heading reuses `property_location` (Milestone 3) — identical text, no duplicate key.

- [ ] **Step 4: Implement RequirementDetailScreen**

```dart
// app/lib/features/requirement/requirement_detail_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/signed_photo.dart';
import 'models/requirement.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';

/// Symmetric with PropertyDetailScreen: photo carousel, criteria
/// breakdown, posting negotiator, and owner-only status actions.
class RequirementDetailScreen extends ConsumerStatefulWidget {
  const RequirementDetailScreen({super.key, required this.requirementId});

  final String requirementId;

  @override
  ConsumerState<RequirementDetailScreen> createState() => _RequirementDetailScreenState();
}

class _RequirementDetailScreenState extends ConsumerState<RequirementDetailScreen> {
  /// Takes the requirement (not just the new status) so the two list
  /// providers can be invalidated too -- otherwise a requirement marked
  /// fulfilled here stays on the board and in My Requirements' Open tab
  /// until restart.
  Future<void> _changeStatus(Requirement requirement, String status) async {
    final repository = ref.read(requirementRepositoryProvider);
    try {
      await repository.updateRequirementStatus(requirementId: widget.requirementId, status: status);
      ref.invalidate(requirementDetailProvider(widget.requirementId));
      ref.invalidate(boardRequirementsProvider);
      ref.invalidate(myRequirementsProvider(requirement.negotiatorId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requirementAsync = ref.watch(requirementDetailProvider(widget.requirementId));
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(),
      body: requirementAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (requirement) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == requirement.negotiatorId;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (requirement.photoUrls.isNotEmpty)
                    SizedBox(
                      height: 220,
                      child: PageView(
                        children: [
                          for (final photoPath in requirement.photoUrls)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SignedPhoto(
                                  path: photoPath,
                                  signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    RequirementFormatting.formatBudgetRange(
                      requirement.budgetMin,
                      requirement.budgetMax,
                      requirement.transactionType,
                    ),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${'listing_property_type_${requirement.propertyType}'.tr()} · '
                    '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (requirement.bedrooms != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.bed),
                        const SizedBox(width: 4),
                        Text('${requirement.bedrooms}'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('property_location'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('${requirement.area}, ${requirement.state}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Builder(builder: (context) {
                    final ownerAsync = ref.watch(requirementOwnerProvider(requirement.negotiatorId));
                    return ownerAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (error, stack) => const SizedBox.shrink(),
                      data: (owner) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(owner.fullName, style: Theme.of(context).textTheme.titleMedium),
                          Text('REN: ${owner.renNumber}', style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  if (isOwner) ...[
                    if (requirement.status != 'fulfilled')
                      OutlinedButton(
                        onPressed: () => _changeStatus(requirement, 'fulfilled'),
                        child: Text('requirement_mark_fulfilled'.tr()),
                      ),
                    if (requirement.status != 'withdrawn')
                      OutlinedButton(
                        onPressed: () => _changeStatus(requirement, 'withdrawn'),
                        child: Text('requirement_withdraw'.tr()),
                      ),
                    if (requirement.status != 'open')
                      OutlinedButton(
                        onPressed: () => _changeStatus(requirement, 'open'),
                        child: Text('requirement_reactivate'.tr()),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/requirement/requirement_detail_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/requirement/requirement_detail_screen.dart app/test/features/requirement/requirement_detail_screen_test.dart app/assets/translations/
git commit -m "feat: add RequirementDetailScreen"
```

---

### Task 10: Wire the router and HomePlaceholderScreen navigation

**Files:**
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/lib/features/auth/home_placeholder_screen.dart`
- Test: `app/test/core/router/app_router_test.dart` (add 4 new `test()` cases inside the existing `group`, keep the existing 11 untouched)
- Test: `app/test/features/auth/home_placeholder_screen_test.dart` (full replace — keeps the existing 3 tests, adds 2 more for the new links)

**Interfaces:**
- Consumes: `RequirementBoardScreen`, `MyRequirementsScreen`, `PostRequirementScreen`, `RequirementDetailScreen` (Tasks 6-9).
- Produces: 4 new routes (`/requirement-board`, `/my-requirements`, `/post-requirement`, `/requirement-board/:requirementId`), all requiring a session. `HomePlaceholderScreen` gains two more navigation buttons.

This is the integration task — after this, `flutter test` (full suite) and `flutter analyze` must both be clean.

- [ ] **Step 1: Write the failing computeAuthRedirect tests for the new routes**

Read the existing `app/test/core/router/app_router_test.dart` first (it has 11 tests from Milestones 2-3). Add 4 new tests inside the existing `group('computeAuthRedirect', () { ... })` block, alongside the existing ones:

```dart
    test('unauthenticated user on /requirement-board is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/requirement-board'), '/');
    });

    test('unauthenticated user on /my-requirements is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-requirements'), '/');
    });

    test('unauthenticated user on /post-requirement is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/post-requirement'), '/');
    });

    test('unauthenticated user on /requirement-board/r-1 is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/requirement-board/r-1'), '/');
    });
```

- [ ] **Step 2: Run test to verify it passes immediately**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/router/app_router_test.dart
```
Expected: `00:0X +15: All tests passed!` — these should already pass since the new paths aren't in `_publicRoutes` and `computeAuthRedirect`'s existing logic already redirects anything not in that set. If it unexpectedly fails, `_publicRoutes` has changed since this plan was written; stop and check `app_router.dart` before proceeding, don't guess.

- [ ] **Step 3: Add the 4 routes to app_router.dart**

Read the current `app/lib/core/router/app_router.dart` first. Add these imports alongside the existing screen imports:

```dart
import '../../features/requirement/my_requirements_screen.dart';
import '../../features/requirement/post_requirement_screen.dart';
import '../../features/requirement/requirement_board_screen.dart';
import '../../features/requirement/requirement_detail_screen.dart';
```

Add these 4 routes to the `routes:` list inside `appRouterProvider`, alongside the existing 10:

```dart
      GoRoute(path: '/requirement-board', builder: (context, state) => const RequirementBoardScreen()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const MyRequirementsScreen()),
      GoRoute(path: '/post-requirement', builder: (context, state) => const PostRequirementScreen()),
      GoRoute(
        path: '/requirement-board/:requirementId',
        builder: (context, state) =>
            RequirementDetailScreen(requirementId: state.pathParameters['requirementId']!),
      ),
```

Do not add any of these 4 paths to `_publicRoutes` — they require a session, which is the default.

- [ ] **Step 4: Write the failing HomePlaceholderScreen navigation test**

Read the existing `app/test/features/auth/home_placeholder_screen_test.dart` first (it has 3 tests from Milestone 3). Replace the whole file — keeps the 3 existing tests, adds 2 more for the new links, and adds the new routes to every router in the file so `HomePlaceholderScreen`'s extra buttons have somewhere to navigate to:

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
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('my_requirements_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-requirements-screen'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run test to verify it fails**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: FAIL — `HomePlaceholderScreen` doesn't have the two new links yet, and the new translation keys don't exist yet.

- [ ] **Step 6: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "requirement_board_title_placeholder_link": "Browse Requirements",
  "my_requirements_title_placeholder_link": "My Requirements"
```

`app/assets/translations/ms.json` additions:
```json
  "requirement_board_title_placeholder_link": "Layari Keperluan",
  "my_requirements_title_placeholder_link": "Keperluan Saya"
```

- [ ] **Step 7: Update HomePlaceholderScreen**

Read the current `app/lib/features/auth/home_placeholder_screen.dart` first. Add two more buttons below the existing two:

```dart
// app/lib/features/auth/home_placeholder_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('home_placeholder_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 12),
                Text('home_placeholder_body'.tr(), style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.push('/marketplace'),
                  child: Text('marketplace_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-inventory'),
                  child: Text('inventory_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.push('/requirement-board'),
                  child: Text('requirement_board_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-requirements'),
                  child: Text('my_requirements_title_placeholder_link'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run test to verify it passes**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: `00:0X +5: All tests passed!`

- [ ] **Step 9: Run the full test suite**

```bash
flutter test
```
Expected: every test passes, zero failures.

- [ ] **Step 10: Run static analysis**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 11: Verify translation key parity**

```bash
flutter test test/l10n/translations_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 12: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/core/router/app_router.dart app/lib/features/auth/home_placeholder_screen.dart app/test/core/router/app_router_test.dart app/test/features/auth/home_placeholder_screen_test.dart
git commit -m "feat: wire requirement routes and add navigation from HomePlaceholderScreen"
```

---

## Definition of Done

- `flutter test` (run from `app/`) passes with zero failures across the whole suite.
- `flutter analyze` reports no issues.
- `flutter run` on the user's Android emulator shows: `/home` has four working links (Marketplace, My Inventory, Requirement Board, My Requirements); My Requirements' "Post New Requirement" reaches a working form (property type/transaction type/state/area/budget min/budget max/bedrooms/up-to-3-photos) with inline budget validation; submitting creates a requirement visible in My Requirements' Open tab and on the Requirement Board (from a different account, or the same account); tapping a requirement card reaches Requirement Detail with a photo carousel (if any), the full criteria, the posting negotiator's name + REN, and working Mark Fulfilled / Withdraw actions when viewing as the owner.
- The SQL migration (`0005_requirement.sql`) has been run in the user's Supabase project (Task 1's manual step) — without this, every requirement read/write fails with Postgrest errors even though all code is correct.
- All 10 tasks committed individually.

## Explicitly not in this plan

The Matching Engine (weighted scoring algorithm, spec in the proposal PDF, needs both `listing` and `requirement` populated — this milestone finishes that precondition), the `match`/`cobroke_request`/collaboration flow (`RequirementBoardScreen`'s "contact this negotiator" CTA depends on it), renaming `get_listing_owner_info` to something feature-neutral (cheap follow-up, not blocking), and server-side search — all per the design doc's "Explicitly deferred" section.
