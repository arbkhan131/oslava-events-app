begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

select has_table('public', 'tier_release_presets', 'tier release presets table exists');
select has_table('public', 'event_tier_custom_offsets', 'custom tier offsets table exists');
select has_table('public', 'event_tier_release_rules', 'event tier release rules table exists');
select has_table('public', 'notifications', 'notifications table exists');
select has_function(
  'public',
  'configure_event_tier_offsets',
  array['uuid', 'integer', 'integer', 'integer', 'integer', 'text'],
  'custom tier offset RPC exists'
);
select has_function('public', 'process_due_tier_releases', array[]::text[], 'tier scheduler RPC exists');
select has_function(
  'public',
  'is_worker_tier_eligible',
  array['uuid', 'uuid', 'timestamp with time zone'],
  'tier eligibility helper exists'
);
select has_function('public', 'notify_vacancy_reopened', array['uuid'], 'vacancy reopened notifier exists');

select is(
  (
    select array_agg(
      array[
        a_offset_minutes,
        b_offset_minutes,
        c_offset_minutes,
        f_offset_minutes
      ]
      order by case tier_strategy
        when 'EMERGENCY'::public.tier_strategy then 1
        when 'STANDARD'::public.tier_strategy then 2
        when 'URGENT'::public.tier_strategy then 3
        else 4
      end
    )
    from public.tier_release_presets
    where tier_strategy in ('EMERGENCY', 'STANDARD', 'URGENT')
  ),
  array[
    array[0, 5, 10, 15],
    array[0, 30, 60, 180],
    array[0, 15, 30, 60]
  ],
  'standard, urgent, and emergency presets have approved offsets'
);

select ok(
  not has_table_privilege('authenticated', 'public.event_tier_release_rules', 'INSERT'),
  'authenticated users cannot directly insert tier release rules'
);

select ok(
  not has_table_privilege('authenticated', 'public.notifications', 'INSERT'),
  'authenticated users cannot directly insert notifications'
);

