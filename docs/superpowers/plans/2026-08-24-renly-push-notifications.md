# Push Notifications (FCM) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver real push notifications for the 3 existing trigger events (new Match, new co-broke request, new chat message), gated by the 3 `notify_*` preference columns Settings already added, via a client-triggered Supabase Edge Function calling the Firebase Cloud Messaging HTTP v1 API. Android only.

**Architecture:** A new `fcm_device_token` table stores per-device tokens. The Flutter client registers/refreshes its token on app start, and after each of the 3 trigger actions succeeds, the owning repository (`MatchingRepository`, `CobrokeRequestRepository`, `MessageRepository`) resolves the recipient(s) from data it already has and calls a new Edge Function, `send-push-notification`, which checks the recipient's preference, looks up their tokens, and sends via FCM's v1 API using a Firebase Service Account credential. Tapping a push deep-links via `go_router`; a foreground push shows an in-app banner instead of a system tray notification.

**Tech Stack:** `firebase_core`/`firebase_messaging` (Flutter), Supabase Edge Function (Deno/TypeScript) using `djwt` for Service-Account JWT signing and a raw `fetch` call to FCM's v1 REST API (no Firebase Admin SDK -- it isn't Deno-compatible).

## Global Constraints

- Every RLS policy on the new table must include `to authenticated` explicitly (this project hit a real bug once from omitting it on `listing`).
- Any `.update()`/`.insert()` whose success determines whether a later step should run must check for an RLS-rejected zero-row result and throw, per this project's established `AgreementRepository`/`CobrokeRequestRepository` pattern -- but note this module's push-sending calls are explicitly NOT held to this: a failed or skipped push must never surface as an error or block the primary action that triggered it (see each wiring task).
- Malaysian Malay for any live guided external-dashboard walkthrough during execution (Firebase project creation, `google-services.json` placement, Edge Function secret setting) -- the plan text itself, like every other plan in this project, is in English.
- Firebase Service Account credential is a secret: the user sets it via `supabase secrets set` directly in their own terminal. It must never be pasted into a chat/conversation, same handling as this project's Stripe secret key and webhook signing secret.
- `google-services.json` is already covered by this repo's `.gitignore` (`**/google-services.json`, added at scaffold time) -- never attempt to commit it.
- Supabase-boundary code (repository methods that call `.from()`/`.rpc()`/`.functions.invoke()`, and the Edge Function itself) is untested by this project's established convention. Pure functions with no Supabase/Flutter dependency get real unit tests, same tier as `MatchingEngine.score()`.

---

### Task 1: Supabase migration -- `fcm_device_token` table

**Files:**
- Create: `supabase/migrations/0016_fcm_device_token.sql`

**Interfaces:**
- Produces: table `fcm_device_token(token_id uuid pk, negotiator_id uuid references negotiator, token text, created_at timestamptz, unique(negotiator_id, token))`, RLS policies `fcm_device_token_select_own`/`fcm_device_token_insert_own`/`fcm_device_token_delete_own`. Later tasks' repository code reads/writes this table by name.

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/0016_fcm_device_token.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0015.
--
-- Stores one row per (negotiator, FCM device token) pair. A separate table
-- rather than a column on negotiator -- a negotiator can be logged in on
-- more than one device and should get a push on all of them, per this
-- module's design doc.
--
-- No UPDATE policy: a token is either current (present) or stale (deleted,
-- by its owner or by send-push-notification's self-cleaning path when FCM
-- reports it invalid), never edited in place.
create table if not exists fcm_device_token (
  token_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  token text not null,
  created_at timestamptz not null default now(),
  unique (negotiator_id, token)
);

alter table fcm_device_token enable row level security;

drop policy if exists fcm_device_token_select_own on fcm_device_token;
create policy fcm_device_token_select_own on fcm_device_token
  for select to authenticated using (negotiator_id = auth.uid());

drop policy if exists fcm_device_token_insert_own on fcm_device_token;
create policy fcm_device_token_insert_own on fcm_device_token
  for insert to authenticated with check (negotiator_id = auth.uid());

drop policy if exists fcm_device_token_delete_own on fcm_device_token;
create policy fcm_device_token_delete_own on fcm_device_token
  for delete to authenticated using (negotiator_id = auth.uid());
```

- [ ] **Step 2: No automated test for this step**

SQL migrations are Supabase-boundary code, untested by this project's established convention (verified manually per Task 9's README section instead). Confirm the file is syntactically well-formed by eye against the pattern of every prior migration in `supabase/migrations/`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0016_fcm_device_token.sql
git commit -m "feat: add fcm_device_token table migration"
```

---

### Task 2: Pure notification logic -- payload model, deep-link routing, recipient resolution, foreground suppression

**Files:**
- Create: `app/lib/features/notifications/models/push_payload.dart`
- Create: `app/lib/features/notifications/deep_link.dart`
- Create: `app/lib/features/notifications/recipient_resolver.dart`
- Create: `app/lib/features/notifications/foreground_suppression.dart`
- Test: `app/test/features/notifications/deep_link_test.dart`
- Test: `app/test/features/notifications/recipient_resolver_test.dart`
- Test: `app/test/features/notifications/foreground_suppression_test.dart`

