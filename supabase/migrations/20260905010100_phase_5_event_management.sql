-- Phase 5: Admin/Super Admin event management.

create table public.events (
  id uuid primary key default extensions.gen_random_uuid(),
  title text not null,
  event_type text not null,
  venue_name text not null,
  maps_url text,
  event_date date not null,
  timezone_name text not null default 'Asia/Kolkata',
  reporting_at timestamptz not null,
  work_starts_at timestamptz not null,
  expected_ends_at timestamptz not null,
  required_worker_count integer not null,
  daily_wage numeric(12, 2) not null,
  currency_code char(3) not null default 'INR',
  instructions text,
  dress_code text,
  event_status public.event_status not null default 'DRAFT',
  recruitment_status public.recruitment_status not null default 'NOT_OPEN',
  tier_strategy public.tier_strategy not null,
  published_at timestamptz,
  cancelled_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  cancelled_by uuid references public.profiles(id) on delete restrict,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint events_title_not_blank check (btrim(title) <> ''),
  constraint events_type_not_blank check (btrim(event_type) <> ''),
  constraint events_venue_not_blank check (btrim(venue_name) <> ''),
  constraint events_time_order check (reporting_at <= work_starts_at and work_starts_at < expected_ends_at),
  constraint events_worker_count_positive check (required_worker_count > 0),
  constraint events_wage_non_negative check (daily_wage >= 0),
  constraint events_timezone_v1 check (timezone_name = 'Asia/Kolkata'),
  constraint events_currency_v1 check (currency_code = 'INR'),
  constraint events_cancelled_pair check (
    (event_status = 'CANCELLED'::public.event_status and cancelled_at is not null and cancelled_by is not null)
    or event_status <> 'CANCELLED'::public.event_status
  ),
  constraint events_published_pair check (
    (event_status in (
      'PUBLISHED'::public.event_status,
      'UPCOMING'::public.event_status,
      'IN_PROGRESS'::public.event_status,
      'COMPLETED'::public.event_status,
      'CLOSED'::public.event_status,
      'CANCELLED'::public.event_status
    ) and published_at is not null)
    or event_status = 'DRAFT'::public.event_status
  ),
  constraint events_recruitment_combo check (
    (event_status = 'DRAFT'::public.event_status and recruitment_status = 'NOT_OPEN'::public.recruitment_status)
    or (event_status = 'CANCELLED'::public.event_status and recruitment_status = 'CLOSED'::public.recruitment_status)
    or (event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) and recruitment_status = 'CLOSED'::public.recruitment_status)
    or event_status not in ('DRAFT'::public.event_status, 'CANCELLED'::public.event_status)
  )
);

create table public.event_leaders (
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  leader_role public.leader_role not null,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  removed_at timestamptz,
  constraint event_leaders_active_unique unique (event_id, user_id, leader_role)
);

create table public.event_requirements (
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  description text,
  is_mandatory boolean not null default true,
  acknowledgement_required boolean not null default false,
  extra_allowance_amount numeric(12, 2) not null default 0,
  currency_code char(3) not null default 'INR',
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint event_requirements_name_not_blank check (btrim(name) <> ''),
  constraint event_requirements_allowance_non_negative check (extra_allowance_amount >= 0),
  constraint event_requirements_currency_v1 check (currency_code = 'INR')
);

create table public.event_allowances (
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  label text not null,
  description text,
  amount numeric(12, 2) not null default 0,
  currency_code char(3) not null default 'INR',
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint event_allowances_label_not_blank check (btrim(label) <> ''),
  constraint event_allowances_amount_non_negative check (amount >= 0),
  constraint event_allowances_currency_v1 check (currency_code = 'INR')
);

create table public.event_history (
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  action text not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  actor_role public.app_role not null,
  before_values jsonb,
  after_values jsonb,
  reason text,
  created_at timestamptz not null default now(),
  constraint event_history_action_not_blank check (btrim(action) <> '')
);

create index events_status_reporting_idx
  on public.events(event_status, recruitment_status, reporting_at);
create index events_created_by_idx on public.events(created_by, created_at desc);
create index event_leaders_event_idx on public.event_leaders(event_id);
create index event_leaders_user_idx on public.event_leaders(user_id);
create index event_requirements_event_order_idx on public.event_requirements(event_id, display_order);
create index event_allowances_event_order_idx on public.event_allowances(event_id, display_order);
create index event_history_event_created_idx on public.event_history(event_id, created_at desc);

