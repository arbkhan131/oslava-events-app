-- Actor lookups used inside RLS must not recursively re-enter profiles RLS.
create or replace function private.current_actor_role()
returns public.app_role
language sql
security definer
stable
set search_path = ''
as $$
  select role
  from public.profiles
  where id = auth.uid();
$$;
revoke all on function private.current_actor_role() from public, anon;
grant execute on function private.current_actor_role() to authenticated, service_role;

create or replace function private.current_account_status()
returns public.account_status
language sql
security definer
stable
set search_path = ''
as $$
  select account_status
  from public.profiles
  where id = auth.uid();
$$;
revoke all on function private.current_account_status() from public, anon;
grant execute on function private.current_account_status() to authenticated, service_role;

create or replace function private.can_view_worker_records()
returns boolean
language sql
security definer
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
revoke all on function private.can_view_worker_records() from public, anon;
grant execute on function private.can_view_worker_records() to authenticated, service_role;

create or replace function private.can_manage_events()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.account_status = 'ACTIVE'::public.account_status
      and p.role in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role)
  );
$$;
revoke all on function private.can_manage_events() from public, anon;
grant execute on function private.can_manage_events() to authenticated, service_role;

-- Readiness R1: privileged identity safety and terminal event reconciliation.
-- Existing RPC signatures/grants and finalized attendance/reliability rules remain intact.
create or replace function private.lock_privileged_identity_mutation()
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- Serialize before reading actor/target state, including simultaneous last-admin changes.
  perform pg_catalog.pg_advisory_xact_lock(20260909, 1);
  if private.current_actor_role() in ('ADMIN', 'SUPER_ADMIN')
    and private.current_account_status() is distinct from 'ACTIVE'::public.account_status then
    raise exception 'an active Admin or Super Admin is required';
  end if;
end;
$$;
revoke all on function private.lock_privileged_identity_mutation() from public, anon, authenticated;

create or replace function private.protect_last_active_super_admin(p_target uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.profiles where id = p_target
      and role = 'SUPER_ADMIN' and account_status = 'ACTIVE')
    and not exists (select 1 from public.profiles where id <> p_target
      and role = 'SUPER_ADMIN' and account_status = 'ACTIVE') then
    raise exception 'the last active Super Admin cannot be removed';
  end if;
end;
$$;
revoke all on function private.protect_last_active_super_admin(uuid) from public, anon, authenticated;


create or replace function public.request_account_erasure(
  p_target_user_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  request_id uuid;
  old_profile public.profiles%rowtype;
begin
  perform private.lock_privileged_identity_mutation();
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can record erasure requests';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_profile
  from public.profiles
  where id = p_target_user_id
  for update;

  if old_profile.id is null then
    raise exception 'profile not found';
  end if;

  if actor_role = 'ADMIN' and old_profile.role in ('ADMIN', 'SUPER_ADMIN') then
    raise exception 'Admin cannot manage Admin or Super Admin accounts';
  end if;
  perform private.protect_last_active_super_admin(p_target_user_id);

  perform set_config('app.bypass_identity_protection', 'on', true);

  update public.profiles
  set account_status = 'INACTIVE'::public.account_status
  where id = p_target_user_id;

  perform set_config('app.bypass_identity_protection', 'off', true);

  insert into public.account_erasure_requests (
    target_user_id,
    requested_by,
    requested_by_role,
    reason
  )
  values (
    p_target_user_id,
    auth.uid(),
    actor_role,
    p_reason
  )
  returning id into request_id;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'account_erasure_requested',
    'profile',
    p_target_user_id,
    to_jsonb(old_profile),
    jsonb_build_object(
      'account_status', 'INACTIVE',
      'erasure_request_id', request_id,
      'due_at', now() + interval '30 days'
    ),
    p_reason,
    'database'
  );

  return request_id;
end;
$$;

