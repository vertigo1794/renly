# renly — Main Navigation Shell + Dashboard Design

## Goal

Replace `HomePlaceholderScreen` (a bare link-hub with 6 direct buttons, no live data, no personalization) with a real Main Dashboard, and give the app its first persistent bottom navigation bar — every screen currently builds its own bare `Scaffold` with no shared chrome. Sourced from the Stitch mockup "Main Dashboard" (project `13581751397915601898`, screen `322c29cec67e4bc6bbde2f7e0b7c8c20`).

This milestone also picks up two items the mockup's bottom nav exposed as gaps: a "Chat" tab has no backing screen today (only a per-request `/messages/:requestId` reached through My Requests), and the mockup's notification bell has no in-app target (push notifications exist, but the prior Push Notifications design explicitly deferred "a notification history/inbox screen" as out of scope). Both are built out fully in this milestone rather than stubbed, per this session's scope decision.

## Source of truth

Stitch "Main Dashboard" screen: TopAppBar (menu icon, logo+wordmark, notification bell), welcome header, a 3-button "Quick Actions" grid (Post Listing / Market / My Inventory), a "Matches for You" horizontal property-card carousel, and a bottom nav (Home / Market / Post-FAB / Chat / Profile, Home active).

**Visual language decision:** every other Stitch mockup adapted this session (splash, onboarding, registration, verification pending) was rendered through this app's own established neo-brutalist system (`BrutalistButton`/`BrutalistCard`/`AppColors`), not copied as Stitch's raw soft-shadow Material3 look. Same call here — Stitch's structure/copy/layout is the reference, not its literal box-shadow/color styling. `AppColors.primary` (`#D2FF00`) stays as-is; it is **not** overwritten to Stitch's dashboard `#536600`, which would break every existing `BrutalistButton`/`BrutalistCard` elsewhere in the app. All icons use `PhosphorIcons`, never Material Symbols.

## Architecture: bottom navigation shell

`go_router`'s `StatefulShellRoute.indexedStack` replaces the current flat top-level route list for the 4 primary destinations:

- **Home** — new `MainDashboardScreen` (replaces `HomePlaceholderScreen`; the placeholder file/route is deleted, not kept as dead code).
- **Market** — existing `MarketplaceScreen`, re-parented under the shell (route stays `/marketplace`, unchanged for any deep link already pointing at it).
- **Chat** — new `ConversationListScreen` (see below).
- **Profile** — existing `ProfileScreen`, re-parented under the shell (route stays `/profile`).

Each branch keeps its own `Navigator`/back-stack (the whole point of `StatefulShellRoute.indexedStack` over a plain `IndexedStack` — switching tabs and back preserves scroll position and any pushed sub-routes per branch) and its own `AppBar`, matching every existing screen's pattern — there is no shared/global AppBar.

The **Post** button in the middle of the bottom nav is **not** a 5th branch. It is a plain action button (styled as an elevated FAB, per the mockup) that calls `context.push('/post-listing')` against the existing `PostListingScreen` — that screen already has its own multi-step flow and professional-tier gating; giving it a persistent branch/back-stack of its own would be over-engineering for a screen that's a one-shot form, not a browsable destination.

All other existing routes (`/property/:listingId`, `/messages/:requestId`, `/settings/*`, `/my-requests`, `/my-matches`, `/reviews`, `/requirement-board*`, `/my-requirements`, `/post-listing`, `/post-requirement`, `/my-inventory`) stay exactly as they are today: flat `GoRoute`s pushed on top of the shell (the bottom nav disappears once one of these is open, standard shell-route behavior, same as any app with a bottom-tab + detail-push pattern).

## Main Dashboard content

