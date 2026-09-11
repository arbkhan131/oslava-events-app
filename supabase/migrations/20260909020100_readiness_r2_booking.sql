-- R2: committed final-seat intake, recoverable allocation, and booking serialization.
alter table public.booking_requests
  add column acknowledged_requirement_ids uuid[] not null default '{}',
  add column late_cancellation_acknowledged boolean not null default false,
  add column acknowledged_event_version integer,
  add column input_snapshot_complete boolean not null default false;

-- Old pending rows have no trustworthy per-request acknowledgement payload.
update public.booking_requests set result='ERROR', result_detail_code='RETRY_WITH_NEW_KEY',
  completed_at=clock_timestamp() where result='PENDING';
update public.booking_arbitration_windows set status='ALLOCATED', allocated_at=clock_timestamp()
where status='OPEN';
create unique index booking_one_open_window on public.booking_arbitration_windows(event_id) where status='OPEN';
create unique index booking_one_pending_worker_event on public.booking_requests(worker_id,event_id) where result='PENDING';

create or replace function private.lock_booking_mutation()
returns void language plpgsql security definer set search_path='' as $$
begin
  -- Never sleep while holding this lock. Intake commits before the priority interval elapses.
  -- One ordering domain also protects a worker applying/promoted into different events.
  perform pg_catalog.pg_advisory_xact_lock(20260909,2);
end $$;
revoke all on function private.lock_booking_mutation() from public,anon,authenticated;

-- Consistent ordering for operations that acquire event/worker/assignment row locks.
-- Preserve their existing signatures, authorization, grants and business behavior.
do $$
declare proc record; definition text;
begin
  for proc in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in
      ('join_waitlist','withdraw_waitlist','cancel_assignment','promote_waitlist',
       'cancel_event','complete_event','close_event','update_event','set_attendance',
       'record_performance_review','change_worker_category','change_user_role',
       'change_user_phone','change_account_status','provision_staff_profile',
       'request_account_erasure','process_event_lifecycle_transitions')
  loop
    definition:=pg_get_functiondef(proc.oid);
    if position('perform private.lock_booking_mutation();' in definition)=0 then
      definition:=regexp_replace(definition, '\mbegin\M',
        E'begin\n  perform private.lock_booking_mutation();', 'i');
      execute definition;
    end if;
  end loop;
end $$;

create or replace function private.validate_booking_request(p_request public.booking_requests)
returns public.booking_requests language plpgsql security definer set search_path='' as $$
declare ev public.events%rowtype; worker public.profiles%rowtype;
begin
  select * into ev from public.events where id=p_request.event_id for update;
  select * into worker from public.profiles where id=p_request.worker_id for update;
  perform 1 from public.worker_profiles wp where wp.user_id=p_request.worker_id for update;
  if worker.role is distinct from 'WORKER'::public.app_role or worker.account_status is distinct from 'ACTIVE'::public.account_status then
    return private.complete_booking_request(p_request.id,'RESTRICTED','ACTIVE_WORKER_REQUIRED');
  end if;
  if not private.required_profile_complete(p_request.worker_id) then
    return private.complete_booking_request(p_request.id,'RESTRICTED','PROFILE_INCOMPLETE');
  end if;
  if ev.id is null or ev.event_status not in ('PUBLISHED','UPCOMING')
    or ev.recruitment_status not in ('OPEN','FULL') or ev.reporting_at<=clock_timestamp() then
    return private.complete_booking_request(p_request.id,'EVENT_UNAVAILABLE','NOT_RECRUITABLE');
  end if;
  if exists(select 1 from public.assignments where event_id=ev.id and worker_id=worker.id and status='CONFIRMED')
    or exists(select 1 from public.waitlist_entries where event_id=ev.id and worker_id=worker.id and status='WAITING') then
    return private.complete_booking_request(p_request.id,'DUPLICATE','ACTIVE_ASSIGNMENT_OR_WAITLIST_EXISTS');
  end if;
  if not public.is_worker_tier_eligible(ev.id,worker.id,clock_timestamp()) then
    return private.complete_booking_request(p_request.id,'LOCKED','TIER_NOT_OPEN');
  end if;
  if exists(select 1 from public.event_requirements r where r.event_id=ev.id
    and r.is_mandatory and r.acknowledgement_required and
    (not r.id=any(p_request.acknowledged_requirement_ids)
     or p_request.acknowledged_event_version is distinct from ev.version)) then
    return private.complete_booking_request(p_request.id,'INVALID_REQUIREMENTS','MISSING_ACKNOWLEDGEMENT');
  end if;
  if public.has_booking_conflict(worker.id,ev.id) then
    return private.complete_booking_request(p_request.id,'CONFLICT','ONE_HOUR_CONFLICT');
  end if;
  if clock_timestamp()>ev.reporting_at-interval '1 hour' and not p_request.late_cancellation_acknowledged then
    return private.complete_booking_request(p_request.id,'ERROR','LATE_CANCELLATION_ACK_REQUIRED');
  end if;
  if private.active_confirmed_assignment_count(ev.id)>=ev.required_worker_count then
    return private.complete_booking_request(p_request.id,'WAITLIST_AVAILABLE','FULL');
  end if;
  return p_request;
