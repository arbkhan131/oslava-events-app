-- Readiness R8: scheduled operations health and resilient notification delivery leases.

alter table public.notification_deliveries
  add column if not exists claim_expires_at timestamptz,
  add column if not exists completed_by text;

create index if not exists notification_deliveries_claim_lease_idx
  on public.notification_deliveries(state, claim_expires_at, next_attempt_at, created_at)
  where state = 'CLAIMED';

create table if not exists public.scheduled_job_runs (
  id uuid primary key default gen_random_uuid(),
  job_name text not null,
  worker_id text not null,
  status text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  lease_expires_at timestamptz not null,
  result jsonb not null default '{}'::jsonb,
  error text,
  created_at timestamptz not null default now(),
  constraint scheduled_job_runs_job_name_not_blank check (btrim(job_name) <> ''),
  constraint scheduled_job_runs_worker_id_not_blank check (btrim(worker_id) <> ''),
  constraint scheduled_job_runs_status_valid check (status in ('RUNNING', 'SUCCEEDED', 'FAILED', 'SKIPPED')),
  constraint scheduled_job_runs_terminal_valid check (
    (status = 'RUNNING' and finished_at is null)
    or (status in ('SUCCEEDED', 'FAILED', 'SKIPPED') and finished_at is not null)
  )
);

create index if not exists scheduled_job_runs_job_started_idx
  on public.scheduled_job_runs(job_name, started_at desc);

alter table public.scheduled_job_runs enable row level security;

create policy scheduled_job_runs_select_admin
  on public.scheduled_job_runs
  for select
  to authenticated
  using (private.current_actor_role() in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role));

create policy scheduled_job_runs_service_all
  on public.scheduled_job_runs
  for all
  to service_role
  using (true)
  with check (true);

