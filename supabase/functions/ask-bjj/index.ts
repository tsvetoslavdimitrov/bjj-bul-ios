// ask-bjj: "Ask BJJ" chat for the BJJ Bul app.
// - Requires a signed-in user's JWT (Authorization: Bearer <access token>).
// - Daily limit per user via public.ai_usage (migration 0008).
// - Retrieval: injects matching rows from gyms_with_coords / events / open_mats as context.
// - Calls any OpenAI-compatible /chat/completions endpoint (xAI by default). Non-streaming for reliability.
//
// Secrets: AI_API_KEY (required), AI_BASE_URL (default https://api.x.ai/v1), AI_MODEL (default grok-4),
//          AI_DAILY_LIMIT (default 30). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY are automatic.
//
// Request:  { "message": "...", "conversation_id"?: "<uuid>", "locale"?: "bg" | "en" }
//           { "action": "usage" }  -> { remaining, limit }
// Response: { reply, conversation_id, remaining, limit }

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const AI_API_KEY = Deno.env.get("AI_API_KEY") ?? "";
const AI_BASE_URL = (Deno.env.get("AI_BASE_URL") ?? "https://api.x.ai/v1").replace(/\/+$/, "");
const AI_MODEL = Deno.env.get("AI_MODEL") ?? "grok-4";
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "30");
const MAX_INPUT = 2000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });
}

const SYSTEM_PROMPT = `You are "Ask BJJ", the assistant inside BJJ Bul, an app for Brazilian jiu-jitsu in Bulgaria.
Role: a knowledgeable, friendly BJJ coach.
Language: always answer in the user's language. If the user writes Bulgarian (Cyrillic), answer in Bulgarian; otherwise follow the app locale hint.
You help with: techniques and concepts (positions, escapes, guards, submissions, transitions), drilling and training plans,
competition rules at a basic level (IBJJF and ADCC: points, advantages, legal techniques by belt/division) — and remind users to check the official current rulebook for details,
etiquette, hygiene, warm-ups, injury prevention and safe training (tap early, controlled pace, respect partners).
Safety: you do NOT give medical advice, diagnoses or treatment. For pain, injuries or health questions, tell the user to see a doctor or physiotherapist.
Off-topic: politely refuse anything unrelated to BJJ, grappling, martial-arts training or the BJJ scene in Bulgaria, and steer back.
Bulgarian facts: for any fact about gyms, schedules, prices, addresses, open mats or competitions in Bulgaria, use ONLY the "App data" provided below.
Never invent gyms, addresses, phones, prices or dates. If the data doesn't contain the answer, say you don't know and suggest checking the Explore or Events tab or contacting the gym.
Keep answers concise and practical; use short lists for step-by-step techniques.`;

type Row = Record<string, unknown>;

const KEYWORDS = [
  "gym", "gyms", "academy", "club", "open mat", "openmat", "event", "events", "competition", "tournament", "where", "near",
  "зала", "зали", "клуб", "академия", "отворен", "свободни борби", "опън мат", "състезан", "турнир", "събити", "къде", "близо",
];
const EVENT_WORDS = ["event", "competition", "tournament", "състезан", "турнир", "събити"];
const OPENMAT_WORDS = ["open mat", "openmat", "опън мат", "свободни борби", "отворен"];

function norm(s: string) {
  return s.toLowerCase().normalize("NFKC");
}

// Prefix match handles Bulgarian inflection ("Пловдив" ~ "пловдивски") and Latin forms.
function mentions(text: string, name: string | null | undefined): boolean {
  if (!name) return false;
  const n = norm(name).trim();
  if (n.length < 3) return false;
  if (text.includes(n)) return true;
  const stem = n.length > 6 ? n.slice(0, n.length - 2) : n;
  return stem.length >= 4 && text.includes(stem);
}

async function safeSelect(q: PromiseLike<{ data: Row[] | null; error: unknown }>): Promise<Row[]> {
  try {
    const { data, error } = await q;
    return error ? [] : (data ?? []);
  } catch {
    return [];
  }
}

