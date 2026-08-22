# renly Co-Broke Request Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Either party to a `match` can send a formal co-broke request; the other party accepts or declines; both sides can see every request they've sent or received in one screen.

**Architecture:** `CobrokeRequestRepository` composes `ListingRepository` (for owner lookups) the same way `MatchingRepository` does — reuses `fetchListingOwner`, doesn't duplicate it. `CobrokeRequestCandidate` wraps a raw `CobrokeRequest` row together with the `MatchCandidate` it's for, reusing that model directly rather than inventing a second "what does this match look like" representation. The "Request Co-Broke" action is a single shared function (`sendCobrokeRequest`), not duplicated three times, called from a new button added to each of the three existing match-list screens.

**Tech Stack:** Flutter/Dart, Riverpod, `supabase_flutter`, `go_router`, `easy_localization` (all already dependencies).

## Global Constraints

- No screen calls `Supabase.instance.client` directly — always through `CobrokeRequestRepository`.
- `currentNegotiatorIdProvider` is defined fresh in `cobroke_request_providers.dart` (same body as the three existing copies in `listing_providers.dart`/`requirement_providers.dart`/`matching_providers.dart`) — not imported from a sibling feature, same established reasoning. This is now a 4th copy of an identical provider; that growing duplication is a known, already-flagged backlog item (a future hoist into `auth_providers.dart` would remove all 4 copies at once) — not something this plan fixes, to keep this module's blast radius limited to files it actually needs to touch.
- Every new UI string goes into BOTH `app/assets/translations/en.json` and `app/assets/translations/ms.json` with matching keys. Reuse `listing_error_generic` for error states — no new collaboration-scoped error key.
- **Every test file with 2+ `testWidgets` sharing `EasyLocalization` MUST include** `import 'package:flutter/services.dart';` + `setUp(() { rootBundle.clear(); });` right after `setUpAll`, plus `await tester.pumpAndSettle();` after every `pumpWidget` and before any `tap`.
- Test assertions/tap targets use hardcoded literal English strings, not `.tr()` calls.
- `cobroke_request.status` is one of `pending`/`accepted`/`declined`. A match may have many `cobroke_request` rows over time (one per attempt), but at most one `pending` at once, enforced by a partial unique index — not a plain unique constraint on `match_id`.
- Only the RECEIVING party (never the initiator) may transition a request's status — enforced by RLS (`initiator_id != auth.uid()` in the UPDATE policy's `USING` clause), not just by hiding the Accept/Decline buttons in the UI.
- All three owner/candidate lookups (`MatchingRepository._toCandidates` precedent from the prior milestone) resolve owners **concurrently** via `Future.wait`, not sequentially in a loop — write it correctly from the start here, this exact mistake needed a fix round in the previous module.
- SQL migration is a manual, user-performed step (Task 1) — this session has no DB credentials.
- Flutter is on PATH via `export PATH="$HOME/development/flutter/bin:$PATH"` — run first if `flutter` isn't found. All commands assume this has been run and `cd` is `app/` unless stated otherwise.

---

### Task 1: Supabase migration SQL (0007_cobroke_request.sql)

**Files:**
- Create: `supabase/migrations/0007_cobroke_request.sql`
- Modify: `app/README.md` (append a "Milestone 6 setup" section)

**Interfaces:**
- Produces: the `cobroke_request` table that Task 3's `CobrokeRequestRepository` assumes exists.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0007_cobroke_request.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0006.
--
-- Written to be re-runnable from the start, same pattern as
-- 0006_matching.sql (create table if not exists, drop policy if exists
-- before each create policy).

create table if not exists cobroke_request (
  request_id uuid primary key default gen_random_uuid(),
  match_id uuid not null references match(match_id) on delete cascade,
  initiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now()
);

-- At most one PENDING request per match at a time. A prior request on the
-- same match that was declined has status 'declined', not 'pending', so it
-- doesn't collide with this index -- this is what makes "re-request after
-- decline" possible, deliberately, per the design doc's resolution of the
-- proposal ERD's ambiguous "1 match : at most 1 request" wording.
drop index if exists cobroke_request_one_pending_per_match;
create unique index cobroke_request_one_pending_per_match
  on cobroke_request(match_id) where status = 'pending';

