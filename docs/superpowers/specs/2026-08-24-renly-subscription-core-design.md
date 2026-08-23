# renly — Subscription Core (Stripe) Design

## Goal

Let a negotiator upgrade to a "Professional" subscription tier via a real (test-mode) Stripe recurring subscription, paid through Stripe's native `PaymentSheet`, with the tier flip driven exclusively by a server-verified Stripe webhook — never by the client reporting success.

This is Sub-milestone A of the Subscription/Billing feature (proposal build-order step 6, "Subscription tiers + Google Play Billing gate"). Sub-milestone B (tier-gating enforcement — the Free-tier listing/requirement cap) is a separate design/plan cycle, built after this one lands, since it depends on `subscription_tier` being genuinely flippable end to end.

## Source of truth

The original MVP design doc (`docs/superpowers/specs/2026-08-16-renly-mvp-design.md`) names "Google Play Billing" as the payment mechanism. This build deliberately uses **Stripe instead**, decided during brainstorm: this is a coursework/FYP project, not a commercial Play Store release, so there is no requirement to use Play Billing's in-app purchase system — Stripe's test mode gives a fully real (if not production-charging) payment flow without needing a Google Play Console account, a signed release build, or an internal-testing-track app listing, all of which this project has never set up and which cannot be exercised on a bare Android emulator the way every other milestone has been.

`negotiator.subscription_tier` already exists (`0001_auth_verification.sql:25-26`, `text not null default 'free' check (subscription_tier in ('free', 'professional'))`) and is already locked from client UPDATE (`0002_rls_hardening.sql`) with an explicit comment that it "must only ever be set via" a privileged path. This design fulfils that existing constraint — the tier is flipped only by the webhook handler, which runs with the Supabase service role, never by an authenticated client PATCH.

## Architecture

