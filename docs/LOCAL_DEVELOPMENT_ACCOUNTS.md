# Local Development Accounts

These accounts are fake fixtures for the local Supabase stack only. They are loaded by `npx supabase db reset` through `supabase/seed.sql`, and the seed refuses to run unless the database exposes Supabase CLI's local JWT secret.

Do not run `npx supabase db push` for these fixtures. Do not copy these accounts into a hosted Supabase project.

## Android Emulator Configuration

Android emulators cannot reach the Windows host Supabase API through `localhost` or `127.0.0.1`. Run the app for emulator testing with:

```bash
flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:54321
```

The local fallback key in Flutter is Supabase CLI's local publishable key, so the Android override usually only needs `SUPABASE_URL`. Host-side tests and desktop runs may continue to use the default local URL `http://127.0.0.1:54321`.

To run the repeatable Android live-auth check on the Pixel_7 emulator:

```bash
flutter test integration_test/local_role_login_test.dart -d emulator-5554 --dart-define=SUPABASE_URL=http://10.0.2.2:54321
```

## Password Recovery OTP

Local SMS OTP is configured in `supabase/config.toml` through `auth.sms.test_otp`. The OTP map uses the Supabase CLI-supported digit-only local test keys, while app login still uses the E.164 phone numbers below. All local development accounts use:

```text
OTP: 123456
```

No real SMS provider account is required for local development. `supabase/config.toml` contains clearly fake local-only Twilio placeholder IDs only because this Supabase CLI/Auth version disables phone login unless a provider switch is enabled; seeded test phones use the fixed `auth.sms.test_otp` values instead of sending SMS.

## Credentials

| Role | Phone | Password |
| --- | --- | --- |
| SUPER_ADMIN | `+919000000001` | `OslavaDev!01` |
| ADMIN | `+919000000002` | `OslavaDev!02` |
| CAPTAIN | `+919000000003` | `OslavaDev!03` |
| SUPERVISOR | `+919000000004` | `OslavaDev!04` |
| WORKER F | `+919000000005` | `OslavaDev!05` |
| WORKER C | `+919000000006` | `OslavaDev!06` |
| WORKER B | `+919000000007` | `OslavaDev!07` |
| WORKER A | `+919000000008` | `OslavaDev!08` |

Worker accounts are `ACTIVE`, have complete fake local-development profile data, have generated numeric Worker IDs after each reset, and point at private `profile-photos` storage fixture objects.