end $$;
revoke all on function private.validate_booking_request(public.booking_requests) from public,anon,authenticated;

create or replace function private.allocate_booking_window(
  p_window_id uuid, p_late_cancellation_acknowledged boolean, p_acknowledged_requirement_ids uuid[]
)
returns void language plpgsql security definer set search_path='' as $$
declare win public.booking_arbitration_windows%rowtype; candidate public.booking_requests%rowtype;
begin
  perform private.lock_booking_mutation();
  -- Retain the old private signature for migration compatibility; caller payloads
  -- are deliberately ignored. Only persisted per-contender inputs are authoritative.
  perform p_late_cancellation_acknowledged, p_acknowledged_requirement_ids;
  select * into win from public.booking_arbitration_windows where id=p_window_id for update;
  if win.id is null or win.status<>'OPEN' or clock_timestamp()<win.closes_at then return; end if;
  for candidate in select br.* from public.booking_requests br
    where br.arbitration_window_id=win.id and br.result='PENDING'
    order by private.category_rank(br.worker_category_snapshot),br.server_received_at,br.id for update
  loop
    candidate:=private.validate_booking_request(candidate);
    if candidate.result='PENDING' then
      -- Ranking uses trusted receipt category; assignment records current authoritative category.
      select category into candidate.worker_category_snapshot from public.worker_profiles where user_id=candidate.worker_id;
      perform private.confirm_booking_request(candidate,candidate.late_cancellation_acknowledged,candidate.acknowledged_requirement_ids);
    end if;
  end loop;
  update public.booking_arbitration_windows set status='ALLOCATED',allocated_at=clock_timestamp() where id=win.id;
end $$;

create or replace function public.resolve_booking_request(p_idempotency_key text)
returns table(booking_request_id uuid,result public.booking_result,result_detail_code text,
  assignment_id uuid,event_id uuid,vacancy_count integer)
language plpgsql security definer set search_path='' as $$
declare req public.booking_requests%rowtype;
begin
  perform private.lock_booking_mutation();
  select * into req from public.booking_requests where worker_id=auth.uid() and idempotency_key=p_idempotency_key;
  if req.id is null then raise exception 'booking request not found'; end if;
  if req.result='PENDING' then
    perform private.allocate_booking_window(req.arbitration_window_id,false,'{}');
    select * into req from public.booking_requests where id=req.id;
  end if;
  return query select * from private.booking_result_row(req);
end $$;
revoke all on function public.resolve_booking_request(text) from public,anon;
grant execute on function public.resolve_booking_request(text) to authenticated;

create or replace function public.get_booking_result(p_booking_request_id uuid)
returns table(booking_request_id uuid,result public.booking_result,result_detail_code text,
  assignment_id uuid,event_id uuid,vacancy_count integer)
language plpgsql security definer set search_path='' as $$
declare key text;
begin
  select br.idempotency_key into key from public.booking_requests br
    where br.id=p_booking_request_id and br.worker_id=auth.uid();
  if key is null then raise exception 'booking request not found'; end if;
  return query select * from public.resolve_booking_request(key);
end $$;
revoke all on function public.get_booking_result(uuid) from public,anon;
grant execute on function public.get_booking_result(uuid) to authenticated;

create or replace function public.apply_for_event(p_event_id uuid,p_idempotency_key text,
  p_acknowledged_requirement_ids uuid[] default '{}',p_late_cancellation_acknowledged boolean default false)
returns table(booking_request_id uuid,result public.booking_result,result_detail_code text,
  assignment_id uuid,event_id uuid,vacancy_count integer)
