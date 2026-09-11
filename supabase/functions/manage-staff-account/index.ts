import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ProvisionRequest = {
  action: "provision_staff";
  email: string;
  phone: string;
  password: string;
  full_name: string;
  initials: string;
  role: "ADMIN" | "CAPTAIN" | "SUPERVISOR";
  reason: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "method not allowed" }, { status: 405 });
  }
  if (!supabaseUrl || !serviceRoleKey) {
    return Response.json(
      { error: "staff account management is not configured" },
      { status: 500 },
    );
  }

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return Response.json({ error: "authentication required" }, { status: 401 });
  }

  let body: ProvisionRequest;
  try {
    body = await request.json();
  } catch (_) {
    return Response.json({ error: "invalid request body" }, { status: 400 });
  }

  if (body.action !== "provision_staff") {
    return Response.json({ error: "unsupported action" }, { status: 400 });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const caller = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { authorization } },
    auth: { persistSession: false },
  });

  const { data: authUser, error: createError } =
    await admin.auth.admin.createUser({
      email: body.email,
      password: body.password,
      email_confirm: true,
      user_metadata: {
        provisioned_by: "manage-staff-account",
        intended_role: body.role,
        contact_phone: body.phone,
      },
    });

  if (createError || !authUser.user) {
    return Response.json(
      { error: createError?.message ?? "staff Auth account was not created" },
      { status: 400 },
    );
  }

  const { data, error } = await caller.rpc("provision_staff_profile", {
    p_auth_user_id: authUser.user.id,
    p_role: body.role,
    p_full_name: body.full_name,
    p_initials: body.initials,
    p_phone_e164: body.phone,
    p_reason: body.reason,
  });

  if (error) {
    await admin.auth.admin.deleteUser(authUser.user.id).catch(() => undefined);
    return Response.json({ error: error.message }, { status: 400 });
  }

  return Response.json({ user_id: Array.isArray(data) ? data[0] : data });
});
