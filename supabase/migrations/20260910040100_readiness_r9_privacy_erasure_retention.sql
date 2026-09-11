-- Readiness R9: self-service erasure initiation, verified fulfillment, and photo cleanup tasks.

alter table public.account_erasure_requests
  add column if not exists verification_status text not null default 'PENDING_VERIFICATION',
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid references public.profiles(id) on delete restrict,
  add column if not exists rejected_at timestamptz,
  add column if not exists fulfillment_attempts integer not null default 0,
  add column if not exists last_fulfillment_error text,
  add column if not exists photo_cleanup_status text not null default 'NOT_REQUIRED',
  add column if not exists source text not null default 'admin';

alter table public.account_erasure_requests
  drop constraint if exists account_erasure_requests_status_valid;

alter table public.account_erasure_requests
  add constraint account_erasure_requests_status_valid check (
    status in ('OPEN', 'VERIFIED', 'COMPLETED', 'REJECTED', 'LEGAL_HOLD')
  );

alter table public.account_erasure_requests
  drop constraint if exists account_erasure_requests_verification_status_valid;

alter table public.account_erasure_requests
  add constraint account_erasure_requests_verification_status_valid check (
    verification_status in ('PENDING_VERIFICATION', 'VERIFIED', 'REJECTED')
  );

alter table public.account_erasure_requests
  drop constraint if exists account_erasure_requests_photo_cleanup_status_valid;

alter table public.account_erasure_requests
  add constraint account_erasure_requests_photo_cleanup_status_valid check (
    photo_cleanup_status in ('NOT_REQUIRED', 'PENDING', 'COMPLETED', 'FAILED')
  );

alter table public.account_erasure_requests
  drop constraint if exists account_erasure_requests_source_valid;

alter table public.account_erasure_requests
  add constraint account_erasure_requests_source_valid check (source in ('self_service', 'admin', 'external'));

alter table public.profiles
  drop constraint if exists profiles_photo_completion_pair;

alter table public.profiles
  add constraint profiles_photo_completion_pair check (
    (profile_completed_at is null and profile_photo_path is null)
    or (profile_completed_at is not null)
  );

create table if not exists public.profile_photo_deletion_tasks (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  storage_path text not null,
  erasure_request_id uuid references public.account_erasure_requests(id) on delete set null,
  state text not null default 'PENDING',
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint profile_photo_deletion_tasks_path_not_blank check (btrim(storage_path) <> ''),
  constraint profile_photo_deletion_tasks_state_valid check (state in ('PENDING', 'COMPLETED', 'FAILED')),
  constraint profile_photo_deletion_tasks_attempts_valid check (attempts >= 0),
  constraint profile_photo_deletion_tasks_completion_pair check (
    (state = 'COMPLETED' and completed_at is not null)
    or (state <> 'COMPLETED' and completed_at is null)
  )
);

create index if not exists profile_photo_deletion_tasks_pending_idx
  on public.profile_photo_deletion_tasks(state, created_at)
  where state in ('PENDING', 'FAILED');

alter table public.profile_photo_deletion_tasks enable row level security;
alter table public.profile_photo_deletion_tasks force row level security;

create trigger profile_photo_deletion_tasks_touch_updated_at
  before update on public.profile_photo_deletion_tasks
  for each row execute function private.touch_updated_at();

create policy profile_photo_deletion_tasks_select_admin
  on public.profile_photo_deletion_tasks
  for select
  to authenticated
  using (private.current_actor_role() = 'SUPER_ADMIN'::public.app_role);

create policy profile_photo_deletion_tasks_service_all
  on public.profile_photo_deletion_tasks
  for all
  to service_role
  using (true)
  with check (true);

create or replace function public.request_my_account_erasure(p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  actor_role public.app_role;
  request_id uuid;
begin
  if actor_id is null then
    raise exception 'authentication required';
  end if;

  actor_role := private.current_actor_role();

  if actor_role is null then
    raise exception 'profile not found';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  if exists (
    select 1
    from public.account_erasure_requests aer
    where aer.target_user_id = actor_id
      and aer.status in ('OPEN', 'VERIFIED', 'LEGAL_HOLD')
  ) then
    raise exception 'an erasure request is already open for this account';
  end if;

  insert into public.account_erasure_requests (
    target_user_id,
    requested_by,
    requested_by_role,
    reason,
    source,
    status,
    verification_status,
    due_at
  ) values (
    actor_id,
    actor_id,
    actor_role,
    p_reason,
    'self_service',
    'OPEN',
    'PENDING_VERIFICATION',
    now() + interval '30 days'
  ) returning id into request_id;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    after_values,
    reason,
    source
  ) values (
    actor_id,
    actor_role,
    'account_erasure_self_requested',
    'account_erasure_request',
    request_id,
    jsonb_build_object('status', 'OPEN', 'verification_status', 'PENDING_VERIFICATION', 'due_at', now() + interval '30 days'),
    p_reason,
    'database'
  );

  return request_id;