create trigger events_touch_updated_at
  before update on public.events
  for each row execute function private.touch_updated_at();

create or replace function private.can_manage_events()
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
      and p.role in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role)
  );
$$;

create or replace function private.validate_event_leaders(p_leaders jsonb)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  leader record;
  profile_role public.app_role;
  profile_status public.account_status;
begin
  if jsonb_typeof(coalesce(p_leaders, '[]'::jsonb)) <> 'array' then
    raise exception 'leaders must be an array';
  end if;

  for leader in
    select *
    from jsonb_to_recordset(coalesce(p_leaders, '[]'::jsonb))
      as x(user_id uuid, leader_role text)
  loop
    if leader.leader_role not in ('CAPTAIN', 'SUPERVISOR') then
      raise exception 'invalid leader role';
    end if;

    select p.role, p.account_status
    into profile_role, profile_status
    from public.profiles p
    where p.id = leader.user_id;

    if profile_role is null then
      raise exception 'leader profile not found';
    end if;

    if profile_status <> 'ACTIVE'::public.account_status
       or profile_role::text <> leader.leader_role then
      raise exception 'leader role must match an active profile';
    end if;
  end loop;
end;
$$;

create or replace function private.insert_event_children(
  p_event_id uuid,
  p_actor_id uuid,
  p_leaders jsonb,
  p_requirements jsonb,
  p_allowances jsonb
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform private.validate_event_leaders(p_leaders);

  if jsonb_typeof(coalesce(p_requirements, '[]'::jsonb)) <> 'array' then
    raise exception 'requirements must be an array';
  end if;

  if jsonb_typeof(coalesce(p_allowances, '[]'::jsonb)) <> 'array' then
    raise exception 'allowances must be an array';
  end if;

  insert into public.event_leaders (
    event_id,
    user_id,
    leader_role,
    assigned_by
  )
  select
    p_event_id,
    x.user_id,
    x.leader_role::public.leader_role,
    p_actor_id
  from jsonb_to_recordset(coalesce(p_leaders, '[]'::jsonb))
    as x(user_id uuid, leader_role text);

  insert into public.event_requirements (
    event_id,
    name,
    description,
    is_mandatory,
    acknowledgement_required,
    extra_allowance_amount,
    display_order
  )
  select
    p_event_id,
    btrim(x.name),
    nullif(btrim(coalesce(x.description, '')), ''),
    coalesce(x.is_mandatory, true),
    coalesce(x.acknowledgement_required, false),
    coalesce(x.extra_allowance_amount, 0),
    coalesce(x.display_order, 0)
  from jsonb_to_recordset(coalesce(p_requirements, '[]'::jsonb))
    as x(
      name text,
      description text,
      is_mandatory boolean,
      acknowledgement_required boolean,
      extra_allowance_amount numeric,
      display_order integer
    );

  insert into public.event_allowances (
    event_id,
    label,
    description,
    amount,
    display_order
  )
  select
    p_event_id,
    btrim(x.label),
    nullif(btrim(coalesce(x.description, '')), ''),
    coalesce(x.amount, 0),
    coalesce(x.display_order, 0)
  from jsonb_to_recordset(coalesce(p_allowances, '[]'::jsonb))
    as x(label text, description text, amount numeric, display_order integer);
end;
$$;

create or replace function private.event_snapshot(p_event_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(e)
  from public.events e
  where e.id = p_event_id;
$$;

create or replace function private.active_confirmed_assignment_count(p_event_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select 0;
$$;

create or replace function public.create_event_draft(
  p_title text,
  p_event_type text,
  p_venue_name text,
  p_maps_url text,
  p_reporting_at timestamptz,
  p_work_starts_at timestamptz,
  p_expected_ends_at timestamptz,
  p_required_worker_count integer,
  p_daily_wage numeric,
  p_tier_strategy public.tier_strategy,
  p_instructions text default null,
  p_dress_code text default null,
  p_leaders jsonb default '[]'::jsonb,
  p_requirements jsonb default '[]'::jsonb,
  p_allowances jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  new_event_id uuid;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  insert into public.events (
    title,
    event_type,
    venue_name,
    maps_url,
    event_date,
    reporting_at,
    work_starts_at,
    expected_ends_at,
    required_worker_count,
    daily_wage,
    tier_strategy,
    instructions,
    dress_code,
    created_by,
    updated_by
  )
  values (
    btrim(p_title),
    btrim(p_event_type),
    btrim(p_venue_name),
    nullif(btrim(coalesce(p_maps_url, '')), ''),
    (p_reporting_at at time zone 'Asia/Kolkata')::date,
    p_reporting_at,
    p_work_starts_at,
    p_expected_ends_at,
    p_required_worker_count,
    p_daily_wage,
    p_tier_strategy,
    nullif(btrim(coalesce(p_instructions, '')), ''),
    nullif(btrim(coalesce(p_dress_code, '')), ''),
    auth.uid(),
    auth.uid()
  )
  returning id into new_event_id;

  perform private.insert_event_children(
    new_event_id,
    auth.uid(),
    p_leaders,
    p_requirements,
    p_allowances
  );

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    after_values,
    reason
  )
  values (
    new_event_id,
    'EVENT_DRAFT_CREATED',
    auth.uid(),
    actor_role,
    private.event_snapshot(new_event_id),
    'Draft created'
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
    auth.uid(),
    actor_role,
    'event_draft_created',
    'event',
    new_event_id,
    private.event_snapshot(new_event_id),
    'database'
  );

  return new_event_id;
end;
$$;

create or replace function public.update_event(
  p_event_id uuid,
  p_expected_version integer,
  p_title text,
  p_event_type text,
  p_venue_name text,
  p_maps_url text,
  p_reporting_at timestamptz,
  p_work_starts_at timestamptz,
  p_expected_ends_at timestamptz,
  p_required_worker_count integer,
  p_daily_wage numeric,
  p_tier_strategy public.tier_strategy,
  p_instructions text default null,
  p_dress_code text default null,
  p_leaders jsonb default '[]'::jsonb,
  p_requirements jsonb default '[]'::jsonb,
  p_allowances jsonb default '[]'::jsonb,
  p_reason text default 'Event updated',
  p_confirm_conflicts boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
  old_snapshot jsonb;
  new_version integer;
  confirmed_count integer;
  timing_changed boolean;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status in ('CANCELLED'::public.event_status, 'CLOSED'::public.event_status) then
    raise exception 'terminal events cannot be edited';
  end if;

  if old_event.version <> p_expected_version then
    raise exception 'STALE_VERSION';
  end if;

  confirmed_count := private.active_confirmed_assignment_count(p_event_id);

  if p_required_worker_count < confirmed_count then
    raise exception 'capacity below confirmed assignments requires management removal workflow';
  end if;

  timing_changed := old_event.reporting_at <> p_reporting_at
    or old_event.work_starts_at <> p_work_starts_at
    or old_event.expected_ends_at <> p_expected_ends_at;

  old_snapshot := to_jsonb(old_event);

  delete from public.event_leaders where event_id = p_event_id;
  delete from public.event_requirements where event_id = p_event_id;
  delete from public.event_allowances where event_id = p_event_id;

  update public.events
  set title = btrim(p_title),
      event_type = btrim(p_event_type),
      venue_name = btrim(p_venue_name),
      maps_url = nullif(btrim(coalesce(p_maps_url, '')), ''),
      event_date = (p_reporting_at at time zone 'Asia/Kolkata')::date,
      reporting_at = p_reporting_at,
      work_starts_at = p_work_starts_at,
      expected_ends_at = p_expected_ends_at,
      required_worker_count = p_required_worker_count,
      daily_wage = p_daily_wage,
      tier_strategy = p_tier_strategy,
      instructions = nullif(btrim(coalesce(p_instructions, '')), ''),
      dress_code = nullif(btrim(coalesce(p_dress_code, '')), ''),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_event_id
  returning version into new_version;

  perform private.insert_event_children(
    p_event_id,
    auth.uid(),
    p_leaders,
    p_requirements,
    p_allowances
  );

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    before_values,
    after_values,
    reason
  )
  values (
    p_event_id,
    'EVENT_UPDATED',
    auth.uid(),
    actor_role,
    old_snapshot,
    private.event_snapshot(p_event_id) || jsonb_build_object(
      'conflict_confirmation_supplied', p_confirm_conflicts,
      'timing_changed', timing_changed,
      'conflict_flag_contract', 'EVENT_TIME_CONFLICT'
    ),
    p_reason
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
    'event_updated',
    'event',
    p_event_id,
    old_snapshot,
    private.event_snapshot(p_event_id) || jsonb_build_object(
      'capacity_reduction_contract', 'below confirmed count requires explicit management removal',
      'conflict_resolution_contract', 'conflict-producing time edits require confirmation and create EVENT_TIME_CONFLICT flags when assignments exist'
    ),
    p_reason,
    'database'
  );

  return new_version;
end;
$$;

create or replace function public.publish_event(
  p_event_id uuid,
  p_reason text default 'Event published'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status <> 'DRAFT'::public.event_status then
    raise exception 'only draft events can be published in Phase 5';
  end if;

  update public.events
  set event_status = case
        when event_date <= (now() at time zone 'Asia/Kolkata')::date
          then 'UPCOMING'::public.event_status
        else 'PUBLISHED'::public.event_status
      end,
      recruitment_status = 'NOT_OPEN'::public.recruitment_status,
      published_at = now(),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_event_id;

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    before_values,
    after_values,
    reason
  )
  values (
    p_event_id,
    'EVENT_PUBLISHED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
  );
end;
$$;

create or replace function public.cancel_event(
  p_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status in ('CANCELLED'::public.event_status, 'CLOSED'::public.event_status) then
    raise exception 'terminal events cannot be cancelled again';
  end if;

  if old_event.event_status = 'COMPLETED'::public.event_status then
    raise exception 'completed events must be closed or resolved, not cancelled';
  end if;

  update public.events
  set event_status = 'CANCELLED'::public.event_status,
      recruitment_status = 'CLOSED'::public.recruitment_status,
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      updated_by = auth.uid(),
      published_at = coalesce(published_at, now()),
      version = version + 1
  where id = p_event_id;

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    before_values,
    after_values,
    reason
  )
  values (
    p_event_id,
    'EVENT_CANCELLED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
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
    'event_cancelled',
    'event',
    p_event_id,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason,
    'database'
  );
end;
$$;

create or replace function public.complete_event(
  p_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status <> 'IN_PROGRESS'::public.event_status then
    raise exception 'only in-progress events can be completed';
  end if;

  update public.events
  set event_status = 'COMPLETED'::public.event_status,
      recruitment_status = 'CLOSED'::public.recruitment_status,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_event_id;

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    before_values,
    after_values,
    reason
  )
  values (
    p_event_id,
    'EVENT_COMPLETED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
  );
end;
$$;

create or replace function public.close_event(
  p_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status <> 'COMPLETED'::public.event_status then
    raise exception 'only completed events can be closed';
  end if;

  update public.events
  set event_status = 'CLOSED'::public.event_status,
      recruitment_status = 'CLOSED'::public.recruitment_status,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_event_id;

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    before_values,
    after_values,
    reason
  )
  values (
    p_event_id,
    'EVENT_CLOSED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
  );
end;
$$;

create or replace function public.process_event_lifecycle_transitions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer := 0;
  closed_recruitment_count integer := 0;
  event_row public.events%rowtype;
  old_snapshot jsonb;
begin
  for event_row in
    select *
    from public.events
    where event_status in (
        'PUBLISHED'::public.event_status,
        'UPCOMING'::public.event_status
      )
      and (
        (
          event_status = 'PUBLISHED'::public.event_status
          and event_date <= (now() at time zone 'Asia/Kolkata')::date
        )
        or reporting_at <= now()
      )
    for update
  loop
    old_snapshot := to_jsonb(event_row);

    update public.events e
    set event_status = case
          when event_row.reporting_at <= now()
            then 'IN_PROGRESS'::public.event_status
          else 'UPCOMING'::public.event_status
        end,
        recruitment_status = case
          when event_row.reporting_at <= now()
            then 'CLOSED'::public.recruitment_status
          else e.recruitment_status
        end,
        version = version + 1
    where e.id = event_row.id;

    insert into public.event_history (
      event_id,
      action,
      actor_id,
      actor_role,
      before_values,
      after_values,
      reason
    )
    values (
      event_row.id,
      'EVENT_LIFECYCLE_AUTOMATED',
      event_row.updated_by,
      (
        select p.role
        from public.profiles p
        where p.id = event_row.updated_by
      ),
      old_snapshot,
      private.event_snapshot(event_row.id),
      'Automated lifecycle transition'
    );

    changed_count := changed_count + 1;
  end loop;

  update public.events
  set recruitment_status = 'CLOSED'::public.recruitment_status,
      version = version + 1
  where recruitment_status in (
      'NOT_OPEN'::public.recruitment_status,
      'OPEN'::public.recruitment_status,
      'FULL'::public.recruitment_status
    )
    and reporting_at <= now()
    and event_status not in (
      'DRAFT'::public.event_status,
      'CANCELLED'::public.event_status,
      'COMPLETED'::public.event_status,
      'CLOSED'::public.event_status
    );

  get diagnostics closed_recruitment_count = row_count;
  changed_count := changed_count + closed_recruitment_count;

  return changed_count;
end;
$$;

create or replace function public.admin_event_list()
returns table (
  id uuid,
  title text,
  event_type text,
  venue_name text,
  event_date date,
  reporting_at timestamptz,
  required_worker_count integer,
  daily_wage numeric,
  currency_code char(3),
  event_status public.event_status,
  recruitment_status public.recruitment_status,
  tier_strategy public.tier_strategy,
  version integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can view admin events';
  end if;

  return query
  select
    e.id,
    e.title,
    e.event_type,
    e.venue_name,
    e.event_date,
    e.reporting_at,
    e.required_worker_count,
    e.daily_wage,
    e.currency_code,
    e.event_status,
    e.recruitment_status,
    e.tier_strategy,
    e.version
  from public.events e
  order by e.reporting_at desc, e.created_at desc;
end;
$$;

alter table public.events enable row level security;
alter table public.events force row level security;
alter table public.event_leaders enable row level security;
alter table public.event_leaders force row level security;
alter table public.event_requirements enable row level security;
alter table public.event_requirements force row level security;
alter table public.event_allowances enable row level security;
alter table public.event_allowances force row level security;
alter table public.event_history enable row level security;
alter table public.event_history force row level security;

revoke all on public.events from public, anon, authenticated;
revoke all on public.event_leaders from public, anon, authenticated;
revoke all on public.event_requirements from public, anon, authenticated;
revoke all on public.event_allowances from public, anon, authenticated;
revoke all on public.event_history from public, anon, authenticated;

grant select on public.events to authenticated;
grant select on public.event_leaders to authenticated;
grant select on public.event_requirements to authenticated;
grant select on public.event_allowances to authenticated;
grant select on public.event_history to authenticated;

grant all on public.events to service_role;
grant all on public.event_leaders to service_role;
grant all on public.event_requirements to service_role;
grant all on public.event_allowances to service_role;
grant all on public.event_history to service_role;

revoke all on function public.create_event_draft(
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  integer,
  numeric,
  public.tier_strategy,
  text,
  text,
  jsonb,
  jsonb,
  jsonb
) from public, anon;
revoke all on function public.update_event(
  uuid,
  integer,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  integer,
  numeric,
  public.tier_strategy,
  text,
  text,
  jsonb,
  jsonb,
  jsonb,
  text,
  boolean
) from public, anon;
revoke all on function public.publish_event(uuid, text) from public, anon;
revoke all on function public.cancel_event(uuid, text) from public, anon;
revoke all on function public.complete_event(uuid, text) from public, anon;
revoke all on function public.close_event(uuid, text) from public, anon;
revoke all on function public.process_event_lifecycle_transitions() from public, anon;
revoke all on function public.admin_event_list() from public, anon;

grant execute on function public.create_event_draft(
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  integer,
  numeric,
  public.tier_strategy,
  text,
  text,
  jsonb,
  jsonb,
  jsonb
) to authenticated;
grant execute on function public.update_event(
  uuid,
  integer,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  integer,
  numeric,
  public.tier_strategy,
  text,
  text,
  jsonb,
  jsonb,
  jsonb,
  text,
  boolean
) to authenticated;
grant execute on function public.publish_event(uuid, text) to authenticated;
grant execute on function public.cancel_event(uuid, text) to authenticated;
grant execute on function public.complete_event(uuid, text) to authenticated;
grant execute on function public.close_event(uuid, text) to authenticated;
grant execute on function public.process_event_lifecycle_transitions() to service_role;
grant execute on function public.admin_event_list() to authenticated;

create policy events_select_admin_all
  on public.events
  for select
  to authenticated
  using (private.can_manage_events());

create policy events_select_worker_visible
  on public.events
  for select
  to authenticated
  using (
    event_status <> 'DRAFT'::public.event_status
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.account_status = 'ACTIVE'::public.account_status
        and p.role = 'WORKER'::public.app_role
    )
  );

create policy event_leaders_select_parent
  on public.event_leaders
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.events e
      where e.id = event_leaders.event_id
    )
  );

create policy event_requirements_select_parent
  on public.event_requirements
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.events e
      where e.id = event_requirements.event_id
    )
  );

create policy event_allowances_select_parent
  on public.event_allowances
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.events e
      where e.id = event_allowances.event_id
    )
  );

create policy event_history_select_admin
  on public.event_history
  for select
  to authenticated
  using (private.can_manage_events());
