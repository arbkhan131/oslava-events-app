-- Run this only against the hosted staging project after all migrations are applied.
-- It does not create passwords or Auth credentials. First create/confirm the
-- Supabase Auth phone user for +918864938636 in the Dashboard/Auth Admin flow.

do $$
declare
  target_user_id uuid;
begin
  select id
  into target_user_id
  from auth.users
  where phone in ('918864938636', '+918864938636')
  order by created_at
  limit 1;

  if target_user_id is null then
    raise exception 'Create the Supabase Auth phone user +918864938636 first, then rerun this bootstrap.';
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

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
  values (
    target_user_id,
    null,
    'SUPER_ADMIN',
    'Oslava Super Admin',
    'SA',
    '+918864938636',
    null,
    null,
    'ACTIVE'
  )
  on conflict (id) do update
  set worker_number = null,
      role = 'SUPER_ADMIN',
      full_name = excluded.full_name,
      initials = excluded.initials,
      phone_e164 = excluded.phone_e164,
      profile_photo_path = null,
      profile_completed_at = null,
      account_status = 'ACTIVE';

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason
  )
  values (
    target_user_id,
    null,
    'SUPER_ADMIN',
    target_user_id,
    'SUPER_ADMIN',
    'Approved staging Super Admin bootstrap'
  );

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    after_values,
    reason,
    source
  )
  values (
    target_user_id,
    'SUPER_ADMIN',
    'staging_super_admin_bootstrapped',
    'profile',
    target_user_id,
    jsonb_build_object(
      'role', 'SUPER_ADMIN',
      'phone_e164', '+918864938636',
      'account_status', 'ACTIVE'
    ),
    'Approved staging Super Admin bootstrap',
    'manual_sql'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);
exception
  when others then
    perform set_config('app.bypass_identity_protection', 'off', true);
    raise;
end
$$;
