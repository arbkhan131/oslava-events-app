create table public.booking_arbitration_windows (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  status text not null default 'OPEN',
  allocated_at timestamptz,
  created_at timestamptz not null default now(),
  constraint booking_arbitration_windows_time_order check (opens_at < closes_at),
  constraint booking_arbitration_windows_status_valid check (status in ('OPEN', 'ALLOCATED'))
);

create index booking_arbitration_windows_open_idx
  on public.booking_arbitration_windows(event_id, closes_at)
  where status = 'OPEN';

create table public.booking_requests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key text not null,
  server_received_at timestamptz not null default now(),
  worker_category_snapshot public.worker_category,
  arbitration_window_id uuid references public.booking_arbitration_windows(id) on delete restrict,
  result public.booking_result not null default 'PENDING',
  result_detail_code text,
  resulting_assignment_id uuid,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint booking_requests_idempotency_not_blank check (btrim(idempotency_key) <> ''),
  constraint booking_requests_completed_pair check (
    (result = 'PENDING'::public.booking_result and completed_at is null)
    or (result <> 'PENDING'::public.booking_result and completed_at is not null)
  ),
  unique (worker_id, idempotency_key)
);

create index booking_requests_event_result_idx
  on public.booking_requests(event_id, result, server_received_at);

create index booking_requests_window_pending_idx
  on public.booking_requests(arbitration_window_id, server_received_at)
  where result = 'PENDING'::public.booking_result;

create table public.requirement_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
  event_requirement_id uuid not null references public.event_requirements(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  event_id uuid not null references public.events(id) on delete restrict,
  event_version integer not null,
  acknowledged_at timestamptz not null default now(),
  unique (booking_request_id, event_requirement_id)
);

alter table public.assignments
  add constraint assignments_booking_request_fk
  foreign key (booking_request_id) references public.booking_requests(id) on delete restrict;

alter table public.booking_requests
  add constraint booking_requests_resulting_assignment_fk
  foreign key (resulting_assignment_id) references public.assignments(id) on delete restrict;

alter table public.booking_arbitration_windows enable row level security;
alter table public.booking_arbitration_windows force row level security;
alter table public.booking_requests enable row level security;
alter table public.booking_requests force row level security;
alter table public.requirement_acknowledgements enable row level security;
alter table public.requirement_acknowledgements force row level security;

revoke all on public.booking_arbitration_windows from public, anon, authenticated;
revoke all on public.booking_requests from public, anon, authenticated;
revoke all on public.requirement_acknowledgements from public, anon, authenticated;

grant select on public.booking_requests to authenticated;
grant select on public.requirement_acknowledgements to authenticated;
grant all on public.booking_arbitration_windows to service_role;
grant all on public.booking_requests to service_role;
grant all on public.requirement_acknowledgements to service_role;

create policy booking_requests_select_own
  on public.booking_requests
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy booking_requests_select_event_managers
  on public.booking_requests
  for select
  to authenticated
  using (private.can_manage_events());

create policy requirement_acknowledgements_select_own
  on public.requirement_acknowledgements
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy requirement_acknowledgements_select_event_managers
  on public.requirement_acknowledgements
  for select
  to authenticated
  using (private.can_manage_events());

create or replace function private.required_profile_complete(p_worker_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.worker_profiles wp on wp.user_id = p.id
    where p.id = p_worker_id
      and p.role = 'WORKER'::public.app_role
      and p.account_status = 'ACTIVE'::public.account_status
      and p.worker_number is not null
      and p.profile_completed_at is not null
      and nullif(btrim(p.full_name), '') is not null
      and nullif(btrim(p.initials), '') is not null
      and nullif(btrim(p.phone_e164), '') is not null
      and nullif(btrim(coalesce(p.profile_photo_path, '')), '') is not null
      and wp.category is not null
      and wp.date_of_birth is not null
      and nullif(btrim(coalesce(wp.address, '')), '') is not null
      and nullif(btrim(coalesce(wp.native_place, '')), '') is not null
      and wp.height_cm is not null
      and nullif(btrim(coalesce(wp.education_status, '')), '') is not null
      and wp.has_previous_experience is not null
  );
$$;

