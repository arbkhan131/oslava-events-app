create table public.attendance (
  assignment_id uuid primary key references public.assignments(id) on delete restrict,
  event_id uuid not null references public.events(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  status public.attendance_status not null default 'NOT_MARKED',
  marked_by uuid references public.profiles(id) on delete restrict,
  marker_role public.app_role,
  marked_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_notes_not_blank check (
    notes is null or btrim(notes) <> ''
  )
);

create index attendance_event_status_idx on public.attendance(event_id, status);
create index attendance_worker_idx on public.attendance(worker_id, status);

create table public.attendance_history (
  id uuid primary key default extensions.gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete restrict,
  event_id uuid not null references public.events(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  old_status public.attendance_status,
  new_status public.attendance_status not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  actor_role public.app_role not null,
  old_notes text,
  new_notes text,
  created_at timestamptz not null default now()
);

create index attendance_history_assignment_created_idx
  on public.attendance_history(assignment_id, created_at desc);
create index attendance_history_event_created_idx
  on public.attendance_history(event_id, created_at desc);

create or replace function private.can_view_event_operations(p_event_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.can_manage_events()
    or exists (
      select 1
      from public.event_leaders el
      join public.profiles p on p.id = el.user_id
      where el.event_id = p_event_id
        and el.user_id = auth.uid()
        and p.account_status = 'ACTIVE'::public.account_status
        and p.role::text = el.leader_role::text
    );
$$;

create or replace function private.can_set_attendance(
  p_event_id uuid,
  p_event_status public.event_status
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when private.can_manage_events() then true
    when p_event_status = 'CLOSED'::public.event_status then false
    else exists (
      select 1
      from public.event_leaders el
      join public.profiles p on p.id = el.user_id
      where el.event_id = p_event_id
        and el.user_id = auth.uid()
        and p.account_status = 'ACTIVE'::public.account_status
        and p.role::text = el.leader_role::text
    )
  end;
$$;

create or replace function private.audit_attendance_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid;
  actor_role public.app_role;
begin
  actor := coalesce(new.marked_by, auth.uid());
  actor_role := coalesce(new.marker_role, private.current_actor_role());

  if actor is null or actor_role is null then
    raise exception 'attendance actor is required';
  end if;

  insert into public.attendance_history (
    assignment_id,
    event_id,
    worker_id,
    old_status,
    new_status,
    actor_id,
    actor_role,
    old_notes,
    new_notes
  )
  values (
    new.assignment_id,
    new.event_id,
    new.worker_id,
    case when tg_op = 'UPDATE' then old.status else null end,
    new.status,
    actor,
    actor_role,
    case when tg_op = 'UPDATE' then old.notes else null end,
    new.notes
  );

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    related_event_id,
    source
  )
  values (
    actor,
    actor_role,
    case when tg_op = 'UPDATE' then 'attendance_updated' else 'attendance_marked' end,
    'attendance',
    new.assignment_id,
    case
      when tg_op = 'UPDATE' then jsonb_build_object(
        'status', old.status,
        'notes', old.notes
      )
      else null
    end,
    jsonb_build_object(
      'status', new.status,
      'notes', new.notes,
      'worker_id', new.worker_id
    ),
    new.event_id,
    'database'
  );

  return new;
end;
$$;

create trigger attendance_touch_updated_at
  before update on public.attendance
  for each row execute function private.touch_updated_at();

create trigger attendance_audit_change
  after insert or update on public.attendance
  for each row execute function private.audit_attendance_change();

create or replace function public.field_event_list()
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
language sql
stable
security definer
set search_path = ''
as $$
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
  where private.can_manage_events()
     or exists (
       select 1
       from public.event_leaders el
       where el.event_id = e.id
         and el.user_id = auth.uid()
     )
  order by e.reporting_at desc, e.created_at desc;
$$;

create or replace function public.event_attendance_roster(
  p_event_id uuid,
  p_search_text text default null
)
returns table (
  assignment_id uuid,
  event_id uuid,
  worker_id uuid,
  worker_number bigint,
  full_name text,
  phone_e164 text,
  profile_photo_path text,
  category_at_confirmation public.worker_category,
  current_category public.worker_category,
  assignment_status public.assignment_status,
  attendance_status public.attendance_status,
  marked_by uuid,
  marker_role public.app_role,
  marked_at timestamptz,
  notes text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_view_event_operations(p_event_id) then
    raise exception 'not authorized for event operations';
  end if;

  return query
  select
    a.id,
    a.event_id,
    p.id,
    p.worker_number,
    p.full_name,
    p.phone_e164,
    p.profile_photo_path,
    a.category_at_confirmation,
    wp.category,
    a.status,
    coalesce(att.status, 'NOT_MARKED'::public.attendance_status),
    att.marked_by,
    att.marker_role,
    att.marked_at,
    att.notes
  from public.assignments a
  join public.profiles p on p.id = a.worker_id
  left join public.worker_profiles wp on wp.user_id = p.id
  left join public.attendance att on att.assignment_id = a.id
  where a.event_id = p_event_id
    and a.status in (
      'CONFIRMED'::public.assignment_status,
      'COMPLETED'::public.assignment_status
    )
    and (
      nullif(btrim(coalesce(p_search_text, '')), '') is null
      or p.full_name ilike '%' || btrim(p_search_text) || '%'
      or p.phone_e164 ilike '%' || btrim(p_search_text) || '%'
      or p.worker_number::text ilike '%' || btrim(p_search_text) || '%'
      or a.category_at_confirmation::text ilike btrim(p_search_text) || '%'
    )
  order by
    private.category_rank(a.category_at_confirmation),
    p.full_name,
    p.worker_number;
end;
$$;

create or replace function public.event_attendance_counters(
  p_event_id uuid
)
returns table (
  total integer,
  not_marked integer,
  present integer,
  late integer,
  absent integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_view_event_operations(p_event_id) then
    raise exception 'not authorized for event operations';
  end if;

  return query
  select
    count(*)::integer,
    count(*) filter (
      where coalesce(att.status, 'NOT_MARKED'::public.attendance_status)
        = 'NOT_MARKED'::public.attendance_status
    )::integer,
    count(*) filter (where att.status = 'PRESENT'::public.attendance_status)::integer,
    count(*) filter (where att.status = 'LATE'::public.attendance_status)::integer,
    count(*) filter (where att.status = 'ABSENT'::public.attendance_status)::integer
  from public.assignments a
  left join public.attendance att on att.assignment_id = a.id
  where a.event_id = p_event_id
    and a.status in (
      'CONFIRMED'::public.assignment_status,
      'COMPLETED'::public.assignment_status
    );
end;
$$;

create or replace function public.set_attendance(
  p_assignment_id uuid,
  p_status public.attendance_status,
  p_notes text default null
)
returns table (
  assignment_id uuid,
  event_id uuid,
  worker_id uuid,
  attendance_status public.attendance_status,
  marked_by uuid,
  marker_role public.app_role,
  marked_at timestamptz,
  notes text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.assignments%rowtype;
  event_record public.events%rowtype;
  actor_role public.app_role;
begin
  actor_role := private.current_actor_role();

  if actor_role is null then
    raise exception 'authentication required';
  end if;

  select *
  into assignment_record
  from public.assignments
  where id = p_assignment_id
  for update;

  if assignment_record.id is null then
    raise exception 'assignment not found';
  end if;

  if assignment_record.status not in (
    'CONFIRMED'::public.assignment_status,
    'COMPLETED'::public.assignment_status
  ) then
    raise exception 'attendance is allowed only for confirmed or completed assignments';
  end if;

  select *
  into event_record
  from public.events
  where id = assignment_record.event_id
  for update;

  if event_record.event_status in (
    'DRAFT'::public.event_status,
    'CANCELLED'::public.event_status
  ) then
    raise exception 'attendance is unavailable for this event status';
  end if;

  if not private.can_set_attendance(event_record.id, event_record.event_status) then
    raise exception 'not authorized to set attendance';
  end if;

  insert into public.attendance (
    assignment_id,
    event_id,
    worker_id,
    status,
    marked_by,
    marker_role,
    marked_at,
    notes
  )
  values (
    assignment_record.id,
    assignment_record.event_id,
    assignment_record.worker_id,
    p_status,
    auth.uid(),
    actor_role,
    now(),
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  on conflict on constraint attendance_pkey do update
  set status = excluded.status,
      marked_by = excluded.marked_by,
      marker_role = excluded.marker_role,
      marked_at = excluded.marked_at,
      notes = excluded.notes;

  return query
  select
    att.assignment_id,
    att.event_id,
    att.worker_id,
    att.status,
    att.marked_by,
    att.marker_role,
    att.marked_at,
    att.notes
  from public.attendance att
  where att.assignment_id = assignment_record.id;
end;
$$;

alter table public.attendance enable row level security;
alter table public.attendance force row level security;
alter table public.attendance_history enable row level security;
alter table public.attendance_history force row level security;

revoke all on public.attendance from public, anon, authenticated;
revoke all on public.attendance_history from public, anon, authenticated;

grant select on public.attendance to authenticated;
grant select on public.attendance_history to authenticated;
grant all on public.attendance to service_role;
grant all on public.attendance_history to service_role;

revoke all on function public.field_event_list() from public, anon;
revoke all on function public.event_attendance_roster(uuid, text) from public, anon;
revoke all on function public.event_attendance_counters(uuid) from public, anon;
revoke all on function public.set_attendance(uuid, public.attendance_status, text) from public, anon;

grant execute on function public.field_event_list() to authenticated;
grant execute on function public.event_attendance_roster(uuid, text) to authenticated;
grant execute on function public.event_attendance_counters(uuid) to authenticated;
grant execute on function public.set_attendance(uuid, public.attendance_status, text) to authenticated;

create policy attendance_select_own_worker
  on public.attendance
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy attendance_select_event_operations
  on public.attendance
  for select
  to authenticated
  using (private.can_view_event_operations(event_id));

create policy attendance_history_select_own_worker
  on public.attendance_history
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy attendance_history_select_event_operations
  on public.attendance_history
  for select
  to authenticated
  using (private.can_view_event_operations(event_id));

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'attendance'
  ) then
    alter publication supabase_realtime add table public.attendance;
  end if;
end
$$;
