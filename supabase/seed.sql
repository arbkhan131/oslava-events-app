-- Local development bootstrap data.
-- This file is loaded by `npx supabase db reset` for the local Supabase stack.
-- It intentionally refuses to run unless the database is using Supabase CLI's
-- local JWT secret, so these fake accounts cannot be seeded into a hosted
-- project by accident.

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
    phone,
    phone_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    is_sso_user,
    is_anonymous
  )
  values
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000001',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!01', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000001',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"SUPER_ADMIN","full_name":"Local Dev Super Admin"}'::jsonb,
      false,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000002',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!02', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000002',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"ADMIN","full_name":"Local Dev Admin"}'::jsonb,
      false,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000003',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!03', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000003',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"CAPTAIN","full_name":"Local Dev Captain"}'::jsonb,
      false,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000004',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!04', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000004',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"SUPERVISOR","full_name":"Local Dev Supervisor"}'::jsonb,
      false,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000005',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!05', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000005',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"WORKER","category":"F","full_name":"Local Dev Worker F"}'::jsonb,
      false,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000006',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!06', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000006',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"WORKER","category":"C","full_name":"Local Dev Worker C"}'::jsonb,
      false,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000007',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!07', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000007',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"WORKER","category":"B","full_name":"Local Dev Worker B"}'::jsonb,
      false,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      '10000000-0000-0000-0000-000000000008',
      'authenticated',
      'authenticated',
      extensions.crypt('OslavaDev!08', extensions.gen_salt('bf')),
      '',
      '',
      '',
      '',
      '',
      '',
      '919000000008',
      now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      '{"local_dev":true,"role":"WORKER","category":"A","full_name":"Local Dev Worker A"}'::jsonb,
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
      phone = excluded.phone,
      phone_confirmed_at = excluded.phone_confirmed_at,
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
    u.phone,
    u.id,
    jsonb_build_object(
      'sub', u.id::text,
      'phone', u.phone,
      'phone_verified', true,
      'local_dev', true
    ),
    'phone',
    now(),
    now(),
    now()
  from auth.users u
  where u.id in (
    '10000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000006',
    '10000000-0000-0000-0000-000000000007',
    '10000000-0000-0000-0000-000000000008'
  )
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
  values
    (
      '10000000-0000-0000-0000-000000000001',
      null,
      'SUPER_ADMIN',
      'Local Dev Super Admin',
      'SA',
      '+919000000001',
      null,
      null,
      'ACTIVE'
    ),
    (
      '10000000-0000-0000-0000-000000000002',
      null,
      'ADMIN',
      'Local Dev Admin',
      'AD',
      '+919000000002',
      null,
      null,
      'ACTIVE'
    ),
    (
      '10000000-0000-0000-0000-000000000003',
      null,
      'CAPTAIN',
      'Local Dev Captain',
      'CA',
      '+919000000003',
      null,
      null,
      'ACTIVE'
    ),
    (
      '10000000-0000-0000-0000-000000000004',
      null,
      'SUPERVISOR',
      'Local Dev Supervisor',
      'SV',
      '+919000000004',
      null,
      null,
      'ACTIVE'
    ),
    (
      '10000000-0000-0000-0000-000000000005',
      nextval('public.worker_number_seq'),
      'WORKER',
      'Local Dev Worker F',
      'WF',
      '+919000000005',
      '10000000-0000-0000-0000-000000000005/local-dev-profile.jpg',
      now(),
      'ACTIVE'
    ),
    (
      '10000000-0000-0000-0000-000000000006',
      nextval('public.worker_number_seq'),
      'WORKER',
      'Local Dev Worker C',
      'WC',
      '+919000000006',
      '10000000-0000-0000-0000-000000000006/local-dev-profile.jpg',
      now(),
      'ACTIVE'
    ),
    (
      '10000000-0000-0000-0000-000000000007',
      nextval('public.worker_number_seq'),
      'WORKER',
      'Local Dev Worker B',
      'WB',
      '+919000000007',
      '10000000-0000-0000-0000-000000000007/local-dev-profile.jpg',
      now(),
      'ACTIVE'
    ),
    (
      '10000000-0000-0000-0000-000000000008',
      nextval('public.worker_number_seq'),
      'WORKER',
      'Local Dev Worker A',
      'WA',
      '+919000000008',
      '10000000-0000-0000-0000-000000000008/local-dev-profile.jpg',
      now(),
      'ACTIVE'
    )
  on conflict (id) do update
  set role = excluded.role,
      full_name = excluded.full_name,
      initials = excluded.initials,
      phone_e164 = excluded.phone_e164,
      profile_photo_path = excluded.profile_photo_path,
      profile_completed_at = excluded.profile_completed_at,
      account_status = excluded.account_status;

  insert into public.worker_profiles (
    user_id,
    category,
    last_worker_category,
    date_of_birth,
    address,
    native_place,
    height_cm,
    education_status,
    has_previous_experience,
    experience_details,
    reliability_score,
    reliability_config_version
  )
  values
    (
      '10000000-0000-0000-0000-000000000005',
      'F',
      'F',
      date '2000-01-05',
      'Local development address 5, Test Nagar, Pune',
      'Pune',
      170,
      'Graduate',
      false,
      'Local development fixture worker, category F.',
      null,
      null
    ),
    (
      '10000000-0000-0000-0000-000000000006',
      'C',
      'C',
      date '2000-01-06',
      'Local development address 6, Test Nagar, Pune',
      'Pune',
      171,
      'Graduate',
      true,
      'Local development fixture worker, category C.',
      null,
      null
    ),
    (
      '10000000-0000-0000-0000-000000000007',
      'B',
      'B',
      date '2000-01-07',
      'Local development address 7, Test Nagar, Pune',
      'Pune',
      172,
      'Graduate',
      true,
      'Local development fixture worker, category B.',
      null,
      null
    ),
    (
      '10000000-0000-0000-0000-000000000008',
      'A',
      'A',
      date '2000-01-08',
      'Local development address 8, Test Nagar, Pune',
      'Pune',
      173,
      'Graduate',
      true,
      'Local development fixture worker, category A.',
      null,
      null
    )
  on conflict (user_id) do update
  set category = excluded.category,
      last_worker_category = excluded.last_worker_category,
      date_of_birth = excluded.date_of_birth,
      address = excluded.address,
      native_place = excluded.native_place,
      height_cm = excluded.height_cm,
      education_status = excluded.education_status,
      has_previous_experience = excluded.has_previous_experience,
      experience_details = excluded.experience_details;

  insert into storage.objects (
    bucket_id,
    name,
    owner,
    owner_id,
    metadata
  )
  values
    (
      'profile-photos',
      '10000000-0000-0000-0000-000000000005/local-dev-profile.jpg',
      '10000000-0000-0000-0000-000000000005',
      '10000000-0000-0000-0000-000000000005',
      '{"mimetype":"image/jpeg","size":1024,"local_dev_fixture":true}'::jsonb
    ),
    (
      'profile-photos',
      '10000000-0000-0000-0000-000000000006/local-dev-profile.jpg',
      '10000000-0000-0000-0000-000000000006',
      '10000000-0000-0000-0000-000000000006',
      '{"mimetype":"image/jpeg","size":1024,"local_dev_fixture":true}'::jsonb
    ),
    (
      'profile-photos',
      '10000000-0000-0000-0000-000000000007/local-dev-profile.jpg',
      '10000000-0000-0000-0000-000000000007',
      '10000000-0000-0000-0000-000000000007',
      '{"mimetype":"image/jpeg","size":1024,"local_dev_fixture":true}'::jsonb
    ),
    (
      'profile-photos',
      '10000000-0000-0000-0000-000000000008/local-dev-profile.jpg',
      '10000000-0000-0000-0000-000000000008',
      '10000000-0000-0000-0000-000000000008',
      '{"mimetype":"image/jpeg","size":1024,"local_dev_fixture":true}'::jsonb
    )
  on conflict (bucket_id, name) do update
  set owner = excluded.owner,
      owner_id = excluded.owner_id,
      metadata = excluded.metadata,
      updated_at = now();

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason
  )
  values
    (
      '10000000-0000-0000-0000-000000000001',
      null,
      'SUPER_ADMIN',
      '10000000-0000-0000-0000-000000000001',
      'SUPER_ADMIN',
      'Local development bootstrap'
    ),
    (
      '10000000-0000-0000-0000-000000000002',
      null,
      'ADMIN',
      '10000000-0000-0000-0000-000000000001',
      'SUPER_ADMIN',
      'Local development bootstrap'
    ),
    (
      '10000000-0000-0000-0000-000000000003',
      null,
      'CAPTAIN',
      '10000000-0000-0000-0000-000000000001',
      'SUPER_ADMIN',
      'Local development bootstrap'
    ),
    (
      '10000000-0000-0000-0000-000000000004',
      null,
      'SUPERVISOR',
      '10000000-0000-0000-0000-000000000001',
      'SUPER_ADMIN',
      'Local development bootstrap'
    )
  on conflict do nothing;

  insert into public.worker_category_history (
    worker_id,
    old_category,
    new_category,
    action,
    actor_id,
    actor_role,
    reason
  )
  values
    (
      '10000000-0000-0000-0000-000000000005',
      null,
      'F',
      'INITIAL_ASSIGNMENT',
      '10000000-0000-0000-0000-000000000001',
      'SUPER_ADMIN',
      'Local development bootstrap'
    ),
    (
      '10000000-0000-0000-0000-000000000006',
      null,
      'C',
      'INITIAL_ASSIGNMENT',
      '10000000-0000-0000-0000-000000000001',
      'SUPER_ADMIN',
      'Local development bootstrap'
    ),
    (
      '10000000-0000-0000-0000-000000000007',
      null,
      'B',
      'INITIAL_ASSIGNMENT',
      '10000000-0000-0000-0000-000000000001',
      'SUPER_ADMIN',
      'Local development bootstrap'
    ),
    (
      '10000000-0000-0000-0000-000000000008',
      null,
      'A',
      'INITIAL_ASSIGNMENT',
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
  select
    '10000000-0000-0000-0000-000000000001',
    'SUPER_ADMIN',
    'local_development_account_bootstrapped',
    'profile',
    p.id,
    jsonb_build_object(
      'role', p.role,
      'phone_e164', p.phone_e164,
      'account_status', p.account_status
    ),
    'Local development bootstrap',
    'seed'
  from public.profiles p
  where p.id in (
    '10000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000006',
    '10000000-0000-0000-0000-000000000007',
    '10000000-0000-0000-0000-000000000008'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);
exception
  when others then
    perform set_config('app.bypass_identity_protection', 'off', true);
    raise;
end
$$;
