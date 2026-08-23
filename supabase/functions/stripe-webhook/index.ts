// supabase/functions/stripe-webhook/index.ts
//
// DEPLOYMENT (REQUIRED — do not deploy this function the normal way):
//
//   supabase functions deploy stripe-webhook --no-verify-jwt
//
// The `--no-verify-jwt` flag is mandatory for THIS function only. Supabase
// Edge Functions verify a Supabase JWT on every incoming request by default,
// but Stripe calls this endpoint directly from its own servers and carries no
// Supabase session — so with the default behaviour every real webhook delivery
// would be rejected with a 401 before a single line of the handler below ever
// runs, and the tier flip would be dead on arrival with no visible error
// anywhere in the app. This endpoint is not unauthenticated: it is secured by
// Stripe's own cryptographic signature check (`constructEventAsync` below).
//
// `create-subscription` and `create-portal-session` are deployed WITHOUT this
// flag — they are called only by an authenticated client and must stay
// JWT-verified.
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
    console.error("stripe-webhook: signature verification failed:", (err as Error).message);
    return new Response(`Webhook signature verification failed: ${(err as Error).message}`, {
      status: 400,
    });
  }

  try {
    switch (event.type) {
      case "customer.subscription.updated":
      case "customer.subscription.deleted": {
        const subscription = event.data.object as Stripe.Subscription;
        // 'past_due' deliberately KEEPS professional access. A failed
        // renewal charge moves the subscription to 'past_due' and fires
        // this event -- but Stripe then runs its own retry/dunning
        // schedule, and only if it gives up entirely does it move the
        // subscription to a genuinely terminal status ('canceled',
        // 'unpaid', 'incomplete_expired'), firing this event again. Those
        // terminal statuses are what actually drop the tier to 'free'.
        // This app does not invent its own grace-period logic on top.
        const tier = ["active", "trialing", "past_due"].includes(subscription.status)
          ? "professional"
          : "free";
        // `current_period_end` must be read defensively, NOT as a plain
        // `subscription.current_period_end`. The shape of this INBOUND
        // payload is set by the API version pinned on the webhook
        // ENDPOINT in the Stripe Dashboard (which defaults to the Stripe
        // account's own default version) -- it is NOT governed by the
        // `apiVersion` passed to `new Stripe(...)` above, which only
        // shapes responses to OUTBOUND calls this SDK makes (and this
        // handler makes none). As of API version 2025-03-31.basil Stripe
        // moved this field off the Subscription object and onto the
        // subscription ITEMS, so on any recently-created Stripe account
        // the top-level field is simply absent. Reading it blindly gave
        // `undefined * 1000` -> NaN -> `new Date(NaN).toISOString()`
        // THROWS RangeError, 500ing the whole delivery and losing the
        // tier flip. Falling back to the item, then to null, keeps the
        // load-bearing tier write alive even when this display-only
        // field cannot be resolved (the column is nullable).
        const firstItem = subscription.items?.data?.[0] as Record<string, unknown> | undefined;
        const periodEndSeconds: unknown = subscription.current_period_end ??
          firstItem?.["current_period_end"];
        const currentPeriodEndIso =
          typeof periodEndSeconds === "number" && Number.isFinite(periodEndSeconds)
            ? new Date(periodEndSeconds * 1000).toISOString()
            : null;
        // `.select("negotiator_id")` on both branches below is NOT
        // decorative -- it is what makes a zero-row match detectable.
        // PostgREST answers an `.update(...).eq(col, value)` that matches
        // NO row with `{ data: [], error: null }`, i.e. NOT an error. So
        // if `stripe_customer_id` was never persisted on the negotiator
        // row (or Stripe sent a null customer, which `as string` would
        // turn into `.eq("stripe_customer_id", null)` -- also a match on
        // nothing), the write would silently no-op, the `error` check
        // would pass, this handler would return 200, and Stripe would
        // never retry. The tier would never flip, with no trace anywhere.
        // Asking for the affected rows back lets us tell "updated" apart
        // from "matched nothing" -- which the two branches then treat
        // very differently, see below.
        //
        // Also note that both branches check `error` explicitly:
        // supabase-js does NOT throw on a database error, it resolves
        // with an `error` field. Without that check a failed write (bad
        // grant, or 0013_subscription.sql not yet run so the columns
        // don't exist) would fall through to the 200 below, Stripe would
        // consider the delivery successful and never retry, and the tier
        // flip would be silently lost. Throwing hands it to the outer
        // catch, which returns 500 and makes Stripe retry.
        if (tier === "professional") {
          // Any event that GRANTS professional access always takes effect
          // and claims this subscription as the current one for this
          // customer. That claim is what lets a legitimate re-subscribe
          // after a fully-resolved cancellation correctly become
          // authoritative, and it is also what later lets a downgrade
          // tell "this is the subscription we're tracking" apart from
          // "this is an old, superseded one".
          const { data: updatedRows, error: updateError } = await adminClient
            .from("negotiator")
            .update({
              subscription_status: subscription.status,
              subscription_tier: "professional",
              stripe_subscription_id: subscription.id,
              current_period_end: currentPeriodEndIso,
            })
            .eq("stripe_customer_id", subscription.customer as string)
            .select("negotiator_id");
          if (updateError) {
            console.error(
              `stripe-webhook: ${event.type} (${event.id}) failed to grant professional tier for customer ${subscription.customer}:`,
              updateError,
            );
            throw updateError;
          }
          if (!updatedRows || updatedRows.length === 0) {
            // A grant that matches nothing IS an error -- the customer id
            // should always resolve to exactly one negotiator. Throw so
            // Stripe retries.
            const message =
              `stripe-webhook: ${event.type} (${event.id}) matched no negotiator for stripe_customer_id=${subscription.customer}`;
            console.error(message);
            throw new Error(message);
          }
        } else {
          // Only apply a DOWNGRADE if THIS subscription is still the one
          // currently on file. An old/abandoned subscription being
          // cleaned up -- e.g. an unpaid `incomplete` subscription that
          // Stripe auto-expires ~23h after it was created, because the
          // user dismissed the PaymentSheet on a first attempt and paid
          // on a second one -- must not clobber a row that has since
          // claimed a different, successful subscription. Without this
          // extra `.eq`, that stale expiry event silently downgraded a
          // paying user to 'free' and nulled their current_period_end
          // while Stripe kept billing them, with no in-app way back
          // (Manage Subscription only renders at professional tier).
          //
          // A zero-row match here is therefore an EXPECTED, legitimate
          // outcome (a stale event for a superseded subscription), NOT an
          // error -- so it is logged for visibility and deliberately not
          // thrown. Throwing would make Stripe retry the delivery
          // forever for an event that can never match again.
          const { data: updatedRows, error: updateError } = await adminClient
            .from("negotiator")
            .update({
              subscription_status: subscription.status,
              subscription_tier: "free",
              current_period_end: currentPeriodEndIso,
            })
            .eq("stripe_customer_id", subscription.customer as string)
            .eq("stripe_subscription_id", subscription.id)
            .select("negotiator_id");
          if (updateError) {
            console.error(
              `stripe-webhook: ${event.type} (${event.id}) failed to downgrade for customer ${subscription.customer}:`,
              updateError,
            );
            throw updateError;
          }
          if (!updatedRows || updatedRows.length === 0) {
            console.error(
              `stripe-webhook: ${event.type} (${event.id}) skipped downgrade for stale subscription ${subscription.id} (customer ${subscription.customer}) -- not the current subscription on file`,
            );
          }
        }
        break;
      }
      case "invoice.payment_failed": {
        const invoice = event.data.object as Stripe.Invoice;
        // Tier deliberately stays 'professional' here -- Stripe runs its
        // own retry/dunning schedule and will fire
        // customer.subscription.updated with a 'canceled'/'unpaid' status
        // if it eventually gives up, which the branch above already
        // handles. This app does not invent its own grace-period logic.
        // Which subscription this invoice belongs to. Read with the same
        // defensiveness as `current_period_end` above and for exactly the
        // same reason: the inbound payload's shape is set by the API
        // version pinned on the webhook ENDPOINT, not by the `apiVersion`
        // passed to `new Stripe(...)`. Recent API versions moved this off
        // the top-level `subscription` field and under
        // `parent.subscription_details.subscription`, so the top-level
        // field can simply be absent on a newer account.
        const invoiceRecord = invoice as unknown as Record<string, unknown>;
        const parent = invoiceRecord["parent"] as Record<string, unknown> | undefined;
        const subscriptionDetails = parent?.["subscription_details"] as
          | Record<string, unknown>
          | undefined;
        const rawInvoiceSubscription = invoice.subscription ??
          subscriptionDetails?.["subscription"];
        const invoiceSubscriptionId = typeof rawInvoiceSubscription === "string"
          ? rawInvoiceSubscription
          : (rawInvoiceSubscription as Stripe.Subscription | undefined)?.id;

        if (!invoiceSubscriptionId) {
          // Nothing to key on. A one-off (non-subscription) invoice can
          // legitimately land here, and marking the negotiator past_due
          // on the strength of the customer id alone is exactly the
          // unguarded write this branch is being fixed to avoid.
          console.error(
            `stripe-webhook: ${event.type} (${event.id}) has no resolvable subscription id (customer ${invoice.customer}) -- skipping past_due`,
          );
          break;
        }

        // Guarded on `stripe_subscription_id` for the same reason the
        // downgrade branch above is: a failed invoice belonging to an
        // old, superseded subscription must not mark a negotiator
        // past_due when their CURRENT subscription is paying fine. As
        // there too, a zero-row match is an expected outcome for a stale
        // event -- logged, not thrown, so Stripe doesn't retry forever.
        const { data: updatedRows, error: updateError } = await adminClient
          .from("negotiator")
          .update({ subscription_status: "past_due" })
          .eq("stripe_customer_id", invoice.customer as string)
          .eq("stripe_subscription_id", invoiceSubscriptionId)
          .select("negotiator_id");
        // Same swallowed-error hazard as the branch above -- see the
        // longer notes there.
        if (updateError) {
          console.error(
            `stripe-webhook: ${event.type} (${event.id}) failed to mark past_due for customer ${invoice.customer}:`,
            updateError,
          );
          throw updateError;
        }
        if (!updatedRows || updatedRows.length === 0) {
          console.error(
            `stripe-webhook: ${event.type} (${event.id}) skipped past_due for stale subscription ${invoiceSubscriptionId} (customer ${invoice.customer}) -- not the current subscription on file`,
          );
        }
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
    console.error(
      `stripe-webhook: unhandled failure processing ${event.type} (${event.id}):`,
      error,
    );
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
