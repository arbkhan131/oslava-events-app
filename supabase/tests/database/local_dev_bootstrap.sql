begin;

select plan(17);

select is(
  (
    select count(*)::integer
    from auth.users
    where phone like '91900000000%'
      and raw_user_meta_data ->> 'local_dev' = 'true'
  ),
  8,
  'local development bootstrap creates eight real auth users'
);

select is(
  (
    select count(*)::integer
    from auth.identities
    where provider = 'phone'
      and provider_id like '91900000000%'
  ),
  8,
  'local development bootstrap creates phone auth identities'
);

select is(
  (
    select count(*)::integer
    from public.profiles
    where phone_e164 like '+91900000000%'
      and account_status = 'ACTIVE'
  ),
  8,
  'all local development profiles are active'
);

select is(
  (
    select role::text
    from public.profiles
    where phone_e164 = '+919000000001'
  ),
  'SUPER_ADMIN',
  'local super admin has SUPER_ADMIN role'
);

select is(
  (
    select role::text
    from public.profiles
    where phone_e164 = '+919000000002'
  ),
  'ADMIN',
  'local admin has ADMIN role'
);

select is(
  (
    select role::text
    from public.profiles
    where phone_e164 = '+919000000003'
  ),
  'CAPTAIN',
  'local captain has CAPTAIN role'
);

select is(
  (
    select role::text
    from public.profiles
    where phone_e164 = '+919000000004'
  ),
  'SUPERVISOR',
  'local supervisor has SUPERVISOR role'
);

select is(
  (
    select wp.category::text
    from public.worker_profiles wp
    join public.profiles p on p.id = wp.user_id
    where p.phone_e164 = '+919000000005'
  ),
  'F',
  'local worker F has category F'
);

select is(
  (
    select wp.category::text
    from public.worker_profiles wp
    join public.profiles p on p.id = wp.user_id
    where p.phone_e164 = '+919000000006'
  ),
  'C',
  'local worker C has category C'
);

select is(
  (
    select wp.category::text
    from public.worker_profiles wp
    join public.profiles p on p.id = wp.user_id
    where p.phone_e164 = '+919000000007'
  ),
  'B',
  'local worker B has category B'
);

select is(
  (
    select wp.category::text
    from public.worker_profiles wp
    join public.profiles p on p.id = wp.user_id
    where p.phone_e164 = '+919000000008'
  ),
  'A',
  'local worker A has category A'
);

select is(
  (
    select count(*)::integer
    from public.profiles p
    join public.worker_profiles wp on wp.user_id = p.id
    where p.role = 'WORKER'
      and p.phone_e164 like '+91900000000%'
      and p.worker_number is not null
      and p.profile_completed_at is not null
      and p.profile_photo_path is not null
      and wp.date_of_birth <= current_date - interval '18 years'
      and btrim(wp.address) <> ''
      and btrim(wp.native_place) <> ''
      and btrim(wp.education_status) <> ''
  ),
  4,
  'local worker profiles satisfy current completeness gates'
);

select is(
  (
    select count(*)::integer
    from storage.objects o
    join public.profiles p on p.profile_photo_path = o.name
    where o.bucket_id = 'profile-photos'
      and o.owner = p.id
      and p.phone_e164 like '+91900000000%'
      and p.role = 'WORKER'
  ),
  4,
  'local worker profile-photo fixtures are private bucket objects'
);

select is(
  (
    select count(*)::integer
    from public.role_history
    where reason = 'Local development bootstrap'
      and user_id in (
        '10000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000003',
        '10000000-0000-0000-0000-000000000004'
      )
  ),
  4,
  'local staff bootstrap is represented in role history'
);

select is(
  (
    select count(*)::integer
    from public.worker_category_history
    where reason = 'Local development bootstrap'
      and worker_id in (
        '10000000-0000-0000-0000-000000000005',
        '10000000-0000-0000-0000-000000000006',
        '10000000-0000-0000-0000-000000000007',
        '10000000-0000-0000-0000-000000000008'
      )
  ),
  4,
  'local worker categories are represented in category history'
);

select isnt(
  (
    select current_setting('app.settings.jwt_secret', true)
  ),
  '',
  'local seed guard can read the Supabase JWT secret setting'
);

select is(
  (
    select current_setting('app.settings.jwt_secret', true)
  ),
  'super-secret-jwt-token-with-at-least-32-characters-long',
  'local seed guard is tied to Supabase CLI local stack'
);

select * from finish();

rollback;
