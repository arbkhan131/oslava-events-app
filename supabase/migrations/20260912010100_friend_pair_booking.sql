-- Friend pair booking: lets one eligible worker book two seats atomically for
-- themself and an approved friend found by phone number.

alter table public.assignments
  drop constraint if exists assignments_source_valid;

alter table public.assignments
  add constraint assignments_source_valid check (
    source in ('DIRECT_APPLY', 'WAITLIST_PROMOTION', 'MANAGEMENT', 'FRIEND_BOOKING')
  );

create table if not exists public.friend_booking_requests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  requester_id uuid not null references public.profiles(id) on delete restrict,
  friend_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key text not null,
  acknowledged_requirement_ids uuid[] not null default '{}',
  late_cancellation_acknowledged boolean not null default false,
  requester_booking_request_id uuid references public.booking_requests(id) on delete restrict,
  friend_booking_request_id uuid references public.booking_requests(id) on delete restrict,
  requester_assignment_id uuid references public.assignments(id) on delete restrict,
  friend_assignment_id uuid references public.assignments(id) on delete restrict,
  result public.booking_result not null default 'PENDING',
  result_detail_code text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_booking_requests_not_self check (requester_id <> friend_id),
  constraint friend_booking_requests_idempotency_not_blank check (btrim(idempotency_key) <> ''),
  constraint friend_booking_requests_completed_pair check (
    (result = 'PENDING'::public.booking_result and completed_at is null)
    or (result <> 'PENDING'::public.booking_result and completed_at is not null)
  ),
  constraint friend_booking_requests_confirmed_pair check (
    result <> 'CONFIRMED'::public.booking_result
    or (
      requester_booking_request_id is not null
      and friend_booking_request_id is not null
      and requester_assignment_id is not null
      and friend_assignment_id is not null
    )
  ),
  unique (requester_id, idempotency_key)
);

create index if not exists friend_booking_requests_event_idx
  on public.friend_booking_requests(event_id, created_at desc);

create index if not exists friend_booking_requests_friend_idx
  on public.friend_booking_requests(friend_id, created_at desc);

alter table public.friend_booking_requests enable row level security;
alter table public.friend_booking_requests force row level security;

revoke all on public.friend_booking_requests from public, anon, authenticated;
grant select on public.friend_booking_requests to authenticated;
grant all on public.friend_booking_requests to service_role;

create policy friend_booking_requests_select_participant
  on public.friend_booking_requests
  for select
  to authenticated
  using (requester_id = auth.uid() or friend_id = auth.uid());

create policy friend_booking_requests_select_event_managers
  on public.friend_booking_requests
  for select
  to authenticated
  using (private.can_manage_events());

drop trigger if exists friend_booking_requests_touch_updated_at on public.friend_booking_requests;
create trigger friend_booking_requests_touch_updated_at
  before update on public.friend_booking_requests
  for each row execute function private.touch_updated_at();

create or replace function private.complete_friend_booking_request(
  p_pair_id uuid,
  p_result public.booking_result,
  p_detail_code text default null,
  p_requester_assignment_id uuid default null,
  p_friend_assignment_id uuid default null
)
returns public.friend_booking_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_pair public.friend_booking_requests%rowtype;
begin
  update public.friend_booking_requests
  set result = p_result,
      result_detail_code = p_detail_code,
      requester_assignment_id = coalesce(p_requester_assignment_id, requester_assignment_id),
      friend_assignment_id = coalesce(p_friend_assignment_id, friend_assignment_id),
      completed_at = clock_timestamp()
  where id = p_pair_id
    and result = 'PENDING'::public.booking_result
  returning * into updated_pair;

  if updated_pair.id is null then
    select * into updated_pair
    from public.friend_booking_requests
    where id = p_pair_id;
  end if;

  return updated_pair;
end;
$$;

