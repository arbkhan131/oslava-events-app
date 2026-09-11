-- R11: email/password authentication while retaining phone as contact data.

drop function if exists public.complete_worker_registration(
  text,
  text,
  text,
  date,
  text,
  text,
  numeric,
  text,
  boolean,
  text
);

drop function if exists public.complete_worker_registration(
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text,
  numeric,
  text,
  boolean,
  text,
  text
);

create or replace function public.complete_worker_registration(
  full_name text,
  initials text,
  email text,
  phone_e164 text,
  profile_photo_path text,
  date_of_birth date,
  address text,
  native_place text,
  height_cm numeric,
  education_status text,
  has_previous_experience boolean,
  experience_details text default null,
  privacy_terms_version text default null
)
returns table (
  user_id uuid,
  worker_number bigint,
  role public.app_role,
  category public.worker_category,
  account_status public.account_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  auth_user_id uuid := auth.uid();
  auth_email text;
  normalized_phone text;
  issued_worker_number bigint;
  active_terms_version text;
begin
  if auth_user_id is null then
    raise exception 'authentication required';
  end if;

  select public.active_privacy_terms_version()
  into active_terms_version;

  if active_terms_version is null then
    raise exception 'active privacy terms version is required';
  end if;

  if privacy_terms_version is null
     or btrim(privacy_terms_version) <> active_terms_version then
    raise exception 'current privacy terms acknowledgement is required';
  end if;

  select email into auth_email
  from auth.users
  where id = auth_user_id;

  if auth_email is null or lower(btrim(auth_email)) <> lower(btrim(email)) then
    raise exception 'email authentication identity is required';
  end if;

  normalized_phone := private.normalize_phone(phone_e164);

  if exists (select 1 from public.profiles where id = auth_user_id) then
    raise exception 'profile already exists';
  end if;

  if not private.is_worker_adult(date_of_birth, current_date) then
    raise exception 'worker must be at least 18 years old';
  end if;

  if not private.profile_photo_path_is_valid(auth_user_id, profile_photo_path) then
    raise exception 'invalid profile photo path';
  end if;

  issued_worker_number := nextval('public.worker_number_seq');

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
    auth_user_id,
    issued_worker_number,
    'WORKER'::public.app_role,
    btrim(full_name),
    btrim(initials),
    normalized_phone,
    profile_photo_path,
    now(),
    'ACTIVE'::public.account_status
  );

  insert into public.privacy_terms_acceptances (
    user_id,
    version,
    accepted_at
  )
  values (
    auth_user_id,
    active_terms_version,
    now()
  );

  insert into public.worker_profiles (
    user_id,
    category,
    last_worker_category,
    date_of_birth,
    address,
    native_place,
    height_cm,
    education_status,
    has_previous_experience,
    experience_details
  )
  values (
    auth_user_id,
    'F'::public.worker_category,
    'F'::public.worker_category,
    date_of_birth,
    btrim(address),
    btrim(native_place),
    height_cm,
    btrim(education_status),
    has_previous_experience,
    nullif(btrim(coalesce(experience_details, '')), '')
  );

  insert into public.worker_category_history (
    worker_id,
    old_category,
    new_category,
    action,
    actor_id,
    actor_role,
    reason
  )
  values (
    auth_user_id,
    null,
    'F'::public.worker_category,
    'INITIAL_ASSIGNMENT',
    auth_user_id,
    'WORKER'::public.app_role,
    'Worker registration'
  );

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    after_values,
    source
  )
  values (
    auth_user_id,
    'WORKER'::public.app_role,
    'worker_registration_completed',
    'profile',
    auth_user_id,
    jsonb_build_object(
      'worker_number', issued_worker_number,
      'role', 'WORKER',
      'category', 'F',
      'account_status', 'ACTIVE',
      'privacy_terms_version', active_terms_version
    ),
    'database'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);

  return query
  select
    p.id,
    p.worker_number,
    p.role,
    wp.category,
    p.account_status
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where p.id = auth_user_id;
end;
$$;

