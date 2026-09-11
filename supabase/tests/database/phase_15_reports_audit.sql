begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

select has_function(
  'public',
  'event_report_summary',
  array['uuid'],
  'event report summary RPC exists'
);
select has_function(
  'public',
  'event_staffing_report',
  array['uuid'],
  'event staffing report RPC exists'
);
select has_function(
  'public',
  'event_audit_history',
  array['uuid', 'integer'],
  'event audit history RPC exists'
);
select has_function(
  'public',
  'event_audit_history_filtered',
  array['uuid', 'text', 'public.app_role', 'integer', 'integer'],
  'filtered event audit history RPC exists'
);
select ok(not has_function_privilege('anon', 'public.event_audit_history_filtered(uuid,text,public.app_role,integer,integer)', 'EXECUTE'), 'anon cannot execute filtered audit history');

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
  ('00000000-0000-0000-0000-000000015001', 'authenticated', 'authenticated', '+919876555001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000015002', 'authenticated', 'authenticated', '+919876555002', crypt('captain-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000015003', 'authenticated', 'authenticated', '+919876555003', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000015004', 'authenticated', 'authenticated', '+919876555004', crypt('worker-f-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000015005', 'authenticated', 'authenticated', '+919876555005', crypt('outsider-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000015001', null, 'ADMIN', 'Admin Fifteen', 'AF', '+919876555001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000015002', null, 'CAPTAIN', 'Captain Fifteen', 'CF', '+919876555002', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000015003', nextval('public.worker_number_seq'), 'WORKER', 'A Worker Fifteen', 'AW', '+919876555003', '00000000-0000-0000-0000-000000015003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000015004', nextval('public.worker_number_seq'), 'WORKER', 'F Worker Fifteen', 'FW', '+919876555004', '00000000-0000-0000-0000-000000015004/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000015005', nextval('public.worker_number_seq'), 'WORKER', 'Outside Worker Fifteen', 'OW', '+919876555005', '00000000-0000-0000-0000-000000015005/profile.webp', now(), 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000015003', 'A', 'A', (current_date - interval '22 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000015004', 'F', 'F', (current_date - interval '21 years')::date, 'Pune', 'Pune', 171, 'College', false),
  ('00000000-0000-0000-0000-000000015005', 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 172, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);

insert into public.events (
  id,
  title,
  event_type,
  venue_name,
  event_date,
  reporting_at,
  work_starts_at,
  expected_ends_at,
  required_worker_count,
  daily_wage,
  tier_strategy,
  event_status,
  recruitment_status,
  published_at,
  created_by,
  updated_by
)
values (
  '00000000-0000-0000-0000-000000015101',
  'Phase 15 Report Event',
  'Wedding',
  'Pune Hall',
  (now() + interval '1 day')::date,
  now() + interval '1 day',
  now() + interval '1 day 1 hour',
  now() + interval '1 day 8 hours',
  2,
  1200,
  'STANDARD',
  'UPCOMING',
  'OPEN',
  now(),
  '00000000-0000-0000-0000-000000015001',
  '00000000-0000-0000-0000-000000015001'
);

insert into public.event_leaders(event_id, user_id, leader_role, assigned_by)
values (
  '00000000-0000-0000-0000-000000015101',
  '00000000-0000-0000-0000-000000015002',
  'CAPTAIN',
  '00000000-0000-0000-0000-000000015001'
);

insert into public.event_allowances(event_id, label, amount, display_order)
values
  ('00000000-0000-0000-0000-000000015101', 'Travel', 100, 1),
  ('00000000-0000-0000-0000-000000015101', 'Meal', 50, 2);

insert into public.assignments (
  id,
  event_id,
  worker_id,
  status,
  source,
  category_at_confirmation
)
values
  ('00000000-0000-0000-0000-000000015201', '00000000-0000-0000-0000-000000015101', '00000000-0000-0000-0000-000000015004', 'CONFIRMED', 'MANAGEMENT', 'F'),
  ('00000000-0000-0000-0000-000000015202', '00000000-0000-0000-0000-000000015101', '00000000-0000-0000-0000-000000015003', 'CONFIRMED', 'MANAGEMENT', 'A');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000015001', true);

select public.set_attendance(
  '00000000-0000-0000-0000-000000015202',
  'PRESENT',
  'Checked in'
);

select is(
  (
    select confirmed_worker_count
    from public.event_report_summary('00000000-0000-0000-0000-000000015101')
  ),
  2,
  'summary includes active confirmed staffing count'
);

select is(
  (
    select attendance_present
    from public.event_report_summary('00000000-0000-0000-0000-000000015101')
  ),
  1,
  'summary includes attendance totals'
);

select is(
  (
    select total_worker_pay_display
    from public.event_report_summary('00000000-0000-0000-0000-000000015101')
  ),
  1350::numeric,
  'summary includes wage plus event allowances for display'
);

select is(
  (
    select string_agg(category_at_confirmation::text, ',' order by row_number)
    from (
      select category_at_confirmation, row_number() over () as row_number
      from public.event_staffing_report('00000000-0000-0000-0000-000000015101')
    ) rows
  ),
  'A,F',
  'staffing report is category sorted by A, B, C, F priority'
);

select ok(
  exists (
    select 1
    from public.event_audit_history('00000000-0000-0000-0000-000000015101', 50)
    where history_source = 'attendance_history'
      and action = 'ATTENDANCE_CHANGED'
  ),
  'event audit history includes attendance history'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000015002', true);

select lives_ok(
  $$ select * from public.event_staffing_report('00000000-0000-0000-0000-000000015101') $$,
  'assigned Captain can view report for assigned event'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000015005', true);

select throws_ok(
  $$ select * from public.event_staffing_report('00000000-0000-0000-0000-000000015101') $$,
  'P0001',
  'not authorized to view staffing reports',
  'unassigned Worker cannot view event staffing report'
);

select throws_ok(
  $$ select * from public.event_audit_history('00000000-0000-0000-0000-000000015101', 50) $$,
  'P0001',
  'not authorized to view event audit history',
  'unassigned Worker cannot view event audit history'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_logs', 'SELECT'),
  'authenticated users cannot directly select global audit logs'
);

select *
from finish();

rollback;
