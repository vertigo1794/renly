# Main Navigation Shell + Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `HomePlaceholderScreen` with a real Main Dashboard, add the app's first persistent bottom navigation bar (Home/Market/Chat/Profile + a Post action button), build a Conversation List screen with message read-tracking, and build an in-app Notification Center — per `docs/superpowers/specs/2026-09-05-renly-main-nav-dashboard-design.md`.

**Architecture:** `go_router`'s `StatefulShellRoute.indexedStack` wraps 4 branches (each keeping its own `Navigator`/back-stack and `AppBar`); a new Supabase migration adds `message.read_at` + a `notification` table; the existing `send-push-notification` Edge Function gains a notification-row insert using its existing service-role client.

**Tech Stack:** Flutter + Riverpod + go_router 14.6.2 + Supabase (Postgres/RLS/Edge Functions) + easy_localization + phosphor_flutter 2.1.0.

## Global Constraints

- `AppColors.primary` (`#D2FF00`) is NOT changed. `primaryContainer`/`onPrimaryContainer`/`secondary`/`error` already match the Stitch dashboard palette and are also left untouched.
- All new/changed icons use `PhosphorIcons.x(PhosphorIconsStyle.bold)`, never `Icons.*` — **except** the 4 new rows added inside `ProfileScreen`'s existing settings-list `Column` (Task 9), which must match that exact list's own established `Icons.*` (Material) convention for visual consistency within that one list, not introduce a mixed icon set in a single section.
- No `security definer` SQL function/view anywhere in the new migration — `conversation_last_message` is a view with `security_invoker = true`, so Postgres evaluates the underlying `message` table's RLS as the querying user (required on Postgres 15+; without it a view runs RLS as the view owner and silently bypasses `message_select`).
- No `insert` RLS policy or grant on the new `notification` table for the `authenticated` role — rows are written only by `send-push-notification`'s existing service-role client.
- `flutter analyze` and the full `flutter test` suite must stay clean after every task.
- No golden-image tests.
- The migration is never auto-applied by any task — it is written to `supabase/migrations/` only; the user applies it manually via the Supabase SQL Editor. Task 1's own last step is the exact `information_schema` verification query to run afterward.
- Supabase-boundary calls (repository methods hitting Postgres, the Edge Function) are not unit-tested — verified manually, per this project's established convention. Pure logic functions get real unit tests. Widget tests use provider overrides + `flutter_test`, following the exact pattern in `app/test/features/collaboration/my_requests_screen_test.dart`.

---

### Task 1: Migration — `message.read_at` + `conversation_last_message` view + `notification` table

**Files:**
- Create: `supabase/migrations/0018_conversation_read_tracking.sql`

**Interfaces:**
- Produces: `message.read_at` (nullable timestamptz column), `message_update_read_at` RLS policy, `conversation_last_message` view (columns `request_id, sender_id, body, sent_at, read_at`), `notification` table (columns `notification_id, recipient_id, category, title, body, deep_link_data, read_at, created_at`) with `notification_select_own`/`notification_update_read_at` RLS policies. Task 2, Task 3, Task 5, and Task 6 all depend on this schema existing once applied.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0018_conversation_read_tracking.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0017.
--
-- Adds message read-tracking (Chat tab / Conversation List unread
-- indicator) and a new `notification` table (in-app Notification Center) --
-- both deferred from their originating designs (Messaging's 0008, and the
-- Push Notifications design's explicit "no inbox screen" scope line) until
-- this milestone needed them for real.

alter table message add column if not exists read_at timestamptz;

-- Only the RECIPIENT of a message (never the sender) may mark it read --
-- mirrors message_select/message_insert's exact accepted-request-party
-- check from 0008_messaging.sql, plus excluding the sender.
drop policy if exists message_update_read_at on message;
create policy message_update_read_at on message for update
  to authenticated using (
    sender_id != auth.uid()
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
  )
  with check (sender_id != auth.uid());

-- 0008_messaging.sql never revoked the default blanket UPDATE grant that
-- Supabase issues to `authenticated` on new tables (it only did a
-- revoke-then-regrant for INSERT). That dormant grant has covered every
-- column of `message` since 0008; 0018 is the first migration to add an
-- UPDATE RLS policy for `message`, which makes it live. A REVOKE-then-
-- column-grant is required here, unlike a case where no such dormant
-- blanket grant exists, otherwise any accepted-request recipient could
-- UPDATE `body`/`sent_at`, not just `read_at`.
revoke update on message from authenticated;
grant update (read_at) on message to authenticated;

-- Latest message per conversation. security_invoker = true is REQUIRED,
-- not optional decoration: since Postgres 15, a view without it runs RLS
-- as the VIEW OWNER, not the querying session (FORCE ROW LEVEL SECURITY
-- is not set anywhere in this schema, so ownership alone skips RLS) --
-- meaning every authenticated user would see the latest message of EVERY
-- conversation in the system, bypassing message_select's accepted-
-- request-party check entirely. With security_invoker = true, Postgres
-- evaluates the underlying `message` table's OWN RLS using the QUERYING
-- user's permissions instead, so this grants no new privilege beyond
-- what message_select already allows and cannot repeat this project's
-- prior security-definer RLS incidents (Co-Broke Request, Profile,
-- Ratings/Reviews).
create or replace view conversation_last_message with (security_invoker = true) as
select distinct on (request_id) request_id, sender_id, body, sent_at, read_at
from message
order by request_id, sent_at desc;

create table if not exists notification (
  notification_id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references negotiator(negotiator_id) on delete cascade,
  category text not null check (category in ('match', 'message', 'cobroke_request')),
  title text not null,
  body text not null,
  deep_link_data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notification_recipient_id_created_at_idx
  on notification(recipient_id, created_at desc);

alter table notification enable row level security;

drop policy if exists notification_select_own on notification;
create policy notification_select_own on notification for select
  to authenticated using (recipient_id = auth.uid());

drop policy if exists notification_update_read_at on notification;
create policy notification_update_read_at on notification for update
  to authenticated using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

-- Same dormant-blanket-grant gap as `message` above: `notification` is a
-- net-new table in this migration, so it still carries Supabase's default
-- table-wide UPDATE grant to `authenticated` until explicitly revoked.
-- WITH CHECK already pins recipient_id = auth.uid(), so without the
-- revoke a user could only rewrite their OWN notification rows -- but
-- could still rewrite title/body/category/deep_link_data via UPDATE, not
-- just read_at, breaking the intended immutability of those columns.
revoke update on notification from authenticated;
grant update (read_at) on notification to authenticated;

-- Deliberately NO insert policy/grant for `authenticated`. recipient_id is
-- caller-supplied, not derivable from auth.uid() the way every other
-- insert policy in this schema pins it -- an insert policy here would let
-- any signed-in user write into any OTHER user's notification feed. Rows
-- are written exclusively by the send-push-notification Edge Function's
-- service-role client, which bypasses RLS entirely (same pattern that
-- function already uses to read fcm_device_token across all recipients).
```

- [ ] **Step 2: Verify the file is syntactically consistent with the existing schema**

Run: `grep -n "table match\|table listing\|table requirement\|table cobroke_request\|table negotiator" "supabase/migrations/0003_listing.sql" "supabase/migrations/0005_requirement.sql" "supabase/migrations/0006_matching.sql" "supabase/migrations/0007_cobroke_request.sql" "supabase/migrations/0001_auth_verification.sql" 2>/dev/null`
Expected: confirms `listing.negotiator_id`, `requirement.negotiator_id`, `match.listing_id`/`match.requirement_id`, `cobroke_request.match_id`/`initiator_id`/`status`, and `negotiator.negotiator_id` are the real column names used above (they were already verified once this session against `0008_messaging.sql` and `0017_get_other_party_in_match.sql` — this step re-confirms against the table-defining migrations themselves before the file is committed).

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0018_conversation_read_tracking.sql
git commit -m "feat: add message read-tracking and notification table migration"
```

- [ ] **Step 4: Record the manual-apply + verification instructions for the user (do not run these yourself — they run the migration, not you)**

After the user pastes Step 1's SQL into the Supabase SQL Editor and runs it, they must run this verification query and confirm it returns exactly these rows before the milestone is considered done (per this project's own established lesson from the Profile milestone's grant-stripping incident — always verify grants landed exactly as written):

```sql
select table_name, column_name, privilege_type
from information_schema.column_privileges
where grantee = 'authenticated'
  and table_name in ('message', 'notification')
  and privilege_type = 'UPDATE'
order by table_name, column_name;
```

Expected exactly 2 rows: `message | read_at | UPDATE` and `notification | read_at | UPDATE`. If `message` shows any OTHER column with `UPDATE` privilege, or `notification` shows an `INSERT` privilege for `authenticated` at all, stop and re-check the migration before proceeding to any other task's manual verification.

---

### Task 2: `Message` model + `MessageRepository` read-tracking additions

**Files:**
- Modify: `app/lib/features/collaboration/models/message.dart`
- Modify: `app/lib/features/collaboration/message_repository.dart`
- Create: `app/lib/features/collaboration/models/conversation_summary.dart`
- Test: `app/test/features/collaboration/message_repository_test.dart` (new — only the pure/non-Supabase pieces are tested; see Step 3)

**Interfaces:**
- Consumes: Task 1's `message.read_at` column and `conversation_last_message` view (schema-only dependency — this task's code can be written and reviewed before the user actually applies the migration, same as every prior migration+repository pairing in this project).
- Produces: `Message.readAt` (`DateTime?`), `ConversationSummary` model (`requestId, senderId, body, sentAt, unreadCount`), `MessageRepository.markConversationRead(String requestId, String currentNegotiatorId)`, `MessageRepository.fetchConversationSummary(String requestId, String currentNegotiatorId) -> Future<ConversationSummary?>`. Task 6 (`ConversationListScreen`) consumes both new repository methods and the new model directly.

- [ ] **Step 1: Add `readAt` to the `Message` model**

```dart
// app/lib/features/collaboration/models/message.dart
/// A row from the `message` table.
class Message {
  final String messageId;
  final String requestId;
  final String senderId;
  final String body;
  final DateTime sentAt;
  final DateTime? readAt;

  const Message({
    required this.messageId,
    required this.requestId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.readAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      messageId: json['message_id'] as String,
      requestId: json['request_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
    );
  }
}
```

- [ ] **Step 2: Create the `ConversationSummary` model**

```dart
// app/lib/features/collaboration/models/conversation_summary.dart
/// One row from the `conversation_last_message` view (the latest message in
/// a single request's conversation) plus a separately-queried unread count.
/// Not a `Message` -- `conversation_last_message`'s DISTINCT ON collapses
/// to one row per request_id with no stable `message_id` of its own (a new
/// incoming message replaces which row wins the DISTINCT ON, so any id
/// here would misleadingly suggest a stable identity that doesn't exist).
class ConversationSummary {
  final String requestId;
  final String senderId;
  final String body;
  final DateTime sentAt;
  final int unreadCount;

  const ConversationSummary({
    required this.requestId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    required this.unreadCount,
  });
}
```

- [ ] **Step 3: Write the failing unit test for the one pure piece — a null-conversation edge case guard is not pure, so this task's only real unit-testable surface is nothing new; skip to Step 4.** (Per this project's established convention, `MessageRepository` methods hit Supabase directly and are manually verified, not unit-tested — there is no pure logic in this task to test. Do not create `message_repository_test.dart`; remove it from the Files list above if a previous draft of this brief mentioned it.)