revoke all on function private.complete_friend_booking_request(uuid, public.booking_result, text, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.friend_booking_result_row(p_pair public.friend_booking_requests)
returns table (
  friend_booking_request_id uuid,
  result public.booking_result,
  result_detail_code text,
  event_id uuid,
  requester_id uuid,
  friend_id uuid,
  requester_booking_request_id uuid,
  friend_booking_request_id_inner uuid,
  requester_assignment_id uuid,
  friend_assignment_id uuid,
  vacancy_count integer
)
language sql
stable
set search_path = ''
as $$
  select
    p_pair.id,
    p_pair.result,
    p_pair.result_detail_code,
    p_pair.event_id,
    p_pair.requester_id,
    p_pair.friend_id,
    p_pair.requester_booking_request_id,
    p_pair.friend_booking_request_id,
    p_pair.requester_assignment_id,
    p_pair.friend_assignment_id,
    greatest(e.required_worker_count - private.active_confirmed_assignment_count(e.id), 0)
  from public.events e
  where e.id = p_pair.event_id;
$$;

revoke all on function private.friend_booking_result_row(public.friend_booking_requests)
  from public, anon, authenticated;

create or replace function public.search_bookable_friend_workers(
  p_phone_query text,
  p_event_id uuid default null,
  p_limit integer default 10
)
returns table (
  worker_id uuid,
  worker_number bigint,
  full_name text,
  phone_e164 text,
  category public.worker_category,
  tier_eligible boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller public.profiles%rowtype;
  digits text;
  max_rows integer;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select * into caller
  from public.profiles
  where id = auth.uid();

  if caller.role is distinct from 'WORKER'::public.app_role
    or caller.account_status is distinct from 'ACTIVE'::public.account_status then
    raise exception 'active worker required';
  end if;

  digits := regexp_replace(coalesce(p_phone_query, ''), '[^0-9]', '', 'g');
  if length(digits) < 4 then
    raise exception 'enter at least 4 phone digits';
  end if;

  max_rows := least(greatest(coalesce(p_limit, 10), 1), 20);

  return query
  select
    p.id,
    p.worker_number,
    p.full_name,
    p.phone_e164,
    wp.category,
    case
      when p_event_id is null then null
      else public.is_worker_tier_eligible(p_event_id, p.id, clock_timestamp())
    end
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where p.id <> auth.uid()
    and p.role = 'WORKER'::public.app_role
    and p.account_status = 'ACTIVE'::public.account_status
    and private.required_profile_complete(p.id)
    and regexp_replace(p.phone_e164, '[^0-9]', '', 'g') like '%' || digits || '%'
  order by
    case when regexp_replace(p.phone_e164, '[^0-9]', '', 'g') = digits then 0 else 1 end,
    p.full_name,
    p.worker_number
  limit max_rows;
end;
$$;

revoke all on function public.search_bookable_friend_workers(text, uuid, integer) from public, anon;
grant execute on function public.search_bookable_friend_workers(text, uuid, integer) to authenticated;

create or replace function public.apply_for_event_with_friend(
  p_event_id uuid,
  p_friend_worker_id uuid,
  p_idempotency_key text,
  p_acknowledged_requirement_ids uuid[] default '{}',
  p_late_cancellation_acknowledged boolean default false
)
returns table (
  friend_booking_request_id uuid,
  result public.booking_result,
  result_detail_code text,
  event_id uuid,
  requester_id uuid,
  friend_id uuid,
  requester_booking_request_id uuid,
  friend_booking_request_id_inner uuid,
  requester_assignment_id uuid,
  friend_assignment_id uuid,
  vacancy_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requester_id uuid;
  requester_category public.worker_category;
  friend_category public.worker_category;
  pair public.friend_booking_requests%rowtype;
  ev public.events%rowtype;
  win public.booking_arbitration_windows%rowtype;
  requester_req public.booking_requests%rowtype;
  friend_req public.booking_requests%rowtype;
  confirmed_requester public.booking_requests%rowtype;
  confirmed_friend public.booking_requests%rowtype;
  received timestamptz;
  acks uuid[];
  vacancy integer;
begin
  v_requester_id := auth.uid();
  if v_requester_id is null then
    raise exception 'authentication required';
  end if;
  if p_friend_worker_id is null then
    raise exception 'friend worker is required';
  end if;
  if v_requester_id = p_friend_worker_id then
    raise exception 'choose a different worker as friend';
  end if;
  if btrim(coalesce(p_idempotency_key, '')) = '' then
    raise exception 'idempotency key is required';
  end if;

  perform private.lock_booking_mutation();
  received := clock_timestamp();

  select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into acks
  from unnest(coalesce(p_acknowledged_requirement_ids, '{}')) x
  where x is not null;

  select * into pair
  from public.friend_booking_requests fbr
  where fbr.requester_id = v_requester_id
    and fbr.idempotency_key = p_idempotency_key
  for update;

  if pair.id is not null then
    if pair.event_id <> p_event_id
      or pair.friend_id <> p_friend_worker_id
      or pair.acknowledged_requirement_ids <> acks
      or pair.late_cancellation_acknowledged <> coalesce(p_late_cancellation_acknowledged, false) then
      raise exception 'idempotency key belongs to a different friend booking payload';
    end if;
    return query select * from private.friend_booking_result_row(pair);
    return;
  end if;

  select * into ev
  from public.events
  where id = p_event_id
  for update;

  if ev.id is null then
    raise exception 'event not found';
  end if;

  select w.* into win
  from public.booking_arbitration_windows w
  where w.event_id = p_event_id
    and w.status = 'OPEN'
  for update;

  if win.id is not null and win.closes_at <= received then
    perform private.allocate_booking_window(win.id, false, '{}');
    select * into ev from public.events where id = p_event_id for update;
    win := null;
  end if;

  insert into public.friend_booking_requests(
    event_id,
    requester_id,
    friend_id,
    idempotency_key,
    acknowledged_requirement_ids,
    late_cancellation_acknowledged
  ) values (
    p_event_id,
    v_requester_id,
    p_friend_worker_id,
    p_idempotency_key,
    acks,
    coalesce(p_late_cancellation_acknowledged, false)
  ) returning * into pair;

  if win.id is not null then
    pair := private.complete_friend_booking_request(
      pair.id,
      'WAITLIST_AVAILABLE',
      'PAIR_REQUIRES_TWO_OPEN_VACANCIES'
    );
    return query select * from private.friend_booking_result_row(pair);
    return;
  end if;

  if exists (
    select 1
    from public.booking_requests br
    where br.event_id = p_event_id
      and br.worker_id in (v_requester_id, p_friend_worker_id)
      and br.result = 'PENDING'::public.booking_result
  ) then
    pair := private.complete_friend_booking_request(pair.id, 'DUPLICATE', 'ACTIVE_APPLICATION_EXISTS');
    return query select * from private.friend_booking_result_row(pair);
    return;
  end if;

  select wp.category into requester_category
  from public.worker_profiles wp
  where wp.user_id = v_requester_id;

  select wp.category into friend_category
  from public.worker_profiles wp
  where wp.user_id = p_friend_worker_id;

  if friend_category is null then
    pair := private.complete_friend_booking_request(pair.id, 'RESTRICTED', 'FRIEND_ACTIVE_WORKER_REQUIRED');
    return query select * from private.friend_booking_result_row(pair);
    return;
  end if;

  insert into public.booking_requests(
    event_id,
    worker_id,
    idempotency_key,
    server_received_at,
    worker_category_snapshot,
    acknowledged_requirement_ids,
    late_cancellation_acknowledged,
    acknowledged_event_version,
    input_snapshot_complete
  ) values (
    p_event_id,
    v_requester_id,
    p_idempotency_key,
    received,
    requester_category,
    acks,
    coalesce(p_late_cancellation_acknowledged, false),
    ev.version,
    true
  ) returning * into requester_req;

  insert into public.booking_requests(
    event_id,
    worker_id,
    idempotency_key,
    server_received_at,
    worker_category_snapshot,
    acknowledged_requirement_ids,
    late_cancellation_acknowledged,
    acknowledged_event_version,
    input_snapshot_complete
  ) values (
    p_event_id,
    p_friend_worker_id,
    p_idempotency_key || ':friend:' || p_friend_worker_id::text,
    received,
    friend_category,
    acks,
    coalesce(p_late_cancellation_acknowledged, false),
    ev.version,
    true
  ) returning * into friend_req;

  update public.friend_booking_requests
  set requester_booking_request_id = requester_req.id,
      friend_booking_request_id = friend_req.id
  where id = pair.id
  returning * into pair;

  requester_req := private.validate_booking_request(requester_req);
  friend_req := private.validate_booking_request(friend_req);

  if requester_req.result <> 'PENDING'::public.booking_result then
    if friend_req.result = 'PENDING'::public.booking_result then
      friend_req := private.complete_booking_request(friend_req.id, 'ERROR', 'FRIEND_PAIR_REJECTED');
    end if;
    pair := private.complete_friend_booking_request(pair.id, requester_req.result, requester_req.result_detail_code);
    return query select * from private.friend_booking_result_row(pair);
    return;
  end if;

  if friend_req.result <> 'PENDING'::public.booking_result then
    requester_req := private.complete_booking_request(requester_req.id, 'ERROR', 'FRIEND_PAIR_REJECTED');
    pair := private.complete_friend_booking_request(pair.id, friend_req.result, 'FRIEND_' || coalesce(friend_req.result_detail_code, friend_req.result::text));
    return query select * from private.friend_booking_result_row(pair);
    return;
  end if;

  vacancy := ev.required_worker_count - private.active_confirmed_assignment_count(ev.id);
  if vacancy < 2 then
    requester_req := private.complete_booking_request(requester_req.id, 'WAITLIST_AVAILABLE', 'PAIR_REQUIRES_TWO_OPEN_VACANCIES');
    friend_req := private.complete_booking_request(friend_req.id, 'WAITLIST_AVAILABLE', 'PAIR_REQUIRES_TWO_OPEN_VACANCIES');
    pair := private.complete_friend_booking_request(pair.id, 'WAITLIST_AVAILABLE', 'PAIR_REQUIRES_TWO_OPEN_VACANCIES');
    return query select * from private.friend_booking_result_row(pair);
    return;
  end if;

  confirmed_requester := private.confirm_booking_request(
    requester_req,
    requester_req.late_cancellation_acknowledged,
    requester_req.acknowledged_requirement_ids
  );
  confirmed_friend := private.confirm_booking_request(
    friend_req,
    friend_req.late_cancellation_acknowledged,
    friend_req.acknowledged_requirement_ids
  );

  if confirmed_requester.result <> 'CONFIRMED'::public.booking_result
    or confirmed_friend.result <> 'CONFIRMED'::public.booking_result then
    raise exception 'friend booking confirmation failed';
  end if;

  update public.assignments
  set source = 'FRIEND_BOOKING',
      updated_at = clock_timestamp()
  where id in (confirmed_requester.resulting_assignment_id, confirmed_friend.resulting_assignment_id);

  pair := private.complete_friend_booking_request(
    pair.id,
    'CONFIRMED',
    null,
    confirmed_requester.resulting_assignment_id,
    confirmed_friend.resulting_assignment_id
  );

  insert into public.audit_logs(
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    related_event_id,
    request_id,
    source
  ) values (
    v_requester_id,
    (select role from public.profiles where id = v_requester_id),
    'friend_booking_confirmed',
    'friend_booking_request',
    pair.id,
    null,
    jsonb_build_object(
      'event_id', pair.event_id,
      'requester_id', pair.requester_id,
      'friend_id', pair.friend_id,
      'requester_assignment_id', pair.requester_assignment_id,
      'friend_assignment_id', pair.friend_assignment_id
    ),
    'Worker booked with friend',
    pair.event_id,
    pair.idempotency_key,
    'database'
  );

  return query select * from private.friend_booking_result_row(pair);
exception
  when unique_violation then
    if pair.id is not null then
      pair := private.complete_friend_booking_request(pair.id, 'DUPLICATE', 'ACTIVE_ASSIGNMENT_OR_WAITLIST_EXISTS');
      return query select * from private.friend_booking_result_row(pair);
      return;
    end if;
    raise;
end;
$$;

revoke all on function public.apply_for_event_with_friend(uuid, uuid, text, uuid[], boolean) from public, anon;
grant execute on function public.apply_for_event_with_friend(uuid, uuid, text, uuid[], boolean) to authenticated;

notify pgrst, 'reload schema';

