begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

select has_table('public', 'reliability_configs', 'reliability configs table exists');
select has_table('public', 'worker_reliability_snapshots', 'worker reliability snapshots table exists');
select has_function(
  'public',
  'recompute_worker_reliability',
  array['uuid', 'integer'],
  'single worker recompute RPC exists'
);
select has_function(
  'public',
  'recompute_all_worker_reliability',
  array['integer'],
  'nightly reconciliation RPC exists'
);

select is(
  (
    select array[
      show_up_weight,
      punctuality_weight,
      performance_weight,
      commitment_weight
    ]
    from public.reliability_configs
    where version = 1
  ),
  array[0.45, 0.20, 0.20, 0.15]::numeric[],
  'V1 reliability weights are stored exactly'
);

select throws_ok(
  $$ update public.reliability_configs set show_up_weight = 0.40 where version = 1 $$,
  'P0001',
  'published reliability configurations are immutable',
  'published reliability configs are immutable'
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
  ('00000000-0000-0000-0000-000000013001', 'authenticated', 'authenticated', '+919876553001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000013002', 'authenticated', 'authenticated', '+919876553002', crypt('captain-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000013003', 'authenticated', 'authenticated', '+919876553003', crypt('zero-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000013004', 'authenticated', 'authenticated', '+919876553004', crypt('provisional-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000013005', 'authenticated', 'authenticated', '+919876553005', crypt('rated-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000013006', 'authenticated', 'authenticated', '+919876553006', crypt('missing-performance-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000013007', 'authenticated', 'authenticated', '+919876553007', crypt('upper-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000013001', null, 'ADMIN', 'Admin Thirteen', 'AT', '+919876553001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000013002', null, 'CAPTAIN', 'Captain Thirteen', 'CT', '+919876553002', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000013003', nextval('public.worker_number_seq'), 'WORKER', 'Zero History Thirteen', 'ZH', '+919876553003', '00000000-0000-0000-0000-000000013003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000013004', nextval('public.worker_number_seq'), 'WORKER', 'Provisional Thirteen', 'PT', '+919876553004', '00000000-0000-0000-0000-000000013004/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000013005', nextval('public.worker_number_seq'), 'WORKER', 'Rated Thirteen', 'RT', '+919876553005', '00000000-0000-0000-0000-000000013005/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000013006', nextval('public.worker_number_seq'), 'WORKER', 'Missing Performance Thirteen', 'MP', '+919876553006', '00000000-0000-0000-0000-000000013006/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000013007', nextval('public.worker_number_seq'), 'WORKER', 'Upper Bound Thirteen', 'UB', '+919876553007', '00000000-0000-0000-0000-000000013007/profile.webp', now(), 'ACTIVE');

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
select id, 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false
from public.profiles
where id in (
  '00000000-0000-0000-0000-000000013003',
  '00000000-0000-0000-0000-000000013004',
  '00000000-0000-0000-0000-000000013005',
  '00000000-0000-0000-0000-000000013006',
  '00000000-0000-0000-0000-000000013007'
);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000013001', true);

create temp table phase_13_events as
select generate_series(1, 9) as n,
       gen_random_uuid() as id;

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
select
  id,
  'Reliability Fixture ' || n,
  'Wedding',
  'Pune',
  ('2026-10-' || lpad((10 + n)::text, 2, '0'))::date,
  ('2026-10-' || lpad((10 + n)::text, 2, '0') || ' 09:00:00+05:30')::timestamptz,
  ('2026-10-' || lpad((10 + n)::text, 2, '0') || ' 10:00:00+05:30')::timestamptz,
  ('2026-10-' || lpad((10 + n)::text, 2, '0') || ' 18:00:00+05:30')::timestamptz,
  10,
  1000,
  'STANDARD',
  'COMPLETED',
  'CLOSED',
  now(),
  '00000000-0000-0000-0000-000000013001',
  '00000000-0000-0000-0000-000000013001'
from phase_13_events;

create temp table phase_13_assignments (
  label text primary key,
  id uuid not null,
  event_n integer not null,
  worker_id uuid not null
);

insert into phase_13_assignments(label, id, event_n, worker_id)
values
  ('prov-present', gen_random_uuid(), 1, '00000000-0000-0000-0000-000000013004'),
  ('prov-late', gen_random_uuid(), 2, '00000000-0000-0000-0000-000000013004'),
  ('rated-present', gen_random_uuid(), 1, '00000000-0000-0000-0000-000000013005'),
  ('rated-late', gen_random_uuid(), 2, '00000000-0000-0000-0000-000000013005'),
  ('rated-absent', gen_random_uuid(), 3, '00000000-0000-0000-0000-000000013005'),
  ('rated-not-marked', gen_random_uuid(), 4, '00000000-0000-0000-0000-000000013005'),
  ('rated-worker-cancel', gen_random_uuid(), 5, '00000000-0000-0000-0000-000000013005'),
  ('rated-management-cancel', gen_random_uuid(), 6, '00000000-0000-0000-0000-000000013005'),
  ('missing-present', gen_random_uuid(), 1, '00000000-0000-0000-0000-000000013006'),
  ('missing-present-2', gen_random_uuid(), 2, '00000000-0000-0000-0000-000000013006'),
  ('missing-absent', gen_random_uuid(), 3, '00000000-0000-0000-0000-000000013006'),
  ('upper-present-1', gen_random_uuid(), 1, '00000000-0000-0000-0000-000000013007'),
  ('upper-present-2', gen_random_uuid(), 2, '00000000-0000-0000-0000-000000013007'),
  ('upper-present-3', gen_random_uuid(), 3, '00000000-0000-0000-0000-000000013007');

insert into public.assignments (
  id,
  event_id,
  worker_id,
  status,
  source,
  category_at_confirmation,
  completed_at
)
select
  a.id,
  e.id,
  a.worker_id,
  case when a.label like '%cancel%' then 'CANCELLED'::public.assignment_status else 'COMPLETED'::public.assignment_status end,
  'MANAGEMENT',
  'F',
  case when a.label like '%cancel%' then null else now() end
from phase_13_assignments a
join phase_13_events e on e.n = a.event_n;

insert into public.attendance (
  assignment_id,
  event_id,
  worker_id,
  status,
  marked_by,
  marker_role,
  marked_at
)
select
  a.id,
  e.id,
  a.worker_id,
  case
    when a.label like '%late%' then 'LATE'::public.attendance_status
    when a.label like '%absent%' then 'ABSENT'::public.attendance_status
    when a.label like '%not-marked%' then 'NOT_MARKED'::public.attendance_status
    else 'PRESENT'::public.attendance_status
  end,
  '00000000-0000-0000-0000-000000013001',
  'ADMIN',
  now()
from phase_13_assignments a
join phase_13_events e on e.n = a.event_n
where a.label not like '%cancel%';

insert into public.cancellations (
  assignment_id,
  event_id,
  worker_id,
  actor_id,
  actor_role,
  cancellation_type,
  reason,
  idempotency_key,
  deadline_at,
  within_deadline
)
select
  a.id,
  e.id,
  a.worker_id,
  case when a.label like '%worker-cancel%' then a.worker_id else '00000000-0000-0000-0000-000000013001' end,
  case when a.label like '%worker-cancel%' then 'WORKER'::public.app_role else 'ADMIN'::public.app_role end,
  case when a.label like '%worker-cancel%' then 'WORKER' else 'MANAGEMENT' end,
  'Reliability fixture',
  a.label,
  now() + interval '1 day',
  true
from phase_13_assignments a
join phase_13_events e on e.n = a.event_n
where a.label like '%cancel%';

insert into public.performance_reviews (
  event_id,
  assignment_id,
  worker_id,
  reviewer_id,
  reviewer_role,
  stars,
  tags,
  notes
)
select e.id, a.id, a.worker_id, reviewer_id, reviewer_role, stars, array[]::text[], null
from (
  values
    ('rated-present', '00000000-0000-0000-0000-000000013001'::uuid, 'ADMIN'::public.app_role, 5::smallint),
    ('rated-present', '00000000-0000-0000-0000-000000013002'::uuid, 'CAPTAIN'::public.app_role, 3::smallint),
    ('rated-late', '00000000-0000-0000-0000-000000013001'::uuid, 'ADMIN'::public.app_role, 4::smallint),
    ('upper-present-1', '00000000-0000-0000-0000-000000013001'::uuid, 'ADMIN'::public.app_role, 5::smallint),
    ('upper-present-2', '00000000-0000-0000-0000-000000013001'::uuid, 'ADMIN'::public.app_role, 5::smallint),
    ('upper-present-3', '00000000-0000-0000-0000-000000013001'::uuid, 'ADMIN'::public.app_role, 5::smallint)
) reviews(label, reviewer_id, reviewer_role, stars)
join phase_13_assignments a on a.label = reviews.label
join phase_13_events e on e.n = a.event_n;

truncate table public.worker_reliability_snapshots;

select lives_ok(
  $$ select * from public.recompute_worker_reliability('00000000-0000-0000-0000-000000013003', 1) $$,
  'zero-history Worker recomputes'
);

select is(
  (
    select reliability_state
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013003'
  ),
  'PROVISIONAL',
  'zero-history Worker remains provisional'
);

select is(
  (
    select reliability_score
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013003'
  ),
  null::numeric,
  'zero-history Worker score is null'
);

do $$ begin
  perform public.recompute_worker_reliability('00000000-0000-0000-0000-000000013004', 1);
end $$;

select is(
  (
    select reliability_sample_count
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013004'
  ),
  2,
  'two resolved commitments are counted'
);

select is(
  (
    select reliability_score
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013004'
  ),
  null::numeric,
  'one to two commitments remain unrated'
);

do $$ begin
  perform public.recompute_worker_reliability('00000000-0000-0000-0000-000000013005', 1);
end $$;

select is(
  (
    select reliability_state
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  'RATED',
  'three or more commitments become rated'
);

select is(
  (
    select reliability_sample_count
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  4,
  'eligible sample excludes NOT_MARKED and management cancellation'
);

select is(
  (
    select reliability_score
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  66.25::numeric,
  'exact weighted score uses normalized available components'
);

select is(
  (
    select array[
      reliability_present_count,
      reliability_late_count,
      reliability_absent_count,
      reliability_worker_cancellation_count
    ]
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  array[1, 1, 1, 1],
  'present late absent and Worker cancellation counts are stored'
);

select is(
  (
    select reliability_performance_average
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  4.00::numeric,
  'multiple reviewers are averaged per event before cross-event average'
);

do $$ begin
  perform public.recompute_worker_reliability('00000000-0000-0000-0000-000000013006', 1);
end $$;

select is(
  (
    select reliability_score
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013006'
  ),
  81.25::numeric,
  'missing performance data normalizes remaining available weights'
);

do $$ begin
  perform public.recompute_worker_reliability('00000000-0000-0000-0000-000000013007', 1);
end $$;

select is(
  (
    select reliability_score
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013007'
  ),
  100.00::numeric,
  'score upper bound is 100'
);

select is(
  (
    select min(score) >= 0 and max(score) <= 100
    from public.worker_reliability_snapshots
    where score is not null
  ),
  true,
  'snapshot scores remain within 0-100'
);

select is(
  (
    select count(*)::integer
    from public.worker_reliability_snapshots
    where worker_id = '00000000-0000-0000-0000-000000013005'
  ),
  1,
  'idempotent recompute stores one source-equivalent snapshot before source change'
);

do $$ begin
  perform public.recompute_worker_reliability('00000000-0000-0000-0000-000000013005', 1);
end $$;

select is(
  (
    select count(*)::integer
    from public.worker_reliability_snapshots
    where worker_id = '00000000-0000-0000-0000-000000013005'
  ),
  1,
  'unchanged recompute does not create duplicate snapshot'
);

update public.attendance
set status = 'PRESENT'
where assignment_id = (
  select id from phase_13_assignments where label = 'rated-late'
);

select is(
  (
    select reliability_late_count
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  0,
  'attendance correction triggers recomputation'
);

select is(
  (
    select count(*)::integer
    from public.worker_reliability_snapshots
    where worker_id = '00000000-0000-0000-0000-000000013005'
  ),
  2,
  'source change creates a new snapshot'
);

update public.performance_reviews
set stars = 5
where worker_id = '00000000-0000-0000-0000-000000013005'
  and reviewer_id = '00000000-0000-0000-0000-000000013001'
  and assignment_id = (select id from phase_13_assignments where label = 'rated-late');

select is(
  (
    select reliability_performance_average
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  4.50::numeric,
  'performance review update triggers recomputation'
);

insert into public.cancellations (
  assignment_id,
  event_id,
  worker_id,
  actor_id,
  actor_role,
  cancellation_type,
  reason,
  idempotency_key,
  deadline_at,
  within_deadline
)
select
  a.id,
  e.id,
  a.worker_id,
  a.worker_id,
  'WORKER',
  'WORKER',
  'Additional worker cancellation',
  'rated-extra-worker-cancel',
  now() + interval '1 day',
  true
from phase_13_assignments a
join phase_13_events e on e.n = a.event_n
where a.label = 'rated-not-marked';

select is(
  (
    select reliability_worker_cancellation_count
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  2,
  'Worker cancellation insert triggers recomputation'
);

select is(
  (
    select count(*)::integer
    from public.worker_reliability_snapshots
    where worker_id = '00000000-0000-0000-0000-000000013005'
      and config_version = 1
  ),
  4,
  'snapshot history preserves successive source changes'
);

insert into public.reliability_configs (
  version,
  name,
  show_up_weight,
  punctuality_weight,
  performance_weight,
  commitment_weight,
  minimum_resolved_commitments,
  published_at
)
values (2, 'Alternate test config', 0.50, 0.20, 0.15, 0.15, 3, now());

do $$ begin
  perform public.recompute_worker_reliability('00000000-0000-0000-0000-000000013005', 2);
end $$;

select is(
  (
    select reliability_config_version
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  2,
  'recompute can publish current score under a new config version'
);

select ok(
  exists (
    select 1
    from public.worker_reliability_snapshots
    where worker_id = '00000000-0000-0000-0000-000000013005'
      and config_version = 1
  )
  and exists (
    select 1
    from public.worker_reliability_snapshots
    where worker_id = '00000000-0000-0000-0000-000000013005'
      and config_version = 2
  ),
  'snapshots preserve configuration-version reproducibility'
);

select is(
  (
    select category
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000013005'
  ),
  'F'::public.worker_category,
  'reliability recomputation never changes category'
);

select is(
  (select public.recompute_all_worker_reliability(1)),
  5,
  'nightly reconciliation recomputes all current Worker profiles'
);

select *
from finish();

rollback;
