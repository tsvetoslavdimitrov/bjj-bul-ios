// kiosk-invite: turns a kiosk lead into an invited user + pending student membership.
// Called from the kiosk device (signed-in staff JWT). Body: { lead_id: string, redirect_to?: string }
// Uses the service role (auth.admin.inviteUserByEmail), so the caller must be staff of the lead's gym.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth) return json({ error: "unauthorized" }, 401);
  const url = Deno.env.get("SUPABASE_URL")!;
  const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } }, auth: { persistSession: false },
  });
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  let body: { lead_id?: string; redirect_to?: string } = {};
  try { body = await req.json(); } catch { /* empty */ }
  if (!body.lead_id) return json({ error: "lead_id required" }, 400);

  const { data: lead } = await admin.from("kiosk_leads").select("*").eq("id", body.lead_id).maybeSingle();
  if (!lead) return json({ error: "lead not found" }, 404);

  // Caller must be staff of that gym (checked with the caller's own JWT).
  const { data: isStaff, error: staffErr } = await asCaller.rpc("is_gym_staff", { p_gym: lead.gym_id });
  if (staffErr || isStaff !== true) return json({ error: "not allowed" }, 403);

  if (lead.user_id) return json({ user_id: lead.user_id, status: "already_linked" });
  if (!lead.email) return json({ error: "email required" }, 400);

  let userId: string | null = null;
  let status = "invited";
  const invite = await admin.auth.admin.inviteUserByEmail(lead.email, {
    data: { display_name: lead.name },
    redirectTo: body.redirect_to,
  });
  if (invite.error) {
    // Existing account: find it and just link the membership (no new email).
    const { data: existing } = await admin.rpc("kiosk_find_user_by_email", { p_email: lead.email });
    if (!existing) return json({ error: invite.error.message }, 400);
    userId = existing as string;
    status = "existing_user";
  } else {
    userId = invite.data.user?.id ?? null;
  }
  if (!userId) return json({ error: "invite failed" }, 500);

  if (status === "invited") {
    await admin.from("profiles").update({ display_name: lead.name, belt: lead.belt }).eq("id", userId);
  }
  await admin.from("gym_members").upsert(
    { gym_id: lead.gym_id, user_id: userId, role: "student", status: "pending" },
    { onConflict: "gym_id,user_id", ignoreDuplicates: true },
  );
  await admin.from("kiosk_leads").update({ user_id: userId, invited_at: new Date().toISOString() }).eq("id", lead.id);
  return json({ user_id: userId, status });
});
