-- Phase 4: worker directory, profile maintenance, and account management.

create table public.assignment_review_flags (
  id uuid primary key default extensions.gen_random_uuid(),
  target_user_id uuid not null references public.profiles(id) on delete restrict,
  assignment_id uuid,
  flag_type text not null,
  state text not null default 'OPEN',
  related_account_action_id uuid references public.account_actions(id) on delete restrict,
  detected_at timestamptz not null default now(),
  resolver_id uuid references public.profiles(id) on delete restrict,
  resolution_notes text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint assignment_review_flags_type_valid check (
    flag_type in ('WORKER_DETAINED', 'WORKER_ROLE_CHANGED', 'ROLE_CHANGED', 'EVENT_TIME_CONFLICT')
  ),
  constraint assignment_review_flags_state_valid check (
    state in ('OPEN', 'RESOLVED', 'DISMISSED')
  ),
  constraint assignment_review_flags_resolution_pair check (
    (state = 'OPEN' and resolved_at is null)
    or (state <> 'OPEN' and resolved_at is not null)
  )
);

create unique index assignment_review_flags_open_assignment_type_idx
  on public.assignment_review_flags(assignment_id, flag_type)
  where state = 'OPEN' and assignment_id is not null;

create index assignment_review_flags_target_state_idx
  on public.assignment_review_flags(target_user_id, state, detected_at desc);

alter table public.assignment_review_flags enable row level security;
alter table public.assignment_review_flags force row level security;

revoke all on public.assignment_review_flags from public, anon, authenticated;
grant select on public.assignment_review_flags to authenticated;
grant all on public.assignment_review_flags to service_role;

create or replace function private.current_account_status()
returns public.account_status
language sql
stable
set search_path = ''
as $$
  select account_status
  from public.profiles
  where id = auth.uid();
$$;

create or replace function private.can_view_worker_records()
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.account_status = 'ACTIVE'::public.account_status
      and p.role in (
        'SUPER_ADMIN'::public.app_role,
        'ADMIN'::public.app_role,
        'CAPTAIN'::public.app_role,
        'SUPERVISOR'::public.app_role
      )
  );
$$;

create or replace function public.update_own_profile(
  p_full_name text,
  p_initials text,
  p_address text,
  p_native_place text,
  p_height_cm numeric,
  p_education_status text,
  p_has_previous_experience boolean,
  p_experience_details text default null,
  p_profile_photo_path text default null
)
returns table (
  user_id uuid,
  updated_full_name text,
  updated_initials text,
  updated_profile_photo_path text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role public.app_role;
  old_profile jsonb;
  new_profile jsonb;
begin
  if caller_id is null then
    raise exception 'authentication required';
  end if;

  select role into caller_role
  from public.profiles
  where id = caller_id
  for update;

  if caller_role is null then
    raise exception 'profile not found';
  end if;

  if caller_role <> 'WORKER'::public.app_role then
    raise exception 'only Workers can update worker profile fields in this flow';
  end if;

  if btrim(coalesce(p_full_name, '')) = ''
     or btrim(coalesce(p_initials, '')) = ''
     or btrim(coalesce(p_address, '')) = ''
     or btrim(coalesce(p_native_place, '')) = ''
     or btrim(coalesce(p_education_status, '')) = ''
     or p_height_cm is null
     or p_height_cm <= 0 then
    raise exception 'required profile fields must be complete';
  end if;

  if p_profile_photo_path is not null
     and not private.profile_photo_path_is_valid(caller_id, p_profile_photo_path) then
    raise exception 'invalid profile photo path';
  end if;

  select jsonb_build_object(
    'full_name', p.full_name,
    'initials', p.initials,
    'profile_photo_path', p.profile_photo_path,
    'address', wp.address,
    'native_place', wp.native_place,
    'height_cm', wp.height_cm,
    'education_status', wp.education_status,
    'has_previous_experience', wp.has_previous_experience,
    'experience_details', wp.experience_details
  )
  into old_profile
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where p.id = caller_id;

  perform set_config('app.bypass_identity_protection', 'on', true);

  update public.profiles
  set full_name = btrim(p_full_name),
      initials = btrim(p_initials),
      profile_photo_path = coalesce(p_profile_photo_path, public.profiles.profile_photo_path),
      profile_completed_at = now()
  where id = caller_id;

  update public.worker_profiles
  set address = btrim(p_address),
      native_place = btrim(p_native_place),
      height_cm = p_height_cm,
      education_status = btrim(p_education_status),
      has_previous_experience = p_has_previous_experience,
      experience_details = nullif(btrim(coalesce(p_experience_details, '')), '')
  where public.worker_profiles.user_id = caller_id;

  select jsonb_build_object(
    'full_name', p.full_name,
    'initials', p.initials,
    'profile_photo_path', p.profile_photo_path,
    'address', wp.address,
    'native_place', wp.native_place,
    'height_cm', wp.height_cm,
    'education_status', wp.education_status,
    'has_previous_experience', wp.has_previous_experience,
    'experience_details', wp.experience_details
  )
  into new_profile
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where p.id = caller_id;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    source
  )
  values (
    caller_id,
    caller_role,
    'own_worker_profile_updated',
    'profile',
    caller_id,
    old_profile,
    new_profile,
    'database'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);

  return query
  select p.id, p.full_name, p.initials, p.profile_photo_path
  from public.profiles p
  where p.id = caller_id;