alter table cobroke_request enable row level security;

-- Both parties to the underlying match can see a request: the initiator,
-- or whichever of the match's listing/requirement they own.
drop policy if exists cobroke_request_select on cobroke_request;
create policy cobroke_request_select on cobroke_request for select
  to authenticated using (
    initiator_id = auth.uid()
    or exists (
      select 1 from match m
      join listing l on l.listing_id = m.listing_id
      where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
    )
    or exists (
      select 1 from match m
      join requirement r on r.requirement_id = m.requirement_id
      where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
    )
  );

-- Insert: must be the initiator, and must actually be a party to the match
-- (own the listing or requirement side) -- not an uninvolved third party
-- inserting a request on someone else's match.
drop policy if exists cobroke_request_insert on cobroke_request;
create policy cobroke_request_insert on cobroke_request for insert
  to authenticated with check (
    initiator_id = auth.uid()
    and (
      exists (
        select 1 from match m
        join listing l on l.listing_id = m.listing_id
        where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
      )
      or exists (
        select 1 from match m
        join requirement r on r.requirement_id = m.requirement_id
        where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
      )
    )
  );

-- Update: ONLY the receiving party (never the initiator) may change status,
-- and only while it's still pending. The initiator cannot accept/decline
-- their own request.
drop policy if exists cobroke_request_update_by_recipient on cobroke_request;
create policy cobroke_request_update_by_recipient on cobroke_request for update
  to authenticated using (
    status = 'pending'
    and initiator_id != auth.uid()
    and (
      exists (
        select 1 from match m
        join listing l on l.listing_id = m.listing_id
        where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
      )
      or exists (
        select 1 from match m
        join requirement r on r.requirement_id = m.requirement_id
        where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
      )
    )
  );

revoke insert on cobroke_request from authenticated;
grant insert (match_id, initiator_id) on cobroke_request to authenticated;

revoke update on cobroke_request from authenticated;
grant update (status) on cobroke_request to authenticated;
```

- [ ] **Step 2: Verify the file is well-formed**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0007_cobroke_request.sql
grep -c "^create policy" supabase/migrations/0007_cobroke_request.sql
```
Expected: `1` (cobroke_request) and `3` (cobroke_request_select, cobroke_request_insert, cobroke_request_update_by_recipient).

- [ ] **Step 3: Append manual setup instructions to app/README.md**

Read the current `app/README.md` first (it has Milestone 1-5 setup sections). Append:

```markdown

## Milestone 6 setup (co-broke request)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0007_cobroke_request.sql` (repo root) -> Run. This creates the `cobroke_request` table and its three RLS policies. No storage bucket, no Auth-dashboard changes.
```

- [ ] **Step 4: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add supabase/migrations/0007_cobroke_request.sql app/README.md
git commit -m "feat: add cobroke_request Supabase migration and setup docs"
```

---

### Task 2: CobrokeRequest + CobrokeRequestCandidate models (TDD)

**Files:**
- Create: `app/lib/features/collaboration/models/cobroke_request.dart`
- Create: `app/lib/features/collaboration/models/cobroke_request_candidate.dart`
- Test: `app/test/features/collaboration/models/cobroke_request_test.dart`

**Interfaces:**
- Consumes: `MatchCandidate` (`../../matching/models/match_candidate.dart`, already exists).
- Produces: `CobrokeRequest` (fields `requestId`, `matchId`, `initiatorId`, `status`, `createdAt`, all `final`) with `CobrokeRequest.fromJson(Map<String, dynamic>)`. `CobrokeRequestCandidate` (fields `request` (`CobrokeRequest`), `match` (`MatchCandidate`)) — a repository-composed view, not built from a single JSON row. Task 3's `CobrokeRequestRepository` and Task 6's `MyRequestsScreen` use both.

TDD for `CobrokeRequest` (pure model, `fromJson`). No TDD for `CobrokeRequestCandidate` (a trivial composed wrapper, same boundary as `MatchCandidate` itself).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/collaboration/models/cobroke_request_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';