async function buildContext(admin: SupabaseClient, message: string): Promise<string> {
  const text = norm(message);
  const cities = await safeSelect(admin.from("cities").select("id, name_bg, name_en, slug"));
  const cityHits = cities.filter((c) => mentions(text, c.name_bg as string) || mentions(text, c.name_en as string));
  const cityIds = new Set(cityHits.map((c) => c.id as string));
  const cityName = (id: unknown) => {
    const c = cities.find((x) => x.id === id);
    return c ? `${c.name_bg} / ${c.name_en}` : "";
  };

  const gyms = await safeSelect(admin.from("gyms_with_coords").select("*").limit(500));
  const gymHits = gyms.filter((g) => mentions(text, g.name as string) || mentions(text, g.name_latin as string));
  const keyword = KEYWORDS.some((k) => text.includes(k));
  if (!keyword && cityHits.length === 0 && gymHits.length === 0) return "";

  const parts: string[] = [];
  let relevantGyms = gymHits;
  if (cityIds.size > 0) relevantGyms = [...relevantGyms, ...gyms.filter((g) => cityIds.has(g.city_id as string))];
  relevantGyms = [...new Map(relevantGyms.map((g) => [g.id, g])).values()].slice(0, 25);
  if (relevantGyms.length > 0) {
    parts.push("Gyms:\n" + relevantGyms.map((g) => {
      const fields = [
        `name: ${g.name}`,
        g.name_latin ? `latin: ${g.name_latin}` : "",
        `city: ${cityName(g.city_id)}`,
        g.address ? `address: ${g.address}` : "",
        g.affiliation ? `affiliation: ${g.affiliation}` : "",
        g.phone ? `phone: ${g.phone}` : "",
        g.website ? `website: ${g.website}` : "",
        g.instagram ? `instagram: ${g.instagram}` : "",
        g.price_drop_in != null ? `drop-in: ${g.price_drop_in} ${g.currency ?? ""}` : "",
        g.price_monthly != null ? `monthly: ${g.price_monthly} ${g.currency ?? ""}` : "",
        g.rating_avg != null ? `rating: ${g.rating_avg} (${g.rating_count})` : "",
        g.verified ? "verified" : "unverified listing",
      ].filter(Boolean);
      return "- " + fields.join("; ");
    }).join("\n"));
  } else if (keyword && cityIds.size === 0) {
    // Generic question: give a city-level overview.
    const counts = new Map<string, number>();
    for (const g of gyms) counts.set(cityName(g.city_id), (counts.get(cityName(g.city_id)) ?? 0) + 1);
    parts.push("Gym count per city: " + [...counts.entries()].map(([c, n]) => `${c}: ${n}`).join(", "));
  }

  const today = new Date().toISOString().slice(0, 10);
  if (EVENT_WORDS.some((k) => text.includes(k)) || (keyword && cityIds.size > 0)) {
    const events = await safeSelect(admin.from("events").select("name, city, venue, starts_at, ends_at, url")
      .gte("ends_at", today).order("starts_at").limit(15));
    if (events.length > 0) {
      parts.push("Upcoming competitions (source: Smoothcomp):\n" + events.map((e) =>
        `- ${e.name}; ${String(e.starts_at).slice(0, 10)}${e.city ? "; " + e.city : ""}${e.venue ? "; " + e.venue : ""}; ${e.url ?? ""}`
      ).join("\n"));
    } else if (EVENT_WORDS.some((k) => text.includes(k))) {
      parts.push("Upcoming competitions: none in the app data.");
    }
  }

  if (OPENMAT_WORDS.some((k) => text.includes(k)) || (keyword && cityIds.size > 0)) {
    const mats = await safeSelect(admin.from("open_mats").select("starts_at, ends_at, style, fee, currency, notes, verified, gym_id")
      .gte("starts_at", new Date().toISOString()).order("starts_at").limit(40));
    const filtered = mats.filter((m) => {
      if (cityIds.size === 0) return true;
      const g = gyms.find((x) => x.id === m.gym_id);
      return g ? cityIds.has(g.city_id as string) : false;
    }).slice(0, 15);
    if (filtered.length > 0) {
      parts.push("Upcoming open mats (times in UTC; Bulgaria is UTC+2/UTC+3):\n" + filtered.map((m) => {
        const g = gyms.find((x) => x.id === m.gym_id);
        return `- ${g?.name ?? "gym"}; ${m.starts_at} – ${m.ends_at}; ${m.style}` +
          `${m.fee != null ? "; fee " + m.fee + " " + m.currency : ""}; ${m.verified ? "verified" : "unverified"}` +
          `${m.notes ? "; " + m.notes : ""}`;
      }).join("\n"));
    } else if (OPENMAT_WORDS.some((k) => text.includes(k))) {
      parts.push("Upcoming open mats: none in the app data" + (cityIds.size > 0 ? " for that city." : "."));
    }
  }

  return parts.join("\n\n").slice(0, 12000);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "unauthorized" }, 401);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  const user = userData?.user;
  if (userError || !user) return json({ error: "unauthorized" }, 401);

  let body: { message?: string; conversation_id?: string; locale?: string; action?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  if (body.action === "usage") {
    const { data: used } = await admin.rpc("ai_used_today", { p_user: user.id });
    return json({ remaining: Math.max(DAILY_LIMIT - Number(used ?? 0), 0), limit: DAILY_LIMIT });
  }

  const message = (body.message ?? "").trim();
  if (!message) return json({ error: "empty_message" }, 400);
  if (message.length > MAX_INPUT) return json({ error: "message_too_long" }, 400);
  if (!AI_API_KEY) return json({ error: "ai_not_configured" }, 503);

  const { data: remaining, error: quotaError } = await admin.rpc("ai_try_consume", { p_user: user.id, p_limit: DAILY_LIMIT });
  if (quotaError) return json({ error: "quota_unavailable", detail: quotaError.message }, 500);
  if (Number(remaining) < 0) return json({ error: "daily_limit", remaining: 0, limit: DAILY_LIMIT }, 429);

  // Conversation (create or verify ownership) + recent history.
  let conversationId = body.conversation_id ?? null;
  let history: { role: string; content: string }[] = [];
  if (conversationId) {
    const { data: conv } = await admin.from("ai_conversations").select("id, user_id").eq("id", conversationId).maybeSingle();
    if (!conv || conv.user_id !== user.id) conversationId = null;
  }
  if (conversationId) {
    const { data: rows } = await admin.from("ai_messages").select("role, content")
      .eq("conversation_id", conversationId).order("created_at", { ascending: false }).limit(12);
    history = (rows ?? []).reverse();
  } else {
    const { data: conv } = await admin.from("ai_conversations")
      .insert({ user_id: user.id, title: message.slice(0, 80) }).select("id").single();
    conversationId = conv?.id ?? null;
  }

  const context = await buildContext(admin, message);
  const locale = body.locale === "bg" ? "bg" : "en";
  const system = SYSTEM_PROMPT +
    `\nApp locale hint: ${locale === "bg" ? "Bulgarian" : "English"}.` +
    `\nToday's date: ${new Date().toISOString().slice(0, 10)}.` +
    `\n\nApp data (the only source for Bulgarian gyms/events/open mats; may be incomplete):\n` +
    (context || "(no matching app data for this question)");

  let reply = "";
  try {
    const res = await fetch(`${AI_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { authorization: `Bearer ${AI_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({
        model: AI_MODEL,
        temperature: 0.4,
        max_tokens: 900,
        messages: [{ role: "system", content: system }, ...history, { role: "user", content: message }],
      }),
    });
    if (!res.ok) throw new Error(`AI ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const data = await res.json();
    reply = String(data?.choices?.[0]?.message?.content ?? "").trim();
    if (!reply) throw new Error("empty AI response");
  } catch (e) {
    await admin.rpc("ai_refund", { p_user: user.id });
    console.error(e);
    return json({ error: "ai_failed" }, 502);
  }

  if (conversationId) {
    await admin.from("ai_messages").insert([
      { conversation_id: conversationId, user_id: user.id, role: "user", content: message },
      { conversation_id: conversationId, user_id: user.id, role: "assistant", content: reply.slice(0, 20000) },
    ]);
    await admin.from("ai_conversations").update({ updated_at: new Date().toISOString() }).eq("id", conversationId);
  }

  return json({ reply, conversation_id: conversationId, remaining: Number(remaining), limit: DAILY_LIMIT });
});
