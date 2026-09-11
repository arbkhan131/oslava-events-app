# Local Development Account

The local Supabase seed creates one local-only Super Admin account after `npx supabase db reset`.

This account exists only in the local Supabase CLI stack. The seed refuses to run unless the database exposes Supabase CLI's local JWT secret, so it must not be copied into a hosted Supabase project.

## Local Super Admin

| Role | Phone | Password |
| --- | --- | --- |
| SUPER_ADMIN | `+918864938636` | `OslavaLocalOnly!01` |

Temporary Admin, Captain, Supervisor, and Worker credentials are no longer seeded. Admin/Captain/Supervisor accounts should be created through the approved Super Admin/Admin flows. Workers should self-register.

## Password Recovery OTP

Local SMS OTP is configured in `supabase/config.toml` through `auth.sms.test_otp`. The local-only test OTP is:

```text
123456
```

Hosted staging/production does not use this local OTP fixture. Configure a real SMS provider in the Supabase Dashboard for real phone OTP delivery.