- [ ] **Step 4: Add the two repository methods**

```dart
// app/lib/features/collaboration/message_repository.dart -- add these two
// methods inside the existing MessageRepository class, after fetchSenderName.

  /// Marks every unread message in this conversation that the CURRENT user
  /// did not send as read. Relies on message_update_read_at's own RLS check
  /// (accepted-request party, not the sender) rather than re-deriving that
  /// check client-side -- an update to a row this policy rejects silently
  /// updates zero rows rather than throwing, which is the correct outcome
  /// here (e.g. calling this before the request is actually accepted yet
  /// should be a harmless no-op, not an error).
  Future<void> markConversationRead(String requestId, String currentNegotiatorId) async {
    await _client
        .from('message')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('request_id', requestId)
        .neq('sender_id', currentNegotiatorId)
        .isFilter('read_at', null);
  }

  /// The latest message for this conversation (via the conversation_last_message
  /// view) plus how many of the OTHER party's messages are still unread by
  /// the current user. Returns null if the conversation has no messages yet
  /// (a freshly-accepted request can have zero messages) -- callers must
  /// handle that as "no preview yet", not an error.
  Future<ConversationSummary?> fetchConversationSummary(String requestId, String currentNegotiatorId) async {
    final lastMessageRow = await _client
        .from('conversation_last_message')
        .select()
        .eq('request_id', requestId)
        .maybeSingle();
    if (lastMessageRow == null) return null;

    final unreadCount = await _client
        .from('message')
        .select('message_id')
        .eq('request_id', requestId)
        .neq('sender_id', currentNegotiatorId)
        .isFilter('read_at', null)
        .count(CountOption.exact);

    return ConversationSummary(
      requestId: lastMessageRow['request_id'] as String,
      senderId: lastMessageRow['sender_id'] as String,
      body: lastMessageRow['body'] as String,
      sentAt: DateTime.parse(lastMessageRow['sent_at'] as String),
      unreadCount: unreadCount.count,
    );
  }
```

Add the import at the top of `message_repository.dart`:

```dart
import 'models/conversation_summary.dart';
```

- [ ] **Step 5: Run `flutter analyze` to confirm the new code compiles against the installed `supabase_flutter` API**

