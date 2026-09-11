# Android tester handoff — R10 draft

Generated: 10 September 2026.

## Current artifact

A signed hosted-staging release APK is available for colleague testing after one physical-device smoke test:

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- Size: 64,327,395 bytes
- SHA-256: `2370bae0b2ee492a95e5645cab3741b0a47d382a966029c4696a83492851b622`
- App environment: `staging`
- Package: `com.oslavaevents.oslava_events`
- Signing verifier: Android APK Signature Scheme v2 verified
- Signer certificate SHA-256: `961350f2477698363107f8fa4ea26a5740a6b7641acade7ab00b9452c23c9b17`

This artifact points at hosted staging Supabase: `https://vrpxpidnbhnuismbzroe.supabase.co`. This exact APK was installed and launched on a Motorola edge 50 pro. It reached the Login screen. Before broad testing, verify at least one staging login/account flow with a real test account.

## Build a hosted staging APK for colleagues

Set the hosted staging public values first:

```powershell
$env:SUPABASE_URL = 'https://your-staging-project.supabase.co'
$env:SUPABASE_ANON_KEY = 'your-public-anon-or-publishable-key'
powershell -ExecutionPolicy Bypass -File scripts/build_staging_apk.ps1
```

The script removes any stale APK, builds release with `OSLAVA_ENV=staging`, then prints size and SHA-256.

## Local USB smoke test steps

1. Start local Supabase: `npx supabase start`.
2. Connect Android with USB debugging enabled.
3. Run: `flutter devices` and confirm the phone appears.
4. Run: `powershell -ExecutionPolicy Bypass -File scripts/setup_android_usb_reverse.ps1`.
5. Install the APK: `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
6. Test login/registration, Worker event board, Apply/waitlist/cancel, Admin event creation, attendance, reports, alerts, and Profile → Privacy and deletion.

## Tester focus

Ask testers to record device model, Android version, role/account used, exact action, expected result, actual result, screenshot/video when possible, network state and timestamp.

Priority scenarios:

- Fresh install and login/logout.
- Worker registration with photo and privacy acknowledgement.
- Worker event discovery, Apply, pending result, confirmed result, waitlist join/withdrawal and cancellation boundary.
- Admin event creation/edit/publish/cancel/complete/close.
- Captain/Supervisor roster, attendance and review entry.
- Notifications/alerts screen, unread badge and deep links.
- Profile edits, photo replacement and deletion request submission.
- Small screen/keyboard, large text, Back navigation, airplane-mode retry.

## Known gates before broad colleague testing

- Hosted staging migrations/config/SMS/FCM/jobs must be applied and smoke-tested.
- A physical Android device was not connected during this R10 run, so install/open testing was not completed by Codex.
- Real privacy/support contact and hosted account-deletion URL are still required before store submission.

## Hosted staging login finding - 2026-09-10 19:48 IST

A physical-device login attempt reached hosted Supabase but failed because the hosted Auth API returns `phone_provider_disabled` / `Phone logins are disabled` for phone-password auth. This is a Supabase project setting, not an APK connectivity failure.

Action needed before tester login works: enable Phone provider/login in the hosted Supabase project Auth settings and confirm SMS/Twilio configuration for staging. After that, test with a real registered staging worker account.

The APK has been rebuilt and reinstalled after improving the login error copy for this backend configuration problem.

- APK: `A:\Dev\oslava_events\build\app\outputs\flutter-apk\app-release.apk`
- Size: 64994479 bytes
- SHA-256: `b297546a5b0a9f145b3735528c06e75f34a74d937912cb0fd4d608f6693e1054`
