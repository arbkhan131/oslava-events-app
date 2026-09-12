begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

select has_table('public', 'friend_booking_requests', 'friend booking audit table exists');
select has_function(
  'public',
  'search_bookable_friend_workers',
  array['text', 'uuid', 'integer'],
  'friend phone search RPC exists'
);
select has_function(
  'public',
  'apply_for_event_with_friend',
  array['uuid', 'uuid', 'text', 'uuid[]', 'boolean'],
  'friend pair apply RPC exists'
);
select ok(
  not has_table_privilege('authenticated', 'public.friend_booking_requests', 'INSERT'),
  'authenticated users cannot directly insert friend booking requests'
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
  ('00000000-0000-0000-0000-000000031001', 'authenticated', 'authenticated', '+919876531001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000031002', 'authenticated', 'authenticated', '+919876531002', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000031003', 'authenticated', 'authenticated', '+919876531003', crypt('worker-c-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000031004', 'authenticated', 'authenticated', '+919876531004', crypt('worker-f-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000031001', null, 'ADMIN', 'Admin Friend', 'AF', '+919876531001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000031002', nextval('public.worker_number_seq'), 'WORKER', 'Worker Friend A', 'WA', '+919876531002', '00000000-0000-0000-0000-000000031002/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000031003', nextval('public.worker_number_seq'), 'WORKER', 'Worker Friend C', 'WC', '+919876531003', '00000000-0000-0000-0000-000000031003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000031004', nextval('public.worker_number_seq'), 'WORKER', 'Worker Friend F', 'WF', '+919876531004', '00000000-0000-0000-0000-000000031004/profile.webp', now(), 'ACTIVE');

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
  registration_type,
  requested_category,
  id_card_file_path,
  experience_level
)
values
  ('00000000-0000-0000-0000-000000031002', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false, 'NEW_WORKER', null, 'ids/a.pdf', 'NO_EXPERIENCE'),
  ('00000000-0000-0000-0000-000000031003', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false, 'OLD_WORKER', 'C', 'ids/c.pdf', 'SOME_EXPERIENCE'),
  ('00000000-0000-0000-0000-000000031004', 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false, 'NEW_WORKER', null, 'ids/f.pdf', 'NO_EXPERIENCE');

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000031001', true);

create temp table friend_events (
  key text primary key,
  id uuid not null
);

insert into friend_events
values
  ('pair', public.create_event_draft('Pair Booking', 'Wedding', 'Hall', null, '2026-11-10 15:00:00+05:30', '2026-11-10 16:00:00+05:30', '2026-11-10 23:00:00+05:30', 2, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('single', public.create_event_draft('Single Booking', 'Wedding', 'Hall', null, '2026-11-11 15:00:00+05:30', '2026-11-11 16:00:00+05:30', '2026-11-11 23:00:00+05:30', 1, 1200, 'STANDARD', null, null, '[]', '[]', '[]'));

select public.publish_event(id, 'Publish friend booking event')
from friend_events;

update public.event_tier_release_rules
set opens_at = now() - interval '1 minute'
where event_id in (select id from friend_events);

select public.process_due_tier_releases();

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000031002', true);

select is(
  (select count(*)::integer from public.search_bookable_friend_workers('31003', (select id from friend_events where key = 'pair'), 10)),
  1,
  'active worker can find an approved friend by phone digits'
);

create temp table friend_pair_result as
select *
from public.apply_for_event_with_friend(
  (select id from friend_events where key = 'pair'),
  '00000000-0000-0000-0000-000000031003',
  'friend-pair-ok',
  '{}',
  false
);

select is((select result from friend_pair_result), 'CONFIRMED'::public.booking_result, 'friend pair booking confirms both workers');
select is(
  (select count(*)::integer from public.assignments where event_id = (select id from friend_events where key = 'pair') and status = 'CONFIRMED'),
  2,
  'friend pair booking fills two assignment seats'
);
select is(
  (select count(*)::integer from public.assignments where event_id = (select id from friend_events where key = 'pair') and source = 'FRIEND_BOOKING'),
  2,
  'pair assignments are source-tagged as friend bookings'
);
select is(
  (select count(*)::integer from public.notifications where recipient_id in ('00000000-0000-0000-0000-000000031002', '00000000-0000-0000-0000-000000031003') and related_event_id = (select id from friend_events where key = 'pair') and notification_type = 'APPLICATION_CONFIRMED'),
  2,
  'both workers receive confirmation notifications'
);
select is(
  (select count(*)::integer from public.audit_logs where action = 'friend_booking_confirmed' and related_event_id = (select id from friend_events where key = 'pair')),
  1,
  'friend booking confirmation is audited once'
);

create temp table friend_single_result as
select *
from public.apply_for_event_with_friend(
  (select id from friend_events where key = 'single'),
  '00000000-0000-0000-0000-000000031004',
  'friend-pair-single-seat',
  '{}',
  false
);

select is((select result from friend_single_result), 'WAITLIST_AVAILABLE'::public.booking_result, 'one-seat event rejects pair booking');
select is((select result_detail_code from friend_single_result), 'PAIR_REQUIRES_TWO_OPEN_VACANCIES', 'pair rejection explains that two open seats are required');
select is(
  (select count(*)::integer from public.assignments where event_id = (select id from friend_events where key = 'single') and status = 'CONFIRMED'),
  0,
  'rejected pair booking does not confirm either worker'
);

select * from finish();
rollback;
