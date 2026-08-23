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
