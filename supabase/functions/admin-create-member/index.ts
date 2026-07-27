// Edge Function: admin-create-member
// Creates an auth user + profile (+ client_account if role=client).
// Runs server-side; uses the service-role key that Supabase injects automatically
// (never exposed to the app). Only callers with role='admin' are allowed.

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

    // 1) verify the caller is an admin
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);
    const { data: me } = await caller.from("profiles").select("role").eq("id", user.id).single();
    if (!me || me.role !== "admin") return json({ error: "forbidden: admin only" }, 403);

    // 2) validate input
    const body = await req.json();
    const { full_name, email, password, phone, role, business_name, redirect_to } = body ?? {};
    if (!email || !role) {
      return json({ error: "email and role are required" }, 400);
    }

    // 3) create the user + profile.
    //    - password given  → create directly with a temp password (NO email/SMTP needed).
    //    - no password     → invite by email (needs SMTP + allowed redirect URL).
    const admin = createClient(url, serviceKey);
    let uid: string;
    let status = "active";

    if (password) {
      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { full_name, role },
      });
      if (cErr) return json({ error: cErr.message }, 400);
      uid = created.user!.id;
    } else {
      const redirectTo = redirect_to ?? Deno.env.get("INVITE_REDIRECT_URL") ?? undefined;
      const { data: invited, error: iErr } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { full_name, role, needs_password: true },
        redirectTo,
      });
      if (iErr) return json({ error: iErr.message }, 400);
      uid = invited.user!.id;
      status = "invited";
    }

    const { error: pErr } = await admin.from("profiles").insert({
      id: uid, full_name, email, phone, role, status, created_by: user.id,
    });
    if (pErr) return json({ error: pErr.message }, 400);

    // 4) client role → also create a linked client_account
    if (role === "client") {
      await admin.from("client_accounts").insert({
        business_name: business_name ?? full_name, contact_user_id: uid, email, phone,
      });
    }

    return json({ ok: true, user_id: uid });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
