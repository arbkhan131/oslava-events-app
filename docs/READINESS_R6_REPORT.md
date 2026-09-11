# R6 readiness report — Worker event and work journeys

Date: 10 September 2026  
Scope requested: `begin R6` only.

## Result

R6 is complete locally. A Worker can now browse richer event cards, open a complete commitment detail page, acknowledge requirements, apply with the R2 pending/final-result protocol, join a waitlist with required acknowledgements, withdraw from a waiting waitlist entry, cancel confirmed work before the server deadline, and track confirmed/waitlisted/completed/history work from My Work and Worker Home.

## Implemented

- Added `worker_event_detail_full(event_id)` RPC as a worker-scoped detail read model with event schedule, worker action state, own waitlist state, requirements, allowances and event leaders.
- Added `worker_my_waitlist()` RPC so My Work can show active and historical waitlist entries without direct table mutation authority.
- Wired `withdraw_waitlist` into the Flutter event repository.
- Extended worker event/domain models with requirement, allowance, leader and own-waitlist fields.
- Added `WorkerWaitlistEntry` for My Work waitlist/history presentation.
- Updated the worker event board cards to show wage, vacancy, open categories and locked-tier countdown hints.
- Reworked worker event detail to show schedule, wages/allowances, requirements, Maps URL, instructions, dress code, event leaders, own waitlist position and action state.
- Added requirement acknowledgement checkboxes and late-booking acknowledgement to Apply and Join Waitlist calls. Apply preserves one idempotency key while the result is pending/uncertain.
- Expanded My Work to four tabs: Confirmed, Waitlist, Completed and History. Confirmed work shows the cancellation deadline; waitlist entries can be withdrawn with a reason; all rows drill down to event detail.
- Updated Worker Home with next confirmed work, active waitlist count, available-event count and category/reliability explanation.

## Changed R6 files

- `supabase/migrations/20260910010100_readiness_r6_worker_journeys.sql`
- `supabase/tests/database/phase_10_cancellation_waitlist.sql`
- `lib/features/events/domain/worker_event.dart`
- `lib/features/events/data/event_repository.dart`
- `lib/features/events/presentation/worker_event_list_screen.dart`
- `lib/features/events/presentation/worker_event_detail_screen.dart`
- `lib/features/events/presentation/worker_my_work_screen.dart`
- `lib/features/booking/domain/worker_assignment.dart`
- `lib/features/shell/presentation/role_home_screen.dart`
- `test/event_management_test.dart`
- `docs/READINESS_COMPLETION_PLAN.md`
- `docs/READINESS_R6_REPORT.md`

## Verification

- `npx supabase migration up --local` — passed for the R6 migration.
- `flutter analyze --no-pub` — passed, no issues.
- `flutter test --no-pub test/event_management_test.dart` — passed, 22 tests.
- `npx supabase test db supabase/tests/database/phase_10_cancellation_waitlist.sql` — passed, 33 assertions.
- `flutter test --no-pub` — passed, 95 tests.
- `npx supabase test db` — passed, 19 files / 551 assertions.

## Outstanding / moved forward

- Real push/deep-link refresh and background notification delivery remain R8/R10 gates.
- Physical-device, offline-after-commit and two-device race acceptance remain R10 gates.
- Field operations and report-side reconciliation remain R7.
- R7 has not been started.