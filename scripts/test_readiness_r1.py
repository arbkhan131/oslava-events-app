"""Disposable local R1 migration replay, legacy repair, and two-session permission test.

Requires the existing local Supabase Docker stack. Uses no hosted connection or
credentials, copies only managed schema definitions, and never resets postgres.
Run from the repository root: python scripts/test_readiness_r1.py
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = 'supabase_db_oslava_events'
DATABASE = 'oslava_r1_test_' + uuid.uuid4().hex[:12]
R1 = ROOT / 'supabase/migrations/20260909010100_readiness_r1_permissions_event_states.sql'


def command(args, text=None):
    return subprocess.run(['docker', 'exec', '-i', CONTAINER, *args],
                          input=text, text=True, capture_output=True, timeout=120)


def sql(statement, *, database=DATABASE, role='postgres', check=True):
    result = command(['psql', '-X', '-At', '-U', role, '-d', database,
                      '-v', 'ON_ERROR_STOP=1'], statement)
    if check and result.returncode:
        raise RuntimeError(result.stderr)
    return result


def require(statement, expected, label):
    actual = sql(statement).stdout.strip()
    if actual != expected:
        raise AssertionError(f'{label}: expected {expected!r}, got {actual!r}')
    print('PASS:', label, flush=True)


def fixtures():
    test = (ROOT / 'supabase/tests/database/readiness_r1_permissions_event_states.sql').read_text()
    return test[test.index('insert into auth.users'):test.index('-- Isolate last-Super-Admin')]


def test_legacy_repair():
    setup = fixtures() + """
create temp table legacy_events(key text,id uuid);
insert into legacy_events
select kind, public.create_event_draft('Legacy '||kind,'Wedding','Hall',null,
  now()+interval '4 days',now()+interval '4 days 1 hour',now()+interval '4 days 4 hours',
  1,1200,'STANDARD',null,null,'[]','[]','[]')
from unnest(array['cancel','complete','close']) kind;
select public.publish_event(id,'Legacy publish') from legacy_events;
insert into public.assignments(event_id,worker_id,status,source,category_at_confirmation)
select id,'00000000-0000-0000-0000-000000091002','CONFIRMED','MANAGEMENT','A' from legacy_events;
insert into public.waitlist_entries(event_id,worker_id,category_at_join)
select id,'00000000-0000-0000-0000-000000091003','B' from legacy_events;
select public.cancel_event(id,'Legacy venue cancellation') from legacy_events where key='cancel';
update public.events set event_status='IN_PROGRESS' where id in (select id from legacy_events where key<>'cancel');
select public.complete_event(id,'Legacy work ended') from legacy_events where key<>'cancel';
select public.close_event(id,'Legacy finalized') from legacy_events where key='close';
"""
    assertions = """
