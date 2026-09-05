create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  status public.assignment_status not null default 'CONFIRMED',
  source text not null default 'DIRECT_APPLY',
  confirmed_at timestamptz not null default now(),
  category_at_confirmation public.worker_category,
  booking_request_id uuid,
  waitlist_entry_id uuid,
  late_cancellation_acknowledged boolean not null default false,
  completed_at timestamptz,
  removed_at timestamptz,
  removed_by uuid references public.profiles(id) on delete restrict,
  removal_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assignments_source_valid check (
    source in ('DIRECT_APPLY', 'WAITLIST_PROMOTION', 'MANAGEMENT')
  ),
  constraint assignments_worker_role_snapshot check (
    (status = 'CONFIRMED'::public.assignment_status and category_at_confirmation is not null)
    or status <> 'CONFIRMED'::public.assignment_status
  ),
  constraint assignments_removal_pair check (
    (
      status <> 'REMOVED'::public.assignment_status
      and removed_at is null
      and removal_reason is null
    )
    or (
      status = 'REMOVED'::public.assignment_status
      and removed_at is not null
      and btrim(coalesce(removal_reason, '')) <> ''
    )
  )
);

create unique index assignments_one_active_worker_event_idx
  on public.assignments(event_id, worker_id)
  where status = 'CONFIRMED'::public.assignment_status;

create index assignments_worker_confirmed_idx
  on public.assignments(worker_id, status, confirmed_at desc)
  where status = 'CONFIRMED'::public.assignment_status;

create index assignments_event_confirmed_idx
  on public.assignments(event_id, status)
  where status = 'CONFIRMED'::public.assignment_status;

alter table public.assignment_review_flags
  add column if not exists related_assignment_id uuid,
  add column if not exists related_event_id uuid references public.events(id) on delete restrict,
  add column if not exists cause_event_version integer,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.assignment_review_flags
  add constraint assignment_review_flags_assignment_fk
  foreign key (assignment_id) references public.assignments(id) on delete restrict;

alter table public.assignment_review_flags
  add constraint assignment_review_flags_related_assignment_fk
  foreign key (related_assignment_id) references public.assignments(id) on delete restrict;

alter table public.assignments enable row level security;
alter table public.assignments force row level security;

revoke all on public.assignments from public, anon, authenticated;
grant select on public.assignments to authenticated;
grant all on public.assignments to service_role;

create policy assignments_select_own
  on public.assignments
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy assignments_select_event_managers
  on public.assignments
  for select
  to authenticated
  using (private.can_manage_events());

create or replace function private.active_confirmed_assignment_count(p_event_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer
  from public.assignments a
  where a.event_id = p_event_id
    and a.status = 'CONFIRMED'::public.assignment_status;
$$;

create or replace function private.event_times_conflict(
  p_left_reporting_at timestamptz,
  p_left_expected_ends_at timestamptz,
  p_right_reporting_at timestamptz,
  p_right_expected_ends_at timestamptz
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select not (
    p_left_reporting_at >= p_right_expected_ends_at + interval '1 hour'
    or p_left_expected_ends_at + interval '1 hour' <= p_right_reporting_at
  );
$$;

create or replace function public.has_booking_conflict(
  p_worker_id uuid,
  p_event_id uuid,
  p_exclude_assignment_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.events candidate
    join public.assignments a
      on a.worker_id = p_worker_id
      and a.status = 'CONFIRMED'::public.assignment_status
      and (p_exclude_assignment_id is null or a.id <> p_exclude_assignment_id)
    join public.events booked on booked.id = a.event_id
    where candidate.id = p_event_id
      and booked.id <> candidate.id
      and booked.event_status not in (
        'CANCELLED'::public.event_status,
        'CLOSED'::public.event_status
      )
      and private.event_times_conflict(
        candidate.reporting_at,
        candidate.expected_ends_at,
        booked.reporting_at,
        booked.expected_ends_at
      )
  );
$$;

create or replace function private.event_time_edit_conflicts(
  p_event_id uuid,
  p_reporting_at timestamptz,
  p_expected_ends_at timestamptz
)
returns table (
  assignment_id uuid,
  target_user_id uuid,
  related_assignment_id uuid,
  related_event_id uuid
)
language sql
stable
set search_path = ''
as $$
  select
    edited_assignment.id,
    edited_assignment.worker_id,
    other_assignment.id,
    other_assignment.event_id
  from public.assignments edited_assignment
  join public.assignments other_assignment
    on other_assignment.worker_id = edited_assignment.worker_id
    and other_assignment.status = 'CONFIRMED'::public.assignment_status
    and other_assignment.event_id <> p_event_id
  join public.events other_event on other_event.id = other_assignment.event_id
  where edited_assignment.event_id = p_event_id
    and edited_assignment.status = 'CONFIRMED'::public.assignment_status
    and other_event.event_status not in (
      'CANCELLED'::public.event_status,
      'CLOSED'::public.event_status
    )
    and private.event_times_conflict(
      p_reporting_at,
      p_expected_ends_at,
      other_event.reporting_at,
      other_event.expected_ends_at
    );
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
  conflict_count integer;
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

  if timing_changed then
    select count(*)::integer
    into conflict_count
    from private.event_time_edit_conflicts(
      p_event_id,
      p_reporting_at,
      p_expected_ends_at
    );

    if conflict_count > 0 and not p_confirm_conflicts then
      raise exception 'EVENT_TIME_CONFLICT_CONFIRMATION_REQUIRED';
    end if;
  else
    conflict_count := 0;
  end if;

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

  if timing_changed and conflict_count > 0 then
    insert into public.assignment_review_flags (
      target_user_id,
      assignment_id,
      flag_type,
      related_assignment_id,
      related_event_id,
      cause_event_version,
      metadata
    )
    select
      conflicts.target_user_id,
      conflicts.assignment_id,
      'EVENT_TIME_CONFLICT',
      conflicts.related_assignment_id,
      conflicts.related_event_id,
      new_version,
      jsonb_build_object(
        'source', 'event_time_edit',
        'edited_event_id', p_event_id,
        'confirmed_by_admin', p_confirm_conflicts
      )
    from private.event_time_edit_conflicts(
      p_event_id,
      p_reporting_at,
      p_expected_ends_at
    ) conflicts
    on conflict (assignment_id, flag_type)
      where state = 'OPEN' and assignment_id is not null
      do nothing;
  end if;

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
      'conflict_count', conflict_count,
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
      'conflict_resolution_contract', 'conflict-producing time edits require confirmation and create EVENT_TIME_CONFLICT flags when assignments exist',
      'conflict_count', conflict_count
    ),
    p_reason,
    'database'
  );

  return new_version;
end;
$$;

revoke all on function public.has_booking_conflict(uuid, uuid, uuid) from public, anon;
grant execute on function public.has_booking_conflict(uuid, uuid, uuid) to authenticated;
