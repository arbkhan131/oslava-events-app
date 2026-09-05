begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

select has_table('public', 'assignments', 'assignments table exists');
select has_function(
  'public',
  'has_booking_conflict',
  array['uuid', 'uuid', 'uuid'],
  'booking conflict predicate exists'
);

select ok(
  not has_table_privilege('authenticated', 'public.assignments', 'INSERT'),
  'authenticated users cannot directly insert assignments'
);

select ok(
  not has_table_privilege('authenticated', 'public.assignments', 'UPDATE'),
  'authenticated users cannot directly update assignments'
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
  ('00000000-0000-0000-0000-000000008001', 'authenticated', 'authenticated', '+919876548001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000008002', 'authenticated', 'authenticated', '+919876548002', crypt('worker-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000008001', null, 'ADMIN', 'Admin Eight', 'AE', '+919876548001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000008002', nextval('public.worker_number_seq'), 'WORKER', 'Worker Eight', 'WE', '+919876548002', '00000000-0000-0000-0000-000000008002/profile.webp', now(), 'ACTIVE');

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
  '00000000-0000-0000-0000-000000008002',
  'A',
  'A',
  (current_date - interval '20 years')::date,
  'Pune',
  'Pune',
  170,
  'College',
  false
);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008001', true);

create temp table phase_8_events (
  key text primary key,
  id uuid not null
);

insert into phase_8_events
values
  (
    'existing',
    public.create_event_draft('Existing', 'Wedding', 'Hall', null, '2026-10-10 12:00:00+05:30', '2026-10-10 13:00:00+05:30', '2026-10-10 16:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'boundary_after',
    public.create_event_draft('Boundary After', 'Wedding', 'Hall', null, '2026-10-10 17:00:00+05:30', '2026-10-10 18:00:00+05:30', '2026-10-10 20:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'fifty_nine_after',
    public.create_event_draft('Fifty Nine After', 'Wedding', 'Hall', null, '2026-10-10 16:59:00+05:30', '2026-10-10 18:00:00+05:30', '2026-10-10 20:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'overlap',
    public.create_event_draft('Overlap', 'Wedding', 'Hall', null, '2026-10-10 15:00:00+05:30', '2026-10-10 15:30:00+05:30', '2026-10-10 18:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'boundary_before',
    public.create_event_draft('Boundary Before', 'Wedding', 'Hall', null, '2026-10-10 08:00:00+05:30', '2026-10-10 09:00:00+05:30', '2026-10-10 11:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'fifty_nine_before',
    public.create_event_draft('Fifty Nine Before', 'Wedding', 'Hall', null, '2026-10-10 08:00:00+05:30', '2026-10-10 09:00:00+05:30', '2026-10-10 11:01:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'overnight_existing',
    public.create_event_draft('Overnight Existing', 'Wedding', 'Hall', null, '2026-10-12 22:00:00+05:30', '2026-10-12 23:00:00+05:30', '2026-10-13 02:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'overnight_allowed',
    public.create_event_draft('Overnight Allowed', 'Wedding', 'Hall', null, '2026-10-13 03:00:00+05:30', '2026-10-13 04:00:00+05:30', '2026-10-13 06:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'overnight_blocked',
    public.create_event_draft('Overnight Blocked', 'Wedding', 'Hall', null, '2026-10-13 02:59:00+05:30', '2026-10-13 04:00:00+05:30', '2026-10-13 06:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'edit_source',
    public.create_event_draft('Edit Source', 'Wedding', 'Hall', null, '2026-10-15 08:00:00+05:30', '2026-10-15 09:00:00+05:30', '2026-10-15 11:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  ),
  (
    'edit_other',
    public.create_event_draft('Edit Other', 'Wedding', 'Hall', null, '2026-10-15 14:00:00+05:30', '2026-10-15 15:00:00+05:30', '2026-10-15 17:00:00+05:30', 10, 1200, 'STANDARD', null, null, '[]', '[]', '[]')
  );

select public.publish_event(id, 'Publish for conflict tests')
from phase_8_events;

insert into public.assignments (
  event_id,
  worker_id,
  status,
  source,
  category_at_confirmation
)
values
  ((select id from phase_8_events where key = 'existing'), '00000000-0000-0000-0000-000000008002', 'CONFIRMED', 'DIRECT_APPLY', 'A'),
  ((select id from phase_8_events where key = 'overnight_existing'), '00000000-0000-0000-0000-000000008002', 'CONFIRMED', 'DIRECT_APPLY', 'A'),
  ((select id from phase_8_events where key = 'edit_source'), '00000000-0000-0000-0000-000000008002', 'CONFIRMED', 'DIRECT_APPLY', 'A'),
  ((select id from phase_8_events where key = 'edit_other'), '00000000-0000-0000-0000-000000008002', 'CONFIRMED', 'DIRECT_APPLY', 'A');

select ok(
  not public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'boundary_after')
  ),
  'exactly 60 minutes after an existing assignment is allowed'
);

select ok(
  public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'fifty_nine_after')
  ),
  '59 minutes after an existing assignment is blocked'
);

select ok(
  public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'overlap')
  ),
  'overlapping event times are blocked'
);

select ok(
  not public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'boundary_before')
  ),
  'reverse-order exact 60 minute gap is allowed'
);

select ok(
  public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'fifty_nine_before')
  ),
  'reverse-order 59 minute gap is blocked'
);

select ok(
  not public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'overnight_allowed')
  ),
  'overnight exact 60 minute gap is allowed'
);

