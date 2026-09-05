create or replace function public.worker_event_board()
returns table (
  id uuid,
  title text,
  event_type text,
  venue_name text,
  maps_url text,
  event_date date,
  reporting_at timestamptz,
  work_starts_at timestamptz,
  expected_ends_at timestamptz,
  required_worker_count integer,
  active_confirmed_count integer,
  vacancy_count integer,
  daily_wage numeric(12, 2),
  currency_code text,
  event_status public.event_status,
  recruitment_status public.recruitment_status,
  tier_strategy public.tier_strategy,
  worker_category public.worker_category,
  own_tier_opens_at timestamptz,
  open_categories public.worker_category[],
  action_state text,
  action_label text
)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as (
    select p.id, wp.category
    from public.profiles p
    join public.worker_profiles wp on wp.user_id = p.id
    where p.id = auth.uid()
      and p.role = 'WORKER'::public.app_role
      and p.account_status = 'ACTIVE'::public.account_status
  ),
  visible_events as (
    select e.*
    from public.events e
    where e.event_status <> 'DRAFT'::public.event_status
  ),
  projected as (
    select
      e.*,
      v.category as viewer_category,
      private.active_confirmed_assignment_count(e.id) as confirmed_count,
      (
        select r.opens_at
        from public.event_tier_release_rules r
        where r.event_id = e.id
          and r.category = v.category
      ) as viewer_opens_at,
      coalesce(
        (
          select array_agg(r.category order by private.category_rank(r.category))
          from public.event_tier_release_rules r
          where r.event_id = e.id
            and r.opens_at <= now()
        ),
        array[]::public.worker_category[]
      ) as currently_open_categories
    from visible_events e
    cross join viewer v
  )
  select
    p.id,
    p.title,
    p.event_type,
    p.venue_name,
    p.maps_url,
    p.event_date,
    p.reporting_at,
    p.work_starts_at,
    p.expected_ends_at,
    p.required_worker_count,
    p.confirmed_count,
    greatest(p.required_worker_count - p.confirmed_count, 0),
    p.daily_wage,
    p.currency_code,
    p.event_status,
    p.recruitment_status,
    p.tier_strategy,
    p.viewer_category,
    p.viewer_opens_at,
    p.currently_open_categories,
    case
      when p.event_status = 'CANCELLED'::public.event_status then 'CANCELLED'
      when p.event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) then 'COMPLETED'
      when p.recruitment_status = 'FULL'::public.recruitment_status then 'FULL'
      when p.recruitment_status = 'CLOSED'::public.recruitment_status then 'CLOSED'
      when public.is_worker_tier_eligible(p.id, auth.uid(), now()) then 'AVAILABLE'
      else 'LOCKED'
    end,
    case
      when p.event_status = 'CANCELLED'::public.event_status then 'Cancelled'
      when p.event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) then 'Completed'
      when p.recruitment_status = 'FULL'::public.recruitment_status then 'Join Waitlist'
      when p.recruitment_status = 'CLOSED'::public.recruitment_status then 'Closed'
      when public.is_worker_tier_eligible(p.id, auth.uid(), now()) then 'Apply'
      else 'Locked'
    end
  from projected p
  order by p.reporting_at, p.title;
$$;

create or replace function public.worker_event_detail(
  p_event_id uuid
)
returns table (
  id uuid,
  title text,
  event_type text,
  venue_name text,
  maps_url text,
  event_date date,
  reporting_at timestamptz,
  work_starts_at timestamptz,
  expected_ends_at timestamptz,
  required_worker_count integer,
  active_confirmed_count integer,
  vacancy_count integer,
  daily_wage numeric(12, 2),
  currency_code text,
  event_status public.event_status,
  recruitment_status public.recruitment_status,
  tier_strategy public.tier_strategy,
  worker_category public.worker_category,
  own_tier_opens_at timestamptz,
  open_categories public.worker_category[],
  action_state text,
  action_label text,
  instructions text,
  dress_code text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    board.id,
    board.title,
    board.event_type,
    board.venue_name,
    board.maps_url,
    board.event_date,
    board.reporting_at,
    board.work_starts_at,
    board.expected_ends_at,
    board.required_worker_count,
    board.active_confirmed_count,
    board.vacancy_count,
    board.daily_wage,
    board.currency_code,
    board.event_status,
    board.recruitment_status,
    board.tier_strategy,
    board.worker_category,
    board.own_tier_opens_at,
    board.open_categories,
    board.action_state,
    board.action_label,
    e.instructions,
    e.dress_code
  from public.worker_event_board() board
  join public.events e on e.id = board.id
  where board.id = p_event_id;
$$;

revoke all on function public.worker_event_board() from public, anon;
revoke all on function public.worker_event_detail(uuid) from public, anon;

grant execute on function public.worker_event_board() to authenticated;
grant execute on function public.worker_event_detail(uuid) to authenticated;