**Interfaces:**
- Produces: `PushPayload` class (`recipientNegotiatorId`, `category`, `title`, `body`, `deepLinkData`, `.toJson()`); `String deepLinkRouteFor(String category, Map<String, String> data)`; `List<String> resolveMatchRecipients({required List<Map<String, dynamic>> insertedRows, required String ownerKey, required Map<String, String> ownerNegotiatorIdByKey})`; `String? resolveOtherPartyInMatch({required String actorId, required String listingNegotiatorId, required String requirementNegotiatorId})`; `bool shouldSuppressForegroundBanner({required String category, required String? currentRouteLocation, required Map<String, String> data})`. Tasks 5-7 (repository wiring) consume `PushPayload`/`resolveMatchRecipients`/`resolveOtherPartyInMatch`. Task 8 (client bootstrap) consumes `deepLinkRouteFor`/`shouldSuppressForegroundBanner`.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/features/notifications/deep_link_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/notifications/deep_link.dart';

void main() {
  group('deepLinkRouteFor', () {
    test('match category, owner_side listing routes to property matches', () {
      final route = deepLinkRouteFor('match', {'owner_side': 'listing', 'listing_id': 'L1'});
      expect(route, '/property/L1/matches');
    });

    test('match category, owner_side requirement routes to requirement-board matches', () {
      final route = deepLinkRouteFor('match', {'owner_side': 'requirement', 'requirement_id': 'R1'});
      expect(route, '/requirement-board/R1/matches');
    });

    test('cobroke_request category routes to my-requests', () {
      final route = deepLinkRouteFor('cobroke_request', {});
      expect(route, '/my-requests');
    });

    test('message category routes to messages/:requestId', () {
      final route = deepLinkRouteFor('message', {'request_id': 'REQ1'});
      expect(route, '/messages/REQ1');
    });

    test('unknown category falls back to /home', () {
      final route = deepLinkRouteFor('unknown', {});
      expect(route, '/home');
    });
  });
}
```

```dart
// app/test/features/notifications/recipient_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/notifications/recipient_resolver.dart';

void main() {
  group('resolveMatchRecipients', () {
    test('maps each inserted row to its owner via the given key', () {
      final recipients = resolveMatchRecipients(
        insertedRows: [
          {'listing_id': 'L1', 'requirement_id': 'R1', 'score': 80},
          {'listing_id': 'L2', 'requirement_id': 'R2', 'score': 90},
        ],
        ownerKey: 'requirement_id',
        ownerNegotiatorIdByKey: {'R1': 'N1', 'R2': 'N2'},
      );
      expect(recipients, ['N1', 'N2']);
    });

    test('empty inserted rows yields no recipients', () {
      final recipients = resolveMatchRecipients(
        insertedRows: const [],
        ownerKey: 'requirement_id',
        ownerNegotiatorIdByKey: const {'R1': 'N1'},
      );
      expect(recipients, isEmpty);
    });

    test('a row whose key is missing from the owner map is skipped, not crashed on', () {
      final recipients = resolveMatchRecipients(
        insertedRows: [
          {'listing_id': 'L1', 'requirement_id': 'R_UNKNOWN', 'score': 80},
        ],
        ownerKey: 'requirement_id',
        ownerNegotiatorIdByKey: {'R1': 'N1'},
      );
      expect(recipients, isEmpty);
    });
  });

  group('resolveOtherPartyInMatch', () {
    test('returns the listing side when the actor is the requirement owner', () {
      final other = resolveOtherPartyInMatch(
        actorId: 'N_REQ',
        listingNegotiatorId: 'N_LISTING',
        requirementNegotiatorId: 'N_REQ',
      );
      expect(other, 'N_LISTING');
    });

    test('returns the requirement side when the actor is the listing owner', () {
      final other = resolveOtherPartyInMatch(
        actorId: 'N_LISTING',
        listingNegotiatorId: 'N_LISTING',
        requirementNegotiatorId: 'N_REQ',
      );
      expect(other, 'N_REQ');
    });

    test('returns null when the actor matches neither side', () {
      final other = resolveOtherPartyInMatch(
        actorId: 'N_STRANGER',
        listingNegotiatorId: 'N_LISTING',
        requirementNegotiatorId: 'N_REQ',
      );
      expect(other, isNull);
    });
  });
}
```

```dart
// app/test/features/notifications/foreground_suppression_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/notifications/foreground_suppression.dart';

