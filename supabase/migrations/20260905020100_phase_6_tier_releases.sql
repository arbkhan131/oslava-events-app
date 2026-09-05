create table public.tier_release_presets (
  tier_strategy public.tier_strategy primary key,
  display_name text not null,
  a_offset_minutes integer not null,
  b_offset_minutes integer not null,
  c_offset_minutes integer not null,
  f_offset_minutes integer not null,
  created_at timestamptz not null default now(),
  constraint tier_release_presets_not_custom check (tier_strategy <> 'CUSTOM'::public.tier_strategy),
  constraint tier_release_presets_non_negative check (
    a_offset_minutes >= 0
    and b_offset_minutes >= 0
    and c_offset_minutes >= 0
    and f_offset_minutes >= 0
  ),
  constraint tier_release_presets_ordered check (
    a_offset_minutes <= b_offset_minutes
    and b_offset_minutes <= c_offset_minutes
    and c_offset_minutes <= f_offset_minutes
  )
);

insert into public.tier_release_presets (
  tier_strategy,
  display_name,
  a_offset_minutes,
  b_offset_minutes,
  c_offset_minutes,
  f_offset_minutes
)
values
  ('STANDARD', 'Standard', 0, 30, 60, 180),
  ('URGENT', 'Urgent', 0, 15, 30, 60),
  ('EMERGENCY', 'Emergency', 0, 5, 10, 15)
on conflict (tier_strategy) do update
set display_name = excluded.display_name,
    a_offset_minutes = excluded.a_offset_minutes,
    b_offset_minutes = excluded.b_offset_minutes,
    c_offset_minutes = excluded.c_offset_minutes,
    f_offset_minutes = excluded.f_offset_minutes;

create table public.event_tier_custom_offsets (
  event_id uuid primary key references public.events(id) on delete cascade,
  a_offset_minutes integer not null,
  b_offset_minutes integer not null,
  c_offset_minutes integer not null,
  f_offset_minutes integer not null,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  constraint event_tier_custom_offsets_non_negative check (
    a_offset_minutes >= 0
    and b_offset_minutes >= 0
    and c_offset_minutes >= 0
    and f_offset_minutes >= 0
  ),
  constraint event_tier_custom_offsets_ordered check (
    a_offset_minutes <= b_offset_minutes
    and b_offset_minutes <= c_offset_minutes
    and c_offset_minutes <= f_offset_minutes
  )
);

create table public.event_tier_release_rules (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  category public.worker_category not null,
  release_offset_minutes integer not null,
  opens_at timestamptz not null,
  processed_at timestamptz,
  notification_created_at timestamptz,
  source_strategy public.tier_strategy not null,
  created_at timestamptz not null default now(),
  constraint event_tier_release_rules_non_negative check (release_offset_minutes >= 0),
  unique (event_id, category)
);

create index event_tier_release_rules_due_idx
  on public.event_tier_release_rules (opens_at, processed_at)
  where processed_at is null;

create index event_tier_release_rules_event_idx
  on public.event_tier_release_rules (event_id, category);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  notification_type public.notification_type not null,
  title text not null,
  body text not null,
  related_event_id uuid references public.events(id) on delete cascade,
  deduplication_key text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_title_not_blank check (btrim(title) <> ''),
  constraint notifications_body_not_blank check (btrim(body) <> ''),
  unique (recipient_id, deduplication_key)
);

create index notifications_recipient_created_idx
  on public.notifications (recipient_id, created_at desc);

alter table public.tier_release_presets enable row level security;
alter table public.event_tier_custom_offsets enable row level security;
alter table public.event_tier_release_rules enable row level security;
alter table public.notifications enable row level security;

create policy "authenticated can read tier release presets"
  on public.tier_release_presets
  for select
  to authenticated
  using (true);

create policy "event managers can read custom tier offsets"
  on public.event_tier_custom_offsets
  for select
  to authenticated
  using (private.can_manage_events());

create policy "event managers can read tier release rules"
  on public.event_tier_release_rules
  for select
  to authenticated
  using (private.can_manage_events());

create policy "workers can read release rules for visible events"
  on public.event_tier_release_rules
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.events e
      where e.id = event_tier_release_rules.event_id
        and e.event_status not in ('DRAFT'::public.event_status, 'CANCELLED'::public.event_status)
    )
  );

create policy "users can read own notifications"
  on public.notifications
  for select
  to authenticated
  using (recipient_id = auth.uid());

