-- One-time hosted staging reset.
-- Target state:
--   Login number: 8864938636
--   Hidden Auth email: 918864938636@phone.oslava.local
--   Role: SUPER_ADMIN
--
-- This clears staging app/tester data and Auth users, then creates only the
-- requested Super Admin login. Keep privacy/config tables so the app can boot.

begin;

select set_config('app.bypass_identity_protection', 'on', true);

do $$
declare
  table_to_clear record;
  super_id uuid := '10000000-0000-0000-0000-000000000001';
  super_email text := '918864938636@phone.oslava.local';
  super_phone text := '+918864938636';
begin
  for table_to_clear in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public'
      and tablename not in (
        'privacy_terms_versions',
        'reliability_configs',
        'tier_release_presets',
        'scheduled_job_runs'
      )
  loop
    execute format(
      'truncate table %I.%I restart identity cascade',
      table_to_clear.schemaname,
      table_to_clear.tablename
    );
  end loop;

  delete from auth.mfa_amr_claims;
  delete from auth.sessions;
  delete from auth.refresh_tokens;
  delete from auth.identities;
  delete from auth.one_time_tokens;
  delete from auth.flow_state;
  delete from auth.users;

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
    super_id,
    'authenticated',
    'authenticated',
    extensions.crypt('123456', extensions.gen_salt('bf')),
    '',
    '',
    '',
    '',
    '',
    '',
    super_email,
    now(),
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'auth_mode', 'phone_password',
      'phone_e164', super_phone,
      'created_by', 'reset_hosted_staging_super_admin'
    ),
    false,
    now(),
    now(),
    false,
    false
  );

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
  values (
    extensions.gen_random_uuid(),
    super_id::text,
    super_id,
    jsonb_build_object(
      'sub', super_id::text,
      'email', super_email,
      'email_verified', true
    ),
    'email',
    now(),
    now(),
    now()
  );

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
    super_id,
    null,
    'SUPER_ADMIN',
    'Oslava Super Admin',
    'SA',
    super_phone,
    null,
    null,
    'ACTIVE'
  );

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason
  )
  values (
    super_id,
    null,
    'SUPER_ADMIN',
    super_id,
    'SUPER_ADMIN',
    'Hosted staging reset to single Super Admin'
  );

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
    super_id,
    'SUPER_ADMIN',
    'hosted_staging_reset_super_admin',
    'profile',
    super_id,
    jsonb_build_object(
      'role', 'SUPER_ADMIN',
      'phone_e164', super_phone,
      'account_status', 'ACTIVE',
      'hidden_auth_email', super_email
    ),
    'Hosted staging reset to single Super Admin',
    'manual_sql'
  );
end
$$;

select set_config('app.bypass_identity_protection', 'off', true);

commit;