void main() {
  group('shouldSuppressForegroundBanner', () {
    test('suppresses a message push when already viewing that exact chat', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: '/messages/REQ1',
        data: {'request_id': 'REQ1'},
      );
      expect(suppressed, isTrue);
    });

    test('does not suppress a message push for a different chat', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: '/messages/REQ2',
        data: {'request_id': 'REQ1'},
      );
      expect(suppressed, isFalse);
    });

    test('never suppresses match or cobroke_request pushes -- no Realtime screen backs them', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'match',
        currentRouteLocation: '/property/L1/matches',
        data: {'listing_id': 'L1'},
      );
      expect(suppressed, isFalse);
    });

    test('does not suppress when current route is unknown (null)', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: null,
        data: {'request_id': 'REQ1'},
      );
      expect(suppressed, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/features/notifications/`
Expected: FAIL -- files under `lib/features/notifications/` don't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/features/notifications/models/push_payload.dart
/// Body sent to the send-push-notification Edge Function. category is one
/// of 'match' | 'message' | 'cobroke_request' -- kept as a plain String
/// (not an enum) since it round-trips through JSON to Deno either way and
/// an enum would just add a mapping step with no real type safety gained.
class PushPayload {
  const PushPayload({
    required this.recipientNegotiatorId,
    required this.category,
    required this.title,
    required this.body,
    required this.deepLinkData,
  });

  final String recipientNegotiatorId;
  final String category;
  final String title;
  final String body;
  final Map<String, String> deepLinkData;

  Map<String, dynamic> toJson() => {
        'recipient_negotiator_id': recipientNegotiatorId,
        'category': category,
        'title': title,
        'body': body,
        'deep_link_data': deepLinkData,
      };
}
```

```dart
// app/lib/features/notifications/deep_link.dart
/// Pure mapping from a push's category + data payload to the in-app route
/// to open on tap. `data` mirrors PushPayload.deepLinkData / a
/// RemoteMessage's .data map (string values only, per FCM's own payload
/// format).
String deepLinkRouteFor(String category, Map<String, String> data) {
  switch (category) {
    case 'match':
      if (data['owner_side'] == 'listing') {
        return '/property/${data['listing_id']}/matches';
      }
      return '/requirement-board/${data['requirement_id']}/matches';
    case 'cobroke_request':
      return '/my-requests';
    case 'message':
      return '/messages/${data['request_id']}';
    default:
      return '/home';
  }
}
```

```dart
// app/lib/features/notifications/recipient_resolver.dart
/// Given the rows a match upsert's .select() actually returned (only
/// genuinely-new rows -- PostgREST's RETURNING skips ignoreDuplicates
/// conflicts), maps each to its recipient via a pre-built owner lookup the
/// caller already has in scope from its own compute loop. ownerKey is
/// 'requirement_id' when computing from a freshly-posted Listing (notify
/// the requirement owners), or 'listing_id' when computing from a
/// freshly-posted Requirement (notify the listing owners).
List<String> resolveMatchRecipients({
  required List<Map<String, dynamic>> insertedRows,
  required String ownerKey,
  required Map<String, String> ownerNegotiatorIdByKey,
}) {
  final recipients = <String>[];
  for (final row in insertedRows) {
    final key = row[ownerKey] as String?;
    final ownerId = key == null ? null : ownerNegotiatorIdByKey[key];
    if (ownerId != null) recipients.add(ownerId);
  }
  return recipients;
}

/// Shared shape for co-broke-request and message recipient resolution:
/// given a match's two owning negotiators and who just acted (the request
/// initiator, or a message sender), returns whichever side is NOT the
/// actor. Returns null if the actor matches neither side, which should
/// never happen for a valid match but is handled rather than crashed on.
String? resolveOtherPartyInMatch({
  required String actorId,
  required String listingNegotiatorId,
  required String requirementNegotiatorId,
}) {
  if (listingNegotiatorId != actorId) return listingNegotiatorId;
  if (requirementNegotiatorId != actorId) return requirementNegotiatorId;
  return null;
}
```

```dart
// app/lib/features/notifications/foreground_suppression.dart
/// A foreground 'message' push is redundant when the recipient already has
/// that exact chat open -- ChatScreen's Realtime stream already shows it
/// live. match/cobroke_request pushes are never suppressed: neither has a
/// Realtime-backed screen behind it, so the banner is the only signal the
/// recipient gets.
bool shouldSuppressForegroundBanner({
  required String category,
  required String? currentRouteLocation,
  required Map<String, String> data,
}) {
  if (category != 'message' || currentRouteLocation == null) return false;
  return currentRouteLocation == '/messages/${data['request_id']}';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/features/notifications/`
Expected: All PASS (12 tests: 5 deep_link + 3+3 recipient_resolver + 4 foreground_suppression).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/notifications/models/push_payload.dart \
        app/lib/features/notifications/deep_link.dart \
        app/lib/features/notifications/recipient_resolver.dart \
        app/lib/features/notifications/foreground_suppression.dart \
        app/test/features/notifications/
git commit -m "feat: add pure push-notification logic (payload, deep-link, recipient resolution, foreground suppression)"
```

---

### Task 3: FcmTokenRepository, PushNotificationRepository, notification_providers.dart

**Files:**
- Create: `app/lib/features/notifications/fcm_token_repository.dart`
- Create: `app/lib/features/notifications/push_notification_repository.dart`
- Create: `app/lib/features/notifications/notification_providers.dart`

**Interfaces:**
- Consumes: `PushPayload` (Task 2).
- Produces: `FcmTokenRepository.registerToken({required String negotiatorId, required String token})`; `PushNotificationRepository.sendPushNotification(PushPayload payload)`; `fcmTokenRepositoryProvider`, `pushNotificationRepositoryProvider` (both `Provider<...>`, no `.family`, mirroring every other repository provider in this project). Tasks 4-6 (repository wiring) and Task 8 (client bootstrap) consume these providers.

- [ ] **Step 1: No test-first step**

Both classes are pure Supabase-calling repository code -- untested per this project's established convention (matches `SubscriptionRepository`, every Edge-Function-calling repository method in this project). Write directly.

- [ ] **Step 2: Write the implementation**

```dart
// app/lib/features/notifications/fcm_token_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// The only file in this app that writes fcm_device_token directly.
class FcmTokenRepository {
  FcmTokenRepository(this._client);

  final SupabaseClient _client;

  Future<void> registerToken({required String negotiatorId, required String token}) async {
    await _client.from('fcm_device_token').upsert(
      {'negotiator_id': negotiatorId, 'token': token},
      onConflict: 'negotiator_id,token',
    );
  }
}
```

```dart
// app/lib/features/notifications/push_notification_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/push_payload.dart';

/// Calls the send-push-notification Edge Function. Never throws to a
/// caller that treats push delivery as best-effort (Tasks 4-6) -- those
/// callers wrap this in their own try/catch and swallow failures, since a
/// push failing must never undo or error out an already-successful
/// primary action (a new match, a sent request, a sent message).
class PushNotificationRepository {
  PushNotificationRepository(this._client);

  final SupabaseClient _client;

  Future<void> sendPushNotification(PushPayload payload) async {
    await _client.functions.invoke('send-push-notification', body: payload.toJson());
  }
}
```

```dart
// app/lib/features/notifications/notification_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fcm_token_repository.dart';
import 'push_notification_repository.dart';

final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>((ref) {
  return FcmTokenRepository(Supabase.instance.client);
});

final pushNotificationRepositoryProvider = Provider<PushNotificationRepository>((ref) {
  return PushNotificationRepository(Supabase.instance.client);
});
```

- [ ] **Step 3: Run the full suite to confirm no regressions**

Run: `cd app && flutter test`
Expected: All PASS (no existing tests touch these new files).

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/notifications/fcm_token_repository.dart \
        app/lib/features/notifications/push_notification_repository.dart \
        app/lib/features/notifications/notification_providers.dart
git commit -m "feat: add FcmTokenRepository, PushNotificationRepository, and their providers"
```

---

### Task 4: Edge Function -- `send-push-notification`

**Files:**
- Create: `supabase/functions/send-push-notification/index.ts`

**Interfaces:**
- Consumes: request body `{ recipient_negotiator_id, category, title, body, deep_link_data }` (matches `PushPayload.toJson()` from Task 2/3).
- Produces: HTTP endpoint `send-push-notification`, invoked by `PushNotificationRepository.sendPushNotification` (Task 3).

- [ ] **Step 1: No automated test for this step**

Edge Functions are untested by this project's established convention -- verified manually via `supabase functions serve` + `curl`, per Task 9.

- [ ] **Step 2: Write the Edge Function**

```typescript
// supabase/functions/send-push-notification/index.ts
//
// Deployed WITHOUT --no-verify-jwt (unlike stripe-webhook): this function
// is only ever called by an authenticated app client (MatchingRepository,
// CobrokeRequestRepository, MessageRepository), never by an external
// service reaching in from outside -- Supabase's default JWT check is
// correct here, not a gotcha to work around.
//
// Uses a raw fetch-based Google OAuth2 + FCM v1 REST call rather than the
// Firebase Admin SDK -- the Admin SDK is Node-oriented and not reliably
// Deno-compatible. djwt handles the RS256 JWT signing step.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const FIREBASE_SERVICE_ACCOUNT = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")!);
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

// category -> the negotiator column gating that category's delivery.
const PREFERENCE_COLUMN: Record<string, string> = {
  match: "notify_match",
  message: "notify_message",
  cobroke_request: "notify_cobroke_request",
};

let cachedKey: CryptoKey | null = null;

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  cachedKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return cachedKey;
}

async function getAccessToken(): Promise<string> {
  const key = await importPrivateKey(FIREBASE_SERVICE_ACCOUNT.private_key);
  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: FIREBASE_SERVICE_ACCOUNT.client_email,
      scope: FCM_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      iat: getNumericDate(0),
      exp: getNumericDate(3600),
    },
    key,
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(`Failed to get FCM access token: ${JSON.stringify(data)}`);
  }
  return data.access_token as string;
}

Deno.serve(async (req) => {
  try {
    const { recipient_negotiator_id, category, title, body, deep_link_data } = await req.json();

    const preferenceColumn = PREFERENCE_COLUMN[category];
    if (!preferenceColumn) {
      return new Response(JSON.stringify({ error: `Unknown category: ${category}` }), { status: 400 });
    }

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: negotiator, error: negotiatorError } = await adminClient
      .from("negotiator")
      .select(preferenceColumn)
      .eq("negotiator_id", recipient_negotiator_id)
      .single();
    if (negotiatorError) {
      console.error("send-push-notification: negotiator lookup failed", negotiatorError);
      return new Response(JSON.stringify({ error: "Negotiator lookup failed" }), { status: 500 });
    }
    if (negotiator[preferenceColumn] === false) {
      // Expected, common outcome -- recipient has this category muted.
      return new Response(JSON.stringify({ sent: 0, skipped: "preference_off" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: tokens, error: tokensError } = await adminClient
      .from("fcm_device_token")
      .select("token_id, token")
      .eq("negotiator_id", recipient_negotiator_id);
    if (tokensError) {
      console.error("send-push-notification: token lookup failed", tokensError);
      return new Response(JSON.stringify({ error: "Token lookup failed" }), { status: 500 });
    }
    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, skipped: "no_devices" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken();
    let sent = 0;
    for (const row of tokens) {
      const fcmResponse = await fetch(
        `https://fcm.googleapis.com/v1/projects/${FIREBASE_SERVICE_ACCOUNT.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: row.token,
              notification: { title, body },
              data: deep_link_data ?? {},
            },
          }),
        },
      );
      if (fcmResponse.ok) {
        sent += 1;
        continue;
      }
      const errorBody = await fcmResponse.json();
      const errorStatus = errorBody?.error?.status;
      if (errorStatus === "NOT_FOUND" || errorStatus === "UNREGISTERED" || errorStatus === "INVALID_ARGUMENT") {
        // Stale token (app uninstalled, or FCM rotated it) -- self-clean
        // so this table never accumulates dead rows.
        const { error: deleteError } = await adminClient
          .from("fcm_device_token")
          .delete()
          .eq("token_id", row.token_id);
        if (deleteError) {
          console.error("send-push-notification: failed to delete stale token", deleteError);
        }
      } else {
        console.error("send-push-notification: FCM send failed", errorBody);
      }
    }

    return new Response(JSON.stringify({ sent }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("send-push-notification: unhandled error", error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/send-push-notification/index.ts
git commit -m "feat: add send-push-notification Edge Function (FCM v1 API via service account JWT)"
```

---

### Task 5: Wire push into MatchingRepository

**Files:**
- Modify: `app/lib/features/matching/matching_repository.dart`
- Modify: `app/lib/features/matching/matching_providers.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `PushNotificationRepository` (Task 3), `PushPayload` (Task 2), `resolveMatchRecipients` (Task 2).
- Produces: `MatchingRepository`'s constructor now takes a 4th positional argument, `PushNotificationRepository`. `matching_providers.dart`'s `matchingRepositoryProvider` passes `ref.watch(pushNotificationRepositoryProvider)` as that argument -- any other code constructing `MatchingRepository` directly (there is none outside the provider and its own tests, and this repository has no unit tests per the untested-Supabase-boundary convention) must be updated to match.

- [ ] **Step 1: No test-first step**

`MatchingRepository` is untested Supabase-boundary code (no existing test file for it). Modify directly; `resolveMatchRecipients`'s own correctness is already covered by Task 2's unit tests.

- [ ] **Step 2: Add l10n keys**

In `app/assets/translations/en.json`, add after the last existing key (before the closing `}`):
```json
  "push_match_title": "New Match",
  "push_match_body": "You have a new match. Tap to view."
```

In `app/assets/translations/ms.json`, same position:
```json
  "push_match_title": "Padanan Baru",
  "push_match_body": "Anda ada padanan baru. Ketik untuk lihat."
```

(Match the exact comma placement of whatever key currently sits last in each file -- follow the same insertion pattern every prior milestone's l10n addition used.)

- [ ] **Step 3: Modify `matching_repository.dart`**

Add the import and constructor parameter:

```dart
import 'package:easy_localization/easy_localization.dart';

import '../notifications/models/push_payload.dart';
import '../notifications/push_notification_repository.dart';
import '../notifications/recipient_resolver.dart';
```

```dart
class MatchingRepository {
  MatchingRepository(
    this._client,
    this._listingRepository,
    this._requirementRepository,
    this._pushNotificationRepository,
  );

  final SupabaseClient _client;
  final ListingRepository _listingRepository;
  final RequirementRepository _requirementRepository;
  final PushNotificationRepository _pushNotificationRepository;
```

Replace `computeAndStoreMatchesForListing`, `computeAndStoreMatchesForRequirement`, and `_store` with:

```dart
  Future<void> computeAndStoreMatchesForListing(Listing listing) async {
    final requirements = await _requirementRepository.fetchBoardRequirements();
    final rows = <Map<String, dynamic>>[];
    final ownerByRequirementId = <String, String>{};
    for (final requirement in requirements) {
      if (requirement.negotiatorId == listing.negotiatorId) continue;
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      rows.add({
        'listing_id': listing.listingId,
        'requirement_id': requirement.requirementId,
        'score': score,
      });
      ownerByRequirementId[requirement.requirementId] = requirement.negotiatorId;
    }
    final insertedRows = await _store(rows);
    final recipients = resolveMatchRecipients(
      insertedRows: insertedRows,
      ownerKey: 'requirement_id',
      ownerNegotiatorIdByKey: ownerByRequirementId,
    );
    for (final recipientId in recipients) {
      await _notifyMatch(recipientId, ownerSide: 'requirement', listingId: listing.listingId, requirementId: null);
    }
  }

  Future<void> computeAndStoreMatchesForRequirement(Requirement requirement) async {
    final listings = await _listingRepository.fetchMarketplaceListings();
    final rows = <Map<String, dynamic>>[];
    final ownerByListingId = <String, String>{};
    for (final listing in listings) {
      if (listing.negotiatorId == requirement.negotiatorId) continue;
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      rows.add({
        'listing_id': listing.listingId,
        'requirement_id': requirement.requirementId,
        'score': score,
      });
      ownerByListingId[listing.listingId] = listing.negotiatorId;
    }
    final insertedRows = await _store(rows);
    final recipients = resolveMatchRecipients(
      insertedRows: insertedRows,
      ownerKey: 'listing_id',
      ownerNegotiatorIdByKey: ownerByListingId,
    );
    for (final recipientId in recipients) {
      await _notifyMatch(recipientId, ownerSide: 'listing', listingId: null, requirementId: requirement.requirementId);
    }
  }

  /// ownerSide/listingId/requirementId describe which screen the
  /// RECIPIENT should land on (their own side of the match), not the side
  /// that was just posted -- see deep_link.dart's deepLinkRouteFor.
  Future<void> _notifyMatch(
    String recipientId, {
    required String ownerSide,
    required String? listingId,
    required String? requirementId,
  }) async {
    try {
      await _pushNotificationRepository.sendPushNotification(PushPayload(
        recipientNegotiatorId: recipientId,
        category: 'match',
        title: 'push_match_title'.tr(),
        body: 'push_match_body'.tr(),
        deepLinkData: {
          'owner_side': ownerSide,
          if (listingId != null) 'listing_id': listingId,
          if (requirementId != null) 'requirement_id': requirementId,
        },
      ));
    } catch (_) {
      // Push delivery is best-effort -- a failure here must never undo or
      // surface as an error for the match that was already stored.
    }
  }

  Future<List<Map<String, dynamic>>> _store(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];
    // .select() after an ignoreDuplicates upsert only returns rows that
    // were genuinely inserted -- PostgREST's RETURNING skips rows the
    // ON CONFLICT DO NOTHING clause suppressed. Without this, every
    // re-computation would re-notify recipients for matches that already
    // existed.
    return _client.from('match').upsert(
          rows,
          onConflict: 'listing_id,requirement_id',
          ignoreDuplicates: true,
        ).select();
  }
```

- [ ] **Step 4: Modify `matching_providers.dart`**

```dart
import '../notifications/notification_providers.dart';
```

```dart
final matchingRepositoryProvider = Provider<MatchingRepository>((ref) {
  return MatchingRepository(
    Supabase.instance.client,
    ref.watch(listingRepositoryProvider),
    ref.watch(requirementRepositoryProvider),
    ref.watch(pushNotificationRepositoryProvider),
  );
});
```

- [ ] **Step 5: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues. No existing test directly instantiates `MatchingRepository` (untested by convention), so this is purely a compile-correctness check for `matching_providers.dart`'s call site.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/matching/matching_repository.dart \
        app/lib/features/matching/matching_providers.dart \
        app/assets/translations/en.json \
        app/assets/translations/ms.json
git commit -m "feat: send push notification on new match, avoid re-notifying on re-computation"
```

---

### Task 6: Wire push into CobrokeRequestRepository

**Files:**
- Modify: `app/lib/features/collaboration/cobroke_request_repository.dart`
- Modify: `app/lib/features/collaboration/cobroke_request_providers.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `PushNotificationRepository` (Task 3), `PushPayload`/`resolveOtherPartyInMatch` (Task 2).
- Produces: `CobrokeRequestRepository`'s constructor now takes a 3rd positional argument, `PushNotificationRepository`.

- [ ] **Step 1: No test-first step**

Same untested-Supabase-boundary rationale as Task 5.

- [ ] **Step 2: Add l10n keys**

`app/assets/translations/en.json`:
```json
  "push_cobroke_request_title": "New Co-Broke Request",
  "push_cobroke_request_body": "Someone wants to co-broke with you. Tap to view."
```

`app/assets/translations/ms.json`:
```json
  "push_cobroke_request_title": "Permintaan Co-Broke Baru",
  "push_cobroke_request_body": "Seseorang mahu co-broke dengan anda. Ketik untuk lihat."
```

- [ ] **Step 3: Modify `cobroke_request_repository.dart`**

```dart
import 'package:easy_localization/easy_localization.dart';

import '../notifications/models/push_payload.dart';
import '../notifications/push_notification_repository.dart';
import '../notifications/recipient_resolver.dart';
```

```dart
class CobrokeRequestRepository {
  CobrokeRequestRepository(this._client, this._listingRepository, this._pushNotificationRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;
  final PushNotificationRepository _pushNotificationRepository;

  Future<void> createRequest({required String matchId, required String initiatorId}) async {
    await _client.from('cobroke_request').insert({
      'match_id': matchId,
      'initiator_id': initiatorId,
    });
    await _notifyNewRequest(matchId: matchId, initiatorId: initiatorId);
  }

  Future<void> _notifyNewRequest({required String matchId, required String initiatorId}) async {
    try {
      final matchRow = await _client
          .from('match')
          .select('listing!inner(negotiator_id), requirement!inner(negotiator_id)')
          .eq('match_id', matchId)
          .single();
      final listingNegotiatorId = (matchRow['listing'] as Map<String, dynamic>)['negotiator_id'] as String;
      final requirementNegotiatorId = (matchRow['requirement'] as Map<String, dynamic>)['negotiator_id'] as String;
      final recipientId = resolveOtherPartyInMatch(
        actorId: initiatorId,
        listingNegotiatorId: listingNegotiatorId,
        requirementNegotiatorId: requirementNegotiatorId,
      );
      if (recipientId == null) return;
      await _pushNotificationRepository.sendPushNotification(PushPayload(
        recipientNegotiatorId: recipientId,
        category: 'cobroke_request',
        title: 'push_cobroke_request_title'.tr(),
        body: 'push_cobroke_request_body'.tr(),
        deepLinkData: const {},
      ));
    } catch (_) {
      // Push delivery is best-effort -- a failure here must never undo or
      // surface as an error for the request that was already created.
    }
  }
```

- [ ] **Step 4: Modify `cobroke_request_providers.dart`**

```dart
import '../notifications/notification_providers.dart';
```

```dart
final cobrokeRequestRepositoryProvider = Provider<CobrokeRequestRepository>((ref) {
  return CobrokeRequestRepository(
    Supabase.instance.client,
    ref.watch(listingRepositoryProvider),
    ref.watch(pushNotificationRepositoryProvider),
  );
});
```

- [ ] **Step 5: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/collaboration/cobroke_request_repository.dart \
        app/lib/features/collaboration/cobroke_request_providers.dart \
        app/assets/translations/en.json \
        app/assets/translations/ms.json
git commit -m "feat: send push notification to the other party on a new co-broke request"
```

---

### Task 7: Wire push into MessageRepository

**Files:**
- Modify: `app/lib/features/collaboration/message_repository.dart`
- Modify: `app/lib/features/collaboration/message_providers.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `PushNotificationRepository` (Task 3), `PushPayload`/`resolveOtherPartyInMatch` (Task 2).
- Produces: `MessageRepository`'s constructor now takes a 3rd positional argument, `PushNotificationRepository`.

- [ ] **Step 1: No test-first step**

Same untested-Supabase-boundary rationale as Tasks 5-6.

- [ ] **Step 2: Add l10n keys**

`app/assets/translations/en.json`:
```json
  "push_message_title": "New Message",
  "push_message_body": "You have a new message. Tap to view."
```

`app/assets/translations/ms.json`:
```json
  "push_message_title": "Mesej Baru",
  "push_message_body": "Anda ada mesej baru. Ketik untuk lihat."
```

- [ ] **Step 3: Modify `message_repository.dart`**

```dart
import 'package:easy_localization/easy_localization.dart';

import '../notifications/models/push_payload.dart';
import '../notifications/push_notification_repository.dart';
import '../notifications/recipient_resolver.dart';
```

```dart
class MessageRepository {
  MessageRepository(this._client, this._listingRepository, this._pushNotificationRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;
  final PushNotificationRepository _pushNotificationRepository;

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
    await _notifyNewMessage(requestId: requestId, senderId: senderId);
  }

  Future<void> _notifyNewMessage({required String requestId, required String senderId}) async {
    try {
      final requestRow = await _client
          .from('cobroke_request')
          .select('match!inner(listing!inner(negotiator_id), requirement!inner(negotiator_id))')
          .eq('request_id', requestId)
          .single();
      final match = requestRow['match'] as Map<String, dynamic>;
      final listingNegotiatorId = (match['listing'] as Map<String, dynamic>)['negotiator_id'] as String;
      final requirementNegotiatorId = (match['requirement'] as Map<String, dynamic>)['negotiator_id'] as String;
      final recipientId = resolveOtherPartyInMatch(
        actorId: senderId,
        listingNegotiatorId: listingNegotiatorId,
        requirementNegotiatorId: requirementNegotiatorId,
      );
      if (recipientId == null) return;
      await _pushNotificationRepository.sendPushNotification(PushPayload(
        recipientNegotiatorId: recipientId,
        category: 'message',
        title: 'push_message_title'.tr(),
        body: 'push_message_body'.tr(),
        deepLinkData: {'request_id': requestId},
      ));
    } catch (_) {
      // Push delivery is best-effort -- a failure here must never undo or
      // surface as an error for the message that was already sent.
    }
  }
```

- [ ] **Step 4: Modify `message_providers.dart`**

```dart
import '../notifications/notification_providers.dart';
```

```dart
final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(
    Supabase.instance.client,
    ref.watch(listingRepositoryProvider),
    ref.watch(pushNotificationRepositoryProvider),
  );
});
```

- [ ] **Step 5: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/collaboration/message_repository.dart \
        app/lib/features/collaboration/message_providers.dart \
        app/assets/translations/en.json \
        app/assets/translations/ms.json
git commit -m "feat: send push notification to the other party on a new message"
```

---

### Task 8: Client bootstrap -- dependencies, Android Gradle, FCM init, listeners, in-app banner

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/android/settings.gradle.kts`
- Modify: `app/android/app/build.gradle.kts`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes: `deepLinkRouteFor`/`shouldSuppressForegroundBanner` (Task 2), `fcmTokenRepositoryProvider` (Task 3), `appRouterProvider` (existing, `app_router.dart`).
- Produces: `RenlyApp` becomes a `ConsumerStatefulWidget` wiring FCM's 3 listener states; nothing later in this plan consumes new symbols from this task (it's the top-level wiring, not a library other code imports).

- [ ] **Step 1: Add dependencies**

```bash
cd app && flutter pub add firebase_core firebase_messaging
```

- [ ] **Step 2: Add the Google Services Gradle plugin**

In `app/android/settings.gradle.kts`, add to the existing `plugins { ... }` block (after the `org.jetbrains.kotlin.android` line):

```kotlin
    id("com.google.gms.google-services") version "4.4.2" apply false
```

In `app/android/app/build.gradle.kts`, add to the existing `plugins { ... }` block (after `id("kotlin-android")`, before the Flutter Gradle Plugin line -- Google Services must apply before Flutter's plugin per its own docs):

```kotlin
    id("com.google.gms.google-services")
```

No other Gradle change is needed -- the `firebase_core`/`firebase_messaging` Flutter plugins already pull in the native Firebase Android SDKs transitively; the Google Services plugin's only job is reading `google-services.json` at build time to generate the config Firebase's SDKs read at runtime.

`google-services.json` itself is a **user-provided file** placed at `app/android/app/google-services.json` during the live Firebase setup walkthrough (Task 9) -- it does not exist yet and is not created by this task. It is already covered by this repo's `.gitignore` (`**/google-services.json`, present since project scaffold).

- [ ] **Step 3: Modify `main.dart`**

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'features/notifications/deep_link.dart';
import 'features/notifications/foreground_suppression.dart';
import 'features/notifications/notification_providers.dart';
```

Add, right after the Stripe init block and before `runApp`:

```dart
  // Optional, same non-crashing guard as Stripe above: a fresh clone with
  // no google-services.json yet must still be able to flutter run for
  // every other feature. Firebase.initializeApp() throws if the config
  // file is missing/malformed -- catch and skip rather than crash.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {
    // No google-services.json yet, or Firebase project not configured --
    // push notifications are simply unavailable this run.
  }
```

Replace the `runApp(...)` call's `RenlyApp()` with `RenlyApp(firebaseReady: firebaseReady)`, then replace the `RenlyApp` class:

```dart
class RenlyApp extends ConsumerStatefulWidget {
  const RenlyApp({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  ConsumerState<RenlyApp> createState() => _RenlyAppState();
}

class _RenlyAppState extends ConsumerState<RenlyApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    if (!widget.firebaseReady) return;
    _registerToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _registerToken());
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _navigateFromMessage(message.data));
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _navigateFromMessage(message.data);
    });
  }

  Future<void> _registerToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await ref.read(fcmTokenRepositoryProvider).registerToken(
          negotiatorId: session.user.id,
          token: token,
        );
  }

  Map<String, String> _stringData(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, value.toString()));

  void _navigateFromMessage(Map<String, dynamic> data) {
    final stringData = _stringData(data);
    final category = stringData['category'] ?? '';
    final route = deepLinkRouteFor(category, stringData);
    ref.read(appRouterProvider).go(route);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final stringData = _stringData(message.data);
    final category = stringData['category'] ?? '';
    final currentLocation = ref.read(appRouterProvider).routerDelegate.currentConfiguration.uri.toString();
    if (shouldSuppressForegroundBanner(category: category, currentRouteLocation: currentLocation, data: stringData)) {
      return;
    }
    final notification = message.notification;
    if (notification == null) return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('${notification.title}: ${notification.body}'),
        action: SnackBarAction(
          label: 'push_banner_view'.tr(),
          onPressed: () => _navigateFromMessage(message.data),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'renly',
      theme: AppTheme.light,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      routerConfig: router,
    );
  }
}
```

`category` must be included in the Edge Function's outbound FCM `data` payload for this to work -- go back to Task 4's `send-push-notification/index.ts` and confirm `deep_link_data` merges in `category` before sending. Amend the Edge Function's send block:

```typescript
            data: { ...(deep_link_data ?? {}), category },
