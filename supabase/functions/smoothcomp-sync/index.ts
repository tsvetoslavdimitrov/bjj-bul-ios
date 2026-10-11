// smoothcomp-sync: best-effort import of ONE user's public Smoothcomp profile.
// - Requires the signed-in user's JWT; only syncs that user's own saved profiles.smoothcomp_profile_url.
// - Polite: one request per call, identifying User-Agent, and at most once per 24h per user (cached).
// - robots.txt (checked 2026-10-11): User-agent * disallows only /order/, /checkout, /scoreboard; /profile is allowed.
// - IMPORTANT: on 2026-10-11 Smoothcomp served a Cloudflare bot challenge (HTTP 403) to server requests,
//   so the page usually can't be read. We never try to bypass that; the status becomes "blocked" and the
//   app falls back to manually entered (unverified) medals. The parser below is generic and UNTESTED on a real
//   page (we couldn't retrieve one): it walks any embedded JSON (ld+json, data-* / Vue props) for medal- and
//   match-like objects. Check its output before trusting it.

import { createClient } from "jsr:@supabase/supabase-js@2";

const UA = "BJJBul/1.0 (+https://bjjbul.com; admin@bjjbul.com) profile-sync";
const URL_RE = /^https:\/\/(www\.)?smoothcomp\.com\/([a-z]{2}\/)?profile\/(\d+)\/?$/;
const DAY_MS = 24 * 3600 * 1000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

type Medal = { event_name: string; placement: number; division: string | null; event_date: string | null; external_id: string };
type AthleteRecord = { wins: number; losses: number; wins_submission: number; wins_points: number };

function decodeEntities(s: string) {
  return s.replace(/&quot;/g, '"').replace(/&#039;/g, "'").replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}

function jsonBlobs(html: string): unknown[] {
  const out: unknown[] = [];
  const tryParse = (t: string) => {
    const s = t.trim();
    if (!(s.startsWith("{") || s.startsWith("["))) return;
    try { out.push(JSON.parse(s)); } catch { /* ignore */ }
  };
  for (const m of html.matchAll(/<script[^>]*type="application\/(?:ld\+)?json"[^>]*>([\s\S]*?)<\/script>/gi)) tryParse(m[1]);
  for (const m of html.matchAll(/\s(?:data-[\w-]+|:[\w-]+)="([^"]{20,})"/g)) tryParse(decodeEntities(m[1]));
  return out;
}

const str = (v: unknown) => (typeof v === "string" ? v : typeof v === "number" ? String(v) : null);

function walk(node: unknown, visit: (o: Record<string, unknown>) => void, depth = 0) {
  if (depth > 12 || node === null || typeof node !== "object") return;
  if (Array.isArray(node)) { for (const x of node) walk(x, visit, depth + 1); return; }
  const o = node as Record<string, unknown>;
  visit(o);
  for (const v of Object.values(o)) walk(v, visit, depth + 1);
}

function parse(html: string): { medals: Medal[]; record: AthleteRecord | null } {
  const medals = new Map<string, Medal>();
  let wins = 0, losses = 0, subs = 0, points = 0, sawMatch = false;
  for (const blob of jsonBlobs(html)) {
    walk(blob, (o) => {
      const place = Number(o.placement ?? o.place ?? o.rank ?? o.position);
      const eventObj = (o.event ?? o.tournament) as Record<string, unknown> | undefined;
      const eventName = str(o.event_name ?? o.eventName ?? eventObj?.name ?? eventObj?.title);
      if (eventName && place >= 1 && place <= 3) {
        const division = str(o.division ?? o.category ?? o.bracket_name ?? (o.bracket as Record<string, unknown>)?.name);
        const date = str(o.date ?? o.event_date ?? eventObj?.start_date ?? eventObj?.date);
        const id = str(o.id) ?? `${eventName}|${division}|${place}`;
        medals.set(id, { event_name: eventName.slice(0, 200), placement: place, division: division?.slice(0, 200) ?? null,
                         event_date: date && /^\d{4}-\d{2}-\d{2}/.test(date) ? date.slice(0, 10) : null, external_id: id });
      }
      const result = str(o.result ?? o.outcome)?.toLowerCase();
      const won = typeof o.won === "boolean" ? o.won : typeof o.is_winner === "boolean" ? o.is_winner
        : result === "win" || result === "won" ? true : result === "loss" || result === "lost" ? false : null;
      const method = str(o.win_type ?? o.method ?? o.victory_type ?? o.win_method)?.toLowerCase() ?? "";
      if (won !== null && ("opponent" in o || "fight" in o || "match_id" in o || method)) {
        sawMatch = true;
        if (won) {
          wins++;
          if (method.includes("sub")) subs++;
          else if (method.includes("point") || method.includes("decision") || method.includes("advantage")) points++;
        } else losses++;
      }
    });
  }
  return { medals: [...medals.values()], record: sawMatch ? { wins, losses, wins_submission: subs, wins_points: points } : null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "unauthorized" }, 401);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: u } = await admin.auth.getUser(jwt);
  const user = u?.user;
  if (!user) return json({ error: "unauthorized" }, 401);

  const { data: profile } = await admin.from("profiles")
    .select("smoothcomp_profile_url, smoothcomp_synced_at, smoothcomp_status").eq("id", user.id).maybeSingle();
  const url = profile?.smoothcomp_profile_url as string | null;
  if (!url || !URL_RE.test(url)) return json({ status: "invalid_url" }, 400);

  const last = profile?.smoothcomp_synced_at ? Date.parse(profile.smoothcomp_synced_at) : 0;
  if (last && Date.now() - last < DAY_MS) {
    return json({ status: profile?.smoothcomp_status ?? "cached", cached: true, synced_at: profile?.smoothcomp_synced_at });
  }

  let status = "error";
  let medalsCount = 0;
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html" }, redirect: "follow" });
    const html = await res.text();
    if (res.status === 403 || res.status === 429 || html.includes("cf_chl") || html.includes("challenge-platform")) {
      status = "blocked";
    } else if (!res.ok) {
      status = `http_${res.status}`;
    } else {
      const { medals, record } = parse(html);
      if (medals.length === 0 && !record) {
        status = "no_data";
      } else {
        status = "ok";
        medalsCount = medals.length;
        await admin.from("athlete_medals").delete().eq("user_id", user.id).eq("source", "smoothcomp");
        if (medals.length > 0) {
          await admin.from("athlete_medals").insert(medals.map((m) => ({
            ...m, user_id: user.id, source: "smoothcomp", verified: true,
          })));
        }
        if (record) {
          await admin.from("athlete_records").upsert({ user_id: user.id, ...record, source: "smoothcomp",
                                                       synced_at: new Date().toISOString() });
        }
      }
    }
  } catch (e) {
    console.error(e);
    status = "error";
  }

  const now = new Date().toISOString();
  await admin.from("profiles").update({ smoothcomp_synced_at: now, smoothcomp_status: status }).eq("id", user.id);
  return json({ status, medals: medalsCount, synced_at: now });
});