create or replace function private.booking_result_row(p_request public.booking_requests)
returns table (
  booking_request_id uuid,
  result public.booking_result,
  result_detail_code text,
  assignment_id uuid,
  event_id uuid,
  vacancy_count integer
)
language sql
stable
set search_path = ''
as $$
  select
    p_request.id,
    p_request.result,
    p_request.result_detail_code,
    p_request.resulting_assignment_id,
    p_request.event_id,
    greatest(e.required_worker_count - private.active_confirmed_assignment_count(e.id), 0)
  from public.events e
  where e.id = p_request.event_id;
$$;

create or replace function private.complete_booking_request(
  p_request_id uuid,
  p_result public.booking_result,
  p_detail_code text default null,
  p_assignment_id uuid default null
)
returns public.booking_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_request public.booking_requests%rowtype;
begin
  update public.booking_requests
  set result = p_result,
      result_detail_code = p_detail_code,
      resulting_assignment_id = p_assignment_id,
      completed_at = now()
  where id = p_request_id
    and result = 'PENDING'::public.booking_result
  returning * into updated_request;

  if updated_request.id is null then
    select *
    into updated_request
    from public.booking_requests
    where id = p_request_id;
  end if;

  return updated_request;
end;
$$;

create or replace function private.confirm_booking_request(
  p_request public.booking_requests,
  p_late_cancellation_acknowledged boolean,
  p_acknowledged_requirement_ids uuid[]
)
returns public.booking_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_assignment_id uuid;
  event_record public.events%rowtype;
  confirmed_count integer;
  updated_request public.booking_requests%rowtype;
begin
  select *
  into event_record
  from public.events
  where id = p_request.event_id
  for update;

  if event_record.id is null then
    return private.complete_booking_request(p_request.id, 'EVENT_UNAVAILABLE', 'EVENT_NOT_FOUND');
  end if;

  confirmed_count := private.active_confirmed_assignment_count(event_record.id);

  if confirmed_count >= event_record.required_worker_count then
    return private.complete_booking_request(p_request.id, 'WAITLIST_AVAILABLE', 'FULL');
  end if;

  insert into public.assignments (
    event_id,
    worker_id,
    status,
    source,
    category_at_confirmation,
    booking_request_id,
    late_cancellation_acknowledged
  )
  values (
    p_request.event_id,
    p_request.worker_id,
    'CONFIRMED',
    'DIRECT_APPLY',
    p_request.worker_category_snapshot,
    p_request.id,
    p_late_cancellation_acknowledged
  )
  returning id into new_assignment_id;

  insert into public.requirement_acknowledgements (
    booking_request_id,
    event_requirement_id,
    worker_id,
    event_id,
    event_version
  )
  select
    p_request.id,
    requirement.id,
    p_request.worker_id,
    p_request.event_id,
    event_record.version
  from public.event_requirements requirement
  where requirement.event_id = p_request.event_id
    and requirement.acknowledgement_required
    and requirement.id = any(p_acknowledged_requirement_ids);

  if private.active_confirmed_assignment_count(event_record.id) >= event_record.required_worker_count then
    update public.events
    set recruitment_status = 'FULL'::public.recruitment_status,
        updated_at = now()
    where id = event_record.id
      and recruitment_status = 'OPEN'::public.recruitment_status;
  end if;

  insert into public.notifications (
    recipient_id,
    notification_type,
    title,
    body,
    related_event_id,
    deduplication_key
  )
  values (
    p_request.worker_id,
    'APPLICATION_CONFIRMED'::public.notification_type,
    'Application confirmed',
    event_record.title || ' is confirmed.',
    p_request.event_id,
    'application-confirmed:' || p_request.id::text
  )
  on conflict (recipient_id, deduplication_key) do nothing;

  updated_request := private.complete_booking_request(
    p_request.id,
    'CONFIRMED',
    null,
    new_assignment_id
  );

  return updated_request;
exception
  when unique_violation then
    return private.complete_booking_request(p_request.id, 'DUPLICATE', 'ACTIVE_ASSIGNMENT_EXISTS');
end;
$$;

