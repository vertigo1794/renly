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
      // This write is load-bearing far beyond this request: it is the ONLY
      // place `stripe_customer_id` gets persisted, and `stripe-webhook`
      // looks the negotiator up by that exact column on every later
      // subscription event. supabase-js resolves (never throws) on a
      // database error, so letting this go unchecked meant a failed write
      // would leave the column null while this request still returned a
      // client secret -- the customer would pay, and every subsequent
      // webhook would match zero rows and never flip the tier.
      const { error: customerIdWriteError } = await adminClient
        .from("negotiator")
        .update({ stripe_customer_id: customerId })
        .eq("negotiator_id", user.id);
      if (customerIdWriteError) {
        console.error(
          `create-subscription: failed to persist stripe_customer_id for negotiator ${user.id}:`,
          customerIdWriteError,
        );
        return new Response(JSON.stringify({ error: "Failed to save Stripe customer id" }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    // Create-ONCE for the Subscription, mirroring the create-once logic
    // for the Customer above. Calling stripe.subscriptions.create
    // unconditionally here was a real, reachable money bug, not a
    // theoretical one: a user taps Upgrade, dismisses the PaymentSheet
    // (which leaves a live, `incomplete` Subscription behind on Stripe's
    // side), then taps Upgrade again and pays on the SECOND one. ~23
    // hours later Stripe auto-expires the FIRST, never-paid subscription
    // and fires customer.subscription.updated/.deleted for it with
    // status `incomplete_expired` -- which the webhook, keyed only on
    // the customer id, would happily apply, downgrading a paying user to
    // 'free' while Stripe keeps billing their real subscription. The
    // webhook now also guards on stripe_subscription_id, but not
    // manufacturing the duplicate in the first place is the actual fix.
    const existingSubscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: "all",
      price: PROFESSIONAL_PRICE_ID,
      limit: 10,
    });
    // Checked as two separate scans, not one `find` over the mixed-status
    // list -- a single find() picks whichever non-terminal subscription
    // Stripe happens to list first, so if an abandoned `incomplete`
    // subscription were ever listed ahead of a genuinely `active` one,
    // the 409 guard below would silently never fire and the reuse path
    // would let the user pay a second time. The paying check must not
    // depend on Stripe's listing order.
    const payingSubscription = existingSubscriptions.data.find((s) =>
      ["active", "trialing"].includes(s.status)
    );
    if (payingSubscription) {
      // Already paying. Nothing to do here -- the client should be
      // showing the professional tier and the Manage Subscription
      // button, not the upgrade flow.
      return new Response(JSON.stringify({ error: "Already subscribed" }), {
        status: 409,
        headers: { "Content-Type": "application/json" },
      });
    }
    const reusable = existingSubscriptions.data.find((s) =>
      ["incomplete", "past_due"].includes(s.status)
    );

    let subscription: Stripe.Subscription;
    if (reusable) {
      // Reuse the existing incomplete/past_due subscription instead of
      // creating a duplicate -- re-expand to get a fresh (or the same,
      // still-valid) PaymentIntent client secret.
      subscription = await stripe.subscriptions.retrieve(reusable.id, {
        expand: ["latest_invoice.payment_intent"],
      });
    } else {
      subscription = await stripe.subscriptions.create({
        customer: customerId,
        items: [{ price: PROFESSIONAL_PRICE_ID }],
        payment_behavior: "default_incomplete",
        payment_settings: { save_default_payment_method: "on_subscription" },
        expand: ["latest_invoice.payment_intent"],
      });
    }

    // Checked for the same reason the stripe_customer_id write above is:
    // supabase-js resolves (never throws) on a database error. This write
    // used to go unchecked on the grounds that nothing read the column --
    // that is no longer true. `stripe-webhook` now matches on
    // `stripe_subscription_id` before applying any DOWNGRADE, so a
    // silently-failed write here would leave the column stale or null and
    // make every legitimate cancellation event look like a stale event
    // for a superseded subscription, i.e. the tier would never drop back
    // to 'free'. The column is load-bearing now, so the write is checked.
    const { error: subscriptionWriteError } = await adminClient
      .from("negotiator")
      .update({
        stripe_subscription_id: subscription.id,
        subscription_status: subscription.status,
      })
      .eq("negotiator_id", user.id);
    if (subscriptionWriteError) {
      console.error(
        `create-subscription: failed to persist stripe_subscription_id for negotiator ${user.id}:`,
        subscriptionWriteError,
      );
      return new Response(JSON.stringify({ error: "Failed to save subscription id" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

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
