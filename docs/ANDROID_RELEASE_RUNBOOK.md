# Android Release Runbook

## Scope

Phase 17 prepares the Android release path without checking signing keys, service-role credentials, Firebase service-account credentials, or database passwords into Git. Production launch still requires explicit approval.

## Release Identity

| Item | Value |
|---|---|
| Android application ID | `com.oslavaevents.oslava_events` |
| Display name | `Oslava Events` |
| Version source | `pubspec.yaml` `version` |
| Firebase Android app | Must use package `com.oslavaevents.oslava_events` |

## Required Local Signing Setup

Create an upload keystore outside the repository, then copy `android/key.properties.example` to `android/key.properties` and fill in local values.

`android/key.properties`, `*.jks`, and `*.keystore` are ignored by Git. Do not store them in the repo, Flutter code, Supabase functions, or CI logs.

Example generation command:

```powershell
keytool -genkeypair -v -keystore C:\Users\hp\keystores\oslava-events-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias oslava-events-upload
```

## CI Secrets

For CI release builds, store these as protected repository secrets:

| Secret | Purpose |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Base64-encoded upload keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Upload-key alias |
| `ANDROID_KEY_PASSWORD` | Upload-key password |
| `SUPABASE_URL` | Production Supabase project URL |
| `SUPABASE_ANON_KEY` | Production Supabase publishable/anon key |

Never add Supabase service-role keys, database passwords, FCM server credentials, or Firebase service-account JSON to Flutter.

## Build

```powershell
flutter pub get
flutter analyze
flutter test -j 1
flutter build appbundle --release --dart-define=OSLAVA_ENV=production --dart-define=SUPABASE_URL=<production-url> --dart-define=SUPABASE_ANON_KEY=<production-anon-key>
```

The Gradle build intentionally fails release tasks until signing is configured through `android/key.properties` or CI secrets.

## Manual Play Console Checklist

- Create the Play app and select internal testing first.
- Confirm package name `com.oslavaevents.oslava_events`.
- Upload the signed AAB.
- Complete Data Safety disclosures for phone/password authentication, profile details, private profile photos, event participation, attendance, reviews, reliability scoring, notifications, and retention/erasure processes.
- Link to the current Privacy Notice and Terms.
- Confirm Android notification permission copy and device/OS permission behavior.
- Run the Play pre-launch report and fix any crashes, blocked permissions, or policy warnings.
- Smoke test login, role routing, profile photo upload, event discovery, booking/waitlist, attendance, reviews, notifications, reports, and logout/account switching with production-safe test accounts.

## Rollback

- Keep the previous accepted AAB available in Play Console.
- Use staged rollout for the first production release.
- If a critical issue appears, halt rollout or roll back to the prior release from Play Console.
- If a backend migration issue appears, follow `BACKUP_RESTORE_RUNBOOK.md` and prefer forward-fix migrations unless restore is explicitly approved.

## Release Gate

Phase 17 local readiness can pass without exposing secrets. Full completion requires:

- signed AAB built with the real upload key
- Play internal testing pass
- production RLS smoke test with production-safe test accounts
- production backup/restore launch dependencies accepted or completed
- explicit production launch approval
