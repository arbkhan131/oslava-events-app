# SMS Provider Setup

## When This Is Required

This is required before sharing a hosted staging APK with testers who need real OTP delivery to their phones.

Local development can still use `auth.sms.test_otp` in `supabase/config.toml`; hosted staging cannot rely on that local fixture.

## Supabase Staging Steps

1. Open the Supabase Dashboard for `oslava-events-dev`.
2. Go to Authentication -> Providers.
3. Enable Phone authentication.
4. Choose and configure an SMS provider.
5. Keep OTP rate limits conservative for staging.
6. Test OTP delivery to `+918864938636`.
7. Test OTP delivery to one Worker tester phone.

Supabase's current phone-auth documentation says hosted projects enable phone auth on the Auth Providers page and also require an SMS provider. Supported providers include MessageBird, Twilio, Vonage, and community-supported TextLocal.

## Recommended Provider For India Staging

For India-based testing, prefer a provider that can handle Indian SMS delivery and compliance requirements. Supabase explicitly notes that some countries, including India, have special SMS regulations such as TRAI DLT, so verify deliverability and compliance before broad testing.

Practical recommendation:

1. Use Twilio Verify if you already have a working Twilio account and verified Indian delivery.
2. If Twilio setup blocks Indian delivery, evaluate Vonage or TextLocal with India/TRAI support.
3. Keep provider credentials only in Supabase Dashboard/provider console, never in Flutter or Git.

## Required Values

Exact fields depend on the selected provider, but expect provider-side credentials such as account ID/SID, auth token/API key, service/sender/template information, and possibly region/compliance settings.

Do not send these credentials in chat unless you intentionally want me to configure them and understand they are secrets. Prefer entering them directly in the Supabase Dashboard.

## App Behavior

The Flutter app should receive only:

- hosted Supabase URL
- public Supabase publishable/anon key

SMS provider credentials stay server-side in Supabase/Auth provider configuration.

## References

- Supabase Phone sign-in: https://supabase.com/docs/guides/auth/phone-login