Run: `cd app && flutter analyze`
Expected: `No issues found!` — if `.count(CountOption.exact)` or `.isFilter(...)` are not the exact method names on the installed `supabase_flutter` version, `flutter analyze` will report the real error here; fix to match whatever the installed package actually exposes (check `pubspec.lock`'s `supabase_flutter`/`postgrest` version if the exact method signature differs) before moving on.

- [ ] **Step 6: Run the full test suite to confirm nothing existing broke**

Run: `cd app && flutter test`
Expected: all existing tests still pass (this task adds no new test file, per Step 3's reasoning).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/collaboration/models/message.dart app/lib/features/collaboration/models/conversation_summary.dart app/lib/features/collaboration/message_repository.dart
git commit -m "feat: add message read-tracking to Message model and MessageRepository"
```

---

### Task 3: `send-push-notification` Edge Function — insert a `notification` row

**Files:**
- Modify: `supabase/functions/send-push-notification/index.ts`

**Interfaces:**
- Consumes: Task 1's `notification` table existing (schema-only dependency; this task's code can be written before the migration is actually applied by the user).
- Produces: every call to this function now also writes one row to `notification`, using the same `recipient_negotiator_id, category, title, body, deep_link_data` already validated earlier in the handler.

- [ ] **Step 1: Insert a `notification` row right after the recipient/negotiator lookup succeeds, unconditionally of push preference/device outcome**

Add this block in `supabase/functions/send-push-notification/index.ts` immediately after the `if (!negotiator) { ... }` check (around line 185, right before the `if (negotiator[preferenceColumn] === false)` check) — the in-app Notification Center is a separate channel from push delivery, so it must not skip writing just because the push itself will be skipped (muted preference, or no registered devices):

```typescript
    // In-app Notification Center row -- written regardless of whether the
    // push preference is off or no device tokens exist. The in-app history
    // is a separate channel from push delivery; it should exist as long as
    // the recipient is a real negotiator, independent of whether a device
    // actually received anything.
    const { error: notificationInsertError } = await adminClient.from("notification").insert({
      recipient_id: recipient_negotiator_id,
      category,
      title,
      body,
      deep_link_data: sanitizedDeepLinkData ?? {},
    });
    if (notificationInsertError) {
      // Never block/fail the push send over the in-app history insert --
      // log and continue, same best-effort philosophy this whole function
      // already applies to per-token FCM failures below.
      console.error("send-push-notification: notification insert failed", notificationInsertError);
    }
```

- [ ] **Step 2: Verify the file still type-checks under Deno's own tooling (no local Flutter/Dart toolchain applies to this file)**

Run: `cd supabase/functions/send-push-notification && deno check index.ts`
Expected: no type errors. If `deno` is not installed locally, skip this step and rely on Step 3's manual verification instead — do not block the task on a missing local Deno install.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/send-push-notification/index.ts
git commit -m "feat: write an in-app notification row from send-push-notification"
```

- [ ] **Step 4: Record the manual verification instructions (do not deploy/run this yourself)**

Once the user has applied Task 1's migration AND redeployed this function (`supabase functions deploy send-push-notification`), they should trigger any one of the 3 existing push events (e.g. send a message on an accepted co-broke request) and then run:

```sql
select notification_id, recipient_id, category, title, created_at
from notification
order by created_at desc
limit 5;
```

Expected: a new row matching the just-triggered event, with `category` matching the event type (`message`/`match`/`cobroke_request`).

---

### Task 4: `PropertyCard` widget (extracted from `marketplace_screen.dart`)

**Files:**
- Create: `app/lib/core/widgets/property_card.dart`
- Modify: `app/lib/features/listing/marketplace_screen.dart`
- Test: `app/test/core/widgets/property_card_test.dart`

**Interfaces:**
- Consumes: `Listing` model (`app/lib/features/listing/models/listing.dart`), `ListingPhoto` (`app/lib/features/listing/listing_photo.dart`), `ListingFormatting.formatPrice(double price, String transactionType)` (`app/lib/features/listing/listing_formatting.dart`), `BrutalistCard`, `StatusBadge`.
- Produces: `PropertyCard({required Listing listing, required VoidCallback onTap})` — a `StatelessWidget`. Task 7 (`MainDashboardScreen`) consumes this directly for its Recent Listings carousel.

- [ ] **Step 1: Write the failing widget test**

```dart
// app/test/core/widgets/property_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/property_card.dart';
import 'package:renly/features/listing/models/listing.dart';

const _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'Modern Villa',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: '124 Maple St, Downtown',
  price: 2450000,
  bedrooms: 4,
  bathrooms: 3,
  photoUrls: [],
  status: 'active',
);

void main() {
  testWidgets('renders listing price, area, and bed/bath counts', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PropertyCard(listing: _listing, onTap: () {}),
          ),
        ),
      ),
    );

    expect(find.textContaining('2,450,000'), findsOneWidget);
    expect(find.text('124 Maple St, Downtown'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping the card calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PropertyCard(listing: _listing, onTap: () => tapped = true),
                  ),
        ),
      ),
    );

    await tester.tap(find.byType(PropertyCard));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/core/widgets/property_card_test.dart`
Expected: FAIL — `property_card.dart` does not exist yet (import error).

- [ ] **Step 3: Write `PropertyCard`**

Read `app/lib/features/listing/listing_formatting.dart` first to confirm `formatPrice`'s exact signature before writing this file (it is used here identically to `marketplace_screen.dart`'s existing call).

```dart
// app/lib/core/widgets/property_card.dart
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../features/listing/listing_formatting.dart';
import '../../features/listing/listing_photo.dart';
import '../../features/listing/models/listing.dart';
import '../theme/app_colors.dart';
import 'brutalist_card.dart';
import 'status_badge.dart';

/// A reusable property summary card -- extracted from the inline
/// BrutalistCard+InkWell markup marketplace_screen.dart used to build
/// directly in its ListView.builder, so the Marketplace list and the
/// Dashboard's Recent Listings carousel render identically and never drift.
/// Bed/bathtub icons switched from marketplace_screen.dart's original
/// Icons.bed/Icons.bathtub to PhosphorIcons while extracting -- this app's
/// icon convention everywhere else already uses PhosphorIcons, this file
/// was simply never updated when that convention was established.
class PropertyCard extends StatelessWidget {
  const PropertyCard({required this.listing, required this.onTap, super.key});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: BrutalistCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (listing.photoUrls.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: ListingPhoto(path: listing.photoUrls.first),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (listing.status == 'active') const StatusBadge(label: 'Available'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ListingFormatting.formatPrice(listing.price, listing.transactionType),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (listing.bedrooms != null) ...[
                          Icon(PhosphorIcons.bed(PhosphorIconsStyle.bold), size: 16),
                          const SizedBox(width: 4),
                          Text('${listing.bedrooms}'),
                          const SizedBox(width: 12),
                        ],
                        if (listing.bathrooms != null) ...[
                          Icon(PhosphorIcons.bathtub(PhosphorIconsStyle.bold), size: 16),
                          const SizedBox(width: 4),
                          Text('${listing.bathrooms}'),
                          const SizedBox(width: 12),
                        ],
                        Flexible(
                          child: Text(
                            listing.area,
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/core/widgets/property_card_test.dart`
Expected: PASS (2/2). If the `'Available'` label test fails because `StatusBadge`'s localized label should come from `.tr()` instead of a raw string, fix `PropertyCard` to use `'listing_status_available'.tr()` (check `app/assets/translations/en.json`/`ms.json` first for whether this key already exists from an earlier milestone — reuse it if so, add it to both locale files if not) and update the test's expectation to match whichever localized string that key resolves to in the `en` locale.

- [ ] **Step 5: Update `marketplace_screen.dart` to use `PropertyCard` instead of its inline markup**

Replace the `Material(color: Colors.transparent, child: InkWell(... child: BrutalistCard(...)))` block inside `ListView.builder`'s `itemBuilder` (the entire block currently spanning roughly lines 94-159 of `app/lib/features/listing/marketplace_screen.dart`) with:

```dart
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: PropertyCard(
                          listing: listing,
                          onTap: () => context.push('/property/${listing.listingId}'),
                        ),
                      );
```

Add the import at the top of `marketplace_screen.dart`:

```dart
import '../../core/widgets/property_card.dart';
```

Remove the now-unused `import '../../core/widgets/brutalist_card.dart';` line from `marketplace_screen.dart` if `BrutalistCard` is no longer referenced anywhere else in that file (check with `grep -n "BrutalistCard" app/lib/features/listing/marketplace_screen.dart` first).

- [ ] **Step 6: Check `app/test/features/listing/marketplace_screen_test.dart` for now-stale matchers**

Run: `grep -n "find\." "app/test/features/listing/marketplace_screen_test.dart"`
Expected: identify any assertion that depended on the old inline markup's exact widget tree (e.g. `find.byType(BrutalistCard)` used as a count-of-listings check) — update it to `find.byType(PropertyCard)` if so. If assertions only check for text content (price/title/area), no change is needed.

- [ ] **Step 7: Run the full test suite**

Run: `cd app && flutter test`
Expected: all tests pass, including the updated `marketplace_screen_test.dart`.

- [ ] **Step 8: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add app/lib/core/widgets/property_card.dart app/test/core/widgets/property_card_test.dart app/lib/features/listing/marketplace_screen.dart app/test/features/listing/marketplace_screen_test.dart
git commit -m "feat: extract PropertyCard widget from marketplace_screen's inline markup"
```

---

### Task 5: Notification Center — repository, providers, list screen, route

**Files:**
- Create: `app/lib/features/notifications/models/app_notification.dart`
- Create: `app/lib/features/notifications/notification_repository.dart`
- Modify: `app/lib/features/notifications/notification_providers.dart`
- Create: `app/lib/features/notifications/notification_list_screen.dart`
- Modify: `app/lib/core/router/app_router.dart` (add the `/notifications` route only — the shell wiring itself is Task 8)
- Test: `app/test/features/notifications/notification_list_screen_test.dart`

**Interfaces:**
- Consumes: Task 1's `notification` table existing (schema dependency only). `deepLinkRouteFor(String category, Map<String, String> data)` from `app/lib/features/notifications/deep_link.dart` (existing, unmodified). `BrutalistCard` (existing).
- Produces: `AppNotification` model, `notificationRepositoryProvider`, `notificationsProvider` (`FutureProvider.autoDispose<List<AppNotification>>`), `unreadNotificationCountProvider` (`Provider<int>`), `NotificationListScreen`, route `/notifications`. Task 7 (`MainDashboardScreen`) consumes `unreadNotificationCountProvider` for the bell badge and pushes `/notifications`.

- [ ] **Step 1: Create the `AppNotification` model**

```dart
// app/lib/features/notifications/models/app_notification.dart
/// A row from the `notification` table.
class AppNotification {
  final String notificationId;
  final String category;
  final String title;
  final String body;
  final Map<String, String> deepLinkData;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.notificationId,
    required this.category,
    required this.title,
    required this.body,
    required this.deepLinkData,
    required this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawDeepLinkData = json['deep_link_data'] as Map<String, dynamic>? ?? const {};
    return AppNotification(
      notificationId: json['notification_id'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      deepLinkData: rawDeepLinkData.map((key, value) => MapEntry(key, value.toString())),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 2: Write `NotificationRepository`**

```dart
// app/lib/features/notifications/notification_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/app_notification.dart';

/// The only file in this app that talks to Supabase for the in-app
/// Notification Center. Rows are written exclusively by the
/// send-push-notification Edge Function's service-role client -- this
/// repository only ever reads and marks-read, matching the `notification`
/// table's RLS (select + update(read_at) only, no insert for authenticated).
class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> fetchNotifications(String recipientId) async {
    final rows = await _client
        .from('notification')
        .select()
        .eq('recipient_id', recipientId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List).map((row) => AppNotification.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<void> markRead(String notificationId) async {
    await _client
        .from('notification')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('notification_id', notificationId);
  }
}
```

- [ ] **Step 3: Add the two new providers to `notification_providers.dart`**

```dart
// app/lib/features/notifications/notification_providers.dart -- add these
// imports and providers alongside the existing ones.
import '../auth/auth_providers.dart';
import 'models/app_notification.dart';
import 'notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(Supabase.instance.client);
});

/// Same session-state read duplicated across every feature's own
/// providers file in this project (see the identical copies in
/// listing_providers.dart / cobroke_request_providers.dart) -- established
/// convention, not an oversight.
final _currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// autoDispose + refetch-on-entry -- there is no push-driven client-side
/// cache invalidation to hook into, same reasoning as
/// receivedRequestsProvider/sentRequestsProvider in cobroke_request_providers.dart.
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) {
  final recipientId = ref.watch(_currentNegotiatorIdProvider);
  if (recipientId == null) return Future.value(const []);
  return ref.watch(notificationRepositoryProvider).fetchNotifications(recipientId);
});

/// Derives from notificationsProvider's already-fetched list rather than a
/// second query -- the list is capped to 50 recent rows, small enough that
/// a client-side count is simpler than a dedicated count query.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notificationsAsync = ref.watch(notificationsProvider);
  return notificationsAsync.valueOrNull?.where((n) => n.readAt == null).length ?? 0;
});
```

- [ ] **Step 4: Write the failing widget test for `NotificationListScreen`**

```dart
// app/test/features/notifications/notification_list_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/notifications/models/app_notification.dart';
import 'package:renly/features/notifications/notification_list_screen.dart';
import 'package:renly/features/notifications/notification_providers.dart';

final _unread = AppNotification(
  notificationId: 'n-1',
  category: 'message',
  title: 'New message',
  body: 'You have a new message',
  deepLinkData: const {'request_id': 'req-1'},
  readAt: null,
  createdAt: DateTime(2026, 9, 5, 10, 0),
);

final _read = AppNotification(
  notificationId: 'n-2',
  category: 'cobroke_request',
  title: 'New request',
  body: 'You have a new co-broke request',
  deepLinkData: const {},
  readAt: DateTime(2026, 9, 5, 9, 0),
  createdAt: DateTime(2026, 9, 5, 9, 0),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('renders notifications and navigates to the deep-linked route on tap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const NotificationListScreen()),
      GoRoute(
        path: '/messages/:requestId',
        builder: (context, state) => Text('chat-${state.pathParameters['requestId']}'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [notificationsProvider.overrideWith((ref) async => [_unread, _read])],
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

    expect(find.text('New message'), findsOneWidget);
    expect(find.text('New request'), findsOneWidget);

    await tester.tap(find.text('New message'));
    await tester.pumpAndSettle();

    expect(find.text('chat-req-1'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `cd app && flutter test test/features/notifications/notification_list_screen_test.dart`
Expected: FAIL — `notification_list_screen.dart` does not exist yet.

- [ ] **Step 6: Write `NotificationListScreen`**

```dart
// app/lib/features/notifications/notification_list_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_card.dart';
import 'deep_link.dart';
import 'models/app_notification.dart';
import 'notification_providers.dart';

class NotificationListScreen extends ConsumerWidget {
  const NotificationListScreen({super.key});

  IconData _iconFor(String category) {
    switch (category) {
      case 'match':
        return PhosphorIcons.handshake(PhosphorIconsStyle.bold);
      case 'cobroke_request':
        return PhosphorIcons.userPlus(PhosphorIconsStyle.bold);
      case 'message':
      default:
        return PhosphorIcons.chatCircle(PhosphorIconsStyle.bold);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('notification_center_title'.tr())),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(child: Text('notification_center_empty'.tr()));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final isUnread = notification.readAt == null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      if (isUnread) {
                        await ref.read(notificationRepositoryProvider).markRead(notification.notificationId);
                        ref.invalidate(notificationsProvider);
                      }
                      if (context.mounted) {
                        context.push(deepLinkRouteFor(notification.category, notification.deepLinkData));
                      }
                    },
                    child: BrutalistCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_iconFor(notification.category)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notification.title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(notification.body),
                              ],
                            ),
                          ),
                        ],
                      ),
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

