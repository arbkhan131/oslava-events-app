begin;

create extension if not exists pgtap with schema extensions;

select plan(42);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'worker_profiles', 'worker_profiles table exists');
select has_table('public', 'role_history', 'role_history table exists');
select has_table('public', 'worker_category_history', 'worker_category_history table exists');
select has_table('public', 'phone_change_history', 'phone_change_history table exists');
select has_table(
  'public',
  'password_recovery_challenges',
  'password recovery challenge table exists'
);

select has_function(
  'public',
  'complete_worker_registration',
  array[
    'text',
    'text',
    'text',
    'date',
    'text',
    'text',
    'numeric',
    'text',
    'boolean',
    'text'
  ],
  'worker registration RPC exists'
);

select has_function(
  'public',
  'change_user_phone',
  array['uuid', 'text', 'text'],
  'phone reassignment RPC exists'
);

select has_function(
  'public',
  'start_password_recovery',
  array['text', 'text'],
  'SMS OTP recovery start RPC exists'
);

select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'INSERT'),
  'authenticated users cannot directly insert profiles'
);

select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'UPDATE'),
  'authenticated users cannot directly update profiles'
);

select ok(
  not has_table_privilege('authenticated', 'public.worker_profiles', 'INSERT'),
  'authenticated users cannot directly insert worker profiles'
);

select ok(
  not has_table_privilege('anon', 'public.profiles', 'SELECT'),
  'anon cannot read profiles'
);

