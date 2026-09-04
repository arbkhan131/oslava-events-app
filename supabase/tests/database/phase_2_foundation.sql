begin;

create extension if not exists pgtap with schema extensions;

select plan(44);

select ok(
  exists (
    select 1 from pg_extension where extname = 'pgcrypto'
  ),
  'pgcrypto extension is installed'
);

select ok(
  exists (
    select 1 from pg_extension where extname = 'pgtap'
  ),
  'pgtap extension is installed for database tests'
);

select has_schema('private', 'private schema exists');

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE'),
  'anon cannot use private schema'
);

select ok(
  not has_schema_privilege('authenticated', 'private', 'USAGE'),
  'authenticated cannot use private schema'
);

select ok(
  has_schema_privilege('service_role', 'private', 'USAGE'),
  'service_role can use private schema'
);

select ok(
  not has_schema_privilege('public', 'public', 'CREATE'),
  'public cannot create objects in public schema'
);

select ok(
  has_schema_privilege('anon', 'public', 'USAGE'),
  'anon has explicit public schema usage'
);

select ok(
  has_schema_privilege('authenticated', 'public', 'USAGE'),
  'authenticated has explicit public schema usage'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'app_role'
  ),
  array['SUPER_ADMIN', 'ADMIN', 'CAPTAIN', 'SUPERVISOR', 'WORKER']::text[],
  'app_role enum preserves finalized role labels'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'worker_category'
  ),
  array['A', 'B', 'C', 'F']::text[],
  'worker_category enum preserves category order labels'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'account_status'
  ),
  array['ACTIVE', 'SUSPENDED', 'DETAINED', 'BLACKLISTED', 'INACTIVE']::text[],
  'account_status enum exists'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'event_status'
  ),
  array[
    'DRAFT',
    'PUBLISHED',
    'UPCOMING',
    'IN_PROGRESS',
    'COMPLETED',
    'CLOSED',
    'CANCELLED'
  ]::text[],
  'event_status enum exists'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'recruitment_status'
  ),
  array['NOT_OPEN', 'OPEN', 'FULL', 'CLOSED']::text[],
  'recruitment_status enum exists'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'tier_strategy'
  ),
  array['STANDARD', 'URGENT', 'EMERGENCY', 'CUSTOM']::text[],
  'tier_strategy enum exists'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'leader_role'
  ),
  array['CAPTAIN', 'SUPERVISOR']::text[],
  'leader_role enum exists'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'assignment_status'
  ),
  array['CONFIRMED', 'CANCELLED', 'REMOVED', 'COMPLETED']::text[],
  'assignment_status enum exists'
);

select ok(
  exists (
    select 1
    from pg_type
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'booking_result'
  ),
  'booking_result enum exists'
);

select ok(
  exists (
    select 1
    from pg_type
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'waitlist_status'
  ),
  'waitlist_status enum exists'
);

select is(
  (
    select array_agg(enumlabel order by enumsortorder)::text[]
    from pg_enum
    join pg_type on pg_type.oid = pg_enum.enumtypid
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'attendance_status'
  ),
  array['NOT_MARKED', 'PRESENT', 'LATE', 'ABSENT']::text[],
  'attendance_status enum exists'
);

select ok(
  exists (
    select 1
    from pg_type
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'notification_type'
  ),
  'notification_type enum exists'
);

select is(
  private.category_rank('A'::public.worker_category),
  1,
  'category A has highest priority rank'
);

select is(
  private.category_rank('B'::public.worker_category),
  2,
  'category B has second priority rank'
);

select is(
  private.category_rank('C'::public.worker_category),
  3,
  'category C has third priority rank'
);

select is(
  private.category_rank('F'::public.worker_category),
  4,
  'category F has final priority rank'
);

select is(
  private.is_admin_role('SUPER_ADMIN'::public.app_role),
  true,
  'Super Admin is an admin role'
);

select is(
  private.is_admin_role('ADMIN'::public.app_role),
  true,
  'Admin is an admin role'
);

select is(
  private.is_admin_role('CAPTAIN'::public.app_role),
  false,
  'Captain is not an admin role'
);

select is(
  private.is_field_leader_role('CAPTAIN'::public.app_role),
  true,
  'Captain is a field leader role'
);

select is(
  private.is_field_leader_role('SUPERVISOR'::public.app_role),
  true,
  'Supervisor is a field leader role'
);

select is(
  private.is_field_leader_role('ADMIN'::public.app_role),
  false,
  'Admin is not a field leader role'
);

select has_sequence(
  'public',
  'worker_number_seq',
  'worker_number_seq exists'
);

select ok(
  not has_sequence_privilege('anon', 'public.worker_number_seq', 'USAGE'),
  'anon cannot use worker number sequence'
);

select ok(
  not has_sequence_privilege(
    'authenticated',
    'public.worker_number_seq',
    'USAGE'
  ),
  'authenticated cannot use worker number sequence'
);

select has_table('public', 'audit_logs', 'audit_logs table exists');

select col_is_pk('public', 'audit_logs', 'id', 'audit_logs id is primary key');

select col_not_null(
  'public',
  'audit_logs',
  'action',
  'audit action is required'
);

select col_not_null(
  'public',
  'audit_logs',
  'entity_type',
  'audit entity type is required'
);

select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    where pg_namespace.nspname = 'public'
      and pg_class.relname = 'audit_logs'
  ),
  'audit_logs has RLS enabled and forced'
);

select ok(
  not has_table_privilege('anon', 'public.audit_logs', 'SELECT'),
  'anon cannot read audit logs'
);

select ok(
  not has_table_privilege('authenticated', 'public.audit_logs', 'INSERT'),
  'authenticated cannot insert audit logs directly'
);

select ok(
  has_table_privilege('service_role', 'public.audit_logs', 'INSERT'),
  'service_role has explicit audit insert grant'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.audit_logs'::regclass
      and tgname = 'audit_logs_no_update'
      and not tgisinternal
  ),
  'audit_logs has append-only update trigger'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.audit_logs'::regclass
      and tgname = 'audit_logs_no_delete'
      and not tgisinternal
  ),
  'audit_logs has append-only delete trigger'
);

select * from finish();

rollback;
