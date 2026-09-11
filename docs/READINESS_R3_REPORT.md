# R3 — navigation, authentication and session lifecycle

Completed locally: 9 September 2026. Authorized by “begin R3,” followed by “finish the R3 - if something is left.” R4 has not started.

## What changed

R3 closes the local app-side readiness gaps around entry, navigation, account lifecycle and safe session transitions.

- Added persistent role navigation shells with Home, Events, role-specific work/team/profile destinations, Alerts and a visible Sign out action for each authenticated role.
- Converted role routes into nested routes so Home -> feature -> detail -> Back behaves predictably and cross-role deep links are redirected to the signed-in role's home.
- Added bootstrap/session status handling for loading, retryable account-check failures, restricted accounts and incomplete registration.
- Reworked login and recovery forms with scroll-safe layout, keyboard actions, password visibility, friendly errors, busy states and recovery OTP resend/expiry guidance.
- Completed registration flow basics: server privacy-version loading, required acknowledgement, photo validation before Auth creation, resumable draft/profile completion, hosted phone-confirmation OTP handling and Worker ID presentation after success.
- Hardened auth/session refresh: app subscribes to Auth state changes, refreshes on resume and periodically while active, ignores stale refresh results and rechecks server role/account status instead of trusting client metadata.
- Added safe logout/account switching: outgoing notification tokens are invalidated before sign-out, feature caches and search filters are cleared when identity/role/status changes, and denied notification permission does not block app use.
- Added reusable auth form/error/password helpers for later R4-R7 screens.

No database migration was required for R3. The existing server-side profile, privacy terms, auth and token contracts were reused.

## Regression coverage

New and updated tests cover:

- all five roles and cross-role deep-link rejection;
- nested feature/detail Back behavior;
- bootstrap races, failed refresh retry and restricted-account routing;
- account switch cache isolation and worker search reset;
- logout ordering with token invalidation before Auth sign-out;
- notification permission denial and outgoing-account token race protection;
- small-screen phone-keyboard overflow and password visibility;
- registration invalid photo before Auth creation, underage validation, duplicate/unconfirmed phone handling, success Worker ID, interrupted RPC/profile resume and active privacy-version use;
- password recovery with no automatic account creation, staging environment mapping and OTP-session cleanup after password update failure.

## Verification

| Command | Result |
|---|---|
| `flutter test --no-pub test/r3_session_navigation_test.dart test/r3_auth_repository_test.dart` | PASS — 17 focused R3 tests |
| `flutter analyze --no-pub` | PASS — no issues |
| `flutter test --no-pub` | PASS — 89 Flutter tests |
| `npx supabase test db` | PASS — 18 files, 519 assertions |

The Flutter suite still prints the pre-existing PDF Helvetica Unicode notice during report tests. It remains non-failing and belongs to the later export-quality work already assigned to R7/R10/R11.

## Files changed for R3

- `lib/app/app.dart`
- `lib/app/router/app_router.dart`
- `lib/features/auth/application/auth_session.dart`
- `lib/features/auth/application/logout.dart`
- `lib/features/auth/data/auth_repository.dart`
- `lib/features/auth/data/profile_photo_preparer.dart`
- `lib/features/auth/domain/auth_failure.dart`
- `lib/features/auth/domain/worker_registration_input.dart`
- `lib/features/auth/presentation/auth_widgets.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/presentation/password_recovery_screen.dart`
- `lib/features/auth/presentation/session_status_screen.dart`
- `lib/features/auth/presentation/worker_registration_screen.dart`
- `lib/features/notifications/data/fcm_device_token_service.dart`
- `lib/features/shell/presentation/role_home_screen.dart`
- `lib/features/shell/presentation/role_navigation_shell.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `test/app_router_test.dart`
- `test/r3_auth_repository_test.dart`
- `test/r3_session_navigation_test.dart`
- `docs/READINESS_COMPLETION_PLAN.md`
- `docs/READINESS_R3_REPORT.md`

## Remaining gates

R3's local exit conditions are met: users are not trapped in auth/navigation loops, registration reaches the correct worker experience, every role can log out, and session/data isolation is tested.

Real hosted SMS delivery, real FCM delivery/open handling, physical-device Back/keyboard/accessibility behavior and staging account-switching evidence remain R10 acceptance gates. Final public policy/contact/deletion-resource content remains R9. Domain-specific dashboards and feature screens remain owned by R4-R7.

The existing unrelated working-copy changes were preserved. No Git commit, remote migration push, deployment, APK generation/distribution or store submission was performed. R4 requires a separate instruction.
