begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

select has_table('public', 'booking_requests', 'booking requests table exists');
select has_table('public', 'booking_arbitration_windows', 'arbitration windows table exists');
select has_table('public', 'requirement_acknowledgements', 'requirement acknowledgements table exists');
select has_function(
  'public',
  'apply_for_event',
  array['uuid', 'text', 'uuid[]', 'boolean'],
  'apply RPC exists'
);

select ok(
  not has_table_privilege('authenticated', 'public.booking_requests', 'INSERT'),
  'authenticated users cannot directly insert booking requests'
);

select ok(
  not has_table_privilege('authenticated', 'public.requirement_acknowledgements', 'INSERT'),
  'authenticated users cannot directly insert requirement acknowledgements'
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
  ('00000000-0000-0000-0000-000000009001', 'authenticated', 'authenticated', '+919876549001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000009002', 'authenticated', 'authenticated', '+919876549002', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000009003', 'authenticated', 'authenticated', '+919876549003', crypt('worker-c-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000009004', 'authenticated', 'authenticated', '+919876549004', crypt('worker-f-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000009005', 'authenticated', 'authenticated', '+919876549005', crypt('incomplete-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000009001', null, 'ADMIN', 'Admin Nine', 'AN', '+919876549001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000009002', nextval('public.worker_number_seq'), 'WORKER', 'Worker A Nine', 'WA', '+919876549002', '00000000-0000-0000-0000-000000009002/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000009003', nextval('public.worker_number_seq'), 'WORKER', 'Worker C Nine', 'WC', '+919876549003', '00000000-0000-0000-0000-000000009003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000009004', nextval('public.worker_number_seq'), 'WORKER', 'Worker F Nine', 'WF', '+919876549004', '00000000-0000-0000-0000-000000009004/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000009005', nextval('public.worker_number_seq'), 'WORKER', 'Incomplete Worker', 'IW', '+919876549005', null, null, 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000009002', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000009003', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000009004', 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000009005', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009001', true);

create temp table phase_9_events (
  key text primary key,
  id uuid not null
);

insert into phase_9_events
values
  ('open', public.create_event_draft('Open Booking', 'Wedding', 'Hall', null, '2026-10-10 15:00:00+05:30', '2026-10-10 16:00:00+05:30', '2026-10-10 23:00:00+05:30', 3, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('locked', public.create_event_draft('Locked Booking', 'Wedding', 'Hall', null, '2026-10-11 15:00:00+05:30', '2026-10-11 16:00:00+05:30', '2026-10-11 23:00:00+05:30', 3, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('requirements', public.create_event_draft('Requirements Booking', 'Wedding', 'Hall', null, '2026-10-12 15:00:00+05:30', '2026-10-12 16:00:00+05:30', '2026-10-12 23:00:00+05:30', 3, 1200, 'STANDARD', null, null, '[]', '[{"name":"Black shoes","is_mandatory":true,"acknowledgement_required":true}]', '[]')),
  ('full', public.create_event_draft('Full Booking', 'Wedding', 'Hall', null, '2026-10-13 15:00:00+05:30', '2026-10-13 16:00:00+05:30', '2026-10-13 23:00:00+05:30', 1, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('conflict', public.create_event_draft('Conflict Booking', 'Wedding', 'Hall', null, '2026-10-10 16:30:00+05:30', '2026-10-10 17:00:00+05:30', '2026-10-10 21:00:00+05:30', 3, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('final', public.create_event_draft('Final Seat', 'Wedding', 'Hall', null, '2026-10-14 15:00:00+05:30', '2026-10-14 16:00:00+05:30', '2026-10-14 23:00:00+05:30', 1, 1200, 'STANDARD', null, null, '[]', '[]', '[]'));

select public.publish_event(id, 'Publish booking event')
from phase_9_events;

update public.event_tier_release_rules
set opens_at = now() - interval '1 minute'
where event_id in (select id from phase_9_events where key in ('open', 'requirements', 'full', 'conflict', 'final'));

select public.process_due_tier_releases();

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009002', true);

create temp table phase_9_open_result as
select *
from public.apply_for_event((select id from phase_9_events where key = 'open'), 'open-a', '{}', false);

select is((select result from phase_9_open_result), 'CONFIRMED'::public.booking_result, 'eligible worker is confirmed');
select isnt((select assignment_id from phase_9_open_result), null, 'confirmed result returns assignment id');

create temp table phase_9_repeat_result as
select *
from public.apply_for_event((select id from phase_9_events where key = 'open'), 'open-a', '{}', false);

select is(
  (select assignment_id from phase_9_repeat_result),
  (select assignment_id from phase_9_open_result),
  'repeated idempotency key returns the same assignment'
);

select is(
  (
    select action_state
    from public.worker_event_board()
    where id = (select id from phase_9_events where key = 'open')
  ),
  'CONFIRMED',
  'worker event board shows confirmed state after booking'
);

select is(
  (select result from public.apply_for_event((select id from phase_9_events where key = 'open'), 'duplicate-a', '{}', false)),
  'DUPLICATE'::public.booking_result,
  'second application to the same event is duplicate'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009005', true);

select is(
  (select result_detail_code from public.apply_for_event((select id from phase_9_events where key = 'open'), 'incomplete-a', '{}', false)),
  'PROFILE_INCOMPLETE',
  'incomplete profile cannot apply'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009003', true);

select is(
  (select result from public.apply_for_event((select id from phase_9_events where key = 'locked'), 'locked-c', '{}', false)),
  'LOCKED'::public.booking_result,
  'closed tier returns locked'
);

select is(
  (select result from public.apply_for_event((select id from phase_9_events where key = 'requirements'), 'missing-req-c', '{}', false)),
  'INVALID_REQUIREMENTS'::public.booking_result,
  'missing mandatory acknowledgement is rejected'
);

select is(
  (
    select result
    from public.apply_for_event(
      (select id from phase_9_events where key = 'requirements'),
      'acked-req-c',
      array[(select id from public.event_requirements where event_id = (select id from phase_9_events where key = 'requirements'))],
      false
    )
  ),
  'CONFIRMED'::public.booking_result,
  'mandatory acknowledgement permits booking'
);

select is(
  (
    select count(*)::integer
    from public.requirement_acknowledgements
    where event_id = (select id from phase_9_events where key = 'requirements')
      and worker_id = '00000000-0000-0000-0000-000000009003'
  ),
  1,
  'confirmed booking records requirement acknowledgement snapshot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009002', true);

select is(
  (select result from public.apply_for_event((select id from phase_9_events where key = 'conflict'), 'conflict-c', '{}', false)),
  'CONFLICT'::public.booking_result,
  'one-hour conflict blocks booking'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009004', true);

select is(
  (select result from public.apply_for_event((select id from phase_9_events where key = 'full'), 'full-f', '{}', false)),
  'CONFIRMED'::public.booking_result,
  'first booking fills one-seat event'
);

select is(
  (
    select recruitment_status
    from public.events
    where id = (select id from phase_9_events where key = 'full')
  ),
  'FULL'::public.recruitment_status,
  'booking final vacancy sets recruitment FULL'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009003', true);

select is(
  (select result from public.apply_for_event((select id from phase_9_events where key = 'full'), 'waitlist-available-c', '{}', false)),
  'WAITLIST_AVAILABLE'::public.booking_result,
  'full event returns waitlist available without auto-enrolling'
);

select is(
  private.active_confirmed_assignment_count((select id from phase_9_events where key = 'full')),
  1,
  'confirmed assignments never exceed required capacity'
);

insert into public.booking_arbitration_windows (event_id, opens_at, closes_at)
values ((select id from phase_9_events where key = 'final'), now() - interval '2 seconds', now() - interval '1 second');

insert into public.booking_requests (
  event_id,
  worker_id,
  idempotency_key,
  server_received_at,
  worker_category_snapshot,
  arbitration_window_id
)
values
  ((select id from phase_9_events where key = 'final'), '00000000-0000-0000-0000-000000009003', 'manual-c', now() - interval '1500 milliseconds', 'C', (select id from public.booking_arbitration_windows where event_id = (select id from phase_9_events where key = 'final'))),
  ((select id from phase_9_events where key = 'final'), '00000000-0000-0000-0000-000000009002', 'manual-a', now() - interval '1000 milliseconds', 'A', (select id from public.booking_arbitration_windows where event_id = (select id from phase_9_events where key = 'final')));

select private.allocate_booking_window(
  (select id from public.booking_arbitration_windows where event_id = (select id from phase_9_events where key = 'final')),
  false,
  '{}'
);

select is(
  (
    select result
    from public.booking_requests
    where idempotency_key = 'manual-a'
  ),
  'CONFIRMED'::public.booking_result,
  'A wins final-seat arbitration over earlier C request'
);

select is(
  (
    select result
    from public.booking_requests
    where idempotency_key = 'manual-c'
  ),
  'WAITLIST_AVAILABLE'::public.booking_result,
  'losing final-seat contender receives non-confirmed waitlist-available result'
);

select is(
  (
    select count(*)::integer
    from public.assignments
    where event_id = (select id from phase_9_events where key = 'final')
      and status = 'CONFIRMED'
  ),
  1,
  'final-seat arbitration creates exactly one confirmed assignment'
);

select *
from finish();

rollback;
