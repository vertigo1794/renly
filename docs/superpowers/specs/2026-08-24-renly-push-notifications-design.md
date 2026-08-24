# renly — Push Notifications (Firebase Cloud Messaging) Design

## Goal

Deliver real push notifications for the 3 events this app already has as concrete triggers -- a new Match computed, a new co-broke request received, a new chat message -- respecting the 3 preference toggles (`notify_match`/`notify_message`/`notify_cobroke_request`) that Milestone 11 (Settings) already added to `negotiator` specifically in anticipation of this milestone. Those columns are currently functionally inert (default `true`, nothing reads them); this milestone is what makes them do something.

## Source of truth

Last remaining item from the proposal's original "Subscription tiers + push notification delay for Free tier" line -- the subscription/tier half was built as Subscription Core + Tier-Gating Enforcement (both merged); this is the notification-delivery half, deferred out of every milestone since Matching Engine because it needed Firebase, an external service this project has never touched.

## Platform scope

**Android only.** This project has been developed and tested on Android emulator exclusively across all 13 prior milestones. iOS support would require an Apple Developer account (paid) and APNs auth key setup -- explicitly out of scope for this milestone, can be added later as its own small follow-up if the user gets an Apple Developer account.

## Architecture

**Client-triggered, not a Postgres trigger.** Right after one of the 3 actions succeeds client-side (a match is computed and stored, a co-broke request is created, a message is sent), the client calls a new Supabase Edge Function, `send-push-notification`, directly -- the same "client calls Edge Function directly" pattern Subscription Core established with `create-subscription`/`create-portal-session`.

This was chosen over a Postgres trigger + `pg_net` webhook-out approach (which would be more robust -- it fires even if the client crashes right after the write, and would also catch server-side-only paths) because: it reuses an existing, well-understood pattern in this codebase instead of introducing a first-ever `pg_net`/webhook-from-Postgres mechanism; all 3 trigger events in this milestone's scope only ever originate from a live client action (unlike, say, `stripe-webhook`'s tier flips, which are genuinely server-only) so the "client crashes right after write" failure mode is a narrow edge case, not a structural gap; and it keeps the failure mode visible and debuggable the same way every other Edge Function call in this app already is.

The Edge Function itself, using the Supabase service-role client and a Firebase Service Account credential (both secrets, set via `supabase secrets set` directly in the user's own terminal -- never pasted into chat, same handling as Stripe's secret key and webhook signing secret):

1. Checks the recipient's relevant `notify_*` preference column. If off, returns success having sent nothing -- this is an expected, common outcome, not an error.
2. Reads every row in `fcm_device_token` for that recipient.
3. Calls the Firebase Cloud Messaging HTTP v1 API once per token.
4. For any token FCM reports as invalid/unregistered (the normal outcome when an app is uninstalled or a token has rotated), deletes that row from `fcm_device_token` -- self-cleaning, no separate cron/cleanup job needed.

The client cannot call the FCM API directly -- sending a push to someone else's device requires a Firebase Service Account credential, which must never live on a device.

## Data model

```sql
create table if not exists fcm_device_token (
  token_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  token text not null,
  created_at timestamptz not null default now(),
  unique (negotiator_id, token)
);

alter table fcm_device_token enable row level security;

create policy fcm_device_token_select_own on fcm_device_token
  for select to authenticated using (negotiator_id = auth.uid());
create policy fcm_device_token_insert_own on fcm_device_token
  for insert to authenticated with check (negotiator_id = auth.uid());
create policy fcm_device_token_delete_own on fcm_device_token
  for delete to authenticated using (negotiator_id = auth.uid());
```

A separate table, not a column on `negotiator`, because multi-device support was explicitly chosen over the simpler one-token-per-negotiator column during this design's brainstorm -- a negotiator can be logged in on more than one device and expects a push on all of them. `unique(negotiator_id, token)` makes registration idempotent: re-registering the same token (the common case -- FCM tokens rarely rotate) is a plain upsert, never a duplicate row.

No `UPDATE` policy -- a token is either the current one (present) or stale (deleted, by the owning negotiator or by the Edge Function's self-cleaning path), never edited in place.

The Edge Function reads every negotiator's tokens via the service-role client, bypassing RLS entirely -- same pattern as every other Edge Function in this project.

## Recipient resolution

Each of the 3 trigger points must determine who to notify *before* calling the Edge Function -- the client already has the context to compute this without an extra round-trip.

**Match** (`MatchingRepository.computeAndStoreMatchesForListing`/`computeAndStoreMatchesForRequirement`, called from `PostListingScreen`/`PostRequirementScreen` right after a successful create): the existing `_store` method upserts into `match` with `ignoreDuplicates: true` but doesn't currently read back which rows were genuinely new. This must change to chain `.select()` after the upsert -- with `ignoreDuplicates: true`, PostgREST's `RETURNING` only reports rows that were actually inserted; a row that already existed (a re-computation re-matching something already matched) is silently skipped by the conflict clause and never appears in the returned set. Without this, every re-computation would re-notify recipients for matches they were already notified about. The recipient for each genuinely-new row is the *other* side's negotiator: the requirement owner when a listing was just posted, the listing owner when a requirement was just posted (the querying screen already knows which side it created, so no extra lookup is needed to know which field to read as "recipient").

**Co-broke request** (`sendCobrokeRequest` in `send_cobroke_request_action.dart`, right after `createRequest` succeeds): the recipient is whichever side of the request's `match` is *not* `initiator_id` -- resolved via `match!inner(listing!inner(*), requirement!inner(*))`, the exact join shape `CobrokeRequestRepository._toCandidates` already uses to resolve both parties.

**Message** (`MessageRepository.sendMessage`, right after the insert succeeds): the recipient is the other party in that message's `cobroke_request` -- one join further than the co-broke-request case (`message.request_id -> cobroke_request.match_id -> match -> listing/requirement`), same resolution shape, one more hop.

All 3 resolutions are extracted into a single pure function, `resolveRecipient`, taking the already-fetched row data and the caller's own negotiator id, returning the recipient id (or `null` if there's no valid other party) -- testable the same way `MatchingEngine.score()` is: no Supabase dependency, plain unit tests.

