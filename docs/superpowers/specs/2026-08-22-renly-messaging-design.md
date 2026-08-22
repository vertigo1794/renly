# renly — Messaging Design

Status: approved (2026-08-22). Seventh milestone, built on Co-Broke Request (`docs/superpowers/specs/2026-08-23-renly-cobroke-request-design.md`), merged and live. Second of three deliberately-split sub-milestones covering the proposal's "Collaboration Module" — this doc covers `message` (Supabase Realtime chat) only. Digital agreements (`agreement`) is the third and final sub-milestone, not part of this scope.

## Goal

Let two negotiators with an ACCEPTED co-broke request exchange live text messages, matching the proposal's own workflow ordering: co-broke request accepted → structured messaging opens.

## Source of truth

From `Fakhrullah_Renly_Project_Proposal.pdf` Table 6.1 (ERD):

> `message`: `message_id` (PK), `request_id` (FK), `sender_id` (FK), `body`, `sent_at`. Relationship: 1 request : many messages.

Proposal §5.3 (workflow, step 8): "Negotiation: upon acceptance, structured messaging opens between the two parties and the proposed commission split is exchanged."

**Resolved with the user:** messaging is hard-gated on `cobroke_request.status == 'accepted'`. A pending or declined request has no chat — not just hidden in the UI, but rejected at the RLS level too. This is a deliberate interpretation of "upon acceptance" as a precondition, not merely a suggested workflow order.

## Realtime architecture

First use of Supabase Realtime in this codebase across 7 prior milestones (all request/response only). Two approaches were considered:

- **Chosen: `.stream()` convenience API.** `supabase.from('message').stream(primaryKey: ['message_id']).eq('request_id', id)` returns a live-updating `Stream<List<Map>>` that respects RLS server-side. Each emission is the FULL current row set for that filter, not a delta — so there's no separate "fetch history on load" + "merge incoming events" logic to write; one stream covers both. Wrapped in Riverpod as `StreamProvider.autoDispose.family<List<Message>, String>` — **`.autoDispose` must be explicit**: in the Riverpod version this project is pinned to (2.6.1), `.family` alone does NOT default to autoDispose (that's a Riverpod 3.x behavior); omitting it leaves the Realtime subscription and its channel open for the rest of the app's process lifetime after `ChatScreen` is popped, one leaked channel per distinct `requestId` ever opened. With the explicit modifier, the subscription is cancelled when `ChatScreen` is popped and re-established fresh (with full current history) if reopened. Sorting is done in Dart on the parsed `DateTime`, not via `.order()` on the stream builder — see Data model note below.
- **Rejected: raw `RealtimeChannel` + `.onPostgresChanges()`.** Gives finer control (event-level granularity, presence/typing indicators) at the cost of manually written subscribe-on-enter/unsubscribe-on-exit lifecycle and manual local-state merging. None of that control is needed for a plain list-and-send chat screen, and hand-rolled lifecycle code is exactly where a first-time-Realtime bug would hide.

**Testing boundary gap, acknowledged explicitly:** this project's established convention never unit-tests Supabase-calling code (repositories), and a widget test cannot exercise a live Realtime subscription firing across two sessions. The same blind spot that let a Critical RLS bug through Co-Broke Request's 131/131-passing suite applies here. This design requires a mandatory manual two-account verification step after merge (see Testing approach) — not optional, not deferred to "if there's time."

## Data model

```sql
create table message (
  message_id uuid primary key default gen_random_uuid(),
  request_id uuid not null references cobroke_request(request_id) on delete cascade,
  sender_id uuid not null references negotiator(negotiator_id) on delete cascade,
  body text not null check (char_length(trim(body)) > 0),
  sent_at timestamptz not null default now()
);
```

No update/delete — messages are immutable once sent, same as `match`. No edit/unsend flow in this milestone.

## RLS

```sql
alter table message enable row level security;

-- Select/insert: viewer must be a party to the underlying cobroke_request
-- (its initiator, or whichever side of the match's listing/requirement they
-- own), AND the request must be status = 'accepted'. Same ownership-join
-- pattern cobroke_request's own RLS already uses to reach match ->
-- listing/requirement, one level deeper via cobroke_request -> match.
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
```

The `cr.status = 'accepted'` condition lives inside RLS itself (both SELECT and INSERT), not just as an app-level UI gate — enforced at the database, same defense-in-depth precedent as Matching Engine's mandatory-filter trigger and consistent with the lesson from Co-Broke Request's Critical bug (never trust the client-side gate alone).

Supabase Realtime's `postgres_changes` subscriptions respect the same RLS policies as regular queries — a subscriber only receives change events for rows their SELECT policy would return. This means `.stream()` naturally stops delivering messages the moment `cr.status` were ever to change away from `accepted` (no such transition exists in this milestone, but the policy holds regardless).

