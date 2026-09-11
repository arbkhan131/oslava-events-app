-- R5: admin event detail payload and dashboard counters for the app.

create or replace function public.admin_event_detail(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  payload jsonb;
begin
  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can view admin events';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'title', e.title,
    'event_type', e.event_type,
    'venue_name', e.venue_name,
    'maps_url', e.maps_url,
    'event_date', e.event_date,
    'timezone_name', e.timezone_name,
    'reporting_at', e.reporting_at,
    'work_starts_at', e.work_starts_at,
    'expected_ends_at', e.expected_ends_at,
    'required_worker_count', e.required_worker_count,
    'daily_wage', e.daily_wage,
    'currency_code', e.currency_code,
    'instructions', e.instructions,
    'dress_code', e.dress_code,
    'event_status', e.event_status,
    'recruitment_status', e.recruitment_status,
    'tier_strategy', e.tier_strategy,
    'version', e.version,
    'confirmed_count', (
      select count(*)
      from public.assignments a
      where a.event_id = e.id
        and a.status = 'CONFIRMED'::public.assignment_status
    ),
    'waitlist_count', (
      select count(*)
      from public.waitlist_entries w
      where w.event_id = e.id
        and w.status = 'WAITING'::public.waitlist_status
    ),
    'open_review_flags', (
      select count(*)
      from public.assignment_review_flags f
      where f.state = 'OPEN'
        and (
          f.assignment_id in (
            select a.id from public.assignments a where a.event_id = e.id
          )
          or f.target_user_id in (
            select a.worker_id from public.assignments a where a.event_id = e.id
          )
        )
    ),
    'leaders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'user_id', l.user_id,
          'full_name', p.full_name,
          'leader_role', l.leader_role
        )
        order by l.leader_role, p.full_name
      )
      from public.event_leaders l
      join public.profiles p on p.id = l.user_id
      where l.event_id = e.id
        and l.removed_at is null
    ), '[]'::jsonb),
    'requirements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'name', r.name,
          'description', r.description,
          'is_mandatory', r.is_mandatory,
          'acknowledgement_required', r.acknowledgement_required,
          'extra_allowance_amount', r.extra_allowance_amount,
          'display_order', r.display_order
        )
        order by r.display_order, r.name
      )
      from public.event_requirements r
      where r.event_id = e.id
    ), '[]'::jsonb),
    'allowances', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'label', a.label,
          'description', a.description,
          'amount', a.amount,
          'display_order', a.display_order
        )
        order by a.display_order, a.label
      )
      from public.event_allowances a
      where a.event_id = e.id
    ), '[]'::jsonb)
  )
  into payload
  from public.events e
  where e.id = p_event_id;

  if payload is null then
    raise exception 'event not found';
  end if;

  return payload;
end;
$$;

create or replace function public.admin_event_dashboard()
returns table (
  today_event_count integer,
  draft_count integer,
  published_count integer,
  upcoming_count integer,
  in_progress_count integer,
  completed_count integer,
  open_review_flag_count integer,
  required_today_count integer,
  confirmed_today_count integer,
  vacant_today_count integer
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
  with today_events as (
    select *
    from public.events e
    where e.event_date = (now() at time zone 'Asia/Kolkata')::date
      and e.event_status <> 'CANCELLED'::public.event_status
  ),
  today_assignments as (
    select a.event_id, count(*)::integer as confirmed_count
    from public.assignments a
    join today_events e on e.id = a.event_id
    where a.status = 'CONFIRMED'::public.assignment_status
    group by a.event_id
  )
  select
    (select count(*)::integer from today_events),
    count(*) filter (where e.event_status = 'DRAFT'::public.event_status)::integer,
    count(*) filter (where e.event_status = 'PUBLISHED'::public.event_status)::integer,
    count(*) filter (where e.event_status = 'UPCOMING'::public.event_status)::integer,
    count(*) filter (where e.event_status = 'IN_PROGRESS'::public.event_status)::integer,
    count(*) filter (where e.event_status = 'COMPLETED'::public.event_status)::integer,
    (select count(*)::integer from public.assignment_review_flags f where f.state = 'OPEN'),
    coalesce((select sum(required_worker_count)::integer from today_events), 0),
    coalesce((select sum(confirmed_count)::integer from today_assignments), 0),
    greatest(
      coalesce((select sum(required_worker_count)::integer from today_events), 0)
      - coalesce((select sum(confirmed_count)::integer from today_assignments), 0),
      0
    )
  from public.events e;
end;
$$;

revoke all on function public.admin_event_detail(uuid) from public, anon;
revoke all on function public.admin_event_dashboard() from public, anon;
grant execute on function public.admin_event_detail(uuid) to authenticated;
grant execute on function public.admin_event_dashboard() to authenticated;
