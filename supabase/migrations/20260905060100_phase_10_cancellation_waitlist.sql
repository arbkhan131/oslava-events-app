create table public.waitlist_entries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  status public.waitlist_status not null default 'WAITING',
  joined_at timestamptz not null default now(),
  category_at_join public.worker_category not null,
  promoted_assignment_id uuid references public.assignments(id) on delete restrict,
  promoted_at timestamptz,
  withdrawn_at timestamptz,
  skipped_at timestamptz,
  skip_reason text,
  penalty_applies boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint waitlist_entries_terminal_pair check (
    (status = 'WAITING'::public.waitlist_status and promoted_at is null and withdrawn_at is null and skipped_at is null)
    or (status = 'PROMOTED'::public.waitlist_status and promoted_at is not null and promoted_assignment_id is not null)
    or (status = 'WITHDRAWN'::public.waitlist_status and withdrawn_at is not null)
    or (status = 'SKIPPED'::public.waitlist_status and skipped_at is not null and btrim(coalesce(skip_reason, '')) <> '')
    or (status = 'EXPIRED'::public.waitlist_status)
  )
);

create unique index waitlist_entries_one_waiting_worker_event_idx
  on public.waitlist_entries(event_id, worker_id)
  where status = 'WAITING'::public.waitlist_status;

create index waitlist_entries_event_waiting_idx
  on public.waitlist_entries(event_id, status, joined_at)
  where status = 'WAITING'::public.waitlist_status;

alter table public.assignments
  add constraint assignments_waitlist_entry_fk
  foreign key (waitlist_entry_id) references public.waitlist_entries(id) on delete restrict;

