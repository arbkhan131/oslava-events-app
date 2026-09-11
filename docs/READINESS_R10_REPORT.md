# Readiness R10 report — Android staging test release

Status: hosted staging APK produced; physical-device smoke test still pending because no Android phone was detected.

Completed local work on 10 September 2026.

## What changed

- Resolved the `README.md` merge conflict and replaced the starter text with project/build guidance.
- Added Android signing-secret ignores for `android/key.properties`, `*.jks` and `*.keystore`.
- Hardened `scripts/build_staging_apk.ps1` so it removes stale output, fails on missing `SUPABASE_ANON_KEY`, fails on missing APK output and prints artifact size/SHA-256 after a successful staging build.
- Added `docs/ANDROID_TESTER_HANDOFF_R10.md` with local USB smoke-test steps, staging rebuild command, tester focus areas and known gates.

## Artifact produced

A signed hosted-staging release APK was produced:

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- Size: 64,327,395 bytes
- SHA-256: `2370bae0b2ee492a95e5645cab3741b0a47d382a966029c4696a83492851b622`
- Build command: `powershell -ExecutionPolicy Bypass -File scripts/build_staging_apk.ps1`
- Signature verification: PASS via Android build-tools `apksigner`; v2 signature verified.

## Verification

- `flutter analyze --no-pub` — PASS.
- `flutter test --no-pub` — PASS, 100 tests.
- `npx supabase test db` — PASS, 20 files / 587 assertions.
- `powershell -ExecutionPolicy Bypass -File scripts/build_staging_apk.ps1` — PASS after staging public key was supplied.
- `flutter build apk --release --dart-define=OSLAVA_ENV=local` — PASS.
- `apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk` — PASS.
- `flutter devices` — no Android phone detected; only Windows/Chrome/Edge were available.

## Outstanding R10 gates

- Hosted staging APK cannot be built until `SUPABASE_ANON_KEY` is supplied in the shell for the staging project.
- Hosted staging parity for migrations/RLS/private Storage/Auth/SMS/jobs/FCM was not verified because remote deployment/configuration was not authorized or available in this run.
- Physical Android install/open smoke test completed on Motorola edge 50 pro. Install succeeded with `adb install -r`; launch reached the Login screen with no fatal startup crash in filtered logs. Login/authenticated-flow smoke remains pending unless staging test credentials are supplied.
- Representative load/device/accessibility matrix remains pending after a hosted staging APK and device are available.

## Recommendation

Use the current APK only for your own USB/local Supabase smoke test. For colleagues, rebuild with hosted staging values and verify that exact APK on one physical Android device before sharing.



## Physical Android smoke update

- Device: Motorola edge 50 pro, Android 16 (API 36), id `ZD222PNK3D`.
- Install command: Android SDK `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
- Install result: PASS.
- Launch command: `monkey -p com.oslavaevents.oslava_events -c android.intent.category.LAUNCHER 1`.
- Launch result: PASS; app focused `com.oslavaevents.oslava_events/.MainActivity` and rendered the Login screen.
- Screenshot evidence: `build/app/outputs/flutter-apk/r10_staging_smoke_2.png`.
- Filtered startup log check: no Oslava/Flutter fatal exception captured.
- Pending: login and authenticated role-flow smoke test require a staging test account phone/password.

## Hosted staging login finding - 2026-09-10 19:48 IST

A physical-device login attempt reached hosted Supabase but failed because the hosted Auth API returns `phone_provider_disabled` / `Phone logins are disabled` for phone-password auth. This is a Supabase project setting, not an APK connectivity failure.

Action needed before tester login works: enable Phone provider/login in the hosted Supabase project Auth settings and confirm SMS/Twilio configuration for staging. After that, test with a real registered staging worker account.

The APK has been rebuilt and reinstalled after improving the login error copy for this backend configuration problem.

- APK: `A:\Dev\oslava_events\build\app\outputs\flutter-apk\app-release.apk`
- Size: 64994479 bytes
- SHA-256: `b297546a5b0a9f145b3735528c06e75f34a74d937912cb0fd4d608f6693e1054`
