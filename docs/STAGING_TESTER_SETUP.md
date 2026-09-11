# Staging Tester Setup

## Recommended Staging Shape

Physical-phone APK testing should use the hosted Supabase project `oslava-events-dev`, not the local Supabase CLI API. Local addresses such as `127.0.0.1` and `10.0.2.2` are for local/emulator development only and are not reliable for testers.

## Initial Staging Account

Only this initial Super Admin should be bootstrapped:

| Role | Phone |
| --- | --- |
| SUPER_ADMIN | `+918864938636` |

After Super Admin login works, create real Admin, Captain, and Supervisor accounts through the app's approved role-management flows. Workers should register themselves with their own phone numbers.

## APK Build Inputs

Build staging APKs with:

```powershell
flutter build apk --release `
  --dart-define=OSLAVA_ENV=staging `
  --dart-define=SUPABASE_URL=https://vrpxpidnbhnuismbzroe.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=<staging-publishable-or-anon-key>
```

Only the Supabase project URL and public publishable/anon key may be bundled in Flutter. Never bundle service-role keys, database passwords, SMS provider credentials, Firebase server credentials, or Supabase Management API tokens.

## Supabase Work Needed Before Tester APKs

1. Apply the reviewed migrations to `oslava-events-dev`.
2. Configure hosted Supabase Auth phone/SMS settings.
3. Create or confirm the Auth user for `+918864938636`.
4. Add the matching `profiles` row with role `SUPER_ADMIN` and `account_status = ACTIVE`.
5. Confirm worker self-registration can create phone/password Auth users and complete profiles.
6. Build a staging APK using the hosted project URL and public anon/publishable key.

## Tester Smoke Test

1. Install the staging APK.
2. Login as Super Admin.
3. Create an Admin.
4. Login as Admin.
5. Create Captain and Supervisor users.
6. Register one Worker using a real tester phone number.
7. Create and publish a test event.
8. Verify Worker discovery, Apply, waitlist/cancellation, attendance, performance/reliability, notifications, reports, and logout/account switching.