- [ ] **Step 7: Add the 2 new l10n keys**

Add to `app/assets/translations/en.json`: `"notification_center_title": "Notifications"`, `"notification_center_empty": "No notifications yet."`
Add the matching Malay values to `app/assets/translations/ms.json` (check the file's existing style for whether nearby keys are translated or left in English per this project's established, previously-documented EN/MS quirk — match whatever the immediately surrounding keys do).

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd app && flutter test test/features/notifications/notification_list_screen_test.dart`
Expected: PASS (1/1).

- [ ] **Step 9: Add the `/notifications` route**

In `app/lib/core/router/app_router.dart`, add the import:

```dart
import '../../features/notifications/notification_list_screen.dart';
```

And add this route to the `routes:` list (alongside the other flat top-level routes, e.g. right after the `/reviews` route):

```dart
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationListScreen()),
```

- [ ] **Step 10: Run the full test suite and `flutter analyze`**

Run: `cd app && flutter test && flutter analyze`
Expected: all tests pass, `No issues found!`.

- [ ] **Step 11: Commit**

```bash
git add app/lib/features/notifications/ app/test/features/notifications/ app/assets/translations/en.json app/assets/translations/ms.json app/lib/core/router/app_router.dart
git commit -m "feat: add Notification Center (repository, providers, list screen, route)"
```

---

### Task 6: `ConversationListScreen` (Chat tab content)

**Files:**
- Create: `app/lib/features/collaboration/conversation_list_screen.dart`
- Test: `app/test/features/collaboration/conversation_list_screen_test.dart`

**Interfaces:**
- Consumes: `receivedRequestsProvider`, `sentRequestsProvider` (existing, `cobroke_request_providers.dart`), `CobrokeRequestCandidate`/`CobrokeRequest`/`MatchCandidate` (existing models), Task 2's `MessageRepository.fetchConversationSummary`/`ConversationSummary`, `BrutalistCard` (existing).
- Produces: a pure top-level function `mergeAcceptedConversations(List<CobrokeRequestCandidate> received, List<CobrokeRequestCandidate> sent)` (exported from this file, unit-tested), `ConversationListScreen` widget. Task 8 (shell wiring) consumes `ConversationListScreen` directly as the Chat branch's root.

- [ ] **Step 1: Write the failing unit test for the pure merge function**

```dart
// app/test/features/collaboration/conversation_list_screen_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:renly/features/collaboration/conversation_list_screen.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

