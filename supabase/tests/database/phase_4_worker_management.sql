begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

select has_table('public', 'assignment_review_flags', 'assignment review flags table exists');

select has_function(
  'public',
  'update_own_profile',
  array[
    'text',
    'text',
    'text',
    'text',
    'numeric',
    'text',
    'boolean',
    'text',
    'text'
  ],
  'own profile update RPC exists'
);

select has_function(
  'public',
  'worker_directory',
  array['text', 'public.account_status', 'public.worker_category', 'integer'],
  'worker directory RPC exists'
);

select has_function(
  'public',
  'worker_history',
  array['uuid'],
  'worker history RPC exists'
);

select has_function(
  'public',
  'change_account_status',
  array['uuid', 'public.account_status', 'text', 'uuid', 'text'],
  'account status RPC exists'
);

select ok(
  not has_table_privilege('authenticated', 'public.assignment_review_flags', 'INSERT'),
  'authenticated users cannot directly insert assignment review flags'
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
    '00000000-0000-0000-0000-000000004001',
    'authenticated',
    'authenticated',
    '+919876544001',
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
    '00000000-0000-0000-0000-000000004002',
    'authenticated',
    'authenticated',
    '+919876544002',
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
    '00000000-0000-0000-0000-000000004003',
    'authenticated',
    'authenticated',
    '+919876544003',
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
    '00000000-0000-0000-0000-000000004004',
    'authenticated',
    'authenticated',
    '+919876544004',
    crypt('captain-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000004005',
    'authenticated',
    'authenticated',
    '+919876544005',
    crypt('supervisor-password', gen_salt('bf')),
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
  '00000000-0000-0000-0000-000000004001',
  nextval('public.worker_number_seq'),
  'WORKER',
  'Worker Four',
  'WF',
  '+919876544001',
  '00000000-0000-0000-0000-000000004001/profile.webp',
  now(),
  'ACTIVE'
);

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
  '00000000-0000-0000-0000-000000004001',
  'F',
  'F',
  (current_date - interval '20 years')::date,
  'Old address',
  'Old native place',
  170,
  'College',
  false
);

insert into public.worker_category_history (
  worker_id,
  old_category,
  new_category,
  action,
  actor_id,
  actor_role,
  reason
)
values (
  '00000000-0000-0000-0000-000000004001',
  null,
  'F',
  'INITIAL_ASSIGNMENT',
  '00000000-0000-0000-0000-000000004001',
  'WORKER',
  'Worker management fixture'
);

insert into public.profiles (id, role, full_name, initials, phone_e164, account_status)
values
  (
    '00000000-0000-0000-0000-000000004002',
    'ADMIN',
    'Admin Four',
    'AF',
    '+919876544002',
    'ACTIVE'
  ),
  (
    '00000000-0000-0000-0000-000000004003',
    'SUPER_ADMIN',
    'Super Four',
    'SF',
    '+919876544003',
    'ACTIVE'
  ),
  (
    '00000000-0000-0000-0000-000000004004',
    'CAPTAIN',
    'Captain Four',
    'CF',
    '+919876544004',
    'ACTIVE'
  ),
  (
    '00000000-0000-0000-0000-000000004005',
    'SUPERVISOR',
    'Supervisor Four',
    'VF',
    '+919876544005',
    'ACTIVE'
  );

