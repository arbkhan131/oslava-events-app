# Oslava Events

Oslava Events is a Flutter application backed by Supabase for worker registration, event staffing, booking, field attendance, reports, notifications, privacy controls and Android/iOS release preparation.

## Local development

Use the local Supabase stack for development unless you are preparing a hosted staging build.

```powershell
npx supabase start
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
npx supabase test db
```

Android local-device testing is documented in `docs/ANDROID_LOCAL_DEVICE_TESTING.md`.

## Android staging APK

Release signing is read from `android/key.properties`. Keep the keystore and `android/key.properties` outside Git history. Copy `android/key.properties.example` only as a template.

To build a hosted staging APK, set the public Supabase values and run:

```powershell
$env:SUPABASE_URL = 'https://your-staging-project.supabase.co'
$env:SUPABASE_ANON_KEY = 'your-public-anon-or-publishable-key'
powershell -ExecutionPolicy Bypass -File scripts/build_staging_apk.ps1
```

The generated APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