create table public.cancellations (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete restrict,
  event_id uuid not null references public.events(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  actor_role public.app_role not null,
  cancellation_type text not null,
  reason text not null,
  idempotency_key text not null,
  requested_at timestamptz not null default now(),
  deadline_at timestamptz not null,
  within_deadline boolean not null,
  promoted_assignment_id uuid references public.assignments(id) on delete restrict,
  refill_result text,
  created_at timestamptz not null default now(),
  constraint cancellations_reason_not_blank check (btrim(reason) <> ''),
  constraint cancellations_idempotency_not_blank check (btrim(idempotency_key) <> ''),
  constraint cancellations_type_valid check (cancellation_type in ('WORKER', 'MANAGEMENT', 'EVENT')),
  unique (worker_id, idempotency_key)
);

create index cancellations_assignment_idx on public.cancellations(assignment_id, created_at desc);
create index cancellations_worker_idx on public.cancellations(worker_id, created_at desc);

alter table public.waitlist_entries enable row level security;
alter table public.waitlist_entries force row level security;
alter table public.cancellations enable row level security;
alter table public.cancellations force row level security;

revoke all on public.waitlist_entries from public, anon, authenticated;
revoke all on public.cancellations from public, anon, authenticated;
grant select on public.waitlist_entries to authenticated;
grant select on public.cancellations to authenticated;
grant all on public.waitlist_entries to service_role;
grant all on public.cancellations to service_role;

create policy waitlist_entries_select_own
  on public.waitlist_entries
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy waitlist_entries_select_event_managers
  on public.waitlist_entries
  for select
  to authenticated
  using (private.can_manage_events());

create policy cancellations_select_own
  on public.cancellations
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy cancellations_select_event_managers
  on public.cancellations
  for select
  to authenticated
  using (private.can_manage_events());

create or replace function private.waitlist_position(p_entry_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select ranked.position
  from (
    select
      wl.id,
      row_number() over (
        partition by wl.event_id
        order by private.category_rank(wp.category), wl.joined_at, wl.id
      )::integer as position
    from public.waitlist_entries wl
    join public.worker_profiles wp on wp.user_id = wl.worker_id
    where wl.status = 'WAITING'::public.waitlist_status
  ) ranked
  where ranked.id = p_entry_id;
$$;

create or replace function private.notify_vacancy_reopened_internal(
  p_event_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_title text;
  inserted_count integer := 0;
begin
  select title
  into event_title
  from public.events
  where id = p_event_id
    and event_status in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status)
    and recruitment_status = 'OPEN'::public.recruitment_status;

  if event_title is null then
    return 0;
  end if;

  insert into public.notifications (
    recipient_id,
    notification_type,
    title,
    body,
    related_event_id,
    deduplication_key
  )
  select
    p.id,
    'VACANCY_REOPENED'::public.notification_type,
    'Vacancy reopened',
    event_title || ' has an available seat again.',
    p_event_id,
    'vacancy-reopened:' || p_event_id::text || ':' || p.id::text
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where p.role = 'WORKER'::public.app_role
    and p.account_status = 'ACTIVE'::public.account_status
    and wp.category is not null
    and public.is_worker_tier_eligible(p_event_id, p.id, now())
    and not exists (
      select 1
      from public.assignments a
      where a.event_id = p_event_id
        and a.worker_id = p.id
        and a.status = 'CONFIRMED'::public.assignment_status
    )
    and not public.has_booking_conflict(p.id, p_event_id)
  on conflict (recipient_id, deduplication_key) do nothing;

  get diagnostics inserted_count = row_count;

  return inserted_count;
end;
$$;

create or replace function public.notify_vacancy_reopened(
  p_event_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can notify reopened vacancies';
  end if;

  return private.notify_vacancy_reopened_internal(p_event_id);
end;
$$;

create or replace function public.join_waitlist(
  p_event_id uuid,
  p_idempotency_key text,
  p_acknowledged_requirement_ids uuid[] default array[]::uuid[]
)
returns table (
  waitlist_entry_id uuid,
  status public.waitlist_status,
  result_detail_code text,
  queue_position integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  worker_record record;
  event_record public.events%rowtype;
  existing_entry public.waitlist_entries%rowtype;
  new_entry public.waitlist_entries%rowtype;
  missing_acknowledgements integer;
begin
  if btrim(coalesce(p_idempotency_key, '')) = '' then
    raise exception 'idempotency key is required';
  end if;

  select *
  into existing_entry
  from public.waitlist_entries wl
  where wl.worker_id = auth.uid()
    and wl.event_id = p_event_id
    and wl.status in ('WAITING'::public.waitlist_status, 'PROMOTED'::public.waitlist_status);

  if existing_entry.id is not null then
    return query
    select existing_entry.id, existing_entry.status, 'DUPLICATE', private.waitlist_position(existing_entry.id);
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
    or worker_record.account_status <> 'ACTIVE'::public.account_status
    or not private.required_profile_complete(auth.uid()) then
    return query select null::uuid, null::public.waitlist_status, 'ACTIVE_COMPLETE_WORKER_REQUIRED', null::integer;
    return;
  end if;

  select *
  into event_record
  from public.events
  where id = p_event_id
  for update;

  if event_record.id is null
    or event_record.event_status not in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status)
    or event_record.recruitment_status <> 'FULL'::public.recruitment_status then
    return query select null::uuid, null::public.waitlist_status, 'EVENT_NOT_FULL', null::integer;
    return;
  end if;

  if not public.is_worker_tier_eligible(p_event_id, auth.uid(), now()) then
    return query select null::uuid, null::public.waitlist_status, 'TIER_NOT_OPEN', null::integer;
    return;
  end if;

  if exists (
    select 1 from public.assignments a
    where a.event_id = p_event_id
      and a.worker_id = auth.uid()
      and a.status = 'CONFIRMED'::public.assignment_status
  ) then
    return query select null::uuid, null::public.waitlist_status, 'ACTIVE_ASSIGNMENT_EXISTS', null::integer;
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
    return query select null::uuid, null::public.waitlist_status, 'MISSING_ACKNOWLEDGEMENT', null::integer;
    return;
  end if;

  if public.has_booking_conflict(auth.uid(), p_event_id) then
    return query select null::uuid, null::public.waitlist_status, 'ONE_HOUR_CONFLICT', null::integer;
    return;
  end if;

  insert into public.waitlist_entries (
    event_id,
    worker_id,
    category_at_join
  )
  values (
    p_event_id,
    auth.uid(),
    worker_record.category
  )
  returning * into new_entry;

  insert into public.notifications (
    recipient_id,
    notification_type,
    title,
    body,
    related_event_id,
    deduplication_key
  )
  values (
    auth.uid(),
    'WAITLIST_JOINED'::public.notification_type,
    'Waitlist joined',
    event_record.title || ' waitlist joined.',
    p_event_id,
    'waitlist-joined:' || new_entry.id::text
  )
  on conflict (recipient_id, deduplication_key) do nothing;

  return query
  select new_entry.id, new_entry.status, null::text, private.waitlist_position(new_entry.id);
exception
  when unique_violation then
    select *
    into existing_entry
    from public.waitlist_entries wl
    where wl.worker_id = auth.uid()
      and wl.event_id = p_event_id
      and wl.status = 'WAITING'::public.waitlist_status;

    return query
    select existing_entry.id, existing_entry.status, 'DUPLICATE', private.waitlist_position(existing_entry.id);
end;
$$;

create or replace function private.promote_one_waitlist_candidate(p_event_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate public.waitlist_entries%rowtype;
  current_category public.worker_category;
  event_record public.events%rowtype;
  new_assignment_id uuid;
begin
  select *
  into event_record
  from public.events
  where id = p_event_id
  for update;

  if event_record.id is null
    or event_record.recruitment_status = 'CLOSED'::public.recruitment_status
    or private.active_confirmed_assignment_count(p_event_id) >= event_record.required_worker_count then
    return null;
  end if;

  for candidate in
    select wl.*
    from public.waitlist_entries wl
    join public.worker_profiles wp on wp.user_id = wl.worker_id
    join public.profiles p on p.id = wl.worker_id
    where wl.event_id = p_event_id
      and wl.status = 'WAITING'::public.waitlist_status
    order by private.category_rank(wp.category), wl.joined_at, wl.id
    for update of wl skip locked
  loop
    select wp.category
    into current_category
    from public.profiles p
    join public.worker_profiles wp on wp.user_id = p.id
    where p.id = candidate.worker_id
      and p.role = 'WORKER'::public.app_role
      and p.account_status = 'ACTIVE'::public.account_status
      and private.required_profile_complete(p.id);

    if current_category is null then
      update public.waitlist_entries
      set status = 'SKIPPED',
          skipped_at = now(),
          skip_reason = 'WORKER_NOT_ACTIVE_OR_COMPLETE',
          updated_at = now()
      where id = candidate.id;
      continue;
    end if;

    if not public.is_worker_tier_eligible(p_event_id, candidate.worker_id, now()) then
      update public.waitlist_entries
      set status = 'SKIPPED',
          skipped_at = now(),
          skip_reason = 'TIER_NOT_OPEN',
          updated_at = now()
      where id = candidate.id;
      continue;
    end if;

    if public.has_booking_conflict(candidate.worker_id, p_event_id) then
      update public.waitlist_entries
      set status = 'SKIPPED',
          skipped_at = now(),
          skip_reason = 'ONE_HOUR_CONFLICT',
          updated_at = now()
      where id = candidate.id;
      continue;
    end if;

    begin
      insert into public.assignments (
        event_id,
        worker_id,
        status,
        source,
        category_at_confirmation,
        waitlist_entry_id
      )
      values (
        p_event_id,
        candidate.worker_id,
        'CONFIRMED',
        'WAITLIST_PROMOTION',
        current_category,
        candidate.id
      )
      returning id into new_assignment_id;
    exception
      when unique_violation then
        update public.waitlist_entries
        set status = 'SKIPPED',
            skipped_at = now(),
            skip_reason = 'ACTIVE_ASSIGNMENT_EXISTS',
            updated_at = now()
        where id = candidate.id;
        continue;
    end;

    update public.waitlist_entries
    set status = 'PROMOTED',
        promoted_assignment_id = new_assignment_id,
        promoted_at = now(),
        updated_at = now()
    where id = candidate.id;

    insert into public.notifications (
      recipient_id,
      notification_type,
      title,
      body,
      related_event_id,
      deduplication_key
    )
    values (
      candidate.worker_id,
      'WAITLIST_PROMOTED'::public.notification_type,
      'Waitlist promoted',
      event_record.title || ' is now confirmed from the waitlist.',
      p_event_id,
      'waitlist-promoted:' || candidate.id::text
    )
    on conflict (recipient_id, deduplication_key) do nothing;

    if private.active_confirmed_assignment_count(p_event_id) >= event_record.required_worker_count then
      update public.events
      set recruitment_status = 'FULL'::public.recruitment_status,
          updated_at = now()
      where id = p_event_id
        and recruitment_status = 'OPEN'::public.recruitment_status;
    end if;

    return new_assignment_id;
  end loop;

  return null;
end;
$$;

create or replace function public.promote_waitlist(p_event_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  promoted_count integer := 0;
  promoted_id uuid;
begin
  if not private.can_manage_events() and auth.role() <> 'service_role' then
    raise exception 'only Admin, Super Admin, or service role can promote waitlist';
  end if;

  loop
    promoted_id := private.promote_one_waitlist_candidate(p_event_id);
    exit when promoted_id is null;
    promoted_count := promoted_count + 1;
  end loop;

  if promoted_count = 0 then
    perform private.notify_vacancy_reopened_internal(p_event_id);
  end if;

  return promoted_count;
end;
$$;

create or replace function public.withdraw_waitlist(
  p_waitlist_entry_id uuid,
  p_reason text default 'Worker withdrew from waitlist'
)
returns public.waitlist_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry_record public.waitlist_entries%rowtype;
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into entry_record
  from public.waitlist_entries
  where id = p_waitlist_entry_id
    and worker_id = auth.uid()
  for update;

  if entry_record.id is null then
    raise exception 'waitlist entry not found';
  end if;

  if entry_record.status = 'PROMOTED'::public.waitlist_status then
    raise exception 'promoted waitlist entries use normal cancellation rules';
  end if;

  if entry_record.status <> 'WAITING'::public.waitlist_status then
    return entry_record.status;
  end if;

  update public.waitlist_entries
  set status = 'WITHDRAWN',
      withdrawn_at = now(),
      penalty_applies = false,
      updated_at = now()
  where id = entry_record.id
  returning status into entry_record.status;

  return entry_record.status;
end;
$$;

create or replace function public.cancel_assignment(
  p_assignment_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns table (
  cancellation_id uuid,
  assignment_id uuid,
  event_id uuid,
  status public.assignment_status,
  promoted_assignment_id uuid,
  recruitment_status public.recruitment_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.assignments%rowtype;
  event_record public.events%rowtype;
  existing_cancellation public.cancellations%rowtype;
  new_cancellation public.cancellations%rowtype;
  promoted_id uuid;
  deadline_at timestamptz;
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  if btrim(coalesce(p_idempotency_key, '')) = '' then
    raise exception 'idempotency key is required';
  end if;

  select *
  into existing_cancellation
  from public.cancellations c
  where c.worker_id = auth.uid()
    and c.idempotency_key = p_idempotency_key;

  if existing_cancellation.id is not null then
    return query
    select
      existing_cancellation.id,
      existing_cancellation.assignment_id,
      existing_cancellation.event_id,
      a.status,
      existing_cancellation.promoted_assignment_id,
      e.recruitment_status
    from public.assignments a
    join public.events e on e.id = a.event_id
    where a.id = existing_cancellation.assignment_id;
    return;
  end if;

  select *
  into assignment_record
  from public.assignments
  where id = p_assignment_id
    and worker_id = auth.uid()
  for update;

  if assignment_record.id is null then
    raise exception 'assignment not found';
  end if;

  if assignment_record.status <> 'CONFIRMED'::public.assignment_status then
    raise exception 'only confirmed assignments can be cancelled';
  end if;

  select *
  into event_record
  from public.events
  where id = assignment_record.event_id
  for update;

  deadline_at := event_record.reporting_at - interval '1 hour';

  if now() > deadline_at then
    raise exception 'CANCELLATION_LOCKED';
  end if;

  update public.assignments
  set status = 'CANCELLED',
      updated_at = now()
  where id = assignment_record.id
  returning * into assignment_record;

  if event_record.recruitment_status = 'FULL'::public.recruitment_status
    and event_record.event_status in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status) then
    update public.events
    set recruitment_status = 'OPEN'::public.recruitment_status,
        updated_at = now()
    where id = event_record.id;
  end if;

  promoted_id := private.promote_one_waitlist_candidate(event_record.id);

  insert into public.cancellations (
    assignment_id,
    event_id,
    worker_id,
    actor_id,
    actor_role,
    cancellation_type,
    reason,
    idempotency_key,
    deadline_at,
    within_deadline,
    promoted_assignment_id,
    refill_result
  )
  values (
    assignment_record.id,
    assignment_record.event_id,
    assignment_record.worker_id,
    auth.uid(),
    private.current_actor_role(),
    'WORKER',
    p_reason,
    p_idempotency_key,
    deadline_at,
    true,
    promoted_id,
    case when promoted_id is null then 'NO_PROMOTION' else 'PROMOTED' end
  )
  returning * into new_cancellation;

  if promoted_id is null then
    perform private.notify_vacancy_reopened_internal(event_record.id);
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
    assignment_record.worker_id,
    'EVENT_CANCELLED'::public.notification_type,
    'Assignment cancelled',
    event_record.title || ' assignment cancelled.',
    event_record.id,
    'assignment-cancelled:' || new_cancellation.id::text
  )
  on conflict (recipient_id, deduplication_key) do nothing;

  return query
  select
    new_cancellation.id,
    assignment_record.id,
    event_record.id,
    assignment_record.status,
    promoted_id,
    (select e.recruitment_status from public.events e where e.id = event_record.id);
end;
$$;

create or replace function public.worker_my_work()
returns table (
  assignment_id uuid,
  event_id uuid,
  title text,
  venue_name text,
  reporting_at timestamptz,
  expected_ends_at timestamptz,
  assignment_status public.assignment_status,
  cancellation_deadline_at timestamptz,
  can_cancel boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    e.id,
    e.title,
    e.venue_name,
    e.reporting_at,
    e.expected_ends_at,
    a.status,
    e.reporting_at - interval '1 hour',
    a.status = 'CONFIRMED'::public.assignment_status
      and now() <= e.reporting_at - interval '1 hour'
  from public.assignments a
  join public.events e on e.id = a.event_id
  where a.worker_id = auth.uid()
  order by e.reporting_at desc;
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
      exists (
        select 1
        from public.waitlist_entries own_waitlist
        where own_waitlist.event_id = e.id
          and own_waitlist.worker_id = v.id
          and own_waitlist.status = 'WAITING'::public.waitlist_status
      ) as has_waiting_waitlist,
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
      when p.has_waiting_waitlist then 'WAITLISTED'
      when p.event_status = 'CANCELLED'::public.event_status then 'CANCELLED'
      when p.event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) then 'COMPLETED'
      when p.recruitment_status = 'FULL'::public.recruitment_status then 'FULL'
      when p.recruitment_status = 'CLOSED'::public.recruitment_status then 'CLOSED'
      when public.is_worker_tier_eligible(p.id, p.viewer_id, now()) then 'AVAILABLE'
      else 'LOCKED'
    end,
    case
      when p.has_confirmed_assignment then 'Confirmed'
      when p.has_waiting_waitlist then 'Waitlisted'
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

revoke all on function public.join_waitlist(uuid, text, uuid[]) from public, anon;
revoke all on function public.promote_waitlist(uuid) from public, anon;
revoke all on function public.withdraw_waitlist(uuid, text) from public, anon;
revoke all on function public.cancel_assignment(uuid, text, text) from public, anon;
revoke all on function public.worker_my_work() from public, anon;

grant execute on function public.join_waitlist(uuid, text, uuid[]) to authenticated;
grant execute on function public.promote_waitlist(uuid) to authenticated, service_role;
grant execute on function public.withdraw_waitlist(uuid, text) to authenticated;
grant execute on function public.cancel_assignment(uuid, text, text) to authenticated;
grant execute on function public.worker_my_work() to authenticated;