create policy "users can mark own notifications read"
  on public.notifications
  for update
  to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create or replace function private.tier_offsets_for_event(
  p_event_id uuid,
  p_strategy public.tier_strategy
)
returns table(category public.worker_category, offset_minutes integer)
language sql
stable
set search_path = ''
as $$
  select v.category, v.offset_minutes
  from public.tier_release_presets p
  cross join lateral (
    values
      ('A'::public.worker_category, p.a_offset_minutes),
      ('B'::public.worker_category, p.b_offset_minutes),
      ('C'::public.worker_category, p.c_offset_minutes),
      ('F'::public.worker_category, p.f_offset_minutes)
  ) as v(category, offset_minutes)
  where p.tier_strategy = p_strategy
    and p_strategy <> 'CUSTOM'::public.tier_strategy

  union all

  select v.category, v.offset_minutes
  from public.event_tier_custom_offsets c
  cross join lateral (
    values
      ('A'::public.worker_category, c.a_offset_minutes),
      ('B'::public.worker_category, c.b_offset_minutes),
      ('C'::public.worker_category, c.c_offset_minutes),
      ('F'::public.worker_category, c.f_offset_minutes)
  ) as v(category, offset_minutes)
  where c.event_id = p_event_id
    and p_strategy = 'CUSTOM'::public.tier_strategy;
$$;

create or replace function private.create_event_tier_release_rules(
  p_event_id uuid,
  p_strategy public.tier_strategy,
  p_published_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rules_created integer;
begin
  insert into public.event_tier_release_rules (
    event_id,
    category,
    release_offset_minutes,
    opens_at,
    source_strategy
  )
  select
    p_event_id,
    offsets.category,
    offsets.offset_minutes,
    p_published_at + make_interval(mins => offsets.offset_minutes),
    p_strategy
  from private.tier_offsets_for_event(p_event_id, p_strategy) offsets
  on conflict (event_id, category) do nothing;

  get diagnostics rules_created = row_count;

  if rules_created <> 4 then
    raise exception 'tier release configuration must define A, B, C, and F exactly once';
  end if;
end;
$$;

create or replace function public.configure_event_tier_offsets(
  p_event_id uuid,
  p_a_offset_minutes integer,
  p_b_offset_minutes integer,
  p_c_offset_minutes integer,
  p_f_offset_minutes integer,
  p_reason text default 'Configured custom tier release offsets'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  target_event public.events%rowtype;
  old_offsets jsonb;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can configure event tier releases';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  if p_a_offset_minutes < 0
    or p_b_offset_minutes < 0
    or p_c_offset_minutes < 0
    or p_f_offset_minutes < 0 then
    raise exception 'tier release offsets cannot be negative';
  end if;

  if not (
    p_a_offset_minutes <= p_b_offset_minutes
    and p_b_offset_minutes <= p_c_offset_minutes
    and p_c_offset_minutes <= p_f_offset_minutes
  ) then
    raise exception 'tier release offsets must expand in A, B, C, F order';
  end if;

  select *
  into target_event
  from public.events
  where id = p_event_id
  for update;

  if target_event.id is null then
    raise exception 'event not found';
  end if;

  if target_event.tier_strategy <> 'CUSTOM'::public.tier_strategy then
    raise exception 'custom tier offsets can only be configured for custom strategy events';
  end if;

  if target_event.event_status <> 'DRAFT'::public.event_status then
    raise exception 'custom tier offsets can only be changed while the event is draft';
  end if;

  select to_jsonb(existing)
  into old_offsets
  from public.event_tier_custom_offsets existing
  where existing.event_id = p_event_id;

  insert into public.event_tier_custom_offsets (
    event_id,
    a_offset_minutes,
    b_offset_minutes,
    c_offset_minutes,
    f_offset_minutes,
    updated_by
  )
  values (
    p_event_id,
    p_a_offset_minutes,
    p_b_offset_minutes,
    p_c_offset_minutes,
    p_f_offset_minutes,
    auth.uid()
  )
  on conflict (event_id) do update
  set a_offset_minutes = excluded.a_offset_minutes,
      b_offset_minutes = excluded.b_offset_minutes,
      c_offset_minutes = excluded.c_offset_minutes,
      f_offset_minutes = excluded.f_offset_minutes,
      updated_by = excluded.updated_by,
      updated_at = now();

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    before_values,
    after_values,
    reason
  )
  values (
    p_event_id,
    'TIER_RELEASE_CONFIGURED',
    auth.uid(),
    actor_role,
    coalesce(old_offsets, '{}'::jsonb),
    (
      select to_jsonb(updated)
      from public.event_tier_custom_offsets updated
      where updated.event_id = p_event_id
    ),
    p_reason
  );
end;
$$;

create or replace function public.publish_event(
  p_event_id uuid,
  p_reason text default 'Event published'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
  effective_published_at timestamptz := now();
  first_opens_at timestamptz;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status <> 'DRAFT'::public.event_status then
    raise exception 'only draft events can be published';
  end if;

  perform private.create_event_tier_release_rules(
    p_event_id,
    old_event.tier_strategy,
    effective_published_at
  );

  select min(opens_at)
  into first_opens_at
  from public.event_tier_release_rules
  where event_id = p_event_id;

  update public.events
  set event_status = case
        when event_date <= (effective_published_at at time zone 'Asia/Kolkata')::date
          then 'UPCOMING'::public.event_status
        else 'PUBLISHED'::public.event_status
      end,
      recruitment_status = case
        when first_opens_at <= effective_published_at
          then 'OPEN'::public.recruitment_status
        else 'NOT_OPEN'::public.recruitment_status
      end,
      published_at = effective_published_at,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_event_id;

  insert into public.event_history (
    event_id,
    action,
    actor_id,
    actor_role,
    before_values,
    after_values,
    reason
  )
  values (
    p_event_id,
    'EVENT_PUBLISHED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
  );
end;
$$;

create or replace function public.is_worker_tier_eligible(
  p_event_id uuid,
  p_worker_id uuid,
  p_at timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.worker_profiles wp on wp.user_id = p.id
    join public.events e on e.id = p_event_id
    join public.event_tier_release_rules r
      on r.event_id = e.id
      and r.category = wp.category
    where p.id = p_worker_id
      and p.role = 'WORKER'::public.app_role
      and p.account_status = 'ACTIVE'::public.account_status
      and wp.category is not null
      and e.event_status in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status)
      and e.recruitment_status <> 'CLOSED'::public.recruitment_status
      and r.opens_at <= p_at
  );
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
        deduplication_key
      )
      select
        p.id,
        'TIER_OPENED'::public.notification_type,
        'Event access opened',
        due_rule.title || ' is now open for category ' || due_rule.category::text || '.',
        due_rule.event_id,
        'tier-opened:' || due_rule.event_id::text || ':' || due_rule.category::text
      from public.profiles p
      join public.worker_profiles wp on wp.user_id = p.id
      where p.role = 'WORKER'::public.app_role
        and p.account_status = 'ACTIVE'::public.account_status
        and wp.category = due_rule.category
        and public.is_worker_tier_eligible(due_rule.event_id, p.id, now())
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
  on conflict (recipient_id, deduplication_key) do nothing;

  get diagnostics inserted_count = row_count;

  return inserted_count;