const _listing = Listing(
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

const _requirement = Requirement(
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

const _owner = ListingOwner(fullName: 'Owner', renNumber: '12345');

const _match = MatchCandidate(
  matchId: 'm-1',
  score: 90,
  listing: _listing,
  requirement: _requirement,
  listingOwner: _owner,
  requirementOwner: _owner,
);

CobrokeRequestCandidate _candidate(String requestId, String status) {
  return CobrokeRequestCandidate(
    request: CobrokeRequest(
      requestId: requestId,
      matchId: 'm-1',
      initiatorId: 'n-2',
      status: status,
      createdAt: DateTime(2026, 9, 5),
    ),
    match: _match,
  );
}

void main() {
  test('keeps only accepted requests from received+sent, deduplicated by requestId', () {
    final received = [_candidate('req-1', 'accepted'), _candidate('req-2', 'pending')];
    final sent = [_candidate('req-3', 'accepted'), _candidate('req-1', 'accepted')];

    final result = mergeAcceptedConversations(received, sent);

    expect(result.map((c) => c.request.requestId).toSet(), {'req-1', 'req-3'});
  });

  test('returns an empty list when nothing is accepted', () {
    final received = [_candidate('req-1', 'pending')];
    final sent = [_candidate('req-2', 'declined')];

    expect(mergeAcceptedConversations(received, sent), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/features/collaboration/conversation_list_screen_test.dart`
Expected: FAIL — `conversation_list_screen.dart` does not exist yet.

- [ ] **Step 3: Write `ConversationListScreen` (including the pure merge function)**

```dart
// app/lib/features/collaboration/conversation_list_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/brutalist_card.dart';
import 'cobroke_request_providers.dart';
import 'message_repository.dart';
import 'models/cobroke_request_candidate.dart';
import 'models/conversation_summary.dart';

/// Merges received+sent co-broke requests into one accepted-only,
/// deduplicated-by-requestId list -- a conversation only exists once a
/// request is accepted (mirrors message_select/message_insert's own RLS
/// invariant), and a request can only ever appear in exactly ONE of
/// received/sent (whichever side didn't initiate it sees it as "received"),
/// so the dedup here is defensive, not expected to ever trigger in
/// practice -- kept anyway since the two lists are independently fetched
/// and nothing enforces that invariant at the type level.
List<CobrokeRequestCandidate> mergeAcceptedConversations(
  List<CobrokeRequestCandidate> received,
  List<CobrokeRequestCandidate> sent,
) {
  final byRequestId = <String, CobrokeRequestCandidate>{};
  for (final candidate in [...received, ...sent]) {
    if (candidate.request.status == 'accepted') {
      byRequestId[candidate.request.requestId] = candidate;
    }
  }
  return byRequestId.values.toList();
}

class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final sentAsync = ref.watch(sentRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('conversation_list_title'.tr())),
      body: receivedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (received) => sentAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
          data: (sent) {
            final conversations = mergeAcceptedConversations(received, sent);
            if (conversations.isEmpty) {
              return Center(child: Text('conversation_list_empty'.tr()));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final candidate = conversations[index];
                final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
                final counterpartyOwner =
                    isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ConversationRow(
                    requestId: candidate.request.requestId,
                    counterpartyName: counterpartyOwner.fullName,
                    currentNegotiatorId: currentNegotiatorId,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({
    required this.requestId,
    required this.counterpartyName,
    required this.currentNegotiatorId,
  });

  final String requestId;
  final String counterpartyName;
  final String? currentNegotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (currentNegotiatorId == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/messages/$requestId'),
          child: BrutalistCard(
            child: Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      );
    }

    final summaryAsync =
        ref.watch(_conversationSummaryProvider((requestId: requestId, negotiatorId: currentNegotiatorId!)));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/messages/$requestId'),
        child: BrutalistCard(
          child: summaryAsync.when(
            loading: () => Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
            error: (error, stack) => Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
            data: (summary) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        summary?.body ?? 'conversation_no_messages_yet'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                                          ),
                    ],
                  ),
                ),
                if (summary != null && summary.unreadCount > 0)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _conversationSummaryProvider =
    FutureProvider.autoDispose.family<ConversationSummary?, ({String requestId, String negotiatorId})>((ref, args) {
  return ref.watch(messageRepositoryProvider).fetchConversationSummary(args.requestId, args.negotiatorId);
});
```

Note: `messageRepositoryProvider` must already exist in `message_providers.dart` (it does, per this session's own earlier research) — add the import `import 'message_providers.dart';` at the top of `conversation_list_screen.dart` if `messageRepositoryProvider` is not already in scope via one of the other imports.

- [ ] **Step 4: Add the 3 new l10n keys**

Add to `app/assets/translations/en.json`: `"conversation_list_title": "Chat"`, `"conversation_list_empty": "No conversations yet."`, `"conversation_no_messages_yet": "No messages yet"`.
Add the matching Malay values to `app/assets/translations/ms.json`, same convention-matching approach as Task 5 Step 7.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd app && flutter test test/features/collaboration/conversation_list_screen_test.dart`
Expected: PASS (2/2).

- [ ] **Step 6: Run the full test suite and `flutter analyze`**

Run: `cd app && flutter test && flutter analyze`
Expected: all tests pass, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/collaboration/conversation_list_screen.dart app/test/features/collaboration/conversation_list_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add ConversationListScreen with accepted-only merge and unread indicator"
```

---

### Task 7: `MainDashboardScreen`

**Files:**
- Create: `app/lib/features/home/main_dashboard_screen.dart`
- Test: `app/test/features/home/main_dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `myProfileProvider` (existing, `app/lib/features/profile/profile_providers.dart`, for the welcome header's `fullName`), `marketplaceListingsProvider` (existing, `listing_providers.dart`), Task 4's `PropertyCard`, Task 5's `unreadNotificationCountProvider`, `BrutalistButton` (existing, `fullWidth`/`icon` params).
- Produces: `MainDashboardScreen` widget. Task 8 (shell wiring) consumes this directly as the Home branch's root, replacing `HomePlaceholderScreen`.

- [ ] **Step 1: Read `app/lib/features/profile/profile_providers.dart` and `app/lib/features/profile/models/profile.dart` first**

Run: `grep -n "myProfileProvider\|class Profile" app/lib/features/profile/profile_providers.dart app/lib/features/profile/models/profile.dart`
Expected: confirms `myProfileProvider`'s exact type (`FutureProvider<Profile>` or similar) and `Profile.fullName`'s exact field name, before writing Step 3 below — do not assume the signature from `profile_screen.dart`'s usage alone without checking the provider file directly.

- [ ] **Step 2: Write the failing widget test**

```dart
// app/test/features/home/main_dashboard_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/home/main_dashboard_screen.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';

const _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'Modern Villa',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Downtown',
  price: 2450000,
  bedrooms: 4,
  bathrooms: 3,
  photoUrls: [],
  status: 'active',
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('renders welcome header, quick actions, and a listing card', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MainDashboardScreen()),
      GoRoute(path: '/post-listing', builder: (context, state) => const Text('post-listing-screen')),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => const Profile(
                negotiatorId: 'n-1',
                fullName: 'Aiman Yusof',
                verificationStatus: 'approved',
              )),
          marketplaceListingsProvider.overrideWith((ref) async => [_listing]),
          unreadNotificationCountProvider.overrideWith((ref) => 2),
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

    expect(find.textContaining('Aiman Yusof'), findsOneWidget);
    expect(find.text('Modern Villa'), findsOneWidget);

    await tester.tap(find.text('dashboard_quick_action_post_listing'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('post-listing-screen'), findsOneWidget);
  });
}
```

Note: `Profile`'s constructor above is a guess at its likely required fields based on `profile_screen.dart`'s usage (`fullName`, `verificationStatus`, plus `negotiatorId` since `_TrustScoreCard`/`_EditForm` both take a `negotiatorId`) — **adjust this fixture to match `Profile`'s ACTUAL constructor** (read `app/lib/features/profile/models/profile.dart` per Step 1 first; it may require additional fields like `renNumber`/`agencyName`/`territory`/`propertySpecialisation` as nullable — pass `null` for any not relevant to this test).

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd app && flutter test test/features/home/main_dashboard_screen_test.dart`
Expected: FAIL — `main_dashboard_screen.dart` does not exist yet.

- [ ] **Step 4: Write `MainDashboardScreen`**

```dart
// app/lib/features/home/main_dashboard_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/property_card.dart';
import '../listing/listing_providers.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart';

class MainDashboardScreen extends ConsumerWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('app_name'.tr()),
        actions: [
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              profileAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stack) => const SizedBox.shrink(),
                data: (profile) => Text(
                  '${'dashboard_welcome_back'.tr()} ${profile.fullName}.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text('dashboard_subtitle'.tr()),
              const SizedBox(height: 24),
              Text('dashboard_quick_actions_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: BrutalistButton(
                      label: 'dashboard_quick_action_post_listing'.tr(),
                      icon: PhosphorIcons.plusCircle(PhosphorIconsStyle.bold),
                      onPressed: () => context.push('/post-listing'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BrutalistButton(
                      label: 'dashboard_quick_action_market'.tr(),
                      variant: BrutalistButtonVariant.secondary,
                      icon: PhosphorIcons.storefront(PhosphorIconsStyle.bold),
                      onPressed: () => context.go('/marketplace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BrutalistButton(
                label: 'dashboard_quick_action_my_inventory'.tr(),
                variant: BrutalistButtonVariant.secondary,
                icon: PhosphorIcons.listBullets(PhosphorIconsStyle.bold),
                onPressed: () => context.push('/my-inventory'),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('dashboard_recent_listings_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.go('/marketplace'),
                    child: Text('dashboard_view_all'.tr()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: listingsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                  data: (listings) {
                    if (listings.isEmpty) {
                      return Center(child: Text('dashboard_recent_listings_empty'.tr()));
                    }
                    final recent = listings.take(10).toList();
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final listing = recent[index];
                        return SizedBox(
                          width: 260,
                          child: PropertyCard(
                            listing: listing,
                            onTap: () => context.push('/property/${listing.listingId}'),
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
      ),
    );
  }
}
```

- [ ] **Step 5: Add the 8 new l10n keys**

Add to `app/assets/translations/en.json`: `"dashboard_welcome_back": "Welcome back,"`, `"dashboard_subtitle": "Market is moving. Here's your daily briefing."`, `"dashboard_quick_actions_title": "Quick Actions"`, `"dashboard_quick_action_post_listing": "Post Listing"`, `"dashboard_quick_action_market": "Market"`, `"dashboard_quick_action_my_inventory": "My Inventory"`, `"dashboard_recent_listings_title": "Recent Listings"`, `"dashboard_view_all": "View All"`, `"dashboard_recent_listings_empty": "No listings yet."`.
Add the matching Malay values to `app/assets/translations/ms.json`, same convention-matching approach as Task 5 Step 7.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd app && flutter test test/features/home/main_dashboard_screen_test.dart`
Expected: PASS (1/1).

- [ ] **Step 7: Run the full test suite and `flutter analyze`**

Run: `cd app && flutter test && flutter analyze`
Expected: all tests pass, `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/home/main_dashboard_screen.dart app/test/features/home/main_dashboard_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add MainDashboardScreen (welcome header, quick actions, recent listings)"
```

---

### Task 8: `StatefulShellRoute` wiring in `app_router.dart`

**Files:**
- Modify: `app/lib/core/router/app_router.dart`
- Test: `app/test/core/router/main_shell_test.dart`

**Interfaces:**
- Consumes: Task 4's `MainDashboardScreen` does NOT apply here — consumes Task 7's `MainDashboardScreen`, Task 6's `ConversationListScreen`, existing `MarketplaceScreen`/`ProfileScreen`.
- Produces: the `/home` route now resolves through a `StatefulShellRoute` with 4 branches; `HomePlaceholderScreen`'s import/route is removed from this file (the file itself is deleted in Task 10, once nothing else references it).

- [ ] **Step 1: Read the current full `app_router.dart` immediately before editing**

Run: `cat -n app/lib/core/router/app_router.dart`
Expected: confirms the exact current route list and import block one more time right before this task's edit — earlier reads of this file happened in an earlier session pass and must not be trusted blindly for exact line numbers this late in the plan (Tasks 1-7 did not touch this file, but re-reading immediately before editing is cheap insurance against any drift).

- [ ] **Step 2: Write the failing widget test for the shell**

```dart
// app/test/core/router/main_shell_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/home/main_dashboard_screen.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/marketplace_screen.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/profile_providers.dart';

// This test builds a MINIMAL 2-branch shell mirroring app_router.dart's
// real StatefulShellRoute structure (Home + Market only, no Chat/Profile),
// rather than exercising the full appRouterProvider -- appRouterProvider
// depends on a live Supabase.instance.client (auth state stream), which
// this project's established test convention does not stand up in widget
// tests. This confirms the SHELL MECHANISM (tapping a destination switches
// the visible branch, state is preserved) works with go_router 14.6.2's
// real API, independent of Supabase wiring.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('tapping a bottom nav destination switches the visible branch', (tester) async {
    final homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
    final marketNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'market');

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(
            body: navigationShell,
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) => navigationShell.goBranch(index),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Market'),
              ],
            ),
          ),
          branches: [
            StatefulShellBranch(
              navigatorKey: homeNavigatorKey,
              routes: [GoRoute(path: '/home', builder: (context, state) => const MainDashboardScreen())],
            ),
            StatefulShellBranch(
              navigatorKey: marketNavigatorKey,
              routes: [GoRoute(path: '/marketplace', builder: (context, state) => const MarketplaceScreen())],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) => const Stream.empty()),
          marketplaceListingsProvider.overrideWith((ref) async => const []),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
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

    expect(find.byType(MainDashboardScreen), findsOneWidget);
    expect(find.byType(MarketplaceScreen), findsNothing);

    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();

    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(find.byType(MainDashboardScreen), findsNothing);
  });
}
```

Note: `myProfileProvider.overrideWith((ref) => const Stream.empty())` above is almost certainly the WRONG override shape for a `FutureProvider` — **fix this to match `myProfileProvider`'s real provider type** (confirmed in Task 7 Step 1; if it is a plain `FutureProvider<Profile>`, override with `myProfileProvider.overrideWith((ref) async => const Profile(...))` using a minimal valid fixture, matching Task 7 Step 2's own fixture).

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd app && flutter test test/core/router/main_shell_test.dart`
Expected: FAIL initially only if the override shape from Step 2's note wasn't already fixed — once fixed to a valid override, this test should actually PASS immediately since it doesn't depend on any new production code (it builds its own local `GoRouter`, not `appRouterProvider`). This is intentional: Step 2's test validates the SHELL MECHANISM using go_router's real, already-installed API, decoupled from `appRouterProvider`'s Supabase dependency — Step 4 below is where `appRouterProvider` itself actually changes.

- [ ] **Step 4: Wire the real `StatefulShellRoute` into `appRouterProvider`**

In `app/lib/core/router/app_router.dart`, replace this import:

```dart
import '../../features/auth/home_placeholder_screen.dart';
```

with:

```dart
import '../../features/collaboration/conversation_list_screen.dart';
import '../../features/home/main_dashboard_screen.dart';
```

Replace this single line:

```dart
      GoRoute(path: '/home', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const MarketplaceScreen()),
```

and this single line (further down the same `routes:` list):

```dart
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
```

with one `StatefulShellRoute.indexedStack` that replaces all 3 of the above (Home/Market/Profile) plus the new Chat branch, in place of wherever `/home`'s `GoRoute` currently sits in the list:

```dart
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => _MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (context, state) => const MainDashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/marketplace', builder: (context, state) => const MarketplaceScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/chat', builder: (context, state) => const ConversationListScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen())],
          ),
        ],
      ),
```

Remove the now-separate old `/profile` `GoRoute` line entirely (it's folded into the shell above) — do not leave two routes both claiming `/profile`.

- [ ] **Step 5: Add the `_MainShell` widget (the bottom nav bar + Post FAB action button) at the bottom of `app_router.dart`**

```dart
// app/lib/core/router/app_router.dart -- add at the end of the file.
class _MainShell extends StatelessWidget {
  const _MainShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        items: [
          BottomNavigationBarItem(
            icon: Icon(PhosphorIcons.house(PhosphorIconsStyle.bold)),
            label: 'nav_home'.tr(),
          ),
          BottomNavigationBarItem(
            icon: Icon(PhosphorIcons.storefront(PhosphorIconsStyle.bold)),
            label: 'nav_market'.tr(),
          ),
          BottomNavigationBarItem(
            icon: Icon(PhosphorIcons.chatCircle(PhosphorIconsStyle.bold)),
            label: 'nav_chat'.tr(),
          ),
          BottomNavigationBarItem(
            icon: Icon(PhosphorIcons.user(PhosphorIconsStyle.bold)),
            label: 'nav_profile'.tr(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/post-listing'),
        child: Icon(PhosphorIcons.plusCircle(PhosphorIconsStyle.bold)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
```

Add these 2 imports at the top of `app_router.dart`:

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
```

`app_router.dart` currently imports `package:flutter/widgets.dart` (confirmed this session) — change that import to `package:flutter/material.dart` instead, since `Scaffold`/`BottomNavigationBar`/`FloatingActionButton` all require Material, not just Widgets.

- [ ] **Step 6: Add the 4 new l10n keys**

Add to `app/assets/translations/en.json`: `"nav_home": "Home"`, `"nav_market": "Market"`, `"nav_chat": "Chat"`, `"nav_profile": "Profile"`.
Add the matching Malay values to `app/assets/translations/ms.json`, same convention-matching approach as Task 5 Step 7.

- [ ] **Step 7: Run the full test suite**

Run: `cd app && flutter test`
Expected: all tests pass, INCLUDING every existing test that navigates to `/home`, `/marketplace`, or `/profile` via a router fixture of its own (not `appRouterProvider`) — those are unaffected by this change since they build their own local `GoRouter` the same way Task 8's own test does. Any existing test that specifically asserted `find.byType(HomePlaceholderScreen)` will now fail — fix it to expect `MainDashboardScreen` instead (see Task 10 for the systematic cleanup of `HomePlaceholderScreen`'s own test file, but any OTHER test file referencing it must be fixed here, in this task, not deferred).

Run: `grep -rln "HomePlaceholderScreen" app/lib app/test`
Expected: after Step 4's edit, this should show only `app/lib/features/auth/home_placeholder_screen.dart` itself and `app/test/features/auth/home_placeholder_screen_test.dart` — if any OTHER file still references it, fix that reference now.

- [ ] **Step 8: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add app/lib/core/router/app_router.dart app/test/core/router/main_shell_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: wire StatefulShellRoute bottom nav (Home/Market/Chat/Profile) + Post FAB"
```

---

### Task 9: `ProfileScreen` submenu additions

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart` (existing — check first, do not assume its exact current assertions)

**Interfaces:**
- Consumes: existing routes `/requirement-board`, `/my-requirements`, `/my-matches`, `/my-requests` (all unchanged).
- Produces: nothing consumed by later tasks — this is the last screen-content task before cleanup.

- [ ] **Step 1: Read the existing `profile_screen_test.dart` first**

Run: `cat -n app/test/features/profile/profile_screen_test.dart`
Expected: confirms exactly which `ListTile`/text matchers already exist, so Step 3's new rows don't accidentally collide with an existing matcher (e.g. two different `Text` widgets both matching the same string in a `find.text(...)` call would make an existing assertion ambiguous).

- [ ] **Step 2: Add 4 new `ListTile` rows to the existing settings-list `Column`**

In `app/lib/features/profile/profile_screen.dart`, inside the existing `Material(color: Colors.transparent, child: Column(children: [...]))` block (the settings-list section, currently ending with the Subscription `ListTile` around line 122), add these 4 rows immediately after the last existing `ListTile` (the Subscription one) and before the closing `],`:

```dart
                        ListTile(
                          leading: const Icon(Icons.assignment_outlined),
                          title: Text('profile_requirement_board_row_title'.tr()),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/requirement-board'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.list_alt_outlined),
                          title: Text('profile_my_requirements_row_title'.tr()),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/my-requirements'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.handshake_outlined),
                          title: Text('profile_my_matches_row_title'.tr()),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/my-matches'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.inbox_outlined),
                          title: Text('profile_my_requests_row_title'.tr()),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/my-requests'),
                        ),
```

(Matches the existing rows' own `Icons.*` Material-icon convention exactly, per this plan's Global Constraints — this one list is a deliberate exception to the project-wide PhosphorIcons rule, not a violation of it.)

- [ ] **Step 3: Add the 4 new l10n keys**

Add to `app/assets/translations/en.json`: `"profile_requirement_board_row_title": "Requirement Board"`, `"profile_my_requirements_row_title": "My Requirements"`, `"profile_my_matches_row_title": "My Matches"`, `"profile_my_requests_row_title": "My Requests"`.
Add the matching Malay values to `app/assets/translations/ms.json`, same convention-matching approach as Task 5 Step 7.

- [ ] **Step 4: Update `profile_screen_test.dart` if it asserts an exact `ListTile` count**

Based on Step 1's read: if the existing test asserts something like `find.byType(ListTile)` with an exact `findsNWidgets(5)` (the 5 pre-existing rows), update the count to include the 4 new rows. If it only checks for specific existing row titles by text, no change is needed (new rows don't collide with existing assertions).

- [ ] **Step 5: Run the full test suite**

Run: `cd app && flutter test`
Expected: all tests pass, including the updated `profile_screen_test.dart`.

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add Requirement Board/My Requirements/My Matches/My Requests to Profile"
```

---

### Task 10: Delete `HomePlaceholderScreen`

**Files:**
- Delete: `app/lib/features/auth/home_placeholder_screen.dart`
- Delete: `app/test/features/auth/home_placeholder_screen_test.dart`

**Interfaces:**
- Consumes: Task 8's removal of the `/home` route's old builder (this task only proceeds once nothing references the old file at all).

- [ ] **Step 1: Confirm nothing still references `HomePlaceholderScreen`**

Run: `grep -rln "HomePlaceholderScreen\|home_placeholder_screen" app/lib app/test`
Expected: only the 2 files being deleted in this task appear in the result (per Task 8 Step 7's own check, which already confirmed this — this is a final re-check immediately before deletion, since Tasks 8/9 may have run in a different order or a different agent may not have carried that context forward).

- [ ] **Step 2: Delete both files**

```bash
git rm app/lib/features/auth/home_placeholder_screen.dart app/test/features/auth/home_placeholder_screen_test.dart
```

- [ ] **Step 3: Run the full test suite**

Run: `cd app && flutter test`
Expected: all tests pass (the deleted test file's own tests are simply gone, not failing).

- [ ] **Step 4: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git commit -m "chore: delete HomePlaceholderScreen, replaced by MainDashboardScreen"
```

- [ ] **Step 6: Run the graphify incremental update**

Per this project's established standing workflow (see this session's own memory), run `detect_incremental` + AST extraction on every new/changed `.dart` file from this entire plan + `build_merge` + `cluster-only` + manifest save, following the exact pattern used at the end of every prior milestone this session.

---

## Manual verification checklist (after all 10 tasks are code-complete)

These require the live emulator + the user's own Supabase project and are NOT run by any task's automated steps above:

1. Apply Task 1's migration in the Supabase SQL Editor, then run its `information_schema` verification query (Task 1 Step 4) and confirm exactly the 2 expected rows.
2. Redeploy `send-push-notification` (`supabase functions deploy send-push-notification`), trigger any one of the 3 push events, and confirm a new `notification` row appears (Task 3 Step 4's query).
3. On the emulator: sign in, confirm the bottom nav shows Home/Market/Chat/Profile with the Post FAB, and that switching tabs preserves each tab's own scroll position/back-stack (push something inside Market, switch to Home, switch back to Market — the pushed screen should still be there).
4. Confirm the Home tab shows the real signed-in negotiator's name in the welcome header, real Quick Actions navigate correctly (Post Listing/Market/My Inventory), and the Recent Listings carousel shows real marketplace data.
5. Accept a co-broke request between two test accounts, send a message from one side, confirm it appears as an unread dot + last-message preview in the OTHER account's Chat tab, and confirms the dot clears after opening that conversation.
6. Confirm the notification bell's badge appears after a push-worthy event fires, and that tapping a Notification Center row navigates to the correct deep-linked screen and clears its own unread state.
7. Confirm Profile shows the 4 new rows (Requirement Board/My Requirements/My Matches/My Requests) navigating to their existing, unchanged screens.
