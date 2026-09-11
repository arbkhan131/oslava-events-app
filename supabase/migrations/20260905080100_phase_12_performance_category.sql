-- Phase 12: performance reviews and audited one-step category changes.

create table public.performance_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  assignment_id uuid not null references public.assignments(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  reviewer_role public.app_role not null,
  stars smallint not null,
  tags text[] not null default array[]::text[],
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_reviews_stars_range check (stars between 1 and 5),
  constraint performance_reviews_notes_not_blank check (
    notes is null or btrim(notes) <> ''
  ),
  constraint performance_reviews_reviewer_worker_event_unique unique (
    reviewer_id,
    worker_id,
    event_id
  )
);

create index performance_reviews_worker_event_idx
  on public.performance_reviews(worker_id, event_id);

create index performance_reviews_reviewer_idx
  on public.performance_reviews(reviewer_id, created_at desc);

create table public.performance_review_history (
  id uuid primary key default extensions.gen_random_uuid(),
  review_id uuid not null references public.performance_reviews(id) on delete restrict,
  event_id uuid not null references public.events(id) on delete restrict,
  assignment_id uuid not null references public.assignments(id) on delete restrict,
  worker_id uuid not null references public.profiles(id) on delete restrict,
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  reviewer_role public.app_role not null,
  old_stars smallint,
  new_stars smallint not null,
  old_tags text[],
  new_tags text[] not null,
  old_notes text,
  new_notes text,
  created_at timestamptz not null default now()
);

create index performance_review_history_review_created_idx
  on public.performance_review_history(review_id, created_at desc);

create index performance_review_history_worker_created_idx
  on public.performance_review_history(worker_id, created_at desc);

create or replace function private.can_change_worker_category()
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.account_status = 'ACTIVE'::public.account_status
      and p.role in (
        'SUPER_ADMIN'::public.app_role,
        'ADMIN'::public.app_role,
        'CAPTAIN'::public.app_role,
        'SUPERVISOR'::public.app_role
      )
  );
$$;

create or replace function private.audit_performance_review_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.performance_review_history (
    review_id,
    event_id,
    assignment_id,
    worker_id,
    reviewer_id,
    reviewer_role,
    old_stars,
    new_stars,
    old_tags,
    new_tags,
    old_notes,
    new_notes
  )
  values (
    new.id,
    new.event_id,
    new.assignment_id,
    new.worker_id,
    new.reviewer_id,
    new.reviewer_role,
    case when tg_op = 'UPDATE' then old.stars else null end,
    new.stars,
    case when tg_op = 'UPDATE' then old.tags else null end,
    new.tags,
    case when tg_op = 'UPDATE' then old.notes else null end,
    new.notes
  );

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    related_event_id,
    source
  )
  values (
    new.reviewer_id,
    new.reviewer_role,
    case when tg_op = 'UPDATE' then 'performance_review_updated' else 'performance_review_created' end,
    'performance_review',
    new.id,
    case
      when tg_op = 'UPDATE' then jsonb_build_object(
        'stars', old.stars,
        'tags', old.tags,
        'notes', old.notes
      )
      else null
    end,
    jsonb_build_object(
      'assignment_id', new.assignment_id,
      'worker_id', new.worker_id,
      'stars', new.stars,
      'tags', new.tags,
      'notes', new.notes
    ),
    new.event_id,
    'database'
  );

  return new;
end;
$$;

create trigger performance_reviews_touch_updated_at
  before update on public.performance_reviews
  for each row execute function private.touch_updated_at();

create trigger performance_reviews_audit_change
  after insert or update on public.performance_reviews
  for each row execute function private.audit_performance_review_change();

