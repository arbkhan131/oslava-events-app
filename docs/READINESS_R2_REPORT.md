# R2 — concurrent booking correctness

Completed locally: 9 September 2026. Authorized by “begin R2,” followed by “finish the R2 if something is left.” R3 has not started.

## Result

The reproduced final-seat priority failure is fixed. In the final independent-connection run, A entered **0.032 seconds after F** within the same one-second window, and A received the only confirmed assignment. F received `WAITLIST_AVAILABLE`, without automatic enrollment.

The window is still exactly one second. The implementation changes how intake and allocation commit; it does not replace the approved category order, same-category receipt order, one-hour conflict boundary, or explicit waitlist behavior.

## Backend changes

- `apply_for_event` stores a durable request and immediately returns `PENDING` when the final seat needs arbitration. It does not sleep while holding locks. Requests when more than one seat is available can still confirm immediately.
- Each request stores its own canonical acknowledgement IDs, late-cancellation acceptance, event version and trusted server receipt/category snapshot. Receipt is stamped when the server admits the request under the mutation lock. A client cannot supply a timestamp or category.
- A short shared transaction lock gives booking, promotion, cancellation, event changes and related worker-state changes a consistent lock order. The lock is released when intake commits, before the arbitration interval elapses. This deliberately favors correctness over maximum write concurrency; production-scale throughput remains an R10 measurement.
- Allocation waits for the recorded cutoff without holding an open sleeping transaction. It ranks contenders by receipt category A > B > C > F, receipt time, then request UUID. It revalidates current account/profile eligibility, tier, event time/state, mandatory consent/version, late consent, capacity, duplicates and cross-event conflicts before confirmation.
- A valid lower-priority candidate can win if a higher-priority candidate becomes ineligible. An outside-window arrival first resolves the older window and cannot displace its winner. Another pending key for the same worker/event returns the existing contender instead of creating a second one.
- Same-key retries return the original result. Reusing a new-format key with a different event or acknowledgement payload is rejected. Legacy final outcomes remain retrievable because their original full payload was never stored. Legacy pending rows are finalized as `ERROR / RETRY_WITH_NEW_KEY`; no consent is invented for them.
- `get_booking_result(request_id)` and `resolve_booking_request(idempotency_key)` resolve/read only the caller's request. Global recovery is service-only. Direct helper execution and direct table writes remain unavailable to clients. Final outcomes receive one audit record.
- `process_due_booking_windows` processes a bounded batch of due windows. A dedicated pg_cron job runs every second, independently of client polling and the later notification scheduler. A rolled-back allocation leaves the committed intake recoverable. No seat is committed unless the result, assignment and related effects commit together.
- Apply and promotion reject elapsed reporting time even when the lifecycle scheduler has not updated event status. Apply/promotion across different events cannot both confirm conflicting work for one worker. Cancel/refill races preserve capacity and cancellation idempotency.

## Minimal client compatibility

The event detail screen explicitly says a pending application is **not confirmed yet**, disables duplicate submission while a request is running, and retains the same request/key for an uncertain-result retry. It polls the server at 500 ms intervals for at most six attempts. If still unresolved, it offers a check action rather than fabricating success or failure.

Reopening an event checks for the account's server-side pending request and resumes it. Result resolution refreshes event detail, the event board and My Work. The broader acknowledgement UI and complete worker journey remain R6; authentication/session lifecycle remains R3.

## Verification

| Check | Result |
|---|---|
| `npx supabase migration up --local` | R2 applied locally; no reset or hosted push |
| `npx supabase test db` | 18 files, **519 assertions passed** |
| `npx supabase db lint --local` | No schema errors or warnings |
| `python scripts/test_readiness_r2.py` | Fresh migration replay and **40 checks passed** using warm independent PostgreSQL connections |
| `flutter test` | **72 tests passed**, including five new pending/resolution tests |
| `flutter analyze --no-pub` | No issues found |

The concurrency harness verifies within/outside-window category priority, same-category ordering, exactly one seat, same/different-key duplicates, changed-payload denial, another worker's result denial, conflicting event applications, separate mandatory/optional/late consent, detention during arbitration, cancellation during arbitration, cancel/apply/refill races, Apply versus waitlist promotion, changed event versions, allocator rollback/recovery, one audited outcome, and stale lifecycle time gates.

It also schedules an actual one-second recovery job against its disposable database and verifies completion without any client resolution calls. The temporary job is removed and the database is dropped afterward. Docker process-start overhead is excluded from the priority interval by opening database connections before the race. No hosted or personal account data is copied into the harness.

Existing sequential booking tests now exercise intake followed by resolution, retaining their original business assertions. R1's terminal-state regressions still pass. The existing PDF font notices during the Flutter suite concern the previously recorded R7 report-export work; they did not fail tests and were not changed in R2.

## Changed files

- `supabase/migrations/20260909020100_readiness_r2_booking.sql`
- `supabase/tests/database/readiness_r2_booking.sql`
- `supabase/tests/database/phase_9_atomic_booking.sql`
- `supabase/tests/database/phase_10_cancellation_waitlist.sql`
- `supabase/tests/database/readiness_r1_permissions_event_states.sql`
- `scripts/test_readiness_r2.py`
- `lib/features/booking/domain/booking_application_result.dart`
- `lib/features/booking/domain/settle_booking.dart`
- `lib/features/events/data/event_repository.dart`
- `lib/features/events/presentation/worker_event_detail_screen.dart`
- `test/booking_resolution_test.dart`
- `docs/BACKEND_LOGIC.md`
- `docs/READINESS_R2_REPORT.md`
- `docs/READINESS_COMPLETION_PLAN.md`
- `docs/APP_READINESS_REVIEW_2026-09-08.md`

## Remaining gates

R2's local exit conditions are met. Hosted migration approval, pg_cron availability/job execution, multi-device acceptance and production-scale measurements remain R10 gates. The global mutation lock is intentionally coarse; measured contention must guide any later optimization without weakening the one-second rule or worker conflict protection.

The existing unrelated working-copy changes were preserved. No Git commit, remote migration push, deployment, APK generation/distribution or store submission was performed. R3 requires a separate instruction.