end;
$$;

revoke all on table public.tier_release_presets from public, anon, authenticated;
revoke all on table public.event_tier_custom_offsets from public, anon, authenticated;
revoke all on table public.event_tier_release_rules from public, anon, authenticated;
revoke all on table public.notifications from public, anon, authenticated;

grant select on table public.tier_release_presets to authenticated;
grant select on table public.event_tier_custom_offsets to authenticated;
grant select on table public.event_tier_release_rules to authenticated;
grant select, update (read_at) on table public.notifications to authenticated;

grant all on table public.tier_release_presets to service_role;
grant all on table public.event_tier_custom_offsets to service_role;
grant all on table public.event_tier_release_rules to service_role;
grant all on table public.notifications to service_role;

revoke all on function public.configure_event_tier_offsets(uuid, integer, integer, integer, integer, text) from public, anon;
revoke all on function public.publish_event(uuid, text) from public, anon;
revoke all on function public.is_worker_tier_eligible(uuid, uuid, timestamptz) from public, anon;
revoke all on function public.process_due_tier_releases() from public, anon, authenticated;
revoke all on function public.notify_vacancy_reopened(uuid) from public, anon;

grant execute on function public.configure_event_tier_offsets(uuid, integer, integer, integer, integer, text) to authenticated;
grant execute on function public.publish_event(uuid, text) to authenticated;
grant execute on function public.is_worker_tier_eligible(uuid, uuid, timestamptz) to authenticated;
grant execute on function public.process_due_tier_releases() to service_role;
grant execute on function public.notify_vacancy_reopened(uuid) to authenticated, service_role;
