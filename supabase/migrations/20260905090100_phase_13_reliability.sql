-- Phase 13: reliability scoring with versioned configuration and snapshots.

create table public.reliability_configs (
  version integer primary key,
  name text not null,
  show_up_weight numeric(5, 4) not null,
  punctuality_weight numeric(5, 4) not null,
  performance_weight numeric(5, 4) not null,
  commitment_weight numeric(5, 4) not null,
  minimum_resolved_commitments integer not null,
  effective_from timestamptz not null default now(),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  constraint reliability_configs_name_not_blank check (btrim(name) <> ''),
  constraint reliability_configs_weights_valid check (
    show_up_weight >= 0
    and punctuality_weight >= 0
    and performance_weight >= 0
    and commitment_weight >= 0
    and show_up_weight + punctuality_weight + performance_weight + commitment_weight = 1
  ),
  constraint reliability_configs_minimum_valid check (minimum_resolved_commitments >= 1)
);

insert into public.reliability_configs (
  version,
  name,
  show_up_weight,
  punctuality_weight,
  performance_weight,
  commitment_weight,
  minimum_resolved_commitments,
  published_at
)
values (
  1,
  'V1 approved reliability formula',
  0.45,
  0.20,
  0.20,
  0.15,
  3,
  now()
);

create or replace function private.prevent_published_reliability_config_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.published_at is not null then
    raise exception 'published reliability configurations are immutable';
  end if;

  return new;
end;
$$;

create trigger reliability_configs_published_immutable
  before update or delete on public.reliability_configs
  for each row execute function private.prevent_published_reliability_config_update();

alter table public.worker_profiles
  add column reliability_state text not null default 'PROVISIONAL',
  add column reliability_sample_count integer not null default 0,
  add column reliability_present_count integer not null default 0,
  add column reliability_late_count integer not null default 0,
  add column reliability_absent_count integer not null default 0,
  add column reliability_worker_cancellation_count integer not null default 0,
  add column reliability_completed_event_count integer not null default 0,
  add column reliability_performance_event_count integer not null default 0,
  add column reliability_performance_average numeric(5, 2),
  add column reliability_computed_at timestamptz,
  add constraint worker_profiles_reliability_state_valid check (
    reliability_state in ('PROVISIONAL', 'RATED')
  ),
  add constraint worker_profiles_reliability_counts_valid check (
    reliability_sample_count >= 0
    and reliability_present_count >= 0
    and reliability_late_count >= 0
    and reliability_absent_count >= 0
    and reliability_worker_cancellation_count >= 0
    and reliability_completed_event_count >= 0
    and reliability_performance_event_count >= 0
  ),
  add constraint worker_profiles_reliability_performance_valid check (
    reliability_performance_average is null
    or (reliability_performance_average >= 1 and reliability_performance_average <= 5)
  );

create table public.worker_reliability_snapshots (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete restrict,
  config_version integer not null references public.reliability_configs(version) on delete restrict,
  reliability_state text not null,
  score numeric(5, 2),
  sample_count integer not null,
  present_count integer not null,
  late_count integer not null,
  absent_count integer not null,
  worker_cancellation_count integer not null,
  eligible_commitment_count integer not null,
  completed_event_count integer not null,
  performance_event_count integer not null,
  performance_average numeric(5, 2),
  show_up_component numeric(5, 2),
  punctuality_component numeric(5, 2),
  performance_component numeric(5, 2),
  commitment_component numeric(5, 2),
  source_through_at timestamptz not null,
  source_hash text not null,
  computed_at timestamptz not null default now(),
  constraint worker_reliability_snapshots_state_valid check (
    reliability_state in ('PROVISIONAL', 'RATED')
  ),
  constraint worker_reliability_snapshots_score_valid check (
    score is null or (score >= 0 and score <= 100)
  ),
  constraint worker_reliability_snapshots_counts_valid check (
    sample_count >= 0
    and present_count >= 0
    and late_count >= 0
    and absent_count >= 0
    and worker_cancellation_count >= 0
    and eligible_commitment_count >= 0
    and completed_event_count >= 0
    and performance_event_count >= 0
  ),
  constraint worker_reliability_snapshots_source_unique unique (
    worker_id,
    config_version,
    source_hash
  )
);

