begin;

create extension if not exists pgtap with schema extensions;

select plan(54);

select has_table('public', 'events', 'events table exists');
select has_table('public', 'event_leaders', 'event leaders table exists');
select has_table('public', 'event_requirements', 'event requirements table exists');
select has_table('public', 'event_allowances', 'event allowances table exists');
select has_table('public', 'event_history', 'event history table exists');

select has_function(
  'public',
  'create_event_draft',
  array[
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'timestamp with time zone',
    'timestamp with time zone',
    'integer',
    'numeric',
    'public.tier_strategy',
    'text',
    'text',
    'jsonb',
    'jsonb',
    'jsonb'
  ],
  'create event draft RPC exists'
);

select has_function(
  'public',
  'update_event',
  array[
    'uuid',
    'integer',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'timestamp with time zone',
    'timestamp with time zone',
    'integer',
    'numeric',
    'public.tier_strategy',
    'text',
    'text',
    'jsonb',
    'jsonb',
    'jsonb',
    'text',
    'boolean'
  ],
  'update event RPC exists'
);

select has_function('public', 'publish_event', array['uuid', 'text'], 'publish event RPC exists');
select has_function('public', 'cancel_event', array['uuid', 'text'], 'cancel event RPC exists');
select has_function('public', 'complete_event', array['uuid', 'text'], 'complete event RPC exists');
select has_function('public', 'close_event', array['uuid', 'text'], 'close event RPC exists');
select has_function(
  'public',
  'process_event_lifecycle_transitions',
  array[]::text[],
  'automated lifecycle transition RPC exists'
);
select has_function('public', 'admin_event_list', array[]::text[], 'admin event list RPC exists');

select ok(
  not has_table_privilege('authenticated', 'public.events', 'INSERT'),
  'authenticated users cannot directly insert events'
);