do $$ begin
  if (select count(*) from public.assignments where status='COMPLETED') <> 2
     or (select count(*) from public.assignments where status='CANCELLED') <> 1
     or (select count(*) from public.waitlist_entries where status='EXPIRED') <> 3
     or (select count(*) from public.cancellations where cancellation_type='EVENT') <> 1
     or exists (select 1 from public.reporting_reminder_schedules where skipped_at is null and processed_at is null)
     or exists (select 1 from public.notifications where deduplication_key like 'event-cancelled:%')
     or (select reliability_completed_event_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091002') <> 2
     or (select reliability_sample_count from public.worker_profiles where user_id='00000000-0000-0000-0000-000000091002') <> 0
     or (select count(*) from public.audit_logs where action='assignment_event_reconciled') <> 3
  then raise exception 'legacy repair assertion failed'; end if;
end $$;
"""
    # Roll back the synthetic records and the trial migration together.
    # Replaying twice also checks that repair cannot duplicate ledger/audit effects.
    sql('begin;\n' + setup + R1.read_text() + assertions + R1.read_text() + assertions + '\nrollback;')
    print('PASS: legacy cancelled/completed/closed rows repaired; repeat repair is harmless', flush=True)


def test_two_sessions():
    sql('begin;\n' + fixtures() + """
select set_config('app.bypass_identity_protection','on',false);
update public.worker_profiles set category=null where user_id in
 ('00000000-0000-0000-0000-000000091005','00000000-0000-0000-0000-000000091006');
update public.profiles set role='SUPER_ADMIN' where id in
 ('00000000-0000-0000-0000-000000091005','00000000-0000-0000-0000-000000091006');
select set_config('app.bypass_identity_protection','off',false);
commit;
""")

    def demote(suffix, pause=False):
        user = '00000000-0000-0000-0000-00000009100' + suffix
        return sql(f"""begin;
set local application_name='r1-demote-{suffix}';
set local role authenticated;
select set_config('request.jwt.claim.sub','{user}',true);
select public.change_user_role('{user}','ADMIN','R1 concurrent demotion');
{'select pg_sleep(2);' if pause else ''}
commit;""", check=False)

    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(demote, '5', True)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            sleeping = sql("select exists (select 1 from pg_stat_activity where datname=current_database() and application_name='r1-demote-5' and wait_event='PgSleep');").stdout.strip()
            if sleeping == 't':
                break
            if first.done():
                raise AssertionError('First demotion did not reach controlled overlap: ' + first.result().stderr)
            time.sleep(.03)
        else:
            raise AssertionError('No overlap observed')
        second = executor.submit(demote, '6')
        a, b = first.result(), second.result()
    if a.returncode or not b.returncode or 'the last active Super Admin cannot be removed' not in b.stderr:
        raise AssertionError('Concurrent demotion result mismatch: ' + a.stderr + b.stderr)
    require("select count(*) from public.profiles where role='SUPER_ADMIN' and account_status='ACTIVE';", '1',
            'overlapping authenticated demotions preserve the last active Super Admin')


def main():
    created = False
    try:
        sql('create database ' + DATABASE, database='postgres', role='supabase_admin')
        created = True
        dump = command(['pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--schema-only',
                        '--no-owner', '--no-acl', '--schema=auth', '--schema=storage', '--schema=extensions'])
        if dump.returncode:
            raise RuntimeError(dump.stderr)
        # App storage policies are rebuilt from migrations; no application schema/data is copied.
        managed = re.sub(r'CREATE POLICY .*?;\n', '', dump.stdout, flags=re.S)
        sql(managed, role='supabase_admin')
        sql(f"""grant all on database {DATABASE} to postgres;
grant all on schema public, auth, storage, extensions to postgres;
grant usage on schema auth, extensions to anon, authenticated, service_role;
grant all on all tables in schema auth, storage to postgres;
grant all on all sequences in schema auth, storage to postgres;
alter database {DATABASE} set search_path=public,extensions;
create publication supabase_realtime;
alter publication supabase_realtime owner to postgres;
""", role='supabase_admin')
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            if path == R1:
                test_legacy_repair()
            sql('begin;\n' + path.read_text() + '\ncommit;')
        print('PASS: all versioned application migrations replayed under postgres ownership', flush=True)
        files = assertions = 0
        for path in sorted((ROOT / 'supabase/tests/database').glob('*.sql')):
            if path.name == 'local_dev_bootstrap.sql':
                continue  # No real/local account data is copied or seeded into this scratch database.
            output = sql(path.read_text()).stdout
            tests = re.findall(r'^ok \d+\b', output, re.M)
            plans = re.findall(r'^1\.\.(\d+)$', output, re.M)
            if re.search(r'^not ok ', output, re.M) or not plans or int(plans[-1]) != len(tests):
                raise AssertionError(path.name + '\n' + output)
            files += 1
            assertions += len(tests)
        print(f'PASS: disposable database suite: {files} files, {assertions} assertions (bootstrap excluded)', flush=True)
        test_two_sessions()
    finally:
        if created:
            assert re.fullmatch(r'oslava_r1_test_[0-9a-f]{12}', DATABASE)
            sql('drop database ' + DATABASE + ' with (force)', database='postgres', role='supabase_admin')
            print('Removed this run\'s disposable database.', flush=True)


if __name__ == '__main__':
    main()
