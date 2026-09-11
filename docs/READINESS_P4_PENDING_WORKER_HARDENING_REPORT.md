# Readiness P4 - Pending worker access and notification hardening

Date: 2026-09-11

## Completed

- Confirmed existing worker event functions already require active worker status for event-board visibility, application, and waitlist actions.
- Added backend hardening so non-active accounts cannot register push-device tokens. This blocks `PENDING_APPROVAL` and `REJECTED` workers before they can receive event push notifications.
- Updated notification delivery enqueueing so even if a stale active token exists for a pending/rejected user, new notification rows do not create FCM delivery rows.
- Updated notification delivery claiming so the dispatcher skips stale deliveries whose recipient account is no longer active.
- Added a profile-status trigger that deactivates device tokens whenever an account changes away from `ACTIVE`.
- Added focused database coverage for pending/rejected token denial, stale pending-token delivery prevention, dispatcher skip behavior, and token deactivation after non-active status change.

## Validation

Passed:

- `npx supabase db reset`
- `npx supabase test db supabase/tests/database/readiness_p4_pending_worker_hardening.sql`
- `flutter analyze`
- `flutter test`

Full database suite result:

- `npx supabase test db` still fails only in the older `readiness_r1_permissions_event_states.sql` erasure-permission test. The new P4 hardening test passes inside the full suite.

## Hosted staging

- Hosted Supabase rejected the initial push attempt with the 403 access-control error before P4 started. P3 and P4 migrations need to be pushed together once project DB push access is available again.

## Outstanding

- Build a fresh hosted staging APK after P3/P4 migrations are applied to hosted staging.
- The old R1 erasure-permission regression remains separate from the phone-registration and pending-worker readiness work.
