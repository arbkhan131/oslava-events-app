create or replace function public.worker_event_detail_full(p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select * from public.worker_event_detail(p_event_id) limit 1
  ), own_waitlist as (
    select wl.id, wl.status, private.waitlist_position(wl.id) as queue_position
    from public.waitlist_entries wl
    where wl.event_id = p_event_id
      and wl.worker_id = auth.uid()
      and wl.status = 'WAITING'::public.waitlist_status
    order by wl.joined_at desc
    limit 1
  )
  select case when not exists(select 1 from base) then null::jsonb else jsonb_build_object(
    'id', b.id,
    'title', b.title,
    'event_type', b.event_type,
    'venue_name', b.venue_name,
    'maps_url', b.maps_url,
    'event_date', b.event_date,
    'reporting_at', b.reporting_at,
    'work_starts_at', b.work_starts_at,
    'expected_ends_at', b.expected_ends_at,
    'required_worker_count', b.required_worker_count,
    'active_confirmed_count', b.active_confirmed_count,
    'vacancy_count', b.vacancy_count,
    'daily_wage', b.daily_wage,
    'currency_code', b.currency_code,
    'event_status', b.event_status,
    'recruitment_status', b.recruitment_status,
    'tier_strategy', b.tier_strategy,
    'worker_category', b.worker_category,
    'own_tier_opens_at', b.own_tier_opens_at,
    'open_categories', b.open_categories,
    'action_state', b.action_state,
    'action_label', b.action_label,
    'instructions', b.instructions,
    'dress_code', b.dress_code,
    'own_waitlist_entry_id', (select id from own_waitlist),
    'own_waitlist_position', (select queue_position from own_waitlist),
    'requirements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'description', r.description,
        'is_mandatory', r.is_mandatory,
        'acknowledgement_required', r.acknowledgement_required,
        'extra_allowance_amount', r.extra_allowance_amount,
        'currency_code', r.currency_code,
        'display_order', r.display_order
      ) order by r.display_order, r.name)
      from public.event_requirements r
      where r.event_id = b.id
    ), '[]'::jsonb),
    'allowances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'label', a.label,
        'description', a.description,
        'amount', a.amount,
        'currency_code', a.currency_code,
        'display_order', a.display_order
      ) order by a.display_order, a.label)
      from public.event_allowances a
      where a.event_id = b.id
    ), '[]'::jsonb),
    'leaders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', l.user_id,
        'full_name', p.full_name,
        'leader_role', l.leader_role
      ) order by l.leader_role, p.full_name)
      from public.event_leaders l
      join public.profiles p on p.id = l.user_id
      where l.event_id = b.id
        and l.removed_at is null
    ), '[]'::jsonb)
  ) end
  from base b;
$$;

create or replace function public.worker_my_waitlist()
returns table (
  waitlist_entry_id uuid,
  event_id uuid,
  title text,
  venue_name text,
  reporting_at timestamptz,
  expected_ends_at timestamptz,
  status public.waitlist_status,
  queue_position integer,
  can_withdraw boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    wl.id,
    e.id,
    e.title,
    e.venue_name,
    e.reporting_at,
    e.expected_ends_at,
    wl.status,
    private.waitlist_position(wl.id),
    wl.status = 'WAITING'::public.waitlist_status
  from public.waitlist_entries wl
  join public.events e on e.id = wl.event_id
  where wl.worker_id = auth.uid()
    and wl.status in ('WAITING'::public.waitlist_status, 'PROMOTED'::public.waitlist_status, 'WITHDRAWN'::public.waitlist_status, 'SKIPPED'::public.waitlist_status, 'EXPIRED'::public.waitlist_status)
  order by e.reporting_at desc, wl.joined_at desc;
$$;

revoke all on function public.worker_event_detail_full(uuid) from public, anon;
revoke all on function public.worker_my_waitlist() from public, anon;
grant execute on function public.worker_event_detail_full(uuid) to authenticated;
grant execute on function public.worker_my_waitlist() to authenticated;