Three new Supabase Edge Functions (Deno) — the first use of Edge Functions anywhere in this project (every prior privileged server-side action used a Postgres `security definer` function instead; Edge Functions are necessary here because talking to the Stripe API requires an HTTP client and a secret API key, which can't live in Postgres SQL). A new `features/subscription/` Flutter module composes them. `flutter_stripe` (new dependency) supplies the native `PaymentSheet` widget for card entry — Stripe's SDK, not a hand-rolled card form, so no PCI-scope code is ever written in this app.

```
Flutter app                         Supabase Edge Functions              Stripe
------------                        ------------------------              ------
SubscriptionScreen
  "Upgrade" tap
    -> create-subscription  ---------->  create/reuse Customer
                                          create Subscription
                                          (payment_behavior: default_incomplete)
                                     <----  client_secret
  PaymentSheet.confirm(client_secret) ---------------------------------->  charge (test card)
                                                                            emits webhook event
                                     stripe-webhook  <--------------------  customer.subscription.*
                                       verify signature                    invoice.payment_failed
                                       update negotiator row (final-review fix round):
                                       - grant (tier -> professional): always applies,
                                         writes subscription_tier/status/current_period_end
                                         AND claims stripe_subscription_id as current
                                       - downgrade/past_due: only applies if the event's
                                         subscription id still matches the negotiator's
                                         stored stripe_subscription_id (an old/superseded
                                         subscription's terminal event must not clobber a
                                         row that has since claimed a different one)
SubscriptionScreen
  (Realtime .stream() on negotiator row)
  sees tier flip -> shows "Professional" state

  "Manage Subscription" tap
    -> create-portal-session ------->  create Portal Session
                                     <----  portal URL
  url_launcher opens portal URL  ---------------------------------------->  Stripe-hosted billing portal
                                                                            (cancel/update card/view invoices)
```

## Data model

New columns on `negotiator` (additive-only grant, following the lesson from Profile Management's Critical bug and Settings' deliberately-additive migration — no `revoke update` anywhere in this migration):

```sql
alter table negotiator add column if not exists stripe_customer_id text;
alter table negotiator add column if not exists stripe_subscription_id text;
alter table negotiator add column if not exists subscription_status text;
alter table negotiator add column if not exists current_period_end timestamptz;
```

`subscription_status` mirrors Stripe's own subscription status strings (`active`, `past_due`, `canceled`, `incomplete`, `incomplete_expired`, `unpaid`) rather than inventing a new vocabulary — the webhook handler writes Stripe's status through unchanged. `subscription_tier` (already existing) is the single source of truth for gating (Sub-milestone B reads only this column); `subscription_status`/`current_period_end` are display-only, shown in `SubscriptionScreen` ("renews on X" / "payment past due").

No new table: this is a 1:1 relationship with `negotiator`, same reasoning as `property_specialisation` (Profile Management) and the `notify_*` columns (Settings) — a new `subscription` table was considered and rejected as unnecessary normalization for a single active subscription per negotiator.

**Grant:** all 4 columns are written ONLY by the webhook handler, which uses the Supabase **service role key** (bypasses RLS and column grants entirely, by design — this is the established pattern for privileged Postgres access from a trusted server context). No client-facing UPDATE grant is added for these columns at all — a client can SELECT them (needed to render "renews on X"), but no `grant update` statement is added for them to `authenticated`, ever. This is stricter than `subscription_tier`'s existing precedent (which is excluded from the grant but the column exists in a table with SOME columns grantable) — these 4 new columns get zero client write path, full stop.

## Edge Functions

**`create-subscription`** (invoked by the authenticated client via `supabase.functions.invoke`):
1. Reads the caller's `auth.uid()` from the function's JWT context.
2. If `negotiator.stripe_customer_id` is null, creates a Stripe Customer (email from `auth.users`) and stores the id.
3. Creates a Stripe Subscription for that Customer on the Professional price (`payment_behavior: 'default_incomplete'`, `expand: ['latest_invoice.payment_intent']`), storing `stripe_subscription_id` and `subscription_status: 'incomplete'` immediately (the webhook will confirm `active` once payment succeeds).
4. Returns the PaymentIntent's `client_secret` to the client.

**`stripe-webhook`** (public endpoint, Stripe calls this directly — no Supabase auth, secured instead by Stripe's own webhook signature; MUST be deployed with `--no-verify-jwt`, since Supabase's default JWT check would reject every Stripe delivery before this function's own signature check ever runs, silently making the whole tier-flip mechanism dead on arrival — this is the Edge-Function-era equivalent of this project's earlier RLS `security definer`/`WITH CHECK` lessons, a one-flag miss that fails everything downstream with no obvious error):
1. Verifies the `Stripe-Signature` header against the raw request body using the webhook signing secret (`STRIPE_WEBHOOK_SECRET`, set via `supabase secrets set`, never in client code).
2. On `customer.subscription.updated`/`customer.subscription.deleted`: looks up the negotiator by `stripe_customer_id`, writes `subscription_status` from the event, sets `subscription_tier = 'professional'` when status is `active`, `trialing`, or `past_due` (see step 3 — access is retained through a failed charge), sets `subscription_tier = 'free'` when status is `canceled`/`unpaid`/`incomplete_expired`, writes `current_period_end`.
3. On `invoice.payment_failed`: writes `subscription_status = 'past_due'` (tier stays `professional` until Stripe itself cancels the subscription after its own retry schedule — this app doesn't invent its own grace-period logic, it defers entirely to Stripe's).
4. Uses the Supabase service role key for all writes (bypasses RLS, the only way an Edge Function can write columns with no client grant).

**`create-portal-session`** (invoked by the authenticated client):
1. Reads `negotiator.stripe_customer_id` for the caller.
2. Creates a Stripe Billing Portal session, returns its URL.
3. Client opens the URL via `url_launcher` (new direct dependency — currently only a transitive dependency of `image_picker`, confirmed present in `pubspec.lock` but not declared directly, so it must be added to `pubspec.yaml` rather than relied on implicitly) in an external browser — cancellation, payment method updates, and invoice history are entirely Stripe-hosted, no custom UI built for any of it.

## Client (`app/lib/features/subscription/`)

- `SubscriptionRepository`: `createSubscription() -> Future<String>` (returns client_secret), `createPortalSession() -> Future<String>` (returns portal URL) — both thin wrappers over `supabase.functions.invoke`. Untested directly (Edge-Function-calling code, same convention as every Supabase-touching repository in this codebase).
- `subscription_providers.dart`: `subscriptionRepositoryProvider`, this feature's own `currentNegotiatorIdProvider` copy, `subscriptionStatusProvider = StreamProvider.autoDispose<Negotiator subscription fields>` using `.stream()` on the `negotiator` row filtered to the current id — mirrors Messaging's established Realtime pattern (the only prior Realtime usage in this codebase), so the UI reflects the webhook's tier flip live without a manual refresh or poll.
- `SubscriptionScreen`: reachable from a new 5th row added to the "App Settings" list on `ProfileScreen` (alongside Notification/Account/Privacy/Help from the Settings sub-pages milestone) — no mockup shows a billing screen at all (none of the 13 original Stitch mockups include one), so this placement is a free design decision; a Settings row was chosen over a separate top-level entry point since subscription management is account-adjacent, consistent with where Account (password/identity) already lives. Two states via `.when()`/tier check: **Free** — shows "Upgrade to Professional" button; tap calls `createSubscription()`, then presents `flutter_stripe`'s `Stripe.instance.initPaymentSheet` + `presentPaymentSheet()` with the returned `client_secret`; on `PaymentSheet` success, shows a "processing" indicator until the Realtime stream reflects `subscription_tier == 'professional'`, bounded by a 15-second timeout after which the indicator is replaced with a manual "Refresh" button (in case the webhook is slow or the Realtime event was missed) rather than spinning indefinitely. **Professional** — shows tier, `current_period_end`, `subscription_status` if not `active`, and a "Manage Subscription" button calling `createPortalSession()` then `url_launcher.launchUrl`.

## Error handling

Every Edge Function call is wrapped in try/catch with the established `listing_error_generic` visible-error pattern (no silent `SizedBox.shrink()`, per this codebase's own recurring-finding history in Ratings/Settings). `PaymentSheet` failures/cancellations from `flutter_stripe` are caught distinctly from network/Edge-Function errors (Stripe's own exceptions carry a `localizedMessage` that is shown as-is for payment-specific failures, since these are meaningful to the user in a way `listing_error_generic` isn't — e.g. "Your card was declined").

## Testing approach

`SubscriptionRepository` untested (Edge-Function-calling code, established convention). The Edge Functions themselves have no existing test infrastructure in this project (first Edge Function usage) — verified manually using the Stripe CLI's `stripe listen --forward-to` and `stripe trigger` commands against the locally-served function (`supabase functions serve`), documented as a **mandatory manual verification** step, same weight as Ratings' mandatory two-account test. `SubscriptionScreen` gets widget tests via provider override for both tier states (free/professional) and the processing/timeout state; the actual `PaymentSheet` presentation itself is not unit-testable (it's a native platform UI) and is exercised only in the manual verification pass.

## Manual setup (mandatory, sequence-sensitive)

1. Create a Stripe account (free), stay in **test mode** throughout — no real charges possible.
2. Create a "Professional" recurring Price in the Stripe dashboard (test mode), note its price ID.
3. Get the test-mode publishable key (`pk_test_...`) and secret key (`sk_test_...`).
4. Add `STRIPE_PUBLISHABLE_KEY=pk_test_...` to `app/.env` (same file/pattern as `SUPABASE_URL`/`SUPABASE_ANON_KEY` — git-ignored, never committed).
5. Set the secret key, the webhook signing secret, and the Professional price's id as Supabase Edge Function secrets (`supabase secrets set STRIPE_SECRET_KEY=sk_test_... STRIPE_WEBHOOK_SECRET=whsec_... STRIPE_PROFESSIONAL_PRICE_ID=price_...`) — never in the Flutter app, never in a migration file. (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are already automatically available inside every deployed Edge Function's environment — Supabase injects these itself, no separate `secrets set` needed for them.)
6. Deploy the 3 Edge Functions (`supabase functions deploy`). The `stripe-webhook` function must be deployed with JWT verification disabled (`supabase functions deploy stripe-webhook --no-verify-jwt`) — Stripe calls this endpoint directly with no Supabase session, so the default JWT check would reject every webhook delivery with a 401 before the handler's own Stripe-signature check ever runs. `create-subscription` and `create-portal-session` deploy normally (JWT-verified, called only by an authenticated client).
7. Register the webhook endpoint URL in the Stripe dashboard (test mode), subscribed to `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_failed`.
8. Run `0013_subscription.sql` (the 4-column migration) in the SQL Editor.
9. **Mandatory manual verification:** use a Stripe test card (`4242 4242 4242 4242`, any future expiry/CVC) to complete a real PaymentSheet flow end to end, confirm the webhook fires (visible in the Stripe dashboard's webhook log) and `subscription_tier` flips to `professional` in the `negotiator` table without any client-side write. Then use the Stripe CLI's `stripe trigger customer.subscription.deleted` (or cancel via the Customer Portal) and confirm the tier flips back to `free`.

## Explicitly deferred / out of scope for this sub-milestone

- Sub-milestone B: the actual Free-tier listing/requirement cap enforcement (this design only makes the tier flippable, it does not yet make the tier DO anything).
- The proposal's "notification delay for Free tier" gate — structurally requires FCM, which remains deferred project-wide; will be revisited once/if push notification delivery is built as its own milestone.
- Proration, trial periods, coupons, multiple price tiers, annual billing — a single monthly Professional price only.
- Any custom cancellation/payment-method UI — entirely delegated to Stripe's hosted Customer Portal.
- Retry/dunning logic beyond what Stripe's own subscription settings already do by default.
