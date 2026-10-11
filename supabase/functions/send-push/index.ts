// send-push: drains public.notifications_outbox and delivers via APNs (token-based auth).
// STUB: works end-to-end once the secrets below are set, but has no retry backoff / batching yet.
//
// Secrets (supabase secrets set ...):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID (com.bjjbul.app),
//   APNS_PRIVATE_KEY (contents of the .p8 file, including BEGIN/END lines)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
//
// Invoke on a schedule (e.g. every minute with pg_cron + pg_net, or an external cron):
//   POST https://<project>.supabase.co/functions/v1/send-push  (Authorization: Bearer <service role key>)

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.bjjbul.app";
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";

function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedJwt: { token: string; issuedAt: number } | null = null;

// APNs provider token (ES256), reused for up to 50 minutes.
async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 3000) return cachedJwt.token;
  const pem = PRIVATE_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "ES256", kid: KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: TEAM_ID, iat: now }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`),
  );
  const token = `${header}.${claims}.${base64url(signature)}`;
  cachedJwt = { token, issuedAt: now };
  return token;
}

async function sendToDevice(token: string, environment: string, payload: unknown) {
  const host = environment === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJwt()}`,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  return { ok: res.ok, status: res.status, body: res.ok ? "" : await res.text() };
}

Deno.serve(async () => {
  if (!KEY_ID || !TEAM_ID || !PRIVATE_KEY) {
    return new Response(JSON.stringify({ error: "APNs secrets not configured" }), { status: 500 });
  }

  const { data: jobs, error } = await supabase
    .from("notifications_outbox")
    .select("id, user_id, attempts, notification:notifications(title, body, data)")
    .eq("status", "pending")
    .lt("attempts", 5)
    .order("created_at")
    .limit(100);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  let sent = 0;
  for (const job of jobs ?? []) {
    // deno-lint-ignore no-explicit-any
    const n = (job as any).notification;
    const { data: devices } = await supabase
      .from("device_tokens").select("token, environment").eq("user_id", job.user_id);

    const payload = { aps: { alert: { title: n?.title ?? "", body: n?.body ?? "" }, sound: "default" }, ...(n?.data ?? {}) };
    let anyOk = false;
    let lastError = "";
    for (const d of devices ?? []) {
      const r = await sendToDevice(d.token, d.environment, payload);
      if (r.ok) anyOk = true;
      else {
        lastError = `${r.status} ${r.body}`;
        // 410 Unregistered / 400 BadDeviceToken: drop the stale token.
        if (r.status === 410 || r.body.includes("BadDeviceToken")) {
          await supabase.from("device_tokens").delete().eq("token", d.token);
        }
      }
    }

    await supabase.from("notifications_outbox").update(
      anyOk
        ? { status: "sent", sent_at: new Date().toISOString(), attempts: job.attempts + 1 }
        : { status: job.attempts + 1 >= 5 ? "failed" : "pending", attempts: job.attempts + 1, last_error: lastError || "no devices" },
    ).eq("id", job.id);
    if (anyOk) sent++;
  }

  return new Response(JSON.stringify({ processed: jobs?.length ?? 0, sent }), {
    headers: { "content-type": "application/json" },
  });
});
