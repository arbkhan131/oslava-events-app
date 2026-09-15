# UI/UX polish — 13 September 2026

This pass builds on the existing UI refresh and the local registration fixes. It focuses on clear account states, usable forms, and small-screen layouts. It does not change roles, approval rules, booking eligibility, or Supabase configuration.

## Improvements

- Pending approval now shows a welcoming receipt, review steps, and a specific check-status action. Restricted and failed account checks keep their distinct messages.
- Registration documents have individual upload cards, selected filenames, a rounded photo preview, and an explicit replacement affordance. Missing profile details and invalid heights receive readable guidance before submission. Selecting a file no longer leaves a success message in the submission-error area.
- Login distinguishes the primary sign-in action from worker registration and presents errors in an accessible notice panel. Submission dismisses the keyboard.
- Staff creation has separated fields, explanatory text, password visibility, and an expanding role dropdown. The phone-change dialog scrolls above the keyboard.
- The worker directory scrolls as one page, including expanded team accounts. Filters follow the selected query, empty results offer a reset, worker rows use cards, and pagination wraps on small screens.
- Alerts have distinct read/unread styling, helpful empty/error states and retry, readable notification setup messages, and handled open failures. Refresh waits for the request on populated lists.
- My Work tabs scroll at larger text sizes and empty work lists link to events. Navigation uses role-appropriate worker/team icons and selected states.
- Shared surfaces use white dialogs, consistent dividers, and reusable feedback/upload components.

## Changed source files in this pass

- `lib/app/theme/app_theme.dart`
- `lib/core/widgets/app_feedback.dart`
- `lib/core/widgets/document_upload_card.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/presentation/worker_registration_screen.dart`
- `lib/features/auth/presentation/session_status_screen.dart`
- `lib/features/workers/presentation/worker_directory_screen.dart`
- `lib/features/notifications/presentation/alerts_screen.dart`
- `lib/features/events/presentation/worker_my_work_screen.dart`
- `lib/features/shell/presentation/role_navigation_shell.dart`
- `test/ui_layout_test.dart`

## Validation and release boundary

- Flutter analysis: passed.
- Full Flutter suite: 110 tests passed.
- Added checks for pending approval at large text size, staff creation with an open keyboard, and readable alert failures. Existing login, registration category, event layout, route, authentication, and worker-management tests also pass.
- An optional widget render produces `build/ui-review/pending.png`; this is a simulated Flutter screen, not an Android device capture.
- Changes are local source only. No APK was rebuilt or installed, and no Git push or backend deployment was performed in this pass.
- Native file pickers, real notification permission prompts, and live registration/approval still need verification on the next staging APK. This UI work does not resolve the previously reported Supabase management-access restriction.

## Follow-up polish

- Worker event details now lead with a branded title/venue/status panel. Schedule and staffing values stack beneath their labels, avoiding narrow fixed-width columns. The venue URL has an Open venue map action with a readable failure message; only HTTP(S) links are launched.
- Confirmed work and waitlist entries use cards with clearly separated status, venue, reporting time, deadlines or queue position, and labeled actions. Empty waitlists explain what will appear there.
- Cancellation and withdrawal confirmation forms explain the consequence, scroll above the keyboard, and require a reason without closing the dialog prematurely. Backend authorization and cancellation limits remain authoritative.
- Sign-out moved to the top of Home, removing the extra sign-out row above bottom navigation on every screen. Existing logout behavior and session cleanup are retained.
- Additional files: `worker_event_detail_screen.dart`, `worker_my_work_screen.dart`, `role_home_screen.dart`, `role_navigation_shell.dart`, and new `auth/presentation/sign_out_button.dart` under their corresponding feature presentation directories. Layout tests cover narrow work cards and cancellation confirmation validation.
- Visually inspected `build/ui-review/my-work.png`, rendered using Flutter with actual text and icon fonts. This is a simulated screen with sample data, not a live account or physical-device capture.
- Follow-up validation: Flutter analysis passed and all 111 tests passed, including logout/session regression coverage. Native map launching still needs checking on an Android device; no updated APK was built during this pass.
