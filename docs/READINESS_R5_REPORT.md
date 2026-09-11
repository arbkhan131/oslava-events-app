# R5 readiness report — Admin event management

Date: 9 September 2026  
Scope requested: `begin R5` only.

## Result

R5 is complete locally. Admin and Super Admin can now create and edit event drafts using explicit Asia/Kolkata date and 12-hour time inputs, inspect full event setup, publish/cancel/complete/close events, see today's staffing counters and filter the event list by lifecycle status. No event schedule is silently invented by the UI.

## Implemented

- Added `admin_event_detail(event_id)` RPC with authorized full event payload: schedule, maps, staffing counts, waitlist count, unresolved assignment-review flags, leaders, requirements and allowances.
- Added `admin_event_dashboard()` RPC with authorized dashboard counters for today's events, required/confirmed/vacant staffing and lifecycle totals.
- Extended Phase 5 database tests to cover the new RPCs, multiple leaders, detail payloads, dashboard counters and the guard that blocks capacity reductions below confirmed assignments without the management-removal/review workflow.
- Extended Flutter event domain models for admin detail, dashboard, leader inputs, requirement inputs and allowance inputs.
- Extended the event repository with admin detail/dashboard loading and versioned event update support.
- Replaced the admin event form's fixed one-week 9 AM schedule with explicit date, reporting, work-start and expected-end inputs in Asia/Kolkata. Overnight events are supported by rolling start/end to the next day when needed.
- Added edit support with expected-version updates, custom tier validation, leader selection from active Captain/Supervisor staff, requirements/acknowledgement fields, allowances, Maps URL, instructions and dress code.
- Rebuilt the admin event detail screen around the new backend detail payload, including staffing impact, unresolved flags, leaders, requirements, allowances and lifecycle actions.
- Added Admin/Super Admin edit routes.
- Added dashboard and lifecycle filter states to the admin event list with refresh, error and empty states.

## Changed R5 files

- `supabase/migrations/20260909040100_readiness_r5_admin_event_management.sql`
- `supabase/tests/database/phase_5_event_management.sql`
- `lib/features/events/domain/event_summary.dart`
- `lib/features/events/data/event_repository.dart`
- `lib/features/events/presentation/admin_event_form_screen.dart`
- `lib/features/events/presentation/admin_event_list_screen.dart`
- `lib/features/events/presentation/admin_event_detail_screen.dart`
- `lib/app/router/app_router.dart`
- `test/event_management_test.dart`
- `docs/READINESS_COMPLETION_PLAN.md`
- `docs/READINESS_R5_REPORT.md`

## Verification

- `npx supabase migration up --local` — passed for the R5 migration.
- `npx supabase test db supabase/tests/database/phase_5_event_management.sql` — passed, 64 assertions.
- `flutter analyze --no-pub` — passed, no issues.
- `flutter test --no-pub test/event_management_test.dart` — passed, 20 tests.
- `flutter test --no-pub` — passed, 93 tests.
- `npx supabase test db` — passed, 19 files / 545 assertions.

## Outstanding / moved forward

- Explicit management removal and assignment-review resolution backend primitives existed as constraints/flags around event edits, but a full worker-removal picker/resolution workflow is still best completed in the worker/field operations journey where assignment state is operated directly. R5 now blocks silent capacity drops and shows the impact/reason.
- Calendar UI is represented by status filters and today's dashboard counters; a visual calendar grid is not necessary for the R5 exit gate but can be added later if testers ask for it.
- Hosted staging, real device verification, SMS/FCM, load testing and APK production remain R10 gates.
- Broad reports/audit exploration remains R7.
- R6 has not been started.