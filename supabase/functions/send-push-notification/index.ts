// supabase/functions/send-push-notification/index.ts
//
// Deployed WITHOUT --no-verify-jwt (unlike stripe-webhook): this function
// is only ever called by an authenticated app client (MatchingRepository,
// CobrokeRequestRepository, MessageRepository), never by an external
// service reaching in from outside -- Supabase's default JWT check is
// correct here, not a gotcha to work around. On top of that platform-level
// check, this handler also establishes the caller's identity itself (see
// callerClient below) -- establishing "an authenticated user made this
// call" is the fix at this module's rigor level; verifying that the caller
// is actually a legitimate party to the specific match/request/conversation
// being notified about is explicitly out of scope per this module's design
// doc.
//
// Uses a raw fetch-based Google OAuth2 + FCM v1 REST call rather than the
// Firebase Admin SDK -- the Admin SDK is Node-oriented and not reliably
// Deno-compatible. djwt handles the RS256 JWT signing step.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const FIREBASE_SERVICE_ACCOUNT = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")!);
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// category -> the negotiator column gating that category's delivery.
const PREFERENCE_COLUMN: Record<string, string> = {
  match: "notify_match",
  message: "notify_message",
  cobroke_request: "notify_cobroke_request",
};

const JSON_HEADERS = { "Content-Type": "application/json" };

