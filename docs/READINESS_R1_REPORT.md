# R1 — permission and event-state corrections

Completed locally: 9 September 2026. Authorization: “begin R1.” R2 has not started.

## Baseline and scope

Starting HEAD: `d10b1129db17e4f9b12a5ffd6528b1dc3c812a6c`. The working copy already contained extensive Flutter, Android/iOS, documentation, dependency and backend changes, including implementation phases 12–16. Those changes were preserved. No commit was created.

Before R1, `npx supabase test db` passed 16 files / 452 assertions. The new authenticated permission regression failed against that baseline: Admin erasure requests successfully deactivated privileged targets. The existing readiness review's terminal-state findings were also reproduced in the disposable legacy-repair fixture.

R1 changes only backend permissions and terminal-state handling, with regression tests and completion documentation. Flutter files were not changed; Flutter analysis/tests were not rerun for this backend-only phase.

## Implemented behavior

- Admin erasure requests cannot target Admin or Super Admin accounts, including self-erasure. Super Admin retains the approved authority over other accounts. Required reasons and existing request/audit records remain in place.
- Erasure, role changes, phone changes, staff provisioning and account detention/release reject inactive privileged actors. These operations share a transaction lock before reading actor/target state. Erasure and demotion cannot remove the last active Super Admin, including overlapping requests.
- Authenticated reads exposed recursion in profile RLS actor lookups. Four narrowly scoped identity/permission lookup functions now execute as their owner with an empty search path and explicit execute grants, avoiding recursive profile-policy evaluation. Table grants and RLS remain enabled.
- Event cancellation changes confirmed assignments to `CANCELLED`, records cancellation cause `EVENT`, expires waiting entries without a penalty, skips outstanding reporting reminders, and creates deduplicated cancellation notifications for confirmed workers, waiting workers and active event leaders. It never invokes refill.
- Completion changes confirmed assignments to `COMPLETED`, records their completion time, expires waiting entries and stops outstanding reminders. Closure retains the completed assignments. Every changed assignment/waitlist entry receives an audit record; event transition history remains intact.
- Worker board precedence and My Work now reflect terminal event states. Terminal work cannot offer worker cancellation. Attendance, review and worker-cancellation RPCs acquire the event lock before the assignment lock to agree with the new transition operations.
- The migration repairs existing inconsistent cancelled/completed/closed records using recorded transition timestamps and actors. Repair preserves history, does not send retrospective cancellation notifications, and can be replayed without duplicate reconciliation effects.

## Attendance, reviews and reliability

The approved calculation and business rules are unchanged. Assignment updates activate the existing reliability recomputation triggers, so completed-work counts now reconcile with the event lifecycle.

Completion/closure never invent attendance or performance reviews. Missing attendance and explicit `NOT_MARKED` remain excluded from resolved samples. Actual attendance remains recorded; outstanding reviews can be entered after completion, but reviews are frozen after closure. Admin attendance corrections remain possible after closure and use the existing audit/history flow.

Event-caused cancellation does not become a worker cancellation or add a reliability penalty/sample. Completed-work count is contextual and does not turn unmarked work into a resolved commitment. Worker categories are not changed automatically.

## Verification

| Check | Result |
|---|---|
| Original database baseline | 16 files / 452 assertions passed |
| `npx supabase migration up --local` | R1 applied to the existing local stack; no database reset |
| `npx supabase test db` | 17 files / 502 assertions passed, including 50 new R1 assertions |
| `npx supabase db lint --local` | No schema errors |
| `python scripts/test_readiness_r1.py` | Fresh application migration replay; legacy repair and repeat repair; 16 files / 494 assertions; overlapping authenticated demotions passed |

The disposable harness copies only Supabase-managed schema definitions, replays application migrations under `postgres` ownership, and uses synthetic fixtures. It excludes the eight local-account bootstrap assertions because it does not copy or seed personal development account data; those assertions pass in the full local suite. Each harness run removes only its own newly created database. The existing local database and user records were not reset.

Coverage includes authenticated Admin-to-privileged-target denial, inactive actors, last-Super-Admin protection, normal public publish/apply/join/cancel flows, attendance → completion → closure, safe rejection of repeated transitions, worker projections, reliability counts, outstanding review/attendance rules, reminder cleanup and audit records. The two-session test observes overlapping transactions and verifies that the second demotion is rejected after the first commits.

## Files changed in R1

- `supabase/migrations/20260909010100_readiness_r1_permissions_event_states.sql` — versioned backend changes and legacy repair.
- `supabase/tests/database/readiness_r1_permissions_event_states.sql` — 50 maintained regressions.
- `scripts/test_readiness_r1.py` — disposable replay, legacy repair and concurrency harness.
- `docs/READINESS_R1_REPORT.md` — this report.
- `docs/READINESS_COMPLETION_PLAN.md` — authorization, coverage and R1 status.
- `docs/APP_READINESS_REVIEW_2026-09-08.md` — dated implementation-status note; original review retained.

## Outstanding work

R1's local exit conditions are met. No hosted migration push, deployment, APK creation, distribution or store submission was performed. Hosted permission/lifecycle acceptance remains R10; the application is not yet release-ready.

R2 owns booking arbitration and broader apply/cancel/refill concurrency. R8 owns delivery recovery, job scheduling and device notification verification. R9 owns user deletion initiation, verification and erasure fulfillment. These phases were not started. The next phase requires its own user instruction.
