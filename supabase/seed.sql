-- Local development bootstrap data.
-- This file is loaded by `npx supabase db reset` for the local Supabase stack.
-- It intentionally refuses to run unless the database is using Supabase CLI's
-- local JWT secret, so this local-only bootstrap cannot be seeded into a
-- hosted project by accident.

do $$
begin
  if current_setting('app.settings.jwt_secret', true)
     <> 'super-secret-jwt-token-with-at-least-32-characters-long' then
    raise exception 'Refusing to load local development accounts outside Supabase CLI local stack';
  end if;
end
$$;

do $$
begin
  perform set_config('app.bypass_identity_protection', 'on', true);

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    encrypted_password,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    reauthentication_token,
    email,
    email_confirmed_at,
    phone,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    is_sso_user,
    is_anonymous
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    extensions.crypt('123456', extensions.gen_salt('bf')),
    '',
    '',
    '',
    '',
    '',
    '',
    'arbkh.03.11@gmail.com',
    now(),
    '918864938636',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"local_dev":true,"role":"SUPER_ADMIN","full_name":"Oslava Super Admin"}'::jsonb,
    false,
    now(),
    now(),
    false,
    false
  )
  on conflict (id) do update
  set encrypted_password = excluded.encrypted_password,
      confirmation_token = excluded.confirmation_token,
      recovery_token = excluded.recovery_token,
      email_change_token_new = excluded.email_change_token_new,
      email_change = excluded.email_change,
      email_change_token_current = excluded.email_change_token_current,
      reauthentication_token = excluded.reauthentication_token,
      email = excluded.email,
      email_confirmed_at = excluded.email_confirmed_at,
      phone = excluded.phone,
      raw_app_meta_data = excluded.raw_app_meta_data,
      raw_user_meta_data = excluded.raw_user_meta_data,
      updated_at = now();

  insert into auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  select
    extensions.gen_random_uuid(),
    u.id::text,
    u.id,
    jsonb_build_object(
      'sub', u.id::text,
      'email', u.email,
      'email_verified', true,
      'local_dev', true
    ),
    'email',
    now(),
    now(),
    now()
  from auth.users u
  where u.id = '10000000-0000-0000-0000-000000000001'
  on conflict (provider_id, provider) do update
  set user_id = excluded.user_id,
      identity_data = excluded.identity_data,
      updated_at = now();

  insert into public.profiles (
    id,
    worker_number,
    role,
    full_name,
    initials,
    phone_e164,
    profile_photo_path,
    profile_completed_at,
    account_status
  )
  values (
    '10000000-0000-0000-0000-000000000001',
    null,
    'SUPER_ADMIN',
    'Oslava Super Admin',
    'SA',
    '+918864938636',
    null,
    null,
    'ACTIVE'
  )
  on conflict (id) do update
  set worker_number = excluded.worker_number,
      role = excluded.role,
      full_name = excluded.full_name,
      initials = excluded.initials,
      phone_e164 = excluded.phone_e164,
      profile_photo_path = excluded.profile_photo_path,
      profile_completed_at = excluded.profile_completed_at,
      account_status = excluded.account_status;

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason
  )
  values (
    '10000000-0000-0000-0000-000000000001',
    null,
    'SUPER_ADMIN',
    '10000000-0000-0000-0000-000000000001',
    'SUPER_ADMIN',
    'Local development bootstrap'
  )
  on conflict do nothing;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    after_values,
    reason,
    source
  )
  values (
    '10000000-0000-0000-0000-000000000001',
    'SUPER_ADMIN',
    'local_development_super_admin_bootstrapped',
    'profile',
    '10000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'role', 'SUPER_ADMIN',
      'email', 'arbkh.03.11@gmail.com',
      'phone_e164', '+918864938636',
      'account_status', 'ACTIVE'
    ),
    'Local development bootstrap',
    'seed'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);
exception
  when others then
    perform set_config('app.bypass_identity_protection', 'off', true);
    raise;
end
$$;
