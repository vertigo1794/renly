# Messaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let two negotiators with an ACCEPTED co-broke request exchange live text messages over Supabase Realtime, gated at the RLS level on `cobroke_request.status = 'accepted'`.

**Architecture:** A `message` table with RLS joining through `cobroke_request` -> `match` -> `listing`/`requirement` (same ownership-join pattern as every prior milestone). `MessageRepository` composes `ListingRepository` for sender-name lookups, same reuse precedent as `CobrokeRequestRepository`. Live delivery uses supabase_flutter's `.stream()` convenience API (not a hand-rolled `RealtimeChannel`), wrapped in a Riverpod `StreamProvider.autoDispose.family` (the `.autoDispose` is required, not implicit — see Task 4). A "Chat" button on accepted rows in `MyRequestsScreen` is the only entry point.

**Tech Stack:** Flutter, Riverpod, supabase_flutter ^2.8.0 (`.stream()` API), go_router, easy_localization (EN/MS).

## Global Constraints

- RLS gate: both `message_select` and `message_insert` require `cobroke_request.status = 'accepted'` for the underlying request — not just a UI-level check.
- No update/delete policy on `message` — messages are immutable once sent (same as `match`).
- Column-scoped grant: `insert (request_id, sender_id, body)` only — nothing else is ever client-writable.
- `MessageRepository` is untested directly (Supabase-calling code) — established project convention. `Message.fromJson` gets a real unit test. `ChatScreen` gets widget tests via provider override with a static list.
- `currentNegotiatorIdProvider`: add another own copy in `message_providers.dart`, same as every other feature (`listing`, `requirement`, `matching`, `collaboration`'s own `cobroke_request_providers.dart`) — deliberately not hoisted to a shared file, per established precedent.
- Widget tests cannot prove live Realtime delivery. Mandatory manual two-account verification happens AFTER merge, as a human step — it is not a plan task and no subagent should attempt to simulate it.
- l10n: every new user-facing string needs both an `en.json` and `ms.json` entry, same `easy_localization` key-based pattern as `cobroke_request_*` keys.

---

### Task 1: Supabase Migration SQL (0008_messaging.sql)

**Files:**
- Create: `supabase/migrations/0008_messaging.sql`
- Modify: `app/README.md` (append a "Milestone 7 setup (messaging)" section after the Milestone 6 section)

**Interfaces:**
- Consumes: `cobroke_request` table and its `status` column (from `0007_cobroke_request.sql`), `match` table (from `0006_matching.sql`), `listing`/`requirement`/`negotiator` tables (from earlier migrations).
- Produces: `message` table (`message_id`, `request_id`, `sender_id`, `body`, `sent_at`) with RLS, used by Task 3's `MessageRepository`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0008_messaging.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0007.
--
-- Written to be re-runnable from the start, same pattern as
-- 0006_matching.sql / 0007_cobroke_request.sql (create table if not
-- exists, drop policy if exists before each create policy).

create table if not exists message (
  message_id uuid primary key default gen_random_uuid(),
  request_id uuid not null references cobroke_request(request_id) on delete cascade,
  sender_id uuid not null references negotiator(negotiator_id) on delete cascade,
  body text not null check (char_length(trim(body)) > 0),
  sent_at timestamptz not null default now()
);

-- Every .stream() open (and every Realtime re-evaluation of this table's
-- RLS per subscriber) filters on request_id, then orders by sent_at --
-- without this index every chat open is a sequential scan.
create index if not exists message_request_id_sent_at_idx on message(request_id, sent_at);

alter table message enable row level security;

-- Select: viewer must be a party to the underlying cobroke_request (its
-- initiator, or whichever side of the match's listing/requirement they
-- own), AND the request must be status = 'accepted'. This is the RLS-level
-- enforcement of "messaging opens upon acceptance" -- not just a UI gate.
drop policy if exists message_select on message;
create policy message_select on message for select
  to authenticated using (
    exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = message.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

-- Insert: sender must be the current user, and the same accepted-request
-- party check as select.
drop policy if exists message_insert on message;
create policy message_insert on message for insert
  to authenticated with check (
    sender_id = auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = message.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

revoke insert on message from authenticated;
grant insert (request_id, sender_id, body) on message to authenticated;

-- Enable Realtime delivery for this table. Without this, .stream()
-- subscriptions receive the initial row set but never see live inserts.
-- Guarded (unlike a bare ALTER PUBLICATION ... ADD TABLE) so re-running
-- this file after a successful first run doesn't raise "relation "message"
-- is already member of publication" and roll back the whole script --
-- Supabase's SQL editor runs a pasted file as one implicit transaction.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message'
  ) then
    alter publication supabase_realtime add table message;
  end if;
end $$;
```

- [ ] **Step 2: Append README setup section**

Read `app/README.md`, find the "Milestone 6 setup (co-broke request)" section, and append immediately after it:

```markdown
### Milestone 7 setup (messaging)

Run `supabase/migrations/0008_messaging.sql` in the Supabase SQL Editor after 0001-0007. This creates the `message` table, its RLS policies, and enables Realtime delivery for it (`alter publication supabase_realtime add table message;`) — no separate Database > Replication dashboard step is needed, it's included in the migration. If that statement ever errors with "must be owner of publication" (a role-permissions edge case, not expected on this project), toggle `message` on manually under Database > Replication instead.
```

- [ ] **Step 3: Verify with grep**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0008_messaging.sql
grep -c "^create policy" supabase/migrations/0008_messaging.sql
grep -c "alter publication supabase_realtime add table message" supabase/migrations/0008_messaging.sql
```
Expected: `1`, `2`, `1`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0008_messaging.sql app/README.md
git commit -m "feat: add message Supabase migration, enable Realtime, setup docs"
```

---

### Task 2: Message model + unit test

**Files:**
- Create: `app/lib/features/collaboration/models/message.dart`
- Test: `app/test/features/collaboration/models/message_test.dart`

**Interfaces:**
- Consumes: nothing (leaf model).
- Produces: `Message` class with `messageId`, `requestId`, `senderId`, `body`, `sentAt` fields and `Message.fromJson(Map<String, dynamic>)` factory — used by Task 3's `MessageRepository` and Task 5's `ChatScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/collaboration/models/message_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/collaboration/models/message.dart';

void main() {
  group('Message.fromJson', () {
    test('parses a full row', () {
      final message = Message.fromJson({
        'message_id': 'msg-1',
        'request_id': 'req-1',
        'sender_id': 'n-1',
        'body': 'Hi, interested to co-broke.',
        'sent_at': '2026-08-24T10:00:00.000Z',
      });

      expect(message.messageId, 'msg-1');
      expect(message.requestId, 'req-1');
      expect(message.senderId, 'n-1');
      expect(message.body, 'Hi, interested to co-broke.');
      expect(message.sentAt, DateTime.parse('2026-08-24T10:00:00.000Z'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/models/message_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'renly' in 'package:renly/features/collaboration/models/message.dart'` (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/features/collaboration/models/message.dart

/// A row from the `message` table.
class Message {
  final String messageId;
  final String requestId;
  final String senderId;
  final String body;
  final DateTime sentAt;

  const Message({
    required this.messageId,
    required this.requestId,
    required this.senderId,
    required this.body,
    required this.sentAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      messageId: json['message_id'] as String,
      requestId: json['request_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/models/message_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/collaboration/models/message.dart app/test/features/collaboration/models/message_test.dart
git commit -m "feat: add Message model"
```

---

### Task 3: MessageRepository

**Files:**
- Create: `app/lib/features/collaboration/message_repository.dart`

**Interfaces:**
- Consumes: `Message`/`Message.fromJson` (Task 2); `ListingRepository.fetchListingOwner(String negotiatorId) -> Future<ListingOwner>` (`app/lib/features/listing/listing_repository.dart:45`, generic by negotiator id despite the class name); `ListingOwner` (`app/lib/features/listing/models/listing_owner.dart`, fields `fullName`, `renNumber`).
- Produces: `MessageRepository` with `sendMessage({required String requestId, required String senderId, required String body})` and `messagesStream(String requestId) -> Stream<List<Message>>` and `fetchSenderName(String negotiatorId) -> Future<ListingOwner>` — used by Task 4's providers and Task 5's `ChatScreen`.

This repository is NOT unit-tested directly — same established convention as `CobrokeRequestRepository`/`MatchingRepository` (Supabase-calling code). No test file for this task.

- [ ] **Step 1: Write the repository**

```dart
// app/lib/features/collaboration/message_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing_owner.dart';
import 'models/message.dart';

/// The only file in this app that talks to Supabase for the message
/// feature. Composes ListingRepository for sender-name lookups (the
/// get_listing_owner_info RPC is generic by negotiator id, not
/// listing-specific), same reuse precedent as CobrokeRequestRepository.
class MessageRepository {
  MessageRepository(this._client, this._listingRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;

  Future<void> sendMessage({
    required String requestId,
    required String senderId,
    required String body,
  }) async {
    await _client.from('message').insert({
      'request_id': requestId,
      'sender_id': senderId,
      'body': body,
    });
  }

  /// Live-updating stream of every message for this request, respecting
  /// RLS server-side (only accepted-request parties ever receive rows).
  /// Each emission carries the FULL current row set for the filter, not a
  /// delta -- so this single stream covers both the initial history load
  /// and every subsequent live insert, with no separate merge logic.
  Stream<List<Message>> messagesStream(String requestId) {
    // Sort the PARSED DateTime in Dart, not via .order('sent_at') on the
    // stream builder. SupabaseStreamBuilder merges rows from two different
    // sources -- the initial PostgREST fetch and live Realtime INSERT
    // payloads -- and sorts the raw sent_at STRING. Those two sources
    // format timestamptz differently ("2026-08-24T10:00:00+00:00" from
    // PostgREST vs "2026-08-24 10:00:00+00" from a Realtime payload,
    // space- not T-separated), so a raw string comparison sorts every
    // live-delivered message ABOVE the entire same-day history instead of
    // below it. Sorting the parsed DateTime sidesteps the format mismatch
    // entirely (and makes ascending: true unnecessary -- no .order() call
    // at all).
    return _client
        .from('message')
        .stream(primaryKey: ['message_id'])
        .eq('request_id', requestId)
        .map((rows) {
          final messages = rows.map(Message.fromJson).toList();
          messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
          return messages;
        });
  }

  Future<ListingOwner> fetchSenderName(String negotiatorId) {
    return _listingRepository.fetchListingOwner(negotiatorId);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/collaboration/message_repository.dart
git commit -m "feat: add MessageRepository with Realtime stream"
```

---

### Task 4: message_providers.dart

**Files:**
- Create: `app/lib/features/collaboration/message_providers.dart`

**Interfaces:**
- Consumes: `MessageRepository` (Task 3); `authStateProvider` (`app/lib/features/auth/auth_providers.dart`, same as every other feature's own `currentNegotiatorIdProvider` copy); `listingRepositoryProvider` (`app/lib/features/listing/listing_providers.dart`).
- Produces: `messageRepositoryProvider`, `currentNegotiatorIdProvider` (this feature's own copy), `messagesStreamProvider = StreamProvider.autoDispose.family<List<Message>, String>` (the `.autoDispose` is required, not the default — see the code below) — used by Task 5's `ChatScreen`.

- [ ] **Step 1: Write the providers**

```dart
// app/lib/features/collaboration/message_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import 'message_repository.dart';
import 'models/message.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(Supabase.instance.client, ref.watch(listingRepositoryProvider));
});

/// Same session-state read as the copies in listing_providers.dart,
/// requirement_providers.dart, matching_providers.dart, and
/// cobroke_request_providers.dart -- duplicated here rather than imported
/// from a sibling feature, same established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// Live-updating message list for one request. The .autoDispose HERE IS
/// REQUIRED, not the default: in the Riverpod version this project is
/// pinned to (2.6.1), `.family` alone does NOT default to autoDispose --
/// that's a Riverpod 3.x behavior. Without the explicit modifier, popping
/// ChatScreen would NOT cancel the underlying Realtime subscription --
/// SupabaseStreamBuilder only tears down its channel when the Dart
/// subscription is cancelled, which only happens on provider disposal --
/// leaking one open Realtime channel per distinct requestId ever opened
/// for the rest of the app's process lifetime. With .autoDispose, popping
/// ChatScreen cancels the subscription, and reopening the screen
/// establishes a fresh one (whose first emission is the full current
/// history, per messagesStream's own contract).
final messagesStreamProvider = StreamProvider.autoDispose.family<List<Message>, String>((ref, requestId) {
  return ref.watch(messageRepositoryProvider).messagesStream(requestId);
});
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/collaboration/message_providers.dart
git commit -m "feat: add message Riverpod providers"
```

---

### Task 5: ChatScreen + widget tests

**Files:**
- Create: `app/lib/features/collaboration/chat_screen.dart`
- Test: `app/test/features/collaboration/chat_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json` (add new keys, see Step 1)

**Interfaces:**
- Consumes: `messagesStreamProvider`, `currentNegotiatorIdProvider`, `messageRepositoryProvider` (Task 4); `Message` (Task 2); `ListingOwner` (`app/lib/features/listing/models/listing_owner.dart`).
- Produces: `ChatScreen(requestId)` widget — used by Task 6's router wiring.

**Sender-name resolution note:** the CURRENT user's own messages never need a name lookup (just render "You" or the message bubble styled as own). Only OTHER senders' messages need `fetchSenderName`. Since every message in a given chat is from exactly one of the two parties, resolve the counterparty's name ONCE per screen build (not per-message) — collect the distinct `senderId`s that are NOT the current user from the loaded message list, and resolve them concurrently via `Future.wait`, same pattern `CobrokeRequestRepository._toCandidates` and `MatchingRepository` already use for owner lookups. Do this resolution inside the widget via a `FutureBuilder` or a small `FutureProvider.family` keyed by the counterparty's negotiator id — the simplest correct option is a `FutureProvider.family<ListingOwner, String>` wrapping `messageRepositoryProvider.fetchSenderName`, so add that to `message_providers.dart` conceptually — but to keep Task 4 and Task 5 cleanly separated, define it directly in `chat_screen.dart` as shown below (it is only ever consumed by this screen).

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"cobroke_request_my_requests_link": "My Requests"` (last `cobroke_request_*` key) and add immediately after it (keep valid JSON — add a comma after the existing last line before the closing brace, or wherever the file's structure requires; insert these as new top-level keys):

```json
  "message_chat_title": "Chat",
  "message_input_hint": "Type a message...",
  "message_send": "Send",
  "message_empty": "No messages yet. Say hello!",
  "cobroke_request_chat_button": "Chat"
```

In `app/assets/translations/ms.json`, same position, add:

```json
  "message_chat_title": "Sembang",
  "message_input_hint": "Taip mesej...",
  "message_send": "Hantar",
  "message_empty": "Tiada mesej lagi. Cuba mula sembang!",
  "cobroke_request_chat_button": "Sembang"
```

- [ ] **Step 2: Write the widget**

```dart
// app/lib/features/collaboration/chat_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../listing/models/listing_owner.dart';
import 'message_providers.dart';

final _senderNameProvider = FutureProvider.autoDispose.family<ListingOwner, String>((ref, negotiatorId) {
  return ref.watch(messageRepositoryProvider).fetchSenderName(negotiatorId);
});

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String senderId) async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            requestId: widget.requestId,
            senderId: senderId,
            body: body,
          );
      if (mounted) _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
    final messagesAsync = ref.watch(messagesStreamProvider(widget.requestId));

    return Scaffold(
      appBar: AppBar(title: Text('message_chat_title'.tr())),
      body: SafeArea(
        child: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(child: Text('message_empty'.tr()));
                }
                // reverse: true keeps the viewport pinned to the newest
                // message on open and on every new arrival, without a
                // ScrollController. messages is already oldest-first (see
                // MessageRepository.messagesStream), so the itemBuilder
                // reads it back-to-front via reversedIndex.
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final reversedIndex = messages.length - 1 - index;
                    final message = messages[reversedIndex];
                    final isOwn = message.senderId == currentNegotiatorId;
                    return Align(
                      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!isOwn) _SenderLabel(negotiatorId: message.senderId),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isOwn
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(message.body),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (currentNegotiatorId != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(hintText: 'message_input_hint'.tr()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sending ? null : () => _send(currentNegotiatorId),
                    child: Text('message_send'.tr()),
                  ),
                ],
              ),
            ),
        ],
        ),
      ),
    );
  }
}

class _SenderLabel extends ConsumerWidget {
  const _SenderLabel({required this.negotiatorId});

  final String negotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerAsync = ref.watch(_senderNameProvider(negotiatorId));
    return ownerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (owner) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(owner.fullName, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}
```

- [ ] **Step 3: Write the widget test**

```dart
// app/test/features/collaboration/chat_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/collaboration/chat_screen.dart';
import 'package:renly/features/collaboration/message_providers.dart';
import 'package:renly/features/collaboration/models/message.dart';

final _fixtureMessages = [
  Message(
    messageId: 'msg-1',
    requestId: 'req-1',
    senderId: 'n-2',
    body: 'Hi, interested to co-broke.',
    sentAt: DateTime(2026, 8, 24, 10, 0),
  ),
  Message(
    messageId: 'msg-2',
    requestId: 'req-1',
    senderId: 'n-1',
    body: 'Sure, let us discuss.',
    sentAt: DateTime(2026, 8, 24, 10, 1),
  ),
];

Widget _wrap(GoRouter router, {List<Message>? messages}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      messagesStreamProvider('req-1').overrideWith((ref) => Stream.value(messages ?? _fixtureMessages)),
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

  testWidgets('renders messages from the fixed stream', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen(requestId: 'req-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Hi, interested to co-broke.'), findsOneWidget);
    expect(find.text('Sure, let us discuss.'), findsOneWidget);
  });

  testWidgets('renders empty state when there are no messages', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen(requestId: 'req-1')),
    ]);

    await tester.pumpWidget(_wrap(router, messages: []));
    await tester.pumpAndSettle();

    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
  });

  testWidgets('send button is present with input hint', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen(requestId: 'req-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Send'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Type a message...'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/chat_screen_test.dart`
Expected: PASS (3 tests).

Note explicitly in this task's completion report: these tests verify RENDERING against a fixed static stream override, not live Realtime delivery. A widget test cannot open two simulated sessions and prove a message sent by one appears on the other — that verification is a mandatory manual step after this branch merges (see this plan's final section), not something any task or subagent here can satisfy.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/collaboration/chat_screen.dart app/test/features/collaboration/chat_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add ChatScreen with widget tests and l10n keys"
```

---

### Task 6: Wire "Chat" button into MyRequestsScreen + router

**Files:**
- Modify: `app/lib/features/collaboration/my_requests_screen.dart`
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/test/features/collaboration/my_requests_screen_test.dart` (add one test)

**Interfaces:**
- Consumes: `ChatScreen(requestId)` (Task 5); existing `_RequestList`/`CobrokeRequestCandidate` shapes (already in the file, unchanged).
- Produces: nothing new consumed by later tasks — this is the last task.

- [ ] **Step 1: Add the import and route to app_router.dart**

In `app/lib/core/router/app_router.dart`, `chat_screen.dart` sorts alphabetically BEFORE `my_requests_screen.dart`. Insert this import immediately BEFORE the existing `import '../../features/collaboration/my_requests_screen.dart';` line:

```dart
import '../../features/collaboration/chat_screen.dart';
```

Then add this route immediately after the existing `GoRoute(path: '/my-requests', builder: (context, state) => const MyRequestsScreen()),` line (currently the last route in the `routes:` list):

```dart
      GoRoute(
        path: '/messages/:requestId',
        builder: (context, state) => ChatScreen(requestId: state.pathParameters['requestId']!),
      ),
```

- [ ] **Step 2: Add the Chat button to my_requests_screen.dart**

In `app/lib/features/collaboration/my_requests_screen.dart`, add this import at the top with the others:

```dart
import 'package:go_router/go_router.dart';
```

Then in `_RequestList.build`, inside the `Card`'s `Column` `children`, find the closing of the `Text(_statusLabel(candidate.request.status))` line and the `if (isReceived && candidate.request.status == 'pending')` block that follows it. Add a NEW `if` block for the Chat button immediately after the existing pending-action `if` block closes (so it applies to BOTH tabs, gated only on accepted status):

```dart
                      if (candidate.request.status == 'accepted') ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => context.push('/messages/${candidate.request.requestId}'),
                          child: Text('cobroke_request_chat_button'.tr()),
                        ),
                      ],
```

The full `children` list of that `Column` should now read, in order: name `Text`, `SizedBox`, score `Text`, `SizedBox`, status `Text`, the existing `if (isReceived && ... == 'pending')` Accept/Decline block, then this new `if (... == 'accepted')` Chat block.

- [ ] **Step 3: Add a widget test for the Chat button**

In `app/test/features/collaboration/my_requests_screen_test.dart`, add this test inside `main()`, after the existing three tests:

```dart
  testWidgets('accepted request shows a Chat button, pending does not', (tester) async {
    final pendingRouter = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    // _fixtureReceived (the default when `received` is omitted) is a
    // 'pending' request -- confirm no Chat button renders for it before
    // testing the accepted case below.
    await tester.pumpWidget(_wrap(pendingRouter));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsNothing);

    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-3',
          matchId: 'm-3',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
      GoRoute(
        path: '/messages/:requestId',
        builder: (context, state) => Scaffold(body: Text('chat for ${state.pathParameters['requestId']}')),
      ),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.text('chat for req-3'), findsOneWidget);
  });
```

- [ ] **Step 4: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/my_requests_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the full suite to confirm zero regression**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test`
Expected: all tests pass (prior suite count + this plan's new tests: Task 2's 1 + Task 5's 3 + Task 6's 1 = 5 new tests).

- [ ] **Step 6: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/collaboration/my_requests_screen.dart app/lib/core/router/app_router.dart app/test/features/collaboration/my_requests_screen_test.dart
git commit -m "feat: wire Chat button and /messages/:requestId route"
```

---

## After all tasks: mandatory manual verification (not a task, a human step)

This plan's tests prove the schema, RLS logic (by inspection, same as every prior milestone — Supabase-boundary code stays untested by convention), and screen rendering against static fixtures. None of that can prove a live Realtime subscription actually delivers a new message from one session to another. Before this milestone is considered functionally done (after merge, after the migration is run on live Supabase):

1. Run the app on two accounts (two devices, or two browser profiles) that already share an ACCEPTED co-broke request.
2. Open the Chat screen on both.
3. Send a message from account A.
4. Confirm it appears on account B's screen without a manual refresh.

This is the same category of required live check as running each new migration on Supabase has been for every prior milestone — but this one verifies live behavior, not just schema application.
