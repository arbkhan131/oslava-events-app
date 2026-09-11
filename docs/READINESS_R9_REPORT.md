# Readiness R9 report — Privacy, deletion and retention

Completed: 10 September 2026.

## What changed

- Added `20260910040100_readiness_r9_privacy_erasure_retention.sql` with self-service erasure initiation, user-visible erasure status, Admin/Super Admin verification, trusted due fulfillment, private profile-photo deletion tasks and retention cleanup integration.
- Extended account erasure records with verification, source, retry/error and photo-cleanup state so requests are auditable and resumable.
- Added fulfillment behavior that preserves operational/audit integrity while setting the account inactive, pseudonymizing current profile PII, clearing the current profile-photo reference, invalidating device tokens and queueing trusted Storage object deletion.
- Updated the R8 scheduled operations runner so trusted scheduled runs can execute retention cleanup and due verified erasure fulfillment.
- Added a Profile → Privacy and deletion card where workers can read the deletion process, submit a deletion request for verification and view request status.
- Added an external account-deletion request page template and runbook for store-review preparation. The template is intentionally marked as a placeholder until real business-approved contact details and hosted URL are supplied.
- Added Dart and SQL regressions for request/status parsing, self-request, duplicate prevention, unauthorized verification denial, Admin verification, fulfillment, token/photo cleanup, idempotent retries and direct-table privilege denial.

## Verification

- `flutter analyze --no-pub` — PASS.
- `flutter test --no-pub` — PASS, 100 tests.
- `npx supabase db reset` — PASS.
- `npx supabase test db` — PASS, 20 files / 587 assertions.

## Outstanding / later phases

- Real privacy/support contact details and the hosted external deletion request URL must be supplied and verified before store submission. I did not invent these values.
- Actual Storage object deletion requires a trusted backend/Edge worker to process `profile_photo_deletion_tasks` in the hosted environment; R9 queues and tracks the task, and hosted proof remains R10/R11.
- No remote database push, deployment, APK build, external hosting, store submission or tester messaging was performed.