- **Welcome header**: `"Welcome back, {fullName}."` + static subtitle (`"Market is moving. Here's your daily briefing."`). Name comes from the existing profile provider (`ProfileScreen` already reads the current negotiator's `fullName`) — not hardcoded.
- **Quick Actions**: a 3-button row (`Post Listing` / `Market` / `My Inventory`), each a `BrutalistButton` using its existing `icon` + `fullWidth: false` parameters (added in the Urby Restyle Phase 2B pass) rather than a new bento-grid component. Icons: `PhosphorIcons.plusCircle`, `storefront`, `listBullets` (exact bold-style icon names confirmed against the installed `phosphor_flutter` version during implementation, not guessed here).
- **Recent Listings carousel** (renamed from the mockup's "Matches for You" — user chose plain recent-listings over a real Matching-Engine feed, to avoid depending on match-scoring semantics on the dashboard): a horizontal-scroll row of a new `PropertyCard` widget, backed by the existing `marketplaceListingsProvider`, capped to the first ~10 results, most-recent first (provider's existing ordering, not re-derived). A "View All" link switches to the Market tab (`context.go('/marketplace')` — a shell-branch switch, not a push).
- **Notification bell** (AppBar action): shows an unread-count badge dot when `unreadNotificationCountProvider` (below) is non-zero; tapping pushes `/notifications`.

## New `PropertyCard` widget

`lib/core/widgets/property_card.dart` — new, reusable. Extracted from the inline `BrutalistCard`+`InkWell` markup already duplicated in `marketplace_screen.dart` (a refactor of existing code into a shared widget, not a second parallel implementation). Fields: `Listing`, tap callback. Renders: `ListingPhoto` thumbnail, an "Available" `StatusBadge`-style pill, formatted price, address, and a bed/bath/sqft icon row (`PhosphorIcons.bed`/`bathtubbold`... exact Phosphor names confirmed at implementation time). `marketplace_screen.dart` is updated to consume the new widget instead of its inline markup, so the two call sites (Marketplace list, Dashboard carousel) never drift.

## Chat tab: Conversation List + read-tracking

No aggregate "list my conversations" query exists today — `MessageRepository` only has `messagesStream(requestId)`, scoped to one accepted `cobroke_request` at a time, and there is zero read/unread tracking anywhere in the schema.

**Migration `0018_conversation_read_tracking.sql`:**

```sql
alter table message add column read_at timestamptz;

-- Only the RECIPIENT of a message (never the sender) may mark it read, and
-- only column-scoped to read_at -- a plain UPDATE grant is never issued.
create policy message_update_read_at on message
  for update to authenticated
  using (
    sender_id != auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      join listing l on l.listing_id = m.listing_id
      join requirement r on r.requirement_id = m.requirement_id
      where cr.request_id = message.request_id
        and cr.status = 'accepted'
        and (l.negotiator_id = auth.uid() or r.negotiator_id = auth.uid())
    )
  )
  with check (sender_id != auth.uid());

grant update (read_at) on message to authenticated;

-- Latest message per conversation. A PLAIN view (no `security definer`) --
-- Postgres evaluates the underlying `message` table's own RLS using the
-- QUERYING user's permissions, so this is safe by construction and cannot
-- repeat this project's prior security-definer RLS incidents (Co-Broke
-- Request, Profile, Ratings/Reviews all had a Critical fix of that exact
-- shape). No new privilege is granted by this view that `message`'s
-- existing select policy doesn't already allow.
create view conversation_last_message as
select distinct on (request_id) request_id, sender_id, body, sent_at, read_at
from message
order by request_id, sent_at desc;
```

The existing `message_select`/`message_insert` RLS on the base table already scopes every row to accepted-request parties only — the new `message_update_read_at` policy repeats that same scoping (not a copy-paste of the select policy verbatim, since it additionally requires the caller not be the sender) and the view inherits it for free.

**`MessageRepository` gains**: `Future<void> markConversationRead(requestId)` (a single `UPDATE message SET read_at = now() WHERE request_id = :id AND sender_id != auth.uid() AND read_at IS NULL`, relying on the RLS policy above rather than re-deriving the accepted-request check client-side). `ChatScreen` calls this once in `initState`/on-open.

**`ConversationListScreen`** (new, `lib/features/collaboration/conversation_list_screen.dart`): merges `receivedRequestsProvider` + `sentRequestsProvider` (both already exist), filters to `status == 'accepted'` only (a conversation only exists once accepted, matching the existing RLS invariant), and for each resulting `CobrokeRequestCandidate` queries `conversation_last_message` for that `requestId` (a new small repository method, `fetchLastMessage(requestId)`) plus an unread count (`count(*) where sender_id != me and read_at is null`, a second small repository method rather than adding a second view, since a single count query per row is simple and this list is small — a couple dozen conversations at most for a single agent). Row: counterparty name (already available from `match.listingOwner`/`match.requirementOwner`, no extra join needed), last-message preview + relative timestamp, an unread dot, tap → `context.push('/messages/${requestId}')` (existing route, unchanged).

## Notification Center

The prior Push Notifications design explicitly deferred "a notification history/inbox screen" — this is new work, not a reversal of that decision, and reuses its existing pieces rather than inventing a parallel event/category system.

**Migration `0018_conversation_read_tracking.sql`** (same file as above, since both are small additions to the same milestone) **also adds:**

```sql
create table notification (
  notification_id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references negotiator(negotiator_id) on delete cascade,
  category text not null check (category in ('match', 'message', 'cobroke_request')),
  title text not null,
  body text not null,
  deep_link_data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notification_recipient_id_created_at_idx
  on notification(recipient_id, created_at desc);

alter table notification enable row level security;

create policy notification_select_own on notification
  for select to authenticated using (recipient_id = auth.uid());
create policy notification_update_read_at on notification
  for update to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());
grant update (read_at) on notification to authenticated;

-- Deliberately NO insert policy for `authenticated`. A client-side insert
-- policy would let any signed-in user write a row into any OTHER user's
-- notification feed (recipient_id is caller-supplied, not derivable from
-- auth.uid() the way every other insert policy in this schema pins it).
-- Rows are written exclusively by the `send-push-notification` Edge
-- Function using the service-role client, the same "server writes on
-- someone else's behalf" pattern that function already uses to read
-- `fcm_device_token` across all recipients.
```

`category` reuses `PushPayload`'s existing 3-value taxonomy verbatim (`match`/`message`/`cobroke_request`) — no new event types are introduced. `deep_link_data` stores the same map `PushPayload.deepLinkData` already carries, so `deepLinkRouteFor(category, deepLinkData)` (existing pure function in `lib/features/notifications/deep_link.dart`, already used for push-tap handling) resolves a tapped Notification Center row's target route identically to a tapped system push — one resolution function, not two.

**`send-push-notification` Edge Function update**: right after successfully sending (or attempting) the FCM push, insert one `notification` row for the recipient using the function's existing service-role Supabase client (already instantiated for the `fcm_device_token` read) — same title/body/category/deep-link data already being sent to FCM, no new data to compute. This insert happens even if every device token turned out stale (self-cleaned) — the in-app history doesn't depend on a device actually receiving the push.

**`NotificationRepository`** (new, `lib/features/notifications/notification_repository.dart`): `fetchNotifications(recipientId)` (select, order by `created_at desc`, `limit(50)`), `markRead(notificationId)` (update `read_at = now()`). Provider: `notificationsProvider` (`FutureProvider.autoDispose<List<AppNotification>>`, re-fetched on screen entry — same `.autoDispose`-refetch convention `receivedRequestsProvider`/`sentRequestsProvider` already established, since there's no push-driven client-side cache invalidation to hook into either). `unreadNotificationCountProvider` derives from the same list (`.where((n) => n.readAt == null).length`) — no second query.

**`NotificationListScreen`** (new, `lib/features/notifications/notification_list_screen.dart`): `BrutalistCard` rows (category icon, title, body, relative time, unread rows visually bolder), tap → `markRead(id)` then `context.push(deepLinkRouteFor(category, deepLinkData))`.

## Profile submenu additions

`ProfileScreen` gains 4 new list items, in the same settings-list style the Settings sub-pages already use: **Requirement Board**, **My Requirements**, **My Matches**, **My Requests** — each navigating to its existing, unchanged route (`/requirement-board`, `/my-requirements`, `/my-matches`, `/my-requests`). `HomePlaceholderScreen`'s file is deleted once these are wired, since nothing points at it anymore.

## Testing approach

Following this project's established convention (Supabase-boundary calls are manually verified, pure logic gets real unit/widget tests):

- `deepLinkRouteFor` — already tested (Push Notifications milestone); no change needed since its signature is unchanged.
- New pure logic: the "merge received+sent requests, accepted-only" filter for `ConversationListScreen` — extracted as a small pure function, unit-tested.
- Widget tests: `MainDashboardScreen` (Quick Actions render, carousel renders `PropertyCard`s from a provider override, welcome name interpolation), `PropertyCard` (renders given a `Listing` fixture), `ConversationListScreen` (renders rows from provider overrides, unread dot shown/hidden), `NotificationListScreen` (same pattern), the new shell itself (tapping each bottom-nav destination switches the visible branch, Post button pushes `/post-listing` without switching branches).
- `notification`/`message.read_at` RLS and the `send-push-notification` Edge Function update — manual verification only (same convention as every other migration/Edge-Function change this project has made), **with the read-tracking and notification-insert policies specifically checked against `information_schema` after the migration runs live** (per this project's own established post-Profile-migration lesson: verify grants/policies landed exactly as written before considering a migration done, since a wrong grant has broken registered users before).

## Explicitly deferred / out of scope

- Real Matching-Engine-scored "Matches for You" on the dashboard (using plain recent listings instead, per this design's own decision above).
- Realtime/live-updating unread badges (both Chat tab and Notification bell are refetch-on-entry, not subscribed — consistent with `receivedRequestsProvider`/`sentRequestsProvider`'s existing no-realtime convention).
- Push notification categories beyond the existing 3 (`match`/`message`/`cobroke_request`) — no new event types (e.g. rating-received, subscription-expiring) are added to either the push system or the Notification Center in this milestone.
- A "mark all read" bulk action on either the Chat tab or Notification Center — per-item only.
- iOS (unchanged from the Push Notifications design's own Android-only scope).
- **Server-side caller verification in `send-push-notification` (recorded security follow-up).** The function still does not verify that its caller is a legitimate party to the match/request/conversation named in the payload — a pre-existing gap, but this milestone raised its consequence: the new `notification`-row insert means a forged call now writes a *durable* row into another user's Notification Center (attacker-chosen title/body/category/deep_link_data, addressed by a caller-supplied `recipient_negotiator_id`), not just a transient push banner. Accepted for now (single-org internal app, no external threat-model change); the fix — verifying `auth.uid()` is an actual party to the referenced entity before sending or inserting — is a deliberate follow-up task. Documented in-code above the insert block in `supabase/functions/send-push-notification/index.ts`.