create or replace function private.allocate_booking_window(
  p_window_id uuid,
  p_late_cancellation_acknowledged boolean,
  p_acknowledged_requirement_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  window_record public.booking_arbitration_windows%rowtype;
  candidate public.booking_requests%rowtype;
  winner_selected boolean := false;
begin
  select *
  into window_record
  from public.booking_arbitration_windows
  where id = p_window_id
  for update;

  if window_record.id is null or window_record.status = 'ALLOCATED' then
    return;
  end if;

  if now() < window_record.closes_at then
    perform pg_sleep(extract(epoch from window_record.closes_at - now()));
  end if;

  for candidate in
    select br.*
    from public.booking_requests br
    where br.arbitration_window_id = p_window_id
      and br.result = 'PENDING'::public.booking_result
    order by
      private.category_rank(br.worker_category_snapshot),
      br.server_received_at,
      br.id
    for update
  loop
    if not winner_selected
      and private.active_confirmed_assignment_count(candidate.event_id) <
          (select e.required_worker_count from public.events e where e.id = candidate.event_id) then
      perform private.confirm_booking_request(
        candidate,
        p_late_cancellation_acknowledged,
        p_acknowledged_requirement_ids
      );
      winner_selected := true;
    else
      perform private.complete_booking_request(candidate.id, 'WAITLIST_AVAILABLE', 'FULL');
    end if;
  end loop;

  update public.booking_arbitration_windows
  set status = 'ALLOCATED',
      allocated_at = now()
  where id = p_window_id;
end;
$$;

create or replace function private.get_or_create_booking_window(
  p_event_id uuid,
  p_received_at timestamptz
)
returns public.booking_arbitration_windows
language plpgsql
security definer
set search_path = ''
as $$
declare
  window_record public.booking_arbitration_windows%rowtype;
begin
  select *
  into window_record
  from public.booking_arbitration_windows
  where event_id = p_event_id
    and status = 'OPEN'
    and closes_at > p_received_at
  order by opens_at
  limit 1
  for update;

  if window_record.id is not null then
    return window_record;
  end if;

  insert into public.booking_arbitration_windows (
    event_id,
    opens_at,
    closes_at
  )
  values (
    p_event_id,
    p_received_at,
    p_received_at + interval '1 second'
  )
  returning * into window_record;

  return window_record;
end;
$$;

create or replace function public.apply_for_event(
  p_event_id uuid,
  p_idempotency_key text,
  p_acknowledged_requirement_ids uuid[] default array[]::uuid[],
  p_late_cancellation_acknowledged boolean default false
)
returns table (
  booking_request_id uuid,
  result public.booking_result,
  result_detail_code text,
  assignment_id uuid,
  event_id uuid,
  vacancy_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  worker_record record;
  event_record public.events%rowtype;
  existing_request public.booking_requests%rowtype;
  new_request public.booking_requests%rowtype;
  completed_request public.booking_requests%rowtype;
  missing_acknowledgements integer;
  confirmed_count integer;
  received_at timestamptz := now();
  arbitration_window public.booking_arbitration_windows%rowtype;
begin
  if btrim(coalesce(p_idempotency_key, '')) = '' then
    raise exception 'idempotency key is required';
  end if;

  select *
  into existing_request
  from public.booking_requests
  where worker_id = auth.uid()
    and idempotency_key = p_idempotency_key;

  if existing_request.id is not null then
    return query select * from private.booking_result_row(existing_request);
    return;
  end if;

  select p.id, p.role, p.account_status, wp.category
  into worker_record
  from public.profiles p
  left join public.worker_profiles wp on wp.user_id = p.id
  where p.id = auth.uid()
  for update of p;

  if worker_record.id is null
    or worker_record.role <> 'WORKER'::public.app_role
    or worker_record.account_status <> 'ACTIVE'::public.account_status then
    insert into public.booking_requests (
      event_id,
      worker_id,
      idempotency_key,
      server_received_at,
      worker_category_snapshot,
      result,
      result_detail_code,
      completed_at
    )
    values (
      p_event_id,
      auth.uid(),
      p_idempotency_key,
      received_at,
      worker_record.category,
      'RESTRICTED',
      'ACTIVE_WORKER_REQUIRED',
      now()
    )
    returning * into completed_request;

    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  insert into public.booking_requests (
    event_id,
    worker_id,
    idempotency_key,
    server_received_at,
    worker_category_snapshot
  )
  values (
    p_event_id,
    auth.uid(),
    p_idempotency_key,
    received_at,
    worker_record.category
  )
  returning * into new_request;

  select *
  into event_record
  from public.events
  where id = p_event_id
  for update;

  if event_record.id is null
    or event_record.event_status not in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status)
    or event_record.recruitment_status not in ('OPEN'::public.recruitment_status, 'FULL'::public.recruitment_status) then
    completed_request := private.complete_booking_request(new_request.id, 'EVENT_UNAVAILABLE', 'NOT_RECRUITABLE');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  if not private.required_profile_complete(auth.uid()) then
    completed_request := private.complete_booking_request(new_request.id, 'RESTRICTED', 'PROFILE_INCOMPLETE');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  if event_record.recruitment_status = 'FULL'::public.recruitment_status then
    completed_request := private.complete_booking_request(new_request.id, 'WAITLIST_AVAILABLE', 'FULL');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  if not public.is_worker_tier_eligible(p_event_id, auth.uid(), received_at) then
    completed_request := private.complete_booking_request(new_request.id, 'LOCKED', 'TIER_NOT_OPEN');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  if exists (
    select 1
    from public.assignments a
    where a.event_id = p_event_id
      and a.worker_id = auth.uid()
      and a.status = 'CONFIRMED'::public.assignment_status
  ) then
    completed_request := private.complete_booking_request(new_request.id, 'DUPLICATE', 'ACTIVE_ASSIGNMENT_EXISTS');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  select count(*)::integer
  into missing_acknowledgements
  from public.event_requirements requirement
  where requirement.event_id = p_event_id
    and requirement.is_mandatory
    and requirement.acknowledgement_required
    and not requirement.id = any(p_acknowledged_requirement_ids);

  if missing_acknowledgements > 0 then
    completed_request := private.complete_booking_request(new_request.id, 'INVALID_REQUIREMENTS', 'MISSING_ACKNOWLEDGEMENT');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  if public.has_booking_conflict(auth.uid(), p_event_id) then
    completed_request := private.complete_booking_request(new_request.id, 'CONFLICT', 'ONE_HOUR_CONFLICT');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  if received_at > event_record.reporting_at - interval '1 hour'
    and not p_late_cancellation_acknowledged then
    completed_request := private.complete_booking_request(new_request.id, 'ERROR', 'LATE_CANCELLATION_ACK_REQUIRED');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  confirmed_count := private.active_confirmed_assignment_count(p_event_id);

  if confirmed_count >= event_record.required_worker_count then
    completed_request := private.complete_booking_request(new_request.id, 'WAITLIST_AVAILABLE', 'FULL');
    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  if event_record.required_worker_count - confirmed_count = 1 then
    arbitration_window := private.get_or_create_booking_window(p_event_id, received_at);

    update public.booking_requests
    set arbitration_window_id = arbitration_window.id
    where id = new_request.id
    returning * into new_request;

    perform private.allocate_booking_window(
      arbitration_window.id,
      p_late_cancellation_acknowledged,
      p_acknowledged_requirement_ids
    );

    select *
    into completed_request
    from public.booking_requests
    where id = new_request.id;

    return query select * from private.booking_result_row(completed_request);
    return;
  end if;

  completed_request := private.confirm_booking_request(
    new_request,
    p_late_cancellation_acknowledged,
    p_acknowledged_requirement_ids
  );

  return query select * from private.booking_result_row(completed_request);
end;
$$;

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
      v.id as viewer_id,
      v.category as viewer_category,
      private.active_confirmed_assignment_count(e.id) as confirmed_count,
      exists (
        select 1
        from public.assignments own_assignment
        where own_assignment.event_id = e.id
          and own_assignment.worker_id = v.id
          and own_assignment.status = 'CONFIRMED'::public.assignment_status
      ) as has_confirmed_assignment,
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
      when p.has_confirmed_assignment then 'CONFIRMED'
      when p.event_status = 'CANCELLED'::public.event_status then 'CANCELLED'
      when p.event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) then 'COMPLETED'
      when p.recruitment_status = 'FULL'::public.recruitment_status then 'FULL'
      when p.recruitment_status = 'CLOSED'::public.recruitment_status then 'CLOSED'
      when public.is_worker_tier_eligible(p.id, p.viewer_id, now()) then 'AVAILABLE'
      else 'LOCKED'
    end,
    case
      when p.has_confirmed_assignment then 'Confirmed'
      when p.event_status = 'CANCELLED'::public.event_status then 'Cancelled'
      when p.event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) then 'Completed'
      when p.recruitment_status = 'FULL'::public.recruitment_status then 'Join Waitlist'
      when p.recruitment_status = 'CLOSED'::public.recruitment_status then 'Closed'
      when public.is_worker_tier_eligible(p.id, p.viewer_id, now()) then 'Apply'
      else 'Locked'
    end
  from projected p
  order by p.reporting_at, p.title;
$$;

revoke all on function public.apply_for_event(uuid, text, uuid[], boolean) from public, anon;
grant execute on function public.apply_for_event(uuid, text, uuid[], boolean) to authenticated;
