"""R2 isolated migration replay and real multi-connection booking regressions.

Run from the repository root with Python. Requires the local Supabase Docker
stack with R2 applied (for pg_cron). No hosted access, personal data or DB reset.
"""
from concurrent.futures import ThreadPoolExecutor
import json
import re
import time
import uuid
import queue
import subprocess
import tempfile
import test_readiness_r1 as db

db.DATABASE = 'oslava_r2_test_' + uuid.uuid4().hex[:12]
connections = None


class Connection:
    """Warm psql sessions keep Docker startup time outside the one-second test."""
    def __init__(self):
        self.errors = tempfile.TemporaryFile(mode='w+t')
        self.process = subprocess.Popen(['docker','exec','-i',db.CONTAINER,
            'psql','-X','-qAt','-U','postgres','-d',db.DATABASE,'-v','ON_ERROR_STOP=1'],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.errors,text=True,bufsize=1)
        self.execute("set statement_timeout='15s'; select 1;")

    def execute(self, statement):
        marker='done_'+uuid.uuid4().hex
        self.process.stdin.write('reset role;\n'+statement+'\n\\echo '+marker+'\n')
        self.process.stdin.flush()
        lines=[]
        while True:
            line=self.process.stdout.readline()
            if not line:
                self.errors.seek(0)
                raise RuntimeError(self.errors.read())
            if line.strip()==marker: break
            lines.append(line)
        return subprocess.CompletedProcess([],0,''.join(lines),'')

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        self.errors.close()


def SQL(statement, **kwargs):
    kwargs.setdefault('database', db.DATABASE)
    if connections is not None and kwargs['database']==db.DATABASE and kwargs.get('role','postgres')=='postgres' and kwargs.get('check',True):
        connection=connections.get()
        try: return connection.execute(statement)
        finally: connections.put(connection)
    return db.sql(statement, **kwargs)
ROOT = db.ROOT
ADMIN = '00000000-0000-0000-0000-000000091001'
def worker(n): return '00000000-0000-0000-0000-00000009100' + str(n)
checks = 0
day = 8


def check(condition, label):
    global checks
    if not condition: raise AssertionError(label)
    checks += 1
    print('PASS:', label, flush=True)


def call(user, expression, *, rollback=False, check_error=True):
    output = SQL(f"begin; set local role authenticated; select set_config('request.jwt.claim.sub','{user}',true); select row_to_json(r) from {expression} r; {'rollback' if rollback else 'commit'};", check=check_error)
    if not check_error: return output
    return json.loads(next(line for line in output.stdout.splitlines() if line.startswith('{')))


def create_event(capacity=1, *, offset=None, requirements='[]'):
    global day
    day += 1
    offset = offset or f'{day} days'
    output = SQL(f"begin; select set_config('request.jwt.claim.sub','{ADMIN}',true); select public.create_event_draft('R2 {day}','Wedding','Hall',null,now()+interval '{offset}',now()+interval '{offset}'+interval '1 hour',now()+interval '{offset}'+interval '4 hours',{capacity},1200,'STANDARD',null,null,'[]','{requirements}','[]'); commit;").stdout
    event = re.findall(r'^[0-9a-f-]{36}$', output, re.M)[-1]
    SQL(f"begin; select set_config('request.jwt.claim.sub','{ADMIN}',true); select public.publish_event('{event}','R2 fixture'); update public.event_tier_release_rules set opens_at=now()-interval '1 minute' where event_id='{event}'; select public.process_due_tier_releases(); commit;")
    return event


def apply(n,event,key,acks=(),late=False):
    return call(worker(n), f"public.apply_for_event('{event}','{key}','{{{','.join(acks)}}}',{str(late).lower()})")


def resolve(n,request):
    return call(worker(n),f"public.get_booking_result('{request['booking_request_id']}')")


def settle(n, request):
    deadline=time.monotonic()+6
    while request['result']=='PENDING' and time.monotonic()<deadline:
        time.sleep(.15)
        request=resolve(n,request)
    check(request['result']!='PENDING','request reaches a terminal outcome')
    return request


def parallel(*operations):
    with ThreadPoolExecutor(max_workers=len(operations)) as pool:
        futures=[pool.submit(operation) for operation in operations]
        return [future.result() for future in futures]


