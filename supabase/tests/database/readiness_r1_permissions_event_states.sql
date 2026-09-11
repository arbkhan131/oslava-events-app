-- R1 regressions: fixtures are owner-created; mutations run as authenticated users.
begin;
create extension if not exists pgtap with schema extensions;

-- Sequential regression fixtures use both phases of the R2 booking contract.
-- Real contender overlap is verified separately by test_readiness_r2.py.
create function pg_temp.apply_and_resolve(p_event_id uuid,p_idempotency_key text,
  p_acknowledged_requirement_ids uuid[] default '{}',p_late_cancellation_acknowledged boolean default false)
returns table(booking_request_id uuid,result public.booking_result,result_detail_code text,
  assignment_id uuid,event_id uuid,vacancy_count integer)
language plpgsql as $$
declare r record;
begin
  select * into r from public.apply_for_event(p_event_id,p_idempotency_key,p_acknowledged_requirement_ids,p_late_cancellation_acknowledged);
  if r.result='PENDING' then
    perform pg_sleep(1.05);
    return query select * from public.get_booking_result(r.booking_request_id);
  else
    return query select r.booking_request_id,r.result,r.result_detail_code,r.assignment_id,r.event_id,r.vacancy_count;
  end if;
end $$;

select no_plan();
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


-- Isolate last-Super-Admin tests from any developer seed accounts (transaction rolls back).
select set_config('app.bypass_identity_protection', 'on', true);
update public.profiles set account_status = 'INACTIVE' where role = 'SUPER_ADMIN';
update public.worker_profiles set category = null where user_id in ('00000000-0000-0000-0000-000000091005','00000000-0000-0000-0000-000000091006');
update public.profiles set role = 'SUPER_ADMIN' where id = '00000000-0000-0000-0000-000000091005';
update public.profiles set role = 'ADMIN' where id = '00000000-0000-0000-0000-000000091006';
select set_config('app.bypass_identity_protection', 'off', true);
set local role authenticated;
select throws_ok($$select public.request_account_erasure('00000000-0000-0000-0000-000000091005','Test')$$,
  'P0001','Admin cannot manage Admin or Super Admin accounts','Admin cannot erase Super Admin');
select throws_ok($$select public.request_account_erasure('00000000-0000-0000-0000-000000091006','Test')$$,
  'P0001','Admin cannot manage Admin or Super Admin accounts','Admin cannot erase another Admin');
select throws_ok($$select public.request_account_erasure('00000000-0000-0000-0000-000000091001','Test')$$,
  'P0001','Admin cannot manage Admin or Super Admin accounts','Admin cannot bypass hierarchy through self erasure');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091005',true);
select throws_ok($$select public.request_account_erasure('00000000-0000-0000-0000-000000091005','Test')$$,
  'P0001','the last active Super Admin cannot be removed','last active Super Admin cannot erase itself');
select throws_ok($$select public.change_user_role('00000000-0000-0000-0000-000000091005','ADMIN','Test')$$,
  'P0001','the last active Super Admin cannot be removed','last active Super Admin cannot demote itself');
select throws_ok($$select public.request_account_erasure('00000000-0000-0000-0000-000000091002',' ')$$,
  'P0001','reason is required','erasure still requires a reason');
select lives_ok($$select public.request_account_erasure('00000000-0000-0000-0000-000000091006','Authorized erasure')$$,
  'Super Admin can erase an Admin when another active Super Admin remains');
