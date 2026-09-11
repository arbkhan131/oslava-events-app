# P1 Phone Registration Backend Foundation Report

Date: 2026-09-11
Scope: Phase 1 backend foundation for phone/password login, pending worker registration, approval/rejection, and private ID-card storage.

## What changed

### Account approval states

Added explicit worker review states to `public.account_status`:

- `PENDING_APPROVAL`
- `REJECTED`

This avoids overloading `INACTIVE`, which is already used for disabled/deactivated/erasure flows.

### Worker registration metadata

Added worker registration metadata to `public.worker_profiles`:

- `registration_type`: `NEW_WORKER` or `OLD_WORKER`
- `requested_category`: required only for old workers
- `id_card_file_path`: private uploaded ID-card file path
- `experience_level`: `NO_EXPERIENCE`, `SOME_EXPERIENCE`, `HIGHLY_EXPERIENCED`

New workers cannot submit a category and default to category `F` at the backend level.

### Phone auth foundation

Added `public.phone_auth_email(phone_e164)`.

The user-facing flow can collect phone + password, while the app internally signs into Supabase Auth using a generated hidden email such as:

`919876543210@phone.oslava.local`

This keeps Supabase Auth/RLS intact without exposing email login to workers.

### Pending phone registration RPC

Added `public.complete_phone_worker_registration(...)`.

It creates a worker profile as `PENDING_APPROVAL`, stores registration details, stores the requested category only for old workers, defaults new workers to `F`, writes privacy acceptance, category history, and audit logs.

### Review RPC

Added `public.review_worker_registration(...)`.

Allowed reviewer roles:

- Super Admin
- Admin
- Captain
- Supervisor

Review outcomes:

- approve: status becomes `ACTIVE`, category is confirmed
- reject: status becomes `REJECTED`

Both paths write account action and audit records.

### Private ID-card storage

Added private Supabase Storage bucket:

- `worker-id-cards`

Policies allow workers to upload/read their own pending ID-card file, staff who can view worker records to view ID cards, and service role full access.

### Worker directory extension

Extended `public.worker_directory(...)` to include registration review fields so P3 approval UI can list and inspect pending workers.

## Files changed

- `supabase/migrations/20260911010400_p1_worker_approval_statuses.sql`
- `supabase/migrations/20260911010500_p1_phone_pending_registration.sql`
- `supabase/tests/database/readiness_p1_phone_pending_registration.sql`
- `supabase/tests/database/phase_2_foundation.sql`
- `supabase/tests/database/local_dev_bootstrap.sql`
- `supabase/tests/database/readiness_r12_leader_push_notifications.sql`

## Verification

Passed:

- `npx supabase db reset`
  - Full migration chain applies cleanly through P1.
- P1 pgTAP behavior inside `npx supabase test db`
  - phone hidden-email helper exists
  - phone registration RPC exists
  - review RPC exists
  - phone normalization works
  - new worker registers as pending
  - new worker defaults to F
  - new worker cannot request category
  - old worker can request category
  - pending worker cannot see event board
  - captain can approve pending worker
  - approved worker can see event board
  - captain can reject pending worker
- Existing R12 notification test now has corrected plan count.
- Existing account status enum test updated for the intentional new states.
- Local bootstrap auth identity expectation updated to match the current post-R11 email-auth seed.

Full `npx supabase test db` still fails only in `readiness_r1_permissions_event_states.sql`. That failure is outside P1 and appears to be an older R1 permissions/erasure regression in the current migration chain, not caused by the P1 registration changes. It should be handled as a separate permissions hardening fix before final APK readiness.

## Hosted staging

Not pushed to hosted Supabase yet. Per project rule, hosted `npx supabase db push` needs explicit approval.

## Next phase readiness

P2 can now build the phone/password login and the new registration form against these backend APIs.