create or replace function public.request_account_erasure(
  p_target_user_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  request_id uuid;
  old_profile public.profiles%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can record erasure requests';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_profile
  from public.profiles
  where id = p_target_user_id
  for update;

  if old_profile.id is null then
    raise exception 'profile not found';
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

  update public.profiles
  set account_status = 'INACTIVE'::public.account_status
  where id = p_target_user_id;

  perform set_config('app.bypass_identity_protection', 'off', true);

  insert into public.account_erasure_requests (
    target_user_id,
    requested_by,
    requested_by_role,
    reason
  )
  values (
    p_target_user_id,
    auth.uid(),
    actor_role,
    p_reason
  )
  returning id into request_id;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'account_erasure_requested',
    'profile',
    p_target_user_id,
    to_jsonb(old_profile),
    jsonb_build_object(
      'account_status', 'INACTIVE',
      'erasure_request_id', request_id,
      'due_at', now() + interval '30 days'
    ),
    p_reason,
    'database'
  );

  return request_id;
end;
$$;

create or replace function public.run_retention_cleanup(p_dry_run boolean default true)
returns table (
  run_id uuid,
  notifications_expired integer,
  deliveries_expired integer,
  invalid_tokens_removed integer,
  audit_logs_expired integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  notification_count integer := 0;
  delivery_count integer := 0;
  token_count integer := 0;
  audit_count integer := 0;
  cleanup_id uuid;
begin
  actor_role := private.current_actor_role();

  if auth.uid() is not null and actor_role <> 'SUPER_ADMIN'::public.app_role then
    raise exception 'only Super Admin or service role can run retention cleanup';
  end if;

  select count(*)::integer
  into notification_count
  from public.notifications
  where created_at < now() - interval '180 days';

  select count(*)::integer
  into delivery_count
  from public.notification_deliveries
  where state in ('SENT', 'FAILED', 'SKIPPED')
    and coalesce(sent_at, failed_at, updated_at, created_at)
      < now() - interval '90 days';

  select count(*)::integer
  into token_count
  from public.device_tokens
  where active = false
    and coalesce(invalidated_at, updated_at, created_at)
      < now() - interval '1 day';

  select count(*)::integer
  into audit_count
  from public.audit_logs
  where created_at < now() - interval '3 years'
    and not exists (
      select 1
      from public.audit_log_legal_holds hold
      where hold.audit_log_id = public.audit_logs.id
        and hold.released_at is null
    );

  insert into public.retention_cleanup_runs (
    actor_id,
    actor_role,
    dry_run,
    notifications_expired,
    deliveries_expired,
    invalid_tokens_removed,
    audit_logs_expired,
    completed_at,
    metadata
  )
  values (
    auth.uid(),
    actor_role,
    p_dry_run,
    notification_count,
    delivery_count,
    token_count,
    audit_count,
    now(),
    jsonb_build_object(
      'notifications_retention_days', 180,
      'terminal_delivery_retention_days', 90,
      'audit_retention_years', 3
    )
  )
  returning id into cleanup_id;

  if not p_dry_run then
    delete from public.notification_deliveries
    where state in ('SENT', 'FAILED', 'SKIPPED')
      and coalesce(sent_at, failed_at, updated_at, created_at)
        < now() - interval '90 days';

    delete from public.notifications
    where created_at < now() - interval '180 days';

    delete from public.device_tokens
    where active = false
      and coalesce(invalidated_at, updated_at, created_at)
        < now() - interval '1 day';

    perform set_config('app.allow_retention_audit_delete', 'on', true);

    delete from public.audit_logs
    where created_at < now() - interval '3 years'
      and not exists (
        select 1
        from public.audit_log_legal_holds hold
        where hold.audit_log_id = public.audit_logs.id
          and hold.released_at is null
      );

    perform set_config('app.allow_retention_audit_delete', 'off', true);
  end if;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    after_values,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'retention_cleanup_run',
    'retention_cleanup_run',
    cleanup_id,
    jsonb_build_object(
      'dry_run', p_dry_run,
      'notifications_expired', notification_count,
      'deliveries_expired', delivery_count,
      'invalid_tokens_removed', token_count,
      'audit_logs_expired', audit_count
    ),
    'database'
  );

  return query
  select cleanup_id, notification_count, delivery_count, token_count, audit_count;
end;
$$;

alter table public.privacy_terms_versions enable row level security;
alter table public.privacy_terms_versions force row level security;
alter table public.privacy_terms_acceptances enable row level security;
alter table public.privacy_terms_acceptances force row level security;
alter table public.account_erasure_requests enable row level security;
alter table public.account_erasure_requests force row level security;
alter table public.retention_cleanup_runs enable row level security;
alter table public.retention_cleanup_runs force row level security;
alter table public.audit_log_legal_holds enable row level security;
alter table public.audit_log_legal_holds force row level security;