insert into auth.users (
  id,
  aud,
  role,
  phone,
  encrypted_password,
  phone_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_sso_user,
  is_anonymous,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000006001', 'authenticated', 'authenticated', '+919876546001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000006002', 'authenticated', 'authenticated', '+919876546002', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000006003', 'authenticated', 'authenticated', '+919876546003', crypt('worker-b-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000006004', 'authenticated', 'authenticated', '+919876546004', crypt('worker-c-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000006005', 'authenticated', 'authenticated', '+919876546005', crypt('worker-f-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000006006', 'authenticated', 'authenticated', '+919876546006', crypt('inactive-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

select set_config('app.bypass_identity_protection', 'on', true);

insert into public.profiles (
  id,
  worker_number,
  role,
  full_name,
  initials,
  phone_e164,
  profile_photo_path,
  profile_completed_at,
  account_status
)
values
  ('00000000-0000-0000-0000-000000006001', null, 'ADMIN', 'Admin Six', 'AS', '+919876546001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000006002', nextval('public.worker_number_seq'), 'WORKER', 'Worker A', 'WA', '+919876546002', '00000000-0000-0000-0000-000000006002/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000006003', nextval('public.worker_number_seq'), 'WORKER', 'Worker B', 'WB', '+919876546003', '00000000-0000-0000-0000-000000006003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000006004', nextval('public.worker_number_seq'), 'WORKER', 'Worker C', 'WC', '+919876546004', '00000000-0000-0000-0000-000000006004/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000006005', nextval('public.worker_number_seq'), 'WORKER', 'Worker F', 'WF', '+919876546005', '00000000-0000-0000-0000-000000006005/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000006006', nextval('public.worker_number_seq'), 'WORKER', 'Inactive Worker', 'IW', '+919876546006', '00000000-0000-0000-0000-000000006006/profile.webp', now(), 'INACTIVE');

insert into public.worker_profiles (
  user_id,
  category,
  last_worker_category,
  date_of_birth,
  address,
  native_place,
  height_cm,
  education_status,
  has_previous_experience
)
values
  ('00000000-0000-0000-0000-000000006002', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000006003', 'B', 'B', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000006004', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000006005', 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000006006', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006001', true);

create temp table phase_6_standard_event as
select public.create_event_draft(
  'Phase 6 Standard',
  'Wedding',
  'Pune Hall',
  null,
  '2026-10-10 15:00:00+05:30',
  '2026-10-10 16:00:00+05:30',
  '2026-10-10 23:00:00+05:30',
  10,
  1200,
  'STANDARD',
  null,
  null,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.publish_event((select id from phase_6_standard_event), 'Publish standard tier event');

select is(
  (select count(*)::integer from public.event_tier_release_rules where event_id = (select id from phase_6_standard_event)),
  4,
  'publishing creates one release rule per category'
);

select is(
  (
    select array_agg(release_offset_minutes order by private.category_rank(category))
    from public.event_tier_release_rules
    where event_id = (select id from phase_6_standard_event)
  ),
  array[0, 30, 60, 180],
  'standard publish materializes approved offsets in category order'
);

select is(
  (
    select recruitment_status
    from public.events
    where id = (select id from phase_6_standard_event)
  ),
  'OPEN'::public.recruitment_status,
  'zero-minute first tier opens recruitment at publish time'
);

select is(
  public.process_due_tier_releases(),
  1,
  'scheduler processes the immediately due A tier'
);

select is(
  (
    select count(*)::integer
    from public.notifications
    where related_event_id = (select id from phase_6_standard_event)
      and notification_type = 'TIER_OPENED'
      and recipient_id in (
        '00000000-0000-0000-0000-000000006002',
        '00000000-0000-0000-0000-000000006003',
        '00000000-0000-0000-0000-000000006004',
        '00000000-0000-0000-0000-000000006005'
      )
  ),
  1,
  'due A tier creates one notification for the active A worker in this fixture'
);

select is(
  public.process_due_tier_releases(),
  0,
  'repeated scheduler run is idempotent when no new tiers are due'
);

update public.event_tier_release_rules
set opens_at = now() - interval '1 minute'
where event_id = (select id from phase_6_standard_event)
  and category in ('B', 'C', 'F');

select is(
  public.process_due_tier_releases(),
  3,
  'scheduler processes later due B, C, and F tiers'
);

select is(
  (
    select count(*)::integer
    from public.notifications
    where related_event_id = (select id from phase_6_standard_event)
      and notification_type = 'TIER_OPENED'
      and recipient_id in (
        '00000000-0000-0000-0000-000000006002',
        '00000000-0000-0000-0000-000000006003',
        '00000000-0000-0000-0000-000000006004',
        '00000000-0000-0000-0000-000000006005'
      )
  ),
  4,
  'all active categories in this fixture receive their own tier-opened notification'
);

select ok(
  public.is_worker_tier_eligible(
    (select id from phase_6_standard_event),
    '00000000-0000-0000-0000-000000006002',
    now()
  ),
  'A worker remains eligible after lower tiers open'
);

select ok(
  public.is_worker_tier_eligible(
    (select id from phase_6_standard_event),
    '00000000-0000-0000-0000-000000006005',
    now()
  ),
  'F worker becomes eligible after F tier opens'
);

select ok(
  not public.is_worker_tier_eligible(
    (select id from phase_6_standard_event),
    '00000000-0000-0000-0000-000000006006',
    now()
  ),
  'inactive workers are excluded from tier eligibility'
);

select is(
  public.notify_vacancy_reopened((select id from phase_6_standard_event)),
  (
    select count(*)::integer
    from public.profiles p
    join public.worker_profiles wp on wp.user_id = p.id
    where p.role = 'WORKER'::public.app_role
      and p.account_status = 'ACTIVE'::public.account_status
      and wp.category is not null
      and public.is_worker_tier_eligible(
        (select id from phase_6_standard_event),
        p.id,
        now()
      )
  ),
  'vacancy reopened notifier targets all currently eligible active workers'
);

select is(
  public.notify_vacancy_reopened((select id from phase_6_standard_event)),
  0,
  'vacancy reopened notifier suppresses duplicate notifications'
);

create temp table phase_6_full_event as
select public.create_event_draft(
  'Phase 6 Full',
  'Conference',
  'Mumbai Hall',
  null,
  '2026-10-11 15:00:00+05:30',
  '2026-10-11 16:00:00+05:30',
  '2026-10-11 23:00:00+05:30',
  1,
  1200,
  'URGENT',
  null,
  null,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.publish_event((select id from phase_6_full_event), 'Publish full tier event');

update public.events
set recruitment_status = 'FULL'
where id = (select id from phase_6_full_event);

update public.event_tier_release_rules
set opens_at = now() - interval '1 minute'
where event_id = (select id from phase_6_full_event);

select is(
  public.process_due_tier_releases(),
  4,
  'scheduler still marks due tiers processed when recruitment is full'
);

select is(
  (
    select count(*)::integer
    from public.notifications
    where related_event_id = (select id from phase_6_full_event)
      and notification_type = 'TIER_OPENED'
  ),
  0,
  'full recruitment suppresses next-tier vacancy notifications'
);

create temp table phase_6_custom_event as
select public.create_event_draft(
  'Phase 6 Custom',
  'Concert',
  'Nashik Stage',
  null,
  '2026-10-12 15:00:00+05:30',
  '2026-10-12 16:00:00+05:30',
  '2026-10-12 23:00:00+05:30',
  8,
  1500,
  'CUSTOM',
  null,
  null,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select public.configure_event_tier_offsets(
  (select id from phase_6_custom_event),
  10,
  20,
  30,
  40,
  'Custom release schedule'
);

select public.publish_event((select id from phase_6_custom_event), 'Publish custom tier event');

select is(
  (
    select recruitment_status
    from public.events
    where id = (select id from phase_6_custom_event)
  ),
  'NOT_OPEN'::public.recruitment_status,
  'delayed custom A tier leaves recruitment not open at publish time'
);

select is(
  (
    select array_agg(release_offset_minutes order by private.category_rank(category))
    from public.event_tier_release_rules
    where event_id = (select id from phase_6_custom_event)
  ),
  array[10, 20, 30, 40],
  'custom publish materializes configured offsets'
);

create temp table phase_6_bad_custom_event as
select public.create_event_draft(
  'Phase 6 Bad Custom',
  'Concert',
  'Nashik Stage',
  null,
  '2026-10-13 15:00:00+05:30',
  '2026-10-13 16:00:00+05:30',
  '2026-10-13 23:00:00+05:30',
  8,
  1500,
  'CUSTOM',
  null,
  null,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select throws_ok(
  $$
    select public.configure_event_tier_offsets(
      (select id from phase_6_bad_custom_event),
      20,
      10,
      30,
      40,
      'Invalid custom release schedule'
    )
  $$,
  'P0001',
  'tier release offsets must expand in A, B, C, F order',
  'custom offsets must preserve A to F expansion order'
);

create temp table phase_6_unconfigured_custom_event as
select public.create_event_draft(
  'Phase 6 Missing Custom',
  'Concert',
  'Nashik Stage',
  null,
  '2026-10-14 15:00:00+05:30',
  '2026-10-14 16:00:00+05:30',
  '2026-10-14 23:00:00+05:30',
  8,
  1500,
  'CUSTOM',
  null,
  null,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
) as id;

select throws_ok(
  $$
    select public.publish_event(
      (select id from phase_6_unconfigured_custom_event),
      'Publish without custom offsets'
    )
  $$,
  'P0001',
  'tier release configuration must define A, B, C, and F exactly once',
  'custom events cannot publish without a complete schedule'
);

select *
from finish();

rollback;
