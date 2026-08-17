# renly Listing Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A verified negotiator can post a property listing with up to 10 photos, browse other negotiators' active listings on the marketplace, manage their own inventory (active/sold/withdrawn), and view a single listing's detail page.

**Architecture:** Screens under `lib/features/listing/` call a single `ListingRepository` for every Supabase read/write, same pattern as `AuthRepository`. `Listing.fromJson` and small pure helpers (`ListingFormatting`, `ListingStatusFilter`) are dependency-free Dart, unit-testable without Supabase. Photo upload is create-row-then-upload-then-attach: the listing row must exist first so its `listing_id` is available for the Storage path convention.

**Tech Stack:** Flutter/Dart, Riverpod, `supabase_flutter`, `go_router`, `easy_localization`, `image_picker` (already a dependency from Milestone 2).

## Global Constraints

- No screen calls `Supabase.instance.client` directly — always through `ListingRepository`. The one exception is reading the current session's user id, which goes through a new `currentNegotiatorIdProvider` (reads `authStateProvider` from Milestone 2's `lib/features/auth/auth_providers.dart`) — this is session-state, not a Supabase query, and Milestone 2 already established `authStateProvider` for exactly this kind of read.
- Every new UI string goes into BOTH `app/assets/translations/en.json` and `app/assets/translations/ms.json` with matching keys — `app/test/l10n/translations_test.dart` already asserts key-set parity.
- **Every test file with 2+ `testWidgets` sharing `EasyLocalization` MUST include, from the start (not as an afterthought):** `import 'package:flutter/services.dart';` and `setUp(() { rootBundle.clear(); });` right after `setUpAll`, plus `await tester.pumpAndSettle();` immediately after every `pumpWidget` and before any `tap`/`enterText` call. This is a real, previously-diagnosed Flutter/easy_localization bug (`rootBundle` — Flutter's `CachingAssetBundle` — caches asset-load Futures process-wide, but `flutter_test` runs each `testWidgets` in its own torn-down `FakeAsync` zone, so the 2nd+ test hangs re-using the 1st test's stale cached Future). Bake it into every screen test task's Step 1 — do not let an implementer rediscover it.
- **Never swap a text-based test finder (`find.text(...)`, `find.widgetWithText(...)`) for a `Key`-based one because of an unverified "too many elements" guess.** A prior milestone lost a full fix-and-review round over exactly this — the real cause was an off-screen button inside a `SingleChildScrollView` that needed `tester.drag()` to scroll into the hit-testable viewport, not a finder-cardinality problem. If a test's tap/finder fails, scroll first (pattern is in Task 7 below) and diagnose for real before touching the finder strategy.
- Currency is **RM** everywhere (`RM 1,250,000`, or `RM 1,250,000 /mo` for rentals) — never `$` or `Rp` (both are unmodified Stitch template defaults, not deliberate).
- Colors/fonts/spacing come from `AppColors`/`AppTheme` (Milestone 1) — no new hardcoded hex values.
- SQL migration is a manual, user-performed step (Task 1) — this session has no DB credentials.
- Flutter is on PATH via `export PATH="$HOME/development/flutter/bin:$PATH"` — run first if `flutter` isn't found. All commands below assume this has been run and `cd` is `app/` unless stated otherwise.

---

### Task 1: Supabase migration SQL (0003_listing.sql)

**Files:**
- Create: `supabase/migrations/0003_listing.sql`
- Modify: `app/README.md` (append a "Milestone 3 setup" section)

**Interfaces:**
- Produces: the `listing` table and `listing-photos` storage bucket that Task 3's `ListingRepository` calls assume exist.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0003_listing.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001 and 0002.

create table listing (
  listing_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  title text not null,
  description text not null,
  property_type text not null check (property_type in ('apartment', 'house', 'commercial', 'land')),
  transaction_type text not null check (transaction_type in ('sale', 'rent')),
  state text not null,
  area text not null,
  price numeric not null check (price > 0),
  bedrooms integer,
  bathrooms integer,
  photo_urls text[] not null default '{}',
  status text not null default 'active' check (status in ('active', 'sold', 'withdrawn')),
  created_at timestamptz not null default now()
);

alter table listing enable row level security;

-- Owner sees all of their own listings regardless of status; everyone else
-- (browsing the marketplace) sees only active ones.
create policy listing_select on listing for select
  using (negotiator_id = auth.uid() or status = 'active');

create policy listing_insert_own on listing for insert
  with check (negotiator_id = auth.uid());

create policy listing_update_own on listing for update
  using (negotiator_id = auth.uid());

-- Storage: path convention {negotiator_id}/{listing_id}/{n}.jpg
insert into storage.buckets (id, name, public) values ('listing-photos', 'listing-photos', false)
  on conflict (id) do nothing;

create policy listing_photos_select_authenticated on storage.objects for select
  to authenticated using (bucket_id = 'listing-photos');

