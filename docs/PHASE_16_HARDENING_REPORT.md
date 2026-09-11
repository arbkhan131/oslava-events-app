# Phase 16 Hardening Report

## Scope

Phase 16 closes the approved V1 production-hardening decisions for privacy, retention, audit retention, backup/restore, incident response, and final local verification. No remote Supabase project was modified and `npx supabase db push` was not run.

## Implemented Controls

- Worker registration requires the active Privacy Notice and Terms version before `complete_worker_registration` can complete.
- Privacy acknowledgement records store user ID, version, and server timestamp.
- Verified erasure requests are Admin/Super Admin controlled, immediately set the target profile `INACTIVE`, create a 30-day due date, and audit the request.
- Retention cleanup supports dry-run and live modes, records each run, and is idempotent.
- Live retention cleanup deletes expired in-app notifications, expired terminal delivery attempts, invalidated device tokens, and expired audit logs that are not under active legal hold.
- Normal client roles cannot directly forge privacy acknowledgements, retention cleanup runs, or mutate audit logs.
- Profile-photo lifecycle, backup/restore expectations, and incident response are documented in dedicated runbooks.

## Verification Results

| Check | Result |
|---|---|
| `npx supabase db reset` | PASS |
| `npx supabase test db` | PASS, 16 files, 461 assertions |
| `npx supabase db lint --local` | PASS, no schema errors |
| `flutter analyze` | PASS, no issues |
| `flutter test -j 1` | PASS, 66 tests |
| `flutter pub outdated` | PASS review; direct and dev dependencies are current |
| Secret/config review | PASS for Flutter/server-secret separation; no Firebase service-account key or Supabase service-role credential was found in Flutter code |

## Acceptance Coverage

- Full pgTAP suite includes RLS allow/deny, role/account authorization, event lifecycle, tier scheduling, booking arbitration, waitlist/cancellation, attendance, performance/category, reliability, notifications, reporting/export, and Phase 16 privacy/retention checks.
- Flutter unit/widget tests cover app bootstrap, environment separation, route guards, auth domain validation, worker/event/attendance/review/notification/report models, and report PDF generation.
- High-volume production load testing remains an environment activity; local concurrency and capacity invariants are covered by the database acceptance suite.

## Backup And Restore Position

Desired production targets:

- RPO: <= 1 hour where the selected Supabase plan supports PITR or equivalent backup cadence.
- RTO: <= 4 hours for database, Storage, Edge Functions/config, Firebase/FCM configuration, and secrets restoration.

Actual verified state:

- Local restore rehearsal: migration-based rebuild via `npx supabase db reset` passed.
- Production PITR, Storage restore, Edge Function restore, Firebase/FCM restore, and isolated non-production restore rehearsal are not yet verified because production deployment/configuration is not part of this local Phase 16 execution.

## Remaining Launch Dependencies

- Confirm the production Supabase plan supports the desired PITR/RPO target, or formally accept a lower RPO.
- Perform and record an isolated non-production restore rehearsal using production-like backup artifacts.
- Configure production secrets outside Git for Supabase Edge Functions, Firebase/FCM dispatch, and any SMS provider.
- Verify production Storage backup/restore behavior for the private `profile-photos` bucket.
- Assign business/privacy and incident-response contacts before launch.
