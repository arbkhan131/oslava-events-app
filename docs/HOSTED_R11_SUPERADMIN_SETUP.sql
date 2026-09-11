-- R11 hosted superadmin profile setup
-- First create the Auth user in Supabase Dashboard > Authentication > Users:
--   email: arbkh.03.11@gmail.com
--   password: 123456
--   mark/auto-confirm the user.
-- Then run this SQL in the hosted project's SQL editor.

begin;

select set_config('app.bypass_identity_protection', 'on', true);

do $$
declare
  super_id uuid;
begin
  select id
  into super_id
  from auth.users
  where lower(email) = 'arbkh.03.11@gmail.com'
  limit 1;

  if super_id is null then
    raise exception 'Auth user arbkh.03.11@gmail.com does not exist. Create and confirm it in Authentication > Users first.';
  end if;

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
  ) values (
    super_id,
    null,
    'SUPER_ADMIN',
    'Oslava Super Admin',
    'SA',
    '+918864938636',
    null,
    now(),
    'ACTIVE'
  )
  on conflict (id) do update
  set role = excluded.role,
      full_name = excluded.full_name,
      initials = excluded.initials,
      phone_e164 = excluded.phone_e164,
      account_status = excluded.account_status,
      profile_completed_at = coalesce(public.profiles.profile_completed_at, excluded.profile_completed_at);

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason
  ) values (
    super_id,
    null,
    'SUPER_ADMIN',
    super_id,
    'SUPER_ADMIN',
    'R11 hosted bootstrap requested for staging tester login'
  )
  on conflict do nothing;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    after_values,
    reason,
    source
  ) values (
    super_id,
    'SUPER_ADMIN',
    'hosted_super_admin_bootstrapped',
    'profile',
    super_id,
    jsonb_build_object(
      'email', 'arbkh.03.11@gmail.com',
      'role', 'SUPER_ADMIN',
      'phone_e164', '+918864938636',
      'account_status', 'ACTIVE'
    ),
    'R11 hosted bootstrap requested for staging tester login',
    'manual_sql'
  );
end $$;

select set_config('app.bypass_identity_protection', 'off', true);

commit;
