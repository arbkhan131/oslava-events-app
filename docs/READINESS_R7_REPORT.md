# R7 readiness report — Field operations and reports

Date: 10 September 2026  
Scope requested: `start R7` only.

## Result

R7 is complete locally. Field leaders and management now have a stronger event-day workflow: assigned-event dashboard, richer searchable roster with full-event counters, worker photo display, attendance correction with notes, editable performance reviews, report audit filters/pagination, and improved report/export visibility.

## Implemented

- Added `field_event_dashboard()` RPC for Captain/Supervisor/Admin visible events, today's assigned events, required/filled staffing and attendance summary counters.
- Added `event_attendance_roster_v2(event_id, search_text)` RPC with full-event counters separated from filtered roster count, current reviewer performance review values, and worker photo paths.
- Added `event_audit_history_filtered(event_id, action, actor_role, limit, offset)` RPC for authorized report filtering/pagination.
- Kept attendance, review authorization and reliability reconciliation server-side. Flutter displays and edits through existing RPCs only.
- Updated the field event list into a dashboard/list with refresh, retry, empty and error states.
- Updated attendance roster to show full counters plus filtered count, category grouping, search helper text, worker signed photos, attendance notes, current review rating and edit-review entry point.
- Added signed profile-photo loading through the attendance repository.
- Updated the performance review dialog to prefill existing review stars/tags/notes so field leaders can correct reviews before Close.
- Added report audit filters by action text and actor role, plus incremental history loading.
- Kept PDF export and copy summary working with the current report math and staffing rows.

## Changed R7 files

- `supabase/migrations/20260910020100_readiness_r7_field_ops_reports.sql`
- `supabase/tests/database/phase_11_attendance.sql`
- `supabase/tests/database/phase_15_reports_audit.sql`
- `lib/features/attendance/domain/attendance_roster.dart`
- `lib/features/attendance/data/attendance_repository.dart`
- `lib/features/attendance/presentation/field_event_list_screen.dart`
- `lib/features/attendance/presentation/attendance_roster_screen.dart`
- `lib/features/reports/data/report_repository.dart`
- `lib/features/reports/presentation/event_report_screen.dart`
- `test/attendance_test.dart`
- `docs/READINESS_COMPLETION_PLAN.md`
- `docs/READINESS_R7_REPORT.md`

## Verification

- `npx supabase migration up --local` — passed for the R7 migration.
- `flutter analyze --no-pub` — passed, no issues.
- `flutter test --no-pub test/attendance_test.dart test/report_test.dart` — passed, 13 tests.
- `npx supabase test db supabase/tests/database/phase_11_attendance.sql` — passed, 27 assertions.
- `npx supabase test db supabase/tests/database/phase_15_reports_audit.sql` — passed, 14 assertions.
- `flutter test --no-pub` — passed, 97 tests.
- `npx supabase test db` — passed, 19 files / 557 assertions.

## Outstanding / moved forward

- Real push/deep-link refresh and automated job delivery remain R8.
- Physical-device accessibility, export-share and large-roster acceptance remain R10/R11 gates.
- PDF embedded Unicode font improvement remains a release-quality/export hardening item; current tests still pass but the PDF library warns about Helvetica Unicode coverage.
- Global cross-event report dashboards beyond event-scoped reports can be expanded later if testers need them; R7 event operations and event reports are functional locally.
- R8 has not been started.