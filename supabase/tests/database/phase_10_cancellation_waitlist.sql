begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

select has_table('public', 'waitlist_entries', 'waitlist entries table exists');
select has_table('public', 'cancellations', 'cancellations table exists');
select has_function('public', 'join_waitlist', array['uuid', 'text', 'uuid[]'], 'join waitlist RPC exists');
select has_function('public', 'withdraw_waitlist', array['uuid', 'text'], 'withdraw waitlist RPC exists');
select has_function('public', 'cancel_assignment', array['uuid', 'text', 'text'], 'cancel assignment RPC exists');
select has_function('public', 'promote_waitlist', array['uuid'], 'promote waitlist RPC exists');

select ok(
  not has_table_privilege('authenticated', 'public.waitlist_entries', 'INSERT'),
  'authenticated users cannot directly insert waitlist entries'
);

select ok(
  not has_table_privilege('authenticated', 'public.cancellations', 'INSERT'),
  'authenticated users cannot directly insert cancellations'
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
  ('00000000-0000-0000-0000-000000010001', 'authenticated', 'authenticated', '+919876550001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000010002', 'authenticated', 'authenticated', '+919876550002', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000010003', 'authenticated', 'authenticated', '+919876550003', crypt('worker-b-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000010004', 'authenticated', 'authenticated', '+919876550004', crypt('worker-c1-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000010005', 'authenticated', 'authenticated', '+919876550005', crypt('worker-c2-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000010006', 'authenticated', 'authenticated', '+919876550006', crypt('worker-f-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000010001', null, 'ADMIN', 'Admin Ten', 'AT', '+919876550001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000010002', nextval('public.worker_number_seq'), 'WORKER', 'Worker A Ten', 'WA', '+919876550002', '00000000-0000-0000-0000-000000010002/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000010003', nextval('public.worker_number_seq'), 'WORKER', 'Worker B Ten', 'WB', '+919876550003', '00000000-0000-0000-0000-000000010003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000010004', nextval('public.worker_number_seq'), 'WORKER', 'Worker C1 Ten', 'WC', '+919876550004', '00000000-0000-0000-0000-000000010004/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000010005', nextval('public.worker_number_seq'), 'WORKER', 'Worker C2 Ten', 'WC', '+919876550005', '00000000-0000-0000-0000-000000010005/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000010006', nextval('public.worker_number_seq'), 'WORKER', 'Worker F Ten', 'WF', '+919876550006', '00000000-0000-0000-0000-000000010006/profile.webp', now(), 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000010002', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000010003', 'B', 'B', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000010004', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000010005', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000010006', 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010001', true);

create temp table phase_10_events (key text primary key, id uuid not null);

insert into phase_10_events
values
  ('waitlist', public.create_event_draft('Waitlist Event', 'Wedding', 'Hall', null, '2026-10-10 15:00:00+05:30', '2026-10-10 16:00:00+05:30', '2026-10-10 23:00:00+05:30', 1, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('promote_category', public.create_event_draft('Promote Category', 'Wedding', 'Hall', null, '2026-10-11 15:00:00+05:30', '2026-10-11 16:00:00+05:30', '2026-10-11 23:00:00+05:30', 1, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('promote_same_category', public.create_event_draft('Promote Same Category', 'Wedding', 'Hall', null, '2026-10-12 15:00:00+05:30', '2026-10-12 16:00:00+05:30', '2026-10-12 23:00:00+05:30', 1, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('late', public.create_event_draft('Late Booking Event', 'Wedding', 'Hall', null, now() + interval '30 minutes', now() + interval '90 minutes', now() + interval '4 hours', 2, 1200, 'STANDARD', null, null, '[]', '[]', '[]')),
  ('skip', public.create_event_draft('Skip Invalid Waitlist', 'Wedding', 'Hall', null, '2026-10-13 15:00:00+05:30', '2026-10-13 16:00:00+05:30', '2026-10-13 23:00:00+05:30', 1, 1200, 'STANDARD', null, null, '[]', '[]', '[]'));

select public.publish_event(id, 'Publish phase 10 event') from phase_10_events;

update public.event_tier_release_rules
set opens_at = now() - interval '1 minute'
where event_id in (select id from phase_10_events);

select public.process_due_tier_releases();

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010002', true);

create temp table phase_10_waitlist_fill as
select * from public.apply_for_event((select id from phase_10_events where key = 'waitlist'), 'fill-waitlist', '{}', false);

select is((select result from phase_10_waitlist_fill), 'CONFIRMED'::public.booking_result, 'initial apply fills event');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010004', true);

select is(
  (select result from public.apply_for_event((select id from phase_10_events where key = 'waitlist'), 'full-no-auto', '{}', false)),
  'WAITLIST_AVAILABLE'::public.booking_result,
  'apply to full event returns waitlist available'
);

select is(
  (select count(*)::integer from public.waitlist_entries where event_id = (select id from phase_10_events where key = 'waitlist')),
  0,
  'full apply does not automatically create a waitlist entry'
);

create temp table phase_10_join_result as
select * from public.join_waitlist((select id from phase_10_events where key = 'waitlist'), 'join-c1', '{}');

select is((select status from phase_10_join_result), 'WAITING'::public.waitlist_status, 'explicit join creates waiting entry');
select is((select queue_position from phase_10_join_result), 1, 'first waiting worker has position 1');

select is(
  (select result_detail_code from public.join_waitlist((select id from phase_10_events where key = 'waitlist'), 'join-c1-duplicate', '{}')),
  'DUPLICATE',
  'duplicate Join Waitlist is protected'
);

select is(
  public.withdraw_waitlist((select waitlist_entry_id from phase_10_join_result), 'Changed plans'),
  'WITHDRAWN'::public.waitlist_status,
  'waiting worker can withdraw without penalty'
);

select ok(
  not (select penalty_applies from public.waitlist_entries where id = (select waitlist_entry_id from phase_10_join_result)),
  'withdrawn waitlist entry has no penalty'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010002', true);
create temp table phase_10_category_fill as
select * from public.apply_for_event((select id from phase_10_events where key = 'promote_category'), 'fill-category', '{}', false);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010004', true);
select * from public.join_waitlist((select id from phase_10_events where key = 'promote_category'), 'join-category-c', '{}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010003', true);
select * from public.join_waitlist((select id from phase_10_events where key = 'promote_category'), 'join-category-b', '{}');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010002', true);
create temp table phase_10_category_cancel as
select *
from public.cancel_assignment((select assignment_id from phase_10_category_fill), 'Before deadline', 'cancel-category');

select is((select status from phase_10_category_cancel), 'CANCELLED'::public.assignment_status, 'worker can cancel before deadline');

select is(
  (
    select worker_id
    from public.assignments
    where id = (select promoted_assignment_id from phase_10_category_cancel)
  ),
  '00000000-0000-0000-0000-000000010003'::uuid,
  'B waitlist worker is promoted before earlier C worker'
);

select is(
  (
    select status
    from public.waitlist_entries
    where worker_id = '00000000-0000-0000-0000-000000010003'
      and event_id = (select id from phase_10_events where key = 'promote_category')
  ),
  'PROMOTED'::public.waitlist_status,
  'promoted waitlist entry is marked promoted'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010003', true);

select throws_ok(
  $$
    select public.withdraw_waitlist(
      (
        select id
        from public.waitlist_entries
        where worker_id = '00000000-0000-0000-0000-000000010003'
          and event_id = (select id from phase_10_events where key = 'promote_category')
      ),
      'Cannot withdraw promoted'
    )
  $$,
  'P0001',
  'promoted waitlist entries use normal cancellation rules',
  'promoted waitlist entries cannot be withdrawn'
);

select is(
  (
    select count(*)::integer
    from public.notifications
    where recipient_id = '00000000-0000-0000-0000-000000010003'
      and notification_type = 'WAITLIST_PROMOTED'
  ),
  1,
  'waitlist promotion creates notification'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010002', true);
create temp table phase_10_same_fill as
select * from public.apply_for_event((select id from phase_10_events where key = 'promote_same_category'), 'fill-same', '{}', false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010004', true);
select * from public.join_waitlist((select id from phase_10_events where key = 'promote_same_category'), 'join-same-c1', '{}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010005', true);
select * from public.join_waitlist((select id from phase_10_events where key = 'promote_same_category'), 'join-same-c2', '{}');
update public.waitlist_entries
set joined_at = now() - interval '2 minutes'
where event_id = (select id from phase_10_events where key = 'promote_same_category')
  and worker_id = '00000000-0000-0000-0000-000000010004';
update public.waitlist_entries
set joined_at = now() - interval '1 minute'
where event_id = (select id from phase_10_events where key = 'promote_same_category')
  and worker_id = '00000000-0000-0000-0000-000000010005';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010002', true);
create temp table phase_10_same_cancel as
select * from public.cancel_assignment((select assignment_id from phase_10_same_fill), 'Before deadline', 'cancel-same');

select is(
  (
    select worker_id
    from public.assignments
    where id = (select promoted_assignment_id from phase_10_same_cancel)
  ),
  '00000000-0000-0000-0000-000000010004'::uuid,
  'same-category waitlist promotion uses earliest join time'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010004', true);

select is(
  (select result_detail_code from public.apply_for_event((select id from phase_10_events where key = 'late'), 'late-needs-ack', '{}', false)),
  'LATE_CANCELLATION_ACK_REQUIRED',
  'late booking requires explicit acknowledgement'
);

create temp table phase_10_late_apply as
select * from public.apply_for_event((select id from phase_10_events where key = 'late'), 'late-with-ack', '{}', true);

select ok(
  (select late_cancellation_acknowledged from public.assignments where id = (select assignment_id from phase_10_late_apply)),
  'late booking stores cancellation-lock acknowledgement'
);

select throws_ok(
  $$
    select public.cancel_assignment(
      (select assignment_id from phase_10_late_apply),
      'Too late',
      'cancel-too-late'
    )
  $$,
  'P0001',
  'CANCELLATION_LOCKED',
  'worker cancellation after the one-hour deadline is blocked'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010002', true);
create temp table phase_10_skip_fill as
select * from public.apply_for_event((select id from phase_10_events where key = 'skip'), 'fill-skip', '{}', false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010006', true);
select * from public.join_waitlist((select id from phase_10_events where key = 'skip'), 'join-skip-f', '{}');

select set_config('app.bypass_identity_protection', 'on', true);
update public.profiles
set account_status = 'INACTIVE'
where id = '00000000-0000-0000-0000-000000010006';
select set_config('app.bypass_identity_protection', 'off', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010002', true);
select * from public.cancel_assignment((select assignment_id from phase_10_skip_fill), 'Before deadline', 'cancel-skip');

select is(
  (
    select skip_reason
    from public.waitlist_entries
    where worker_id = '00000000-0000-0000-0000-000000010006'
      and event_id = (select id from phase_10_events where key = 'skip')
  ),
  'WORKER_NOT_ACTIVE_OR_COMPLETE',
  'promotion revalidation skips inactive waiting worker'
);

select is(
  (
    select count(*)::integer
    from public.cancellations
    where worker_id = '00000000-0000-0000-0000-000000010002'
  ),
  3,
  'successful worker cancellations are recorded immutably'
);

select *
from finish();

rollback;
