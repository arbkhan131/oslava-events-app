-- Phase 14: FCM device registration, delivery outbox, and reporting reminders.

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null,
  token text not null,
  platform text not null,
  device_id text,
  app_environment text not null default 'local',
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  invalidated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint device_tokens_platform_valid check (platform in ('android', 'ios', 'web', 'other')),
  constraint device_tokens_environment_valid check (app_environment in ('local', 'development', 'production')),
  constraint device_tokens_token_not_blank check (btrim(token) <> ''),
  constraint device_tokens_token_hash_not_blank check (btrim(token_hash) <> ''),
  constraint device_tokens_active_pair check (
    (active and invalidated_at is null)
    or (not active and invalidated_at is not null)
  ),
  unique (user_id, token_hash)
);

create index device_tokens_user_active_idx
  on public.device_tokens(user_id, active, last_seen_at desc);

create unique index device_tokens_one_active_owner_idx
  on public.device_tokens(token_hash)
  where active;

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  device_token_id uuid references public.device_tokens(id) on delete set null,
  channel text not null default 'fcm',
  state text not null default 'PENDING',
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by text,
  provider_message_id text,
  provider_response_code text,
  provider_response text,
  sent_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_deliveries_channel_valid check (channel in ('fcm')),
  constraint notification_deliveries_state_valid check (
    state in ('PENDING', 'CLAIMED', 'SENT', 'FAILED', 'SKIPPED')
  ),
  constraint notification_deliveries_attempts_valid check (
    attempts >= 0 and max_attempts > 0 and attempts <= max_attempts
  ),
  unique (notification_id, device_token_id, channel)
);

create index notification_deliveries_retry_idx
  on public.notification_deliveries(state, next_attempt_at, created_at)
  where state in ('PENDING', 'FAILED');

create index notification_deliveries_notification_idx
  on public.notification_deliveries(notification_id, state);

create table public.reporting_reminder_schedules (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  worker_id uuid not null references public.profiles(id) on delete cascade,
  reminder_offset_hours integer not null,
  trigger_at timestamptz not null,
  notification_id uuid references public.notifications(id) on delete set null,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  skipped_at timestamptz,
  skip_reason text,
  constraint reporting_reminder_offsets_valid check (reminder_offset_hours in (24, 2)),
  constraint reporting_reminder_terminal_valid check (
    (processed_at is null and skipped_at is null)
    or (processed_at is not null and skipped_at is null and notification_id is not null)
    or (processed_at is null and skipped_at is not null and btrim(coalesce(skip_reason, '')) <> '')
  ),
  unique (assignment_id, reminder_offset_hours)
);

create index reporting_reminder_due_idx
  on public.reporting_reminder_schedules(trigger_at, processed_at)
  where processed_at is null and skipped_at is null;

alter table public.notifications
  add column deep_link_path text,
  add column delivery_created_at timestamptz;

create or replace function private.backoff_interval(p_attempts integer)
returns interval
language sql
immutable
set search_path = ''
as $$
  select make_interval(mins => least(60, greatest(1, (power(2, least(p_attempts, 6))::integer))));
$$;

create or replace function private.enqueue_notification_deliveries()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notification_deliveries (
    notification_id,
    device_token_id,
    channel,
    state,
    next_attempt_at
  )
  select
    new.id,
    dt.id,
    'fcm',
    'PENDING',
    now()
  from public.device_tokens dt
  where dt.user_id = new.recipient_id
    and dt.active
  on conflict (notification_id, device_token_id, channel) do nothing;

  update public.notifications
  set delivery_created_at = coalesce(delivery_created_at, now())
  where id = new.id;

  return new;
end;
$$;

create trigger notifications_enqueue_deliveries
  after insert on public.notifications
  for each row execute function private.enqueue_notification_deliveries();

