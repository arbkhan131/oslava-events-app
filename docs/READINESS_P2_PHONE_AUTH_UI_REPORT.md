# Readiness P2 - Phone login and worker registration UI

Date: 2026-09-11

## Completed

- Replaced the worker-facing login form with WhatsApp number + password. The UI shows the fixed `+91` prefix and accepts common Indian phone formats while internally mapping the number to the hidden Supabase Auth email.
- Removed the password reset action from the worker login screen for this phase, matching the no OTP / no SMS / no recovery requirement.
- Rebuilt worker registration around the approved fields:
  - New worker / old worker
  - Name with initial
  - Place
  - WhatsApp number
  - Height
  - Studying class
  - Work experience dropdown
  - Passport size photo
  - ID card upload
  - Date of birth with complete-years age display
  - Password
  - Old-worker category dropdown only
- Added phone-password registration bootstrap through `create-worker-phone-account`, an Edge Function that creates the hidden confirmed Supabase Auth user without email confirmation or OTP.
- Updated registration completion to upload both passport photo and ID card, then call the P1 `complete_phone_worker_registration` RPC.
- Updated pending/rejected/restricted account messaging so newly registered workers see pending approval instead of a generic error.
- Added `file_picker` for ID-card document selection.
- Pushed P1 database migrations to hosted staging and deployed the new Edge Function.

## Hosted staging

Applied migrations:

- `20260911010400_p1_worker_approval_statuses.sql`
- `20260911010500_p1_phone_pending_registration.sql`

Deployed functions:

- `create-worker-phone-account`

## Validation

Passed:

- `flutter pub get`
- `flutter analyze`
- `flutter test test/auth_domain_test.dart test/r3_auth_repository_test.dart`
- `flutter test test/r3_session_navigation_test.dart`
- `flutter test`

Database test result:

- `npx supabase test db` still fails in the older `readiness_r1_permissions_event_states.sql` erasure-permission checks. The new P1 phone-registration database test passes, and the failing R1 test is unchanged from before P2.

## Outstanding

- P3 should add the captain/supervisor approval UI and worker detail display for the new registration fields.
- A new hosted APK must be built before tester distribution, because the current APK predates these P2 UI changes.