end;
$$;

create or replace function public.change_user_role(
  target_user_id uuid,
  new_role public.app_role,
  reason text,
  restore_worker_category public.worker_category default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_role public.app_role;
  old_status public.account_status;
  restored_category public.worker_category;
  has_worker_profile boolean;
begin
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can change roles';
  end if;

  select role, account_status
  into old_role, old_status
  from public.profiles
  where id = target_user_id
  for update;

  if old_role is null then
    raise exception 'target profile not found';
  end if;

  if btrim(coalesce(reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  if actor_role = 'ADMIN'::public.app_role
     and (
       old_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role)
       or new_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role)
     ) then
    raise exception 'Admin cannot manage Admin or Super Admin authority';
  end if;

  if old_role = new_role then
    return;
  end if;

  select exists (
    select 1
    from public.worker_profiles wp
    where wp.user_id = target_user_id
  )
  into has_worker_profile;

  perform set_config('app.bypass_identity_protection', 'on', true);

  if old_role in ('CAPTAIN'::public.app_role, 'SUPERVISOR'::public.app_role)
     and new_role = 'WORKER'::public.app_role
     and not has_worker_profile then
    update public.profiles
    set account_status = 'INACTIVE'::public.account_status
    where id = target_user_id;

    insert into public.account_actions (
      target_user_id,
      old_status,
      new_status,
      action_type,
      reason,
      actor_id,
      actor_role
    )
    values (
      target_user_id,
      old_status,
      'INACTIVE'::public.account_status,
      'STAFF_ACCESS_REVOKED',
      reason,
      auth.uid(),
      actor_role
    );

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
      'staff_only_access_revoked',
      'profile',
      target_user_id,
      jsonb_build_object('role', old_role, 'account_status', old_status),
      jsonb_build_object(
        'role', old_role,
        'account_status', 'INACTIVE',
        'staff_only_revocation', true,
        'requires_explicit_worker_onboarding', true
      ),
      reason,
      'database'
    );

    perform set_config('app.bypass_identity_protection', 'off', true);
    return;
  end if;

  if old_role = 'WORKER'::public.app_role
     and new_role <> 'WORKER'::public.app_role then
    update public.worker_profiles
    set last_worker_category = coalesce(category, last_worker_category),
        category = null
    where user_id = target_user_id;

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
      'worker_role_changed_operational_effects',
      'profile',
      target_user_id,
      jsonb_build_object('role', old_role),
      jsonb_build_object(
        'role', new_role,
        'active_worker_category', null,
        'assignment_flag_type', 'WORKER_ROLE_CHANGED',
        'confirmed_assignments_retained', true,
        'active_waitlist_entries_withdrawn_without_penalty', true,
        'integration_deferred_until_assignments_and_waitlist_tables_exist', true
      ),
      reason,
      'database'
    );
  elsif old_role <> 'WORKER'::public.app_role
        and new_role = 'WORKER'::public.app_role then
    select coalesce(restore_worker_category, last_worker_category)
    into restored_category
    from public.worker_profiles
    where user_id = target_user_id;

    if restored_category is null then
      raise exception 'explicit Worker onboarding is required for staff-only accounts';
    end if;

    update public.worker_profiles
    set category = restored_category,
        last_worker_category = restored_category
    where user_id = target_user_id;

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
      target_user_id,
      null,
      restored_category,
      'ROLE_RESTORATION',
      auth.uid(),
      actor_role,
      reason
    );
  end if;

  update public.profiles
  set role = new_role,
      account_status = case
        when old_status = 'INACTIVE'::public.account_status
          and new_role = 'WORKER'::public.app_role
          and has_worker_profile
          then 'ACTIVE'::public.account_status
        else account_status
      end
  where id = target_user_id;

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason,
    restored_worker_category
  )
  values (
    target_user_id,
    old_role,
    new_role,
    auth.uid(),
    actor_role,
    reason,
    restored_category
  );

  perform set_config('app.bypass_identity_protection', 'off', true);