select set_config('app.bypass_identity_protection', 'off', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004001', true);

select lives_ok(
  $$
    select *
    from public.update_own_profile(
      'Worker Updated',
      'WU',
      'New address',
      'New native place',
      171.5,
      'Diploma',
      true,
      'Two prior events',
      null
    )
  $$,
  'Worker can update allowed own profile fields'
);

select is(
  (
    select full_name
    from public.profiles
    where id = '00000000-0000-0000-0000-000000004001'
  ),
  'Worker Updated',
  'own profile update changes allowed profile field'
);

select is(
  (
    select address
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000004001'
  ),
  'New address',
  'own profile update changes allowed worker field'
);

select is(
  (
    select count(*)
    from public.audit_logs
    where actor_id = '00000000-0000-0000-0000-000000004001'
      and action = 'own_worker_profile_updated'
  ),
  1::bigint,
  'own profile update is audited'
);

select throws_ok(
  $$
    select *
    from public.update_own_profile(
      '',
      'WU',
      'New address',
      'New native place',
      171.5,
      'Diploma',
      true,
      null,
      null
    )
  $$,
  'P0001',
  'required profile fields must be complete',
  'profile completeness remains enforced on self-edit'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004004', true);

select is(
  (
    select count(*)
    from public.worker_directory('Worker', null, null, 10)
  ),
  1::bigint,
  'Captain can search all workers'
);

select is(
  (
    select count(*)
    from public.worker_history('00000000-0000-0000-0000-000000004001')
  ) >= 1,
  true,
  'Captain can view worker history'
);

select throws_ok(
  $$
    select public.change_account_status(
      '00000000-0000-0000-0000-000000004001',
      'DETAINED',
      'Captain attempt',
      null,
      null
    )
  $$,
  'P0001',
  'only Admin or Super Admin can change account status',
  'Captain cannot detain workers'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004005', true);

select is(
  (
    select count(*)
    from public.worker_directory('919876544001', null, null, 10)
  ),
  1::bigint,
  'Supervisor can search workers by phone'
);

select throws_ok(
  $$
    select public.change_account_status(
      '00000000-0000-0000-0000-000000004001',
      'ACTIVE',
      'Supervisor attempt',
      null,
      null
    )
  $$,
  'P0001',
  'only Admin or Super Admin can change account status',
  'Supervisor cannot release workers'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004002', true);

select lives_ok(
  $$
    select public.change_account_status(
      '00000000-0000-0000-0000-000000004001',
      'DETAINED',
      'No-show investigation',
      null,
      'Temporary detention'
    )
  $$,
  'Admin can detain a Worker'
);

select is(
  (
    select account_status
    from public.profiles
    where id = '00000000-0000-0000-0000-000000004001'
  ),
  'DETAINED'::public.account_status,
  'detention updates current account status'
);

select is(
  (
    select count(*)
    from public.account_actions
    where target_user_id = '00000000-0000-0000-0000-000000004001'
      and action_type = 'DETAIN'
      and actor_id = '00000000-0000-0000-0000-000000004002'
      and reason = 'No-show investigation'
  ),
  1::bigint,
  'detention is recorded in account action history'
);

select lives_ok(
  $$
    select public.change_account_status(
      '00000000-0000-0000-0000-000000004001',
      'ACTIVE',
      'Issue resolved',
      null,
      null
    )
  $$,
  'Admin can release a Worker'
);

select is(
  (
    select account_status
    from public.profiles
    where id = '00000000-0000-0000-0000-000000004001'
  ),
  'ACTIVE'::public.account_status,
  'release restores ACTIVE status'
);

select throws_ok(
  $$
    select public.change_account_status(
      '00000000-0000-0000-0000-000000004004',
      'DETAINED',
      'Attempt to detain Captain',
      null,
      null
    )
  $$,
  'P0001',
  'Phase 4 account detention/release applies to Workers only',
  'Phase 4 detention targets Workers only'
);

select throws_ok(
  $$
    select public.change_account_status(
      '00000000-0000-0000-0000-000000004001',
      'BLACKLISTED',
      'Unsupported Phase 4 status',
      null,
      null
    )
  $$,
  'P0001',
  'Phase 4 supports only Detain and Release',
  'Phase 4 account status flow is limited to detain/release'
);

select lives_ok(
  $$
    select public.change_user_role(
      '00000000-0000-0000-0000-000000004001',
      'CAPTAIN',
      'Move to field role',
      null
    )
  $$,
  'Admin can create Captain role from Worker'
);

select is(
  (
    select category
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000004001'
  ),
  null,
  'Worker-to-field role change clears active category'
);

select is(
  (
    select count(*)
    from public.audit_logs
    where entity_id = '00000000-0000-0000-0000-000000004001'
      and action = 'worker_role_changed_operational_effects'
      and after_values->>'assignment_flag_type' = 'WORKER_ROLE_CHANGED'
      and after_values->>'active_waitlist_entries_withdrawn_without_penalty' = 'true'
  ),
  1::bigint,
  'Worker-to-field role change records assignment/waitlist integration contract'
);

select throws_ok(
  $$
    select public.change_user_role(
      '00000000-0000-0000-0000-000000004003',
      'ADMIN',
      'Admin attempt on Super Admin',
      null
    )
  $$,
  'P0001',
  'Admin cannot manage Admin or Super Admin authority',
  'Admin role management boundary is enforced'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004003', true);

select lives_ok(
  $$
    select public.change_user_role(
      '00000000-0000-0000-0000-000000004004',
      'SUPERVISOR',
      'Super Admin changes staff role',
      null
    )
  $$,
  'Super Admin can manage field roles'
);

select lives_ok(
  $$
    select public.change_user_role(
      '00000000-0000-0000-0000-000000004004',
      'WORKER',
      'Revoke direct staff access',
      null
    )
  $$,
  'Super Admin can revoke staff-only access without converting to Worker'
);

select is(
  (
    select role
    from public.profiles
    where id = '00000000-0000-0000-0000-000000004004'
  ),
  'SUPERVISOR'::public.app_role,
  'staff-only revocation retains last staff role as metadata'
);

select is(
  (
    select account_status
    from public.profiles
    where id = '00000000-0000-0000-0000-000000004004'
  ),
  'INACTIVE'::public.account_status,
  'staff-only revocation makes the account inactive'
);

select is(
  (
    select count(*)
    from public.account_actions
    where target_user_id = '00000000-0000-0000-0000-000000004004'
      and action_type = 'STAFF_ACCESS_REVOKED'
      and new_status = 'INACTIVE'
  ),
  1::bigint,
  'staff-only revocation is recorded in account history'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004004', true);

select throws_ok(
  $$
    select *
    from public.worker_directory(null, null, null, 10)
  $$,
  'P0001',
  'not authorized to view worker directory',
  'inactive retained staff role has no worker-directory privilege'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004003', true);

select public.change_user_role(
  '00000000-0000-0000-0000-000000004001',
  'WORKER',
  'Return to Worker for worker-denial checks',
  null
);

select is(
  (
    select count(*)
    from public.assignment_review_flags
  ),
  0::bigint,
  'detention flag table is present and empty until assignments exist'
);

select ok(
  has_table_privilege('authenticated', 'public.assignment_review_flags', 'SELECT'),
  'authenticated has explicit select grant for flagged review queue'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004001', true);

select throws_ok(
  $$
    select *
    from public.worker_directory(null, null, null, 10)
  $$,
  'P0001',
  'not authorized to view worker directory',
  'Worker cannot browse worker directory'
);

select throws_ok(
  $$
    select *
    from public.worker_profile_detail('00000000-0000-0000-0000-000000004002')
  $$,
  'P0001',
  'not authorized to view worker profile',
  'Worker cannot view non-worker staff detail'
);

select * from finish();

rollback;
