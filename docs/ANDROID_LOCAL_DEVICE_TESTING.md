# Android Local Device Testing

## Why Login Timed Out

`10.0.2.2` is an Android emulator-only address for the host computer. A real USB-connected phone cannot use it to reach local Supabase on the PC.

For physical-device local testing, the app uses:

```text
http://127.0.0.1:55321
```

and Android Debug Bridge forwards that phone-local port to the PC-local Supabase API.

## Setup

1. Start local Supabase:

```powershell
npx supabase start
```

2. Connect the phone with USB debugging enabled.

3. Accept the USB debugging authorization prompt on the phone.

4. Configure port forwarding:

```powershell
.\scripts\setup_android_usb_reverse.ps1
```

5. Install the local release APK:

```text
A:\Dev\oslava_events\build\app\outputs\flutter-apk\app-release.apk
```

## Local Credentials

After `npx supabase db reset`, use the local development credentials in `docs/LOCAL_DEVELOPMENT_ACCOUNTS.md`.

For the local-only Super Admin test account, use:

```text
+918864938636
```

with the local-only password from `docs/LOCAL_DEVELOPMENT_ACCOUNTS.md`.

Do not use the old temporary fixture phone:

```text
+919000000001
```

Temporary Admin, Captain, Supervisor, and Worker accounts are no longer seeded.

## Emulator Option

The emulator can also use this same `127.0.0.1:55321` setup if `adb reverse tcp:55321 tcp:55321` is active. If you specifically want the emulator-only host alias, build with:

```powershell
flutter build apk --release --dart-define=OSLAVA_ENV=local --dart-define=SUPABASE_URL=http://10.0.2.2:55321
```
