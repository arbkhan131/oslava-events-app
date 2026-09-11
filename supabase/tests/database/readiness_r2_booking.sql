begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select ok(not has_function_privilege('authenticated','public.process_due_booking_windows(integer)','EXECUTE'),'global recovery is service-only');
select ok(not has_function_privilege('anon','public.get_booking_result(uuid)','EXECUTE'),'anonymous callers cannot read booking outcomes');
select ok(not has_function_privilege('authenticated','private.confirm_booking_request(public.booking_requests,boolean,uuid[])','EXECUTE'),'clients cannot invoke unchecked confirmation helper');
select ok(not has_table_privilege('authenticated','public.booking_requests','INSERT'),'clients cannot forge durable contenders');
select ok(not has_table_privilege('authenticated','public.booking_arbitration_windows','UPDATE'),'clients cannot shorten priority window');
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
  ('00000000-0000-0000-0000-000000091001', 'authenticated', 'authenticated', '+919876591001', crypt('admin-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000091002', 'authenticated', 'authenticated', '+919876591002', crypt('worker-a-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000091003', 'authenticated', 'authenticated', '+919876591003', crypt('worker-b-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000091004', 'authenticated', 'authenticated', '+919876591004', crypt('worker-c1-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000091005', 'authenticated', 'authenticated', '+919876591005', crypt('worker-c2-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now()),
  ('00000000-0000-0000-0000-000000091006', 'authenticated', 'authenticated', '+919876591006', crypt('worker-f-password', gen_salt('bf')), now(), '{"provider":"phone","providers":["phone"]}', '{}', false, false, now(), now());

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
  ('00000000-0000-0000-0000-000000091001', null, 'ADMIN', 'Admin Ten', 'AT', '+919876591001', null, null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000091002', nextval('public.worker_number_seq'), 'WORKER', 'Worker A Ten', 'WA', '+919876591002', '00000000-0000-0000-0000-000000091002/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000091003', nextval('public.worker_number_seq'), 'WORKER', 'Worker B Ten', 'WB', '+919876591003', '00000000-0000-0000-0000-000000091003/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000091004', nextval('public.worker_number_seq'), 'WORKER', 'Worker C1 Ten', 'WC', '+919876591004', '00000000-0000-0000-0000-000000091004/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000091005', nextval('public.worker_number_seq'), 'WORKER', 'Worker C2 Ten', 'WC', '+919876591005', '00000000-0000-0000-0000-000000091005/profile.webp', now(), 'ACTIVE'),
  ('00000000-0000-0000-0000-000000091006', nextval('public.worker_number_seq'), 'WORKER', 'Worker F Ten', 'WF', '+919876591006', '00000000-0000-0000-0000-000000091006/profile.webp', now(), 'ACTIVE');

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
  ('00000000-0000-0000-0000-000000091002', 'A', 'A', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000091003', 'B', 'B', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000091004', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000091005', 'C', 'C', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false),
  ('00000000-0000-0000-0000-000000091006', 'F', 'F', (current_date - interval '20 years')::date, 'Pune', 'Pune', 170, 'College', false);

select set_config('app.bypass_identity_protection', 'off', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000091001', true);



create temp table r2_event(id uuid);
create temp table r2_request as select * from public.booking_requests where false;
grant all on r2_event,r2_request to authenticated;
set local role authenticated;
insert into r2_event select public.create_event_draft('R2 SQL','Wedding','Hall',null,now()+interval '300 days',now()+interval '300 days 1 hour',now()+interval '300 days 4 hours',1,1200,'STANDARD',null,null,'[]','[]','[]');
select public.publish_event(id,'R2 SQL publish') from r2_event;
reset role;
update public.event_tier_release_rules set opens_at=now()-interval '1 minute' where event_id=(select id from r2_event);
select public.process_due_tier_releases();
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091006',true);
select is((select result::text from public.apply_for_event((select id from r2_event),'r2-sql-intake','{}',false)),'PENDING','final-seat intake returns pending');
select is((select result::text from public.resolve_booking_request('r2-sql-intake')),'PENDING','early resolution does not allocate before window closure');
select throws_ok($$select * from public.apply_for_event((select id from r2_event),'r2-sql-intake','{}',true)$$,'P0001','idempotency key belongs to a different booking payload','retry cannot replace persisted payload');
reset role;
select is((select count(*)::int from public.assignments where event_id=(select id from r2_event)),0,'pending intake creates no assignment');
select is((select extract(epoch from closes_at-opens_at)::numeric from public.booking_arbitration_windows where event_id=(select id from r2_event)),1::numeric,'window is exactly one second');
select ok((select input_snapshot_complete from public.booking_requests where idempotency_key='r2-sql-intake'),'new requests carry complete input snapshot');
select pg_sleep(1.05);
set local role authenticated;
select is((select result::text from public.resolve_booking_request('r2-sql-intake')),'CONFIRMED','post-window resolution confirms eligible sole contender');
select is((select result::text from public.apply_for_event((select id from r2_event),'r2-sql-intake','{}',false)),'CONFIRMED','same key returns final outcome');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091002',true);
select throws_ok($$select * from public.resolve_booking_request('r2-sql-intake')$$,'P0001','booking request not found','another worker cannot discover a request by key');
reset role;
select is((select count(*)::int from public.assignments where event_id=(select id from r2_event)),1,'resolution and retries leave one assignment');
select is((select count(*)::int from public.audit_logs where entity_id=(select id from public.booking_requests where idempotency_key='r2-sql-intake') and action='booking_resolved'),1,'final outcome audited once');
-- Legacy final results remain retrievable even though pre-R2 payloads were not stored.
update public.booking_requests set input_snapshot_complete=false where idempotency_key='r2-sql-intake';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091006',true);
select is((select result::text from public.apply_for_event((select id from r2_event),'r2-sql-intake','{}',true)),'CONFIRMED','legacy final result is retained without inventing its original payload');
select * from finish();
rollback;
