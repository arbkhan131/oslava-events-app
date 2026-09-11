begin;

create extension if not exists pgtap with schema extensions;

select plan(46);

select has_table('public', 'device_tokens', 'device_tokens table exists');
select has_table('public', 'notification_deliveries', 'notification deliveries table exists');
select has_table('public', 'reporting_reminder_schedules', 'reporting reminder schedules table exists');
select has_function(
  'public',
  'register_device_token',
  array['text', 'text', 'text', 'text'],
  'device token registration RPC exists'
);
select has_function(
  'public',
  'claim_notification_deliveries',
  array['text', 'integer'],
  'delivery claim RPC exists'
);
select has_function(
  'public',
  'complete_claimed_notification_delivery',
  array['uuid', 'text', 'boolean', 'text', 'text', 'text', 'boolean'],
  'owned delivery completion RPC exists'
);
select has_function(
  'public',
  'run_scheduled_operations',
  array['text', 'text'],
  'scheduled operations runner RPC exists'
);
select has_function(
  'public',
  'notification_delivery_health',
  array[]::text[],
  'notification delivery health RPC exists'
);
select has_table('public', 'scheduled_job_runs', 'scheduled job runs table exists');
select ok(
  not has_table_privilege('authenticated', 'public.device_tokens', 'INSERT'),
  'authenticated users cannot directly insert device tokens'
);
select ok(
  not has_table_privilege('authenticated', 'public.notification_deliveries', 'UPDATE'),
  'authenticated users cannot directly update delivery state'
);
select ok(
  not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'notification_quiet_hours'
  ),
  'V1 has no app-level quiet hours table'
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
  ('00000000-0000-0000-0000-000000014001', 'authenticated', 'authenticated', '+919876554001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000014002', 'authenticated', 'authenticated', '+919876554002', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000014003', 'authenticated', 'authenticated', '+919876554003', crypt('worker-b-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000014004', 'authenticated', 'authenticated', '+919876554004', crypt('worker-c-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000014001', null, 'ADMIN', 'Admin Fourteen', 'AF', '+919876554001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000014002', nextval('public.worker_number_seq'), 'WORKER', 'Worker A Fourteen', 'WA', '+919876554002', '00000000-0000-0000-0000-000000014002/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000014003', nextval('public.worker_number_seq'), 'WORKER', 'Worker B Fourteen', 'WB', '+919876554003', '00000000-0000-0000-0000-000000014003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000014004', nextval('public.worker_number_seq'), 'WORKER', 'Worker C Fourteen', 'WC', '+919876554004', '00000000-0000-0000-0000-000000014004/profile.webp', now(), 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000014002', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000014003', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 171, 'College', false),
  ('00000000-0000-0000-0000-000000014004', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 172, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000014002', true);

select lives_ok(
  $$ select public.register_device_token('fcm-token-worker-a', 'android', 'emulator-1', 'local') $$,
  'worker can register own FCM token'
);

select is(
  (
    select count(*)::integer
    from public.device_tokens
    where user_id = '00000000-0000-0000-0000-000000014002'
      and active
      and platform = 'android'
  ),
  1,
  'registered token is active and platform tagged'
);

select lives_ok(
  $$ select public.register_device_token('fcm-token-worker-a', 'android', 'emulator-1', 'local') $$,
  'device token registration is idempotent'
);

select is(
  (
    select count(*)::integer
    from public.device_tokens
    where user_id = '00000000-0000-0000-0000-000000014002'
  ),
  1,
  'duplicate token registration does not create another token row'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000014003', true);

select lives_ok(
  $$ select public.register_device_token('fcm-token-worker-a', 'android', 'emulator-1', 'local') $$,
  'same FCM token can move to a newly authenticated user'
);

select is(
  (
    select count(*)::integer
    from public.device_tokens
    where token_hash = encode(extensions.digest('fcm-token-worker-a', 'sha256'), 'hex')
      and active
      and user_id = '00000000-0000-0000-0000-000000014003'
  ),
  1,
  'same FCM token has exactly one active owner after account switching'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000014002', true);

do $$ begin
  perform public.register_device_token('fcm-token-worker-a-returned', 'android', 'emulator-1', 'local');
end $$;

insert into public.notifications (
  recipient_id,
  notification_type,
  title,
  body,
  deduplication_key,
  deep_link_path
)
values (
  '00000000-0000-0000-0000-000000014002',
  'NEW_EVENT',
  'New event',
  'A new event is available.',
  'phase14-new-event',
  '/worker/events'
)
on conflict (recipient_id, deduplication_key) do nothing;

select is(
  (
    select count(*)::integer
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-new-event'
  ),
  1,
  'durable notification creates one FCM delivery row'
);

select is(
  (
    select count(*)::integer
    from public.claim_notification_deliveries('test-dispatcher', 10)
  ),
  1,
  'dispatcher claims pending notification delivery'
);

select is(
  (
    select state
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-new-event'
  ),
  'CLAIMED',
  'claimed delivery state is stored'
);

select ok(
  (
    select claim_expires_at > now()
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-new-event'
  ),
  'claimed delivery receives an expiring lease'
);

select is(
  (
    select public.complete_notification_delivery(
      nd.id,
      true,
      'provider-message-id',
      '200',
      'ok',
      false
    )
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-new-event'
  ),
  'SENT',
  'successful delivery records SENT state'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000014003', true);

select is(
  (
    select public.invalidate_device_token('fcm-token-worker-a')
  ),
  true,
  'user can invalidate own token after account switch'
);

select is(
  (
    select active
    from public.device_tokens
    where user_id = '00000000-0000-0000-0000-000000014003'
      and token_hash = encode(extensions.digest('fcm-token-worker-a', 'sha256'), 'hex')
  ),
  false,
  'invalidated token is inactive'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000014002', true);

update public.notification_deliveries
set state = 'SKIPPED'
where state = 'PENDING'
  and notification_id in (
    select id
    from public.notifications
    where deduplication_key = 'phase14-new-event'
  );

insert into public.notifications (
  recipient_id,
  notification_type,
  title,
  body,
  deduplication_key
)
values (
  '00000000-0000-0000-0000-000000014002',
  'EVENT_UPDATED',
  'Event updated',
  'Schedule changed.',
  'phase14-retry'
);

select is(
  (
    select count(*)::integer
    from public.claim_notification_deliveries('test-dispatcher', 10)
  ),
  1,
  'dispatcher claims retry fixture delivery'
);

select throws_ok(
  $$
    select public.complete_claimed_notification_delivery(
      nd.id,
      'other-dispatcher',
      false,
      null,
      '500',
      'temporary failure',
      false
    )
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-retry'
  $$,
  'notification delivery claim is not owned by this worker or has expired',
  'wrong dispatcher cannot complete another worker claim'
);

select is(
  (
    select public.complete_claimed_notification_delivery(
      nd.id,
      'test-dispatcher',
      false,
      null,
      '500',
      'temporary failure',
      false
    )
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-retry'
  ),
  'PENDING',
  'temporary delivery failure returns to pending with backoff'
);

select is(
  (
    select completed_by
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-retry'
  ),
  'test-dispatcher',
  'owned completion records the completing dispatcher'
);

select ok(
  (
    select next_attempt_at > now()
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.deduplication_key = 'phase14-retry'
  ),
  'retry backoff schedules a future attempt'
);

select ok(
  (select pending_count >= 1 from public.notification_delivery_health()),
  'delivery health reports pending retry work'
);

create temp table phase_14_events (
  label text primary key,
  id uuid not null,
  reporting_at timestamptz not null
);

insert into phase_14_events(label, id, reporting_at)
values
  ('thirty-hour', gen_random_uuid(), now() + interval '30 hours'),
  ('six-hour', gen_random_uuid(), now() + interval '6 hours'),
  ('forty-five-min', gen_random_uuid(), now() + interval '45 minutes'),
  ('cancelled-event', gen_random_uuid(), now() + interval '30 hours'),
  ('removed-assignment', gen_random_uuid(), now() + interval '30 hours');

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
  'Reminder ' || label,
  'Wedding',
  'Pune',
  reporting_at::date,
  reporting_at,
  reporting_at + interval '1 hour',
  reporting_at + interval '8 hours',
  10,
  1000,
  'STANDARD',
  'UPCOMING',
  'OPEN',
  now(),
  '00000000-0000-0000-0000-000000014001',
  '00000000-0000-0000-0000-000000014001'
from phase_14_events;

create temp table phase_14_assignments as
select label, gen_random_uuid() as id, id as event_id
from phase_14_events;

insert into public.assignments (
  id,
  event_id,
  worker_id,
  status,
  source,
  category_at_confirmation
)
select
  id,
  event_id,
  '00000000-0000-0000-0000-000000014002',
  'CONFIRMED',
  'MANAGEMENT',
  'A'
from phase_14_assignments;

select is(
  (
    select count(*)::integer
    from public.reporting_reminder_schedules rs
    join phase_14_assignments a on a.id = rs.assignment_id
    where a.label = 'thirty-hour'
  ),
  2,
  '30-hour confirmation schedules 24h and 2h reminders'
);

select is(
  (
    select count(*)::integer
    from public.reporting_reminder_schedules rs
    join phase_14_assignments a on a.id = rs.assignment_id
    where a.label = 'six-hour'
  ),
  1,
  '6-hour confirmation skips expired 24h reminder'
);

select is(
  (
    select count(*)::integer
    from public.reporting_reminder_schedules rs
    join phase_14_assignments a on a.id = rs.assignment_id
    where a.label = 'forty-five-min'
  ),
  0,
  '45-minute confirmation skips all expired reminders'
);

update public.events
set event_status = 'CANCELLED',
    recruitment_status = 'CLOSED',
    cancelled_at = now(),
    cancelled_by = '00000000-0000-0000-0000-000000014001'
where id = (select event_id from phase_14_assignments where label = 'cancelled-event');

update public.reporting_reminder_schedules
set trigger_at = now() - interval '1 minute'
where assignment_id = (select id from phase_14_assignments where label = 'cancelled-event');

select is(
  (select public.process_due_reporting_reminders()),
  0,
  'cancelled events do not send due reporting reminders'
);

select is(
  (
    select count(*)::integer
    from public.reporting_reminder_schedules rs
    join phase_14_assignments a on a.id = rs.assignment_id
    where a.label = 'cancelled-event'
      and rs.skipped_at is not null
  ),
  2,
  'cancelled event reminders are skipped'
);

update public.assignments
set status = 'REMOVED',
    removed_at = now(),
    removed_by = '00000000-0000-0000-0000-000000014001',
    removal_reason = 'Phase 14 test removal',
    category_at_confirmation = null
where id = (select id from phase_14_assignments where label = 'removed-assignment');

select is(
  (
    select count(*)::integer
    from public.reporting_reminder_schedules rs
    join phase_14_assignments a on a.id = rs.assignment_id
    where a.label = 'removed-assignment'
      and rs.skipped_at is not null
  ),
  2,
  'removed assignment reminders are skipped'
);

update public.reporting_reminder_schedules
set trigger_at = now() - interval '1 minute'
where assignment_id = (select id from phase_14_assignments where label = 'six-hour');

select is(
  (select public.process_due_reporting_reminders()),
  1,
  'due reporting reminder creates notification'
);

select is(
  (
    select count(*)::integer
    from public.notifications
    where notification_type = 'REPORTING_REMINDER'
      and deduplication_key like 'reporting-reminder:%:2'
  ),
  1,
  '2h reporting reminder uses duplicate-safe key'
);

select is(
  (select public.process_due_reporting_reminders()),
  0,
  'reporting reminder processing is idempotent'
);

select is(
  (select public.run_scheduled_operations('phase14-test', 'test-scheduler')->>'status'),
  'SUCCEEDED',
  'scheduled operations runner completes catch-up processors'
);

select is(
  (
    select status
    from public.scheduled_job_runs
    where job_name = 'phase14-test'
    order by started_at desc
    limit 1
  ),
  'SUCCEEDED',
  'scheduled operations runner records operational health'
);

insert into public.notifications (
  recipient_id,
  notification_type,
  title,
  body,
  deduplication_key
)
values (
  '00000000-0000-0000-0000-000000014002',
  'ACCOUNT_DETAINED',
  'Account detained',
  'Operational notification is not quiet-hour suppressed.',
  'phase14-no-quiet-hours'
)
on conflict (recipient_id, deduplication_key) do nothing;

select ok(
  exists (
    select 1
    from public.notifications
    where deduplication_key = 'phase14-no-quiet-hours'
  ),
  'operational notifications are durable without app quiet-hour suppression'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000014003', true);

select is(
  (
    select count(*)::integer
    from public.list_my_notifications(50)
  ),
  0,
  'users cannot list another user notifications'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000014002', true);

select is(
  (
    select count(*)::integer
    from public.list_my_notifications(50)
  ) > 0,
  true,
  'users can list own in-app notifications'
);

select is(
  (
    select public.mark_notification_read(id)
    from public.notifications
    where deduplication_key = 'phase14-no-quiet-hours'
  ),
  true,
  'user can mark own notification read'
);

select *
from finish();

rollback;
