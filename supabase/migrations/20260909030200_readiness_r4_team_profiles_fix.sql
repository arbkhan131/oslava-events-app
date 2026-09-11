-- R4 corrective migration for local/schema chains that applied the first R4 draft.

drop function if exists public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer
);

drop function if exists public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer,
  integer
);

create or replace function public.worker_directory(
  p_search_text text default null,
  p_account_filter public.account_status default null,
  p_category_filter public.worker_category default null,
  p_result_limit integer default 50,
  p_result_offset integer default 0
)
returns table (
  user_id uuid,
  worker_number bigint,
  full_name text,
  initials text,
  phone_e164 text,
  profile_photo_path text,
  role public.app_role,
  account_status public.account_status,
  category public.worker_category,
  last_worker_category public.worker_category,
  reliability_score numeric,
  reliability_state text,
  reliability_sample_count integer,
  reliability_present_count integer,
  reliability_late_count integer,
  reliability_absent_count integer,
  reliability_worker_cancellation_count integer,
  reliability_completed_event_count integer,
  reliability_performance_event_count integer,
  reliability_performance_average numeric,
  reliability_config_version integer,
  profile_completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  safe_limit integer := least(greatest(coalesce(p_result_limit, 50), 1), 100);
  safe_offset integer := greatest(coalesce(p_result_offset, 0), 0);
  query_text text := '%' || lower(btrim(coalesce(p_search_text, ''))) || '%';
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not private.can_view_worker_records() then
    raise exception 'not authorized to view worker directory';
  end if;

  return query
  select
    p.id,
    p.worker_number,
    p.full_name,
    p.initials,
    p.phone_e164,
    p.profile_photo_path,
    p.role,
    p.account_status,
    wp.category,
    wp.last_worker_category,
    wp.reliability_score,
    wp.reliability_state,
    wp.reliability_sample_count,
    wp.reliability_present_count,
    wp.reliability_late_count,
    wp.reliability_absent_count,
    wp.reliability_worker_cancellation_count,
    wp.reliability_completed_event_count,
    wp.reliability_performance_event_count,
    wp.reliability_performance_average,
    wp.reliability_config_version,
    p.profile_completed_at
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where (p_account_filter is null or p.account_status = p_account_filter)
    and (p_category_filter is null or wp.category = p_category_filter)
    and (
      btrim(coalesce(p_search_text, '')) = ''
      or lower(p.full_name) like query_text
      or lower(p.initials) like query_text
      or p.phone_e164 like '%' || btrim(p_search_text) || '%'
      or p.worker_number::text like '%' || btrim(p_search_text) || '%'
    )
  order by p.full_name, p.worker_number
  limit safe_limit
  offset safe_offset;
end;
$$;

grant execute on function public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer,
  integer
) to authenticated;

drop function if exists public.provision_staff_profile(
  uuid,
  public.app_role,
  text,
  text,
  text,
  text
);

create or replace function public.provision_staff_profile(
  p_auth_user_id uuid,
  p_role public.app_role,
  p_full_name text,
  p_initials text,
  p_phone_e164 text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  normalized_phone text;
begin
  perform private.lock_privileged_identity_mutation();
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can provision staff accounts';
  end if;

  if p_role not in ('ADMIN'::public.app_role, 'CAPTAIN'::public.app_role, 'SUPERVISOR'::public.app_role) then
    raise exception 'staff provisioning supports Admin, Captain and Supervisor roles';
  end if;

  if actor_role = 'ADMIN'::public.app_role and p_role = 'ADMIN'::public.app_role then
    raise exception 'Admin cannot provision Admin accounts';
  end if;

  if btrim(coalesce(p_full_name, '')) = ''
     or btrim(coalesce(p_initials, '')) = ''
     or btrim(coalesce(p_reason, '')) = '' then
    raise exception 'staff profile fields and reason are required';
  end if;

  if not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception 'Auth account does not exist';
  end if;

  normalized_phone := private.normalize_phone(p_phone_e164);

  if exists (
    select 1
    from public.profiles p
    where p.phone_e164 = normalized_phone
      and p.id <> p_auth_user_id
  ) then
    raise exception 'phone number already belongs to another profile';
  end if;

  if exists (select 1 from public.profiles where id = p_auth_user_id) then
    raise exception 'profile already exists for Auth account';
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

  insert into public.profiles (
    id,
    role,
    full_name,
    initials,
    phone_e164,
    account_status
  )
  values (
    p_auth_user_id,
    p_role,
    btrim(p_full_name),
    btrim(p_initials),
    normalized_phone,
    'ACTIVE'::public.account_status
  );

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason
  )
  values (
    p_auth_user_id,
    null,
    p_role,
    auth.uid(),
    actor_role,
    p_reason
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
    auth.uid(),
    actor_role,
    'staff_profile_provisioned',
    'profile',
    p_auth_user_id,
    jsonb_build_object('role', p_role, 'phone_e164', normalized_phone),
    p_reason,
    'database'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);

  return p_auth_user_id;
end;
$$;

grant execute on function public.provision_staff_profile(
  uuid,
  public.app_role,
  text,
  text,
  text,
  text
) to authenticated;