create or replace function public.change_user_role(
  target_user_id uuid,
  new_role public.app_role,
  reason text,
  restore_worker_category public.worker_category default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_role public.app_role;
  old_status public.account_status;
  restored_category public.worker_category;
  has_worker_profile boolean;
begin
  perform private.lock_privileged_identity_mutation();
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can change roles';
  end if;

  select role, account_status
  into old_role, old_status
  from public.profiles
  where id = target_user_id
  for update;

  if old_role is null then
    raise exception 'target profile not found';
  end if;

  if btrim(coalesce(reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  if actor_role = 'ADMIN'::public.app_role
     and (
       old_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role)
       or new_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role)
     ) then
    raise exception 'Admin cannot manage Admin or Super Admin authority';
  end if;

  if old_role = new_role then
    return;
  end if;

  select exists (
    select 1
    from public.worker_profiles wp
    where wp.user_id = target_user_id
  )
  into has_worker_profile;

  if old_role = 'SUPER_ADMIN' and new_role <> 'SUPER_ADMIN' then
    perform private.protect_last_active_super_admin(target_user_id);
  end if;
  perform set_config('app.bypass_identity_protection', 'on', true);

  if old_role in ('CAPTAIN'::public.app_role, 'SUPERVISOR'::public.app_role)
     and new_role = 'WORKER'::public.app_role
     and not has_worker_profile then
    update public.profiles
    set account_status = 'INACTIVE'::public.account_status
    where id = target_user_id;

    insert into public.account_actions (
      target_user_id,
      old_status,
      new_status,
      action_type,
      reason,
      actor_id,
      actor_role
    )
    values (
      target_user_id,
      old_status,
      'INACTIVE'::public.account_status,
      'STAFF_ACCESS_REVOKED',
      reason,
      auth.uid(),
      actor_role
    );

    insert into public.audit_logs (
      actor_id,
      actor_role,
      action,
      entity_type,
      entity_id,
      before_values,
      after_values,
      reason,
      source
    )
    values (
      auth.uid(),
      actor_role,
      'staff_only_access_revoked',
      'profile',
      target_user_id,
      jsonb_build_object('role', old_role, 'account_status', old_status),
      jsonb_build_object(
        'role', old_role,
        'account_status', 'INACTIVE',
        'staff_only_revocation', true,
        'requires_explicit_worker_onboarding', true
      ),
      reason,
      'database'
    );

    perform set_config('app.bypass_identity_protection', 'off', true);
    return;
  end if;

  if old_role = 'WORKER'::public.app_role
     and new_role <> 'WORKER'::public.app_role then
    update public.worker_profiles
    set last_worker_category = coalesce(category, last_worker_category),
        category = null
    where user_id = target_user_id;

    insert into public.audit_logs (
      actor_id,
      actor_role,
      action,
      entity_type,
      entity_id,
      before_values,
      after_values,
      reason,
      source
    )
    values (
      auth.uid(),
      actor_role,
      'worker_role_changed_operational_effects',
      'profile',
      target_user_id,
      jsonb_build_object('role', old_role),
      jsonb_build_object(
        'role', new_role,
        'active_worker_category', null,
        'assignment_flag_type', 'WORKER_ROLE_CHANGED',
        'confirmed_assignments_retained', true,
        'active_waitlist_entries_withdrawn_without_penalty', true,
        'integration_deferred_until_assignments_and_waitlist_tables_exist', true
      ),
      reason,
      'database'
    );
  elsif old_role <> 'WORKER'::public.app_role
        and new_role = 'WORKER'::public.app_role then
    select coalesce(restore_worker_category, last_worker_category)
    into restored_category
    from public.worker_profiles
    where user_id = target_user_id;

    if restored_category is null then
      raise exception 'explicit Worker onboarding is required for staff-only accounts';
    end if;

    update public.worker_profiles
    set category = restored_category,
        last_worker_category = restored_category
    where user_id = target_user_id;

    insert into public.worker_category_history (
      worker_id,
      old_category,
      new_category,
      action,
      actor_id,
      actor_role,
      reason
    )
    values (
      target_user_id,
      null,
      restored_category,
      'ROLE_RESTORATION',
      auth.uid(),
      actor_role,
      reason
    );
  end if;

  update public.profiles
  set role = new_role,
      account_status = case
        when old_status = 'INACTIVE'::public.account_status
          and new_role = 'WORKER'::public.app_role
          and has_worker_profile
          then 'ACTIVE'::public.account_status
        else account_status
      end
  where id = target_user_id;

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason,
    restored_worker_category
  )
  values (
    target_user_id,
    old_role,
    new_role,
    auth.uid(),
    actor_role,
    reason,
    restored_category
  );

  perform set_config('app.bypass_identity_protection', 'off', true);
