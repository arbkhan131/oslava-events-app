import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  phone?: string;
  password?: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function normalizeIndianPhone(input: string): string | null {
  const digits = input.replace(/[^0-9]/g, "");
  const withoutLeadingZero = digits.startsWith("0") && digits.length === 11
    ? digits.slice(1)
    : digits;
  if (withoutLeadingZero.length === 10) return `+91${withoutLeadingZero}`;
  if (withoutLeadingZero.length === 12 && withoutLeadingZero.startsWith("91")) {
    return `+${withoutLeadingZero}`;
  }
  return null;
}

function authEmail(phoneE164: string): string {
  return `${phoneE164.replace(/[^0-9]/g, "")}@phone.oslava.local`;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "method not allowed" }, { status: 405 });
  }
  if (!supabaseUrl || !serviceRoleKey) {
    return Response.json(
      { error: "worker registration is not configured" },
      { status: 500 },
    );
  }

  let body: RequestBody;
  try {
    body = await request.json();
  } catch (_) {
    return Response.json({ error: "invalid request body" }, { status: 400 });
  }

  const phone = normalizeIndianPhone(body.phone ?? "");
  const password = body.password ?? "";
  if (!phone) {
    return Response.json(
      { error: "Enter a valid 10 digit Indian WhatsApp number." },
      { status: 400 },
    );
  }
  if (password.length < 6) {
    return Response.json(
      { error: "Choose a password with at least six characters." },
      { status: 400 },
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data, error } = await admin.auth.admin.createUser({
    email: authEmail(phone),
    password,
    email_confirm: true,
    user_metadata: {
      auth_mode: "phone_password",
      phone_e164: phone,
      created_by: "create-worker-phone-account",
    },
  });

  if (error || !data.user) {
    const message = (error?.message ?? "worker Auth account was not created")
      .toLowerCase();
    if (message.includes("already") || message.includes("registered")) {
      return Response.json(
        { error: "This WhatsApp number is already registered. Sign in to continue." },
        { status: 409 },
      );
    }
    return Response.json(
      { error: error?.message ?? "worker Auth account was not created" },
      { status: 400 },
    );
  }

  return Response.json({ user_id: data.user.id, phone_e164: phone });
});