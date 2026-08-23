# Subscription Core (Stripe) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a negotiator upgrade to a "Professional" recurring subscription via Stripe (test mode), paid through Stripe's native `PaymentSheet`, with the tier flip driven exclusively by a server-verified Stripe webhook.

**Architecture:** Three new Supabase Edge Functions (Deno) — this project's first ever — talk to the Stripe API using a secret key that never leaves the server. `create-subscription` creates a Stripe Customer/Subscription and returns a PaymentIntent client secret for the Flutter `PaymentSheet`. `stripe-webhook` is the ONLY path that ever writes `subscription_tier` — it verifies Stripe's signature and updates the negotiator row using the Supabase service role (bypassing RLS/grants entirely, since these 4 columns have no client write path at all). `create-portal-session` hands the client a URL to Stripe's hosted billing portal for cancellation/payment-method management. A new `features/subscription/` Flutter module composes all three via `supabase.functions.invoke`, plus a Realtime `.stream()` on the negotiator row (this project's second-ever Realtime usage, after Messaging) so the UI reflects the webhook's tier flip live.

**Tech Stack:** Flutter, Riverpod, supabase_flutter, `flutter_stripe` (new), `url_launcher` (new, currently only transitive), easy_localization (EN/MS), go_router, Deno (Supabase Edge Functions, new), Stripe (new).

## Global Constraints

- `stripe-webhook` MUST be deployed with `--no-verify-jwt`. Supabase's default JWT check runs BEFORE the function body, so without this flag every real Stripe webhook delivery (which carries no Supabase session) gets rejected with a 401 before the handler's own Stripe-signature verification ever executes — the entire tier-flip mechanism would be silently dead, with no client-visible error anywhere in this app. Task reviewer and final reviewer must confirm this flag is present in the deploy command, not assume it.
- The webhook's signature check MUST call `stripe.webhooks.constructEventAsync(body, signature, webhookSecret, undefined, Stripe.createSubtleCryptoProvider())` — the `Stripe.createSubtleCryptoProvider()` argument is REQUIRED in Deno's edge runtime, which has no Node `crypto` module. Omitting it makes every real Stripe webhook delivery fail signature verification. Task reviewer and final reviewer must confirm this exact call shape, not just "a" signature check.
- `0013_subscription.sql`'s 4 new columns (`stripe_customer_id`, `stripe_subscription_id`, `subscription_status`, `current_period_end`) get NO grant statement of any kind to `authenticated` — no `grant update`, ever. They are writable only via the Edge Functions' service-role client (which bypasses grants entirely) and readable via the table's pre-existing default SELECT grant (never revoked, same as `ic_number`/`phone_number`).
- `SubscriptionRepository`/Edge Functions are untested by `flutter test` (Supabase/Edge-Function-calling code, established project convention). `SubscriptionStatus.fromJson` gets a real unit test. `SubscriptionScreen` gets widget tests via provider override.
- `subscriptionStatusProvider` must be `.autoDispose` — this project's pinned Riverpod 2.6.1 does not default to autoDispose (Messaging leaked a Realtime channel from missing this exact modifier once already).
- Every `.when()` error branch renders visible text with a retry action — never `SizedBox.shrink()` (recurring Minor-finding history in Ratings/Settings).
- Missing `STRIPE_PUBLISHABLE_KEY` at app startup must NOT crash the app — every other screen in this app must keep working with zero Stripe configuration present.
- l10n: every new user-facing string needs both an `en.json` and `ms.json` entry.

---

### Task 1: Supabase Migration SQL (0013_subscription.sql)

**Files:**
- Create: `supabase/migrations/0013_subscription.sql`
- Modify: `app/README.md` (append a "Milestone 12 setup (subscription)" section after the Milestone 11 section)

**Interfaces:**
- Consumes: `negotiator` table (from `0001_auth_verification.sql`, `subscription_tier` column already exists and is already locked from client UPDATE).
- Produces: `negotiator.stripe_customer_id`, `.stripe_subscription_id`, `.subscription_status`, `.current_period_end` — used by Tasks 2-4's Edge Functions and Task 6's `SubscriptionRepository`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0013_subscription.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0012.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists stripe_customer_id text;
alter table negotiator add column if not exists stripe_subscription_id text;
alter table negotiator add column if not exists subscription_status text;
alter table negotiator add column if not exists current_period_end timestamptz;

