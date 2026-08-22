# Messaging Module — Final-Review Fix Report

Branch: `feature/messaging`
Reference for corrected code: `docs/superpowers/plans/2026-08-22-renly-messaging.md` and
`docs/superpowers/specs/2026-08-22-renly-messaging-design.md` (both fixed in commit `57fffe1`).
This report covers applying those same fixes to the shipped Dart/SQL files.

## Finding 1 (Important): Realtime channel leak

**File:** `app/lib/features/collaboration/message_providers.dart:23-35`

`messagesStreamProvider` was declared as `StreamProvider.family<...>`. In the pinned Riverpod
version (2.6.1), `.family` alone does **not** default to `autoDispose` (that's 3.x behavior).
`SupabaseStreamBuilder` only cancels its underlying Realtime channel when the Dart stream
subscription is cancelled, which only happens on provider disposal — so without `.autoDispose`,
every distinct `requestId` chat ever opened would leak a permanently-open Realtime channel for the
rest of the app process.

**Fix:** changed the declaration to
`StreamProvider.autoDispose.family<List<Message>, String>` (line 35), and replaced the doc
comment (lines 23-34) with the accurate explanation from the plan doc — it now explicitly states
the `.autoDispose` is required, not the 2.6.1 default, and explains the leak mechanism and the
fix's effect on popping/reopening `ChatScreen`.

## Finding 2 (Important): timestamptz format mismatch breaks message ordering

**File:** `app/lib/features/collaboration/message_repository.dart:35-54`, method `messagesStream`

The old code chained `.order('sent_at', ascending: true)` on the `SupabaseStreamBuilder`. That
builder sorts the raw `sent_at` **string** when merging rows from the initial PostgREST fetch
(ISO format, `"2026-08-24T10:00:00+00:00"`) with rows from live Realtime INSERT payloads
(space-separated format, `"2026-08-24 10:00:00+00"`). A raw string comparison sorted every
live-delivered message above the entire same-day history instead of below it.

**Fix:** removed `.order('sent_at', ascending: true)` entirely; the `.map()` callback (lines
50-54) now parses rows to `Message` objects and sorts the resulting list by the parsed `sentAt`
`DateTime` via `messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));`. Added the explanatory
comment (lines 36-46) describing the two source formats and why sorting the parsed `DateTime`
sidesteps the mismatch.

## Finding 3 (Important): ChatScreen never scrolls to newest message + 3 related fixes

**File:** `app/lib/features/collaboration/chat_screen.dart`

- **Scroll-to-bottom (lines 61, 72-83):** wrapped `Scaffold`'s `body:` in `SafeArea` (matches
  `PropertyDetailScreen`'s precedent), added `reverse: true` to the `ListView.builder`, and
  changed the item lookup to
  `final reversedIndex = messages.length - 1 - index; final message = messages[reversedIndex];`
  instead of `messages[index]`, with a comment explaining the already-oldest-first ordering from
  `MessageRepository.messagesStream`.
- **Disposed-controller guard (line 42):** `_controller.clear();` → `if (mounted) _controller.clear();`
  in `_send`, matching the existing `if (mounted)` guard around the snackbar call in the same
  method.
- **Sender-name provider leak (line 9):** `FutureProvider.family<ListingOwner, String>` →
  `FutureProvider.autoDispose.family<ListingOwner, String>` for `_senderNameProvider` — same leak
  class as Finding 1, lower impact since it's just a name-lookup cache.

## Finding 4 (Minor): missing index on message table

**File:** `supabase/migrations/0008_messaging.sql:15-19`

Added, between the `create table if not exists message (...)` block and
`alter table message enable row level security;`:

```sql
-- Every .stream() open (and every Realtime re-evaluation of this table's
-- RLS per subscriber) filters on request_id, then orders by sent_at --
-- without this index every chat open is a sequential scan.
create index if not exists message_request_id_sent_at_idx on message(request_id, sent_at);
```

This migration has not been run on the live Supabase project yet, so this was a direct edit to
the migration file rather than a new follow-up migration.

## Finding 5 (Minor): test name overstated coverage

**File:** `app/test/features/collaboration/my_requests_screen_test.dart:160-171`

The test `'accepted request shows a Chat button, pending does not'` previously only asserted the
accepted case. Added, at the start of the test body: a fresh `pendingRouter` (only the `/` route),
pumped via the existing `_wrap(pendingRouter)` (no `received:` override, so it uses the file's
`_fixtureReceived` constant — a `'pending'`-status request), followed by
`expect(find.text('Chat'), findsNothing);` before the pre-existing accepted-case assertions.

**Deviation from the verbatim plan-doc text:** between the two `pumpWidget` calls in this test, I
added `await tester.pumpWidget(const SizedBox.shrink());` (test file line 173) — not present in
the plan doc's Task 6 code block. Without it, the test fails: Flutter's `WidgetTester.pumpWidget`
reuses/updates the existing element tree when the new root widget has matching structure/types
(the same reconciliation as a normal rebuild), rather than fully unmounting and remounting. With
two different `GoRouter`/`ProviderScope` widget trees pumped back-to-back in one test, the second
pump did not fully replace the first — `debugDumpApp()` confirmed `MyRequestsScreen` was still
showing the pending fixture's `Accept`/`Decline` buttons instead of the accepted fixture's `Chat`
button after the second `pumpWidget` + `pumpAndSettle`. Inserting a teardown pump of a trivial
widget (`SizedBox.shrink()`) between the two full-tree pumps forces Flutter to dispose the first
tree before mounting the second, which resolved it. Confirmed via `debugDumpApp` this fully fixed
the staleness, then removed the debug dump call before finalizing.

## Finding 6 (Minor): README missing publication-ownership fallback

**File:** `app/README.md`, "Milestone 7 setup (messaging)" section

Appended the requested sentence to the end of the existing paragraph:
> If that statement ever errors with "must be owner of publication" (a role-permissions edge
> case, not expected on this project), toggle `message` on manually under Database > Replication
> instead.

## Verification

All commands run from `"/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"`.
(`flutter` was not on `PATH` in this shell; resolved via
`/Users/unxpected/Development/flutter/bin`.)

### `flutter test test/features/collaboration/chat_screen_test.dart`

```
00:00 +0: renders messages from the fixed stream
00:00 +1: renders empty state when there are no messages
00:01 +2: send button is present with input hint
00:01 +3: (tearDownAll)
00:01 +3: All tests passed!
```
3/3 passed, unchanged. The `reversedIndex` logic still renders `_fixtureMessages` (already
oldest-first) in the same visual order the tests expect — the tests assert text presence, not
list order, so this was unaffected either way, but manually verified the reversed-index math is
correct.

### `flutter test test/features/collaboration/my_requests_screen_test.dart`

```
00:00 +0: Received tab shows a pending request with Accept/Decline
00:00 +1: switching to Sent tab hides Accept/Decline and shows status only
00:00 +2: renders empty state on Received tab when no requests
00:01 +3: accepted request shows a Chat button, pending does not
00:01 +4: (tearDownAll)
00:01 +4: All tests passed!
```
4/4 passed (unchanged test *count* — the new assertion was added inside the existing 4th test,
not as a new `testWidgets` block, per the task's own note to verify the actual delta rather than
assume +1).

### `flutter test` (full suite)

```
00:12 +136: .../marketplace_screen_test.dart: renders empty state when no listings
00:12 +136: All tests passed!
```
137 tests ran, 137 passed (`+136` is 0-indexed in the runner's counter, i.e. 137 total — baseline
was 136 before this change; the delta is the one new `expect` inside an existing test, not a new
test, consistent with the my_requests_screen_test.dart result above).

### `flutter analyze`

```
Analyzing app...
No issues found! (ran in 12.5s)
```
Clean (some unrelated "newer package version available" notices from `flutter pub get`, no
analyzer issues).

## Summary of deviations

1. Added an extra `tester.pumpWidget(const SizedBox.shrink())` teardown step in
   `my_requests_screen_test.dart`'s Finding-5 test, not present in the plan doc's verbatim code —
   required to make the two-router two-pump test pattern actually exercise fresh Riverpod/GoRouter
   state instead of a stale reused element tree. See Finding 5 above for the full explanation.
2. No other deviations — all other fixes match the plan doc's corrected code/comments verbatim.
