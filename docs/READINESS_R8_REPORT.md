# Readiness R8 report — Scheduled operations and notifications

Completed: 10 September 2026.

## What changed

- Added `20260910030100_readiness_r8_scheduled_operations_notifications.sql` with scheduled job run records, RLS/grants, a service-role scheduler RPC, notification delivery health output, expiring outbox leases, and a worker-owned delivery completion RPC.
- Updated the notification dispatcher Edge Function to use owned completion, per-delivery timeout/error isolation, permanent invalid-token detection, and either direct FCM authorization or an explicit proxy shared-secret contract. Dispatcher invocation can also be protected with `DISPATCHER_SHARED_SECRET`.
- Added unread alert counting, an Alerts-tab badge, server quiet-hours policy copy, role-aware notification target resolution, and screen/provider refresh after notification open/read.
- Extended notification regression coverage for lease creation, wrong-dispatcher rejection, secure completion ownership, health records, scheduled runner results, and role-aware deep-link fallback.

## Verification

- `flutter analyze --no-pub` — PASS.
- `flutter test --no-pub` — PASS, 99 tests.
- `npx supabase db reset` — PASS after patching the RLS helper to the existing `private.current_actor_role()` helper.
- `npx supabase test db` — PASS, 19 files / 567 assertions.

## Outstanding / later phases

- Hosted scheduler evidence, real FCM credential/proxy proof, and physical-device push delivery evidence remain R10/R11 work.
- No remote database push was run.