## Client-side: registration, deep-linking, foreground behavior

**Token registration.** In `main.dart`, after `Supabase.initialize` and after confirming a session exists (registering a token with no logged-in negotiator makes no sense): request notification permission (`FirebaseMessaging.instance.requestPermission()`), read the token (`getToken()`), upsert it into `fcm_device_token`. `FirebaseMessaging.instance.onTokenRefresh` is also wired once at the same point, re-upserting whenever FCM rotates a token (rare, but real).

**Deep-linking.** Each push carries a small JSON payload identifying its category and target:
- `match` -> `/property/:listingId/matches` or `/requirement-board/:requirementId/matches`, depending on which side the recipient owns (the payload states which)
- `cobroke_request` -> `/my-requests` (no per-request route exists yet; opens the Received tab)
- `message` -> `/messages/:requestId` (exact existing route)

`firebase_messaging` surfaces 3 distinct states that must all be handled: `FirebaseMessaging.onMessage` (app foreground, push arrives while running), `FirebaseMessaging.onMessageOpenedApp` (app was backgrounded, user tapped the push), and `FirebaseMessaging.instance.getInitialMessage()` (app was fully terminated, the tap itself launched it -- checked once, after the router has finished its first build). The router navigation for the latter two is driven through the app's existing `ProviderContainer` (already available in `main.dart` for `Supabase`/Stripe bootstrap) reading `appRouterProvider`'s `GoRouter` instance and calling `.go(path)` -- no new `GlobalKey<NavigatorState>` needed, this stays consistent with the existing Riverpod-only navigation pattern.

**Foreground behavior.** `onMessage` does *not* show a system tray notification and does *not* auto-navigate -- it shows an in-app `SnackBar`-style banner with the notification's title/body; tapping the banner (not required) performs the same deep-link navigation as a background tap. For `message` specifically, if the recipient is already inside the matching `ChatScreen` (`requestId` matches the currently-open route), the banner is suppressed entirely -- `ChatScreen` already shows the message live via its existing Realtime stream, and a banner on top of a screen already displaying the thing it describes would be pure noise.

## Preference gating

The 3 existing toggles map directly: `notify_match` gates `match` pushes, `notify_message` gates `message` pushes, `notify_cobroke_request` gates `cobroke_request` pushes. Toggling one off suppresses only that category server-side (checked inside the Edge Function, per push) -- it does **not** unregister or delete the device token, since the other two categories must keep working independently. This mirrors the toggles' existing per-category independence from Settings' own design.

## Testing approach

**Automated, following this project's established Supabase-boundary-is-untested convention:**
- `fcm_device_token` upsert/registration logic, the `send-push-notification` Edge Function itself -- untested (same convention as every other repository/Edge-Function call in this project). The Edge Function gets the usual manual `supabase functions serve` + `curl` verification instead.
- `resolveRecipient` (the pure recipient-resolution function) -- real unit tests, same tier as `MatchingEngine.score()`.
- The deep-link payload-to-route mapping -- a pure function, real unit tests.
- Widget tests for the in-app banner's suppression logic (shown/hidden based on current route vs. payload) via provider override, following established convention.

**Manual verification -- genuinely different requirement from every other pending verification in this project.** FCM push delivery does not work on a plain Android emulator; it requires either an Android emulator built from a **Google Play** system image specifically (not the default "Google APIs" image this project's `Medium_Phone_API_36.1` emulator may already be using -- must be confirmed/rebuilt) or a real Android device. This is a hard platform requirement, not a convenience choice, and is called out explicitly so it isn't discovered as a surprise during testing:

1. Post a listing that matches an existing requirement (different negotiator) -- confirm the requirement's owner receives a push.
2. Tap that push -- confirm it opens the correct `MatchesForRequirementScreen`.
3. Toggle `notify_match` off, repeat the match -- confirm no push arrives.
4. Send a co-broke request -- confirm the recipient gets a push, tapping opens `/my-requests`.
5. Send a message (recipient's app backgrounded/terminated) -- confirm delivery and correct `ChatScreen` deep-link.
6. Send a message while the recipient has that exact `ChatScreen` open (foreground) -- confirm the banner is suppressed (Realtime already shows it).
7. Send a message while the recipient's app is foreground but on a *different* screen -- confirm the in-app banner appears (not a system tray notification).
8. Uninstall the app on a test device, then trigger a push toward its now-stale token -- confirm the Edge Function deletes that `fcm_device_token` row after FCM reports it invalid.

## Explicitly deferred / out of scope

- iOS support (Android only, per this design's platform-scope decision).
- A notification history/inbox screen inside the app -- push + deep-link only, no persisted list of past notifications to browse.
- Rich notification content (listing photos in the push, actionable buttons like Accept/Decline directly from the notification tray) -- title + body text only.
- Batching/digest ("5 new matches" as one push) -- every event sends its own push, no grouping.
- Postgres trigger / `pg_net` server-side delivery -- explicitly decided against in favor of client-triggered (see Architecture).
- Per-recipient-locale push content -- text is generated in the sending client's current locale; there's no mechanism to know or honor a recipient's own locale preference.
