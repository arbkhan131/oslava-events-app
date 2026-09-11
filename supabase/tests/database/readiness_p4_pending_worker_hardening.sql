BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);

SELECT has_function(
  'public',
  'register_device_token',
  ARRAY['text','text','text','text'],
  'device-token registration RPC exists'
);

SELECT has_function(
  'public',
  'claim_notification_deliveries',
  ARRAY['text','integer'],
  'notification delivery claim RPC exists'
);

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at
)
VALUES
  ('00000000-0000-0000-0000-000000024001', 'authenticated', 'authenticated', 'p4-active@example.test', crypt('password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000024002', 'authenticated', 'authenticated', 'p4-pending@example.test', crypt('password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000024003', 'authenticated', 'authenticated', 'p4-rejected@example.test', crypt('password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now());

SELECT set_config('app.bypass_identity_protection', 'on', true);

INSERT INTO public.profiles (id, worker_number, role, full_name, initials, phone_e164, account_status, profile_completed_at, profile_photo_path)
VALUES
  ('00000000-0000-0000-0000-000000024001', 24001, 'WORKER', 'P4 Active Worker', 'PA', '+919876524001', 'ACTIVE', now(), '00000000-0000-0000-0000-000000024001/profile.jpg'),
  ('00000000-0000-0000-0000-000000024002', 24002, 'WORKER', 'P4 Pending Worker', 'PP', '+919876524002', 'PENDING_APPROVAL', now(), '00000000-0000-0000-0000-000000024002/profile.jpg'),
  ('00000000-0000-0000-0000-000000024003', 24003, 'WORKER', 'P4 Rejected Worker', 'PR', '+919876524003', 'REJECTED', now(), '00000000-0000-0000-0000-000000024003/profile.jpg');

INSERT INTO public.worker_profiles (
  user_id, category, last_worker_category, date_of_birth, address, native_place,
  height_cm, education_status, has_previous_experience, registration_type,
  requested_category, id_card_file_path, experience_level
)
VALUES
  ('00000000-0000-0000-0000-000000024001', 'F', 'F', current_date - interval '20 years', 'Town', 'Town', 170, 'College', false, 'NEW_WORKER', null, '00000000-0000-0000-0000-000000024001/id.pdf', 'NO_EXPERIENCE'),
  ('00000000-0000-0000-0000-000000024002', 'F', 'F', current_date - interval '20 years', 'Town', 'Town', 170, 'College', false, 'NEW_WORKER', null, '00000000-0000-0000-0000-000000024002/id.pdf', 'NO_EXPERIENCE'),
  ('00000000-0000-0000-0000-000000024003', 'F', 'F', current_date - interval '20 years', 'Town', 'Town', 170, 'College', false, 'NEW_WORKER', null, '00000000-0000-0000-0000-000000024003/id.pdf', 'NO_EXPERIENCE');

SELECT set_config('app.bypass_identity_protection', 'off', true);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000024002', true);

SELECT throws_ok(
  $$SELECT public.register_device_token('pending-token', 'android', 'pending-device', 'development')$$,
  'P0001',
  'only active accounts can register device tokens',
  'pending worker cannot register a push token'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000024003', true);

SELECT throws_ok(
  $$SELECT public.register_device_token('rejected-token', 'android', 'rejected-device', 'development')$$,
  'P0001',
  'only active accounts can register device tokens',
  'rejected worker cannot register a push token'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000024001', true);

SELECT lives_ok(
  $$SELECT public.register_device_token('active-token', 'android', 'active-device', 'development')$$,
  'active worker can register a push token'
);

SELECT is(
  (SELECT count(*)::integer FROM public.device_tokens WHERE user_id = '00000000-0000-0000-0000-000000024001' AND active),
  1,
  'active worker has one active token'
);

INSERT INTO public.device_tokens (id, user_id, token_hash, token, platform, app_environment, active)
VALUES (
  '00000000-0000-0000-0000-000000024101',
  '00000000-0000-0000-0000-000000024002',
  encode(extensions.digest('forced-pending-token', 'sha256'), 'hex'),
  'forced-pending-token',
  'android',
  'development',
  true
);

INSERT INTO public.notifications (id, recipient_id, notification_type, title, body, deduplication_key)
VALUES (
  '00000000-0000-0000-0000-000000024201',
  '00000000-0000-0000-0000-000000024002',
  'TIER_OPENED',
  'Should not send',
  'Pending users should not receive push deliveries',
  'p4-pending-notification'
);

SELECT is(
  (SELECT count(*)::integer FROM public.notification_deliveries WHERE notification_id = '00000000-0000-0000-0000-000000024201'),
  0,
  'pending worker notification does not enqueue push delivery even with a stale active token'
);

INSERT INTO public.notification_deliveries (id, notification_id, device_token_id, channel, state, next_attempt_at)
VALUES (
  '00000000-0000-0000-0000-000000024301',
  '00000000-0000-0000-0000-000000024201',
  '00000000-0000-0000-0000-000000024101',
  'fcm',
  'PENDING',
  now() - interval '1 minute'
);

SELECT is(
  (SELECT count(*)::integer FROM public.claim_notification_deliveries('p4-test-worker', 10)),
  0,
  'stale pending-worker delivery is not claimed by dispatcher'
);

SELECT set_config('app.bypass_identity_protection', 'on', true);
UPDATE public.profiles
SET account_status = 'DETAINED'
WHERE id = '00000000-0000-0000-0000-000000024001';
SELECT set_config('app.bypass_identity_protection', 'off', true);

SELECT is(
  (SELECT count(*)::integer FROM public.device_tokens WHERE user_id = '00000000-0000-0000-0000-000000024001' AND active),
  0,
  'tokens are deactivated when an account becomes non-active'
);

SELECT * FROM finish();
ROLLBACK;
