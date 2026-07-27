// Edge Function: admin-delete-member
// Deletes an auth user (cascades their profile). Admin-only.
// Uses the service-role key Supabase injects automatically (never exposed to the app).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";

    // verify the caller is an admin
    const caller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);
    const { data: me } = await caller.from("profiles").select("role").eq("id", user.id).single();
    if (!me || me.role !== "admin") return json({ error: "forbidden: admin only" }, 403);

    const body = await req.json();
    const { target_user_id } = body ?? {};
    if (!target_user_id) return json({ error: "target_user_id is required" }, 400);
    if (target_user_id === user.id) return json({ error: "you cannot remove yourself" }, 400);

    const admin = createClient(url, serviceKey);
    // clean up client_account link (FK) if any, then delete the auth user (cascades profile)
    await admin.from("client_accounts").update({ contact_user_id: null }).eq("contact_user_id", target_user_id);
    const { error } = await admin.auth.admin.deleteUser(target_user_id);
    if (error) return json({ error: error.message }, 400);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
