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
