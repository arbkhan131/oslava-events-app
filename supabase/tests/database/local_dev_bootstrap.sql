begin;

select plan(8);

select is(
  (
    select count(*)::integer
    from auth.users
    where phone = '918864938636'
      and raw_user_meta_data ->> 'local_dev' = 'true'
  ),
  1,
  'local bootstrap creates one real auth user for the approved Super Admin'
);

select is(
  (
    select count(*)::integer
    from auth.users
    where raw_user_meta_data ->> 'local_dev' = 'true'
  ),
  1,
  'local bootstrap does not create temporary Admin/Captain/Supervisor/Worker credentials'
);

select is(
  (
    select count(*)::integer
    from auth.identities
    where provider = 'email'
      and identity_data ->> 'email' = 'arbkh.03.11@gmail.com'
  ),
  1,
  'local bootstrap creates an email auth identity for the Super Admin'
);

select is(
  (
    select role::text
    from public.profiles
    where phone_e164 = '+918864938636'
      and account_status = 'ACTIVE'
  ),
  'SUPER_ADMIN',
  'approved phone has ACTIVE SUPER_ADMIN profile'
);

select is(
  (
    select count(*)::integer
    from public.worker_profiles wp
    join public.profiles p on p.id = wp.user_id
    where p.phone_e164 = '+918864938636'
  ),
  0,
  'Super Admin bootstrap does not create a Worker profile'
);

select ok(
  exists (
    select 1
    from public.role_history
    where user_id = '10000000-0000-0000-0000-000000000001'
      and new_role = 'SUPER_ADMIN'
      and reason = 'Local development bootstrap'
  ),
  'Super Admin bootstrap is represented in role history'
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