void main() {
  group('CobrokeRequest.fromJson', () {
    test('parses a full row', () {
      final request = CobrokeRequest.fromJson({
        'request_id': 'req-1',
        'match_id': 'm-1',
        'initiator_id': 'n-1',
        'status': 'pending',
        'created_at': '2026-08-23T10:00:00.000Z',
      });

      expect(request.requestId, 'req-1');
      expect(request.matchId, 'm-1');
      expect(request.initiatorId, 'n-1');
      expect(request.status, 'pending');
      expect(request.createdAt, DateTime.parse('2026-08-23T10:00:00.000Z'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/collaboration/models/cobroke_request_test.dart
```
Expected: FAIL — `package:renly/features/collaboration/models/cobroke_request.dart` not found.

- [ ] **Step 3: Implement CobrokeRequest**

```dart
// app/lib/features/collaboration/models/cobroke_request.dart

/// A row from the `cobroke_request` table.
class CobrokeRequest {
  final String requestId;
  final String matchId;
  final String initiatorId;
  final String status;
  final DateTime createdAt;

  const CobrokeRequest({
    required this.requestId,
    required this.matchId,
    required this.initiatorId,
    required this.status,
    required this.createdAt,
  });

  factory CobrokeRequest.fromJson(Map<String, dynamic> json) {
    return CobrokeRequest(
      requestId: json['request_id'] as String,
      matchId: json['match_id'] as String,
      initiatorId: json['initiator_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/collaboration/models/cobroke_request_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 5: Implement CobrokeRequestCandidate (no TDD)**

```dart
// app/lib/features/collaboration/models/cobroke_request_candidate.dart
import '../../matching/models/match_candidate.dart';
import 'cobroke_request.dart';

/// A cobroke_request row joined with the MatchCandidate it's for -- reuses
/// the matching feature's view model directly rather than inventing a
/// second representation of "what does this match look like."
class CobrokeRequestCandidate {
  final CobrokeRequest request;
  final MatchCandidate match;

  const CobrokeRequestCandidate({required this.request, required this.match});
}
```

- [ ] **Step 6: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/collaboration/models/cobroke_request.dart lib/features/collaboration/models/cobroke_request_candidate.dart
```
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/collaboration/models/cobroke_request.dart app/lib/features/collaboration/models/cobroke_request_candidate.dart app/test/features/collaboration/models/cobroke_request_test.dart
git commit -m "feat: add CobrokeRequest and CobrokeRequestCandidate models"
```

---

### Task 3: CobrokeRequestRepository (Supabase I/O)

**Files:**
- Create: `app/lib/features/collaboration/cobroke_request_repository.dart`

**Interfaces:**
- Consumes: `ListingRepository` (`../listing/listing_repository.dart`), `Listing`/`ListingOwner` (`../listing/models/`), `Match`/`MatchCandidate` (`../matching/models/`), `Requirement` (`../requirement/models/requirement.dart`), `CobrokeRequest`/`CobrokeRequestCandidate` (Task 2) — all already exist.
- Produces: `CobrokeRequestRepository(SupabaseClient client, ListingRepository listingRepository)` with methods `createRequest`, `acceptRequest`, `declineRequest`, `fetchReceivedRequests`, `fetchSentRequests` — every later task uses these.

No TDD for this task (same documented boundary as every other repository). Verify with `flutter analyze` only.

**Correctness note carried forward from the Matching Engine's final review:** the previous milestone's `MatchingRepository._toCandidates` originally resolved owner lookups sequentially in a loop despite caching Futures, which needed a dedicated fix round to make genuinely concurrent. This task's `_toCandidates` is written correctly the first time: it collects every distinct negotiator id across all rows, resolves them all in one `Future.wait`, then builds candidates synchronously.

- [ ] **Step 1: Implement CobrokeRequestRepository**

```dart
// app/lib/features/collaboration/cobroke_request_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing.dart';
import '../listing/models/listing_owner.dart';
import '../matching/models/match.dart';
import '../matching/models/match_candidate.dart';
import '../requirement/models/requirement.dart';
import 'models/cobroke_request.dart';
import 'models/cobroke_request_candidate.dart';

/// The only file in this app that talks to Supabase for the cobroke_request
/// feature. Composes ListingRepository (for owner lookups) rather than
/// duplicating that query, same reuse precedent as MatchingRepository.
class CobrokeRequestRepository {
  CobrokeRequestRepository(this._client, this._listingRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;

  Future<void> createRequest({required String matchId, required String initiatorId}) async {
    await _client.from('cobroke_request').insert({
      'match_id': matchId,
      'initiator_id': initiatorId,
    });
  }

  Future<void> acceptRequest(String requestId) {
    return _client.from('cobroke_request').update({'status': 'accepted'}).eq('request_id', requestId);
  }

  Future<void> declineRequest(String requestId) {
    return _client.from('cobroke_request').update({'status': 'declined'}).eq('request_id', requestId);
  }

  Future<List<CobrokeRequestCandidate>> fetchReceivedRequests(String negotiatorId) async {
    final rows = await _client
        .from('cobroke_request')
        .select('*, match!inner(*, listing!inner(*), requirement!inner(*))')
        .neq('initiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<CobrokeRequestCandidate>> fetchSentRequests(String negotiatorId) async {
    final rows = await _client
        .from('cobroke_request')
        .select('*, match!inner(*, listing!inner(*), requirement!inner(*))')
        .eq('initiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<CobrokeRequestCandidate>> _toCandidates(List rows) async {
    final ownerIds = <String>{};
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final matchJson = map['match'] as Map<String, dynamic>;
      final listingJson = matchJson['listing'] as Map<String, dynamic>;
      final requirementJson = matchJson['requirement'] as Map<String, dynamic>;
      ownerIds.add(listingJson['negotiator_id'] as String);
      ownerIds.add(requirementJson['negotiator_id'] as String);
    }

    final ownersById = Map<String, ListingOwner>.fromIterables(
      ownerIds,
      await Future.wait(ownerIds.map(_listingRepository.fetchListingOwner)),
    );

    final candidates = <CobrokeRequestCandidate>[];
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final request = CobrokeRequest.fromJson(map);
      final matchJson = map['match'] as Map<String, dynamic>;
      final match = Match.fromJson(matchJson);
      final listing = Listing.fromJson(matchJson['listing'] as Map<String, dynamic>);
      final requirement = Requirement.fromJson(matchJson['requirement'] as Map<String, dynamic>);
      candidates.add(CobrokeRequestCandidate(
        request: request,
        match: MatchCandidate(
          matchId: match.matchId,
          score: match.score,
          listing: listing,
          requirement: requirement,
          listingOwner: ownersById[listing.negotiatorId]!,
          requirementOwner: ownersById[requirement.negotiatorId]!,
        ),
      ));
    }
    return candidates;
  }
}
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/collaboration/cobroke_request_repository.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/collaboration/cobroke_request_repository.dart
git commit -m "feat: add CobrokeRequestRepository"
```

---

### Task 4: cobroke_request_providers.dart

**Files:**
- Create: `app/lib/features/collaboration/cobroke_request_providers.dart`

**Interfaces:**
- Consumes: `CobrokeRequestRepository` (Task 3), `listingRepositoryProvider` (`../listing/listing_providers.dart`), `authStateProvider` (`../auth/auth_providers.dart`) — all already exist.
- Produces: `cobrokeRequestRepositoryProvider` (`Provider<CobrokeRequestRepository>`), `currentNegotiatorIdProvider` (`Provider<String?>`), `receivedRequestsProvider` (`FutureProvider<List<CobrokeRequestCandidate>>`), `sentRequestsProvider` (`FutureProvider<List<CobrokeRequestCandidate>>`) — every later task uses these.

No TDD for this task (Riverpod wiring, same boundary as every other `*_providers.dart` file). Verify with `flutter analyze`.

- [ ] **Step 1: Implement cobroke_request_providers.dart**

```dart
// app/lib/features/collaboration/cobroke_request_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import 'cobroke_request_repository.dart';
import 'models/cobroke_request_candidate.dart';

final cobrokeRequestRepositoryProvider = Provider<CobrokeRequestRepository>((ref) {
  return CobrokeRequestRepository(Supabase.instance.client, ref.watch(listingRepositoryProvider));
});

/// Same session-state read as the copies in listing_providers.dart,
/// requirement_providers.dart, and matching_providers.dart -- duplicated
/// here rather than imported from a sibling feature, same established
/// reasoning (see this plan's Global Constraints).
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// Requests where the current negotiator is NOT the initiator -- these are
/// the ones they can act on (accept/decline).
final receivedRequestsProvider = FutureProvider<List<CobrokeRequestCandidate>>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) return Future.value(const []);
  return ref.watch(cobrokeRequestRepositoryProvider).fetchReceivedRequests(negotiatorId);
});

/// Requests the current negotiator initiated -- read-only status view.
final sentRequestsProvider = FutureProvider<List<CobrokeRequestCandidate>>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) return Future.value(const []);
  return ref.watch(cobrokeRequestRepositoryProvider).fetchSentRequests(negotiatorId);
});
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/collaboration/cobroke_request_providers.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/collaboration/cobroke_request_providers.dart
git commit -m "feat: add cobroke_request Riverpod providers"
```

---

### Task 5: "Request Co-Broke" action, added to the three existing match-list screens

**Files:**
- Create: `app/lib/features/collaboration/send_cobroke_request_action.dart`
- Modify: `app/lib/features/matching/matches_for_listing_screen.dart`
- Modify: `app/lib/features/matching/matches_for_requirement_screen.dart`
- Modify: `app/lib/features/matching/my_matches_screen.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `cobrokeRequestRepositoryProvider`, `sentRequestsProvider` (Task 4).
- Produces: `sendCobrokeRequest(BuildContext context, WidgetRef ref, String matchId)` — a shared top-level function, not a widget. Each of the three match-list screens calls it from a new button on every row.

This is a regression-risk task, same class as the Matching Engine's compute-on-create hook — it edits three already-shipped, already-tested screens. Written as one shared function (not copy-pasted three times) so the accept/error-handling logic exists in exactly one place.

- [ ] **Step 1: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "cobroke_request_send": "Request Co-Broke",
  "cobroke_request_sent": "Request sent"
```

`app/assets/translations/ms.json` additions:
```json
  "cobroke_request_send": "Minta Co-Broke",
  "cobroke_request_sent": "Permintaan dihantar"
```

- [ ] **Step 2: Implement the shared action function**

```dart
// app/lib/features/collaboration/send_cobroke_request_action.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cobroke_request_providers.dart';

/// Shared "Request Co-Broke" action for the three match-list screens
/// (MatchesForListingScreen, MatchesForRequirementScreen, MyMatchesScreen)
/// -- each match row already has exactly one matchId, so this needs no
/// context about which side of the match the viewer is on.
Future<void> sendCobrokeRequest(BuildContext context, WidgetRef ref, String matchId) async {
  final negotiatorId = ref.read(currentNegotiatorIdProvider);
  if (negotiatorId == null) return;

  try {
    await ref.read(cobrokeRequestRepositoryProvider).createRequest(
          matchId: matchId,
          initiatorId: negotiatorId,
        );
    ref.invalidate(sentRequestsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cobroke_request_sent'.tr())),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('listing_error_generic'.tr())),
      );
    }
  }
}
```

- [ ] **Step 3: Edit MatchesForListingScreen**

Read the current `app/lib/features/matching/matches_for_listing_screen.dart` first. Add the import alongside the existing ones:

```dart
import '../collaboration/send_cobroke_request_action.dart';
```

Find this exact block (the end of each card's content):

```dart
                        Text(
                          '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

Replace it with:

```dart
                        Text(
                          '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          child: Text('cobroke_request_send'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

- [ ] **Step 4: Edit MatchesForRequirementScreen**

Read the current `app/lib/features/matching/matches_for_requirement_screen.dart` first. Add the import alongside the existing ones:

```dart
import '../collaboration/send_cobroke_request_action.dart';
```

Find this exact block:

```dart
                        Text(
                          '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

Replace it with:

```dart
                        Text(
                          '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          child: Text('cobroke_request_send'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

- [ ] **Step 5: Edit MyMatchesScreen**

Read the current `app/lib/features/matching/my_matches_screen.dart` first. Add the import alongside the existing ones:

```dart
import '../collaboration/send_cobroke_request_action.dart';
```

Find this exact block (the end of the `isMyListing ? [...] : [...]` conditional content, still inside the outer `Column`'s `children`):

```dart
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
```

Replace it with:

```dart
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
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          child: Text('cobroke_request_send'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

- [ ] **Step 6: Run all three screens' full existing test suites to confirm zero regression**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/matching/matches_for_listing_screen_test.dart test/features/matching/matches_for_requirement_screen_test.dart test/features/matching/my_matches_screen_test.dart
```
Expected: same pass counts as before this task (3 + 3 + 3 = 9). None of the existing assertions reference the new button's text, and the existing tap targets (`'90/100'`, `'80/100'`) remain valid distinct widgets from the new `ElevatedButton` below them — adding a sibling widget to a `Column` does not change any existing widget's identity or position in the tree in a way that would break a `find.text(...)` lookup.

- [ ] **Step 7: Verify static analysis is clean**

```bash
flutter analyze lib/features/collaboration/send_cobroke_request_action.dart lib/features/matching/matches_for_listing_screen.dart lib/features/matching/matches_for_requirement_screen.dart lib/features/matching/my_matches_screen.dart
```
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/collaboration/send_cobroke_request_action.dart app/lib/features/matching/matches_for_listing_screen.dart app/lib/features/matching/matches_for_requirement_screen.dart app/lib/features/matching/my_matches_screen.dart app/assets/translations/
git commit -m "feat: add Request Co-Broke action to the three match-list screens"
```

---

### Task 6: MyRequestsScreen

**Files:**
- Create: `app/lib/features/collaboration/my_requests_screen.dart`
- Test: `app/test/features/collaboration/my_requests_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `receivedRequestsProvider`, `sentRequestsProvider`, `cobrokeRequestRepositoryProvider`, `currentNegotiatorIdProvider` (Task 4), `CobrokeRequestCandidate` (Task 2).
- Produces: `MyRequestsScreen` — Task 7's router uses it as `/my-requests`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/collaboration/my_requests_screen_test.dart
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
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/collaboration/my_requests_screen.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
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

const _owner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

const _matchCandidate = MatchCandidate(
  matchId: 'm-1',
  score: 90,
  listing: _myListing,
  requirement: _theirRequirement,
  listingOwner: _owner,
  requirementOwner: _owner,
);

final _fixtureReceived = [
  CobrokeRequestCandidate(
    request: CobrokeRequest(
      requestId: 'req-1',
      matchId: 'm-1',
      initiatorId: 'n-2',
      status: 'pending',
      createdAt: DateTime(2026, 8, 23),
    ),
    match: _matchCandidate,
  ),
];

Widget _wrap(GoRouter router, {List<CobrokeRequestCandidate>? received, List<CobrokeRequestCandidate>? sent}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      receivedRequestsProvider.overrideWith((ref) async => received ?? _fixtureReceived),
      sentRequestsProvider.overrideWith((ref) async => sent ?? const []),
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

  testWidgets('Received tab shows a pending request with Accept/Decline', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Aiman Yusof (REN: 12345)'), findsOneWidget);
    expect(find.text('90/100'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('switching to Sent tab hides Accept/Decline and shows status only', (tester) async {
    final sent = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-2',
          matchId: 'm-2',
          initiatorId: 'n-1',
          status: 'declined',
          createdAt: DateTime(2026, 8, 23),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: [], sent: sent));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();

    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('renders empty state on Received tab when no requests', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: [], sent: []));
    await tester.pumpAndSettle();

    expect(find.text('No requests yet'), findsOneWidget);
  });
}
```

`CobrokeRequestCandidate`/`CobrokeRequest`/`MatchCandidate` are plain data holders — `createdAt` is never rendered by this screen, it's populated with a fixed `DateTime(2026, 8, 23)` in the fixtures above purely because `CobrokeRequest.createdAt` is `required` and non-nullable (Task 2). Because `DateTime(...)` isn't a `const` constructor, the two fixture literals that use it are plain object literals (no `const` keyword), not `const` ones — do not add `const` back in front of them.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/collaboration/my_requests_screen_test.dart
```
Expected: FAIL — `package:renly/features/collaboration/my_requests_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "cobroke_request_my_requests_title": "My Requests",
  "cobroke_request_tab_received": "Received",
  "cobroke_request_tab_sent": "Sent",
  "cobroke_request_empty": "No requests yet",
  "cobroke_request_accept": "Accept",
  "cobroke_request_decline": "Decline",
  "cobroke_request_status_pending": "Pending",
  "cobroke_request_status_accepted": "Accepted",
  "cobroke_request_status_declined": "Declined"
```

`app/assets/translations/ms.json` additions:
```json
  "cobroke_request_my_requests_title": "Permintaan Saya",
  "cobroke_request_tab_received": "Diterima",
  "cobroke_request_tab_sent": "Dihantar",
  "cobroke_request_empty": "Tiada permintaan lagi",
  "cobroke_request_accept": "Terima",
  "cobroke_request_decline": "Tolak",
  "cobroke_request_status_pending": "Menunggu",
  "cobroke_request_status_accepted": "Diterima",
  "cobroke_request_status_declined": "Ditolak"
```

- [ ] **Step 4: Implement MyRequestsScreen**

```dart
// app/lib/features/collaboration/my_requests_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cobroke_request_providers.dart';
import 'models/cobroke_request_candidate.dart';

/// Both directions of cobroke_request in one screen -- Received (requests
/// where the viewer can act) and Sent (requests the viewer initiated,
/// status-only). Mirrors the segmented-tab shape already established by
/// MyInventoryScreen/MyRequirementsScreen.
class MyRequestsScreen extends ConsumerStatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  ConsumerState<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends ConsumerState<MyRequestsScreen> {
  String _selectedTab = 'received';

  @override
  Widget build(BuildContext context) {
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('cobroke_request_my_requests_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'received', label: Text('cobroke_request_tab_received'.tr())),
                ButtonSegment(value: 'sent', label: Text('cobroke_request_tab_sent'.tr())),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selection) => setState(() => _selectedTab = selection.first),
            ),
          ),
          Expanded(
            child: _selectedTab == 'received'
                ? _RequestList(
                    provider: receivedRequestsProvider,
                    isReceived: true,
                    currentNegotiatorId: currentNegotiatorId,
                  )
                : _RequestList(
                    provider: sentRequestsProvider,
                    isReceived: false,
                    currentNegotiatorId: currentNegotiatorId,
                  ),
          ),
        ],
      ),
    );
  }
}

class _RequestList extends ConsumerWidget {
  const _RequestList({required this.provider, required this.isReceived, required this.currentNegotiatorId});

  final FutureProvider<List<CobrokeRequestCandidate>> provider;
  final bool isReceived;
  final String? currentNegotiatorId;

  String _statusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'cobroke_request_status_accepted'.tr();
      case 'declined':
        return 'cobroke_request_status_declined'.tr();
      default:
        return 'cobroke_request_status_pending'.tr();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(provider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(child: Text('cobroke_request_empty'.tr()));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final candidate = requests[index];
            final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
            final counterpartyOwner = isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${counterpartyOwner.fullName} (REN: ${counterpartyOwner.renNumber})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('${candidate.match.score}/100'),
                    const SizedBox(height: 4),
                    Text(_statusLabel(candidate.request.status)),
                    if (isReceived && candidate.request.status == 'pending') ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              await ref
                                  .read(cobrokeRequestRepositoryProvider)
                                  .acceptRequest(candidate.request.requestId);
                              ref.invalidate(receivedRequestsProvider);
                            },
                            child: Text('cobroke_request_accept'.tr()),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () async {
                              await ref
                                  .read(cobrokeRequestRepositoryProvider)
                                  .declineRequest(candidate.request.requestId);
                              ref.invalidate(receivedRequestsProvider);
                            },
                            child: Text('cobroke_request_decline'.tr()),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/collaboration/my_requests_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/collaboration/my_requests_screen.dart app/test/features/collaboration/my_requests_screen_test.dart app/assets/translations/
git commit -m "feat: add MyRequestsScreen"
```

---

### Task 7: Wire the router and HomePlaceholderScreen navigation

**Files:**
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/lib/features/auth/home_placeholder_screen.dart`
- Test: `app/test/core/router/app_router_test.dart` (add 1 new `test()` case inside the existing `group`, keep the existing 18 untouched)
- Test: `app/test/features/auth/home_placeholder_screen_test.dart` (full replace — keeps the existing 6 tests, adds 1 more)

**Interfaces:**
- Consumes: `MyRequestsScreen` (Task 6).
- Produces: 1 new route (`/my-requests` — distinct from the already-live `/my-requirements` from the Requirement module; the two names are similar at a glance, verify the diff uses the correct one), requiring a session. `HomePlaceholderScreen` gains one more navigation link.

This is the integration task — after this, `flutter test` (full suite) and `flutter analyze` must both be clean.

- [ ] **Step 1: Write the failing computeAuthRedirect test for the new route**

Read the existing `app/test/core/router/app_router_test.dart` first (it has 18 tests). Add 1 new test inside the existing `group('computeAuthRedirect', () { ... })` block:

```dart
    test('unauthenticated user on /my-requests is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-requests'), '/');
    });
```

- [ ] **Step 2: Run test to verify it passes immediately**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/router/app_router_test.dart
```
Expected: `00:0X +19: All tests passed!` — this should already pass since `/my-requests` isn't in `_publicRoutes`. If it unexpectedly fails, `_publicRoutes` has changed since this plan was written; stop and check `app_router.dart` before proceeding.

- [ ] **Step 3: Add the route to app_router.dart**

Read the current `app/lib/core/router/app_router.dart` first. Add this import alongside the existing screen imports:

```dart
import '../../features/collaboration/my_requests_screen.dart';
```

Add this route to the `routes:` list inside `appRouterProvider`:

```dart
      GoRoute(path: '/my-requests', builder: (context, state) => const MyRequestsScreen()),
```

Do not add `/my-requests` to `_publicRoutes`.

- [ ] **Step 4: Add the translation key for the nav link label**

`app/assets/translations/en.json` addition:
```json
  "cobroke_request_my_requests_link": "My Requests"
```

`app/assets/translations/ms.json` addition:
```json
  "cobroke_request_my_requests_link": "Permintaan Saya"
```

- [ ] **Step 5: Write the failing HomePlaceholderScreen navigation test**

Read the existing `app/test/features/auth/home_placeholder_screen_test.dart` first (it has 6 tests from Milestones 3-5). Replace the whole file — keeps the 6 existing tests, adds 1 more for the new link, and adds the new route to every router in the file:

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
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
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
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
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
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
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
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
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
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
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
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('matching_my_matches_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-matches-screen'), findsOneWidget);
  });

  testWidgets('tapping the my requests link navigates to /my-requests', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Text('my-requests-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cobroke_request_my_requests_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-requests-screen'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: FAIL — `HomePlaceholderScreen` doesn't have the new link yet.

- [ ] **Step 7: Update HomePlaceholderScreen**

Read the current `app/lib/features/auth/home_placeholder_screen.dart` first. Add one more button below the existing five:

```dart
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-matches'),
                  child: Text('matching_my_matches_link'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-requests'),
                  child: Text('cobroke_request_my_requests_link'.tr()),
                ),
```

(this replaces the previous last button + closing of the `Column`'s `children` — the new button is appended after the existing "My Matches" button, before the `],` that closes `children`.)

- [ ] **Step 8: Run test to verify it passes**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: `00:0X +7: All tests passed!`

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
git add app/lib/core/router/app_router.dart app/lib/features/auth/home_placeholder_screen.dart app/test/core/router/app_router_test.dart app/test/features/auth/home_placeholder_screen_test.dart app/assets/translations/
git commit -m "feat: wire cobroke_request route and My Requests nav link"
```

---

## Definition of Done

- `flutter test` (run from `app/`) passes with zero failures across the whole suite.
- `flutter analyze` reports no issues.
- `flutter run` on the user's Android emulator shows: every match card (in Matches for Listing/Requirement, and My Matches) has a working "Request Co-Broke" button; `HomePlaceholderScreen`'s "My Requests" link reaches a screen with Received/Sent tabs; a received pending request shows Accept/Decline buttons that work; an accepted/declined request shows a read-only status; the initiator cannot accept/decline their own sent request (no such buttons appear on the Sent tab).
- The SQL migration (`0007_cobroke_request.sql`) has been run in the user's Supabase project (Task 1's manual step) — without this, every cobroke_request read/write fails with Postgrest errors even though all code is correct.
- All 7 tasks committed individually.

## Explicitly not in this plan

Withdrawing/cancelling a pending request as the initiator. Messaging (`message` table, Supabase Realtime) — next sub-milestone. Digital agreements (`agreement` table) — third sub-milestone. Push notification on a new/accepted/declined request. Any unread/pending-count badge.
