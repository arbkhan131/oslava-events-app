begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

select has_table('public', 'privacy_terms_versions', 'privacy terms versions table exists');
select has_table('public', 'privacy_terms_acceptances', 'privacy terms acceptances table exists');
select has_table('public', 'account_erasure_requests', 'account erasure request table exists');
select has_table('public', 'retention_cleanup_runs', 'retention cleanup run table exists');
select has_table('public', 'audit_log_legal_holds', 'audit log legal holds table exists');
select has_function('public', 'run_retention_cleanup', array['boolean'], 'retention cleanup RPC exists');

select is(public.active_privacy_terms_version(), 'v1.0', 'active privacy terms version is v1.0');

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
  ('00000000-0000-0000-0000-000000016001', 'authenticated', 'authenticated', '+919876556001', crypt('worker-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000016002', 'authenticated', 'authenticated', '+919876556002', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000016003', 'authenticated', 'authenticated', '+919876556003', crypt('other-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000016004', 'authenticated', 'authenticated', '+919876556004', crypt('new-worker-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000016001', nextval('public.worker_number_seq'), 'WORKER', 'Worker Sixteen', 'WS', '+919876556001', '00000000-0000-0000-0000-000000016001/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000016002', null, 'ADMIN', 'Admin Sixteen', 'AS', '+919876556002', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000016003', nextval('public.worker_number_seq'), 'WORKER', 'Other Sixteen', 'OS', '+919876556003', '00000000-0000-0000-0000-000000016003/profile.webp', now(), 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000016001', 'F', 'F', (current_date - interval '22 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000016003', 'F', 'F', (current_date - interval '22 years')::date, 'Pune', 'Pune', 170, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000016004', true);

select throws_ok(
  $$
    select *
    from public.complete_worker_registration(
      'New Worker',
      'NW',
      '00000000-0000-0000-0000-000000016004/profile.webp',
      (current_date - interval '20 years')::date,
      'Pune',
      'Pune',
      170,
      'College',
      false,
      null,
      null
    )
  $$,
  'P0001',
  'current privacy terms acknowledgement is required',
  'Worker registration rejects missing privacy terms acknowledgement'
);

select lives_ok(
  $$
    select *
    from public.complete_worker_registration(
      'New Worker',
      'NW',
      '00000000-0000-0000-0000-000000016004/profile.webp',
      (current_date - interval '20 years')::date,
      'Pune',
      'Pune',
      170,
      'College',
      false,
      null,
      'v1.0'
    )
  $$,
  'Worker registration accepts current privacy terms acknowledgement'
);

select ok(
  exists (
    select 1
    from public.privacy_terms_acceptances
    where user_id = '00000000-0000-0000-0000-000000016004'
      and version = 'v1.0'
  ),
  'privacy terms acceptance is recorded with user and version'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000016001', true);

select throws_ok(
  $$ select public.request_account_erasure('00000000-0000-0000-0000-000000016001', 'Verified request') $$,
  'P0001',
  'only Admin or Super Admin can record erasure requests',
  'Worker cannot record erasure request directly'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000016002', true);

select lives_ok(
  $$ select public.request_account_erasure('00000000-0000-0000-0000-000000016001', 'Verified request') $$,
  'Admin can record account erasure request after verification'
);

select is(
  (
    select account_status
    from public.profiles
    where id = '00000000-0000-0000-0000-000000016001'
  ),
  'INACTIVE'::public.account_status,
  'erasure request disables access by setting account INACTIVE'
);

select ok(
  exists (
    select 1
    from public.audit_logs
    where action = 'account_erasure_requested'
      and entity_id = '00000000-0000-0000-0000-000000016001'
  ),
  'erasure request writes audit record'
);

insert into public.notifications (
  id,
  recipient_id,
  notification_type,
  title,
  body,
  deduplication_key,
  created_at
)
values (
  '00000000-0000-0000-0000-000000016101',
  '00000000-0000-0000-0000-000000016003',
  'NEW_EVENT',
  'Old notification',
  'Expired',
  'phase16-expired-notification',
  now() - interval '181 days'
);

insert into public.device_tokens (
  id,
  user_id,
  token,
  token_hash,
  platform,
  app_environment,
  active,
  invalidated_at,
  created_at,
  updated_at
)
values (
  '00000000-0000-0000-0000-000000016201',
  '00000000-0000-0000-0000-000000016003',
  'expired-token',
  encode(extensions.digest('expired-token', 'sha256'), 'hex'),
  'android',
  'local',
  false,
  now() - interval '2 days',
  now() - interval '10 days',
  now() - interval '2 days'
);

insert into public.notification_deliveries (
  id,
  notification_id,
  device_token_id,
  state,
  sent_at,
  created_at
)
values (
  '00000000-0000-0000-0000-000000016301',
  '00000000-0000-0000-0000-000000016101',
  '00000000-0000-0000-0000-000000016201',
  'SENT',
  now() - interval '91 days',
  now() - interval '100 days'
);

insert into public.audit_logs (
  id,
  actor_id,
  actor_role,
  action,
  entity_type,
  entity_id,
  after_values,
  source,
  created_at
)
values (
  '00000000-0000-0000-0000-000000016401',
  '00000000-0000-0000-0000-000000016002',
  'ADMIN',
  'phase16_expired_audit_fixture',
  'test',
  '00000000-0000-0000-0000-000000016401',
  '{}'::jsonb,
  'database',
  now() - interval '3 years 1 day'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000016003', true);

select throws_ok(
  $$ select * from public.run_retention_cleanup(true) $$,
  'P0001',
  'only Super Admin or service role can run retention cleanup',
  'non-Super-Admin user cannot run retention cleanup'
);

select set_config('request.jwt.claim.sub', '', true);

select is(
  (
    select notifications_expired
    from public.run_retention_cleanup(true)
  ),
  1,
  'retention dry run counts expired notifications'
);

select is(
  (
    select audit_logs_expired
    from public.run_retention_cleanup(true)
  ),
  1,
  'retention dry run counts expired audit logs without legal hold'
);

select is(
  (
    select invalid_tokens_removed
    from public.run_retention_cleanup(false)
  ),
  1,
  'retention cleanup removes invalid tokens when not dry run'
);

select is(
  (
    select count(*)::integer
    from public.device_tokens
    where token = 'expired-token'
  ),
  0,
  'invalid device token is deleted by retention cleanup'
);

select is(
  (
    select count(*)::integer
    from public.audit_logs
    where id = '00000000-0000-0000-0000-000000016401'
  ),
  0,
  'expired audit log without legal hold is deleted only by retention cleanup'
);

select ok(
  not has_table_privilege('authenticated', 'public.retention_cleanup_runs', 'INSERT'),
  'authenticated users cannot directly insert retention run records'
);

select ok(
  not has_table_privilege('authenticated', 'public.privacy_terms_acceptances', 'INSERT'),
  'authenticated users cannot directly forge privacy terms acceptance rows'
);

select throws_ok(
  $$
    update public.audit_logs
    set reason = 'tamper'
    where action = 'account_erasure_requested'
  $$,
  'P0001',
  'audit_logs are append-only',
  'audit logs remain immutable during hardening'
);

select *
from finish();

rollback;