select ok(
  public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'overnight_blocked')
  ),
  'overnight 59 minute gap is blocked'
);

update public.assignments
set status = 'CANCELLED'
where event_id = (select id from phase_8_events where key = 'existing');

select ok(
  not public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'fifty_nine_after')
  ),
  'cancelled assignments are ignored by conflict predicate'
);

update public.assignments
set status = 'REMOVED',
    removed_at = now(),
    removal_reason = 'Management removed for test'
where event_id = (select id from phase_8_events where key = 'overnight_existing');

select ok(
  not public.has_booking_conflict(
    '00000000-0000-0000-0000-000000008002',
    (select id from phase_8_events where key = 'overnight_blocked')
  ),
  'removed assignments are ignored by conflict predicate'
);

select throws_ok(
  $$
    select public.update_event(
      (select id from phase_8_events where key = 'edit_source'),
      (select version from public.events where id = (select id from phase_8_events where key = 'edit_source')),
      'Edit Source',
      'Wedding',
      'Hall',
      null,
      '2026-10-15 13:30:00+05:30',
      '2026-10-15 14:00:00+05:30',
      '2026-10-15 16:00:00+05:30',
      10,
      1200,
      'STANDARD',
      null,
      null,
      '[]',
      '[]',
      '[]',
      'Conflict edit without confirmation',
      false
    )
  $$,
  'P0001',
  'EVENT_TIME_CONFLICT_CONFIRMATION_REQUIRED',
  'conflict-producing time edits require explicit confirmation'
);

select lives_ok(
  $$
    select public.update_event(
      (select id from phase_8_events where key = 'edit_source'),
      (select version from public.events where id = (select id from phase_8_events where key = 'edit_source')),
      'Edit Source',
      'Wedding',
      'Hall',
      null,
      '2026-10-15 13:30:00+05:30',
      '2026-10-15 14:00:00+05:30',
      '2026-10-15 16:00:00+05:30',
      10,
      1200,
      'STANDARD',
      null,
      null,
      '[]',
      '[]',
      '[]',
      'Conflict edit with confirmation',
      true
    )
  $$,
  'confirmed conflict-producing time edit is saved'
);

select is(
  (
    select count(*)::integer
    from public.assignment_review_flags
    where flag_type = 'EVENT_TIME_CONFLICT'
      and target_user_id = '00000000-0000-0000-0000-000000008002'
      and state = 'OPEN'
  ),
  1,
  'confirmed conflict-producing edit creates one open assignment review flag'
);

select is(
  (
    select private.active_confirmed_assignment_count(
      (select id from phase_8_events where key = 'edit_source')
    )
  ),
  1,
  'active confirmed assignment count uses real assignments'
);

select *
from finish();

rollback;
