begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

select has_function('private', 'enqueue_event_leader_notifications', array['uuid'], 'leader notification helper exists');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000012001', 'authenticated', 'authenticated', 'r12-admin@example.test', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000012002', 'authenticated', 'authenticated', 'r12-captain@example.test', crypt('captain-password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now());

select set_config('app.bypass_identity_protection', 'on', true);

insert into public.profiles (id, worker_number, role, full_name, initials, phone_e164, profile_photo_path, profile_completed_at, account_status)
values
  ('00000000-0000-0000-0000-000000012001', null, 'SUPER_ADMIN', 'R12 Admin', 'RA', '+919876512001', null, now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000012002', null, 'CAPTAIN', 'R12 Captain', 'RC', '+919876512002', null, now(), 'ACTIVE');

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012001', true);

insert into public.events (
  id, title, event_type, venue_name, event_date, reporting_at, work_starts_at,
  expected_ends_at, required_worker_count, daily_wage, currency_code,
  event_status, recruitment_status, tier_strategy, created_by, updated_by
)
values (
  '00000000-0000-0000-0000-000000012101', 'R12 Leader Event', 'Wedding', 'Pune', current_date + 1,
  now() + interval '1 day', now() + interval '1 day 1 hour', now() + interval '1 day 8 hours',
  10, 1000, 'INR', 'DRAFT', 'NOT_OPEN', 'STANDARD',
  '00000000-0000-0000-0000-000000012001', '00000000-0000-0000-0000-000000012001'
);

insert into public.event_leaders (event_id, user_id, leader_role, assigned_by)
values ('00000000-0000-0000-0000-000000012101', '00000000-0000-0000-0000-000000012002', 'CAPTAIN', '00000000-0000-0000-0000-000000012001');

select is(
  (select count(*)::integer from public.notifications where recipient_id = '00000000-0000-0000-0000-000000012002'),
  0,
  'draft leader assignment waits until publish before notifying'
);

update public.events
set event_status = 'PUBLISHED', published_at = now()
where id = '00000000-0000-0000-0000-000000012101';

select is(
  (select count(*)::integer from public.notifications where recipient_id = '00000000-0000-0000-0000-000000012002' and notification_type = 'CAPTAIN_ASSIGNED'),
  1,
  'publishing an assigned event creates a Captain notification'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000012002', true);
select lives_ok(
  $$ select public.register_device_token('r12-captain-token', 'android', 'r12-phone', 'development') $$,
  'Captain can register a device token'
);

select is(
  (
    select count(*)::integer
    from public.notification_deliveries nd
    join public.notifications n on n.id = nd.notification_id
    where n.recipient_id = '00000000-0000-0000-0000-000000012002'
      and nd.state = 'PENDING'
  ),
  1,
  'existing leader notification is queued for FCM delivery when token is registered'
);

select * from finish();
rollback;

