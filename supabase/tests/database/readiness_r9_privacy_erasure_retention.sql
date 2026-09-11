begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

select has_function('public', 'request_my_account_erasure', array['text'], 'self-service erasure request RPC exists');
select has_function('public', 'my_account_erasure_requests', array['integer'], 'own erasure status RPC exists');
select has_function('public', 'verify_account_erasure_request', array['uuid', 'boolean', 'text'], 'erasure verification RPC exists');
select has_function('public', 'fulfill_due_erasure_requests', array['integer'], 'erasure fulfillment RPC exists');
select has_table('public', 'profile_photo_deletion_tasks', 'photo deletion task table exists');

insert into auth.users (id, aud, role, phone, encrypted_password, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000019001', 'authenticated', 'authenticated', '+919876559001', crypt('worker-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000019002', 'authenticated', 'authenticated', '+919876559002', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000019003', 'authenticated', 'authenticated', '+919876559003', crypt('super-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000019004', 'authenticated', 'authenticated', '+919876559004', crypt('other-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

select set_config('app.bypass_identity_protection', 'on', true);

insert into public.profiles (id, worker_number, role, full_name, initials, phone_e164, profile_photo_path, profile_completed_at, account_status)
values
  ('00000000-0000-0000-0000-000000019001', nextval('public.worker_number_seq'), 'WORKER', 'Worker Nineteen', 'WN', '+919876559001', '00000000-0000-0000-0000-000000019001/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000019002', null, 'ADMIN', 'Admin Nineteen', 'AN', '+919876559002', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000019003', null, 'SUPER_ADMIN', 'Super Nineteen', 'SN', '+919876559003', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000019004', nextval('public.worker_number_seq'), 'WORKER', 'Other Nineteen', 'ON', '+919876559004', '00000000-0000-0000-0000-000000019004/profile.webp', now(), 'ACTIVE');

insert into public.worker_profiles (user_id, category, last_worker_category, date_of_birth, address, native_place, height_cm, education_status, has_previous_experience)
values
  ('00000000-0000-0000-0000-000000019001', 'F', 'F', (current_date - interval '22 years')::date, 'Pune Address', 'Pune', 170, 'College', true),
  ('00000000-0000-0000-0000-000000019004', 'F', 'F', (current_date - interval '22 years')::date, 'Other Address', 'Pune', 171, 'College', false);

insert into public.device_tokens (user_id, token, token_hash, platform, app_environment)
values ('00000000-0000-0000-0000-000000019001', 'r9-active-token', encode(extensions.digest('r9-active-token', 'sha256'), 'hex'), 'android', 'local');

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000019001', true);

select lives_ok(
  $$ select public.request_my_account_erasure('Please delete my account after verification') $$,
  'worker can submit own erasure request for verification'
);

select is(
  (select verification_status from public.my_account_erasure_requests(5) limit 1),
  'PENDING_VERIFICATION',
  'self-service request is visible as pending verification'
);

select is(
  (select account_status from public.profiles where id = '00000000-0000-0000-0000-000000019001'),
  'ACTIVE'::public.account_status,
  'self-service request does not immediately disable account access'
);

select throws_ok(
  $$ select public.request_my_account_erasure('Duplicate request') $$,
  'P0001',
  'an erasure request is already open for this account',
  'duplicate open self-service request is rejected'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000019004', true);

select throws_ok(
  $$ select public.verify_account_erasure_request((select id from public.account_erasure_requests where target_user_id = '00000000-0000-0000-0000-000000019001'), true, 'verified') $$,
  'P0001',
  'only Admin or Super Admin can verify erasure requests',
  'worker cannot verify erasure request'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000019002', true);

select is(
  (select public.verify_account_erasure_request((select id from public.account_erasure_requests where target_user_id = '00000000-0000-0000-0000-000000019001'), true, 'verified phone owner')),
  'VERIFIED',
  'Admin can mark request verified after identity check'
);

update public.account_erasure_requests
set due_at = now() - interval '1 minute'
where target_user_id = '00000000-0000-0000-0000-000000019001';

select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::integer from public.fulfill_due_erasure_requests(10)),
  1,
  'service role can fulfill verified due erasure request'
);

select is(
  (select full_name from public.profiles where id = '00000000-0000-0000-0000-000000019001') like 'Erased User%',
  true,
  'fulfillment pseudonymizes current profile name'
);

select is(
  (select profile_photo_path is null from public.profiles where id = '00000000-0000-0000-0000-000000019001'),
  true,
  'fulfillment clears current private profile photo reference'
);

select is(
  (select active from public.device_tokens where token = 'r9-active-token'),
  false,
  'fulfillment invalidates active device tokens'
);

select is(
  (select count(*)::integer from public.profile_photo_deletion_tasks where user_id = '00000000-0000-0000-0000-000000019001' and state = 'PENDING'),
  1,
  'fulfillment queues private photo object deletion task'
);

select is(
  (select public.complete_profile_photo_deletion_task(id, true, null) from public.profile_photo_deletion_tasks where user_id = '00000000-0000-0000-0000-000000019001'),
  'COMPLETED',
  'trusted photo cleanup can mark storage deletion task complete'
);

select is(
  (select status from public.account_erasure_requests where target_user_id = '00000000-0000-0000-0000-000000019001'),
  'COMPLETED',
  'erasure request is completed after fulfillment'
);

select is(
  (select count(*)::integer from public.fulfill_due_erasure_requests(10)),
  0,
  'fulfillment is retry-safe and skips already completed requests'
);

select ok(
  not has_table_privilege('authenticated', 'public.profile_photo_deletion_tasks', 'INSERT'),
  'authenticated users cannot directly create photo deletion tasks'
);

select * from finish();
rollback;