def scenarios():
    event=create_event()
    f=apply(6,event,'priority-f'); a=apply(2,event,'priority-a')
    check(f['result']==a['result']=='PENDING','F and A both commit intake without waiting for allocation')
    gap=float(SQL(f"select extract(epoch from max(server_received_at)-min(server_received_at)) from public.booking_requests where event_id='{event}';").stdout.strip())
    check(0<gap<1,f'real server receipt gap {gap:.3f}s is inside one-second window')
    check(settle(6,f)['result']=='WAITLIST_AVAILABLE' and resolve(2,a)['result']=='CONFIRMED','later A beats earlier F inside the window')
    check(SQL(f"select count(*) from public.assignments where event_id='{event}' and status='CONFIRMED';").stdout.strip()=='1','exactly one final seat')
    check(apply(2,event,'priority-a')['assignment_id']==resolve(2,a)['assignment_id'],'retry returns original assignment')
    denied=call(worker(3),f"public.get_booking_result('{a['booking_request_id']}')",check_error=False)
    check(denied.returncode!=0 and 'booking request not found' in denied.stderr,'another worker cannot read or resolve private result')

    event=create_event(); c1=apply(4,event,'same-c1'); c2=apply(5,event,'same-c2')
    check(settle(4,c1)['result']=='CONFIRMED' and resolve(5,c2)['result']=='WAITLIST_AVAILABLE','same category honors earliest server receipt')
    event=create_event(); f=apply(6,event,'outside-f'); time.sleep(1.05); a=apply(2,event,'outside-a')
    check(a['result']=='WAITLIST_AVAILABLE' and resolve(6,f)['result']=='CONFIRMED','later outside-window A cannot displace F')
    event=create_event(); first,second=parallel(lambda:apply(2,event,'duplicate-key'),lambda:apply(2,event,'duplicate-key'))
    check(first['booking_request_id']==second['booking_request_id'],'simultaneous same-key submissions share one request')
    other=apply(2,event,'different-key')
    check(other['booking_request_id']==first['booking_request_id'],'another key cannot create a second pending contender')
    settle(2,first)
    mismatch=call(worker(2),f"public.apply_for_event('{event}','duplicate-key','{{}}',true)",check_error=False)
    check(mismatch.returncode!=0 and 'different booking payload' in mismatch.stderr,'reusing a key with changed payload is rejected')

    event=create_event(); other=create_event(offset=f'{day} days')
    x,y=parallel(lambda:apply(3,event,'conflicting-x'),lambda:apply(3,other,'conflicting-y'))
    time.sleep(1.05)
    x,y=parallel(lambda:resolve(3,x),lambda:resolve(3,y))
    check(sorted([x['result'],y['result']])==['CONFIRMED','CONFLICT'],'simultaneous overlapping events cannot both confirm a worker')

    event=create_event(requirements='[{"name":"Mandatory","is_mandatory":true,"acknowledgement_required":true},{"name":"Optional","is_mandatory":false,"acknowledgement_required":true}]')
    ids=SQL(f"select id from public.event_requirements where event_id='{event}' order by name;").stdout.splitlines()
    f=apply(6,event,'ack-f',ids,True); a=apply(2,event,'ack-a',ids[:1],False)
    check(settle(2,a)['result']=='CONFIRMED','winner resolves with its own valid acknowledgements')
    check(SQL(f"select count(*) from public.requirement_acknowledgements where booking_request_id='{a['booking_request_id']}';").stdout.strip()=='1','loser optional acknowledgement never leaks into winner')
    check(SQL(f"select late_cancellation_acknowledged from public.assignments where booking_request_id='{a['booking_request_id']}';").stdout.strip()=='f','loser late acknowledgement never leaks into winner')
    event=create_event(offset='30 minutes'); a=apply(2,event,'late-no'); f=apply(6,event,'late-yes',late=True)
    check(a['result_detail_code']=='LATE_CANCELLATION_ACK_REQUIRED' and settle(6,f)['result']=='CONFIRMED','late acknowledgement is enforced per contender')

    event=create_event(); f=apply(6,event,'revalidate-f'); a=apply(2,event,'revalidate-a')
    SQL(f"begin; select set_config('request.jwt.claim.sub','{ADMIN}',true); select public.change_account_status('{worker(2)}','DETAINED','R2 eligibility changed'); commit;")
    check(settle(6,f)['result']=='CONFIRMED' and resolve(2,a)['result']=='RESTRICTED','detained high-priority contender is revalidated and skipped')
    SQL(f"begin; select set_config('request.jwt.claim.sub','{ADMIN}',true); select public.change_account_status('{worker(2)}','ACTIVE','R2 restore'); commit;")
    event=create_event(); f=apply(6,event,'cancel-pending')
    SQL(f"begin; select set_config('request.jwt.claim.sub','{ADMIN}',true); select public.cancel_event('{event}','R2 cancelled during window'); commit;")
    check(settle(6,f)['result']=='EVENT_UNAVAILABLE','event cancellation during priority interval cannot confirm stale work')

    event=create_event(); filled=settle(2,apply(2,event,'refill-original'))
    call(worker(3),f"public.join_waitlist('{event}','refill-wait','{{}}')")
    cancelled,contender=parallel(
      lambda:call(worker(2),f"public.cancel_assignment('{filled['assignment_id']}','R2 worker cancelled','refill-cancel')"),
      lambda:apply(6,event,'refill-new'))
    if contender['result']=='PENDING': contender=settle(6,contender)
    check(SQL(f"select worker_id from public.assignments where event_id='{event}' and status='CONFIRMED';").stdout.strip()==worker(3),'cancel/apply race preserves the promoted waitlist seat without oversubscription')
    repeat=call(worker(2),f"public.cancel_assignment('{filled['assignment_id']}','R2 worker cancelled','refill-cancel')")
    check(repeat['cancellation_id']==cancelled['cancellation_id'],'cancellation retry does not refill twice')

    event=create_event(); other=create_event(capacity=2,offset=f'{day} days')
    filled=settle(2,apply(2,event,'promotion-conflict-original'))
    call(worker(3),f"public.join_waitlist('{event}','promotion-conflict-wait','{{}}')")
    _, competing=parallel(
      lambda:call(worker(2),f"public.cancel_assignment('{filled['assignment_id']}','R2 promotion race','promotion-conflict-cancel')"),
      lambda:apply(3,other,'promotion-conflict-other'))
    check(competing['result'] in ('CONFIRMED','CONFLICT'),'Apply versus promotion produces an authoritative result')
    check(SQL(f"select count(*) from public.assignments where worker_id='{worker(3)}' and event_id in ('{event}','{other}') and status='CONFIRMED';").stdout.strip()=='1','Apply and waitlist promotion cannot create conflicting dual confirmation')

    event=create_event(requirements='[{"name":"Mandatory","is_mandatory":true,"acknowledgement_required":true}]')
    requirement=SQL(f"select id from public.event_requirements where event_id='{event}';").stdout.strip()
    a=apply(2,event,'changed-requirement',[requirement])
    SQL(f"update public.events set version=version+1 where id='{event}';")
    check(settle(2,a)['result']=='INVALID_REQUIREMENTS','allocation rejects acknowledgement of an outdated event version')

    event=create_event(); f=apply(6,event,'interrupted'); time.sleep(1.05)
    call(worker(6),f"public.get_booking_result('{f['booking_request_id']}')",rollback=True)
    check(SQL(f"select result from public.booking_requests where id='{f['booking_request_id']}';").stdout.strip()=='PENDING','allocator rollback leaves durable intake recoverable')
    SQL('set role service_role; select public.process_due_booking_windows(32);')
    check(resolve(6,f)['result']=='CONFIRMED','recovery job completes abandoned allocation')
    check(SQL(f"select count(*) from public.audit_logs where entity_id='{f['booking_request_id']}' and action='booking_resolved';").stdout.strip()=='1','rollback and retries produce one audited outcome')

    event=create_event(); SQL(f"update public.events set reporting_at=now()-interval '1 minute' where id='{event}';")
    check(apply(4,event,'stale-time')['result']=='EVENT_UNAVAILABLE','Apply rejects elapsed reporting time despite stale lifecycle status')
    check(SQL(f"select public.is_worker_tier_eligible('{event}','{worker(4)}',now());").stdout.strip()=='f','time eligibility is closed while lifecycle job is late')

    # Exercise actual second-level background recovery, with no client resolution calls.
    event=create_event(); req=apply(4,event,'cron-abandoned')
    job='r2-recovery-'+uuid.uuid4().hex[:10]
    try:
        SQL(f"select cron.schedule_in_database('{job}','1 second','select public.process_due_booking_windows(32)','{db.DATABASE}');",database='postgres')
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            status=SQL(f"select result from public.booking_requests where id='{req['booking_request_id']}';").stdout.strip()
            if status!='PENDING': break
            time.sleep(.2)
        check(status=='CONFIRMED','actual second-level scheduler resolves an abandoned client request')
    finally:
        SQL(f"select cron.unschedule('{job}');",database='postgres')