select ok(
  not has_table_privilege('authenticated', 'public.events', 'UPDATE'),
  'authenticated users cannot directly update events'
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
    '00000000-0000-0000-0000-000000005001',
    'authenticated',
    'authenticated',
    '+919876545001',
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
    '00000000-0000-0000-0000-000000005002',
    'authenticated',
    'authenticated',
    '+919876545002',
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
    '00000000-0000-0000-0000-000000005003',
    'authenticated',
    'authenticated',
    '+919876545003',
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
    '00000000-0000-0000-0000-000000005004',
    'authenticated',
    'authenticated',
    '+919876545004',
    crypt('supervisor-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000005005',
    'authenticated',
    'authenticated',
    '+919876545005',
    crypt('worker-password', gen_salt('bf')),
    now(),
    '{"provider":"phone","providers":["phone"]}',
    '{}',
    false,
    false,
    now(),
    now()
  );

select set_config('app.bypass_identity_protection', 'on', true);

insert into public.profiles (id, role, full_name, initials, phone_e164, account_status)
values
  ('00000000-0000-0000-0000-000000005001', 'ADMIN', 'Admin Five', 'AF', '+919876545001', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000005002', 'SUPER_ADMIN', 'Super Five', 'SF', '+919876545002', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000005003', 'CAPTAIN', 'Captain Five', 'CF', '+919876545003', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000005004', 'SUPERVISOR', 'Supervisor Five', 'VF', '+919876545004', 'ACTIVE');

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
  '00000000-0000-0000-0000-000000005005',
  nextval('public.worker_number_seq'),
  'WORKER',
  'Worker Five',
  'WF',
  '+919876545005',
  '00000000-0000-0000-0000-000000005005/profile.webp',
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
  '00000000-0000-0000-0000-000000005005',
  'F',
  'F',
  (current_date - interval '20 years')::date,
  'Pune',
  'Pune',
  170,
  'College',
  false
);

select set_config('app.bypass_identity_protection', 'off', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005005', true);

select throws_ok(
  $$
    select public.create_event_draft(
      'Worker Attempt',
      'Wedding',
      'Pune Hall',
      null,
      '2026-10-10 15:00:00+05:30',
      '2026-10-10 16:00:00+05:30',
      '2026-10-10 23:00:00+05:30',
      10,
      1200,
      'STANDARD',
      null,
      null,
      '[]',
      '[]',
      '[]'
    )
  $$,
  'P0001',
  'only Admin or Super Admin can manage events',
  'Worker cannot create event draft'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005001', true);

create temp table phase_5_created_event(id uuid);

insert into phase_5_created_event
select public.create_event_draft(
  'Ganesh Festival Staffing',
  'Festival',
  'Oslava Grounds',
  'https://maps.example.test/oslava',
  '2026-10-10 15:00:00+05:30',
  '2026-10-10 16:00:00+05:30',
  '2026-10-10 23:00:00+05:30',
  25,
  1200,
  'STANDARD',
  'Report at main gate',
  'Black formal shoes',
  jsonb_build_array(
    jsonb_build_object('user_id', '00000000-0000-0000-0000-000000005003', 'leader_role', 'CAPTAIN'),
    jsonb_build_object('user_id', '00000000-0000-0000-0000-000000005004', 'leader_role', 'SUPERVISOR')
  ),
  jsonb_build_array(
    jsonb_build_object(
      'name', 'Black shirt',
      'description', 'Plain black shirt',
      'is_mandatory', true,
      'acknowledgement_required', true,
      'extra_allowance_amount', 0,
      'display_order', 1
    )
  ),
  jsonb_build_array(
    jsonb_build_object(
      'label', 'Dinner',
      'description', 'Meal allowance',
      'amount', 150,
      'display_order', 1
    )
  )
);

select is(
  (select event_status from public.events where id = (select id from phase_5_created_event)),
  'DRAFT'::public.event_status,
  'new event starts as DRAFT'
);

select is(
  (select recruitment_status from public.events where id = (select id from phase_5_created_event)),
  'NOT_OPEN'::public.recruitment_status,
  'new event starts recruitment NOT_OPEN'
);

select is(
  (select timezone_name from public.events where id = (select id from phase_5_created_event)),
  'Asia/Kolkata',
  'event stores Asia/Kolkata timezone'
);

select is(
  (select currency_code from public.events where id = (select id from phase_5_created_event)),
  'INR'::bpchar,
  'event stores INR currency'
);

select is(
  (select count(*) from public.event_leaders where event_id = (select id from phase_5_created_event)),
  2::bigint,
  'event supports multiple Captain/Supervisor leaders'
);

select is(
  (select count(*) from public.event_requirements where event_id = (select id from phase_5_created_event)),
  1::bigint,
  'event stores structured requirements'
);

select is(
  (select amount from public.event_allowances where event_id = (select id from phase_5_created_event)),
  150::numeric,
  'event stores INR allowances'
);

select is(
  (select count(*) from public.event_history where event_id = (select id from phase_5_created_event) and action = 'EVENT_DRAFT_CREATED'),
  1::bigint,
  'draft creation is recorded in event history'
);

select throws_ok(
  $$
    select public.create_event_draft(
      'Bad Time',
      'Wedding',
      'Pune Hall',
      null,
      '2026-10-10 18:00:00+05:30',
      '2026-10-10 16:00:00+05:30',
      '2026-10-10 23:00:00+05:30',
      10,
      1200,
      'STANDARD',
      null,
      null,
      '[]',
      '[]',
      '[]'
    )
  $$,
  '23514',
  null,
  'time ordering is enforced'
);

select throws_ok(
  $$
    select public.create_event_draft(
      'Bad Leader',
      'Wedding',
      'Pune Hall',
      null,
      '2026-10-10 15:00:00+05:30',
      '2026-10-10 16:00:00+05:30',
      '2026-10-10 23:00:00+05:30',
      10,
      1200,
      'STANDARD',
      null,
      null,
      jsonb_build_array(jsonb_build_object('user_id', '00000000-0000-0000-0000-000000005005', 'leader_role', 'CAPTAIN')),
      '[]',
      '[]'
    )
  $$,
  'P0001',
  'leader role must match an active profile',
  'leader assignment validates active matching role'
);

select is(
  public.update_event(
    (select id from phase_5_created_event),
    1,
    'Ganesh Festival Updated',
    'Festival',
    'Oslava Grounds',
    'https://maps.example.test/oslava',
    '2026-10-10 15:00:00+05:30',
    '2026-10-10 16:00:00+05:30',
    '2026-10-10 23:30:00+05:30',
    30,
    1300,
    'URGENT',
    'Updated instructions',
    'Black formal shoes',
    '[]',
    '[]',
    '[]',
    'Venue timing changed',
    false
  ),
  2,
  'event update increments optimistic version'
);

select is(
  (select title from public.events where id = (select id from phase_5_created_event)),
  'Ganesh Festival Updated',
  'event update changes event fields'
);

select is(
  (select count(*) from public.event_history where event_id = (select id from phase_5_created_event) and action = 'EVENT_UPDATED'),
  1::bigint,
  'event update is audited'
);

select throws_ok(
  $$
    select public.update_event(
      (select id from phase_5_created_event),
      1,
      'Stale Update',
      'Festival',
      'Oslava Grounds',
      null,
      '2026-10-10 15:00:00+05:30',
      '2026-10-10 16:00:00+05:30',
      '2026-10-10 23:30:00+05:30',
      30,
      1300,
      'URGENT',
      null,
      null,
      '[]',
      '[]',
      '[]',
      'Stale version',
      false
    )
  $$,
  'P0001',
  'STALE_VERSION',
  'stale event edits are rejected'
);

select lives_ok(
  $$
    select public.publish_event((select id from phase_5_created_event), 'Ready to publish')
  $$,
  'Admin can publish a draft'
);

select is(
  (select event_status from public.events where id = (select id from phase_5_created_event)),
  'PUBLISHED'::public.event_status,
  'publish changes lifecycle to PUBLISHED'
);

select is(
  (select recruitment_status from public.events where id = (select id from phase_5_created_event)),
  'OPEN'::public.recruitment_status,
  'Phase 6 tier release opens recruitment immediately when first tier is due'
);

select isnt(
  (select published_at from public.events where id = (select id from phase_5_created_event)),
  null,
  'publish records timestamp'
);

select lives_ok(
  $$
    select public.cancel_event((select id from phase_5_created_event), 'Client cancelled')
  $$,
  'Admin can cancel an event'
);

select is(
  (select event_status from public.events where id = (select id from phase_5_created_event)),
  'CANCELLED'::public.event_status,
  'cancel changes lifecycle to CANCELLED'
);

select is(
  (select recruitment_status from public.events where id = (select id from phase_5_created_event)),
  'CLOSED'::public.recruitment_status,
  'cancel closes recruitment'
);

select is(
  (select count(*) from public.event_history where event_id = (select id from phase_5_created_event) and action = 'EVENT_CANCELLED'),
  1::bigint,
  'cancel is recorded in event history'
);

create temp table phase_5_same_day_event(id uuid);

insert into phase_5_same_day_event
select public.create_event_draft(
  'Same Day Event',
  'Corporate',
  'Pune Venue',
  null,
  (((now() at time zone 'Asia/Kolkata')::date + time '23:00') at time zone 'Asia/Kolkata'),
  (((now() at time zone 'Asia/Kolkata')::date + time '23:15') at time zone 'Asia/Kolkata'),
  (((now() at time zone 'Asia/Kolkata')::date + time '23:45') at time zone 'Asia/Kolkata'),
  5,
  900,
  'STANDARD',
  null,
  null,
  '[]',
  '[]',
  '[]'
);

select lives_ok(
  $$
    select public.publish_event((select id from phase_5_same_day_event), 'Same-day publish')
  $$,
  'same-day event can be published'
);

select is(
  (select event_status from public.events where id = (select id from phase_5_same_day_event)),
  'UPCOMING'::public.event_status,
  'same-day publish enters UPCOMING immediately'
);

create temp table phase_5_due_event(id uuid);

insert into phase_5_due_event
select public.create_event_draft(
  'Due Event',
  'Corporate',
  'Mumbai Venue',
  null,
  now() - interval '2 hours',
  now() - interval '90 minutes',
  now() + interval '4 hours',
  5,
  900,
  'STANDARD',
  null,
  null,
  '[]',
  '[]',
  '[]'
);

select public.publish_event((select id from phase_5_due_event), 'Publish due event');

select cmp_ok(
  public.process_event_lifecycle_transitions(),
  '>=',
  1,
  'automated lifecycle processor changes due events'
);

select is(
  (select event_status from public.events where id = (select id from phase_5_due_event)),
  'IN_PROGRESS'::public.event_status,
  'reporting time moves event to IN_PROGRESS'
);

select is(
  (select recruitment_status from public.events where id = (select id from phase_5_due_event)),
  'CLOSED'::public.recruitment_status,
  'reporting time closes recruitment'
);

select lives_ok(
  $$
    select public.complete_event((select id from phase_5_due_event), 'Work finished')
  $$,
  'Admin can manually complete an in-progress event'
);

select is(
  (select event_status from public.events where id = (select id from phase_5_due_event)),
  'COMPLETED'::public.event_status,
  'manual completion sets lifecycle COMPLETED'
);

select is(
  (select recruitment_status from public.events where id = (select id from phase_5_due_event)),
  'CLOSED'::public.recruitment_status,
  'completed event keeps recruitment CLOSED'
);

select lives_ok(
  $$
    select public.close_event((select id from phase_5_due_event), 'Finalized attendance')
  $$,
  'Admin can manually close a completed event'
);

select is(
  (select event_status from public.events where id = (select id from phase_5_due_event)),
  'CLOSED'::public.event_status,
  'manual finalization sets lifecycle CLOSED'
);

select throws_ok(
  $$
    select public.cancel_event((select id from phase_5_due_event), 'Too late')
  $$,
  'P0001',
  'terminal events cannot be cancelled again',
  'closed events are terminal'
);

create temp table phase_5_emergency_event(id uuid);

insert into phase_5_emergency_event
select public.create_event_draft(
  'Emergency Cancellation Event',
  'Corporate',
  'Mumbai Venue',
  null,
  now() - interval '2 hours',
  now() - interval '90 minutes',
  now() + interval '4 hours',
  5,
  900,
  'STANDARD',
  null,
  null,
  '[]',
  '[]',
  '[]'
);

select public.publish_event((select id from phase_5_emergency_event), 'Publish emergency event');
select public.process_event_lifecycle_transitions();

select lives_ok(
  $$
    select public.cancel_event((select id from phase_5_emergency_event), 'Emergency cancellation during reporting')
  $$,
  'Admin can emergency-cancel an in-progress event'
);

select is(
  (select event_status from public.events where id = (select id from phase_5_emergency_event)),
  'CANCELLED'::public.event_status,
  'in-progress emergency cancellation sets CANCELLED'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005002', true);

select lives_ok(
  $$
    select public.create_event_draft(
      'Super Admin Event',
      'Corporate',
      'Mumbai Venue',
      null,
      '2026-11-01 10:00:00+05:30',
      '2026-11-01 11:00:00+05:30',
      '2026-11-01 20:00:00+05:30',
      10,
      1000,
      'EMERGENCY',
      null,
      null,
      '[]',
      '[]',
      '[]'
    )
  $$,
  'Super Admin can create event draft'
);

select is(
  (select count(*) from public.admin_event_list()),
  5::bigint,
  'Admin event list returns managed events'
);

select cmp_ok(
  (select count(*) from public.audit_logs where action in ('event_draft_created', 'event_updated', 'event_cancelled')),
  '>=',
  3::bigint,
  'critical event mutations write audit logs'
);

select * from finish();

rollback;