insert into auth.users (
  id,
  aud,
  role,
  phone,
  encrypted_password,
  phone_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_sso_user,
  is_anonymous,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000101',
    'authenticated',
    'authenticated',
    '+919876543210',
    crypt('password-one', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    'authenticated',
    'authenticated',
    '+919876543211',
    crypt('password-two', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000201',
    'authenticated',
    'authenticated',
    '+919876543301',
    crypt('admin-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000202',
    'authenticated',
    'authenticated',
    '+919876543302',
    crypt('super-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000203',
    'authenticated',
    'authenticated',
    '+919876543303',
    crypt('captain-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  );

select set_config('app.bypass_identity_protection', 'on', true);

insert into public.profiles (
  id,
  role,
  full_name,
  initials,
  phone_e164,
  account_status
)
values
  (
    '00000000-0000-0000-0000-000000000201',
    'ADMIN',
    'Admin User',
    'AU',
    '+919876543301',
    'ACTIVE'
  ),
  (
    '00000000-0000-0000-0000-000000000202',
    'SUPER_ADMIN',
    'Super Admin',
    'SA',
    '+919876543302',
    'ACTIVE'
  ),
  (
    '00000000-0000-0000-0000-000000000203',
    'CAPTAIN',
    'Captain User',
    'CU',
    '+919876543303',
    'ACTIVE'
  );

select set_config('app.bypass_identity_protection', 'off', true);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000101',
  true
);

select lives_ok(
  $$
    select *
    from public.complete_worker_registration(
      'Worker One',
      'WO',
      '00000000-0000-0000-0000-000000000101/profile.webp',
      (current_date - interval '19 years')::date,
      'Pune',
      'Nashik',
      172.5,
      'College',
      true,
      'Events'
    )
  $$,
  'adult Worker registration completes'
);

select is(
  (
    select role
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000101'
  ),
  'WORKER'::public.app_role,
  'registered user role is WORKER'
);

select is(
  (
    select account_status
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000101'
  ),
  'ACTIVE'::public.account_status,
  'registered Worker starts ACTIVE'
);

select isnt(
  (
    select worker_number
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000101'
  ),
  null,
  'registered Worker receives generated operational Worker ID'
);

select is(
  (
    select category
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000000101'
  ),
  'F'::public.worker_category,
  'registered Worker starts in F category'
);

select is(
  (
    select phone_e164
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000101'
  ),
  '+919876543210',
  'profile phone comes from Auth phone identity'
);

select is(
  (
    select count(*)
    from public.worker_category_history
    where worker_id = '00000000-0000-0000-0000-000000000101'
      and action = 'INITIAL_ASSIGNMENT'
      and new_category = 'F'
  ),
  1::bigint,
  'initial category assignment is audited'
);

select throws_ok(
  $$
    insert into public.profiles (
      id,
      worker_number,
      role,
      full_name,
      initials,
      phone_e164,
      profile_photo_path,
      profile_completed_at
    )
    values (
      '00000000-0000-0000-0000-000000000999',
      999999,
      'WORKER',
      'Direct Insert',
      'DI',
      '+919876549999',
      '00000000-0000-0000-0000-000000000999/profile.webp',
      now()
    )
  $$,
  'P0001',
  'identity records must be changed through controlled functions',
  'direct profile inserts are rejected by trigger'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000102',
  true
);

select throws_ok(
  $$
    select *
    from public.complete_worker_registration(
      'Under Age',
      'UA',
      '00000000-0000-0000-0000-000000000102/profile.webp',
      (current_date - interval '17 years')::date,
      'Pune',
      'Pune',
      160::numeric,
      'School',
      false,
      null
    )
  $$,
  'P0001',
  'worker must be at least 18 years old',
  'under-18 Worker registration is rejected'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000201',
  true
);

select lives_ok(
  $$
    select public.change_user_phone(
      '00000000-0000-0000-0000-000000000101',
      '+919876543299',
      'Manual identity verification complete'
    )
  $$,
  'Admin can reassign a Worker phone after manual verification'
);

select is(
  (
    select phone_e164
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000101'
  ),
  '+919876543299',
  'profile phone changes without creating a second account'
);

select is(
  (
    select phone
    from auth.users
    where id = '00000000-0000-0000-0000-000000000101'
  ),
  '+919876543299',
  'Auth phone is changed with the profile phone'
);

select is(
  (
    select count(*)
    from public.phone_change_history
    where target_user_id = '00000000-0000-0000-0000-000000000101'
      and old_phone_e164 = '+919876543210'
      and new_phone_e164 = '+919876543299'
      and actor_id = '00000000-0000-0000-0000-000000000201'
  ),
  1::bigint,
  'phone reassignment is audited with actor and old/new numbers'
);

select throws_ok(
  $$
    select public.change_user_phone(
      '00000000-0000-0000-0000-000000000202',
      '+919876543298',
      'Attempt to change Super Admin phone'
    )
  $$,
  'P0001',
  'Admin cannot manage Admin or Super Admin authority',
  'Admin cannot reassign Super Admin phone'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000202',
  true
);

select lives_ok(
  $$
    select public.change_user_phone(
      '00000000-0000-0000-0000-000000000201',
      '+919876543398',
      'Super Admin verified Admin identity'
    )
  $$,
  'Super Admin can reassign an Admin phone through controlled flow'
);

select is(
  (
    select count(*)
    from public.phone_change_history
    where target_user_id = '00000000-0000-0000-0000-000000000201'
      and old_phone_e164 = '+919876543301'
      and new_phone_e164 = '+919876543398'
      and actor_id = '00000000-0000-0000-0000-000000000202'
      and actor_role = 'SUPER_ADMIN'
  ),
  1::bigint,
  'Super Admin phone reassignment of Admin is audited'
);

select lives_ok(
  $$
    select public.change_user_role(
      '00000000-0000-0000-0000-000000000101',
      'CAPTAIN',
      'Promoted to field role',
      null
    )
  $$,
  'Admin can move Worker to Captain'
);

select is(
  (
    select category
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000000101'
  ),
  null,
  'Worker category is null while active role is Captain'
);

select lives_ok(
  $$
    select public.change_user_role(
      '00000000-0000-0000-0000-000000000101',
      'WORKER',
      'Returned to Worker',
      null
    )
  $$,
  'Admin can return Captain to Worker'
);

select is(
  (
    select category
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000000101'
  ),
  'F'::public.worker_category,
  'previous Worker category is restored by default'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000203',
  true
);

select throws_ok(
  $$
    select public.change_user_phone(
      '00000000-0000-0000-0000-000000000101',
      '+919876543297',
      'Captain attempt'
    )
  $$,
  'P0001',
  'only Admin or Super Admin can change phone numbers',
  'Captain cannot reassign phone numbers'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000202',
  true
);

select lives_ok(
  $$
    select public.provision_staff_profile(
      '00000000-0000-0000-0000-000000000102',
      'SUPERVISOR',
      'Supervisor User',
      'SU',
      '+919876543211',
      'Pre-provisioned field staff account'
    )
  $$,
  'Super Admin can provision a non-Worker staff profile'
);

select is(
  (
    select worker_number
    from public.profiles
    where id = '00000000-0000-0000-0000-000000000102'
  ),
  null,
  'non-Worker staff profile does not receive Worker ID'
);

select throws_ok(
  $$
    select public.start_password_recovery('+919876543299', 'staging')
  $$,
  'P0001',
  'invalid recovery provider environment',
  'recovery provider environment is constrained'
);

select lives_ok(
  $$
    select public.start_password_recovery('+919876543299', 'development')
  $$,
  'password recovery challenge can be started for an active registered phone'
);

select is(
  (
    select provider_environment
    from public.password_recovery_challenges
    where phone_e164 = '+919876543299'
    order by created_at desc
    limit 1
  ),
  'development',
  'password recovery records the selected provider environment'
);

select is(
  (
    select file_size_limit
    from storage.buckets
    where id = 'profile-photos'
  ),
  5242880::bigint,
  'profile photo bucket has 5 MB source upload limit'
);

select is(
  (
    select allowed_mime_types
    from storage.buckets
    where id = 'profile-photos'
  ),
  array['image/jpeg', 'image/png', 'image/webp']::text[],
  'profile photo bucket allows only approved image MIME types'
);

select is(
  (
    select public
    from storage.buckets
    where id = 'profile-photos'
  ),
  false,
  'profile photo bucket is private'
);

select * from finish();

rollback;