end;
$$;

create or replace function public.change_user_phone(
  target_user_id uuid,
  new_phone_e164 text,
  reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  target_role public.app_role;
  old_phone text;
  normalized_phone text;
begin
  perform private.lock_privileged_identity_mutation();
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can change phone numbers';
  end if;

  if btrim(coalesce(reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select role, phone_e164
  into target_role, old_phone
  from public.profiles
  where id = target_user_id
  for update;

  if target_role is null then
    raise exception 'target profile not found';
  end if;

  if actor_role = 'ADMIN'::public.app_role
     and target_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role) then
    raise exception 'Admin cannot manage Admin or Super Admin authority';
  end if;

  normalized_phone := private.normalize_phone(new_phone_e164);

  if old_phone = normalized_phone then
    raise exception 'new phone number must differ from current phone number';
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

  update auth.users
  set phone = normalized_phone,
      phone_confirmed_at = coalesce(phone_confirmed_at, now()),
      updated_at = now()
  where id = target_user_id;

  update public.profiles
  set phone_e164 = normalized_phone
  where id = target_user_id;

  insert into public.phone_change_history (
    target_user_id,
    old_phone_e164,
    new_phone_e164,
    actor_id,
    actor_role,
    reason
  )
  values (
    target_user_id,
    old_phone,
    normalized_phone,
    auth.uid(),
    actor_role,
    reason
  );

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'user_phone_changed',
    'profile',
    target_user_id,
    jsonb_build_object('phone_e164', old_phone),
    jsonb_build_object('phone_e164', normalized_phone),
    reason,
    'database'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);
end;
$$;

create or replace function public.provision_staff_profile(
  target_user_id uuid,
  target_role public.app_role,
  full_name text,
  initials text,
  phone_e164 text,
  reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  normalized_phone text;
begin
  perform private.lock_privileged_identity_mutation();
  if btrim(coalesce(reason, '')) = '' then
    raise exception 'reason is required';
  end if;
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can provision staff profiles';
  end if;

  if target_role = 'WORKER'::public.app_role then
    raise exception 'use complete_worker_registration for workers';
  end if;

  if actor_role = 'ADMIN'::public.app_role
     and target_role in ('ADMIN'::public.app_role, 'SUPER_ADMIN'::public.app_role) then
    raise exception 'Admin cannot manage Admin or Super Admin authority';
  end if;

  normalized_phone := private.normalize_phone(phone_e164);

  perform set_config('app.bypass_identity_protection', 'on', true);

  insert into public.profiles (
    id,
    role,
    full_name,
    initials,
    phone_e164,
    account_status
  )
  values (
    target_user_id,
    target_role,
    btrim(full_name),
    btrim(initials),
    normalized_phone,
    'ACTIVE'::public.account_status
  );

  insert into public.role_history (
    user_id,
    old_role,
    new_role,
    actor_id,
    actor_role,
    reason
  )
  values (
    target_user_id,
    null,
    target_role,
    auth.uid(),
    actor_role,
    reason
  );

  perform set_config('app.bypass_identity_protection', 'off', true);

  return target_user_id;
end;
$$;

create or replace function public.change_account_status(
  p_target_user_id uuid,
  p_new_status public.account_status,
  p_reason text,
  p_related_event_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  target_role public.app_role;
  old_status public.account_status;
  action_id uuid;
begin
  perform private.lock_privileged_identity_mutation();
  actor_role := private.current_actor_role();

  if actor_role is null or actor_role not in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role) then
    raise exception 'only Admin or Super Admin can change account status';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select role, account_status
  into target_role, old_status
  from public.profiles
  where id = p_target_user_id
  for update;

  if target_role is null then
    raise exception 'target profile not found';
  end if;

  if target_role <> 'WORKER'::public.app_role then
    raise exception 'Phase 4 account detention/release applies to Workers only';
  end if;

  if p_new_status not in ('ACTIVE'::public.account_status, 'DETAINED'::public.account_status) then
    raise exception 'Phase 4 supports only Detain and Release';
  end if;

  if old_status = p_new_status then
    return null;
  end if;

  perform set_config('app.bypass_identity_protection', 'on', true);

  update public.profiles
  set account_status = p_new_status
  where id = p_target_user_id;

  insert into public.account_actions (
    target_user_id,
    old_status,
    new_status,
    action_type,
    reason,
    related_event_id,
    actor_id,
    actor_role,
    notes
  )
  values (
    p_target_user_id,
    old_status,
    p_new_status,
    case
      when p_new_status = 'DETAINED'::public.account_status then 'DETAIN'
      when p_new_status = 'ACTIVE'::public.account_status then 'RELEASE'
      else 'STATUS_CHANGE'
    end,
    p_reason,
    p_related_event_id,
    auth.uid(),
    actor_role,
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning id into action_id;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    related_event_id,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'account_status_changed',
    'profile',
    p_target_user_id,
    jsonb_build_object('account_status', old_status),
    jsonb_build_object('account_status', p_new_status),
    p_reason,
    p_related_event_id,
    'database'
  );

  perform set_config('app.bypass_identity_protection', 'off', true);

  return action_id;
end;
$$;

create or replace function private.reconcile_terminal_event(
  p_event_id uuid, p_actor uuid, p_actor_role public.app_role, p_reason text,
  p_notify boolean default true
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  ev public.events%rowtype;
  item public.assignments%rowtype;
  entry public.waitlist_entries%rowtype;
  terminal_at timestamptz;
begin
  select * into ev from public.events where id = p_event_id for update;
  if ev.event_status not in ('CANCELLED', 'COMPLETED', 'CLOSED') then
    raise exception 'terminal event required';
  end if;
  -- Use the recorded transition time for legacy repair; do not invent attendance.
  select coalesce(ev.cancelled_at, min(h.created_at), ev.updated_at)
  into terminal_at from public.event_history h
  where h.event_id = ev.id and h.action in ('EVENT_COMPLETED', 'EVENT_CLOSED');

  if ev.event_status = 'CANCELLED' and p_notify then
    insert into public.notifications
      (recipient_id, notification_type, title, body, related_event_id, deduplication_key)
    select recipient_id, 'EVENT_CANCELLED', 'Event cancelled',
      ev.title || ' has been cancelled.', ev.id, 'event-cancelled:' || ev.id::text
    from (
      select worker_id as recipient_id from public.assignments where event_id = ev.id and status = 'CONFIRMED'
      union select worker_id from public.waitlist_entries where event_id = ev.id and status = 'WAITING'
      union select user_id from public.event_leaders where event_id = ev.id and removed_at is null
    ) recipients
    on conflict (recipient_id, deduplication_key) do nothing;
  end if;

  for item in select * from public.assignments
      where event_id = ev.id and status = 'CONFIRMED' order by worker_id, id for update
  loop
    if ev.event_status = 'CANCELLED' then
      insert into public.cancellations
        (assignment_id, event_id, worker_id, actor_id, actor_role, cancellation_type,
         reason, idempotency_key, requested_at, deadline_at, within_deadline, refill_result)
      values (item.id, ev.id, item.worker_id, p_actor, p_actor_role, 'EVENT',
        p_reason, 'event-cancelled:' || item.id::text, terminal_at,
        ev.reporting_at - interval '1 hour', terminal_at <= ev.reporting_at - interval '1 hour',
        'EVENT_TERMINAL');
      update public.assignments set status = 'CANCELLED', updated_at = now() where id = item.id;
    else
      update public.assignments set status = 'COMPLETED',
        completed_at = coalesce(completed_at, terminal_at), updated_at = now() where id = item.id;
    end if;
    insert into public.audit_logs
      (actor_id, actor_role, action, entity_type, entity_id, before_values, after_values, reason, source)
    select p_actor, p_actor_role, 'assignment_event_reconciled', 'assignment', item.id,
      to_jsonb(item), to_jsonb(a), p_reason, 'database'
    from public.assignments a where a.id = item.id;
  end loop;

  for entry in select * from public.waitlist_entries
      where event_id = ev.id and status = 'WAITING' order by id for update
  loop
    update public.waitlist_entries set status = 'EXPIRED', penalty_applies = false,
      skip_reason = 'Event ' || lower(ev.event_status::text), updated_at = now() where id = entry.id;
    insert into public.audit_logs
      (actor_id, actor_role, action, entity_type, entity_id, before_values, after_values, reason, source)
    select p_actor, p_actor_role, 'waitlist_event_expired', 'waitlist_entry', entry.id,
      to_jsonb(entry), to_jsonb(w), p_reason, 'database'
    from public.waitlist_entries w where w.id = entry.id;
  end loop;
  update public.reporting_reminder_schedules set skipped_at = now(),
    skip_reason = 'Event ' || lower(ev.event_status::text)
  where event_id = ev.id and processed_at is null and skipped_at is null;
end;
$$;
revoke all on function private.reconcile_terminal_event(uuid, uuid, public.app_role, text, boolean)
  from public, anon, authenticated;


create or replace function public.cancel_event(
  p_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status in ('CANCELLED'::public.event_status, 'CLOSED'::public.event_status) then
    raise exception 'terminal events cannot be cancelled again';
  end if;

  if old_event.event_status = 'COMPLETED'::public.event_status then
    raise exception 'completed events must be closed or resolved, not cancelled';
  end if;

  update public.events
  set event_status = 'CANCELLED'::public.event_status,
      recruitment_status = 'CLOSED'::public.recruitment_status,
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      updated_by = auth.uid(),
      published_at = coalesce(published_at, now()),
      version = version + 1
  where id = p_event_id;

  perform private.reconcile_terminal_event(p_event_id, auth.uid(), actor_role, p_reason);

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
    'EVENT_CANCELLED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
  );

  insert into public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    source
  )
  values (
    auth.uid(),
    actor_role,
    'event_cancelled',
    'event',
    p_event_id,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason,
    'database'
  );
end;
$$;

create or replace function public.complete_event(
  p_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status <> 'IN_PROGRESS'::public.event_status then
    raise exception 'only in-progress events can be completed';
  end if;

  update public.events
  set event_status = 'COMPLETED'::public.event_status,
      recruitment_status = 'CLOSED'::public.recruitment_status,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_event_id;

  perform private.reconcile_terminal_event(p_event_id, auth.uid(), actor_role, p_reason);

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
    'EVENT_COMPLETED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
  );
end;
$$;

create or replace function public.close_event(
  p_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.app_role;
  old_event public.events%rowtype;
begin
  actor_role := private.current_actor_role();

  if not private.can_manage_events() then
    raise exception 'only Admin or Super Admin can manage events';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason is required';
  end if;

  select *
  into old_event
  from public.events
  where id = p_event_id
  for update;

  if old_event.id is null then
    raise exception 'event not found';
  end if;

  if old_event.event_status <> 'COMPLETED'::public.event_status then
    raise exception 'only completed events can be closed';
  end if;

  update public.events
  set event_status = 'CLOSED'::public.event_status,
      recruitment_status = 'CLOSED'::public.recruitment_status,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_event_id;

  perform private.reconcile_terminal_event(p_event_id, auth.uid(), actor_role, p_reason);

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
    'EVENT_CLOSED',
    auth.uid(),
    actor_role,
    to_jsonb(old_event),
    private.event_snapshot(p_event_id),
    p_reason
  );
end;
$$;

create or replace function public.set_attendance(
  p_assignment_id uuid,
  p_status public.attendance_status,
  p_notes text default null
)
returns table (
  assignment_id uuid,
  event_id uuid,
  worker_id uuid,
  attendance_status public.attendance_status,
  marked_by uuid,
  marker_role public.app_role,
  marked_at timestamptz,
  notes text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.assignments%rowtype;
  event_record public.events%rowtype;
  actor_role public.app_role;
begin
  actor_role := private.current_actor_role();

  if actor_role is null then
    raise exception 'authentication required';
  end if;

  perform 1 from public.events e
  where e.id = (select a.event_id from public.assignments a where a.id = p_assignment_id)
  for update;

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
    raise exception 'attendance is allowed only for confirmed or completed assignments';
  end if;

  select *
  into event_record
  from public.events
  where id = assignment_record.event_id
  for update;

  if event_record.event_status in (
    'DRAFT'::public.event_status,
    'CANCELLED'::public.event_status
  ) then
    raise exception 'attendance is unavailable for this event status';
  end if;

  if not private.can_set_attendance(event_record.id, event_record.event_status) then
    raise exception 'not authorized to set attendance';
  end if;

  insert into public.attendance (
    assignment_id,
    event_id,
    worker_id,
    status,
    marked_by,
    marker_role,
    marked_at,
    notes
  )
  values (
    assignment_record.id,
    assignment_record.event_id,
    assignment_record.worker_id,
    p_status,
    auth.uid(),
    actor_role,
    now(),
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  on conflict on constraint attendance_pkey do update
  set status = excluded.status,
      marked_by = excluded.marked_by,
      marker_role = excluded.marker_role,
      marked_at = excluded.marked_at,
      notes = excluded.notes;

  return query
  select
    att.assignment_id,
    att.event_id,
    att.worker_id,
    att.status,
    att.marked_by,
    att.marker_role,
    att.marked_at,
    att.notes
  from public.attendance att
  where att.assignment_id = assignment_record.id;
end;
$$;

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

  perform 1 from public.events e
  where e.id = (select a.event_id from public.assignments a where a.id = p_assignment_id)
  for update;

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

  perform 1 from public.events e
  where e.id = (select a.event_id from public.assignments a where a.id = p_assignment_id)
  for update;

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
      when p.event_status = 'CANCELLED'::public.event_status then 'CANCELLED'
      when p.event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) then 'COMPLETED'
      when p.has_confirmed_assignment then 'CONFIRMED'
      when p.has_waiting_waitlist then 'WAITLISTED'
      when p.recruitment_status = 'FULL'::public.recruitment_status then 'FULL'
      when p.recruitment_status = 'CLOSED'::public.recruitment_status then 'CLOSED'
      when public.is_worker_tier_eligible(p.id, p.viewer_id, now()) then 'AVAILABLE'
      else 'LOCKED'
    end,
    case
      when p.event_status = 'CANCELLED'::public.event_status then 'Cancelled'
      when p.event_status in ('COMPLETED'::public.event_status, 'CLOSED'::public.event_status) then 'Completed'
      when p.has_confirmed_assignment then 'Confirmed'
      when p.has_waiting_waitlist then 'Waitlisted'
      when p.recruitment_status = 'FULL'::public.recruitment_status then 'Join Waitlist'
      when p.recruitment_status = 'CLOSED'::public.recruitment_status then 'Closed'
      when public.is_worker_tier_eligible(p.id, p.viewer_id, now()) then 'Apply'
      else 'Locked'
    end
  from projected p
  order by p.reporting_at, p.title;
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
    case when e.event_status = 'CANCELLED' and a.status = 'CONFIRMED' then 'CANCELLED'::public.assignment_status
      when e.event_status in ('COMPLETED', 'CLOSED') and a.status = 'CONFIRMED' then 'COMPLETED'::public.assignment_status
      else a.status end,
    e.reporting_at - interval '1 hour',
    a.status = 'CONFIRMED'::public.assignment_status
      and e.event_status not in ('CANCELLED', 'COMPLETED', 'CLOSED')
      and now() <= e.reporting_at - interval '1 hour'
  from public.assignments a
  join public.events e on e.id = a.event_id
  where a.worker_id = auth.uid()
  order by e.reporting_at desc;
$$;

-- Repair only inconsistent existing terminal records, preserving the original actor
-- and history. Do not send retrospective notifications during migration.
do $$
declare ev public.events%rowtype;
begin
  for ev in select * from public.events where event_status in ('CANCELLED', 'COMPLETED', 'CLOSED') order by id
  loop
    perform private.reconcile_terminal_event(ev.id, coalesce(ev.cancelled_by, ev.updated_by),
      (select role from public.profiles where id = coalesce(ev.cancelled_by, ev.updated_by)),
      'R1 repair of existing terminal event records', false);
  end loop;
end;
$$;