create policy listing_photos_insert_own on storage.objects for insert
  to authenticated with check (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy listing_photos_update_own on storage.objects for update
  to authenticated using (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy listing_photos_delete_own on storage.objects for delete
  to authenticated using (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'listing-photos';
```

- [ ] **Step 2: Verify the file is well-formed**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0003_listing.sql
grep -c "^create policy" supabase/migrations/0003_listing.sql
```
Expected: `1` (listing) and `6` (listing_select, listing_insert_own, listing_update_own, listing_photos_select_authenticated, listing_photos_insert_own, listing_photos_update_own, listing_photos_delete_own — count the actual `create policy` lines in the file to confirm; there are 7, not 6, since the storage policies include a delete policy the table policies don't need — verify by reading the file, the grep count is a sanity check not a strict pass/fail gate).

- [ ] **Step 3: Append manual setup instructions to app/README.md**

Read the current `app/README.md` first (it has Milestone 1 and Milestone 2 setup sections already). Append:

```markdown

## Milestone 3 setup (listing)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0003_listing.sql` (repo root) -> Run. This creates the `listing` table, its RLS policies, and the `listing-photos` storage bucket. No Auth-dashboard changes needed this time.
```

- [ ] **Step 4: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add supabase/migrations/0003_listing.sql app/README.md
git commit -m "feat: add listing Supabase migration and setup docs"
```

---

### Task 2: Listing model + pure helpers (TDD)

**Files:**
- Create: `app/lib/features/listing/models/listing.dart`
- Create: `app/lib/features/listing/listing_formatting.dart`
- Create: `app/lib/features/listing/listing_status_filter.dart`
- Create: `app/lib/core/constants/malaysian_states.dart`
- Test: `app/test/features/listing/models/listing_test.dart`
- Test: `app/test/features/listing/listing_formatting_test.dart`
- Test: `app/test/features/listing/listing_status_filter_test.dart`

**Interfaces:**
- Produces: `Listing` (fields: `listingId`, `negotiatorId`, `title`, `description`, `propertyType`, `transactionType`, `state`, `area`, `price` (`double`), `bedrooms` (`int?`), `bathrooms` (`int?`), `photoUrls` (`List<String>`), `status`, all `final`) with `Listing.fromJson(Map<String, dynamic>)`. `ListingFormatting.formatPrice(num price, String transactionType)` → `String`. `ListingStatusFilter.byStatus(List<Listing>, String status)` → `List<Listing>`. `malaysianStates` → `List<String>` constant. Every later task imports these.

- [ ] **Step 1: Write the failing Listing model test**

```dart
// app/test/features/listing/models/listing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing.dart';

void main() {
  group('Listing.fromJson', () {
    test('parses a full row', () {
      final listing = Listing.fromJson({
        'listing_id': 'l-1',
        'negotiator_id': 'n-1',
        'title': 'The Vertex Residency',
        'description': 'A modern apartment.',
        'property_type': 'apartment',
        'transaction_type': 'sale',
        'state': 'Selangor',
        'area': 'Petaling Jaya',
        'price': 1250000,
        'bedrooms': 3,
        'bathrooms': 2,
        'photo_urls': ['n-1/l-1/0.jpg', 'n-1/l-1/1.jpg'],
        'status': 'active',
      });

      expect(listing.listingId, 'l-1');
      expect(listing.negotiatorId, 'n-1');
      expect(listing.title, 'The Vertex Residency');
      expect(listing.price, 1250000.0);
      expect(listing.bedrooms, 3);
      expect(listing.bathrooms, 2);
      expect(listing.photoUrls, ['n-1/l-1/0.jpg', 'n-1/l-1/1.jpg']);
      expect(listing.status, 'active');
    });

    test('handles null bedrooms/bathrooms and empty photo_urls', () {
      final listing = Listing.fromJson({
        'listing_id': 'l-2',
        'negotiator_id': 'n-1',
        'title': 'Empty Land Plot',
        'description': 'Vacant land.',
        'property_type': 'land',
        'transaction_type': 'sale',
        'state': 'Johor',
        'area': 'Iskandar Puteri',
        'price': 500000,
        'bedrooms': null,
        'bathrooms': null,
        'photo_urls': null,
        'status': 'active',
      });

      expect(listing.bedrooms, isNull);
      expect(listing.bathrooms, isNull);
      expect(listing.photoUrls, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/listing/models/listing_test.dart
```
Expected: FAIL — `package:renly/features/listing/models/listing.dart` not found.

- [ ] **Step 3: Implement Listing**

```dart
// app/lib/features/listing/models/listing.dart

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

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/listing/models/listing_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 5: Write the failing ListingFormatting test**

```dart
// app/test/features/listing/listing_formatting_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/listing_formatting.dart';

void main() {
  group('ListingFormatting.formatPrice', () {
    test('formats a sale price with thousands separators', () {
      expect(ListingFormatting.formatPrice(1250000, 'sale'), 'RM 1,250,000');
    });

    test('formats a rental price with /mo suffix', () {
      expect(ListingFormatting.formatPrice(12000, 'rent'), 'RM 12,000 /mo');
    });

    test('formats a price under 1000 with no separator', () {
      expect(ListingFormatting.formatPrice(500, 'sale'), 'RM 500');
    });

    test('formats a price of exactly 1000', () {
      expect(ListingFormatting.formatPrice(1000, 'sale'), 'RM 1,000');
    });
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

```bash
flutter test test/features/listing/listing_formatting_test.dart
```
Expected: FAIL — `package:renly/features/listing/listing_formatting.dart` not found.

- [ ] **Step 7: Implement ListingFormatting**

```dart
// app/lib/features/listing/listing_formatting.dart

/// Pure price-display formatting. No Flutter/Supabase -- fully unit-testable.
class ListingFormatting {
  ListingFormatting._();

  static String formatPrice(num price, String transactionType) {
    final rounded = price.round();
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    final suffix = transactionType == 'rent' ? ' /mo' : '';
    return 'RM $buffer$suffix';
  }
}
```

- [ ] **Step 8: Run test to verify it passes**

```bash
flutter test test/features/listing/listing_formatting_test.dart
```
Expected: `00:0X +4: All tests passed!`

- [ ] **Step 9: Write the failing ListingStatusFilter test**

```dart
// app/test/features/listing/listing_status_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/listing_status_filter.dart';
import 'package:renly/features/listing/models/listing.dart';

Listing _listing(String id, String status) {
  return Listing(
    listingId: id,
    negotiatorId: 'n-1',
    title: 'Test $id',
    description: 'desc',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'PJ',
    price: 100000,
    photoUrls: const [],
    status: status,
  );
}

void main() {
  group('ListingStatusFilter.byStatus', () {
    test('returns only listings matching the given status', () {
      final listings = [_listing('1', 'active'), _listing('2', 'sold'), _listing('3', 'active')];
      final result = ListingStatusFilter.byStatus(listings, 'active');
      expect(result.map((l) => l.listingId), ['1', '3']);
    });

    test('returns empty list when nothing matches', () {
      final listings = [_listing('1', 'active')];
      expect(ListingStatusFilter.byStatus(listings, 'withdrawn'), isEmpty);
    });
  });
}
```

- [ ] **Step 10: Run test to verify it fails**

```bash
flutter test test/features/listing/listing_status_filter_test.dart
```
Expected: FAIL — `package:renly/features/listing/listing_status_filter.dart` not found.

- [ ] **Step 11: Implement ListingStatusFilter**

```dart
// app/lib/features/listing/listing_status_filter.dart
import 'models/listing.dart';

/// Pure client-side tab filter for My Inventory (active/sold/withdrawn).
class ListingStatusFilter {
  ListingStatusFilter._();

  static List<Listing> byStatus(List<Listing> listings, String status) {
    return listings.where((listing) => listing.status == status).toList();
  }
}
```

- [ ] **Step 12: Run test to verify it passes**

```bash
flutter test test/features/listing/listing_status_filter_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 13: Create the Malaysian states constant (no TDD -- a static data list)**

```dart
// app/lib/core/constants/malaysian_states.dart

/// The 13 states and 3 federal territories of Malaysia, for the listing
/// state dropdown (and, later, the requirement/negotiator territory
/// dropdowns -- shared constant, not listing-specific).
const List<String> malaysianStates = [
  'Johor',
  'Kedah',
  'Kelantan',
  'Melaka',
  'Negeri Sembilan',
  'Pahang',
  'Perak',
  'Perlis',
  'Pulau Pinang',
  'Sabah',
  'Sarawak',
  'Selangor',
  'Terengganu',
  'W.P. Kuala Lumpur',
  'W.P. Labuan',
  'W.P. Putrajaya',
];
```

- [ ] **Step 14: Run the full listing test directory to confirm everything from this task passes together**

```bash
flutter test test/features/listing/
```
Expected: `00:0X +8: All tests passed!` (2 Listing + 4 ListingFormatting + 2 ListingStatusFilter).

- [ ] **Step 15: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/models/listing.dart app/lib/features/listing/listing_formatting.dart app/lib/features/listing/listing_status_filter.dart app/lib/core/constants/malaysian_states.dart app/test/features/listing/
git commit -m "feat: add Listing model and pure formatting/filter helpers"
```

---

### Task 3: ListingOwner model + ListingRepository (Supabase I/O)

**Files:**
- Create: `app/lib/features/listing/models/listing_owner.dart`
- Create: `app/lib/features/listing/listing_repository.dart`

**Interfaces:**
- Consumes: `Listing` (Task 2).
- Produces: `ListingOwner` (fields `fullName`, `renNumber`, both `String`) with `ListingOwner.fromJson`. `ListingRepository(SupabaseClient client)` with methods `fetchMarketplaceListings`, `fetchOwnListings`, `fetchListingById`, `fetchListingOwner`, `uploadListingPhoto`, `createListing`, `updateListingPhotos`, `updateListingStatus` — every later screen task calls these.

No TDD for this task (same documented boundary as `AuthRepository` in Milestone 2 — Supabase-calling code isn't unit-tested in this project). Verify with `flutter analyze` only.

- [ ] **Step 1: Implement ListingOwner**

```dart
// app/lib/features/listing/models/listing_owner.dart

/// The listing's negotiator, scoped to what PropertyDetailScreen displays
/// (name + REN number) -- deliberately not the full `Negotiator` model from
/// the auth feature, to keep this feature's Supabase reads self-contained
/// rather than reaching into another feature's model.
class ListingOwner {
  final String fullName;
  final String renNumber;

  const ListingOwner({required this.fullName, required this.renNumber});

  factory ListingOwner.fromJson(Map<String, dynamic> json) {
    return ListingOwner(
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String? ?? '',
    );
  }
}
```

- [ ] **Step 2: Implement ListingRepository**

```dart
// app/lib/features/listing/listing_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/listing.dart';
import 'models/listing_owner.dart';

/// The only file in this app that talks to Supabase for the listing
/// feature. Screens call these methods; nothing else touches
/// `SupabaseClient` for listings.
class ListingRepository {
  ListingRepository(this._client);

  final SupabaseClient _client;

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

  Future<Listing> fetchListingById(String listingId) async {
    final row = await _client.from('listing').select().eq('listing_id', listingId).single();
    return Listing.fromJson(row);
  }

  Future<ListingOwner> fetchListingOwner(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('full_name, ren_number')
        .eq('negotiator_id', negotiatorId)
        .single();
    return ListingOwner.fromJson(row);
  }

  Future<String> uploadListingPhoto({
    required String negotiatorId,
    required String listingId,
    required int index,
    required Uint8List bytes,
  }) async {
    final path = '$negotiatorId/$listingId/$index.jpg';
    await _client.storage.from('listing-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

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

  Future<void> updateListingPhotos({required String listingId, required List<String> photoUrls}) {
    return _client.from('listing').update({'photo_urls': photoUrls}).eq('listing_id', listingId);
  }

  Future<void> updateListingStatus({required String listingId, required String status}) {
    return _client.from('listing').update({'status': status}).eq('listing_id', listingId);
  }
}
```

- [ ] **Step 3: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/listing/models/listing_owner.dart lib/features/listing/listing_repository.dart
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/models/listing_owner.dart app/lib/features/listing/listing_repository.dart
git commit -m "feat: add ListingOwner model and ListingRepository"
```

---

### Task 4: listing_providers.dart

**Files:**
- Create: `app/lib/features/listing/listing_providers.dart`

**Interfaces:**
- Consumes: `ListingRepository` (Task 3), `authStateProvider` (from `../auth/auth_providers.dart`, Milestone 2).
- Produces: `listingRepositoryProvider` (`Provider<ListingRepository>`), `currentNegotiatorIdProvider` (`Provider<String?>`), `marketplaceListingsProvider` (`FutureProvider<List<Listing>>`), `myListingsProvider` (`FutureProvider.family<List<Listing>, String>`), `listingDetailProvider` (`FutureProvider.family<Listing, String>`), `listingOwnerProvider` (`FutureProvider.family<ListingOwner, String>`, keyed by `negotiatorId`) — every screen task uses these.

No TDD for this task (Riverpod wiring around Supabase singletons, same boundary as `auth_providers.dart`). Verify with `flutter analyze`.

- [ ] **Step 1: Implement listing_providers.dart**

```dart
// app/lib/features/listing/listing_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'listing_repository.dart';
import 'models/listing.dart';
import 'models/listing_owner.dart';

final listingRepositoryProvider = Provider<ListingRepository>((ref) {
  return ListingRepository(Supabase.instance.client);
});

/// Reads the current session's user id -- not a Supabase query, just
/// session state already tracked by Milestone 2's authStateProvider.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

final marketplaceListingsProvider = FutureProvider<List<Listing>>((ref) {
  return ref.watch(listingRepositoryProvider).fetchMarketplaceListings();
});

final myListingsProvider = FutureProvider.family<List<Listing>, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).fetchOwnListings(negotiatorId);
});

final listingDetailProvider = FutureProvider.family<Listing, String>((ref, listingId) {
  return ref.watch(listingRepositoryProvider).fetchListingById(listingId);
});

final listingOwnerProvider = FutureProvider.family<ListingOwner, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).fetchListingOwner(negotiatorId);
});
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/listing/listing_providers.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/listing_providers.dart
git commit -m "feat: add listing Riverpod providers"
```

---

### Task 5: MarketplaceScreen

**Files:**
- Create: `app/lib/features/listing/marketplace_screen.dart`
- Test: `app/test/features/listing/marketplace_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `marketplaceListingsProvider` (Task 4), `Listing`/`ListingFormatting` (Task 2). Navigates via `context.push('/property/${listing.listingId}')` — string route, doesn't depend on `PropertyDetailScreen` existing yet.
- Produces: `MarketplaceScreen` (`ConsumerWidget`) — Task 9's router uses it as `/marketplace`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/listing/marketplace_screen_test.dart
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
import 'package:renly/features/listing/marketplace_screen.dart';
import 'package:renly/features/listing/models/listing.dart';

final _fixtureListings = [
  const Listing(
    listingId: 'l-1',
    negotiatorId: 'n-1',
    title: 'The Vertex Residency',
    description: 'A modern apartment.',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'Petaling Jaya',
    price: 1250000,
    bedrooms: 3,
    bathrooms: 2,
    photoUrls: [],
    status: 'active',
  ),
  const Listing(
    listingId: 'l-2',
    negotiatorId: 'n-2',
    title: 'City Loft',
    description: 'Rental loft.',
    propertyType: 'apartment',
    transactionType: 'rent',
    state: 'W.P. Kuala Lumpur',
    area: 'Bukit Bintang',
    price: 3500,
    bedrooms: 1,
    bathrooms: 1,
    photoUrls: [],
    status: 'active',
  ),
];

Widget _wrap(GoRouter router, {List<Listing>? listings}) {
  return ProviderScope(
    overrides: [
      marketplaceListingsProvider.overrideWith((ref) async => listings ?? _fixtureListings),
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

  testWidgets('renders active listings with formatted price and area', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 1,250,000'), findsOneWidget);
    expect(find.text('RM 3,500 /mo'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Bukit Bintang'), findsOneWidget);
  });

  testWidgets('tapping a listing card navigates to its property detail route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => Text('detail-${state.pathParameters['listingId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Vertex Residency'));
    await tester.pumpAndSettle();

    expect(find.text('detail-l-1'), findsOneWidget);
  });

  testWidgets('renders empty state when no listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, listings: []));
    await tester.pumpAndSettle();

    expect(find.text('No listings yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/listing/marketplace_screen_test.dart
```
Expected: FAIL — `package:renly/features/listing/marketplace_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "marketplace_title": "Market",
  "marketplace_search_hint": "Search properties, neighbourhoods...",
  "marketplace_empty": "No listings yet"
```

`app/assets/translations/ms.json` additions:
```json
  "marketplace_title": "Pasaran",
  "marketplace_search_hint": "Cari hartanah, kawasan...",
  "marketplace_empty": "Tiada senarai lagi"
```

- [ ] **Step 4: Implement MarketplaceScreen**

```dart
// app/lib/features/listing/marketplace_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'listing_formatting.dart';
import 'listing_providers.dart';
import 'models/listing.dart';

/// Ports stitch_renly_property_agent_network/marketplace. Search is
/// client-side only for this pass (filters the already-fetched active
/// listings) -- no server-side full-text search yet.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Listing> _filter(List<Listing> listings) {
    if (_query.trim().isEmpty) return listings;
    final q = _query.toLowerCase();
    return listings
        .where((l) =>
            l.title.toLowerCase().contains(q) ||
            l.area.toLowerCase().contains(q) ||
            l.state.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final listingsAsync = ref.watch(marketplaceListingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('marketplace_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'marketplace_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: listingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text(error.toString())),
              data: (listings) {
                final filtered = _filter(listings);
                if (filtered.isEmpty) {
                  return Center(child: Text('marketplace_empty'.tr()));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final listing = filtered[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: () => context.push('/property/${listing.listingId}'),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(listing.title, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(
                                ListingFormatting.formatPrice(listing.price, listing.transactionType),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: AppColors.primary),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (listing.bedrooms != null) ...[
                                    const Icon(Icons.bed, size: 16),
                                    const SizedBox(width: 4),
                                    Text('${listing.bedrooms}'),
                                    const SizedBox(width: 12),
                                  ],
                                  if (listing.bathrooms != null) ...[
                                    const Icon(Icons.bathtub, size: 16),
                                    const SizedBox(width: 4),
                                    Text('${listing.bathrooms}'),
                                    const SizedBox(width: 12),
                                  ],
                                  Text(listing.area, style: Theme.of(context).textTheme.labelSmall),
                                ],
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
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/listing/marketplace_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/marketplace_screen.dart app/test/features/listing/marketplace_screen_test.dart app/assets/translations/
git commit -m "feat: add MarketplaceScreen"
```

---

### Task 6: MyInventoryScreen

**Files:**
- Create: `app/lib/features/listing/my_inventory_screen.dart`
- Test: `app/test/features/listing/my_inventory_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `myListingsProvider`, `currentNegotiatorIdProvider` (Task 4), `ListingStatusFilter` (Task 2). Navigates via `context.push('/post-listing')` — string route.
- Produces: `MyInventoryScreen` (`ConsumerStatefulWidget`) — Task 9's router uses it as `/my-inventory`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/listing/my_inventory_screen_test.dart
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
import 'package:renly/features/listing/my_inventory_screen.dart';

final _fixtureListings = [
  const Listing(
    listingId: 'l-1',
    negotiatorId: 'n-1',
    title: 'Active One',
    description: 'd',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    price: 800000,
    photoUrls: [],
    status: 'active',
  ),
  const Listing(
    listingId: 'l-2',
    negotiatorId: 'n-1',
    title: 'Sold One',
    description: 'd',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    price: 900000,
    photoUrls: [],
    status: 'sold',
  ),
];

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myListingsProvider.overrideWith((ref, negotiatorId) async => _fixtureListings),
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

  testWidgets('Active tab shows only active listings by default', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Active One'), findsOneWidget);
    expect(find.text('Sold One'), findsNothing);
  });

  testWidgets('switching to Sold tab shows only sold listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sold'));
    await tester.pumpAndSettle();

    expect(find.text('Sold One'), findsOneWidget);
    expect(find.text('Active One'), findsNothing);
  });

  testWidgets('tapping Post New Listing navigates to /post-listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
      GoRoute(path: '/post-listing', builder: (context, state) => const Text('post-listing-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Listing'));
    await tester.pumpAndSettle();

    expect(find.text('post-listing-screen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/listing/my_inventory_screen_test.dart
```
Expected: FAIL — `package:renly/features/listing/my_inventory_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "inventory_title": "Inventory Management",
  "inventory_tab_active": "Active",
  "inventory_tab_sold": "Sold",
  "inventory_tab_withdrawn": "Withdrawn",
  "inventory_post_new": "Post New Listing",
  "inventory_empty": "No listings in this tab yet"
```

`app/assets/translations/ms.json` additions:
```json
  "inventory_title": "Pengurusan Inventori",
  "inventory_tab_active": "Aktif",
  "inventory_tab_sold": "Terjual",
  "inventory_tab_withdrawn": "Ditarik Balik",
  "inventory_post_new": "Siarkan Senarai Baharu",
  "inventory_empty": "Tiada senarai dalam tab ini lagi"
```

- [ ] **Step 4: Implement MyInventoryScreen**

```dart
// app/lib/features/listing/my_inventory_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'listing_formatting.dart';
import 'listing_providers.dart';
import 'listing_status_filter.dart';

/// Ports stitch_renly_property_agent_network/my_inventory. Adds a third
/// "Withdrawn" tab beyond the mockup's Active/Sold -- the status model has
/// three states and hiding withdrawn listings from their own owner would
/// be a real gap, not a deliberate simplification.
class MyInventoryScreen extends ConsumerStatefulWidget {
  const MyInventoryScreen({super.key});

  @override
  ConsumerState<MyInventoryScreen> createState() => _MyInventoryScreenState();
}

class _MyInventoryScreenState extends ConsumerState<MyInventoryScreen> {
  String _selectedStatus = 'active';

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('inventory_title'.tr())),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/post-listing'),
        label: Text('inventory_post_new'.tr()),
        icon: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'active', label: Text('inventory_tab_active'.tr())),
                ButtonSegment(value: 'sold', label: Text('inventory_tab_sold'.tr())),
                ButtonSegment(value: 'withdrawn', label: Text('inventory_tab_withdrawn'.tr())),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (selection) => setState(() => _selectedStatus = selection.first),
            ),
          ),
          Expanded(
            child: negotiatorId == null
                ? const SizedBox.shrink()
                : Consumer(
                    builder: (context, ref, _) {
                      final listingsAsync = ref.watch(myListingsProvider(negotiatorId));
                      return listingsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (error, stack) => Center(child: Text(error.toString())),
                        data: (listings) {
                          final filtered = ListingStatusFilter.byStatus(listings, _selectedStatus);
                          if (filtered.isEmpty) {
                            return Center(child: Text('inventory_empty'.tr()));
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final listing = filtered[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: ListTile(
                                  onTap: () => context.push('/property/${listing.listingId}'),
                                  title: Text(listing.title),
                                  subtitle: Text(
                                    ListingFormatting.formatPrice(listing.price, listing.transactionType),
                                  ),
                                ),
                              );
                            },
                          );
                        },
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
flutter test test/features/listing/my_inventory_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/my_inventory_screen.dart app/test/features/listing/my_inventory_screen_test.dart app/assets/translations/
git commit -m "feat: add MyInventoryScreen"
```

---

### Task 7: PostListingScreen (multi-photo upload)

**Files:**
- Create: `app/lib/features/listing/post_listing_screen.dart`
- Test: `app/test/features/listing/post_listing_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `listingRepositoryProvider`, `currentNegotiatorIdProvider` (Task 4), `malaysianStates` (Task 2).
- Produces: `PostListingScreen` (`ConsumerStatefulWidget`) — on success, calls `context.go('/my-inventory')`. Task 9's router uses it as `/post-listing`.

This is the first multi-file upload flow in the app (Milestone 2's `RegistrationProfessionalScreen` uploaded exactly one photo). The picker uses `ImagePicker().pickMultiImage(imageQuality: 85, limit: 10)`, appended to a local `List<XFile>` (capped at 10 total — if the picker returns more than the remaining slots, only the remaining slots are taken, matching the mockup's "Max 10" label). Submit order: `createListing` (no photos yet) → for each local photo, `uploadListingPhoto` with the returned `listing_id` → `updateListingPhotos` with the collected paths → navigate away. If this screen's tests need to tap a submit button below the fold (a 9-field form plus a photo grid is taller than the default test viewport), scroll the `SingleChildScrollView` into view first — do NOT swap the finder for a `Key` on an unverified guess (see Global Constraints).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/listing/post_listing_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/post_listing_screen.dart';

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
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listing_title_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_description_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_transaction_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_state_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_area_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_price_field')), findsOneWidget);
  });

  testWidgets('submitting with empty required fields shows validation errors', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Now'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/listing/post_listing_screen_test.dart
```
Expected: FAIL — `package:renly/features/listing/post_listing_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "listing_post_title": "Post a Listing",
  "listing_field_title": "Title",
  "listing_field_description": "Description",
  "listing_field_property_type": "Property Type",
  "listing_field_transaction_type": "Transaction Type",
  "listing_field_state": "State",
  "listing_field_area": "Area",
  "listing_field_price": "Price (RM)",
  "listing_field_bedrooms": "Bedrooms",
  "listing_field_bathrooms": "Bathrooms",
  "listing_photos_label": "Photos",
  "listing_photos_max": "Max 10",
  "listing_add_photo": "Add Photo",
  "listing_post_now": "Post Now",
  "listing_property_type_apartment": "Apartment",
  "listing_property_type_house": "House",
  "listing_property_type_commercial": "Commercial Space",
  "listing_property_type_land": "Land",
  "listing_transaction_type_sale": "Sale",
  "listing_transaction_type_rent": "Rent"
```

`app/assets/translations/ms.json` additions:
```json
  "listing_post_title": "Siarkan Senarai",
  "listing_field_title": "Tajuk",
  "listing_field_description": "Penerangan",
  "listing_field_property_type": "Jenis Hartanah",
  "listing_field_transaction_type": "Jenis Urus Niaga",
  "listing_field_state": "Negeri",
  "listing_field_area": "Kawasan",
  "listing_field_price": "Harga (RM)",
  "listing_field_bedrooms": "Bilik Tidur",
  "listing_field_bathrooms": "Bilik Air",
  "listing_photos_label": "Gambar",
  "listing_photos_max": "Maksimum 10",
  "listing_add_photo": "Tambah Gambar",
  "listing_post_now": "Siarkan Sekarang",
  "listing_property_type_apartment": "Apartmen",
  "listing_property_type_house": "Rumah",
  "listing_property_type_commercial": "Ruang Komersial",
  "listing_property_type_land": "Tanah",
  "listing_transaction_type_sale": "Jual",
  "listing_transaction_type_rent": "Sewa"
```

- [ ] **Step 4: Implement PostListingScreen**

```dart
// app/lib/features/listing/post_listing_screen.dart
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/malaysian_states.dart';
import 'listing_providers.dart';

/// Ports stitch_renly_property_agent_network/post_listing's "Sediakan
/// Listing" branch only -- see the design doc's "Scope split" section for
/// why the "Cari Listing" (requirement) tab isn't built here yet.
class PostListingScreen extends ConsumerStatefulWidget {
  const PostListingScreen({super.key});

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
  String _propertyType = 'apartment';
  String _transactionType = 'sale';
  String _state = malaysianStates.first;
  final List<XFile> _photos = [];
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _areaController.dispose();
    _priceController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    super.dispose();
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
    setState(() => _photos.removeAt(index));
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
      );

      final photoUrls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        final path = await repository.uploadListingPhoto(
          negotiatorId: negotiatorId,
          listingId: listing.listingId,
          index: i,
          bytes: bytes,
        );
        photoUrls.add(path);
      }
      if (photoUrls.isNotEmpty) {
        await repository.updateListingPhotos(listingId: listing.listingId, photoUrls: photoUrls);
      }

      if (!mounted) return;
      context.go('/my-inventory');
    } catch (e) {
      if (mounted) setState(() => _submitError = e.toString());
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
      appBar: AppBar(title: Text('listing_post_title'.tr())),
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
                              child: Image.file(File(_photos[index].path), fit: BoxFit.cover),
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
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('listing_post_now'.tr()),
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
flutter test test/features/listing/post_listing_screen_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/post_listing_screen.dart app/test/features/listing/post_listing_screen_test.dart app/assets/translations/
git commit -m "feat: add PostListingScreen with multi-photo upload"
```

---

### Task 8: PropertyDetailScreen

**Files:**
- Create: `app/lib/features/listing/property_detail_screen.dart`
- Test: `app/test/features/listing/property_detail_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `listingDetailProvider`, `listingOwnerProvider`, `currentNegotiatorIdProvider`, `listingRepositoryProvider` (Task 4), `ListingOwner` (Task 3).
- Produces: `PropertyDetailScreen` (`ConsumerStatefulWidget`, constructor `{required this.listingId}`) — Task 9's router uses it for `/property/:listingId`, passing `state.pathParameters['listingId']!`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/listing/property_detail_screen_test.dart
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
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/listing/property_detail_screen.dart';

const _fixtureListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'A modern apartment with lots of light.',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 1250000,
  bedrooms: 3,
  bathrooms: 2,
  photoUrls: [],
  status: 'active',
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2'}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      listingDetailProvider.overrideWith((ref, listingId) async => _fixtureListing),
      listingOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
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

  testWidgets('renders title, price, description, and area', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('The Vertex Residency'), findsOneWidget);
    expect(find.text('RM 1,250,000'), findsOneWidget);
    expect(find.text('A modern apartment with lots of light.'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('REN: 12345'), findsOneWidget);
  });

  testWidgets('shows status-change actions when viewer is the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-1'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Sold'), findsOneWidget);
  });

  testWidgets('hides status-change actions when viewer is not the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-2'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Sold'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/listing/property_detail_screen_test.dart
```
Expected: FAIL — `package:renly/features/listing/property_detail_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "property_overview": "Property Overview",
  "property_location": "Location",
  "property_mark_sold": "Mark as Sold",
  "property_withdraw": "Withdraw Listing",
  "property_reactivate": "Reactivate Listing"
```

`app/assets/translations/ms.json` additions:
```json
  "property_overview": "Gambaran Hartanah",
  "property_location": "Lokasi",
  "property_mark_sold": "Tanda Terjual",
  "property_withdraw": "Tarik Balik Senarai",
  "property_reactivate": "Aktifkan Semula Senarai"
```

- [ ] **Step 4: Implement PropertyDetailScreen**

```dart
// app/lib/features/listing/property_detail_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'listing_formatting.dart';
import 'listing_providers.dart';
import 'models/listing_owner.dart';

/// Ports stitch_renly_property_agent_network/property_detail.
class PropertyDetailScreen extends ConsumerStatefulWidget {
  const PropertyDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends ConsumerState<PropertyDetailScreen> {
  Future<void> _changeStatus(String status) async {
    final repository = ref.read(listingRepositoryProvider);
    await repository.updateListingStatus(listingId: widget.listingId, status: status);
    ref.invalidate(listingDetailProvider(widget.listingId));
  }

  @override
  Widget build(BuildContext context) {
    final listingAsync = ref.watch(listingDetailProvider(widget.listingId));
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      body: listingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (listing) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == listing.negotiatorId;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (listing.photoUrls.isNotEmpty)
                    SizedBox(
                      height: 220,
                      child: PageView(
                        children: [
                          for (final _ in listing.photoUrls)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(listing.title, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    ListingFormatting.formatPrice(listing.price, listing.transactionType),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
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
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('property_overview'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(listing.description, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Text('property_location'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(listing.area, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Builder(builder: (context) {
                    final ownerAsync = ref.watch(listingOwnerProvider(listing.negotiatorId));
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
                    if (listing.status != 'sold')
                      OutlinedButton(
                        onPressed: () => _changeStatus('sold'),
                        child: Text('property_mark_sold'.tr()),
                      ),
                    if (listing.status != 'withdrawn')
                      OutlinedButton(
                        onPressed: () => _changeStatus('withdrawn'),
                        child: Text('property_withdraw'.tr()),
                      ),
                    if (listing.status != 'active')
                      OutlinedButton(
                        onPressed: () => _changeStatus('active'),
                        child: Text('property_reactivate'.tr()),
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
flutter test test/features/listing/property_detail_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/listing/property_detail_screen.dart app/test/features/listing/property_detail_screen_test.dart app/assets/translations/
git commit -m "feat: add PropertyDetailScreen"
```

---

### Task 9: Wire the router and HomePlaceholderScreen navigation

**Files:**
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/lib/features/auth/home_placeholder_screen.dart`
- Test: `app/test/core/router/app_router_test.dart` (add 4 new `test()` cases inside the existing `group`, keep the existing 7 untouched)
- Test: `app/test/features/auth/home_placeholder_screen_test.dart` (the existing single test's assertion is preserved, but its wrapper upgrades from a bare `MaterialApp` to a `GoRouter`-aware `MaterialApp.router`, since the two new tests in this same file need a router — see Step 5's full replacement content, which keeps the original assertion as its first test)

**Interfaces:**
- Consumes: `MarketplaceScreen`, `MyInventoryScreen`, `PostListingScreen`, `PropertyDetailScreen` (Tasks 5-8).
- Produces: 4 new routes (`/marketplace`, `/my-inventory`, `/post-listing`, `/property/:listingId`), all requiring a session. `HomePlaceholderScreen` gains two navigation buttons.

This is the integration task — after this, `flutter test` (full suite) and `flutter analyze` must both be clean.

- [ ] **Step 1: Write the failing computeAuthRedirect tests for the new routes**

Read the existing `app/test/core/router/app_router_test.dart` first (it has 7 tests from Milestone 2). Add 4 new tests inside the existing `group('computeAuthRedirect', () { ... })` block, alongside the existing ones (don't replace the file, add to it):

```dart
    test('unauthenticated user on /marketplace is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/marketplace'), '/');
    });

    test('unauthenticated user on /my-inventory is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-inventory'), '/');
    });

    test('unauthenticated user on /post-listing is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/post-listing'), '/');
    });

    test('unauthenticated user on /property/l-1 is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/property/l-1'), '/');
    });
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/router/app_router_test.dart
```
Expected: FAIL — the 4 new assertions fail because `_publicRoutes` doesn't yet exclude these paths, so `computeAuthRedirect` correctly returns `'/'`... actually this should already PASS once you add the tests, since these routes aren't in `_publicRoutes` and the function's existing logic already redirects anything not in that set. Run it anyway to confirm — if it unexpectedly fails, `_publicRoutes` has been changed since this plan was written; stop and check `app_router.dart` before proceeding, don't guess.

- [ ] **Step 3: Add the 4 routes to app_router.dart**

Read the current `app/lib/core/router/app_router.dart` first. Add these imports alongside the existing screen imports:

```dart
import '../../features/listing/marketplace_screen.dart';
import '../../features/listing/my_inventory_screen.dart';
import '../../features/listing/post_listing_screen.dart';
import '../../features/listing/property_detail_screen.dart';
```

Add these 4 routes to the `routes:` list inside `appRouterProvider`, alongside the existing 6:

```dart
      GoRoute(path: '/marketplace', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const MyInventoryScreen()),
      GoRoute(path: '/post-listing', builder: (context, state) => const PostListingScreen()),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => PropertyDetailScreen(listingId: state.pathParameters['listingId']!),
      ),
```

Do not add any of these 4 paths to `_publicRoutes` — they require a session, which is the default (only paths explicitly listed in `_publicRoutes` skip the redirect).

- [ ] **Step 4: Run the router test again to confirm it passes**

```bash
flutter test test/core/router/app_router_test.dart
```
Expected: `00:0X +11: All tests passed!` (7 existing + 4 new).

- [ ] **Step 5: Write the failing HomePlaceholderScreen navigation test**

Read the existing `app/test/features/auth/home_placeholder_screen_test.dart` first (it has 1 test, pumping the screen inside a bare `MaterialApp`, no router). Replace its single test with a version that also verifies navigation — the screen needs a `GoRouter` now, so the wrapper changes from `MaterialApp` to `MaterialApp.router`:

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
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inventory_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('inventory-screen'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: FAIL — `HomePlaceholderScreen` doesn't build a `GoRouter`-aware tree yet (no navigable links), and the new translation keys don't exist yet.

- [ ] **Step 7: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "marketplace_title_placeholder_link": "Browse Marketplace",
  "inventory_title_placeholder_link": "My Inventory"
```

`app/assets/translations/ms.json` additions:
```json
  "marketplace_title_placeholder_link": "Layari Pasaran",
  "inventory_title_placeholder_link": "Inventori Saya"
```

- [ ] **Step 8: Update HomePlaceholderScreen**

Read the current `app/lib/features/auth/home_placeholder_screen.dart` first. Replace its `build` method's body to add two navigation buttons below the existing text, and add the `go_router` import:

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: Run test to verify it passes**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 10: Run the full test suite**

```bash
flutter test
```
Expected: every test passes, zero failures (Milestone 1-2's ~46 tests plus this plan's new tests: Task 2's 8, Task 5's 3, Task 6's 3, Task 7's 2, Task 8's 3, Task 9's 4 router + 2 extra home-placeholder = roughly `00:0X +71: All tests passed!` — exact count isn't the point, zero failures is).

- [ ] **Step 11: Run static analysis**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 12: Verify translation key parity**

```bash
flutter test test/l10n/translations_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 13: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/core/router/app_router.dart app/lib/features/auth/home_placeholder_screen.dart app/test/core/router/app_router_test.dart app/test/features/auth/home_placeholder_screen_test.dart
git commit -m "feat: wire listing routes and add navigation from HomePlaceholderScreen"
```

---

## Definition of Done

- `flutter test` (run from `app/`) passes with zero failures across the whole suite.
- `flutter analyze` reports no issues.
- `flutter run` on the user's Android emulator shows: `/home` (after login as an approved negotiator — or `/verification-pending` if still pending, unchanged from Milestone 2) has two working links to Marketplace and My Inventory; My Inventory's "Post New Listing" reaches a working multi-field form with photo picker; submitting creates a listing visible in My Inventory's Active tab and in Marketplace (from a different account, or the same account — RLS allows the owner to see their own regardless of status); tapping a listing card reaches Property Detail with working Mark Sold / Withdraw actions when viewing as the owner.
- The SQL migration (`0003_listing.sql`) has been run in the user's Supabase project (Task 1's manual step) — without this, every listing read/write fails with Postgrest errors even though all code is correct.
- All 9 tasks committed individually.

## Explicitly not in this plan

The `requirement` table, Requirement Board screen, My Requirements screen, and the `post_listing` mockup's "Cari Listing" tab — next milestone, per the design doc's scope split. Server-side search, the `match`/`cobroke_request`/collaboration flow, and the real `main_dashboard` screen are also out of scope, per the design doc's "Explicitly deferred" section.