reset role;
select is((select count(*)::int from public.account_erasure_requests where target_user_id='00000000-0000-0000-0000-000000091005'),0,'denied requests do not create erasure records');
select is((select account_status::text from public.profiles where id='00000000-0000-0000-0000-000000091005'),'ACTIVE','denied request preserves active Super Admin');
select is((select count(*)::int from public.audit_logs where entity_id='00000000-0000-0000-0000-000000091006' and action='account_erasure_requested' and reason='Authorized erasure'),1,'authorized erasure audited once');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091006',true);
select throws_ok($$select public.change_user_role('00000000-0000-0000-0000-000000091002','CAPTAIN','Test')$$,'P0001','an active Admin or Super Admin is required','inactive Admin cannot change roles');
select throws_ok($$select public.change_user_phone('00000000-0000-0000-0000-000000091002','+919999991234','Test')$$,'P0001','an active Admin or Super Admin is required','inactive Admin cannot change phones');
select throws_ok($$select public.change_account_status('00000000-0000-0000-0000-000000091002','DETAINED','Test')$$,'P0001','an active Admin or Super Admin is required','inactive Admin cannot detain');
select throws_ok($$select public.provision_staff_profile('00000000-0000-0000-0000-000000091002','CAPTAIN','Test','T','+919999991234','Test')$$,'P0001','an active Admin or Super Admin is required','inactive Admin cannot provision staff');
select throws_ok($$select public.request_account_erasure('00000000-0000-0000-0000-000000091002','Test')$$,'P0001','an active Admin or Super Admin is required','inactive Admin cannot erase');
reset role;

create temp table r1_events(key text primary key,id uuid);
grant all on r1_events to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091001',true);
insert into r1_events values
 ('cancel',public.create_event_draft('R1 cancel','Wedding','Hall',null,now()+interval '4 days',now()+interval '4 days 1 hour',now()+interval '4 days 4 hours',1,1200,'STANDARD',null,null,'[]','[]','[]')),
 ('complete',public.create_event_draft('R1 complete','Wedding','Hall',null,now()+interval '5 days',now()+interval '5 days 1 hour',now()+interval '5 days 4 hours',2,1200,'STANDARD',null,null,'[]','[]','[]'));
