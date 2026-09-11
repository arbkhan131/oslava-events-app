# Readiness R11 — Email authentication migration

Date: 2026-09-10

## Result

R11 moved the app's authentication identity from phone/password to email/password for all roles. Phone numbers remain as contact/profile data for worker directories, attendance, reports, and controlled phone corrections.

## Completed

- Login now uses email address + password.
- Worker registration now collects email for Auth identity and phone as contact data.
- Worker registration calls Supabase Auth `signUp` with email/password and sends `email` plus `phone_e164` to the authoritative `complete_worker_registration` RPC.
- Password reset now sends a Supabase email reset link instead of phone OTP.
- Staff provisioning UI and `manage-staff-account` Edge Function now create Auth users with email/password while still saving phone on the profile.
- Added versioned migration `20260910050100_readiness_r11_email_auth.sql` to replace `complete_worker_registration` for email Auth and retain backend authority over profile creation.
- Updated local seed so the requested Super Admin can log in locally with email/password.
- Removed dormant `integration_test` dev dependency from release packaging and excluded the old integration-test folder from analyzer to prevent release APK plugin registration failures.
- Rebuilt and installed the hosted staging APK on the connected Android device; Login screen now shows Email address.

## Requested Super Admin

- Email: `arbkh.03.11@gmail.com`
- Password: `123456`
- Role: `SUPER_ADMIN`

This is present in local seed/bootstrap. Hosted staging still needs the migration applied and the Auth/profile user created in the hosted Supabase project with admin/service-role privileges.

## Verification

- `flutter analyze --no-pub` — PASS.
- `flutter test --no-pub` — PASS, 100 tests.
- `npx supabase test db` — PASS, 20 files / 587 assertions.
- Hosted staging release APK build — PASS.
- APK signature verification — PASS.
- Physical Android install/open smoke — PASS; Login screen rendered with Email address field.

## APK

- Path: `A:/Dev/oslava_events/build/app/outputs/flutter-apk/app-release.apk`
- Size: 64,994,371 bytes
- SHA-256: `ebd32b6eeab8b2dcb7ce384b492f8e2bc70c24ebab91ec62f20be7a56f594939`
- Screenshot: `A:/Dev/oslava_events/build/app/outputs/flutter-apk/r11_email_auth_login.png`

## Outstanding before sharing with testers

- Apply the R11 migration to hosted Supabase. Per project rule, do not run `npx supabase db push` without explicit approval.
- Enable Email provider in hosted Supabase Auth. It already appeared enabled during the R10 probe, but confirm before testing.
- Create/confirm the hosted Auth user and `profiles` row for `arbkh.03.11@gmail.com` as active `SUPER_ADMIN`.
- Verify hosted login on the phone after hosted migration/user setup.


## Hosted push attempt

The user approved pushing hosted Supabase changes, but Supabase CLI returned `403` for both `npx supabase db push` and `npx supabase functions deploy manage-staff-account --project-ref vrpxpidnbhnuismbzroe`.

Blocker: the Supabase account/token configured on this machine does not have sufficient hosted project privileges for database migration or Edge Function deployment.

Required resolution: grant the CLI account Owner/Developer access to project `oslava-events-dev`, or apply the R11 SQL and function update manually from an authorized Supabase account.
