-- Phase 2: Supabase schema and security foundation.
-- Feature tables and domain RPCs are introduced by their owning phases.

create extension if not exists pgcrypto with schema extensions;

revoke create on schema public from public;
revoke all on schema public from public;
grant usage on schema public to anon, authenticated, service_role;

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
grant usage on schema private to postgres, service_role;

do $$
begin
  create type public.app_role as enum (
    'SUPER_ADMIN',
    'ADMIN',
    'CAPTAIN',
    'SUPERVISOR',
    'WORKER'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.worker_category as enum ('A', 'B', 'C', 'F');
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.account_status as enum (
    'ACTIVE',
    'SUSPENDED',
    'DETAINED',
    'BLACKLISTED',
    'INACTIVE'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.event_status as enum (
    'DRAFT',
    'PUBLISHED',
    'UPCOMING',
    'IN_PROGRESS',
    'COMPLETED',
    'CLOSED',
    'CANCELLED'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.recruitment_status as enum (
    'NOT_OPEN',
    'OPEN',
    'FULL',
    'CLOSED'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.tier_strategy as enum (
    'STANDARD',
    'URGENT',
    'EMERGENCY',
    'CUSTOM'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.leader_role as enum ('CAPTAIN', 'SUPERVISOR');
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.assignment_status as enum (
    'CONFIRMED',
    'CANCELLED',
    'REMOVED',
    'COMPLETED'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.booking_result as enum (
    'PENDING',
    'CONFIRMED',
    'FULL',
    'WAITLIST_AVAILABLE',
    'WAITLISTED',
    'LOCKED',
    'CONFLICT',
    'RESTRICTED',
    'DUPLICATE',
    'INVALID_REQUIREMENTS',
    'EVENT_UNAVAILABLE',
    'ERROR'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.waitlist_status as enum (
    'WAITING',
    'PROMOTED',
    'WITHDRAWN',
    'SKIPPED',
    'EXPIRED'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.attendance_status as enum (
    'NOT_MARKED',
    'PRESENT',
    'LATE',
    'ABSENT'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.notification_type as enum (
    'NEW_EVENT',
    'TIER_OPENED',
    'APPLICATION_CONFIRMED',
    'WAITLIST_JOINED',
    'WAITLIST_PROMOTED',
    'CAPTAIN_ASSIGNED',
    'SUPERVISOR_ASSIGNED',
    'EVENT_FULL',
    'EVENT_UPDATED',
    'EVENT_CANCELLED',
    'REPORTING_REMINDER',
    'CATEGORY_CHANGED',
    'ACCOUNT_DETAINED',
    'VACANCY_REOPENED'
  );
exception
  when duplicate_object then null;
end
$$;

create sequence if not exists public.worker_number_seq
  as bigint
  start with 100001
  increment by 1
  no minvalue
  no maxvalue
  cache 1;

revoke all on sequence public.worker_number_seq from public;
revoke all on sequence public.worker_number_seq from anon;
revoke all on sequence public.worker_number_seq from authenticated;
grant usage, select on sequence public.worker_number_seq to service_role;

create or replace function private.category_rank(category public.worker_category)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case category
    when 'A'::public.worker_category then 1
    when 'B'::public.worker_category then 2
    when 'C'::public.worker_category then 3
    when 'F'::public.worker_category then 4
  end;
$$;

create or replace function private.is_admin_role(role public.app_role)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select role in ('SUPER_ADMIN'::public.app_role, 'ADMIN'::public.app_role);
$$;

create or replace function private.is_field_leader_role(role public.app_role)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select role in ('CAPTAIN'::public.app_role, 'SUPERVISOR'::public.app_role);
$$;

create or replace function private.current_auth_user_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select auth.uid();
$$;

create table if not exists public.audit_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid,
  actor_role public.app_role,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_values jsonb,
  after_values jsonb,
  reason text,
  related_event_id uuid,
  request_id text,
  source text not null default 'database',
  created_at timestamptz not null default now(),
  constraint audit_logs_action_not_blank check (btrim(action) <> ''),
  constraint audit_logs_entity_type_not_blank check (btrim(entity_type) <> ''),
  constraint audit_logs_source_not_blank check (btrim(source) <> '')
);

alter table public.audit_logs enable row level security;
alter table public.audit_logs force row level security;

revoke all on public.audit_logs from public;
revoke all on public.audit_logs from anon;
revoke all on public.audit_logs from authenticated;
grant select, insert on public.audit_logs to service_role;

create or replace function private.reject_audit_log_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'audit_logs are append-only';
end;
$$;

drop trigger if exists audit_logs_no_update on public.audit_logs;
create trigger audit_logs_no_update
  before update on public.audit_logs
  for each row execute function private.reject_audit_log_mutation();

drop trigger if exists audit_logs_no_delete on public.audit_logs;
create trigger audit_logs_no_delete
  before delete on public.audit_logs
  for each row execute function private.reject_audit_log_mutation();

alter default privileges in schema public revoke all on tables from public;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on tables from authenticated;
alter default privileges in schema public revoke all on sequences from public;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on sequences from authenticated;
alter default privileges in schema public revoke all on functions from public;
alter default privileges in schema public revoke all on functions from anon;
alter default privileges in schema public revoke all on functions from authenticated;

alter default privileges in schema private revoke all on tables from public;
alter default privileges in schema private revoke all on tables from anon;
alter default privileges in schema private revoke all on tables from authenticated;
alter default privileges in schema private revoke all on functions from public;
alter default privileges in schema private revoke all on functions from anon;
alter default privileges in schema private revoke all on functions from authenticated;