revoke all on public.privacy_terms_versions from public, anon, authenticated;
revoke all on public.privacy_terms_acceptances from public, anon, authenticated;
revoke all on public.account_erasure_requests from public, anon, authenticated;
revoke all on public.retention_cleanup_runs from public, anon, authenticated;
revoke all on public.audit_log_legal_holds from public, anon, authenticated;

grant select on public.privacy_terms_versions to anon, authenticated;
grant select on public.privacy_terms_acceptances to authenticated;
grant select on public.account_erasure_requests to authenticated;
grant select on public.retention_cleanup_runs to authenticated;
grant select on public.audit_log_legal_holds to authenticated;
grant all on public.privacy_terms_versions to service_role;
grant all on public.privacy_terms_acceptances to service_role;
grant all on public.account_erasure_requests to service_role;
grant all on public.retention_cleanup_runs to service_role;
grant all on public.audit_log_legal_holds to service_role;

revoke all on function public.active_privacy_terms_version() from public;
revoke all on function public.complete_worker_registration(
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text,
  numeric,
  text,
  boolean,
  text,
  text
) from public, anon;
revoke all on function public.request_account_erasure(uuid, text) from public, anon;
revoke all on function public.run_retention_cleanup(boolean) from public, anon, authenticated;

grant execute on function public.active_privacy_terms_version() to anon, authenticated;
grant execute on function public.complete_worker_registration(
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text,
  numeric,
  text,
  boolean,
  text,
  text
) to authenticated;
grant execute on function public.request_account_erasure(uuid, text) to authenticated;
grant execute on function public.run_retention_cleanup(boolean) to authenticated, service_role;



-- Local bootstrap for requested Super Admin test identity. Hosted staging should
-- create the same Auth user/profile with service-role/admin tooling.
do $$
declare
  super_id uuid := '10000000-0000-0000-0000-000000000001';
begin
  if current_setting('app.settings.jwt_secret', true)
     = 'super-secret-jwt-token-with-at-least-32-characters-long' then
    perform set_config('app.bypass_identity_protection', 'on', true);

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, reauthentication_token, raw_app_meta_data,
      raw_user_meta_data, is_super_admin, created_at, updated_at, is_sso_user, is_anonymous
    ) values (
      '00000000-0000-0000-0000-000000000000', super_id, 'authenticated', 'authenticated',
      'arbkh.03.11@gmail.com', extensions.crypt('123456', extensions.gen_salt('bf')), now(),
      '', '', '', '', '', '', '{"provider":"email","providers":["email"]}'::jsonb,
      '{"local_dev":true,"role":"SUPER_ADMIN","full_name":"Oslava Super Admin"}'::jsonb,
      false, now(), now(), false, false
    ) on conflict (id) do update set
      email = excluded.email,
      encrypted_password = excluded.encrypted_password,
      email_confirmed_at = excluded.email_confirmed_at,
      raw_app_meta_data = excluded.raw_app_meta_data,
      raw_user_meta_data = excluded.raw_user_meta_data,
      updated_at = now();

    insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      extensions.gen_random_uuid(), super_id::text, super_id,
      jsonb_build_object('sub', super_id::text, 'email', 'arbkh.03.11@gmail.com', 'email_verified', true),
      'email', now(), now(), now()
    ) on conflict (provider_id, provider) do update set
      user_id = excluded.user_id,
      identity_data = excluded.identity_data,
      updated_at = now();

    insert into public.profiles (id, worker_number, role, full_name, initials, phone_e164, profile_photo_path, profile_completed_at, account_status)
    values (super_id, null, 'SUPER_ADMIN', 'Oslava Super Admin', 'SA', '+918864938636', null, now(), 'ACTIVE')
    on conflict (id) do update set
      role = excluded.role,
      full_name = excluded.full_name,
      initials = excluded.initials,
      phone_e164 = excluded.phone_e164,
      account_status = excluded.account_status,
      profile_completed_at = excluded.profile_completed_at;

    perform set_config('app.bypass_identity_protection', 'off', true);
  end if;
exception when others then
  perform set_config('app.bypass_identity_protection', 'off', true);
  raise;
end $$;