def main():
    global connections
    created=False
    sessions=[]
    try:
        SQL('create database '+db.DATABASE,database='postgres',role='supabase_admin'); created=True
        dump=db.command(['pg_dump','-U','supabase_admin','-d','postgres','--schema-only','--no-owner','--no-acl','--schema=auth','--schema=storage','--schema=extensions'])
        if dump.returncode: raise RuntimeError(dump.stderr)
        SQL(re.sub(r'CREATE POLICY .*?;\n','',dump.stdout,flags=re.S),role='supabase_admin')
        SQL(f"grant all on database {db.DATABASE} to postgres; grant all on schema public,auth,storage,extensions to postgres; grant usage on schema auth,extensions to anon,authenticated,service_role; grant all on all tables in schema auth,storage to postgres; grant all on all sequences in schema auth,storage to postgres; alter database {db.DATABASE} set search_path=public,extensions; create publication supabase_realtime; alter publication supabase_realtime owner to postgres;",role='supabase_admin')
        for path in sorted((ROOT/'supabase/migrations').glob('*.sql')):
            SQL('begin;\n'+path.read_text()+'\ncommit;')
        check(True,'all versioned migrations replay in a disposable database')
        SQL('begin;\n'+db.fixtures()+'\ncommit;')
        sessions=[Connection(),Connection()]
        connections=queue.Queue()
        for session in sessions: connections.put(session)
        scenarios()
        print(f'R2 PASSED: {checks} checks.',flush=True)
    finally:
        connections=None
        for session in sessions: session.close()
        if created:
            assert re.fullmatch(r'oslava_r2_test_[0-9a-f]{12}',db.DATABASE)
            SQL('drop database '+db.DATABASE+' with (force)',database='postgres',role='supabase_admin')
            print('Removed this run\'s disposable database.',flush=True)


if __name__=='__main__': main()