create index worker_reliability_snapshots_worker_computed_idx
  on public.worker_reliability_snapshots(worker_id, computed_at desc);

create or replace function private.current_reliability_config_version()
returns integer
language sql
stable
set search_path = ''
as $$
  select version
  from public.reliability_configs
  where published_at is not null
    and effective_from <= now()
  order by effective_from desc, version desc
  limit 1;
$$;

create or replace function public.recompute_worker_reliability(
  p_worker_id uuid,
  p_config_version integer default null
)
returns table (
  worker_id uuid,
  reliability_state text,
  score numeric,
  sample_count integer,
  config_version integer,
  snapshot_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  config_record public.reliability_configs%rowtype;
  present_count integer := 0;
  late_count integer := 0;
  absent_count integer := 0;
  attended_count integer := 0;
  attendance_denominator integer := 0;
  worker_cancellations integer := 0;
  eligible_commitments integer := 0;
  completed_events integer := 0;
  performance_events integer := 0;
  performance_average numeric;
  show_up_component numeric;
  punctuality_component numeric;
  performance_component numeric;
  commitment_component numeric;
  weighted_total numeric := 0;
  available_weight numeric := 0;
  computed_score numeric;
  computed_state text;
  source_through timestamptz;
  calculated_hash text;
  inserted_snapshot_id uuid;
begin
  select *
  into config_record
  from public.reliability_configs
  where version = coalesce(p_config_version, private.current_reliability_config_version())
    and published_at is not null;

  if config_record.version is null then
    raise exception 'published reliability configuration not found';
  end if;

  if not exists (
    select 1
    from public.worker_profiles wp
    where wp.user_id = p_worker_id
  ) then
    raise exception 'worker profile not found';
  end if;

  perform 1
  from public.worker_profiles wp
  where wp.user_id = p_worker_id
  for update;

  select
    count(*) filter (where a.status = 'COMPLETED'::public.assignment_status)::integer
  into completed_events
  from public.assignments a
  where a.worker_id = p_worker_id;

  select
    count(*) filter (where att.status = 'PRESENT'::public.attendance_status)::integer,
    count(*) filter (where att.status = 'LATE'::public.attendance_status)::integer,
    count(*) filter (where att.status = 'ABSENT'::public.attendance_status)::integer
  into present_count, late_count, absent_count
  from public.attendance att
  where att.worker_id = p_worker_id;

  attendance_denominator := present_count + late_count + absent_count;
  attended_count := present_count + late_count;

  select count(*)::integer
  into worker_cancellations
  from public.cancellations c
  where c.worker_id = p_worker_id
    and c.cancellation_type = 'WORKER';

  select count(distinct source.assignment_id)::integer
  into eligible_commitments
  from (
    select att.assignment_id
    from public.attendance att
    where att.worker_id = p_worker_id
      and att.status in (
        'PRESENT'::public.attendance_status,
        'LATE'::public.attendance_status,
        'ABSENT'::public.attendance_status
      )
    union
    select c.assignment_id
    from public.cancellations c
    where c.worker_id = p_worker_id
      and c.cancellation_type = 'WORKER'
  ) source;

  select
    count(*)::integer,
    avg(event_average)::numeric
  into performance_events, performance_average
  from (
    select pr.event_id, avg(pr.stars)::numeric as event_average
    from public.performance_reviews pr
    where pr.worker_id = p_worker_id
    group by pr.event_id
  ) reviewed_events;

  if attendance_denominator > 0 then
    show_up_component := 100 * attended_count::numeric / attendance_denominator;
    weighted_total := weighted_total + show_up_component * config_record.show_up_weight;
    available_weight := available_weight + config_record.show_up_weight;
  end if;

  if attended_count > 0 then
    punctuality_component := 100 * present_count::numeric / attended_count;
    weighted_total := weighted_total + punctuality_component * config_record.punctuality_weight;
    available_weight := available_weight + config_record.punctuality_weight;
  end if;

  if performance_events > 0 then
    performance_component := ((performance_average - 1) / 4) * 100;
    weighted_total := weighted_total + performance_component * config_record.performance_weight;
    available_weight := available_weight + config_record.performance_weight;
  end if;

  if eligible_commitments > 0 then
    commitment_component := greatest(
      0,
      100 * (1 - worker_cancellations::numeric / eligible_commitments)
    );
    weighted_total := weighted_total + commitment_component * config_record.commitment_weight;
    available_weight := available_weight + config_record.commitment_weight;
  end if;

  computed_state := case
    when eligible_commitments >= config_record.minimum_resolved_commitments then 'RATED'
    else 'PROVISIONAL'
  end;

  if computed_state = 'RATED' and available_weight > 0 then
    computed_score := round(least(greatest(weighted_total / available_weight, 0), 100), 2);
  else
    computed_score := null;
  end if;

  select greatest(
    coalesce(max(a.updated_at), 'epoch'::timestamptz),
    coalesce(max(att.updated_at), 'epoch'::timestamptz),
    coalesce(max(c.created_at), 'epoch'::timestamptz),
    coalesce(max(pr.updated_at), 'epoch'::timestamptz)
  )
  into source_through
  from public.worker_profiles wp
  left join public.assignments a on a.worker_id = wp.user_id
  left join public.attendance att on att.worker_id = wp.user_id
  left join public.cancellations c on c.worker_id = wp.user_id
  left join public.performance_reviews pr on pr.worker_id = wp.user_id
  where wp.user_id = p_worker_id
  group by wp.user_id;

  source_through := greatest(coalesce(source_through, 'epoch'::timestamptz), config_record.published_at);

  calculated_hash := md5(jsonb_build_object(
    'config_version', config_record.version,
    'state', computed_state,
    'score', computed_score,
    'sample_count', eligible_commitments,
    'present_count', present_count,
    'late_count', late_count,
    'absent_count', absent_count,
    'worker_cancellation_count', worker_cancellations,
    'completed_event_count', completed_events,
    'performance_event_count', performance_events,
    'performance_average', round(performance_average, 2),
    'show_up_component', round(show_up_component, 2),
    'punctuality_component', round(punctuality_component, 2),
    'performance_component', round(performance_component, 2),
    'commitment_component', round(commitment_component, 2)
  )::text);

  insert into public.worker_reliability_snapshots (
    worker_id,
    config_version,
    reliability_state,
    score,
    sample_count,
    present_count,
    late_count,
    absent_count,
    worker_cancellation_count,
    eligible_commitment_count,
    completed_event_count,
    performance_event_count,
    performance_average,
    show_up_component,
    punctuality_component,
    performance_component,
    commitment_component,
    source_through_at,
    source_hash
  )
  values (
    p_worker_id,
    config_record.version,
    computed_state,
    computed_score,
    eligible_commitments,
    present_count,
    late_count,
    absent_count,
    worker_cancellations,
    eligible_commitments,
    completed_events,
    performance_events,
    round(performance_average, 2),
    round(show_up_component, 2),
    round(punctuality_component, 2),
    round(performance_component, 2),
    round(commitment_component, 2),
    source_through,
    calculated_hash
  )
  on conflict on constraint worker_reliability_snapshots_source_unique do update
  set source_through_at = excluded.source_through_at
  returning id into inserted_snapshot_id;

  perform set_config('app.bypass_identity_protection', 'on', true);

  begin
    update public.worker_profiles
    set reliability_score = computed_score,
        reliability_config_version = config_record.version,
        reliability_state = computed_state,
        reliability_sample_count = eligible_commitments,
        reliability_present_count = present_count,
        reliability_late_count = late_count,
        reliability_absent_count = absent_count,
        reliability_worker_cancellation_count = worker_cancellations,
        reliability_completed_event_count = completed_events,
        reliability_performance_event_count = performance_events,
        reliability_performance_average = round(performance_average, 2),
        reliability_computed_at = now(),
        updated_at = now()
    where user_id = p_worker_id;
  exception
    when others then
      perform set_config('app.bypass_identity_protection', 'off', true);
      raise;
  end;

  perform set_config('app.bypass_identity_protection', 'off', true);

  return query
  select
    p_worker_id,
    computed_state,
    computed_score,
    eligible_commitments,
    config_record.version,
    inserted_snapshot_id;
end;
$$;

create or replace function public.recompute_all_worker_reliability(
  p_config_version integer default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  worker_record record;
  recomputed_count integer := 0;
begin
  for worker_record in
    select wp.user_id
    from public.worker_profiles wp
  loop
    perform public.recompute_worker_reliability(worker_record.user_id, p_config_version);
    recomputed_count := recomputed_count + 1;
  end loop;

  return recomputed_count;
end;
$$;

create or replace function private.recompute_worker_reliability_from_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_worker_id uuid;
begin
  target_worker_id := coalesce(new.worker_id, old.worker_id);

  if target_worker_id is not null then
    perform public.recompute_worker_reliability(target_worker_id, null);
  end if;

  return coalesce(new, old);
end;
$$;

create trigger attendance_recompute_reliability
  after insert or update on public.attendance
  for each row execute function private.recompute_worker_reliability_from_source();

create trigger cancellations_recompute_reliability
  after insert or update on public.cancellations
  for each row execute function private.recompute_worker_reliability_from_source();

create trigger assignments_recompute_reliability
  after insert or update on public.assignments
  for each row execute function private.recompute_worker_reliability_from_source();

create trigger performance_reviews_recompute_reliability
  after insert or update on public.performance_reviews
  for each row execute function private.recompute_worker_reliability_from_source();

drop function public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer
);

create or replace function public.worker_directory(
  p_search_text text default null,
  p_account_filter public.account_status default null,
  p_category_filter public.worker_category default null,
  p_result_limit integer default 50
)
returns table (
  user_id uuid,
  worker_number bigint,
  full_name text,
  initials text,
  phone_e164 text,
  profile_photo_path text,
  role public.app_role,
  account_status public.account_status,
  category public.worker_category,
  last_worker_category public.worker_category,
  reliability_score numeric,
  reliability_state text,
  reliability_sample_count integer,
  reliability_present_count integer,
  reliability_late_count integer,
  reliability_absent_count integer,
  reliability_worker_cancellation_count integer,
  reliability_completed_event_count integer,
  reliability_performance_event_count integer,
  reliability_performance_average numeric,
  reliability_config_version integer,
  profile_completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  safe_limit integer := least(greatest(coalesce(p_result_limit, 50), 1), 100);
  query_text text := '%' || lower(btrim(coalesce(p_search_text, ''))) || '%';
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not private.can_view_worker_records() then
    raise exception 'not authorized to view worker directory';
  end if;

  return query
  select
    p.id,
    p.worker_number,
    p.full_name,
    p.initials,
    p.phone_e164,
    p.profile_photo_path,
    p.role,
    p.account_status,
    wp.category,
    wp.last_worker_category,
    wp.reliability_score,
    wp.reliability_state,
    wp.reliability_sample_count,
    wp.reliability_present_count,
    wp.reliability_late_count,
    wp.reliability_absent_count,
    wp.reliability_worker_cancellation_count,
    wp.reliability_completed_event_count,
    wp.reliability_performance_event_count,
    wp.reliability_performance_average,
    wp.reliability_config_version,
    p.profile_completed_at
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where (p_account_filter is null or p.account_status = p_account_filter)
    and (p_category_filter is null or wp.category = p_category_filter)
    and (
      btrim(coalesce(p_search_text, '')) = ''
      or lower(p.full_name) like query_text
      or lower(p.initials) like query_text
      or p.phone_e164 like '%' || btrim(p_search_text) || '%'
      or p.worker_number::text like '%' || btrim(p_search_text) || '%'
    )
  order by p.full_name, p.worker_number
  limit safe_limit;
end;
$$;

drop function public.worker_profile_detail(uuid);

create or replace function public.worker_profile_detail(p_target_user_id uuid)
returns table (
  user_id uuid,
  worker_number bigint,
  full_name text,
  initials text,
  phone_e164 text,
  profile_photo_path text,
  role public.app_role,
  account_status public.account_status,
  category public.worker_category,
  last_worker_category public.worker_category,
  date_of_birth date,
  address text,
  native_place text,
  height_cm numeric,
  education_status text,
  has_previous_experience boolean,
  experience_details text,
  reliability_score numeric,
  reliability_state text,
  reliability_sample_count integer,
  reliability_present_count integer,
  reliability_late_count integer,
  reliability_absent_count integer,
  reliability_worker_cancellation_count integer,
  reliability_completed_event_count integer,
  reliability_performance_event_count integer,
  reliability_performance_average numeric,
  reliability_config_version integer,
  reliability_computed_at timestamptz,
  profile_completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_target_user_id <> auth.uid() and not private.can_view_worker_records() then
    raise exception 'not authorized to view worker profile';
  end if;

  return query
  select
    p.id,
    p.worker_number,
    p.full_name,
    p.initials,
    p.phone_e164,
    p.profile_photo_path,
    p.role,
    p.account_status,
    wp.category,
    wp.last_worker_category,
    wp.date_of_birth,
    wp.address,
    wp.native_place,
    wp.height_cm,
    wp.education_status,
    wp.has_previous_experience,
    wp.experience_details,
    wp.reliability_score,
    wp.reliability_state,
    wp.reliability_sample_count,
    wp.reliability_present_count,
    wp.reliability_late_count,
    wp.reliability_absent_count,
    wp.reliability_worker_cancellation_count,
    wp.reliability_completed_event_count,
    wp.reliability_performance_event_count,
    wp.reliability_performance_average,
    wp.reliability_config_version,
    wp.reliability_computed_at,
    p.profile_completed_at
  from public.profiles p
  join public.worker_profiles wp on wp.user_id = p.id
  where p.id = p_target_user_id;
end;
$$;

grant execute on function public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer
) to authenticated;
grant execute on function public.worker_profile_detail(uuid) to authenticated;

alter table public.reliability_configs enable row level security;
alter table public.reliability_configs force row level security;
alter table public.worker_reliability_snapshots enable row level security;
alter table public.worker_reliability_snapshots force row level security;

revoke all on public.reliability_configs from public, anon, authenticated;
revoke all on public.worker_reliability_snapshots from public, anon, authenticated;

grant select on public.reliability_configs to authenticated;
grant select on public.worker_reliability_snapshots to authenticated;
grant all on public.reliability_configs to service_role;
grant all on public.worker_reliability_snapshots to service_role;

revoke all on function public.recompute_worker_reliability(uuid, integer) from public, anon;
revoke all on function public.recompute_all_worker_reliability(integer) from public, anon;

grant execute on function public.recompute_worker_reliability(uuid, integer) to service_role;
grant execute on function public.recompute_all_worker_reliability(integer) to service_role;

create policy reliability_configs_select_published
  on public.reliability_configs
  for select
  to authenticated
  using (published_at is not null);

create policy worker_reliability_snapshots_select_own
  on public.worker_reliability_snapshots
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy worker_reliability_snapshots_select_staff
  on public.worker_reliability_snapshots
  for select
  to authenticated
  using (private.can_view_worker_records());