```

(Replace the line `data: deep_link_data ?? {},` from Task 4 with the line above.)

- [ ] **Step 4: Add the banner's l10n key**

`app/assets/translations/en.json`: `"push_banner_view": "View"`
`app/assets/translations/ms.json`: `"push_banner_view": "Lihat"`

- [ ] **Step 5: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues. `flutter test` runs with no Firebase config present -- `firebaseReady` stays `false` in every test harness (no widget test constructs `RenlyApp` directly today), so this must not break anything.

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock \
        app/android/settings.gradle.kts app/android/app/build.gradle.kts \
        app/lib/main.dart \
        app/assets/translations/en.json app/assets/translations/ms.json \
        supabase/functions/send-push-notification/index.ts
git commit -m "feat: wire FCM token registration, listeners, deep-linking, and in-app banner into main.dart"
```

---

### Task 9: README setup section and manual verification pointer

**Files:**
- Modify: `app/README.md`

**Interfaces:**
- Consumes: nothing new -- documentation only.

- [ ] **Step 1: Add the Milestone 15 setup section**

Append to `app/README.md`, after the Milestone 14 section:

```markdown
## Milestone 15 setup (push notifications)

Two Supabase-side steps, plus a Firebase project and Android config the app didn't need before:

1. **Run the migration.** Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0016_fcm_device_token.sql` -> Run. Creates `fcm_device_token` and its 3 RLS policies.
2. **Create a Firebase project** (console.firebase.google.com) for this app -- a separate project from Supabase, free tier is enough. Add an Android app to it using this project's application id, `com.renly.renly` (see `app/android/app/build.gradle.kts`'s `applicationId`). Download the generated `google-services.json` and place it at `app/android/app/google-services.json` (already gitignored -- this file is never committed).
3. **Create a Service Account** for that Firebase project (Firebase console -> Project Settings -> Service Accounts -> Generate new private key), which downloads a JSON file. Set its full contents as an Edge Function secret **in your own terminal**, never pasted into a chat -- same handling as the Stripe secret key/webhook signing secret from Milestone 12:
   ```bash
   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat path/to/downloaded-service-account.json)"
   ```
4. **Deploy the Edge Function:**
   ```bash
   supabase functions deploy send-push-notification
   ```
   No `--no-verify-jwt` needed here -- unlike `stripe-webhook`, this function is only ever called by an already-authenticated app client.

**Manual verification -- requires a Google-Play-image Android emulator or a real device, NOT the plain emulator this project's other pending verifications use.** FCM push delivery does not work without Google Play Services present. See the "Testing approach" section of `docs/superpowers/specs/2026-08-24-renly-push-notifications-design.md` for the full 8-step verification checklist (new match, tap-to-deep-link, preference-off suppression, co-broke request, message delivery in 3 app states, and stale-token self-cleanup).
```

- [ ] **Step 2: No automated test for this step**

Documentation only.

- [ ] **Step 3: Commit**

```bash
git add app/README.md
git commit -m "docs: add Milestone 15 setup section (push notifications)"
```
