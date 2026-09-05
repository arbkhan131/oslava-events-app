begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

select has_table('public', 'attendance', 'attendance table exists');
select has_table('public', 'attendance_history', 'attendance history table exists');
select has_function(
  'public',
  'set_attendance',
  array['uuid', 'public.attendance_status', 'text'],
  'attendance mutation RPC exists'
);
select has_function(
  'public',
  'event_attendance_roster',
  array['uuid', 'text'],
  'attendance roster RPC exists'
);
select has_function(
  'public',
  'event_attendance_counters',
  array['uuid'],
  'attendance counters RPC exists'
);

select ok(
  not has_table_privilege('authenticated', 'public.attendance', 'INSERT'),
  'authenticated users cannot directly insert attendance'
);

select ok(
  not has_table_privilege('authenticated', 'public.attendance', 'UPDATE'),
  'authenticated users cannot directly update attendance'
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
  ('00000000-0000-0000-0000-000000011001', 'authenticated', 'authenticated', '+919876551001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000011002', 'authenticated', 'authenticated', '+919876551002', crypt('captain-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000011003', 'authenticated', 'authenticated', '+919876551003', crypt('supervisor-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000011004', 'authenticated', 'authenticated', '+919876551004', crypt('other-captain-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000011005', 'authenticated', 'authenticated', '+919876551005', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000011006', 'authenticated', 'authenticated', '+919876551006', crypt('worker-b-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
values
  ('00000000-0000-0000-0000-000000011001', null, 'ADMIN', 'Admin Eleven', 'AE', '+919876551001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000011002', null, 'CAPTAIN', 'Captain Eleven', 'CE', '+919876551002', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000011003', null, 'SUPERVISOR', 'Supervisor Eleven', 'SE', '+919876551003', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000011004', null, 'CAPTAIN', 'Other Captain Eleven', 'OC', '+919876551004', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000011005', nextval('public.worker_number_seq'), 'WORKER', 'Worker A Eleven', 'WA', '+919876551005', '00000000-0000-0000-0000-000000011005/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000011006', nextval('public.worker_number_seq'), 'WORKER', 'Worker B Eleven', 'WB', '+919876551006', '00000000-0000-0000-0000-000000011006/profile.webp', now(), 'ACTIVE');

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
values
  ('00000000-0000-0000-0000-000000011005', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000011006', 'B', 'B', (current_date - interval '20 years')::date, 'Pune', 'Pune', 171, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000011001', true);

create temp table phase_11_event as
select public.create_event_draft(
  'Phase 11 Attendance',
  'Wedding',
  'Pune Hall',
  null,
  '2026-10-10 15:00:00+05:30',
  '2026-10-10 16:00:00+05:30',
  '2026-10-10 23:00:00+05:30',
  4,
  1200,
  'STANDARD',
  null,
  null,
  '[{"user_id":"00000000-0000-0000-0000-000000011002","leader_role":"CAPTAIN"},{"user_id":"00000000-0000-0000-0000-000000011003","leader_role":"SUPERVISOR"}]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.publish_event((select id from phase_11_event), 'Publish attendance event');

insert into public.assignments (
  event_id,
  worker_id,
  status,
  source,
  category_at_confirmation
)
values
  ((select id from phase_11_event), '00000000-0000-0000-0000-000000011005', 'CONFIRMED', 'MANAGEMENT', 'A'),
  ((select id from phase_11_event), '00000000-0000-0000-0000-000000011006', 'CONFIRMED', 'MANAGEMENT', 'B');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000011002', true);

select is(
  (select count(*)::integer from public.field_event_list()),
  1,
  'assigned Captain sees assigned field event'
);

select is(
  (
    select count(*)::integer
    from public.event_attendance_roster((select id from phase_11_event), null)
  ),
  2,
  'assigned Captain can see confirmed worker roster'
);

select is(
  (
    select not_marked
    from public.event_attendance_counters((select id from phase_11_event))
  ),
  2,
  'unmarked confirmed assignments count as NOT_MARKED'
);

select lives_ok(
  $$
    select *
    from public.set_attendance(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000011005'
      ),
      'PRESENT',
      'Arrived on time'
    )
  $$,
  'assigned Captain can mark attendance before Close'
);

select is(
  (
    select status
    from public.attendance
    where worker_id = '00000000-0000-0000-0000-000000011005'
  ),
  'PRESENT'::public.attendance_status,
  'Captain mark stores PRESENT'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000011003', true);

select lives_ok(
  $$
    select *
    from public.set_attendance(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000011005'
      ),
      'LATE',
      'Corrected by supervisor'
    )
  $$,
  'assigned Supervisor can correct attendance before Close'
);

select is(
  (
    select count(*)::integer
    from public.attendance_history
    where worker_id = '00000000-0000-0000-0000-000000011005'
  ),
  2,
  'every attendance change writes history'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000011004', true);

select is(
  (select count(*)::integer from public.field_event_list()),
  0,
  'unassigned field leader sees no assigned events'
);

select throws_ok(
  $$
    select *
    from public.set_attendance(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000011006'
      ),
      'ABSENT',
      'Unassigned attempt'
    )
  $$,
  'P0001',
  'not authorized to set attendance',
  'unassigned field leader cannot mark attendance'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000011006', true);

select throws_ok(
  $$
    select *
    from public.event_attendance_roster((select id from phase_11_event), null)
  $$,
  'P0001',
  'not authorized for event operations',
  'worker cannot view field roster'
);

select throws_ok(
  $$
    select *
    from public.set_attendance(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000011006'
      ),
      'PRESENT',
      'Worker attempt'
    )
  $$,
  'P0001',
  'not authorized to set attendance',
  'worker cannot alter attendance'
);

update public.events
set event_status = 'CLOSED',
    recruitment_status = 'CLOSED'
where id = (select id from phase_11_event);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000011002', true);

select throws_ok(
  $$
    select *
    from public.set_attendance(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000011006'
      ),
      'PRESENT',
      'Captain after close'
    )
  $$,
  'P0001',
  'not authorized to set attendance',
  'field leader cannot correct attendance after Close'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000011001', true);

select lives_ok(
  $$
    select *
    from public.set_attendance(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000011006'
      ),
      'ABSENT',
      'Admin correction after close'
    )
  $$,
  'Admin can correct attendance after Close'
);

select is(
  (
    select absent
    from public.event_attendance_counters((select id from phase_11_event))
  ),
  1,
  'attendance counters include ABSENT after correction'
);

select is(
  (
    select count(*)::integer
    from public.audit_logs
    where entity_type = 'attendance'
      and related_event_id = (select id from phase_11_event)
  ),
  3,
  'attendance changes are written to audit logs'
);

select is(
  (
    select count(*)::integer
    from public.event_attendance_roster((select id from phase_11_event), 'Worker B')
  ),
  1,
  'attendance roster supports worker search'
);

select *
from finish();

rollback;