create or replace function public.record_performance_review(
  p_assignment_id uuid,
  p_stars integer,
  p_tags text[] default array[]::text[],
  p_notes text default null
)
returns table (
  review_id uuid,
  event_id uuid,
  assignment_id uuid,
  worker_id uuid,
  reviewer_id uuid,
  reviewer_role public.app_role,
  stars smallint,
  tags text[],
  notes text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.assignments%rowtype;
  event_record public.events%rowtype;
  actor_role public.app_role;
  normalized_tags text[] := array[]::text[];
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  actor_role := private.current_actor_role();

  if actor_role is null then
    raise exception 'authentication required';
  end if;

  if actor_role not in (
    'SUPER_ADMIN'::public.app_role,
    'ADMIN'::public.app_role,
    'CAPTAIN'::public.app_role,
    'SUPERVISOR'::public.app_role
  ) then
    raise exception 'not authorized to record performance reviews';
  end if;

  if p_stars is null or p_stars < 1 or p_stars > 5 then
    raise exception 'performance rating must be between 1 and 5';
  end if;

  select *
  into assignment_record
  from public.assignments
  where id = p_assignment_id
  for update;

  if assignment_record.id is null then
    raise exception 'assignment not found';
  end if;

  if assignment_record.status not in (
    'CONFIRMED'::public.assignment_status,
    'COMPLETED'::public.assignment_status
  ) then
    raise exception 'performance review is allowed only for confirmed or completed assignments';
  end if;

  select *
  into event_record
  from public.events
  where id = assignment_record.event_id
  for update;

  if event_record.event_status = 'CLOSED'::public.event_status then
    raise exception 'performance reviews are closed for this event';
  end if;

  if event_record.event_status in (
    'DRAFT'::public.event_status,
    'CANCELLED'::public.event_status
  ) then
    raise exception 'performance review is unavailable for this event status';
  end if;

  if not private.can_view_event_operations(event_record.id) then
    raise exception 'not authorized for event operations';
  end if;

  select coalesce(array_agg(distinct tag order by tag), array[]::text[])
  into normalized_tags
  from (
    select nullif(btrim(tag_value), '') as tag
    from unnest(coalesce(p_tags, array[]::text[])) as tag_value
  ) tags
  where tag is not null;

  insert into public.performance_reviews (
    event_id,
    assignment_id,
    worker_id,
    reviewer_id,
    reviewer_role,
    stars,
    tags,
    notes
  )
  values (
    assignment_record.event_id,
    assignment_record.id,
    assignment_record.worker_id,
    auth.uid(),
    actor_role,
    p_stars::smallint,
    normalized_tags,
    normalized_notes
  )
  on conflict on constraint performance_reviews_reviewer_worker_event_unique do update
  set assignment_id = excluded.assignment_id,
      reviewer_role = excluded.reviewer_role,
      stars = excluded.stars,
      tags = excluded.tags,
      notes = excluded.notes;

  return query
  select
    pr.id,
    pr.event_id,
    pr.assignment_id,
    pr.worker_id,
    pr.reviewer_id,
    pr.reviewer_role,
    pr.stars,
    pr.tags,
    pr.notes,
    pr.updated_at
  from public.performance_reviews pr
  where pr.reviewer_id = auth.uid()
    and pr.worker_id = assignment_record.worker_id
    and pr.event_id = assignment_record.event_id;
end;
$$;

create or replace function public.change_worker_category(
  p_worker_id uuid,
  p_new_category public.worker_category,
  p_reason text,
  p_notes text default null
)
returns table (
  worker_id uuid,
  old_category public.worker_category,
  new_category public.worker_category
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  worker_record public.worker_profiles%rowtype;
  target_role public.app_role;
  target_status public.account_status;
  action_text text;
  normalized_reason text := btrim(coalesce(p_reason, ''));
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  actor_role := private.current_actor_role();

  if actor_role is null then
    raise exception 'authentication required';
  end if;

  if not private.can_change_worker_category() then
    raise exception 'not authorized to change worker category';
  end if;

  if p_new_category is null then
    raise exception 'new worker category is required';
  end if;

  if normalized_reason = '' then
    raise exception 'category change reason is required';
  end if;

  select wp.*
  into worker_record
  from public.worker_profiles wp
  where wp.user_id = p_worker_id
  for update;

  if worker_record.user_id is null then
    raise exception 'worker profile not found';
  end if;

  select p.role, p.account_status
  into target_role, target_status
  from public.profiles p
  where p.id = p_worker_id
  for update;

  if target_role <> 'WORKER'::public.app_role then
    raise exception 'category changes apply only to active Worker role users';
  end if;

  if target_status <> 'ACTIVE'::public.account_status then
    raise exception 'category changes require an active Worker account';
  end if;

  if worker_record.category is null then
    raise exception 'target Worker has no active category';
  end if;

  if worker_record.category = p_new_category then
    raise exception 'new category must differ from current category';
  end if;

  if abs(private.category_rank(worker_record.category) - private.category_rank(p_new_category)) <> 1 then
    raise exception 'category changes must move exactly one step';
  end if;

  action_text := case
    when private.category_rank(p_new_category) < private.category_rank(worker_record.category)
      then 'PROMOTION'
    else 'DEMOTION'
  end;

  perform set_config('app.bypass_identity_protection', 'on', true);

  begin
    update public.worker_profiles
    set category = p_new_category,
        last_worker_category = p_new_category,
        updated_at = now()
    where user_id = p_worker_id;

    insert into public.worker_category_history (
      worker_id,
      old_category,
      new_category,
      action,
      actor_id,
      actor_role,
      reason,
      notes
    )
    values (
      p_worker_id,
      worker_record.category,
      p_new_category,
      action_text,
      auth.uid(),
      actor_role,
      normalized_reason,
      normalized_notes
    );
  exception
    when others then
      perform set_config('app.bypass_identity_protection', 'off', true);
      raise;
  end;

  perform set_config('app.bypass_identity_protection', 'off', true);

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'worker_category_changed',
    'worker_profile',
    p_worker_id,
    jsonb_build_object('category', worker_record.category),
    jsonb_build_object('category', p_new_category, 'reason', normalized_reason),
    'database'
  );

  insert into public.notifications (
    recipient_id,
    notification_type,
    title,
    body,
    deduplication_key
  )
  values (
    p_worker_id,
    'CATEGORY_CHANGED'::public.notification_type,
    'Category updated',
    'Your worker category changed from ' || worker_record.category::text || ' to ' || p_new_category::text || '.',
    'category-change:' || p_worker_id::text || ':' || clock_timestamp()::text
  );

  return query
  select p_worker_id, worker_record.category, p_new_category;
end;
$$;

alter table public.performance_reviews enable row level security;
alter table public.performance_reviews force row level security;
alter table public.performance_review_history enable row level security;
alter table public.performance_review_history force row level security;

revoke all on public.performance_reviews from public, anon, authenticated;
revoke all on public.performance_review_history from public, anon, authenticated;

grant select on public.performance_reviews to authenticated;
grant select on public.performance_review_history to authenticated;
grant all on public.performance_reviews to service_role;
grant all on public.performance_review_history to service_role;

revoke all on function public.record_performance_review(uuid, integer, text[], text) from public, anon;
revoke all on function public.change_worker_category(uuid, public.worker_category, text, text) from public, anon;

grant execute on function public.record_performance_review(uuid, integer, text[], text) to authenticated;
grant execute on function public.change_worker_category(uuid, public.worker_category, text, text) to authenticated;

create policy performance_reviews_select_own_worker
  on public.performance_reviews
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy performance_reviews_select_reviewer
  on public.performance_reviews
  for select
  to authenticated
  using (reviewer_id = auth.uid());

create policy performance_reviews_select_worker_records
  on public.performance_reviews
  for select
  to authenticated
  using (private.can_view_worker_records());

create policy performance_review_history_select_own_worker
  on public.performance_review_history
  for select
  to authenticated
  using (worker_id = auth.uid());

create policy performance_review_history_select_reviewer
  on public.performance_review_history
  for select
  to authenticated
  using (reviewer_id = auth.uid());

create policy performance_review_history_select_worker_records
  on public.performance_review_history
  for select
  to authenticated
  using (private.can_view_worker_records());
