-- Phase 15: authorized audit/history reads and MVP event reports.

create index if not exists audit_logs_related_event_created_idx
  on public.audit_logs(related_event_id, created_at desc)
  where related_event_id is not null;

create index if not exists audit_logs_entity_created_idx
  on public.audit_logs(entity_type, entity_id, created_at desc);

create or replace function public.event_report_summary(p_event_id uuid)
returns table (
  event_id uuid,
  title text,
  event_type text,
  venue_name text,
  event_date date,
  reporting_at timestamptz,
  work_starts_at timestamptz,
  expected_ends_at timestamptz,
  required_worker_count integer,
  confirmed_worker_count integer,
  daily_wage numeric,
  allowance_total numeric,
  total_worker_pay_display numeric,
  currency_code char(3),
  event_status public.event_status,
  recruitment_status public.recruitment_status,
  attendance_total integer,
  attendance_not_marked integer,
  attendance_present integer,
  attendance_late integer,
  attendance_absent integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_view_event_operations(p_event_id) then
    raise exception 'not authorized to view event reports';
  end if;

  return query
  with confirmed as (
    select count(*)::integer as count
    from public.assignments a
    where a.event_id = p_event_id
      and a.status in (
        'CONFIRMED'::public.assignment_status,
        'COMPLETED'::public.assignment_status
      )
  ),
  allowances as (
    select coalesce(sum(ea.amount), 0)::numeric as total
    from public.event_allowances ea
    where ea.event_id = p_event_id
  ),
  attendance_counts as (
    select *
    from public.event_attendance_counters(p_event_id)
  )
  select
    e.id,
    e.title,
    e.event_type,
    e.venue_name,
    e.event_date,
    e.reporting_at,
    e.work_starts_at,
    e.expected_ends_at,
    e.required_worker_count,
    confirmed.count,
    e.daily_wage,
    allowances.total,
    e.daily_wage + allowances.total,
    e.currency_code,
    e.event_status,
    e.recruitment_status,
    attendance_counts.total,
    attendance_counts.not_marked,
    attendance_counts.present,
    attendance_counts.late,
    attendance_counts.absent
  from public.events e
  cross join confirmed
  cross join allowances
  cross join attendance_counts
  where e.id = p_event_id;
end;
$$;

create or replace function public.event_staffing_report(p_event_id uuid)
returns table (
  assignment_id uuid,
  worker_id uuid,
  worker_number bigint,
  full_name text,
  phone_e164 text,
  category_at_confirmation public.worker_category,
  assignment_status public.assignment_status,
  confirmed_at timestamptz,
  attendance_status public.attendance_status,
  attendance_marked_at timestamptz,
  attendance_notes text,
  daily_wage numeric,
  allowance_total numeric,
  total_pay_display numeric,
  currency_code char(3)
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_view_event_operations(p_event_id) then
    raise exception 'not authorized to view staffing reports';
  end if;

  return query
  with allowances as (
    select coalesce(sum(ea.amount), 0)::numeric as total
    from public.event_allowances ea
    where ea.event_id = p_event_id
  )
  select
    a.id,
    a.worker_id,
    p.worker_number,
    p.full_name,
    p.phone_e164,
    a.category_at_confirmation,
    a.status,
    a.confirmed_at,
    coalesce(att.status, 'NOT_MARKED'::public.attendance_status),
    att.marked_at,
    att.notes,
    e.daily_wage,
    allowances.total,
    e.daily_wage + allowances.total,
    e.currency_code
  from public.assignments a
  join public.events e on e.id = a.event_id
  join public.profiles p on p.id = a.worker_id
  left join public.attendance att on att.assignment_id = a.id
  cross join allowances
  where a.event_id = p_event_id
    and a.status in (
      'CONFIRMED'::public.assignment_status,
      'COMPLETED'::public.assignment_status
    )
  order by
    private.category_rank(a.category_at_confirmation),
    p.full_name,
    p.worker_number;
end;
$$;

create or replace function public.event_audit_history(
  p_event_id uuid,
  p_limit integer default 100
)
returns table (
  history_source text,
  action text,
  actor_id uuid,
  actor_role public.app_role,
  entity_type text,
  entity_id uuid,
  reason text,
  before_values jsonb,
  after_values jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  row_limit integer;
begin
  if not private.can_view_event_operations(p_event_id) then
    raise exception 'not authorized to view event audit history';
  end if;

  row_limit := least(greatest(coalesce(p_limit, 100), 1), 250);

  return query
  select *
  from (
    select
      'event_history'::text as history_source,
      eh.action,
      eh.actor_id,
      eh.actor_role,
      'event'::text as entity_type,
      eh.event_id as entity_id,
      eh.reason,
      eh.before_values,
      eh.after_values,
      eh.created_at
    from public.event_history eh
    where eh.event_id = p_event_id

    union all

    select
      'attendance_history'::text,
      'ATTENDANCE_CHANGED'::text,
      ah.actor_id,
      ah.actor_role,
      'attendance'::text,
      ah.assignment_id,
      null::text,
      jsonb_build_object('status', ah.old_status, 'notes', ah.old_notes),
      jsonb_build_object('status', ah.new_status, 'notes', ah.new_notes),
      ah.created_at
    from public.attendance_history ah
    where ah.event_id = p_event_id

    union all

    select
      'audit_logs'::text,
      al.action,
      al.actor_id,
      al.actor_role,
      al.entity_type,
      al.entity_id,
      al.reason,
      al.before_values,
      al.after_values,
      al.created_at
    from public.audit_logs al
    where al.related_event_id = p_event_id
       or (al.entity_type = 'event' and al.entity_id = p_event_id)
  ) history_rows
  order by history_rows.created_at desc
  limit row_limit;
end;
$$;

revoke all on function public.event_report_summary(uuid) from public, anon;
revoke all on function public.event_staffing_report(uuid) from public, anon;
revoke all on function public.event_audit_history(uuid, integer) from public, anon;

grant execute on function public.event_report_summary(uuid) to authenticated;
grant execute on function public.event_staffing_report(uuid) to authenticated;
grant execute on function public.event_audit_history(uuid, integer) to authenticated;
