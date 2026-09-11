import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ClaimedDelivery = {
  delivery_id: string;
  fcm_token: string;
  notification_type: string;
  title: string;
  body: string;
  related_event_id: string | null;
  deep_link_path: string | null;
};

type SendResult = {
  ok: boolean;
  status: number;
  body: string;
  messageId: string | null;
  permanentlyInvalidToken: boolean;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const fcmProjectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
const fcmEndpoint =
  Deno.env.get("FCM_SEND_ENDPOINT") ??
  (fcmProjectId ? `https://fcm.googleapis.com/v1/projects/${fcmProjectId}/messages:send` : "");
const fcmAuthorization = Deno.env.get("FCM_AUTHORIZATION") ?? "";
const fcmProxySharedSecret = Deno.env.get("FCM_PROXY_SHARED_SECRET") ?? "";
const fcmServiceAccountJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";
const fcmServiceAccountJsonBase64 = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON_BASE64") ?? "";
const dispatcherSharedSecret = Deno.env.get("DISPATCHER_SHARED_SECRET") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

Deno.serve(async (request) => {
  if (dispatcherSharedSecret) {
    const providedSecret = request.headers.get("x-oslava-dispatch-secret") ?? "";
    if (providedSecret !== dispatcherSharedSecret) {
      return Response.json({ error: "unauthorized dispatcher invocation" }, { status: 401 });
    }
  }

  if (!supabaseUrl || !serviceRoleKey || !fcmEndpoint) {
    return Response.json(
      { error: "notification dispatcher is not configured" },
      { status: 500 },
    );
  }

  if (!fcmAuthorization && !fcmProxySharedSecret && !serviceAccountJson()) {
    return Response.json(
      { error: "FCM authorization, service account, or proxy shared secret is required" },
      { status: 500 },
    );
  }

  const workerId = `dispatch-notifications-${crypto.randomUUID()}`;
  const { data, error } = await supabase.rpc("claim_notification_deliveries", {
    p_worker_id: workerId,
    p_limit: 50,
  });

  if (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }

  const claimed = (data ?? []) as ClaimedDelivery[];
  const results = [];

  for (const delivery of claimed) {
    const response = await sendFcm(delivery);

    const { error: completeError } = await supabase.rpc(
      "complete_claimed_notification_delivery",
      {
        p_delivery_id: delivery.delivery_id,
        p_worker_id: workerId,
        p_success: response.ok,
        p_provider_message_id: response.messageId,
        p_provider_response_code: response.status.toString(),
        p_provider_response: response.body,
        p_permanently_invalid_token: response.permanentlyInvalidToken,
      },
    );

    results.push({
      delivery_id: delivery.delivery_id,
      sent: response.ok,
      status: response.status,
      permanently_invalid_token: response.permanentlyInvalidToken,
      complete_error: completeError?.message ?? null,
    });
  }

  return Response.json({ claimed: claimed.length, results });
});

async function sendFcm(delivery: ClaimedDelivery): Promise<SendResult> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);

  try {
    const response = await fetch(fcmEndpoint, {
      method: "POST",
      signal: controller.signal,
      headers: await fcmHeaders(),
      body: JSON.stringify({
        message: {
          token: delivery.fcm_token,
          notification: {
            title: delivery.title,
            body: delivery.body,
          },
          data: {
            notification_id: delivery.delivery_id,
            notification_type: delivery.notification_type,
            related_event_id: delivery.related_event_id ?? "",
            deep_link_path: delivery.deep_link_path ?? "",
          },
        },
      }),
    });

    const body = await response.text();
    return {
      ok: response.ok,
      status: response.status,
      body,
      messageId: parseMessageId(body),
      permanentlyInvalidToken: isPermanentTokenError(response.status, body),
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      ok: false,
      status: 0,
      body: message,
      messageId: null,
      permanentlyInvalidToken: false,
    };
  } finally {
    clearTimeout(timeout);
  }
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function fcmHeaders(): Promise<HeadersInit> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (fcmAuthorization) {
    headers.authorization = fcmAuthorization;
  } else if (serviceAccountJson()) {
    headers.authorization = `Bearer ${await firebaseAccessToken()}`;
  }
  if (fcmProxySharedSecret) {
    headers["x-oslava-fcm-proxy-secret"] = fcmProxySharedSecret;
  }
  return headers;
}

async function firebaseAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt - 60 > now) {
    return cachedAccessToken.token;
  }

  const account = JSON.parse(serviceAccountJson()) as {
    client_email?: string;
    private_key?: string;
    token_uri?: string;
  };
  const clientEmail = account.client_email;
  const privateKey = account.private_key;
  const tokenUri = account.token_uri ?? "https://oauth2.googleapis.com/token";

  if (!clientEmail || !privateKey) {
    throw new Error("FCM service account JSON must include client_email and private_key");
  }

  const assertion = await signedJwt({
    clientEmail,
    privateKey,
    tokenUri,
    issuedAt: now,
    expiresAt: now + 3600,
  });

  const tokenResponse = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const tokenBody = await tokenResponse.text();
  if (!tokenResponse.ok) {
    throw new Error(`FCM OAuth token request failed: ${tokenResponse.status} ${tokenBody}`);
  }

  const parsed = JSON.parse(tokenBody) as { access_token?: string; expires_in?: number };
  if (!parsed.access_token) {
    throw new Error("FCM OAuth token response did not include access_token");
  }

  cachedAccessToken = {
    token: parsed.access_token,
    expiresAt: now + (parsed.expires_in ?? 3600),
  };
  return cachedAccessToken.token;
}

function serviceAccountJson(): string {
  if (fcmServiceAccountJson) return fcmServiceAccountJson;
  if (!fcmServiceAccountJsonBase64) return "";
  return new TextDecoder().decode(base64ToBytes(fcmServiceAccountJsonBase64));
}

async function signedJwt(input: {
  clientEmail: string;
  privateKey: string;
  tokenUri: string;
  issuedAt: number;
  expiresAt: number;
}): Promise<string> {
  const encodedHeader = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const encodedClaims = base64UrlEncode(JSON.stringify({
    iss: input.clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: input.tokenUri,
    iat: input.issuedAt,
    exp: input.expiresAt,
  }));
  const unsignedToken = `${encodedHeader}.${encodedClaims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(input.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken),
  );
  return `${unsignedToken}.${base64UrlEncode(signature)}`;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function base64UrlEncode(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function parseMessageId(body: string): string | null {
  try {
    const parsed = JSON.parse(body) as { name?: string };
    return parsed.name ?? null;
  } catch (_) {
    return null;
  }
}

function isPermanentTokenError(status: number, body: string): boolean {
  if (status === 404 || status === 410) return true;
  try {
    const parsed = JSON.parse(body) as { error?: { status?: string; details?: Array<{ errorCode?: string }> } };
    const code = parsed.error?.status ?? parsed.error?.details?.find((detail) => detail.errorCode)?.errorCode;
    return code === "UNREGISTERED" || code === "NOT_FOUND" || code === "INVALID_ARGUMENT";
  } catch (_) {
    return false;
  }
}