-- Deliberately NO grant statement for these 4 columns, to authenticated or
-- anyone else -- unlike every other "new column" migration in this
-- project, these are never client-writable at all, not even narrowly.
-- They are written ONLY by the stripe-webhook Edge Function using the
-- Supabase service role key, which bypasses table grants and RLS entirely
-- (the established pattern for privileged server-side writes on this
-- table, alongside subscription_tier itself -- see 0002_rls_hardening.sql
-- for that column's own "never client-writable" precedent). SELECT
-- access for these 4 columns comes from the table's pre-existing default
-- grant (never revoked in this migration set, same as ic_number/
-- phone_number) -- a negotiator can read their own subscription details,
-- just never write them directly.
```

- [ ] **Step 2: Append README setup section**

Read `app/README.md`, find the "Milestone 11 setup (settings)" section, and append immediately after it:

```markdown
## Milestone 12 setup (subscription)

Run `supabase/migrations/0013_subscription.sql` in the Supabase SQL Editor after 0001-0012. This adds 4 nullable columns to `negotiator` for Stripe subscription state -- no grant statement of any kind is added for them, ever (unlike every other new-column migration in this project). They are written only by the `stripe-webhook` Edge Function using the Supabase service role key, which bypasses grants and RLS entirely.

This milestone also requires deploying 3 new Supabase Edge Functions and configuring a Stripe account (test mode) -- see the Subscription Core design doc (`docs/superpowers/specs/2026-08-24-renly-subscription-core-design.md`) for the full manual setup sequence (Stripe account, Price creation, secrets, Edge Function deployment with `--no-verify-jwt` on `stripe-webhook`, webhook registration). This is NOT just a SQL paste-and-run step like every prior migration -- the migration alone does nothing useful until the Edge Functions are deployed and the webhook is registered.
```

- [ ] **Step 3: Verify with grep**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^alter table negotiator add column" supabase/migrations/0013_subscription.sql
grep -c "^grant" supabase/migrations/0013_subscription.sql
```
Expected: `4`, `0` (the `0` is the whole point of this task -- no grant statement anywhere).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0013_subscription.sql app/README.md
git commit -m "feat: add subscription migration with zero client-write grant"
```

---

### Task 2: Edge Function — create-subscription

**Files:**
- Create: `supabase/functions/create-subscription/index.ts`

**Interfaces:**
- Consumes: `negotiator` table (Task 1's new columns + existing `full_name`), Stripe API.
- Produces: an HTTP endpoint returning `{ client_secret: string }`, consumed by Task 6's `SubscriptionRepository.createSubscription()`.

This is the first Supabase Edge Function in this project — there is no existing precedent to follow, no `flutter test` coverage applies, and no automated test exists for this task. Verification is manual, via the Supabase CLI's local function server and `curl`.

- [ ] **Step 1: Write the function**

```typescript
// supabase/functions/create-subscription/index.ts
import Stripe from "https://esm.sh/stripe@17.4.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-11-20.acacia",
  httpClient: Stripe.createFetchHttpClient(),
});

