begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

select has_function(
  'public',
  'provision_staff_profile',
  array['uuid', 'public.app_role', 'text', 'text', 'text', 'text'],
  'staff profile provisioning RPC exists'
);

select has_function(
  'public',
  'staff_directory',
  array['text', 'public.app_role', 'public.account_status', 'integer', 'integer'],
  'staff directory RPC exists'
);

select has_function(
  'public',
  'worker_directory',
  array['text', 'public.account_status', 'public.worker_category', 'integer', 'integer'],
  'paginated worker directory RPC exists'
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
    '00000000-0000-0000-0000-000000094001',
    'authenticated',
    'authenticated',
    '+919876594001',
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
    '00000000-0000-0000-0000-000000094002',
    'authenticated',
    'authenticated',
    '+919876594002',
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
    '00000000-0000-0000-0000-000000094003',
    'authenticated',
    'authenticated',
    '+919876594003',
    crypt('worker-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000094101',
    'authenticated',
    'authenticated',
    '+919876594101',
    crypt('staff-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000094102',
    'authenticated',
    'authenticated',
    '+919876594102',
    crypt('staff-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  );

select set_config('app.bypass_identity_protection', 'on', true);

insert into public.profiles (id, worker_number, role, full_name, initials, phone_e164, account_status, profile_completed_at, profile_photo_path)
values
  ('00000000-0000-0000-0000-000000094001', null, 'SUPER_ADMIN', 'R4 Super', 'RS', '+919876594001', 'ACTIVE', now(), '00000000-0000-0000-0000-000000094001/profile.webp'),
  ('00000000-0000-0000-0000-000000094002', null, 'ADMIN', 'R4 Admin', 'RA', '+919876594002', 'ACTIVE', now(), '00000000-0000-0000-0000-000000094002/profile.webp'),
  ('00000000-0000-0000-0000-000000094003', nextval('public.worker_number_seq'), 'WORKER', 'R4 Worker', 'RW', '+919876594003', 'ACTIVE', now(), '00000000-0000-0000-0000-000000094003/profile.webp');

insert into public.worker_profiles (
  user_id,
  category,
  last_worker_category,
  date_of_birth,
  address,
  native_place,
  height_cm,
  education_status,
  has_previous_experience
)
values (
  '00000000-0000-0000-0000-000000094003',
  'F',
  'F',
  (current_date - interval '20 years')::date,
  'Address',
  'Native',
  170,
  'College',
  false
);

select set_config('app.bypass_identity_protection', 'off', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000094001', true);

select lives_ok(
  $$
    select *
    from public.provision_staff_profile(
      '00000000-0000-0000-0000-000000094101',
      'ADMIN',
      'New Admin',
      'NA',
      '+919876594101',
      'Create first Admin'
    )
  $$,
  'Super Admin can provision an Admin profile for an existing Auth account'
);

select is(
  (
    select role
    from public.profiles
    where id = '00000000-0000-0000-0000-000000094101'
  ),
  'ADMIN'::public.app_role,
  'provisioning stores the requested staff role'
);

select is(
  (
    select count(*)
    from public.audit_logs
    where entity_id = '00000000-0000-0000-0000-000000094101'
      and action = 'staff_profile_provisioned'
  ),
  1::bigint,
  'staff provisioning is audited'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000094002', true);

select throws_ok(
  $$
    select *
    from public.provision_staff_profile(
      '00000000-0000-0000-0000-000000094102',
      'ADMIN',
      'Blocked Admin',
      'BA',
      '+919876594102',
      'Admin creates Admin'
    )
  $$,
  'P0001',
  'Admin cannot provision Admin accounts',
  'Admin cannot provision another Admin'
);

select lives_ok(
  $$
    select *
    from public.provision_staff_profile(
      '00000000-0000-0000-0000-000000094102',
      'CAPTAIN',
      'New Captain',
      'NC',
      '+919876594102',
      'Create Captain'
    )
  $$,
  'Admin can provision Captain profiles'
);

select is(
  (
    select count(*)
    from public.staff_directory(null, null, 'ACTIVE', 10, 0)
  ),
  1::bigint,
  'Admin staff directory hides Admin accounts and includes field staff'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000094002', true);

select throws_ok(
  $$
    select *
    from public.provision_staff_profile(
      '00000000-0000-0000-0000-000000094101',
      'SUPERVISOR',
      'Duplicate Profile',
      'DP',
      '+919876594102',
      'Duplicate profile'
    )
  $$,
  'P0001',
  'phone number already belongs to another profile',
  'duplicate profile creation is blocked before overwrite'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000094003', true);

select throws_ok(
  $$ select * from public.staff_directory(null, null, null, 10, 0) $$,
  'P0001',
  'not authorized to view staff directory',
  'Worker cannot view staff directory'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000094001', true);

select is(
  (
    select full_name
    from public.worker_directory(null, null, null, 1, 0)
  ),
  'R4 Worker',
  'paginated worker directory returns first worker'
);

select is(
  (
    select count(*)
    from public.worker_directory(null, null, null, 1, 1)
  ),
  0::bigint,
  'worker directory offset advances the result window'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000094002', true);

select throws_ok(
  $$
    select public.change_user_phone(
      '00000000-0000-0000-0000-000000094101',
      '+919876594999',
      'Admin tries Admin phone'
    )
  $$,
  'P0001',
  'Admin cannot manage Admin or Super Admin authority',
  'Admin cannot reassign Admin phone numbers'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000094001', true);

select lives_ok(
  $$
    select public.change_user_phone(
      '00000000-0000-0000-0000-000000094102',
      '+919876594222',
      'Correct field staff phone'
    )
  $$,
  'Super Admin can reassign field staff phone through the controlled RPC'
);

select is(
  (
    select count(*)
    from public.phone_change_history
    where target_user_id = '00000000-0000-0000-0000-000000094102'
      and new_phone_e164 = '+919876594222'
  ),
  1::bigint,
  'phone reassignment records history'
);

select * from finish();

rollback;
