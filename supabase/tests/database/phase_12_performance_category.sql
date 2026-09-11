begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

select has_table('public', 'performance_reviews', 'performance_reviews table exists');
select has_table('public', 'performance_review_history', 'performance review history table exists');
select has_function(
  'public',
  'record_performance_review',
  array['uuid', 'integer', 'text[]', 'text'],
  'performance review RPC exists'
);
select has_function(
  'public',
  'change_worker_category',
  array['uuid', 'public.worker_category', 'text', 'text'],
  'worker category change RPC exists'
);

select ok(
  not has_table_privilege('authenticated', 'public.performance_reviews', 'INSERT'),
  'authenticated users cannot directly insert performance reviews'
);

select ok(
  not has_table_privilege('authenticated', 'public.performance_reviews', 'UPDATE'),
  'authenticated users cannot directly update performance reviews'
);

select ok(
  not has_table_privilege('authenticated', 'public.performance_review_history', 'INSERT'),
  'authenticated users cannot directly insert performance review history'
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
  ('00000000-0000-0000-0000-000000012001', 'authenticated', 'authenticated', '+919876552001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000012002', 'authenticated', 'authenticated', '+919876552002', crypt('captain-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000012003', 'authenticated', 'authenticated', '+919876552003', crypt('supervisor-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000012004', 'authenticated', 'authenticated', '+919876552004', crypt('other-captain-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000012005', 'authenticated', 'authenticated', '+919876552005', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000012006', 'authenticated', 'authenticated', '+919876552006', crypt('worker-b-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000012007', 'authenticated', 'authenticated', '+919876552007', crypt('worker-f-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000012001', null, 'ADMIN', 'Admin Twelve', 'AT', '+919876552001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000012002', null, 'CAPTAIN', 'Captain Twelve', 'CT', '+919876552002', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000012003', null, 'SUPERVISOR', 'Supervisor Twelve', 'ST', '+919876552003', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000012004', null, 'CAPTAIN', 'Other Captain Twelve', 'OC', '+919876552004', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000012005', nextval('public.worker_number_seq'), 'WORKER', 'Worker A Twelve', 'WA', '+919876552005', '00000000-0000-0000-0000-000000012005/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000012006', nextval('public.worker_number_seq'), 'WORKER', 'Worker B Twelve', 'WB', '+919876552006', '00000000-0000-0000-0000-000000012006/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000012007', nextval('public.worker_number_seq'), 'WORKER', 'Worker F Twelve', 'WF', '+919876552007', '00000000-0000-0000-0000-000000012007/profile.webp', now(), 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000012005', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000012006', 'B', 'B', (current_date - interval '20 years')::date, 'Pune', 'Pune', 171, 'College', false),
  ('00000000-0000-0000-0000-000000012007', 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 172, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012001', true);

create temp table phase_12_event as
select public.create_event_draft(
  'Phase 12 Performance',
  'Wedding',
  'Pune Hall',
  null,
  '2026-10-12 15:00:00+05:30',
  '2026-10-12 16:00:00+05:30',
  '2026-10-12 23:00:00+05:30',
  4,
  1200,
  'STANDARD',
  null,
  null,
  '[{"user_id":"00000000-0000-0000-0000-000000012002","leader_role":"CAPTAIN"},{"user_id":"00000000-0000-0000-0000-000000012003","leader_role":"SUPERVISOR"}]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.publish_event((select id from phase_12_event), 'Publish performance event');

insert into public.assignments (
  event_id,
  worker_id,
  status,
  source,
  category_at_confirmation
)
values
  ((select id from phase_12_event), '00000000-0000-0000-0000-000000012005', 'CONFIRMED', 'MANAGEMENT', 'A'),
  ((select id from phase_12_event), '00000000-0000-0000-0000-000000012006', 'COMPLETED', 'MANAGEMENT', 'B');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012002', true);

select lives_ok(
  $$
    select *
    from public.record_performance_review(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000012005'
      ),
      5,
      array['punctual', 'professional']::text[],
      'Strong shift'
    )
  $$,
  'assigned Captain can record a performance review'
);

select is(
  (
    select stars::integer
    from public.performance_reviews
    where worker_id = '00000000-0000-0000-0000-000000012005'
  ),
  5,
  'performance review stores 1-5 star value'
);

select is(
  (
    select tags
    from public.performance_reviews
    where worker_id = '00000000-0000-0000-0000-000000012005'
  ),
  array['professional', 'punctual']::text[],
  'performance review stores normalized optional tags'
);

select lives_ok(
  $$
    select *
    from public.record_performance_review(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000012005'
      ),
      4,
      array['corrected']::text[],
      'Updated before close'
    )
  $$,
  'same reviewer can edit review before Close'
);

select is(
  (
    select count(*)::integer
    from public.performance_reviews
    where reviewer_id = '00000000-0000-0000-0000-000000012002'
      and worker_id = '00000000-0000-0000-0000-000000012005'
      and event_id = (select id from phase_12_event)
  ),
  1,
  'one review exists per reviewer worker event after edit'
);

select is(
  (
    select count(*)::integer
    from public.performance_review_history
    where worker_id = '00000000-0000-0000-0000-000000012005'
  ),
  2,
  'performance review create and edit are audited'
);

select throws_ok(
  $$
    select *
    from public.record_performance_review(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000012006'
      ),
      6,
      array[]::text[],
      null
    )
  $$,
  'P0001',
  'performance rating must be between 1 and 5',
  'rating above 5 is rejected'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012004', true);

select throws_ok(
  $$
    select *
    from public.record_performance_review(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000012006'
      ),
      3,
      array[]::text[],
      null
    )
  $$,
  'P0001',
  'not authorized for event operations',
  'unassigned field leader cannot record performance review'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012006', true);

select throws_ok(
  $$
    select *
    from public.record_performance_review(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000012005'
      ),
      3,
      array[]::text[],
      null
    )
  $$,
  'P0001',
  'not authorized to record performance reviews',
  'Worker cannot record performance review'
);

update public.events
set event_status = 'CLOSED',
    recruitment_status = 'CLOSED'
where id = (select id from phase_12_event);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012001', true);

select throws_ok(
  $$
    select *
    from public.record_performance_review(
      (
        select id
        from public.assignments
        where worker_id = '00000000-0000-0000-0000-000000012006'
      ),
      5,
      array[]::text[],
      'After close'
    )
  $$,
  'P0001',
  'performance reviews are closed for this event',
  'performance reviews cannot be created after Close'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012002', true);

select lives_ok(
  $$
    select *
    from public.change_worker_category(
      '00000000-0000-0000-0000-000000012006',
      'A',
      'Excellent recent performance',
      'Phase 12 test'
    )
  $$,
  'Captain can globally promote a Worker one step'
);

select is(
  (
    select category
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000012006'
  ),
  'A'::public.worker_category,
  'category change updates current Worker category immediately'
);

select is(
  (
    select action
    from public.worker_category_history
    where worker_id = '00000000-0000-0000-0000-000000012006'
    order by created_at desc, id desc
    limit 1
  ),
  'PROMOTION',
  'promotion history uses PROMOTION action'
);

select is(
  (
    select reason
    from public.worker_category_history
    where worker_id = '00000000-0000-0000-0000-000000012006'
    order by created_at desc
    limit 1
  ),
  'Excellent recent performance',
  'promotion reason is stored'
);

select is(
  (
    select count(*)::integer
    from public.notifications
    where recipient_id = '00000000-0000-0000-0000-000000012006'
      and notification_type = 'CATEGORY_CHANGED'
  ),
  1,
  'category change creates worker notification'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012003', true);

select lives_ok(
  $$
    select *
    from public.change_worker_category(
      '00000000-0000-0000-0000-000000012006',
      'B',
      'Needs another review cycle',
      null
    )
  $$,
  'Supervisor can globally demote a Worker one step'
);

select is(
  (
    select count(*)::integer
    from public.worker_category_history
    where worker_id = '00000000-0000-0000-0000-000000012006'
      and action = 'DEMOTION'
      and old_category = 'A'
      and new_category = 'B'
  ),
  1,
  'demotion history uses DEMOTION action'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012001', true);

select throws_ok(
  $$
    select *
    from public.change_worker_category(
      '00000000-0000-0000-0000-000000012007',
      'A',
      'Trying to skip levels',
      null
    )
  $$,
  'P0001',
  'category changes must move exactly one step',
  'skipped category transition is rejected'
);

select throws_ok(
  $$
    select *
    from public.change_worker_category(
      '00000000-0000-0000-0000-000000012007',
      'C',
      '',
      null
    )
  $$,
  'P0001',
  'category change reason is required',
  'category change without reason is rejected'
);

select throws_ok(
  $$
    select *
    from public.change_worker_category(
      '00000000-0000-0000-0000-000000012002',
      'C',
      'Not a worker',
      null
    )
  $$,
  'P0001',
  'worker profile not found',
  'category change on non-worker without worker profile is rejected'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012007', true);

select throws_ok(
  $$
    select *
    from public.change_worker_category(
      '00000000-0000-0000-0000-000000012006',
      'A',
      'Worker attempt',
      null
    )
  $$,
  'P0001',
  'not authorized to change worker category',
  'Worker cannot change another Worker category'
);

select is(
  (
    select count(*)::integer
    from public.audit_logs
    where action = 'worker_category_changed'
      and entity_id = '00000000-0000-0000-0000-000000012006'
  ),
  2,
  'category changes are written to audit logs'
);

select ok(
  (
    select reliability_score is null
    from public.worker_profiles
    where user_id = '00000000-0000-0000-0000-000000012006'
  ),
  'category changes do not compute or alter deferred reliability score'
);

select *
from finish();

rollback;
