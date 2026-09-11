BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

SELECT has_function('public', 'phone_auth_email', ARRAY['text'], 'public phone auth email helper exists');
SELECT has_function(
  'public',
  'complete_phone_worker_registration',
  ARRAY['text','text','text','text','date','text','numeric','text','public.worker_experience_level','public.worker_registration_type','public.worker_category','text'],
  'phone worker registration RPC exists'
);
SELECT has_function(
  'public',
  'review_worker_registration',
  ARRAY['uuid','boolean','public.worker_category','text'],
  'registration review RPC exists'
);

SELECT is(
  public.phone_auth_email('+91 98765 51001'),
  '919876551001@phone.oslava.local',
  'phone auth email normalizes India-style phone input'
);

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous, created_at, updated_at
)
VALUES
  ('00000000-0000-0000-0000-000000021001', 'authenticated', 'authenticated', 'p1-super@example.test', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000021002', 'authenticated', 'authenticated', 'p1-captain@example.test', crypt('captain-password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000021101', 'authenticated', 'authenticated', '919876551101@phone.oslava.local', crypt('worker-password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000021102', 'authenticated', 'authenticated', '919876551102@phone.oslava.local', crypt('worker-password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000021103', 'authenticated', 'authenticated', '919876551103@phone.oslava.local', crypt('worker-password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', false, false, now(), now());

SELECT set_config('app.bypass_identity_protection', 'on', true);

INSERT INTO public.profiles (id, worker_number, role, full_name, initials, phone_e164, account_status, profile_completed_at, profile_photo_path)
VALUES
  ('00000000-0000-0000-0000-000000021001', null, 'SUPER_ADMIN', 'P1 Super', 'PS', '+919876521001', 'ACTIVE', now(), '00000000-0000-0000-0000-000000021001/profile.jpg'),
  ('00000000-0000-0000-0000-000000021002', null, 'CAPTAIN', 'P1 Captain', 'PC', '+919876521002', 'ACTIVE', now(), '00000000-0000-0000-0000-000000021002/profile.jpg');

SELECT set_config('app.bypass_identity_protection', 'off', true);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021101', true);

SELECT lives_ok(
  $$
    SELECT * FROM public.complete_phone_worker_registration(
      full_name := 'Muhammed Siyas K C',
      phone_e164 := '+91 98765 51101',
      profile_photo_path := '00000000-0000-0000-0000-000000021101/profile.jpg',
      id_card_file_path := '00000000-0000-0000-0000-000000021101/aadhaar.pdf',
      date_of_birth := (current_date - interval '20 years')::date,
      native_place := 'Kozhikode',
      height_cm := 172,
      education_status := 'BSc Physics',
      experience_level := 'NO_EXPERIENCE'::public.worker_experience_level,
      registration_type := 'NEW_WORKER'::public.worker_registration_type,
      p_requested_category := null::public.worker_category,
      privacy_terms_version := 'v1.0'
    )
  $$,
  'new worker phone registration completes as pending'
);

SELECT is(
  (SELECT account_status FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000021101'),
  'PENDING_APPROVAL'::public.account_status,
  'registered worker starts pending approval'
);

SELECT is(
  (SELECT category FROM public.worker_profiles WHERE user_id = '00000000-0000-0000-0000-000000021101'),
  'F'::public.worker_category,
  'new worker defaults to F category'
);

SELECT is(
  (SELECT requested_category FROM public.worker_profiles WHERE user_id = '00000000-0000-0000-0000-000000021101'),
  null::public.worker_category,
  'new worker does not store a requested category'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021103', true);

SELECT throws_ok(
  $$
    SELECT * FROM public.complete_phone_worker_registration(
      full_name := 'New Worker With Category',
      phone_e164 := '+919876551103',
      profile_photo_path := '00000000-0000-0000-0000-000000021103/profile.jpg',
      id_card_file_path := '00000000-0000-0000-0000-000000021103/id.pdf',
      date_of_birth := (current_date - interval '20 years')::date,
      native_place := 'Kannur',
      height_cm := 170,
      education_status := '12th class',
      experience_level := 'SOME_EXPERIENCE'::public.worker_experience_level,
      registration_type := 'NEW_WORKER'::public.worker_registration_type,
      p_requested_category := 'A'::public.worker_category,
      privacy_terms_version := 'v1.0'
    )
  $$,
  'P0001',
  'new worker category is assigned during approval',
  'new worker cannot request a category'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021102', true);

SELECT lives_ok(
  $$
    SELECT * FROM public.complete_phone_worker_registration(
      full_name := 'Old Worker One',
      phone_e164 := '+919876551102',
      profile_photo_path := '00000000-0000-0000-0000-000000021102/profile.png',
      id_card_file_path := '00000000-0000-0000-0000-000000021102/id-card.png',
      date_of_birth := (current_date - interval '24 years')::date,
      native_place := 'Malappuram',
      height_cm := 176,
      education_status := '12th class',
      experience_level := 'HIGHLY_EXPERIENCED'::public.worker_experience_level,
      registration_type := 'OLD_WORKER'::public.worker_registration_type,
      p_requested_category := 'B'::public.worker_category,
      privacy_terms_version := 'v1.0'
    )
  $$,
  'old worker can request category while pending'
);

SELECT is(
  (SELECT requested_category FROM public.worker_profiles WHERE user_id = '00000000-0000-0000-0000-000000021102'),
  'B'::public.worker_category,
  'old worker requested category is stored'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021101', true);

INSERT INTO public.events (
  id, title, event_type, venue_name, event_date, reporting_at, work_starts_at,
  expected_ends_at, required_worker_count, daily_wage, currency_code,
  event_status, recruitment_status, tier_strategy, published_at, created_by, updated_by
)
VALUES (
  '00000000-0000-0000-0000-000000021901', 'P1 Pending Hidden Event', 'Wedding', 'Venue', current_date + 1,
  now() + interval '1 day', now() + interval '1 day 1 hour', now() + interval '1 day 8 hours',
  10, 1000, 'INR', 'PUBLISHED', 'OPEN', 'STANDARD', now(),
  '00000000-0000-0000-0000-000000021001', '00000000-0000-0000-0000-000000021001'
);
INSERT INTO public.event_tier_release_rules (event_id, category, release_offset_minutes, opens_at, source_strategy)
VALUES ('00000000-0000-0000-0000-000000021901', 'F', 0, now() - interval '1 minute', 'STANDARD');

SELECT is(
  (SELECT count(*)::integer FROM public.worker_event_board()),
  0,
  'pending worker cannot see worker event board'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021002', true);

SELECT is(
  (SELECT account_status FROM public.review_worker_registration('00000000-0000-0000-0000-000000021101', true, null, 'Looks good')),
  'ACTIVE'::public.account_status,
  'Captain can approve pending worker'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021101', true);

SELECT is(
  (SELECT count(*)::integer FROM public.worker_event_board()),
  1,
  'approved worker can see worker event board'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021002', true);

SELECT is(
  (SELECT account_status FROM public.review_worker_registration('00000000-0000-0000-0000-000000021102', false, null, 'Not accepted')),
  'REJECTED'::public.account_status,
  'Captain can reject pending worker'
);

SELECT * FROM finish();
ROLLBACK;


