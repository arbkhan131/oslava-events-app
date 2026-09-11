-- R12: notify event leaders when their assigned event becomes active.

create or replace function private.enqueue_event_leader_notifications(p_event_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_count integer := 0;
begin
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
    el.user_id,
    case el.leader_role
      when 'CAPTAIN'::public.leader_role then 'CAPTAIN_ASSIGNED'::public.notification_type
      when 'SUPERVISOR'::public.leader_role then 'SUPERVISOR_ASSIGNED'::public.notification_type
    end,
    case el.leader_role
      when 'CAPTAIN'::public.leader_role then 'Captain assigned'
      when 'SUPERVISOR'::public.leader_role then 'Supervisor assigned'
    end,
    e.title || ' has been published and assigned to you.',
    e.id,
    'leader-assigned:' || e.id::text || ':' || el.user_id::text || ':' || el.leader_role::text,
    '/field/events/' || e.id::text
  from public.event_leaders el
  join public.events e on e.id = el.event_id
  join public.profiles p on p.id = el.user_id
  where el.event_id = p_event_id
    and el.removed_at is null
    and e.event_status in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status, 'IN_PROGRESS'::public.event_status)
    and p.account_status = 'ACTIVE'::public.account_status
    and p.role::text = el.leader_role::text
  on conflict (recipient_id, deduplication_key) do nothing;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

create or replace function private.notify_event_leaders_after_publish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.event_status = 'DRAFT'::public.event_status
     and new.event_status in ('PUBLISHED'::public.event_status, 'UPCOMING'::public.event_status, 'IN_PROGRESS'::public.event_status) then
    perform private.enqueue_event_leader_notifications(new.id);
  end if;
  return new;
end;
$$;

create or replace function private.notify_event_leader_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.enqueue_event_leader_notifications(new.event_id);
  return new;
end;
$$;

drop trigger if exists events_notify_leaders_after_publish on public.events;
create trigger events_notify_leaders_after_publish
  after update of event_status on public.events
  for each row execute function private.notify_event_leaders_after_publish();

drop trigger if exists event_leaders_notify_after_insert on public.event_leaders;
create trigger event_leaders_notify_after_insert
  after insert on public.event_leaders
  for each row execute function private.notify_event_leader_after_insert();

revoke all on function private.enqueue_event_leader_notifications(uuid) from public, anon, authenticated;
revoke all on function private.notify_event_leaders_after_publish() from public, anon, authenticated;
revoke all on function private.notify_event_leader_after_insert() from public, anon, authenticated;