## Screens

**File structure:**
```
lib/features/collaboration/
  message_repository.dart      # sole Supabase touchpoint: sendMessage, messagesStream
  message_providers.dart       # messageRepositoryProvider, messagesStreamProvider.family
  chat_screen.dart              # ChatScreen(requestId)
  models/
    message.dart                # messageId, requestId, senderId, body, sentAt
```

- `MessageRepository.sendMessage({required String requestId, required String senderId, required String body})` — inserts a row.
- `MessageRepository.messagesStream(String requestId)` — returns `Stream<List<Message>>` built from `.stream(primaryKey: ['message_id']).eq('request_id', requestId)`, mapped row-by-row through `Message.fromJson`, then sorted in Dart by the parsed `sentAt` `DateTime`. **Not** sorted via `.order('sent_at')` on the stream builder: the builder's internal merge sorts the raw column as a STRING, and a `timestamptz` value arrives in a different string format from a Realtime INSERT payload (`"2026-08-24 10:00:00+00"`, space-separated) than from the initial PostgREST fetch (`"2026-08-24T10:00:00+00:00"`, ISO `T`-separated) — a raw string comparison sorts every live-delivered message above the entire same-day history instead of below it. Sorting the already-parsed `DateTime` values sidesteps the format mismatch entirely.
- `messagesStreamProvider` = `StreamProvider.family<List<Message>, String>(requestId)`, watches the repository stream.
- `ChatScreen(requestId)` — `ref.watch(messagesStreamProvider(requestId))` renders an `AsyncValue<List<Message>>` as a `ListView` (`reverse: true` over the reversed list, so the viewport stays pinned to the newest message on open and on every new arrival — own messages right-aligned, counterparty's left-aligned, sender resolved via the same negotiator-lookup pattern already used for `MatchCandidate`/`CobrokeRequestCandidate` owners), plus a text field + send button. Send calls `sendMessage`, wrapped in try/catch + snackbar on failure (`PropertyDetailScreen._changeStatus` precedent), clears the input on success — no optimistic local append needed since the stream's next emission (near-instant on the sender's own connection) already includes the new row.

**Access point:** a "Chat" button added to `MyRequestsScreen` rows (both Received and Sent tabs) where `status == 'accepted'`, navigating to `/messages/:requestId`. Not added to the Matching Engine match-card screens — chat requires an accepted request to exist, not just a match.

## Router

New route, requiring a session: `/messages/:requestId` → `ChatScreen`. No list-of-conversations screen in this milestone — the only way in is the "Chat" button from an accepted row in `MyRequestsScreen`, which already serves as the conversation list.

## Manual setup

`supabase/migrations/0008_messaging.sql` — single file, same hardened-from-the-start re-runnable pattern (`create table if not exists`, `drop policy if exists` before each create) as `0006`/`0007`. No storage bucket, no Auth-dashboard changes. **Supabase Realtime must be enabled for the `message` table** — this requires one extra manual step beyond running the SQL: in the Supabase dashboard, Database → Replication, toggle the `message` table on for the `supabase_realtime` publication (or run `alter publication supabase_realtime add table message;` as part of the same migration file). This design includes it in the migration SQL directly so it's not a separately-forgotten manual step.

## Testing approach

Same boundary as every prior milestone, with one addition specific to Realtime:

- `MessageRepository` untested directly (Supabase-calling code) — established convention.
- `Message.fromJson` gets a real unit test.
- `ChatScreen` gets widget tests following the established pattern (`rootBundle.clear()`, `pumpAndSettle`, hardcoded literal test strings) — but these can only verify rendering given a fixed `AsyncValue<List<Message>>` (via provider override with a static list), NOT that a live subscription actually delivers a new message when another party sends one. This gap is explicitly named, not silently accepted.
- **Mandatory manual verification after merge, before considering the milestone done:** the user runs the app on two accounts (two devices/browser profiles) with an already-accepted co-broke request between them, opens `ChatScreen` on both, sends a message from account A, and confirms it appears **at the bottom of account B's message list**, below the existing history, without a manual refresh — not merely that it appears somewhere. This is a required step for this milestone specifically, the same way running each new migration on live Supabase has been required for every prior milestone — but this one verifies *behavior*, not just schema.

## Explicitly deferred / out of scope for this milestone

- Editing or unsending a sent message.
- Typing indicators, read receipts, presence.
- File/image attachments in chat (proposal's ERD has `body` as the only content field).
- A standalone "all conversations" list screen (accepted requests in `MyRequestsScreen` serve this purpose for now).
- Push notification on new message (same FCM-not-wired-up reason every prior milestone deferred it).
- Digital agreements (`agreement` table) — third and final Collaboration sub-milestone, next after this one.
