# Ratings/Reviews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let two negotiators who completed an accepted co-broking agreement rate and optionally review each other, once each, feeding a public average "Trust Score" on the rated negotiator's `ProfileScreen`, with a full reviews list screen.

**Architecture:** A new `rating` table with RLS reusing a new `is_agreement_party` helper function (checks one negotiator's party-membership on one agreement, avoiding repeating the join chain for both sides inline). A `RatingRepository` composes `ListingRepository` for rater-name lookups, bulk-resolved via `Future.wait`, matching the established `_toCandidates` pattern. Two already-shipped screens (`MyRequestsScreen`, `ProfileScreen`) gain new UI; one brand-new screen (`ReviewsScreen`) is added.

**Tech Stack:** Flutter, Riverpod, supabase_flutter, easy_localization (EN/MS), go_router. No new dependencies, no Realtime.

## Global Constraints

- `rating_update_by_rater`'s USING and WITH CHECK clauses must be IDENTICAL (`rater_id = auth.uid() and now() - created_at < interval '24 hours'`) — this is deliberate, not an oversight to "fix" into asymmetry. This project has already shipped 2 Critical-or-near-Critical bugs from the UPDATE+WITH CHECK risk class (Co-Broke Request's missing WITH CHECK, Profile's grant regression) — the task reviewer and final reviewer MUST trace this policy by hand, not wave it through as routine boilerplate.
- `created_at`, `rater_id`, `rated_id`, `agreement_id` must NEVER appear in the `update` column grant — only `(stars, review_text)`. This is what prevents the edit window from being extendable or the rating from being reassigned.
- `RatingRepository` is untested directly (Supabase-calling code) — established project convention. `Rating.fromJson` gets a real unit test. Widget-tested UI (`RateDialog`, `MyRequestsScreen`'s addition, `ProfileScreen`'s 3rd card, `ReviewsScreen`) all get widget tests via provider override.
- `currentNegotiatorIdProvider`: add another own copy in `rating_providers.dart`, same per-feature-file duplication convention as every sibling feature.
- `myRatingForAgreementProvider` and `ratingsForNegotiatorProvider` must both be `.autoDispose.family` — not bare `.family` (this project's pinned Riverpod 2.6.1 does not default `.family` to autoDispose).
- `updateRating` MUST chain `.select()` after the UPDATE and throw `StateError` if the result is empty — PostgREST returns 204 (success) on a zero-row RLS-rejected UPDATE, the same silent-failure shape `AgreementRepository`'s final-review fix already had to correct once in this codebase.
- l10n: every new user-facing string needs both an `en.json` and `ms.json` entry.

---

### Task 1: Supabase Migration SQL (0011_rating.sql)

**Files:**
- Create: `supabase/migrations/0011_rating.sql`
- Modify: `app/README.md` (append a "Milestone 10 setup (rating)" section after the Milestone 9 section)

**Interfaces:**
- Consumes: `agreement` table (from `0009_agreement.sql`), `cobroke_request`/`match`/`listing`/`requirement`/`negotiator` tables (from earlier migrations).
- Produces: `rating` table, `is_agreement_party(uuid, uuid) returns boolean` function, RLS, used by Task 3's `RatingRepository`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0011_rating.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0010.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

create table if not exists rating (
  rating_id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references agreement(agreement_id) on delete cascade,
  rater_id uuid not null references negotiator(negotiator_id) on delete cascade,
  rated_id uuid not null references negotiator(negotiator_id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  review_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  check (rater_id != rated_id)
);

-- At most one rating per rater per agreement, for the life of the
-- agreement. Not a point-in-time cap -- editing (within 24h, see below)
-- already covers "I made a mistake," so there's no re-rate-after-decline
-- case to accommodate here, unlike cobroke_request/agreement's own
-- partial-unique-index pattern.
drop index if exists rating_one_per_rater_per_agreement;
create unique index rating_one_per_rater_per_agreement
  on rating(agreement_id, rater_id);

create or replace function rating_set_updated_at() returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists rating_set_updated_at_trigger on rating;
create trigger rating_set_updated_at_trigger
  before update on rating for each row
  execute function rating_set_updated_at();

-- Checks whether p_negotiator_id is a genuine party (initiator, listing
-- owner, or requirement owner) to the cobroke_request underlying
-- p_agreement_id. Extracted as a reusable function rather than repeating
-- the agreement -> cobroke_request -> match -> listing/requirement join
-- chain inline for both rater_id and rated_id in the INSERT policy below.
-- Since every cobroke_request has exactly two parties, confirming BOTH
-- rater_id and rated_id are independently party members (and distinct
-- from each other, enforced separately) is sufficient to prove they are
-- the two opposite sides -- no explicit pairing logic needed.
create or replace function is_agreement_party(p_agreement_id uuid, p_negotiator_id uuid) returns boolean
language sql stable as $$
  select exists (
    select 1 from agreement a
    join cobroke_request cr on cr.request_id = a.request_id
    join match m on m.match_id = cr.match_id
    where a.agreement_id = p_agreement_id
      and (
        cr.initiator_id = p_negotiator_id
        or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = p_negotiator_id)
        or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = p_negotiator_id)
      )
  );
$$;

alter table rating enable row level security;

-- Select: public. Ratings/reviews are a trust signal meant to be visible
-- to any authenticated negotiator, same reasoning as agency_select_all.
drop policy if exists rating_select on rating;
create policy rating_select on rating for select
  to authenticated using (true);

-- Insert: sender must be themselves, target must be someone else, the
-- underlying agreement must be accepted, and BOTH rater and rated must
-- genuinely be parties to it.
drop policy if exists rating_insert on rating;
create policy rating_insert on rating for insert
  to authenticated with check (
    rater_id = auth.uid()
    and rated_id != rater_id
    and exists (select 1 from agreement a where a.agreement_id = rating.agreement_id and a.status = 'accepted')
    and is_agreement_party(rating.agreement_id, rater_id)
    and is_agreement_party(rating.agreement_id, rated_id)
  );

-- Update: only the original rater, only within 24 hours of creation.
-- USING and WITH CHECK are IDENTICAL here -- unlike cobroke_request's
-- Critical bug (USING encoded a "before" status the update was designed
-- to move away from), the 24-hour window condition doesn't change between
-- the old and new row states, so there's no transition to gate
-- asymmetrically. rater_id/created_at are excluded from the UPDATE grant
-- entirely (see below), so neither can be touched to extend the window or
-- reassign the rating.
drop policy if exists rating_update_by_rater on rating;
create policy rating_update_by_rater on rating for update
  to authenticated using (
    rater_id = auth.uid()
    and now() - created_at < interval '24 hours'
  )
  with check (
    rater_id = auth.uid()
    and now() - created_at < interval '24 hours'
  );

revoke insert on rating from authenticated;
grant insert (agreement_id, rater_id, rated_id, stars, review_text) on rating to authenticated;

revoke update on rating from authenticated;
grant update (stars, review_text) on rating to authenticated;
```

- [ ] **Step 2: Append README setup section**

Read `app/README.md`, find the "Milestone 9 setup (profile)" section, and append immediately after it:

```markdown
### Milestone 10 setup (rating)

Run `supabase/migrations/0011_rating.sql` in the Supabase SQL Editor after 0001-0010. This creates the `rating` table, its RLS policies, an `is_agreement_party` helper function, and a trigger that sets `updated_at` server-side on every update -- no manual dashboard step beyond running the SQL.
```

- [ ] **Step 3: Verify with grep**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0011_rating.sql
grep -c "^create policy" supabase/migrations/0011_rating.sql
grep -c "create or replace function" supabase/migrations/0011_rating.sql
```
Expected: `1`, `3`, `2` (2 functions: `rating_set_updated_at`, `is_agreement_party`).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0011_rating.sql app/README.md
git commit -m "feat: add rating Supabase migration with is_agreement_party helper"
```

---

### Task 2: Rating + RatingCandidate models + unit test

**Files:**
- Create: `app/lib/features/ratings/models/rating.dart`
- Create: `app/lib/features/ratings/models/rating_candidate.dart`
- Test: `app/test/features/ratings/models/rating_test.dart`

**Interfaces:**
- Consumes: `ListingOwner` (`app/lib/features/listing/models/listing_owner.dart`, fields `fullName`, `renNumber`).
- Produces: `Rating` class with `ratingId, agreementId, raterId, ratedId, stars (int), reviewText (String?), createdAt, updatedAt (DateTime?)` and `Rating.fromJson(Map<String, dynamic>)`; `RatingCandidate` class wrapping `{required Rating rating, required ListingOwner rater}` — used by Task 3's `RatingRepository`, Task 4's providers, Task 6/7/8's UI.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/ratings/models/rating_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/ratings/models/rating.dart';

void main() {
  group('Rating.fromJson', () {
    test('parses a fresh rating with no review text or update', () {
      final rating = Rating.fromJson({
        'rating_id': 'rat-1',
        'agreement_id': 'agr-1',
        'rater_id': 'n-1',
        'rated_id': 'n-2',
        'stars': 5,
        'review_text': null,
        'created_at': '2026-08-24T10:00:00.000Z',
        'updated_at': null,
      });

      expect(rating.ratingId, 'rat-1');
      expect(rating.agreementId, 'agr-1');
      expect(rating.raterId, 'n-1');
      expect(rating.ratedId, 'n-2');
      expect(rating.stars, 5);
      expect(rating.reviewText, isNull);
      expect(rating.createdAt, DateTime.parse('2026-08-24T10:00:00.000Z'));
      expect(rating.updatedAt, isNull);
    });

    test('parses an edited rating with review text and updated_at', () {
      final rating = Rating.fromJson({
        'rating_id': 'rat-2',
        'agreement_id': 'agr-2',
        'rater_id': 'n-3',
        'rated_id': 'n-4',
        'stars': 3,
        'review_text': 'Good to work with, minor communication delays.',
        'created_at': '2026-08-24T10:00:00.000Z',
        'updated_at': '2026-08-24T11:30:00.000Z',
      });

      expect(rating.stars, 3);
      expect(rating.reviewText, 'Good to work with, minor communication delays.');
      expect(rating.updatedAt, DateTime.parse('2026-08-24T11:30:00.000Z'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/ratings/models/rating_test.dart`
Expected: FAIL -- `Rating` is not defined (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/features/ratings/models/rating.dart

/// A row from the `rating` table.
class Rating {
  final String ratingId;
  final String agreementId;
  final String raterId;
  final String ratedId;
  final int stars;
  final String? reviewText;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Rating({
    required this.ratingId,
    required this.agreementId,
    required this.raterId,
    required this.ratedId,
    required this.stars,
    this.reviewText,
    required this.createdAt,
    this.updatedAt,
  });

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      ratingId: json['rating_id'] as String,
      agreementId: json['agreement_id'] as String,
      raterId: json['rater_id'] as String,
      ratedId: json['rated_id'] as String,
      stars: json['stars'] as int,
      reviewText: json['review_text'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null ? null : DateTime.parse(json['updated_at'] as String),
    );
  }
}
```

```dart
// app/lib/features/ratings/models/rating_candidate.dart
import '../../listing/models/listing_owner.dart';
import 'rating.dart';

/// A rating row joined with the rater's display name -- reuses
/// `ListingOwner` directly rather than inventing a second name-shaped
/// model, same reuse precedent as `CobrokeRequestCandidate` wrapping
/// `MatchCandidate`.
class RatingCandidate {
  final Rating rating;
  final ListingOwner rater;

  const RatingCandidate({required this.rating, required this.rater});
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/ratings/models/rating_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/ratings/models/rating.dart app/lib/features/ratings/models/rating_candidate.dart app/test/features/ratings/models/rating_test.dart
git commit -m "feat: add Rating and RatingCandidate models"
```

---

### Task 3: RatingRepository

**Files:**
- Create: `app/lib/features/ratings/rating_repository.dart`

**Interfaces:**
- Consumes: `Rating`/`RatingCandidate` (Task 2); `ListingRepository.fetchListingOwner(String negotiatorId) -> Future<ListingOwner>` (`app/lib/features/listing/listing_repository.dart:45`).
- Produces: `RatingRepository` with `createRating({required agreementId, required raterId, required ratedId, required int stars, String? reviewText}) -> Future<void>`, `updateRating({required ratingId, required int stars, String? reviewText}) -> Future<void>`, `fetchMyRatingForAgreement({required agreementId, required raterId}) -> Future<Rating?>`, `fetchRatingsForNegotiator(String negotiatorId) -> Future<List<RatingCandidate>>` -- used by Task 4's providers.

This repository is NOT unit-tested directly -- established convention. No test file for this task.

- [ ] **Step 1: Write the repository**

```dart
// app/lib/features/ratings/rating_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing_owner.dart';
import 'models/rating.dart';
import 'models/rating_candidate.dart';

/// The only file in this app that talks to Supabase for the ratings
/// feature. Composes ListingRepository for rater-name lookups, same reuse
/// precedent as CobrokeRequestRepository/MessageRepository.
class RatingRepository {
  RatingRepository(this._client, this._listingRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;

  Future<void> createRating({
    required String agreementId,
    required String raterId,
    required String ratedId,
    required int stars,
    String? reviewText,
  }) async {
    await _client.from('rating').insert({
      'agreement_id': agreementId,
      'rater_id': raterId,
      'rated_id': ratedId,
      'stars': stars,
      'review_text': reviewText,
    });
  }

  /// Chains .select() after the update and throws if the result is empty
  /// -- PostgREST returns 204 (success) on a zero-row RLS-rejected UPDATE
  /// (e.g. the 24-hour edit window has expired), the same silent-failure
  /// shape AgreementRepository's final-review fix already had to correct
  /// once in this codebase.
  Future<void> updateRating({
    required String ratingId,
    required int stars,
    String? reviewText,
  }) async {
    final rows = await _client
        .from('rating')
        .update({'stars': stars, 'review_text': reviewText})
        .eq('rating_id', ratingId)
        .select();
    if (rows.isEmpty) {
      throw StateError('Rating update was rejected (edit window expired or not permitted)');
    }
  }

  Future<Rating?> fetchMyRatingForAgreement({
    required String agreementId,
    required String raterId,
  }) async {
    final row = await _client
        .from('rating')
        .select()
        .eq('agreement_id', agreementId)
        .eq('rater_id', raterId)
        .maybeSingle();
    if (row == null) return null;
    return Rating.fromJson(row);
  }

  /// Bulk-resolves rater names via Future.wait over the distinct rater ids
  /// in the result set, not a sequential per-row await -- same concurrent
  /// resolution pattern MatchingRepository/CobrokeRequestRepository's
  /// _toCandidates methods already establish.
  Future<List<RatingCandidate>> fetchRatingsForNegotiator(String negotiatorId) async {
    final rows = await _client
        .from('rating')
        .select()
        .eq('rated_id', negotiatorId)
        .order('created_at', ascending: false);
    final ratings = (rows as List).map((row) => Rating.fromJson(row as Map<String, dynamic>)).toList();

    final raterIds = ratings.map((r) => r.raterId).toSet();
    final ownersById = Map<String, ListingOwner>.fromIterables(
      raterIds,
      await Future.wait(raterIds.map(_listingRepository.fetchListingOwner)),
    );

    return ratings
        .map((rating) => RatingCandidate(rating: rating, rater: ownersById[rating.raterId]!))
        .toList();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/ratings/rating_repository.dart
git commit -m "feat: add RatingRepository"
```

---

### Task 4: rating_providers.dart

**Files:**
- Create: `app/lib/features/ratings/rating_providers.dart`

**Interfaces:**
- Consumes: `RatingRepository` (Task 3); `authStateProvider` (`app/lib/features/auth/auth_providers.dart`); `listingRepositoryProvider` (`app/lib/features/listing/listing_providers.dart`).
- Produces: `ratingRepositoryProvider`, `currentNegotiatorIdProvider` (this feature's own copy), `myRatingForAgreementProvider = FutureProvider.autoDispose.family<Rating?, String>` (keyed by agreementId), `ratingsForNegotiatorProvider = FutureProvider.autoDispose.family<List<RatingCandidate>, String>` (keyed by negotiatorId) -- used by Task 5/6/7/8's UI.

- [ ] **Step 1: Write the providers**

```dart
// app/lib/features/ratings/rating_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import 'rating_repository.dart';
import 'models/rating.dart';
import 'models/rating_candidate.dart';

final ratingRepositoryProvider = Provider<RatingRepository>((ref) {
  return RatingRepository(Supabase.instance.client, ref.watch(listingRepositoryProvider));
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// The current viewer's own rating for one agreement, if any -- used to
/// decide whether MyRequestsScreen shows Rate, Edit rating, or a static
/// "you rated" label. autoDispose is REQUIRED, not the default, in this
/// project's pinned Riverpod version (2.6.1).
final myRatingForAgreementProvider = FutureProvider.autoDispose.family<Rating?, String>((ref, agreementId) {
  final raterId = ref.watch(currentNegotiatorIdProvider);
  if (raterId == null) return Future.value(null);
  return ref.watch(ratingRepositoryProvider).fetchMyRatingForAgreement(agreementId: agreementId, raterId: raterId);
});

/// All ratings received by one negotiator, with rater names resolved --
/// one provider, two consumers: ProfileScreen's average computation and
/// ReviewsScreen's full list.
final ratingsForNegotiatorProvider = FutureProvider.autoDispose.family<List<RatingCandidate>, String>((ref, negotiatorId) {
  return ref.watch(ratingRepositoryProvider).fetchRatingsForNegotiator(negotiatorId);
});
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/ratings/rating_providers.dart
git commit -m "feat: add rating Riverpod providers"
```

---

### Task 5: RateDialog + l10n keys

**Files:**
- Create: `app/lib/features/ratings/rate_dialog.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json` (add new keys, see Step 1)

**Interfaces:**
- Consumes: `ratingRepositoryProvider`, `myRatingForAgreementProvider`, `ratingsForNegotiatorProvider` (Task 4); `Rating` (Task 2).
- Produces: `RateDialog({required String agreementId, required String raterId, required String ratedId, Rating? existingRating})` -- used by Task 6's `MyRequestsScreen` addition.

Follows `ProposeAgreementDialog`'s established pattern (`ConsumerStatefulWidget`, `_submitting`/`_submitError`, `AlertDialog` with Cancel/Submit).

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"profile_save_success": "Profile updated"` (the last key in the file) and add a comma after it, then add these new keys immediately after:

```json
  "rating_dialog_title": "Rate this collaboration",
  "rating_review_label": "Review (optional)",
  "rating_submit": "Submit",
  "rating_cancel": "Cancel",
  "rating_rate_button": "Rate",
  "rating_edit_button": "Edit rating",
  "rating_you_rated": "You rated",
  "profile_trust_score_label": "Trust Score",
  "profile_no_ratings_yet": "No ratings yet",
  "rating_reviews_title": "Reviews",
  "rating_reviews_empty": "No reviews yet"
```

In `app/assets/translations/ms.json`, same position (after `"profile_save_success": "Profil dikemas kini"`), add:

```json
  "rating_dialog_title": "Nilai kerjasama ini",
  "rating_review_label": "Ulasan (pilihan)",
  "rating_submit": "Hantar",
  "rating_cancel": "Batal",
  "rating_rate_button": "Nilai",
  "rating_edit_button": "Edit penilaian",
  "rating_you_rated": "Anda menilai",
  "profile_trust_score_label": "Skor Kepercayaan",
  "profile_no_ratings_yet": "Belum ada penilaian",
  "rating_reviews_title": "Ulasan",
  "rating_reviews_empty": "Belum ada ulasan"
```

- [ ] **Step 2: Write the dialog**

```dart
// app/lib/features/ratings/rate_dialog.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/rating.dart';
import 'rating_providers.dart';

class RateDialog extends ConsumerStatefulWidget {
  const RateDialog({
    super.key,
    required this.agreementId,
    required this.raterId,
    required this.ratedId,
    this.existingRating,
  });

  final String agreementId;
  final String raterId;
  final String ratedId;
  final Rating? existingRating;

  @override
  ConsumerState<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends ConsumerState<RateDialog> {
  late int _stars;
  late final TextEditingController _reviewController;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _stars = widget.existingRating?.stars ?? 5;
    _reviewController = TextEditingController(text: widget.existingRating?.reviewText ?? '');
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final reviewText = _reviewController.text.trim().isEmpty ? null : _reviewController.text.trim();
      final existing = widget.existingRating;
      if (existing == null) {
        await ref.read(ratingRepositoryProvider).createRating(
              agreementId: widget.agreementId,
              raterId: widget.raterId,
              ratedId: widget.ratedId,
              stars: _stars,
              reviewText: reviewText,
            );
      } else {
        await ref.read(ratingRepositoryProvider).updateRating(
              ratingId: existing.ratingId,
              stars: _stars,
              reviewText: reviewText,
            );
      }
      ref.invalidate(myRatingForAgreementProvider(widget.agreementId));
      ref.invalidate(ratingsForNegotiatorProvider(widget.ratedId));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError = 'listing_error_generic'.tr();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('rating_dialog_title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return IconButton(
                icon: Icon(starValue <= _stars ? Icons.star : Icons.star_border),
                onPressed: _submitting ? null : () => setState(() => _stars = starValue),
              );
            }),
          ),
          TextField(
            controller: _reviewController,
            decoration: InputDecoration(labelText: 'rating_review_label'.tr()),
            maxLines: 3,
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 8),
            Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('rating_cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text('rating_submit'.tr()),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/ratings/rate_dialog.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add RateDialog and rating l10n keys"
```

---

### Task 6: Wire Rate button into MyRequestsScreen

**Files:**
- Modify: `app/lib/features/collaboration/my_requests_screen.dart`
- Modify: `app/test/features/collaboration/my_requests_screen_test.dart`

**Interfaces:**
- Consumes: `RateDialog` (Task 5); `myRatingForAgreementProvider`, `ratingRepositoryProvider` (Task 4); `Rating` (Task 2); existing `_RequestList`/`_AgreementSection`/`CobrokeRequestCandidate` shapes.
- Produces: nothing new consumed by later tasks.

- [ ] **Step 1: Add imports**

In `app/lib/features/collaboration/my_requests_screen.dart`, add these two imports alphabetically with the existing imports (`ratings/` sorts after `propose_agreement_dialog.dart`'s own directory position -- insert after the existing `import 'propose_agreement_dialog.dart';` line):

```dart
import '../ratings/rate_dialog.dart';
import '../ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
```

The `hide currentNegotiatorIdProvider` clause is required for the same reason `agreement_providers.dart`'s import already has one -- `rating_providers.dart` defines its own copy, which would otherwise collide with `cobroke_request_providers.dart`'s.

- [ ] **Step 2: Compute and thread the counterparty's negotiator id**

In `_RequestList.build`'s `itemBuilder`, currently:

```dart
              final candidate = requests[index];
              final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
              final counterpartyOwner = isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;
```

Add one line immediately after `counterpartyOwner`:

```dart
              final candidate = requests[index];
              final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
              final counterpartyOwner = isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;
              final counterpartyNegotiatorId =
                  isMyListing ? candidate.match.requirement.negotiatorId : candidate.match.listing.negotiatorId;
```

- [ ] **Step 3: Pass the new value into _AgreementSection**

Currently:

```dart
                        _AgreementSection(
                          requestId: candidate.request.requestId,
                          currentNegotiatorId: currentNegotiatorId,
                        ),
```

Change to:

```dart
                        _AgreementSection(
                          requestId: candidate.request.requestId,
                          currentNegotiatorId: currentNegotiatorId,
                          ratedId: counterpartyNegotiatorId,
                        ),
```

- [ ] **Step 4: Update _AgreementSection's constructor**

Currently:

```dart
class _AgreementSection extends ConsumerWidget {
  const _AgreementSection({required this.requestId, required this.currentNegotiatorId});

  final String requestId;
  final String? currentNegotiatorId;
```

Change to:

```dart
class _AgreementSection extends ConsumerWidget {
  const _AgreementSection({
    required this.requestId,
    required this.currentNegotiatorId,
    required this.ratedId,
  });

  final String requestId;
  final String? currentNegotiatorId;
  final String ratedId;
```

- [ ] **Step 5: Add the rating section to the accepted-status branch**

Currently, the last branch in `_AgreementSection.build`'s `data:` callback (the `// status == 'accepted'` branch) ends:

```dart
        // status == 'accepted'
        final acceptedAt = agreement.acceptedAt;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(splitText),
            if (agreement.terms != null && agreement.terms!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(agreement.terms!),
            ],
            const SizedBox(height: 4),
            Text(acceptedAt == null
                ? 'agreement_accepted_on'.tr()
                : '${'agreement_accepted_on'.tr()} ${acceptedAt.day}/${acceptedAt.month}/${acceptedAt.year}'),
          ],
        );
      },
    );
  }
}
```

Add a new item to that `children` list, right after the accepted-date `Text`:

```dart
        // status == 'accepted'
        final acceptedAt = agreement.acceptedAt;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(splitText),
            if (agreement.terms != null && agreement.terms!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(agreement.terms!),
            ],
            const SizedBox(height: 4),
            Text(acceptedAt == null
                ? 'agreement_accepted_on'.tr()
                : '${'agreement_accepted_on'.tr()} ${acceptedAt.day}/${acceptedAt.month}/${acceptedAt.year}'),
            const SizedBox(height: 8),
            _RatingSection(
              agreementId: agreement.agreementId,
              raterId: currentNegotiatorId!,
              ratedId: ratedId,
            ),
          ],
        );
      },
    );
  }
}
```

Then add this new widget class at the very end of the file, after the closing brace of `_AgreementSection`:

```dart
class _RatingSection extends ConsumerWidget {
  const _RatingSection({required this.agreementId, required this.raterId, required this.ratedId});

  final String agreementId;
  final String raterId;
  final String ratedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingAsync = ref.watch(myRatingForAgreementProvider(agreementId));

    return ratingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (rating) {
        if (rating == null) {
          return OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(agreementId: agreementId, raterId: raterId, ratedId: ratedId),
            ),
            child: Text('rating_rate_button'.tr()),
          );
        }

        final withinEditWindow = DateTime.now().difference(rating.createdAt) < const Duration(hours: 24);
        if (withinEditWindow) {
          return OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(
                agreementId: agreementId,
                raterId: raterId,
                ratedId: ratedId,
                existingRating: rating,
              ),
            ),
            child: Text('rating_edit_button'.tr()),
          );
        }

        return Text('${'rating_you_rated'.tr()}: ${rating.stars}');
      },
    );
  }
}
```

- [ ] **Step 6: Extend the test file's fixtures with a match that has both sides' negotiatorId set**

In `app/test/features/collaboration/my_requests_screen_test.dart`, add this import after the existing `agreement_providers.dart`-related import:

```dart
import 'package:renly/features/ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
```

Extend the `_wrap` function signature to accept an optional rating override, following the exact same optional-parameter pattern already used for `agreementRequestId`/`agreement`:

```dart
Widget _wrap(
  GoRouter router, {
  List<CobrokeRequestCandidate>? received,
  List<CobrokeRequestCandidate>? sent,
  String? agreementRequestId,
  Agreement? agreement,
  String? ratingAgreementId,
  Rating? rating,
}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      receivedRequestsProvider.overrideWith((ref) async => received ?? _fixtureReceived),
      sentRequestsProvider.overrideWith((ref) async => sent ?? const []),
      if (agreementRequestId != null)
        agreementForRequestProvider(agreementRequestId).overrideWith((ref) async => agreement),
      if (ratingAgreementId != null)
        myRatingForAgreementProvider(ratingAgreementId).overrideWith((ref) async => rating),
    ],
```

Add this import too (for the `Rating` type used in the new optional parameter):

```dart
import 'package:renly/features/ratings/models/rating.dart';
```

- [ ] **Step 7: Add the new tests**

Add these 3 tests inside `main()`, after the existing tests:

```dart
  testWidgets('shows Rate button when accepted agreement has no rating yet', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-10',
          matchId: 'm-10',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-5',
      requestId: 'req-10',
      initiatorId: 'n-2',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 24),
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      received: accepted,
      agreementRequestId: 'req-10',
      agreement: agreement,
      ratingAgreementId: 'agr-5',
      rating: null,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rate'), findsOneWidget);
  });

  testWidgets('shows Edit rating button within the 24-hour window', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-11',
          matchId: 'm-11',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-6',
      requestId: 'req-11',
      initiatorId: 'n-2',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 24),
      createdAt: DateTime(2026, 8, 24),
    );
    final recentRating = Rating(
      ratingId: 'rat-10',
      agreementId: 'agr-6',
      raterId: 'n-1',
      ratedId: 'n-2',
      stars: 4,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      received: accepted,
      agreementRequestId: 'req-11',
      agreement: agreement,
      ratingAgreementId: 'agr-6',
      rating: recentRating,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Edit rating'), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('shows read-only "you rated" text past the 24-hour window', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-12',
          matchId: 'm-12',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-7',
      requestId: 'req-12',
      initiatorId: 'n-2',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 24),
      createdAt: DateTime(2026, 8, 24),
    );
    final oldRating = Rating(
      ratingId: 'rat-11',
      agreementId: 'agr-7',
      raterId: 'n-1',
      ratedId: 'n-2',
      stars: 2,
      createdAt: DateTime.now().subtract(const Duration(hours: 25)),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      received: accepted,
      agreementRequestId: 'req-12',
      agreement: agreement,
      ratingAgreementId: 'agr-7',
      rating: oldRating,
    ));
    await tester.pumpAndSettle();

    expect(find.text('You rated: 2'), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
    expect(find.text('Edit rating'), findsNothing);
  });
```

- [ ] **Step 8: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/my_requests_screen_test.dart`
Expected: PASS (13 tests -- the 10 existing plus 3 new).

- [ ] **Step 9: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 10: Commit**

```bash
git add app/lib/features/collaboration/my_requests_screen.dart app/test/features/collaboration/my_requests_screen_test.dart
git commit -m "feat: wire Rate/Edit-rating UI into MyRequestsScreen's accepted-agreement row"
```

---

### Task 7: Wire Trust Score stat card into ProfileScreen

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Modify: `app/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `ratingsForNegotiatorProvider` (Task 4); `RatingCandidate` (Task 2); existing `ProfileScreen`/`_StatCard`/`Profile` shapes.
- Produces: nothing new consumed by later tasks.

- [ ] **Step 1: Add imports**

In `app/lib/features/profile/profile_screen.dart`, add these two imports alphabetically with the existing ones (after the `flutter_riverpod` import, before the relative imports):

```dart
import 'package:go_router/go_router.dart';
```

And with the relative imports:

```dart
import '../ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
```

- [ ] **Step 2: Widen _StatCard's value type from int to String**

Currently:

```dart
class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    );
  }
}
```

Change to:

```dart
class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Update the two existing call sites and add the third card**

Currently:

```dart
                countsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (counts) => Row(
                    children: [
                      Expanded(child: _StatCard(value: counts.$1, label: 'profile_active_listings_label'.tr())),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(value: counts.$2, label: 'profile_deals_closed_label'.tr())),
                    ],
                  ),
                ),
```

Change to:

```dart
                countsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (counts) => Row(
                    children: [
                      Expanded(child: _StatCard(value: '${counts.$1}', label: 'profile_active_listings_label'.tr())),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(value: '${counts.$2}', label: 'profile_deals_closed_label'.tr())),
                      const SizedBox(width: 12),
                      Expanded(child: _TrustScoreCard(negotiatorId: profile.negotiatorId)),
                    ],
                  ),
                ),
```

- [ ] **Step 4: Add the _TrustScoreCard widget**

Add this new widget class at the end of the file, after the closing brace of `_StatCard`:

```dart
class _TrustScoreCard extends ConsumerWidget {
  const _TrustScoreCard({required this.negotiatorId});

  final String negotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsForNegotiatorProvider(negotiatorId));

    return ratingsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (candidates) {
        final display = candidates.isEmpty
            ? 'profile_no_ratings_yet'.tr()
            : (candidates.map((c) => c.rating.stars).reduce((a, b) => a + b) / candidates.length)
                .toStringAsFixed(1);
        return InkWell(
          onTap: () => context.push('/reviews'),
          child: _StatCard(value: display, label: 'profile_trust_score_label'.tr()),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Extend the test file's fixture wrap helper**

In `app/test/features/profile/profile_screen_test.dart`, add these two imports after the existing `profile_providers.dart` import:

```dart
import 'package:renly/features/ratings/models/rating_candidate.dart';
import 'package:renly/features/ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
```

Extend `_wrap`'s signature and overrides list to accept an optional ratings override:

```dart
Widget _wrap(GoRouter router, {Profile? profile, (int, int)? counts, List<RatingCandidate>? ratings}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myProfileProvider.overrideWith((ref) async => profile ?? _fixtureProfile),
      profileCountsProvider.overrideWith((ref) async => counts ?? (5, 3)),
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => ratings ?? const []),
    ],
```

- [ ] **Step 6: Add a test for the Trust Score card**

Add this test inside `main()`, after the existing tests:

```dart
  testWidgets('shows "No ratings yet" when the negotiator has no ratings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, ratings: const []));
    await tester.pumpAndSettle();

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('Trust Score'), findsOneWidget);
  });
```

- [ ] **Step 7: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/profile_screen_test.dart`
Expected: PASS (4 tests -- the 3 existing plus 1 new).

- [ ] **Step 8: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart
git commit -m "feat: wire Trust Score stat card into ProfileScreen, widen _StatCard to String"
```

---

### Task 8: ReviewsScreen + router wiring

**Files:**
- Create: `app/lib/features/ratings/reviews_screen.dart`
- Test: `app/test/features/ratings/reviews_screen_test.dart`
- Modify: `app/lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: `ratingsForNegotiatorProvider`, `currentNegotiatorIdProvider` (Task 4); `RatingCandidate`/`Rating` (Task 2).
- Produces: `ReviewsScreen` widget, `/reviews` route -- last task, nothing consumed further.

- [ ] **Step 1: Write the screen**

```dart
// app/lib/features/ratings/reviews_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/rating_candidate.dart';
import 'rating_providers.dart';

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('rating_reviews_title'.tr())),
      body: negotiatorId == null ? const SizedBox.shrink() : _ReviewsList(negotiatorId: negotiatorId),
    );
  }
}

class _ReviewsList extends ConsumerWidget {
  const _ReviewsList({required this.negotiatorId});

  final String negotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsForNegotiatorProvider(negotiatorId));

    return ratingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
      data: (candidates) {
        if (candidates.isEmpty) {
          return Center(child: Text('rating_reviews_empty'.tr()));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: candidates.length,
          itemBuilder: (context, index) => _ReviewRow(candidate: candidates[index]),
        );
      },
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.candidate});

  final RatingCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final rating = candidate.rating;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(candidate.rater.fullName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${rating.stars} / 5'),
            if (rating.reviewText != null && rating.reviewText!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(rating.reviewText!),
            ],
            const SizedBox(height: 4),
            Text('${rating.createdAt.day}/${rating.createdAt.month}/${rating.createdAt.year}'),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the widget test**

```dart
// app/test/features/ratings/reviews_screen_test.dart
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
import 'package:renly/features/ratings/models/rating.dart';
import 'package:renly/features/ratings/models/rating_candidate.dart';
import 'package:renly/features/ratings/rating_providers.dart';
import 'package:renly/features/ratings/reviews_screen.dart';

final _fixtureCandidates = [
  RatingCandidate(
    rating: Rating(
      ratingId: 'rat-1',
      agreementId: 'agr-1',
      raterId: 'n-2',
      ratedId: 'n-1',
      stars: 5,
      reviewText: 'Excellent to work with.',
      createdAt: DateTime(2026, 8, 24),
    ),
    rater: const ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345'),
  ),
];

Widget _wrap(GoRouter router, {List<RatingCandidate>? candidates}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => candidates ?? _fixtureCandidates),
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

  testWidgets('renders reviews from the fixed provider override', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ReviewsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('5 / 5'), findsOneWidget);
    expect(find.text('Excellent to work with.'), findsOneWidget);
  });

  testWidgets('renders empty state when there are no reviews', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ReviewsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, candidates: []));
    await tester.pumpAndSettle();

    expect(find.text('No reviews yet'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/ratings/`
Expected: PASS (4 tests -- 2 from Task 2's `rating_test.dart` plus these 2 new).

- [ ] **Step 4: Add the import and route to app_router.dart**

In `app/lib/core/router/app_router.dart`, insert this import after the `profile/profile_screen.dart` import and before the `requirement/` imports:

```dart
import '../../features/ratings/reviews_screen.dart';
```

Add this route as the new last entry in the `routes:` list, immediately after the existing `GoRoute(path: '/profile', ...)` route:

```dart
      GoRoute(path: '/reviews', builder: (context, state) => const ReviewsScreen()),
```

- [ ] **Step 5: Run the full suite to confirm zero regression**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test`
Expected: all tests pass (prior suite count 150 + this plan's new tests: Task 2's 2 + Task 6's 3 + Task 7's 1 + Task 8's 2 = 8 new tests = 158 total).

- [ ] **Step 6: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/ratings/reviews_screen.dart app/test/features/ratings/reviews_screen_test.dart app/lib/core/router/app_router.dart
git commit -m "feat: add ReviewsScreen and /reviews route"
```