end;
$$;

create or replace function public.my_account_erasure_requests(p_limit integer default 10)
returns table (
  request_id uuid,
  status text,
  verification_status text,
  due_at timestamptz,
  completed_at timestamptz,
  completion_notes text,
  photo_cleanup_status text,
  created_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    aer.id,
    aer.status,
    aer.verification_status,
    aer.due_at,
    aer.completed_at,
    aer.completion_notes,
    aer.photo_cleanup_status,
    aer.created_at
  from public.account_erasure_requests aer
  where aer.target_user_id = auth.uid()
  order by aer.created_at desc
  limit least(greatest(coalesce(p_limit, 10), 1), 50);
$$;

create or replace function public.verify_account_erasure_request(
  p_request_id uuid,
  p_verified boolean,
  p_notes text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  request_record public.account_erasure_requests%rowtype;
begin
  actor_role := private.current_actor_role();
  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can verify erasure requests';
  end if;

  select * into request_record
  from public.account_erasure_requests
  where id = p_request_id
  for update;

  if request_record.id is null then
    raise exception 'erasure request not found';
  end if;

  if request_record.status not in ('OPEN', 'LEGAL_HOLD') then
    raise exception 'erasure request is not open for verification';
  end if;

  if p_verified then
    update public.account_erasure_requests
    set status = 'VERIFIED',
        verification_status = 'VERIFIED',
        verified_at = now(),
        verified_by = auth.uid(),
        completion_notes = nullif(btrim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_request_id;
  else
    update public.account_erasure_requests
    set status = 'REJECTED',
        verification_status = 'REJECTED',
        rejected_at = now(),
        completion_notes = nullif(btrim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_request_id;
  end if;

  insert into public.audit_logs(actor_id, actor_role, action, entity_type, entity_id, after_values, reason, source)
  values (
    auth.uid(),
    actor_role,
    case when p_verified then 'account_erasure_verified' else 'account_erasure_rejected' end,
    'account_erasure_request',
    p_request_id,
    jsonb_build_object('verified', p_verified, 'notes', p_notes),
    p_notes,
    'database'
  );

  return case when p_verified then 'VERIFIED' else 'REJECTED' end;
end;
$$;

create or replace function public.fulfill_due_erasure_requests(p_limit integer default 25)
returns table (
  request_id uuid,
  target_user_id uuid,
  photo_storage_path text,
  fulfilled boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  safe_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
begin
  actor_role := private.current_actor_role();
  if auth.uid() is not null and actor_role <> 'SUPER_ADMIN'::public.app_role then
    raise exception 'only Super Admin or service role can fulfill erasure requests';
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

  return query
  with due as (
    select aer.id, aer.target_user_id, p.profile_photo_path
    from public.account_erasure_requests aer
    join public.profiles p on p.id = aer.target_user_id
    where aer.status = 'VERIFIED'
      and aer.verification_status = 'VERIFIED'
      and aer.due_at <= now()
      and not exists (
        select 1
        from public.audit_logs al
        join public.audit_log_legal_holds hold on hold.audit_log_id = al.id
        where al.entity_id = aer.target_user_id
          and hold.released_at is null
      )
    order by aer.due_at, aer.created_at
    limit safe_limit
    for update of aer skip locked
  ), changed_profiles as (
    update public.profiles p
    set full_name = 'Erased User ' || substring(p.id::text from 1 for 8),
        initials = 'EU',
        phone_e164 = '+91' || lpad((abs(hashtext(p.id::text)) % 10000000000)::text, 10, '0'),
        profile_photo_path = null,
        account_status = 'INACTIVE'::public.account_status,
        updated_at = now()
    from due
    where p.id = due.target_user_id
    returning due.id as request_id, p.id as target_user_id, due.profile_photo_path as old_photo_path
  ), changed_worker_profiles as (
    update public.worker_profiles wp
    set date_of_birth = date '1900-01-01',
        address = 'Erased',
        native_place = 'Erased',
        height_cm = 1,
        education_status = 'Erased',
        has_previous_experience = false,
        experience_details = null,
        updated_at = now()
    from changed_profiles cp
    where wp.user_id = cp.target_user_id
    returning wp.user_id
  ), disabled_tokens as (
    update public.device_tokens dt
    set active = false,
        invalidated_at = coalesce(dt.invalidated_at, now()),
        updated_at = now()
    from changed_profiles cp
    where dt.user_id = cp.target_user_id
      and dt.active
    returning dt.id
  ), queued_photos as (
    insert into public.profile_photo_deletion_tasks(user_id, storage_path, erasure_request_id, state)
    select cp.target_user_id, cp.old_photo_path, cp.request_id, 'PENDING'
    from changed_profiles cp
    where cp.old_photo_path is not null
    on conflict do nothing
    returning erasure_request_id
  ), completed_requests as (
    update public.account_erasure_requests aer
    set status = 'COMPLETED',
        completed_at = now(),
        completion_notes = coalesce(nullif(aer.completion_notes, ''), 'Current profile PII removed; operational records retained under approved policy.'),
        fulfillment_attempts = aer.fulfillment_attempts + 1,
        photo_cleanup_status = case when cp.old_photo_path is null then 'NOT_REQUIRED' else 'PENDING' end,
        last_fulfillment_error = null,
        updated_at = now()
    from changed_profiles cp
    where aer.id = cp.request_id
    returning aer.id, aer.target_user_id, cp.old_photo_path
  ), audit_rows as (
    insert into public.audit_logs(actor_id, actor_role, action, entity_type, entity_id, after_values, source)
    select auth.uid(), actor_role, 'account_erasure_fulfilled', 'profile', cr.target_user_id,
      jsonb_build_object('erasure_request_id', cr.id, 'photo_cleanup_status', case when cr.old_photo_path is null then 'NOT_REQUIRED' else 'PENDING' end),
      'database'
    from completed_requests cr
    returning id
  )
  select cr.id, cr.target_user_id, cr.old_photo_path, true
  from completed_requests cr;

  perform set_config('app.bypass_identity_protection', 'off', true);
exception when others then
  perform set_config('app.bypass_identity_protection', 'off', true);
  raise;
end;
$$;

create or replace function public.complete_profile_photo_deletion_task(
  p_task_id uuid,
  p_success boolean,
  p_error text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  task_record public.profile_photo_deletion_tasks%rowtype;
  final_state text;
begin
  select * into task_record
  from public.profile_photo_deletion_tasks
  where id = p_task_id
  for update;

  if task_record.id is null then
    raise exception 'photo deletion task not found';
  end if;

  final_state := case when p_success then 'COMPLETED' when task_record.attempts + 1 >= 5 then 'FAILED' else 'PENDING' end;

  update public.profile_photo_deletion_tasks
  set state = final_state,
      attempts = attempts + 1,
      last_error = case when p_success then null else nullif(btrim(coalesce(p_error, '')), '') end,
      completed_at = case when p_success then now() else null end,
      updated_at = now()
  where id = p_task_id;

  if task_record.erasure_request_id is not null then
    update public.account_erasure_requests
    set photo_cleanup_status = final_state,
        updated_at = now()
    where id = task_record.erasure_request_id;
  end if;

  return final_state;
end;
$$;

create or replace function public.run_retention_cleanup(p_dry_run boolean default true)
returns table (
  run_id uuid,
  notifications_expired integer,
  deliveries_expired integer,
  invalid_tokens_removed integer,
  audit_logs_expired integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  notification_count integer := 0;
  delivery_count integer := 0;
  token_count integer := 0;
  audit_count integer := 0;
  cleanup_id uuid;
  erasure_count integer := 0;
begin
  actor_role := private.current_actor_role();

  if auth.uid() is not null and actor_role <> 'SUPER_ADMIN'::public.app_role then
    raise exception 'only Super Admin or service role can run retention cleanup';
  end if;

  select count(*)::integer into notification_count
  from public.notifications
  where created_at < now() - interval '180 days';

  select count(*)::integer into delivery_count
  from public.notification_deliveries
  where state in ('SENT', 'FAILED', 'SKIPPED')
    and coalesce(sent_at, failed_at, updated_at, created_at) < now() - interval '90 days';

  select count(*)::integer into token_count
  from public.device_tokens
  where active = false
    and coalesce(invalidated_at, updated_at, created_at) < now() - interval '1 day';

  select count(*)::integer into audit_count
  from public.audit_logs
  where created_at < now() - interval '3 years'
    and not exists (
      select 1 from public.audit_log_legal_holds hold
      where hold.audit_log_id = public.audit_logs.id
        and hold.released_at is null
    );

  select count(*)::integer into erasure_count
  from public.account_erasure_requests aer
  where aer.status = 'VERIFIED'
    and aer.due_at <= now();

  insert into public.retention_cleanup_runs (
    actor_id, actor_role, dry_run, notifications_expired, deliveries_expired,
    invalid_tokens_removed, audit_logs_expired, completed_at, metadata
  ) values (
    auth.uid(), actor_role, p_dry_run, notification_count, delivery_count,
    token_count, audit_count, now(),
    jsonb_build_object(
      'notifications_retention_days', 180,
      'terminal_delivery_retention_days', 90,
      'audit_retention_years', 3,
      'verified_erasure_requests_due', erasure_count
    )
  ) returning id into cleanup_id;

  if not p_dry_run then
    perform public.fulfill_due_erasure_requests(100);

    delete from public.notification_deliveries
    where state in ('SENT', 'FAILED', 'SKIPPED')
      and coalesce(sent_at, failed_at, updated_at, created_at) < now() - interval '90 days';

    delete from public.notifications
    where created_at < now() - interval '180 days';

    delete from public.device_tokens
    where active = false
      and coalesce(invalidated_at, updated_at, created_at) < now() - interval '1 day';

    perform set_config('app.allow_retention_audit_delete', 'on', true);

    delete from public.audit_logs
    where created_at < now() - interval '3 years'
      and not exists (
        select 1 from public.audit_log_legal_holds hold
        where hold.audit_log_id = public.audit_logs.id
          and hold.released_at is null
      );

    perform set_config('app.allow_retention_audit_delete', 'off', true);
  end if;

  insert into public.audit_logs(actor_id, actor_role, action, entity_type, entity_id, after_values, source)
  values (
    auth.uid(), actor_role, 'retention_cleanup_run', 'retention_cleanup_run', cleanup_id,
    jsonb_build_object('dry_run', p_dry_run, 'notifications_expired', notification_count, 'deliveries_expired', delivery_count, 'invalid_tokens_removed', token_count, 'audit_logs_expired', audit_count, 'verified_erasure_requests_due', erasure_count),
    'database'
  );

  return query select cleanup_id, notification_count, delivery_count, token_count, audit_count;
end;
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
  retention_run_id uuid;
  retention_notifications integer := 0;
  retention_deliveries integer := 0;
  retention_tokens integer := 0;
  retention_audit_logs integer := 0;
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
  if auth.uid() is null or private.current_actor_role() = 'SUPER_ADMIN'::public.app_role then
    select rc.run_id, rc.notifications_expired, rc.deliveries_expired, rc.invalid_tokens_removed, rc.audit_logs_expired
    into retention_run_id, retention_notifications, retention_deliveries, retention_tokens, retention_audit_logs
    from public.run_retention_cleanup(false) rc;
  end if;

  result_payload := jsonb_build_object(
    'lifecycle_transitions', lifecycle_count,
    'tier_releases', tier_count,
    'reporting_reminders', reminder_count,
    'retention_cleanup_run_id', retention_run_id,
    'retention_notifications_expired', retention_notifications,
    'retention_deliveries_expired', retention_deliveries,
    'retention_invalid_tokens_removed', retention_tokens,
    'retention_audit_logs_expired', retention_audit_logs
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

revoke all on public.profile_photo_deletion_tasks from public, anon, authenticated;
grant select on public.profile_photo_deletion_tasks to authenticated;
grant all on public.profile_photo_deletion_tasks to service_role;

revoke all on function public.request_my_account_erasure(text) from public, anon;
revoke all on function public.my_account_erasure_requests(integer) from public, anon;
revoke all on function public.verify_account_erasure_request(uuid, boolean, text) from public, anon;
revoke all on function public.fulfill_due_erasure_requests(integer) from public, anon, authenticated;
revoke all on function public.complete_profile_photo_deletion_task(uuid, boolean, text) from public, anon, authenticated;

grant execute on function public.request_my_account_erasure(text) to authenticated;
grant execute on function public.my_account_erasure_requests(integer) to authenticated;
grant execute on function public.verify_account_erasure_request(uuid, boolean, text) to authenticated;
grant execute on function public.fulfill_due_erasure_requests(integer) to service_role;
grant execute on function public.complete_profile_photo_deletion_task(uuid, boolean, text) to service_role;