let cachedKey: CryptoKey | null = null;
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

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
  // FCM/Google OAuth2 access tokens are valid for an hour -- reuse a
  // cached one (with a 60s safety margin) instead of paying a full
  // RS256-sign-and-network-round-trip on every single invocation.
  if (cachedAccessToken && Date.now() < cachedAccessToken.expiresAt - 60_000) {
    return cachedAccessToken.token;
  }

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
  if (!data.access_token) {
    throw new Error(`FCM token exchange succeeded but returned no access_token: ${JSON.stringify(data)}`);
  }

  cachedAccessToken = { token: data.access_token as string, expiresAt: Date.now() + 3600_000 };
  return cachedAccessToken.token;
}

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: JSON_HEADERS,
      });
    }

    // Scoped to the caller's own JWT -- only used to identify who is
    // calling, never to read/write data (that's the service-role client
    // below). Establishes that an authenticated negotiator is making this
    // call at all; it does not verify the caller is a legitimate party to
    // the specific match/request/conversation, which is out of scope here.
    const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await callerClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: JSON_HEADERS,
      });
    }

    const { recipient_negotiator_id, category, title, body, deep_link_data } = await req.json();

    if (typeof recipient_negotiator_id !== "string" || recipient_negotiator_id.length === 0) {
      return new Response(JSON.stringify({ error: "recipient_negotiator_id must be a non-empty string" }), {
        status: 400,
        headers: JSON_HEADERS,
      });
    }
    if (typeof title !== "string" || title.length === 0) {
      return new Response(JSON.stringify({ error: "title must be a non-empty string" }), {
        status: 400,
        headers: JSON_HEADERS,
      });
    }
    if (typeof body !== "string" || body.length === 0) {
      return new Response(JSON.stringify({ error: "body must be a non-empty string" }), {
        status: 400,
        headers: JSON_HEADERS,
      });
    }
    let sanitizedDeepLinkData: Record<string, string> | undefined;
    if (deep_link_data !== undefined && deep_link_data !== null) {
      if (typeof deep_link_data !== "object" || Array.isArray(deep_link_data)) {
        return new Response(JSON.stringify({ error: "deep_link_data must be a plain object" }), {
          status: 400,
          headers: JSON_HEADERS,
        });
      }
      sanitizedDeepLinkData = {};
      for (const [k, v] of Object.entries(deep_link_data as Record<string, unknown>)) {
        sanitizedDeepLinkData[k] = typeof v === "string" ? v : String(v);
      }
    }

    if (!Object.hasOwn(PREFERENCE_COLUMN, category)) {
      return new Response(JSON.stringify({ error: `Unknown category: ${category}` }), {
        status: 400,
        headers: JSON_HEADERS,
      });
    }
    const preferenceColumn = PREFERENCE_COLUMN[category];

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: negotiator, error: negotiatorError } = await adminClient
      .from("negotiator")
      .select(preferenceColumn)
      .eq("negotiator_id", recipient_negotiator_id)
      .maybeSingle();
    if (negotiatorError) {
      console.error("send-push-notification: negotiator lookup failed", negotiatorError);
      return new Response(JSON.stringify({ error: "Negotiator lookup failed" }), {
        status: 500,
        headers: JSON_HEADERS,
      });
    }
    if (!negotiator) {
      return new Response(JSON.stringify({ sent: 0, skipped: "no_recipient" }), {
        status: 200,
        headers: JSON_HEADERS,
      });
    }

    // In-app Notification Center row -- written regardless of whether the
    // push preference is off or no device tokens exist. The in-app history
    // is a separate channel from push delivery; it should exist as long as
    // the recipient is a real negotiator, independent of whether a device
    // actually received anything.
    //
    // KNOWN LIMITATION (accepted for now, follow-up task tracked):
    // this function still does NOT verify that the CALLER is a legitimate
    // party to the match/request/conversation named in the payload (see the
    // existing unverified-caller note earlier in this file). That gap is
    // strictly worse since this insert was added: previously the worst a
    // forged call could do was show one unwanted transient push banner;
    // now the same forged call also writes a DURABLE row into another
    // user's in-app Notification Center, with attacker-chosen
    // title/body/category/deep_link_data, addressed by a caller-supplied
    // recipient_negotiator_id. Any signed-in user could in principle inject
    // arbitrary notifications into any other user's feed by invoking this
    // function directly.
    // Accepted for now: single-org internal app, no external threat-model
    // change from this milestone. The real fix -- server-side verification
    // that auth.uid() is an actual party to the referenced entity before
    // either sending or inserting -- is a deliberate follow-up, not a
    // gap to be patched at the call sites.
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

    if (negotiator[preferenceColumn] === false) {
      // Expected, common outcome -- recipient has this category muted.
      return new Response(JSON.stringify({ sent: 0, skipped: "preference_off" }), {
        status: 200,
        headers: JSON_HEADERS,
      });
    }

    const { data: tokens, error: tokensError } = await adminClient
      .from("fcm_device_token")
      .select("token_id, token")
      .eq("negotiator_id", recipient_negotiator_id);
    if (tokensError) {
      console.error("send-push-notification: token lookup failed", tokensError);
      return new Response(JSON.stringify({ error: "Token lookup failed" }), {
        status: 500,
        headers: JSON_HEADERS,
      });
    }
    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, skipped: "no_devices" }), {
        status: 200,
        headers: JSON_HEADERS,
      });
    }

    const accessToken = await getAccessToken();
    let sent = 0;
    for (const row of tokens) {
      try {
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
                data: { ...(sanitizedDeepLinkData ?? {}), category },
              },
            }),
          },
        );
        if (fcmResponse.ok) {
          sent += 1;
          continue;
        }
        const errorBody = await fcmResponse.json();

        // FCM v1 error bodies put the real reason in
        // error.details[].errorCode (an object whose "@type" ends in
        // FcmError), not in the top-level error.status. error.status is
        // FCM's generic gRPC-style bucket: INVALID_ARGUMENT covers any
        // malformed request (e.g. a non-string `data` value, an oversized
        // payload) and is not proof the token itself is dead, so it must
        // never trigger a delete.
        const fcmErrorCode = errorBody?.error?.details?.find(
          (d: any) => typeof d?.["@type"] === "string" && d["@type"].endsWith("FcmError"),
        )?.errorCode;
        const tokenIsDead =
          fcmErrorCode === "UNREGISTERED" ||
          fcmErrorCode === "SENDER_ID_MISMATCH" ||
          errorBody?.error?.status === "NOT_FOUND";

        if (tokenIsDead) {
          // Stale token (app uninstalled, or FCM rotated it) -- self-clean
          // so this table never accumulates dead rows.
          const { error: deleteError } = await adminClient
            .from("fcm_device_token")
            .delete()
            .eq("token_id", row.token_id);
          if (deleteError) {
            console.error(
              `send-push-notification: failed to delete stale token ${row.token_id} for negotiator ${recipient_negotiator_id}:`,
              deleteError,
            );
          }
        } else {
          console.error(
            `send-push-notification: FCM send failed for token ${row.token_id}, negotiator ${recipient_negotiator_id}:`,
            errorBody,
          );
        }
      } catch (perTokenError) {
        // A single malformed/failing token response (e.g. fcmResponse.json()
        // failing on a non-JSON error body, or a network error) must not
        // abort the whole batch and drop the `sent` count already
        // accumulated for other devices.
        console.error(
          `send-push-notification: error sending to token ${row.token_id}, negotiator ${recipient_negotiator_id}:`,
          perTokenError,
        );
        continue;
      }
    }

    return new Response(JSON.stringify({ sent }), {
      status: 200,
      headers: JSON_HEADERS,
    });
  } catch (error) {
    console.error("send-push-notification: unhandled error", error);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: JSON_HEADERS,
    });
  }
});