select public.publish_event(id,'R1 publish') from r1_events;
reset role;
update public.event_tier_release_rules set opens_at=now()-interval '1 minute' where event_id in (select id from r1_events);
select public.process_due_tier_releases();
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091002',true);
select is((select result::text from pg_temp.apply_and_resolve((select id from r1_events where key='cancel'),'r1-cancel-fill','{}',false)),'CONFIRMED','public Apply confirms cancellation fixture');
select is((select result::text from pg_temp.apply_and_resolve((select id from r1_events where key='complete'),'r1-complete-fill','{}',false)),'CONFIRMED','public Apply confirms completion fixture');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091003',true);
select * from public.join_waitlist((select id from r1_events where key='cancel'),'r1-wait','{}');
select * from pg_temp.apply_and_resolve((select id from r1_events where key='complete'),'r1-unmarked','{}',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091004',true);
select * from public.join_waitlist((select id from r1_events where key='complete'),'r1-complete-wait','{}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091001',true);
select lives_ok($$select public.cancel_event((select id from r1_events where key='cancel'),'Venue cancelled')$$,'Admin can cancel booked event');
reset role;
select is((select status::text from public.assignments where event_id=(select id from r1_events where key='cancel')),'CANCELLED','cancel updates confirmed assignment');
select is((select status::text from public.waitlist_entries where event_id=(select id from r1_events where key='cancel')),'EXPIRED','cancel closes waiting list');
select is((select cancellation_type from public.cancellations where event_id=(select id from r1_events where key='cancel')),'EVENT','event cancellation does not impersonate worker cancellation');
select is((select count(*)::int from public.cancellations where event_id=(select id from r1_events where key='cancel') and promoted_assignment_id is not null),0,'cancellation never refills');
select is((select count(*)::int from public.reporting_reminder_schedules where event_id=(select id from r1_events where key='cancel') and skipped_at is null and processed_at is null),0,'cancel skips outstanding reminders');
select is((select count(*)::int from public.notifications where related_event_id=(select id from r1_events where key='cancel') and deduplication_key like 'event-cancelled:%'),2,'confirmed and waitlisted workers receive cancellation notification');
select is((select reliability_sample_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091002'),0,'event cancellation adds no reliability penalty or sample');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091002',true);
select is((select action_state from public.worker_event_board() where id=(select id from r1_events where key='cancel')),'CANCELLED','worker board reflects cancelled event');
select is((select assignment_status::text from public.worker_my_work() where event_id=(select id from r1_events where key='cancel')),'CANCELLED','My Work reflects cancelled event');
select is((select can_cancel from public.worker_my_work() where event_id=(select id from r1_events where key='cancel')),false,'cancelled work has no cancel action');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091001',true);
select throws_ok($$select public.cancel_event((select id from r1_events where key='cancel'),'Repeat')$$,'P0001','terminal events cannot be cancelled again','repeat cancellation is rejected safely');
reset role;
update public.events set event_status='IN_PROGRESS' where id=(select id from r1_events where key='complete');
set local role authenticated;
select * from public.set_attendance((select id from public.assignments where event_id=(select id from r1_events where key='complete') and worker_id='00000000-0000-0000-0000-000000091002'),'PRESENT','Observed');
select lives_ok($$select public.complete_event((select id from r1_events where key='complete'),'Work ended')$$,'Admin completes event');
reset role;
select is((select count(*)::int from public.assignments where event_id=(select id from r1_events where key='complete') and status='COMPLETED' and completed_at is not null),2,'completed event moves both assignments to history');
select is((select status::text from public.waitlist_entries where event_id=(select id from r1_events where key='complete')),'EXPIRED','completion expires waiting entry');
select is((select reliability_completed_event_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091002'),1,'completed-work context is recalculated');
select is((select reliability_sample_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091002'),1,'observed attendance remains a resolved sample');
select is((select reliability_sample_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091003'),0,'missing attendance creates no resolved sample');
select is((select count(*)::int from public.attendance where event_id=(select id from r1_events where key='complete')),1,'completion does not invent attendance');
select is((select count(*)::int from public.performance_reviews where event_id=(select id from r1_events where key='complete')),0,'completion does not invent reviews');
set local role authenticated;
select lives_ok($$select * from public.record_performance_review(
  (select id from public.assignments where event_id=(select id from r1_events where key='complete') and worker_id='00000000-0000-0000-0000-000000091002'),
  4,'{}','Observed after completion')$$,'outstanding review can be entered after completion');
select * from public.set_attendance((select id from public.assignments where event_id=(select id from r1_events where key='complete') and worker_id='00000000-0000-0000-0000-000000091003'),'NOT_MARKED','Still unresolved');
select lives_ok($$select public.close_event((select id from r1_events where key='complete'),'Finalized')$$,'Admin closes completed event with unresolved marks');
select throws_ok($$select * from public.record_performance_review(
  (select id from public.assignments where event_id=(select id from r1_events where key='complete') and worker_id='00000000-0000-0000-0000-000000091002'),
  5,'{}','Late edit')$$,'P0001','performance reviews are closed for this event','closure freezes performance reviews');
select lives_ok($$select * from public.set_attendance(
  (select id from public.assignments where event_id=(select id from r1_events where key='complete') and worker_id='00000000-0000-0000-0000-000000091002'),
  'LATE','Admin correction after closure')$$,'Admin can still make an audited attendance correction after closure');
select throws_ok($$select public.complete_event((select id from r1_events where key='complete'),'Repeat')$$,'P0001','only in-progress events can be completed','repeat completion does not add completed work');
select throws_ok($$select public.close_event((select id from r1_events where key='complete'),'Repeat')$$,'P0001','only completed events can be closed','repeat closure is safely rejected');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000091003',true);
select is((select assignment_status::text from public.worker_my_work() where event_id=(select id from r1_events where key='complete')),'COMPLETED','closed work remains completed in worker history');
reset role;
select is((select reliability_completed_event_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091003'),1,'close does not double-count completed work');
select is((select reliability_sample_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091003'),0,'explicit NOT_MARKED is still excluded after closure');
select is((select category::text from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091002'),'A','terminal transitions never change worker category');
select is((select count(*)::int from public.performance_reviews where event_id=(select id from r1_events where key='complete')),1,'closure retains the actual review');
select is((select count(*)::int from public.reporting_reminder_schedules where event_id in (select id from r1_events) and processed_at is null and skipped_at is null),0,'no pending reminders on terminal events');
select is((select count(*)::int from public.audit_logs where entity_type='assignment' and action='assignment_event_reconciled' and entity_id in (select id from public.assignments where event_id in (select id from r1_events))),3,'every reconciled assignment has an audit record');
select * from finish();
rollback;