create or replace function public.claim_notification_deliveries(
  p_worker_id text,
  p_limit integer default 50
)
returns table (
  delivery_id uuid,
  notification_id uuid,
  device_token_id uuid,
  recipient_id uuid,
  fcm_token text,
  notification_type public.notification_type,
  title text,
  body text,
  related_event_id uuid,
  deep_link_path text,
  attempts integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  safe_worker_id text := nullif(btrim(coalesce(p_worker_id, '')), '');
begin
  if safe_worker_id is null then
    raise exception 'worker id is required';
  end if;

  return query
  with claimable as (
    select nd.id
    from public.notification_deliveries nd
    join public.device_tokens dt on dt.id = nd.device_token_id
    where nd.attempts < nd.max_attempts
      and dt.active
      and (
        (nd.state in ('PENDING', 'FAILED') and nd.next_attempt_at <= now())
        or (nd.state = 'CLAIMED' and coalesce(nd.claim_expires_at, nd.claimed_at + interval '2 minutes') <= now())
      )
    order by nd.next_attempt_at, nd.created_at
    limit safe_limit
    for update of nd skip locked
  ),
  updated as (
    update public.notification_deliveries nd
    set state = 'CLAIMED',
        claimed_at = now(),
        claim_expires_at = now() + interval '2 minutes',
        claimed_by = safe_worker_id,
        attempts = nd.attempts + 1,
        updated_at = now()
    from claimable
    where nd.id = claimable.id
    returning nd.*
  )
  select
    u.id,
    u.notification_id,
    u.device_token_id,
    n.recipient_id,
    dt.token,
    n.notification_type,
    n.title,
    n.body,
    n.related_event_id,
    n.deep_link_path,
    u.attempts
  from updated u
  join public.notifications n on n.id = u.notification_id
  join public.device_tokens dt on dt.id = u.device_token_id;
end;
$$;

create or replace function public.complete_claimed_notification_delivery(
  p_delivery_id uuid,
  p_worker_id text,
  p_success boolean,
  p_provider_message_id text default null,
  p_provider_response_code text default null,
  p_provider_response text default null,
  p_permanently_invalid_token boolean default false
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery_record public.notification_deliveries%rowtype;
  final_state text;
  safe_worker_id text := nullif(btrim(coalesce(p_worker_id, '')), '');
begin
  if safe_worker_id is null then
    raise exception 'worker id is required';
  end if;

  select * into delivery_record
  from public.notification_deliveries
  where id = p_delivery_id
  for update;

  if delivery_record.id is null then
    raise exception 'notification delivery not found';
  end if;

  if delivery_record.state <> 'CLAIMED'
     or delivery_record.claimed_by is distinct from safe_worker_id
     or coalesce(delivery_record.claim_expires_at, '-infinity'::timestamptz) <= now() then
    raise exception 'notification delivery claim is not owned by this worker or has expired';
  end if;

  if p_success then
    update public.notification_deliveries
    set state = 'SENT',
        provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
        provider_response_code = nullif(btrim(coalesce(p_provider_response_code, '')), ''),
        provider_response = nullif(btrim(coalesce(p_provider_response, '')), ''),
        sent_at = now(),
        failed_at = null,
        completed_by = safe_worker_id,
        claim_expires_at = null,
        updated_at = now()
    where id = p_delivery_id;
    final_state := 'SENT';
  else
    final_state := case when delivery_record.attempts >= delivery_record.max_attempts then 'FAILED' else 'PENDING' end;

    update public.notification_deliveries
    set state = final_state,
        provider_response_code = nullif(btrim(coalesce(p_provider_response_code, '')), ''),
        provider_response = nullif(btrim(coalesce(p_provider_response, '')), ''),
        next_attempt_at = case when final_state = 'PENDING' then now() + private.backoff_interval(delivery_record.attempts) else next_attempt_at end,
        failed_at = case when final_state = 'FAILED' then now() else null end,
        completed_by = safe_worker_id,
        claim_expires_at = null,
        updated_at = now()
    where id = p_delivery_id;

    if p_permanently_invalid_token and delivery_record.device_token_id is not null then
      update public.device_tokens
      set active = false,
          invalidated_at = now(),
          updated_at = now()
      where id = delivery_record.device_token_id;
    end if;
  end if;

  return final_state;
end;
$$;

create or replace function public.notification_delivery_health()
returns table (
  pending_count integer,
  claimed_count integer,
  expired_claim_count integer,
  failed_terminal_count integer,
  active_token_count integer
)
language sql
security definer
set search_path = ''
as $$
  select
    count(*) filter (where nd.state = 'PENDING')::integer,
    count(*) filter (where nd.state = 'CLAIMED' and coalesce(nd.claim_expires_at, nd.claimed_at + interval '2 minutes') > now())::integer,
    count(*) filter (where nd.state = 'CLAIMED' and coalesce(nd.claim_expires_at, nd.claimed_at + interval '2 minutes') <= now())::integer,
    count(*) filter (where nd.state = 'FAILED' and nd.attempts >= nd.max_attempts)::integer,
    (select count(*)::integer from public.device_tokens where active)
  from public.notification_deliveries nd;
$$;

create or replace function public.run_scheduled_operations(
  p_job_name text default 'scheduled-operations',
  p_worker_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  safe_job_name text := nullif(btrim(coalesce(p_job_name, '')), '');
  safe_worker_id text := coalesce(nullif(btrim(coalesce(p_worker_id, '')), ''), 'scheduler-' || gen_random_uuid()::text);
  run_id uuid;
  lifecycle_count integer := 0;
  tier_count integer := 0;
  reminder_count integer := 0;
  result_payload jsonb;
begin
  if safe_job_name is null then
    raise exception 'job name is required';
  end if;

  if not pg_try_advisory_xact_lock(hashtext('oslava:' || safe_job_name || ':scheduled-operations')) then
    insert into public.scheduled_job_runs(job_name, worker_id, status, started_at, finished_at, lease_expires_at, result)
    values (safe_job_name, safe_worker_id, 'SKIPPED', now(), now(), now(), jsonb_build_object('reason', 'overlapping_run'))
    returning id into run_id;
    return jsonb_build_object('run_id', run_id, 'status', 'SKIPPED', 'reason', 'overlapping_run');
  end if;

  insert into public.scheduled_job_runs(job_name, worker_id, status, started_at, lease_expires_at)
  values (safe_job_name, safe_worker_id, 'RUNNING', now(), now() + interval '5 minutes')
  returning id into run_id;

  lifecycle_count := public.process_event_lifecycle_transitions();
  tier_count := public.process_due_tier_releases();
  reminder_count := public.process_due_reporting_reminders();

  result_payload := jsonb_build_object(
    'lifecycle_transitions', lifecycle_count,
    'tier_releases', tier_count,
    'reporting_reminders', reminder_count
  );

  update public.scheduled_job_runs
  set status = 'SUCCEEDED', finished_at = now(), result = result_payload
  where id = run_id;

  return jsonb_build_object('run_id', run_id, 'status', 'SUCCEEDED', 'result', result_payload);
exception when others then
  if run_id is not null then
    update public.scheduled_job_runs
    set status = 'FAILED', finished_at = now(), error = sqlerrm
    where id = run_id;
  end if;
  raise;
end;
$$;

revoke all on public.scheduled_job_runs from public, anon;
grant select on public.scheduled_job_runs to authenticated;
grant all on public.scheduled_job_runs to service_role;

revoke all on function public.complete_claimed_notification_delivery(uuid, text, boolean, text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.notification_delivery_health() from public, anon;
revoke all on function public.run_scheduled_operations(text, text) from public, anon, authenticated;

grant execute on function public.complete_claimed_notification_delivery(uuid, text, boolean, text, text, text, boolean) to service_role;
grant execute on function public.notification_delivery_health() to authenticated, service_role;
grant execute on function public.run_scheduled_operations(text, text) to service_role;