language plpgsql security definer set search_path='' as $$
declare req public.booking_requests%rowtype; win public.booking_arbitration_windows%rowtype;
  received timestamptz; ev public.events%rowtype; category public.worker_category; acks uuid[];
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if btrim(coalesce(p_idempotency_key,''))='' then raise exception 'idempotency key is required'; end if;
  perform private.lock_booking_mutation();
  -- Receipt is stamped by the server at serialized admission, never supplied by the caller.
  received:=clock_timestamp();
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into acks
    from unnest(coalesce(p_acknowledged_requirement_ids,'{}')) x where x is not null;
  select * into req from public.booking_requests where worker_id=auth.uid() and idempotency_key=p_idempotency_key;
  if req.id is not null then
    if req.event_id<>p_event_id or (req.input_snapshot_complete and
      (req.acknowledged_requirement_ids<>acks
       or req.late_cancellation_acknowledged<>coalesce(p_late_cancellation_acknowledged,false))) then
      raise exception 'idempotency key belongs to a different booking payload';
    end if;
    return query select * from public.resolve_booking_request(p_idempotency_key); return;
  end if;
  select * into ev from public.events where id=p_event_id for update;
  if ev.id is null then raise exception 'event not found'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'worker profile not found'; end if;
  -- An expired window must finish before a later request can take its seat.
  select w.* into win from public.booking_arbitration_windows w where w.event_id=p_event_id and w.status='OPEN';
  if win.id is not null and win.closes_at<=received then
    perform private.allocate_booking_window(win.id,false,'{}');
    win:=null;
  end if;
  select br.* into req from public.booking_requests br where br.worker_id=auth.uid() and br.event_id=p_event_id and br.result='PENDING';
  if req.id is not null then
    -- A second key does not create a second contender or alter the original acknowledgements.
    return query select * from private.booking_result_row(req); return;
  end if;
  select wp.category into category from public.worker_profiles wp where wp.user_id=auth.uid();
  insert into public.booking_requests(event_id,worker_id,idempotency_key,server_received_at,
    worker_category_snapshot,acknowledged_requirement_ids,late_cancellation_acknowledged,acknowledged_event_version,input_snapshot_complete)
  values(p_event_id,auth.uid(),p_idempotency_key,received,category,acks,coalesce(p_late_cancellation_acknowledged,false),ev.version,true)
  returning * into req;
  req:=private.validate_booking_request(req);
  if req.result='PENDING' then
    if win.id is not null or ev.required_worker_count-private.active_confirmed_assignment_count(ev.id)=1 then
      if win.id is null then
        insert into public.booking_arbitration_windows(event_id,opens_at,closes_at)
        values(ev.id,received,received+interval '1 second') returning * into win;
      end if;
      update public.booking_requests set arbitration_window_id=win.id,result_detail_code='ARBITRATION_PENDING'
      where id=req.id returning * into req;
    else
      req:=private.confirm_booking_request(req,req.late_cancellation_acknowledged,req.acknowledged_requirement_ids);
    end if;
  end if;
  return query select * from private.booking_result_row(req);
end $$;

create or replace function public.process_due_booking_windows(p_limit integer default 32)
returns integer language plpgsql security definer set search_path='' as $$
declare win record; processed integer:=0;
begin
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'limit must be between 1 and 100'; end if;
  -- A busy mutation is retried on the next second, without queueing a long-running job.
  if not pg_try_advisory_xact_lock(20260909,2) then return 0; end if;
  for win in select id from public.booking_arbitration_windows
    where status='OPEN' and closes_at<=clock_timestamp() order by closes_at,id limit p_limit
  loop
    perform private.allocate_booking_window(win.id,false,'{}'); processed:=processed+1;
  end loop;
  return processed;
end $$;
revoke all on function public.process_due_booking_windows(integer) from public,anon,authenticated;
grant execute on function public.process_due_booking_windows(integer) to service_role;

-- Critical allocation outcomes are append-only audited; retries cannot add an outcome twice.
create or replace function private.audit_booking_outcome()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.result<>'PENDING' and old.result='PENDING' then
    insert into public.audit_logs(actor_id,actor_role,action,entity_type,entity_id,before_values,after_values,reason,source)
    values(new.worker_id,(select role from public.profiles where id=new.worker_id),'booking_resolved','booking_request',new.id,to_jsonb(old),to_jsonb(new),
      coalesce(new.result_detail_code,new.result::text),'database');
  end if;
  return new;
end $$;
revoke all on function private.audit_booking_outcome() from public,anon,authenticated;
create trigger booking_outcome_audit after update of result on public.booking_requests
for each row execute function private.audit_booking_outcome();

revoke all on function private.allocate_booking_window(uuid,boolean,uuid[]),
  private.confirm_booking_request(public.booking_requests,boolean,uuid[]),
  private.complete_booking_request(uuid,public.booking_result,text,uuid),
  private.get_or_create_booking_window(uuid,timestamptz)
from public,anon,authenticated;

-- Time gates remain authoritative even if the lifecycle scheduler is late.
do $$
declare name text; definition text;
begin
  foreach name in array array['public.is_worker_tier_eligible(uuid,uuid,timestamp with time zone)',
    'private.promote_one_waitlist_candidate(uuid)']
  loop
    definition:=pg_get_functiondef(name::regprocedure);
    if name like 'public.%' then
      definition:=replace(definition,'and r.opens_at <= p_at','and r.opens_at <= p_at and e.reporting_at > p_at');
    else
      definition:=replace(definition,'if event_record.id is null',
        E'if event_record.reporting_at <= clock_timestamp()\n    or event_record.event_status not in (''PUBLISHED'',''UPCOMING'')\n    or event_record.id is null');
      definition:=replace(definition,'    select wp.category',E'    perform 1 from public.profiles where id=candidate.worker_id for update;\n    perform 1 from public.worker_profiles where user_id=candidate.worker_id for update;\n    select wp.category');
    end if;
    execute definition;
  end loop;
end $$;

-- pg_cron 1.6 supports second intervals. Client polling is an independent fast path.
-- Scratch databases replay functions but cannot host this cluster's cron extension.
do $$
begin
  if current_database()=coalesce(current_setting('cron.database_name',true),'postgres') then
    create extension if not exists pg_cron;
    perform cron.schedule('oslava-booking-resolution','1 second','select public.process_due_booking_windows(32)');
  end if;
end $$;