create or replace function public.register_device_token(
  p_token text,
  p_platform text,
  p_device_id text default null,
  p_app_environment text default 'local'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_platform text := lower(btrim(coalesce(p_platform, 'other')));
  normalized_environment text := lower(btrim(coalesce(p_app_environment, 'local')));
  hashed_token text := encode(extensions.digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex');
  upserted_id uuid;
begin
  if caller_id is null then
    raise exception 'authentication required';
  end if;

  if btrim(coalesce(p_token, '')) = '' then
    raise exception 'device token is required';
  end if;

  if normalized_platform not in ('android', 'ios', 'web', 'other') then
    normalized_platform := 'other';
  end if;

  if normalized_environment not in ('local', 'development', 'production') then
    raise exception 'invalid app environment';
  end if;

  update public.device_tokens
  set active = false,
      invalidated_at = now(),
      updated_at = now()
  where token_hash = hashed_token
    and user_id <> caller_id
    and active;

  insert into public.device_tokens (
    user_id,
    token_hash,
    token,
    platform,
    device_id,
    app_environment,
    active,
    last_seen_at,
    invalidated_at
  )
  values (
    caller_id,
    hashed_token,
    btrim(p_token),
    normalized_platform,
    nullif(btrim(coalesce(p_device_id, '')), ''),
    normalized_environment,
    true,
    now(),
    null
  )
  on conflict (user_id, token_hash) do update
  set token = excluded.token,
      platform = excluded.platform,
      device_id = excluded.device_id,
      app_environment = excluded.app_environment,
      active = true,
      last_seen_at = now(),
      invalidated_at = null,
      updated_at = now()
  returning id into upserted_id;

  insert into public.notification_deliveries (
    notification_id,
    device_token_id,
    channel,
    state,
    next_attempt_at
  )
  select
    n.id,
    upserted_id,
    'fcm',
    'PENDING',
    now()
  from public.notifications n
  where n.recipient_id = caller_id
    and n.created_at >= now() - interval '7 days'
  on conflict (notification_id, device_token_id, channel) do nothing;

  return upserted_id;
end;
$$;

create or replace function public.invalidate_device_token(
  p_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  hashed_token text := encode(extensions.digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex');
  affected_count integer := 0;
begin
  if caller_id is null then
    raise exception 'authentication required';
  end if;

  update public.device_tokens
  set active = false,
      invalidated_at = now(),
      updated_at = now()
  where user_id = caller_id
    and token_hash = hashed_token
    and active;

  get diagnostics affected_count = row_count;
  return affected_count > 0;
end;
$$;

create or replace function public.list_my_notifications(
  p_limit integer default 50
)
returns table (
  notification_id uuid,
  notification_type public.notification_type,
  title text,
  body text,
  related_event_id uuid,
  deep_link_path text,
  read_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  return query
  select
    n.id,
    n.notification_type,
    n.title,
    n.body,
    n.related_event_id,
    n.deep_link_path,
    n.read_at,
    n.created_at
  from public.notifications n
  where n.recipient_id = auth.uid()
  order by n.created_at desc
  limit safe_limit;
end;
$$;

create or replace function public.mark_notification_read(
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  update public.notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and recipient_id = auth.uid();

  get diagnostics affected_count = row_count;
  return affected_count > 0;
end;
$$;

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
begin
  return query
  with claimed as (
    select nd.id
    from public.notification_deliveries nd
    join public.device_tokens dt on dt.id = nd.device_token_id
    where nd.state in ('PENDING', 'FAILED')
      and nd.next_attempt_at <= now()
      and nd.attempts < nd.max_attempts
      and dt.active
    order by nd.next_attempt_at, nd.created_at
    limit safe_limit
    for update of nd skip locked
  ),
  updated as (
    update public.notification_deliveries nd
    set state = 'CLAIMED',
        claimed_at = now(),
        claimed_by = nullif(btrim(coalesce(p_worker_id, '')), ''),
        attempts = nd.attempts + 1,
        updated_at = now()
    from claimed
    where nd.id = claimed.id
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

create or replace function public.complete_notification_delivery(
  p_delivery_id uuid,
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
begin
  select *
  into delivery_record
  from public.notification_deliveries
  where id = p_delivery_id
  for update;

  if delivery_record.id is null then
    raise exception 'notification delivery not found';
  end if;

  if p_success then
    update public.notification_deliveries
    set state = 'SENT',
        provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
        provider_response_code = nullif(btrim(coalesce(p_provider_response_code, '')), ''),
        provider_response = nullif(btrim(coalesce(p_provider_response, '')), ''),
        sent_at = now(),
        failed_at = null,
        updated_at = now()
    where id = p_delivery_id;
    final_state := 'SENT';
  else
    final_state := case
      when delivery_record.attempts >= delivery_record.max_attempts then 'FAILED'
      else 'PENDING'
    end;

    update public.notification_deliveries
    set state = final_state,
        provider_response_code = nullif(btrim(coalesce(p_provider_response_code, '')), ''),
        provider_response = nullif(btrim(coalesce(p_provider_response, '')), ''),
        next_attempt_at = case
          when final_state = 'PENDING' then now() + private.backoff_interval(delivery_record.attempts)
          else next_attempt_at
        end,
        failed_at = case when final_state = 'FAILED' then now() else null end,
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

create or replace function private.schedule_reporting_reminders_for_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_record public.events%rowtype;
  reminder_offset integer;
  reminder_trigger timestamptz;
begin
  if new.status <> 'CONFIRMED'::public.assignment_status then
    update public.reporting_reminder_schedules
    set skipped_at = coalesce(skipped_at, now()),
        skip_reason = coalesce(skip_reason, 'assignment not confirmed')
    where assignment_id = new.id
      and processed_at is null
      and skipped_at is null;
    return new;
  end if;

  select *
  into event_record
  from public.events
  where id = new.event_id;

  if event_record.id is null
     or event_record.event_status = 'CANCELLED'::public.event_status then
    return new;
  end if;

  foreach reminder_offset in array array[24, 2]
  loop
    reminder_trigger := event_record.reporting_at - make_interval(hours => reminder_offset);

    if reminder_trigger > now() then
      insert into public.reporting_reminder_schedules (
        assignment_id,
        event_id,
        worker_id,
        reminder_offset_hours,
        trigger_at
      )
      values (
        new.id,
        new.event_id,
        new.worker_id,
        reminder_offset,
        reminder_trigger
      )
      on conflict (assignment_id, reminder_offset_hours) do update
      set trigger_at = excluded.trigger_at,
          skipped_at = null,
          skip_reason = null;
    end if;
  end loop;

  return new;
end;
$$;

create trigger assignments_schedule_reporting_reminders
  after insert or update of status on public.assignments
  for each row execute function private.schedule_reporting_reminders_for_assignment();

create or replace function public.process_due_reporting_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_reminder record;
  created_notification_id uuid;
  processed_count integer := 0;
begin
  for due_reminder in
    select
      rs.id,
      rs.assignment_id,
      rs.event_id,
      rs.worker_id,
      rs.reminder_offset_hours,
      e.title,
      e.reporting_at,
      e.event_status,
      a.status as assignment_status
    from public.reporting_reminder_schedules rs
    join public.events e on e.id = rs.event_id
    join public.assignments a on a.id = rs.assignment_id
    where rs.processed_at is null
      and rs.skipped_at is null
      and rs.trigger_at <= now()
    order by rs.trigger_at, rs.id
    for update of rs skip locked
  loop
    if due_reminder.event_status = 'CANCELLED'::public.event_status
       or due_reminder.assignment_status <> 'CONFIRMED'::public.assignment_status then
      update public.reporting_reminder_schedules
      set skipped_at = now(),
          skip_reason = 'event cancelled or assignment not confirmed'
      where id = due_reminder.id;
      continue;
    end if;

    insert into public.notifications (
      recipient_id,
      notification_type,
      title,
      body,
      related_event_id,
      deduplication_key,
      deep_link_path
    )
    values (
      due_reminder.worker_id,
      'REPORTING_REMINDER'::public.notification_type,
      due_reminder.reminder_offset_hours::text || 'h reporting reminder',
      due_reminder.title || ' reporting time is approaching.',
      due_reminder.event_id,
      'reporting-reminder:' || due_reminder.assignment_id::text || ':' || due_reminder.reminder_offset_hours::text,
      '/worker/work'
    )
    on conflict (recipient_id, deduplication_key) do update
    set read_at = public.notifications.read_at
    returning id into created_notification_id;

    update public.reporting_reminder_schedules
    set processed_at = now(),
        notification_id = created_notification_id
    where id = due_reminder.id;

    processed_count := processed_count + 1;
  end loop;

  return processed_count;
end;
$$;

create or replace function public.process_due_tier_releases()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_rule record;
  processed_count integer := 0;
begin
  for due_rule in
    select r.id, r.event_id, r.category, r.opens_at, e.title, e.recruitment_status
    from public.event_tier_release_rules r
    join public.events e on e.id = r.event_id
    where r.processed_at is null
      and r.opens_at <= now()
      and e.event_status in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status)
      and e.recruitment_status <> 'CLOSED'::public.recruitment_status
    order by r.opens_at, private.category_rank(r.category)
    for update of r skip locked
  loop
    if due_rule.recruitment_status = 'NOT_OPEN'::public.recruitment_status then
      update public.events
      set recruitment_status = 'OPEN'::public.recruitment_status,
          updated_at = now()
      where id = due_rule.event_id
        and recruitment_status = 'NOT_OPEN'::public.recruitment_status;
    end if;

    if due_rule.recruitment_status <> 'FULL'::public.recruitment_status then
      insert into public.notifications (
        recipient_id,
        notification_type,
        title,
        body,
        related_event_id,
        deduplication_key,
        deep_link_path
      )
      select
        p.id,
        'TIER_OPENED'::public.notification_type,
        'Event access opened',
        due_rule.title || ' is now open for category ' || due_rule.category::text || '.',
        due_rule.event_id,
        'tier-opened:' || due_rule.event_id::text || ':' || due_rule.category::text || ':' || p.id::text,
        '/worker/events/' || due_rule.event_id::text
      from public.profiles p
      join public.worker_profiles wp on wp.user_id = p.id
      where p.role = 'WORKER'::public.app_role
        and p.account_status = 'ACTIVE'::public.account_status
        and wp.category = due_rule.category
        and public.is_worker_tier_eligible(due_rule.event_id, p.id, now())
        and not exists (
          select 1
          from public.assignments a
          where a.event_id = due_rule.event_id
            and a.worker_id = p.id
            and a.status = 'CONFIRMED'::public.assignment_status
        )
        and not public.has_booking_conflict(p.id, due_rule.event_id)
      on conflict (recipient_id, deduplication_key) do nothing;

      update public.event_tier_release_rules
      set notification_created_at = coalesce(notification_created_at, now())
      where id = due_rule.id;
    end if;

    update public.event_tier_release_rules
    set processed_at = coalesce(processed_at, now())
    where id = due_rule.id;

    processed_count := processed_count + 1;
  end loop;

  return processed_count;
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
declare
  event_title text;
  inserted_count integer := 0;
begin
  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can notify reopened vacancies';
  end if;

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
    deduplication_key,
    deep_link_path
  )
  select
    p.id,
    'VACANCY_REOPENED'::public.notification_type,
    'Vacancy reopened',
    event_title || ' has an available seat again.',
    p_event_id,
    'vacancy-reopened:' || p_event_id::text || ':' || p.id::text,
    '/worker/events/' || p_event_id::text
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

alter table public.device_tokens enable row level security;
alter table public.device_tokens force row level security;
alter table public.notification_deliveries enable row level security;
alter table public.notification_deliveries force row level security;
alter table public.reporting_reminder_schedules enable row level security;
alter table public.reporting_reminder_schedules force row level security;

revoke all on public.device_tokens from public, anon, authenticated;
revoke all on public.notification_deliveries from public, anon, authenticated;
revoke all on public.reporting_reminder_schedules from public, anon, authenticated;

grant select on public.device_tokens to authenticated;
grant select on public.notification_deliveries to authenticated;
grant select on public.reporting_reminder_schedules to authenticated;
grant all on public.device_tokens to service_role;
grant all on public.notification_deliveries to service_role;
grant all on public.reporting_reminder_schedules to service_role;

revoke all on function public.register_device_token(text, text, text, text) from public, anon;
revoke all on function public.invalidate_device_token(text) from public, anon;
revoke all on function public.list_my_notifications(integer) from public, anon;
revoke all on function public.mark_notification_read(uuid) from public, anon;
revoke all on function public.claim_notification_deliveries(text, integer) from public, anon, authenticated;
revoke all on function public.complete_notification_delivery(uuid, boolean, text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.process_due_reporting_reminders() from public, anon, authenticated;

grant execute on function public.register_device_token(text, text, text, text) to authenticated;
grant execute on function public.invalidate_device_token(text) to authenticated;
grant execute on function public.list_my_notifications(integer) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.claim_notification_deliveries(text, integer) to service_role;
grant execute on function public.complete_notification_delivery(uuid, boolean, text, text, text, boolean) to service_role;
grant execute on function public.process_due_reporting_reminders() to service_role;

create policy device_tokens_select_own
  on public.device_tokens
  for select
  to authenticated
  using (user_id = auth.uid());

create policy notification_deliveries_select_own
  on public.notification_deliveries
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.notifications n
      where n.id = notification_deliveries.notification_id
        and n.recipient_id = auth.uid()
    )
  );

create policy reporting_reminders_select_own
  on public.reporting_reminder_schedules
  for select
  to authenticated
  using (worker_id = auth.uid());
