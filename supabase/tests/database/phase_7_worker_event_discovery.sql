begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

select has_function('public', 'worker_event_board', array[]::text[], 'worker event board RPC exists');
select has_function('public', 'worker_event_detail', array['uuid'], 'worker event detail RPC exists');

select ok(
  not has_function_privilege('anon', 'public.worker_event_board()', 'EXECUTE'),
  'anon cannot execute worker event board'
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
  ('00000000-0000-0000-0000-000000007001', 'authenticated', 'authenticated', '+919876547001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000007002', 'authenticated', 'authenticated', '+919876547002', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000007003', 'authenticated', 'authenticated', '+919876547003', crypt('worker-c-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000007001', null, 'ADMIN', 'Admin Seven', 'AS', '+919876547001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000007002', nextval('public.worker_number_seq'), 'WORKER', 'Worker A Seven', 'WA', '+919876547002', '00000000-0000-0000-0000-000000007002/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000007003', nextval('public.worker_number_seq'), 'WORKER', 'Worker C Seven', 'WC', '+919876547003', '00000000-0000-0000-0000-000000007003/profile.webp', now(), 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000007002', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000007003', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007001', true);

create temp table phase_7_draft_event as
select public.create_event_draft(
  'Phase 7 Draft',
  'Wedding',
  'Draft Hall',
  'https://maps.example/draft',
  '2026-10-10 15:00:00+05:30',
  '2026-10-10 16:00:00+05:30',
  '2026-10-10 23:00:00+05:30',
  10,
  1200,
  'STANDARD',
  'Draft instructions',
  'Black shirt',
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

create temp table phase_7_standard_event as
select public.create_event_draft(
  'Phase 7 Standard',
  'Conference',
  'Open Hall',
  'https://maps.example/open',
  '2026-10-11 15:00:00+05:30',
  '2026-10-11 16:00:00+05:30',
  '2026-10-11 23:00:00+05:30',
  10,
  1300,
  'STANDARD',
  'Bring ID',
  'Formal black',
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.publish_event((select id from phase_7_standard_event), 'Publish standard');

create temp table phase_7_full_event as
select public.create_event_draft(
  'Phase 7 Full',
  'Concert',
  'Full Hall',
  'https://maps.example/full',
  '2026-10-12 15:00:00+05:30',
  '2026-10-12 16:00:00+05:30',
  '2026-10-12 23:00:00+05:30',
  1,
  1100,
  'STANDARD',
  null,
  null,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.publish_event((select id from phase_7_full_event), 'Publish full');

update public.events
set recruitment_status = 'FULL'
where id = (select id from phase_7_full_event);

create temp table phase_7_cancelled_event as
select public.create_event_draft(
  'Phase 7 Cancelled',
  'Concert',
  'Cancelled Hall',
  'https://maps.example/cancelled',
  '2026-10-13 15:00:00+05:30',
  '2026-10-13 16:00:00+05:30',
  '2026-10-13 23:00:00+05:30',
  1,
  1100,
  'STANDARD',
  null,
  null,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.publish_event((select id from phase_7_cancelled_event), 'Publish cancelled');
select public.cancel_event((select id from phase_7_cancelled_event), 'Cancelled for test');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007002', true);

select is(
  (
    select count(*)::integer
    from public.worker_event_board()
    where id = (select id from phase_7_draft_event)
  ),
  0,
  'worker event board does not leak drafts'
);

select is(
  (
    select action_state
    from public.worker_event_board()
    where id = (select id from phase_7_standard_event)
  ),
  'AVAILABLE',
  'eligible A worker sees an open standard event as available'
);

select is(
  (
    select action_label
    from public.worker_event_board()
    where id = (select id from phase_7_standard_event)
  ),
  'Apply',
  'available event presents Apply'
);

select is(
  (
    select action_label
    from public.worker_event_board()
    where id = (select id from phase_7_full_event)
  ),
  'Join Waitlist',
  'full event presents explicit Join Waitlist'
);

select is(
  (
    select action_state
    from public.worker_event_board()
    where id = (select id from phase_7_cancelled_event)
  ),
  'CANCELLED',
  'cancelled event renders as cancelled'
);

select is(
  (
    select vacancy_count
    from public.worker_event_board()
    where id = (select id from phase_7_standard_event)
  ),
  10,
  'vacancy count uses server-side confirmed assignment count'
);

select is(
  (
    select maps_url
    from public.worker_event_detail((select id from phase_7_standard_event))
  ),
  'https://maps.example/open',
  'detail projection includes maps URL'
);

select is(
  (
    select instructions
    from public.worker_event_detail((select id from phase_7_standard_event))
  ),
  'Bring ID',
  'detail projection includes worker instructions'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007003', true);

select is(
  (
    select action_state
    from public.worker_event_board()
    where id = (select id from phase_7_standard_event)
  ),
  'LOCKED',
  'C worker sees standard event as locked before C tier opens'
);

update public.event_tier_release_rules
set opens_at = now() - interval '1 minute'
where event_id = (select id from phase_7_standard_event)
  and category = 'C';

select is(
  (
    select action_state
    from public.worker_event_board()
    where id = (select id from phase_7_standard_event)
  ),
  'AVAILABLE',
  'C worker sees event as available after C tier opens'
);

select is(
  (
    select open_categories
    from public.worker_event_board()
    where id = (select id from phase_7_standard_event)
  ),
  array['A', 'C']::public.worker_category[],
  'board returns server-derived open categories'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007001', true);

select is(
  (select count(*)::integer from public.worker_event_board()),
  0,
  'non-worker accounts receive no worker event board rows'
);

select *
from finish();

rollback;
