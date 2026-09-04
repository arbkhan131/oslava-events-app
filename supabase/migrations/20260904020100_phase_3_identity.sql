-- Phase 3: identity, registration, login-adjacent data, and profile storage.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  worker_number bigint unique,
  role public.app_role not null,
  full_name text not null,
  initials text not null,
  phone_e164 text not null unique,
  profile_photo_path text,
  profile_completed_at timestamptz,
  account_status public.account_status not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_full_name_not_blank check (btrim(full_name) <> ''),
  constraint profiles_initials_not_blank check (btrim(initials) <> ''),
  constraint profiles_phone_e164_shape check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  constraint profiles_worker_number_for_workers check (
    (role = 'WORKER'::public.app_role and worker_number is not null)
    or role <> 'WORKER'::public.app_role
  ),
  constraint profiles_photo_completion_pair check (
    (profile_completed_at is null and profile_photo_path is null)
    or (profile_completed_at is not null and profile_photo_path is not null)
  )
);

create table public.worker_profiles (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  category public.worker_category,
  last_worker_category public.worker_category not null default 'F',
  date_of_birth date not null,
  address text not null,
  native_place text not null,
  height_cm numeric(5, 2) not null check (height_cm > 0),
  education_status text not null,
  has_previous_experience boolean not null,
  experience_details text,
  reliability_score numeric(5, 2) check (
    reliability_score is null
    or (reliability_score >= 0 and reliability_score <= 100)
  ),
  reliability_config_version integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint worker_profiles_address_not_blank check (btrim(address) <> ''),
  constraint worker_profiles_native_place_not_blank check (btrim(native_place) <> ''),
  constraint worker_profiles_education_not_blank check (btrim(education_status) <> '')
);

create table public.role_history (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  old_role public.app_role,
  new_role public.app_role not null,
  actor_id uuid references public.profiles(id) on delete restrict,
  actor_role public.app_role,
  reason text not null,
  restored_worker_category public.worker_category,
  created_at timestamptz not null default now(),
  constraint role_history_reason_not_blank check (btrim(reason) <> '')
);

create table public.worker_category_history (
  id uuid primary key default extensions.gen_random_uuid(),
  worker_id uuid not null references public.profiles(id) on delete restrict,
  old_category public.worker_category,
  new_category public.worker_category,
  action text not null,
  actor_id uuid references public.profiles(id) on delete restrict,
  actor_role public.app_role,
  related_event_id uuid,
  reason text not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint worker_category_history_action_valid check (
    action in ('INITIAL_ASSIGNMENT', 'PROMOTION', 'DEMOTION', 'ROLE_RESTORATION')
  ),
  constraint worker_category_history_reason_not_blank check (btrim(reason) <> '')
);

create table public.account_actions (
  id uuid primary key default extensions.gen_random_uuid(),
  target_user_id uuid not null references public.profiles(id) on delete restrict,
  old_status public.account_status,
  new_status public.account_status not null,
  action_type text not null,
  reason text not null,
  related_event_id uuid,
  actor_id uuid references public.profiles(id) on delete restrict,
  actor_role public.app_role,
  release_at timestamptz,
  manual_release boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  constraint account_actions_action_type_not_blank check (btrim(action_type) <> ''),
  constraint account_actions_reason_not_blank check (btrim(reason) <> '')
);

