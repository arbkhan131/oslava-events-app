# R4 — team, worker directory and profiles

Completed locally: 9 September 2026. Authorized by “begin R4.” R5 has not started.

## What changed

R4 closes the local readiness gaps around establishing staff accounts, finding workers and viewing/updating profile information.

- Added a trusted staff-account provisioning path: the `manage-staff-account` Edge Function creates the Supabase Auth user with the service-role key, then calls the database provisioning RPC with the caller's JWT so the database remains authoritative for Admin/Super Admin permissions and auditing.
- Strengthened staff provisioning with explicit role boundaries, required reason, duplicate-profile and duplicate-phone checks, role history and audit logging.
- Added staff directory support for Admin/Super Admin screens, with Admin visibility limited away from Admin accounts.
- Extended `worker_directory` with offset pagination while preserving the existing four-argument caller behavior through a defaulted fifth argument.
- Wired worker search filters for account status/category, debounce, pagination, refresh/retry states and signed private photo thumbnails.
- Added staff management UI inside the worker directory for Admin/Super Admin users: view staff accounts, create staff accounts and perform controlled phone corrections.
- Added private profile photo display for own profile and staff worker detail screens.
- Added own-profile photo replacement: upload the new object, update the profile reference, then best-effort cleanup the old object after the profile points to the new photo.
- Exposed controlled phone reassignment from worker detail, reusing the R1 `change_user_phone` RPC so Auth, profile, audit and phone history stay server-controlled.

The first R4 migration was locally recorded before a return-type/signature correction. A second versioned corrective migration is included so existing local chains are repaired without a database reset.

## Regression coverage

New and updated tests cover:

- Super Admin provisioning an Admin profile;
- Admin blocked from provisioning Admin accounts;
- Admin provisioning Captain profiles;
- staff provisioning audit records;
- duplicate profile/phone protection;
- Worker denied staff-directory access;
- Admin staff-directory visibility boundaries;
- paginated worker-directory offset behavior;
- controlled phone reassignment history;
- Admin blocked from changing Admin phone numbers;
- worker directory UI smoke coverage for paginated query and team-account panel;
- staff provisioning request serialization.

## Verification

| Command | Result |
|---|---|
| `npx supabase migration up --local` | PASS — R4 migrations applied locally |
| `npx supabase test db supabase/tests/database/readiness_r4_team_profiles.sql` | PASS — 16 focused R4 assertions |
| `npx supabase test db` | PASS — 19 files, 535 assertions |
| `flutter analyze --no-pub` | PASS — no issues |
| `flutter test --no-pub test/worker_management_test.dart` | PASS — 12 focused worker-management tests |
| `flutter test --no-pub` | PASS — 91 Flutter tests |

The Flutter suite still prints the pre-existing PDF Helvetica Unicode notice during report tests. It remains non-failing and belongs to later export-quality work.

## Files changed for R4

- `lib/features/workers/data/worker_repository.dart`
- `lib/features/workers/domain/worker_profile.dart`
- `lib/features/workers/presentation/edit_worker_profile_screen.dart`
- `lib/features/workers/presentation/worker_detail_screen.dart`
- `lib/features/workers/presentation/worker_directory_screen.dart`
- `lib/features/workers/presentation/worker_profile_screen.dart`
- `supabase/functions/manage-staff-account/index.ts`
- `supabase/migrations/20260909030100_readiness_r4_team_profiles.sql`
- `supabase/migrations/20260909030200_readiness_r4_team_profiles_fix.sql`
- `supabase/tests/database/phase_4_worker_management.sql`
- `supabase/tests/database/readiness_r4_team_profiles.sql`
- `test/worker_management_test.dart`
- `docs/READINESS_COMPLETION_PLAN.md`
- `docs/READINESS_R4_REPORT.md`

## Remaining gates

R4's local exit conditions are met: Super Admin/Admin staff establishment has a trusted server path, worker directory/profile work is usable from the app, private photos use signed URLs, own-photo replacement follows safe ordering, and role/account changes remain server-controlled and audited.

Hosted Edge Function deployment, real service-role configuration, hosted Auth/SMS behavior, private Storage object checks on physical devices and representative large-directory performance remain R10 gates. Full deletion/photo erasure lifecycle remains R9. Event leader assignment consumes these team-management capabilities in R5.

The existing unrelated working-copy changes were preserved. No Git commit, remote migration push, Edge Function deployment, APK generation/distribution or store submission was performed. R5 requires a separate instruction.