end;
$$;

create or replace function public.worker_directory(
  p_search_text text default null,
  p_account_filter public.account_status default null,
  p_category_filter public.worker_category default null,
  p_result_limit integer default 50
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
  profile_completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  safe_limit integer := least(greatest(coalesce(p_result_limit, 50), 1), 100);
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
  limit safe_limit;
end;
$$;

create or replace function public.worker_profile_detail(p_target_user_id uuid)
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
  date_of_birth date,
  address text,
  native_place text,
  height_cm numeric,
  education_status text,
  has_previous_experience boolean,
  experience_details text,
  reliability_score numeric,
  profile_completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_target_user_id <> auth.uid() and not private.can_view_worker_records() then
    raise exception 'not authorized to view worker profile';
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
    wp.date_of_birth,
    wp.address,
    wp.native_place,
    wp.height_cm,
    wp.education_status,
    wp.has_previous_experience,
    wp.experience_details,
    wp.reliability_score,
    p.profile_completed_at
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where p.id = p_target_user_id;
end;
$$;

create or replace function public.worker_history(p_target_user_id uuid)
returns table (
  history_type text,
  action text,
  old_value text,
  new_value text,
  actor_id uuid,
  actor_role public.app_role,
  reason text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_target_user_id <> auth.uid() and not private.can_view_worker_records() then
    raise exception 'not authorized to view worker history';
  end if;

  return query
  select
    'category'::text,
    wch.action,
    wch.old_category::text,
    wch.new_category::text,
    wch.actor_id,
    wch.actor_role,
    wch.reason,
    wch.created_at
  from public.worker_category_history wch
  where wch.worker_id = p_target_user_id
  union all
  select
    'account'::text,
    aa.action_type,
    aa.old_status::text,
    aa.new_status::text,
    aa.actor_id,
    aa.actor_role,
    aa.reason,
    aa.created_at
  from public.account_actions aa
  where aa.target_user_id = p_target_user_id
  union all
  select
    'role'::text,
    'ROLE_CHANGED'::text,
    rh.old_role::text,
    rh.new_role::text,
    rh.actor_id,
    rh.actor_role,
    rh.reason,
    rh.created_at
  from public.role_history rh
  where rh.user_id = p_target_user_id
  union all
  select
    'phone'::text,
    'PHONE_CHANGED'::text,
    pch.old_phone_e164,
    pch.new_phone_e164,
    pch.actor_id,
    pch.actor_role,
    pch.reason,
    pch.created_at
  from public.phone_change_history pch
  where pch.target_user_id = p_target_user_id
  order by created_at desc;
end;
$$;

create or replace function public.change_account_status(
  p_target_user_id uuid,
  p_new_status public.account_status,
  p_reason text,
  p_related_event_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  target_role public.app_role;
  old_status public.account_status;
  action_id uuid;
begin
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can change account status';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select role, account_status
  into target_role, old_status
  from public.profiles
  where id = p_target_user_id
  for update;

  if target_role is null then
    raise exception 'target profile not found';
  end if;

  if target_role <> 'WORKER'::public.app_role then
    raise exception 'Phase 4 account detention/release applies to Workers only';
  end if;

  if p_new_status not in ('ACTIVE'::public.account_status, 'DETAINED'::public.account_status) then
    raise exception 'Phase 4 supports only Detain and Release';
  end if;

  if old_status = p_new_status then
    return null;
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

  update public.profiles
  set account_status = p_new_status
  where id = p_target_user_id;

  insert into public.account_actions (
    target_user_id,
    old_status,
    new_status,
    action_type,
    reason,
    related_event_id,
    actor_id,
    actor_role,
    notes
  )
  values (
    p_target_user_id,
    old_status,
    p_new_status,
    case
      when p_new_status = 'DETAINED'::public.account_status then 'DETAIN'
      when p_new_status = 'ACTIVE'::public.account_status then 'RELEASE'
      else 'STATUS_CHANGE'
    end,
    p_reason,
    p_related_event_id,
    auth.uid(),
    actor_role,
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning id into action_id;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    related_event_id,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'account_status_changed',
    'profile',
    p_target_user_id,
    jsonb_build_object('account_status', old_status),
    jsonb_build_object('account_status', p_new_status),
    p_reason,
    p_related_event_id,
    'database'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);

  return action_id;
end;
$$;

grant execute on function public.update_own_profile(
  text,
  text,
  text,
  text,
  numeric,
  text,
  boolean,
  text,
  text
) to authenticated;
grant execute on function public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer
) to authenticated;
grant execute on function public.worker_profile_detail(uuid) to authenticated;
grant execute on function public.worker_history(uuid) to authenticated;
grant execute on function public.change_account_status(
  uuid,
  public.account_status,
  text,
  uuid,
  text
) to authenticated;

create policy profiles_select_staff_worker_directory
  on public.profiles
  for select
  to authenticated
  using (
    private.can_view_worker_records()
    and exists (
      select 1
      from public.worker_profiles wp
      where wp.user_id = profiles.id
    )
  );

create policy worker_profiles_select_staff_worker_directory
  on public.worker_profiles
  for select
  to authenticated
  using (private.can_view_worker_records());

create policy role_history_select_staff_worker_history
  on public.role_history
  for select
  to authenticated
  using (
    private.can_view_worker_records()
    and exists (
      select 1
      from public.worker_profiles wp
      where wp.user_id = role_history.user_id
    )
  );

create policy worker_category_history_select_staff_worker_history
  on public.worker_category_history
  for select
  to authenticated
  using (private.can_view_worker_records());

create policy account_actions_select_staff_worker_history
  on public.account_actions
  for select
  to authenticated
  using (
    private.can_view_worker_records()
    and exists (
      select 1
      from public.worker_profiles wp
      where wp.user_id = account_actions.target_user_id
    )
  );

create policy phone_change_history_select_staff_worker_history
  on public.phone_change_history
  for select
  to authenticated
  using (
    private.can_view_worker_records()
    and exists (
      select 1
      from public.worker_profiles wp
      where wp.user_id = phone_change_history.target_user_id
    )
  );

create policy assignment_review_flags_select_admin
  on public.assignment_review_flags
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.account_status = 'ACTIVE'::public.account_status
        and p.role in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role)
    )
  );

create policy profile_photos_select_staff_worker_directory
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and private.can_view_worker_records()
  );