create table public.phone_change_history (
  id uuid primary key default extensions.gen_random_uuid(),
  target_user_id uuid not null references public.profiles(id) on delete restrict,
  old_phone_e164 text not null,
  new_phone_e164 text not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  actor_role public.app_role not null,
  reason text not null,
  created_at timestamptz not null default now(),
  constraint phone_change_old_shape check (old_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  constraint phone_change_new_shape check (new_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  constraint phone_change_reason_not_blank check (btrim(reason) <> ''),
  constraint phone_change_numbers_differ check (old_phone_e164 <> new_phone_e164)
);

create table public.password_recovery_challenges (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  phone_e164 text not null,
  provider_environment text not null,
  otp_hash text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0),
  created_at timestamptz not null default now(),
  constraint password_recovery_phone_shape check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  constraint password_recovery_environment_valid check (
    provider_environment in ('local', 'development', 'production')
  )
);

create index profiles_role_idx on public.profiles(role);
create index profiles_account_status_idx on public.profiles(account_status);
create index worker_profiles_category_idx on public.worker_profiles(category);
create index role_history_user_created_idx on public.role_history(user_id, created_at desc);
create index worker_category_history_worker_created_idx
  on public.worker_category_history(worker_id, created_at desc);
create index account_actions_target_created_idx
  on public.account_actions(target_user_id, created_at desc);
create index phone_change_history_target_created_idx
  on public.phone_change_history(target_user_id, created_at desc);
create index password_recovery_user_created_idx
  on public.password_recovery_challenges(user_id, created_at desc);

create or replace function private.normalize_phone(raw_phone text)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  normalized text;
begin
  normalized := regexp_replace(btrim(raw_phone), '[\s().-]', '', 'g');

  if normalized !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'phone number must be normalized E.164';
  end if;

  return normalized;
end;
$$;

create or replace function private.is_worker_adult(
  birth_date date,
  registration_date date default current_date
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select birth_date <= (registration_date - interval '18 years')::date;
$$;

create or replace function private.profile_photo_path_is_valid(
  user_id uuid,
  photo_path text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select photo_path ~ ('^' || user_id::text || '/[A-Za-z0-9._-]+$');
$$;

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function private.touch_updated_at();

create trigger worker_profiles_touch_updated_at
  before update on public.worker_profiles
  for each row execute function private.touch_updated_at();

create or replace function private.reject_direct_identity_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('app.bypass_identity_protection', true) = 'on' then
    return new;
  end if;

  raise exception 'identity records must be changed through controlled functions';
end;
$$;

create trigger profiles_no_direct_insert
  before insert on public.profiles
  for each row execute function private.reject_direct_identity_mutation();

create trigger profiles_no_direct_update
  before update on public.profiles
  for each row execute function private.reject_direct_identity_mutation();

create trigger worker_profiles_no_direct_insert
  before insert on public.worker_profiles
  for each row execute function private.reject_direct_identity_mutation();

create trigger worker_profiles_no_direct_update
  before update on public.worker_profiles
  for each row execute function private.reject_direct_identity_mutation();

create or replace function private.current_actor_role()
returns public.app_role
language sql
stable
set search_path = ''
as $$
  select role
  from public.profiles
  where id = auth.uid();
$$;

create or replace function public.complete_worker_registration(
  full_name text,
  initials text,
  profile_photo_path text,
  date_of_birth date,
  address text,
  native_place text,
  height_cm numeric,
  education_status text,
  has_previous_experience boolean,
  experience_details text default null
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
  auth_phone text;
  normalized_phone text;
  issued_worker_number bigint;
begin
  if auth_user_id is null then
    raise exception 'authentication required';
  end if;

  select phone into auth_phone
  from auth.users
  where id = auth_user_id;

  if auth_phone is null or btrim(auth_phone) = '' then
    raise exception 'phone authentication identity is required';
  end if;

  normalized_phone := private.normalize_phone(auth_phone);

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
      'account_status', 'ACTIVE'
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

create or replace function public.my_profile()
returns table (
  id uuid,
  worker_number bigint,
  role public.app_role,
  full_name text,
  initials text,
  phone_e164 text,
  profile_photo_path text,
  profile_completed_at timestamptz,
  account_status public.account_status,
  category public.worker_category,
  last_worker_category public.worker_category
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.worker_number,
    p.role,
    p.full_name,
    p.initials,
    p.phone_e164,
    p.profile_photo_path,
    p.profile_completed_at,
    p.account_status,
    wp.category,
    wp.last_worker_category
  from public.profiles p
  left join public.worker_profiles wp on wp.user_id = p.id
  where p.id = auth.uid();
$$;

create or replace function public.provision_staff_profile(
  target_user_id uuid,
  target_role public.app_role,
  full_name text,
  initials text,
  phone_e164 text,
  reason text
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
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can provision staff profiles';
  end if;

  if target_role = 'WORKER'::public.app_role then
    raise exception 'use complete_worker_registration for workers';
  end if;

  if actor_role = 'ADMIN'::public.app_role
     and target_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role) then
    raise exception 'Admin cannot manage Admin or Super Admin authority';
  end if;

  normalized_phone := private.normalize_phone(phone_e164);

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
    target_user_id,
    target_role,
    btrim(full_name),
    btrim(initials),
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
    target_user_id,
    null,
    target_role,
    auth.uid(),
    actor_role,
    reason
  );

  perform set_config('app.bypass_identity_protection', 'off', true);

  return target_user_id;
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
  restored_category public.worker_category;
begin
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can change roles';
  end if;

  select role into old_role
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

  perform set_config('app.bypass_identity_protection', 'on', true);

  if old_role = 'WORKER'::public.app_role
     and new_role <> 'WORKER'::public.app_role then
    update public.worker_profiles
    set last_worker_category = coalesce(category, last_worker_category),
        category = null
    where user_id = target_user_id;
  elsif old_role <> 'WORKER'::public.app_role
        and new_role = 'WORKER'::public.app_role then
    select coalesce(restore_worker_category, last_worker_category)
    into restored_category
    from public.worker_profiles
    where user_id = target_user_id;

    if restored_category is null then
      restored_category := 'F'::public.worker_category;
      insert into public.worker_profiles (
        user_id,
        category,
        last_worker_category,
        date_of_birth,
        address,
        native_place,
        height_cm,
        education_status,
        has_previous_experience
      )
      values (
        target_user_id,
        restored_category,
        restored_category,
        current_date - interval '18 years',
        'Administrative restoration required',
        'Administrative restoration required',
        1,
        'Administrative restoration required',
        false
      );
    else
      update public.worker_profiles
      set category = restored_category,
          last_worker_category = restored_category
      where user_id = target_user_id;
    end if;

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
  set role = new_role
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

create or replace function public.change_user_phone(
  target_user_id uuid,
  new_phone_e164 text,
  reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  target_role public.app_role;
  old_phone text;
  normalized_phone text;
begin
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can change phone numbers';
  end if;

  if btrim(coalesce(reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select role, phone_e164
  into target_role, old_phone
  from public.profiles
  where id = target_user_id
  for update;

  if target_role is null then
    raise exception 'target profile not found';
  end if;

  if actor_role = 'ADMIN'::public.app_role
     and target_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role) then
    raise exception 'Admin cannot manage Admin or Super Admin authority';
  end if;

  normalized_phone := private.normalize_phone(new_phone_e164);

  if old_phone = normalized_phone then
    raise exception 'new phone number must differ from current phone number';
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

  update auth.users
  set phone = normalized_phone,
      phone_confirmed_at = coalesce(phone_confirmed_at, now()),
      updated_at = now()
  where id = target_user_id;

  update public.profiles
  set phone_e164 = normalized_phone
  where id = target_user_id;

  insert into public.phone_change_history (
    target_user_id,
    old_phone_e164,
    new_phone_e164,
    actor_id,
    actor_role,
    reason
  )
  values (
    target_user_id,
    old_phone,
    normalized_phone,
    auth.uid(),
    actor_role,
    reason
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
    'user_phone_changed',
    'profile',
    target_user_id,
    jsonb_build_object('phone_e164', old_phone),
    jsonb_build_object('phone_e164', normalized_phone),
    reason,
    'database'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);
end;
$$;

create or replace function public.start_password_recovery(
  recovery_phone_e164 text,
  provider_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_phone text;
  target_user_id uuid;
  challenge_id uuid;
begin
  normalized_phone := private.normalize_phone(recovery_phone_e164);

  if provider_environment not in ('local', 'development', 'production') then
    raise exception 'invalid recovery provider environment';
  end if;

  select id into target_user_id
  from public.profiles p
  where p.phone_e164 = normalized_phone
    and p.account_status = 'ACTIVE'::public.account_status;

  if target_user_id is null then
    raise exception 'recovery unavailable';
  end if;

  insert into public.password_recovery_challenges (
    user_id,
    phone_e164,
    provider_environment,
    otp_hash,
    expires_at
  )
  values (
    target_user_id,
    normalized_phone,
    provider_environment,
    'provider-managed',
    now() + interval '10 minutes'
  )
  returning id into challenge_id;

  return challenge_id;
end;
$$;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.worker_profiles enable row level security;
alter table public.worker_profiles force row level security;
alter table public.role_history enable row level security;
alter table public.role_history force row level security;
alter table public.worker_category_history enable row level security;
alter table public.worker_category_history force row level security;
alter table public.account_actions enable row level security;
alter table public.account_actions force row level security;
alter table public.phone_change_history enable row level security;
alter table public.phone_change_history force row level security;
alter table public.password_recovery_challenges enable row level security;
alter table public.password_recovery_challenges force row level security;

revoke all on public.profiles from public, anon, authenticated;
revoke all on public.worker_profiles from public, anon, authenticated;
revoke all on public.role_history from public, anon, authenticated;
revoke all on public.worker_category_history from public, anon, authenticated;
revoke all on public.account_actions from public, anon, authenticated;
revoke all on public.phone_change_history from public, anon, authenticated;
revoke all on public.password_recovery_challenges from public, anon, authenticated;

grant select on public.profiles to authenticated;
grant select on public.worker_profiles to authenticated;
grant select on public.role_history to authenticated;
grant select on public.worker_category_history to authenticated;
grant select on public.account_actions to authenticated;
grant select on public.phone_change_history to authenticated;

grant all on public.profiles to service_role;
grant all on public.worker_profiles to service_role;
grant all on public.role_history to service_role;
grant all on public.worker_category_history to service_role;
grant all on public.account_actions to service_role;
grant all on public.phone_change_history to service_role;
grant all on public.password_recovery_challenges to service_role;

grant execute on function public.complete_worker_registration(
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
) to authenticated;
grant execute on function public.my_profile() to authenticated;
grant execute on function public.provision_staff_profile(
  uuid,
  public.app_role,
  text,
  text,
  text,
  text
) to authenticated;
grant execute on function public.change_user_role(
  uuid,
  public.app_role,
  text,
  public.worker_category
) to authenticated;
grant execute on function public.change_user_phone(uuid, text, text) to authenticated;
grant execute on function public.start_password_recovery(text, text) to anon, authenticated;

create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

create policy worker_profiles_select_own
  on public.worker_profiles
  for select
  to authenticated
  using (user_id = auth.uid());

create policy role_history_select_own
  on public.role_history
  for select
  to authenticated
  using (user_id = auth.uid() or actor_id = auth.uid());

create policy worker_category_history_select_own
  on public.worker_category_history
  for select
  to authenticated
  using (worker_id = auth.uid() or actor_id = auth.uid());

create policy account_actions_select_own
  on public.account_actions
  for select
  to authenticated
  using (target_user_id = auth.uid() or actor_id = auth.uid());

create policy phone_change_history_select_own
  on public.phone_change_history
  for select
  to authenticated
  using (target_user_id = auth.uid() or actor_id = auth.uid());

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'profile-photos',
  'profile-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy profile_photos_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and owner = auth.uid()
  );

create policy profile_photos_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'profile-photos'
    and owner = auth.uid()
    and name like auth.uid()::text || '/%'
  );

create policy profile_photos_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and owner = auth.uid()
  )
  with check (
    bucket_id = 'profile-photos'
    and owner = auth.uid()
    and name like auth.uid()::text || '/%'
  );

create policy profile_photos_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and owner = auth.uid()
  );