const PROFESSIONAL_PRICE_ID = Deno.env.get("STRIPE_PROFESSIONAL_PRICE_ID")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Scoped to the caller's own JWT -- only used to identify who is
    // calling, never to read/write data (that's the service-role client
    // below, since these columns have no client grant at all).
    const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await callerClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: negotiator, error: fetchError } = await adminClient
      .from("negotiator")
      .select("stripe_customer_id, full_name")
      .eq("negotiator_id", user.id)
      .single();
    if (fetchError || !negotiator) {
      return new Response(JSON.stringify({ error: "Negotiator not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    let customerId = negotiator.stripe_customer_id as string | null;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: negotiator.full_name,
        metadata: { negotiator_id: user.id },
      });
      customerId = customer.id;
      await adminClient
        .from("negotiator")
        .update({ stripe_customer_id: customerId })
        .eq("negotiator_id", user.id);
    }

    const subscription = await stripe.subscriptions.create({
      customer: customerId,
      items: [{ price: PROFESSIONAL_PRICE_ID }],
      payment_behavior: "default_incomplete",
      payment_settings: { save_default_payment_method: "on_subscription" },
      expand: ["latest_invoice.payment_intent"],
    });

    await adminClient
      .from("negotiator")
      .update({
        stripe_subscription_id: subscription.id,
        subscription_status: subscription.status,
      })
      .eq("negotiator_id", user.id);

    const invoice = subscription.latest_invoice as Stripe.Invoice;
    const paymentIntent = invoice.payment_intent as Stripe.PaymentIntent;

    if (!paymentIntent?.client_secret) {
      return new Response(JSON.stringify({ error: "Stripe did not return a client secret" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ client_secret: paymentIntent.client_secret }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 2: Deploy and verify locally**

This requires the Supabase CLI (`brew install supabase/tap/supabase` if not already installed) and a Stripe test-mode secret key + a test Price id already created in the Stripe dashboard (see the design doc's Manual Setup section — this must be done before this step is runnable).

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
supabase functions serve create-subscription --env-file supabase/.env.local
```

(`supabase/.env.local` — git-ignored, not created by this task if it doesn't exist yet — must contain `STRIPE_SECRET_KEY`, `STRIPE_PROFESSIONAL_PRICE_ID`, and the CLI auto-supplies `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY` for local serving.)

In a second terminal, get a real user JWT (e.g. from a logged-in session's local storage, or `supabase auth` tooling) and call:

```bash
curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/create-subscription' \
  --header 'Authorization: Bearer <a real negotiator JWT>'
```

Expected: HTTP 200 with a JSON body `{"client_secret":"pi_..._secret_..."}`. If a Stripe Customer didn't already exist for this negotiator, confirm one now exists in the Stripe dashboard (test mode) and that `negotiator.stripe_customer_id` was written (check via the SQL Editor).

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/create-subscription/index.ts
git commit -m "feat: add create-subscription Edge Function"
```

---

### Task 3: Edge Function — stripe-webhook

**Files:**
- Create: `supabase/functions/stripe-webhook/index.ts`

**Interfaces:**
- Consumes: `negotiator` table (Task 1's new columns), Stripe webhook events.
- Produces: the ONLY path that writes `subscription_tier`/`subscription_status`/`current_period_end` — this is what Task 8's `SubscriptionScreen` waits on via Task 6's Realtime stream.

This is the highest-risk task in the plan — both Global Constraints landmines (`--no-verify-jwt`, `Stripe.createSubtleCryptoProvider()`) live here. No automated test applies; verification is manual via the Stripe CLI.

- [ ] **Step 1: Write the function**

```typescript
// supabase/functions/stripe-webhook/index.ts
import Stripe from "https://esm.sh/stripe@17.4.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-11-20.acacia",
  httpClient: Stripe.createFetchHttpClient(),
});

const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  const signature = req.headers.get("Stripe-Signature");
  const body = await req.text();

  if (!signature) {
    return new Response("Missing Stripe-Signature header", { status: 400 });
  }

  let event: Stripe.Event;
  try {
    // Stripe.createSubtleCryptoProvider() is REQUIRED here -- Deno's edge
    // runtime has no Node `crypto` module, and constructEventAsync's
    // default crypto provider assumes one is present. Omitting this
    // argument makes signature verification throw on every real Stripe
    // delivery, not just some -- this was verified against Stripe's own
    // Deno integration guide, not guessed.
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      WEBHOOK_SECRET,
      undefined,
      Stripe.createSubtleCryptoProvider(),
    );
  } catch (err) {
    return new Response(`Webhook signature verification failed: ${(err as Error).message}`, {
      status: 400,
    });
  }

  try {
    switch (event.type) {
      case "customer.subscription.updated":
      case "customer.subscription.deleted": {
        const subscription = event.data.object as Stripe.Subscription;
        const tier = ["active", "trialing"].includes(subscription.status) ? "professional" : "free";
        await adminClient
          .from("negotiator")
          .update({
            subscription_status: subscription.status,
            subscription_tier: tier,
            current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
          })
          .eq("stripe_customer_id", subscription.customer as string);
        break;
      }
      case "invoice.payment_failed": {
        const invoice = event.data.object as Stripe.Invoice;
        // Tier deliberately stays 'professional' here -- Stripe runs its
        // own retry/dunning schedule and will fire
        // customer.subscription.updated with a 'canceled'/'unpaid' status
        // if it eventually gives up, which the branch above already
        // handles. This app does not invent its own grace-period logic.
        await adminClient
          .from("negotiator")
          .update({ subscription_status: "past_due" })
          .eq("stripe_customer_id", invoice.customer as string);
        break;
      }
      default:
        // Unhandled event types are acknowledged (200) but ignored --
        // Stripe retries on non-2xx, and there is nothing to retry for
        // an event this handler doesn't act on.
        break;
    }
    return new Response(JSON.stringify({ received: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 2: Deploy with JWT verification disabled**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
supabase functions deploy stripe-webhook --no-verify-jwt
```

Confirm the deploy output does not mention JWT verification being active for this function. (`create-subscription` and `create-portal-session` are deployed WITHOUT this flag in their own tasks — only `stripe-webhook` needs it.)

- [ ] **Step 3: Verify locally with the Stripe CLI**

Requires the Stripe CLI (`brew install stripe/stripe-cli/stripe`, then `stripe login`).

```bash
supabase functions serve stripe-webhook --env-file supabase/.env.local
```

In a second terminal:
```bash
stripe listen --forward-to http://127.0.0.1:54321/functions/v1/stripe-webhook
```
Copy the webhook signing secret it prints (`whsec_...`) into `supabase/.env.local`'s `STRIPE_WEBHOOK_SECRET` for this local run, restart `functions serve`. In a third terminal:
```bash
stripe trigger customer.subscription.updated
```
Expected: the `functions serve` terminal logs a 200 response, and the `stripe listen` terminal shows the event was delivered successfully (no signature error). This confirms the signature verification and event handling both work end to end before deploying to production.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/stripe-webhook/index.ts
git commit -m "feat: add stripe-webhook Edge Function (tier flip, no-verify-jwt)"
```

---

### Task 4: Edge Function — create-portal-session

**Files:**
- Create: `supabase/functions/create-portal-session/index.ts`

**Interfaces:**
- Consumes: `negotiator.stripe_customer_id` (Task 1/2).
- Produces: an HTTP endpoint returning `{ url: string }`, consumed by Task 6's `SubscriptionRepository.createPortalSession()`.

- [ ] **Step 1: Write the function**

```typescript
// supabase/functions/create-portal-session/index.ts
import Stripe from "https://esm.sh/stripe@17.4.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-11-20.acacia",
  httpClient: Stripe.createFetchHttpClient(),
});

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await callerClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: negotiator, error: fetchError } = await adminClient
      .from("negotiator")
      .select("stripe_customer_id")
      .eq("negotiator_id", user.id)
      .single();

    if (fetchError || !negotiator?.stripe_customer_id) {
      return new Response(JSON.stringify({ error: "No Stripe customer for this negotiator" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    const session = await stripe.billingPortal.sessions.create({
      customer: negotiator.stripe_customer_id as string,
    });

    return new Response(JSON.stringify({ url: session.url }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 2: Deploy and verify locally**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
supabase functions serve create-portal-session --env-file supabase/.env.local
```

```bash
curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/create-portal-session' \
  --header 'Authorization: Bearer <a real negotiator JWT with an existing stripe_customer_id>'
```

Expected: HTTP 200 with `{"url":"https://billing.stripe.com/p/session/..."}`. Opening that URL in a browser should show Stripe's test-mode Customer Portal.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/create-portal-session/index.ts
git commit -m "feat: add create-portal-session Edge Function"
```

---

### Task 5: SubscriptionStatus model + unit test

**Files:**
- Create: `app/lib/features/subscription/models/subscription_status.dart`
- Test: `app/test/features/subscription/models/subscription_status_test.dart`

**Interfaces:**
- Consumes: nothing (plain data class).
- Produces: `SubscriptionStatus` class with `tier` (`String`), `status` (`String?`), `currentPeriodEnd` (`DateTime?`), and `SubscriptionStatus.fromJson(Map<String, dynamic>)` — used by Task 6's `SubscriptionRepository`/providers and Task 8's `SubscriptionScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/subscription/models/subscription_status_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/subscription/models/subscription_status.dart';

void main() {
  group('SubscriptionStatus.fromJson', () {
    test('parses a professional subscription with all fields present', () {
      final status = SubscriptionStatus.fromJson({
        'subscription_tier': 'professional',
        'subscription_status': 'active',
        'current_period_end': '2026-09-24T10:00:00.000Z',
      });

      expect(status.tier, 'professional');
      expect(status.status, 'active');
      expect(status.currentPeriodEnd, DateTime.parse('2026-09-24T10:00:00.000Z'));
    });

    test('parses a free negotiator with null subscription fields', () {
      final status = SubscriptionStatus.fromJson({
        'subscription_tier': 'free',
        'subscription_status': null,
        'current_period_end': null,
      });

      expect(status.tier, 'free');
      expect(status.status, isNull);
      expect(status.currentPeriodEnd, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/subscription/models/ -v`
Expected: FAIL — `Error: Couldn't resolve the package 'renly'` / file not found.

- [ ] **Step 3: Write the model**

```dart
// app/lib/features/subscription/models/subscription_status.dart
/// A read-only view of one negotiator's subscription state. `tier` is the
/// only field that gates anything (Sub-milestone B reads this, not
/// `status`/`currentPeriodEnd`) -- the other two are display-only,
/// written verbatim from Stripe's own vocabulary by the stripe-webhook
/// Edge Function, never interpreted client-side.
class SubscriptionStatus {
  final String tier;
  final String? status;
  final DateTime? currentPeriodEnd;

  const SubscriptionStatus({required this.tier, this.status, this.currentPeriodEnd});

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final rawPeriodEnd = json['current_period_end'] as String?;
    return SubscriptionStatus(
      tier: json['subscription_tier'] as String,
      status: json['subscription_status'] as String?,
      currentPeriodEnd: rawPeriodEnd == null ? null : DateTime.parse(rawPeriodEnd),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/subscription/models/ -v`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/subscription/models/ app/test/features/subscription/models/
git commit -m "feat: add SubscriptionStatus model"
```

---

### Task 6: SubscriptionRepository + subscription_providers.dart

**Files:**
- Create: `app/lib/features/subscription/subscription_repository.dart`
- Create: `app/lib/features/subscription/subscription_providers.dart`

**Interfaces:**
- Consumes: `SubscriptionStatus` (Task 5), `authStateProvider` (`app/lib/features/auth/auth_providers.dart`), Tasks 2-4's Edge Functions.
- Produces: `SubscriptionRepository` with `createSubscription`, `createPortalSession`, `subscriptionStream`; `subscriptionRepositoryProvider`, `currentNegotiatorIdProvider` (this file's own copy), `subscriptionStatusProvider = StreamProvider.autoDispose<SubscriptionStatus>` — used by Task 8's `SubscriptionScreen`.

- [ ] **Step 1: Write the repository**

```dart
// app/lib/features/subscription/subscription_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/subscription_status.dart';

/// The only file in this app that talks to Supabase for the subscription
/// feature. `createSubscription`/`createPortalSession` call Edge
/// Functions (the only privileged-write path for the 4 new columns on
/// `negotiator` -- no direct client UPDATE exists for any of them, unlike
/// every other repository in this codebase). `subscriptionStream` is a
/// plain read, same shape as MessageRepository's Realtime precedent.
class SubscriptionRepository {
  SubscriptionRepository(this._client);

  final SupabaseClient _client;

  Future<String> createSubscription() async {
    final response = await _client.functions.invoke('create-subscription');
    final clientSecret = (response.data as Map<String, dynamic>?)?['client_secret'] as String?;
    if (clientSecret == null) {
      throw StateError('create-subscription did not return a client_secret.');
    }
    return clientSecret;
  }

  Future<String> createPortalSession() async {
    final response = await _client.functions.invoke('create-portal-session');
    final url = (response.data as Map<String, dynamic>?)?['url'] as String?;
    if (url == null) {
      throw StateError('create-portal-session did not return a url.');
    }
    return url;
  }

  /// Live-updating subscription state for one negotiator -- a single row
  /// filter, so there's no cross-source sort-order concern the way
  /// MessageRepository.messagesStream has to guard against (that lesson
  /// only applies when merging an ordered multi-row history with live
  /// inserts; this is always exactly one row).
  Stream<SubscriptionStatus> subscriptionStream(String negotiatorId) {
    return _client
        .from('negotiator')
        .stream(primaryKey: ['negotiator_id'])
        .eq('negotiator_id', negotiatorId)
        .map((rows) => SubscriptionStatus.fromJson(rows.first));
  }
}
```

- [ ] **Step 2: Write the providers**

```dart
// app/lib/features/subscription/subscription_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'models/subscription_status.dart';
import 'subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// autoDispose is REQUIRED, not the default, in this project's pinned
/// Riverpod version (2.6.1) -- without it, popping SubscriptionScreen
/// would leak the underlying Realtime channel for the rest of the app's
/// process lifetime, the same class of bug Messaging's final review
/// found and fixed once already.
final subscriptionStatusProvider = StreamProvider.autoDispose<SubscriptionStatus>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    return Stream.error(StateError('No authenticated negotiator.'));
  }
  return ref.watch(subscriptionRepositoryProvider).subscriptionStream(negotiatorId);
});
```

- [ ] **Step 3: Verify it compiles**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze lib/features/subscription/`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/subscription/subscription_repository.dart app/lib/features/subscription/subscription_providers.dart
git commit -m "feat: add SubscriptionRepository and subscription providers"
```

---

### Task 7: flutter_stripe + url_launcher dependencies, Stripe init, .env.example

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/main.dart`
- Modify: `app/.env.example`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Stripe` (from `flutter_stripe`) initialized (or gracefully skipped) at app startup, `url_launcher` available as a direct dependency — used by Task 8's `SubscriptionScreen`.

- [ ] **Step 1: Add dependencies**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
/Users/unxpected/Development/flutter/bin/flutter pub add flutter_stripe url_launcher
```

This resolves and pins current compatible versions automatically into `pubspec.yaml`/`pubspec.lock` — do not hand-edit version numbers.

- [ ] **Step 2: Add STRIPE_PUBLISHABLE_KEY to .env.example**

Modify `app/.env.example` from:
```
# Copy this file to app/.env and fill in your actual Supabase project values.
# app/.env is git-ignored — never commit real credentials.
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```
to:
```
# Copy this file to app/.env and fill in your actual Supabase project values.
# app/.env is git-ignored — never commit real credentials.
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
# Optional -- only needed to test the Subscription screen. The app runs
# fine without this set; the Subscription screen's payment flow will
# simply fail if a user tries to upgrade with no key configured.
STRIPE_PUBLISHABLE_KEY=pk_test_your-key-here
```

- [ ] **Step 3: Initialize Stripe in main.dart, without crashing on a missing key**

Modify `app/lib/main.dart` from:
```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final supabaseConfig = SupabaseConfig.fromEnvironment(dotenv.env);
  await Supabase.initialize(
    url: supabaseConfig.url,
    publishableKey: supabaseConfig.anonKey,
  );

  runApp(
```
to:
```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final supabaseConfig = SupabaseConfig.fromEnvironment(dotenv.env);
  await Supabase.initialize(
    url: supabaseConfig.url,
    publishableKey: supabaseConfig.anonKey,
  );

  // Optional: every other screen in this app works with zero Stripe
  // configuration. Only the Subscription screen's upgrade flow needs
  // this -- a missing key must never crash app startup for everyone
  // else.
  final stripePublishableKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];
  if (stripePublishableKey != null && stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = stripePublishableKey;
    await Stripe.instance.applySettings();
  }

  runApp(
```

(The rest of `main.dart` — the `runApp(...)` block and `RenlyApp` class — stays unchanged.)

- [ ] **Step 4: Verify it compiles and existing tests still pass**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze
flutter test
```
Expected: `No issues found!`, and the full existing suite still passes (this task touches no test-covered logic, but confirms the new dependency didn't break anything).

- [ ] **Step 5: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/.env.example app/lib/main.dart
git commit -m "feat: add flutter_stripe and url_launcher dependencies, init Stripe at startup"
```

---

### Task 8: SubscriptionScreen + widget tests

**Files:**
- Create: `app/lib/features/subscription/subscription_screen.dart`
- Test: `app/test/features/subscription/subscription_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `subscriptionStatusProvider`, `currentNegotiatorIdProvider`, `subscriptionRepositoryProvider` (Task 6), `SubscriptionStatus` (Task 5), `flutter_stripe`'s `Stripe`/`SetupPaymentSheetParameters`, `url_launcher`'s `launchUrl` (Task 7).
- Produces: `SubscriptionScreen` widget, used by Task 9's router wiring.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"settings_help_row_subtitle": "Support, FAQ, and contact"` (currently the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "settings_help_row_subtitle": "Support, FAQ, and contact",
  "subscription_title": "Subscription",
  "subscription_free_tier_label": "Free Plan",
  "subscription_professional_tier_label": "Professional Plan",
  "subscription_upgrade_button": "Upgrade to Professional",
  "subscription_manage_button": "Manage Subscription",
  "subscription_renews_on_label": "Renews on",
  "subscription_status_past_due": "Payment past due",
  "subscription_processing": "Processing your upgrade...",
  "subscription_processing_timeout": "This is taking longer than expected.",
  "subscription_refresh_button": "Refresh"
```

In `app/assets/translations/ms.json`, find the line `"settings_help_row_subtitle": "Sokongan, soalan lazim, dan hubungi"` (currently the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "settings_help_row_subtitle": "Sokongan, soalan lazim, dan hubungi",
  "subscription_title": "Langganan",
  "subscription_free_tier_label": "Pelan Percuma",
  "subscription_professional_tier_label": "Pelan Profesional",
  "subscription_upgrade_button": "Naik Taraf ke Profesional",
  "subscription_manage_button": "Urus Langganan",
  "subscription_renews_on_label": "Diperbaharui pada",
  "subscription_status_past_due": "Pembayaran tertunggak",
  "subscription_processing": "Memproses naik taraf anda...",
  "subscription_processing_timeout": "Ini mengambil masa lebih lama dari dijangka.",
  "subscription_refresh_button": "Muat Semula"
```

- [ ] **Step 2: Write the failing test**

```dart
// app/test/features/subscription/subscription_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/subscription/models/subscription_status.dart';
import 'package:renly/features/subscription/subscription_providers.dart';
import 'package:renly/features/subscription/subscription_screen.dart';

Widget _wrap(GoRouter router, {SubscriptionStatus? status, Object? error}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      if (error != null)
        subscriptionStatusProvider.overrideWith((ref) => Stream.error(error))
      else
        subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(status ?? const SubscriptionStatus(tier: 'free')),
        ),
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

  testWidgets('shows Upgrade button for a free-tier negotiator', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SubscriptionScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Free Plan'), findsOneWidget);
    expect(find.text('Upgrade to Professional'), findsOneWidget);
    expect(find.text('Manage Subscription'), findsNothing);
  });

  testWidgets('shows Manage Subscription and renewal date for a professional negotiator', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SubscriptionScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      status: SubscriptionStatus(
        tier: 'professional',
        status: 'active',
        currentPeriodEnd: DateTime(2026, 9, 24),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Professional Plan'), findsOneWidget);
    expect(find.text('Manage Subscription'), findsOneWidget);
    expect(find.text('Upgrade to Professional'), findsNothing);
  });

  testWidgets('shows visible error text on load failure, not a blank screen', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SubscriptionScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, error: StateError('boom')));
    await tester.pumpAndSettle();

    expect(find.text('listing_error_generic'.tr()), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/subscription/subscription_screen_test.dart -v`
Expected: FAIL — `subscription_screen.dart` not found.

- [ ] **Step 4: Write the screen**

```dart
// app/lib/features/subscription/subscription_screen.dart
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/subscription_status.dart';
import 'subscription_providers.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _submitting = false;
  String? _submitError;
  bool _upgradeProcessing = false;
  bool _processingTimedOut = false;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _upgrade() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final clientSecret = await ref.read(subscriptionRepositoryProvider).createSubscription();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'renly',
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      setState(() {
        _upgradeProcessing = true;
        _processingTimedOut = false;
      });
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (mounted) setState(() => _processingTimedOut = true);
      });
    } on StripeException catch (e) {
      if (mounted) setState(() => _submitError = e.error.localizedMessage ?? 'listing_error_generic'.tr());
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _manageSubscription() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final url = await ref.read(subscriptionRepositoryProvider).createPortalSession();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _refresh() {
    _timeoutTimer?.cancel();
    setState(() {
      _upgradeProcessing = false;
      _processingTimedOut = false;
    });
    ref.invalidate(subscriptionStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen (not a direct field mutation during build) is the
    // correct Riverpod way to react to a provider change with a side
    // effect (setState) -- mutating _upgradeProcessing directly inside
    // build() would only happen to work here because a rebuild was
    // already in progress, and would silently stop working if this
    // screen's build ever became conditionally skipped for any reason.
    ref.listen<AsyncValue<SubscriptionStatus>>(subscriptionStatusProvider, (previous, next) {
      if (_upgradeProcessing && next.valueOrNull?.tier == 'professional') {
        _timeoutTimer?.cancel();
        setState(() {
          _upgradeProcessing = false;
          _processingTimedOut = false;
        });
      }
    });

    final statusAsync = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text('subscription_title'.tr())),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('listing_error_generic'.tr()),
              TextButton(
                onPressed: () => ref.invalidate(subscriptionStatusProvider),
                child: Text('agreement_retry'.tr()),
              ),
            ],
          ),
        ),
        data: (status) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_upgradeProcessing) ...[
                Text('subscription_processing'.tr()),
                const SizedBox(height: 12),
                if (!_processingTimedOut)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Text('subscription_processing_timeout'.tr()),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _refresh, child: Text('subscription_refresh_button'.tr())),
                ],
              ] else if (status.tier == 'professional') ...[
                Text('subscription_professional_tier_label'.tr(), style: Theme.of(context).textTheme.titleLarge),
                if (status.status == 'past_due') ...[
                  const SizedBox(height: 8),
                  Text('subscription_status_past_due'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (status.currentPeriodEnd != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${'subscription_renews_on_label'.tr()}: ${status.currentPeriodEnd!.day}/${status.currentPeriodEnd!.month}/${status.currentPeriodEnd!.year}',
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _manageSubscription,
                  child: Text('subscription_manage_button'.tr()),
                ),
              ] else ...[
                Text('subscription_free_tier_label'.tr(), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _upgrade,
                  child: Text('subscription_upgrade_button'.tr()),
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 8),
                Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/subscription/subscription_screen_test.dart -v`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/subscription/subscription_screen.dart app/test/features/subscription/subscription_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add SubscriptionScreen"
```

---

### Task 9: Wire Subscription row into ProfileScreen + router + l10n + tests + mandatory manual verification

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/test/features/profile/profile_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `SubscriptionScreen` (Task 8).
- Produces: `/settings/subscription` route; a 5th row on `ProfileScreen`'s existing "App Settings" `Card`.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"subscription_refresh_button": "Refresh"` (now the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "subscription_refresh_button": "Refresh",
  "settings_subscription_row_title": "Subscription",
  "settings_subscription_row_subtitle": "Manage your plan and billing"
```

In `app/assets/translations/ms.json`, find the line `"subscription_refresh_button": "Muat Semula"` (now the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "subscription_refresh_button": "Muat Semula",
  "settings_subscription_row_title": "Langganan",
  "settings_subscription_row_subtitle": "Urus pelan dan bil anda"
```

- [ ] **Step 2: Write the failing test**

`app/test/features/profile/profile_screen_test.dart` already has a `_wrap(GoRouter router, {Profile? profile, (int, int)? counts, List<RatingCandidate>? ratings})` helper (confirmed by reading the file directly this session) — reuse it as-is. Add this test inside the existing `main()` block, after the last `testWidgets` (`'renders the 4 settings rows and navigates to each on tap'`, added by the Settings milestone), before the closing `}` of `main()`:

```dart
  testWidgets('renders the Subscription row and navigates to it on tap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings/subscription', builder: (context, state) => const Text('subscription screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Subscription'), findsOneWidget);

    await tester.ensureVisible(find.text('Subscription'));
    await tester.tap(find.text('Subscription'));
    await tester.pumpAndSettle();
    expect(find.text('subscription screen'), findsOneWidget);
  });
```

(`tester.ensureVisible` is included proactively — Task 7 of the Settings milestone found that a 5th/later row in this same `Card` can render off the default 800x600 test viewport, causing `tester.tap` to miss. Using it here avoids re-discovering that bug.)

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/profile_screen_test.dart -v`
Expected: FAIL — no widget with text 'Subscription' found.

- [ ] **Step 4: Add the Subscription row to ProfileScreen**

In `app/lib/features/profile/profile_screen.dart`, find this exact existing block (the Help `ListTile`, immediately followed by the `Column`'s closing brackets):

```dart
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: Text('settings_help_row_title'.tr()),
                        subtitle: Text('settings_help_row_subtitle'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/help'),
                      ),
                    ],
                  ),
                ),
```

Replace it with (the Help `ListTile` unchanged, a new Subscription `ListTile` added after it, the closing brackets unchanged):

```dart
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: Text('settings_help_row_title'.tr()),
                        subtitle: Text('settings_help_row_subtitle'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/help'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.workspace_premium),
                        title: Text('settings_subscription_row_title'.tr()),
                        subtitle: Text('settings_subscription_row_subtitle'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/subscription'),
                      ),
                    ],
                  ),
                ),
```

This stays inside the SAME existing "App Settings" `Card` — no new `Card`, just a 5th `ListTile`.

- [ ] **Step 5: Add the route to app_router.dart**

In `app/lib/core/router/app_router.dart`, add this import as the LAST import in the alphabetically-ordered block (after `import '../../features/settings/privacy_screen.dart';`):

```dart
import '../../features/subscription/subscription_screen.dart';
```

After the `GoRoute(path: '/settings/help', builder: (context, state) => const HelpScreen())` line, before the closing `],` of the `routes:` list, add:

```dart
      GoRoute(path: '/settings/subscription', builder: (context, state) => const SubscriptionScreen()),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/profile_screen_test.dart -v`
Expected: PASS (all existing tests plus the new one).

- [ ] **Step 7: Run full suite and analyze**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test
flutter analyze
```
Expected: all tests pass (real count — confirm from actual output, do not estimate), `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/lib/core/router/app_router.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: wire Subscription row into ProfileScreen and router"
```

- [ ] **Step 9: Mandatory manual end-to-end verification (not automated — this is the real gate for this entire milestone)**

With Tasks 1-9 all deployed (migration run, all 3 Edge Functions deployed, webhook registered in the Stripe dashboard per the design doc's Manual Setup section, `STRIPE_PUBLISHABLE_KEY` set in a real `.env`):

1. Log in to the app as a real (free-tier) negotiator, open Profile > App Settings > Subscription.
2. Confirm the Free Plan state renders with an "Upgrade to Professional" button.
3. Tap it, complete the `PaymentSheet` with Stripe's test card `4242 4242 4242 4242`, any future expiry, any CVC.
4. Confirm the "processing" state appears, and — WITHOUT any manual refresh or app restart — the screen flips to the Professional Plan state within a few seconds (this proves the Realtime stream + webhook path both work end to end, not just that the payment itself succeeded).
5. Confirm `negotiator.subscription_tier` shows `'professional'` directly in the Supabase Table Editor, and that this was NEVER set via a client-visible write path (the point of the whole design).
6. Tap "Manage Subscription", confirm Stripe's hosted Customer Portal opens in the browser.
7. In the portal, cancel the subscription (test mode, no real consequence).
8. Return to the app, confirm the screen (after a manual refresh if the Realtime event was missed, or automatically if not) flips back to the Free Plan state.

This step has no automated equivalent — it is the actual proof that 3 separately-deployed Edge Functions, a webhook registration, and a Realtime subscription all cooperate correctly, which nothing in Tasks 1-9's individual test suites can verify in combination.

---

## Self-Review Notes

- **Spec coverage:** all design doc sections covered — migration (Task 1), all 3 Edge Functions (Tasks 2-4) with both Global Constraints landmines addressed explicitly in Task 3, model/repository/providers (Tasks 5-6), dependencies + Stripe init (Task 7), screen (Task 8), ProfileScreen/router wiring + mandatory manual verification (Task 9).
- **Placeholder scan:** no TBD/TODO; every Edge Function task has complete, real Deno TypeScript; every Dart task has complete, real code; every test has real assertions; manual-verification steps (Tasks 2-4, 9) have concrete numbered instructions, not "test appropriately."
- **Type consistency:** `SubscriptionStatus.tier`/`status`/`currentPeriodEnd` field names and JSON keys are identical across Task 5 (definition), Task 6 (repository's `.map()`), and Task 8 (screen's `status.tier`/`.status`/`.currentPeriodEnd` reads) — verified by re-reading each task's code side by side while writing this plan. `createSubscription`/`createPortalSession`/`subscriptionStream` method names and return types match between Task 6's definition and Task 8's call sites.
