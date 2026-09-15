# UI refresh — 12 September 2026

## Findings and changes

- Default-looking controls and weak hierarchy: added a shared blue/teal palette, stronger headings, pale page backgrounds, white bordered cards, rounded inputs, and consistent button sizing. Dialogs, navigation, lists and snackbars inherit the theme.
- Login lacked a clear introduction: added a branded welcome panel, concise instructions and accessible error announcements.
- Registration was one long undifferentiated form: grouped it into personal details, work profile, and account/documents. Explained approval before work access and document uploads. Kept new/old worker selection and old-only category selection. Fixed dropdown overflow at larger text sizes.
- Event and edit-profile fields touched each other: added spacing and keyboard dismissal on drag. Event creation now has an introductory heading.
- Home used identical primary buttons: replaced them with descriptive shortcuts and a role-specific welcome panel. Worker summaries now distinguish missing/loading data from an empty work history.
- Worker event cards compressed title, location, time, wage and status into a tile: separated these into a vertical layout with wrapping metadata and clear event links. Empty lists can be refreshed and failures offer retry.
- Admin event cards also squeezed status beside long text: moved statuses above the title and separated location, reporting time and wage.

## Files

- `lib/app/theme/app_theme.dart`
- `lib/core/widgets/app_section_heading.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/presentation/worker_registration_screen.dart`
- `lib/features/events/presentation/admin_event_form_screen.dart`
- `lib/features/events/presentation/admin_event_list_screen.dart`
- `lib/features/events/presentation/worker_event_list_screen.dart`
- `lib/features/shell/presentation/role_home_screen.dart`
- `lib/features/workers/presentation/edit_worker_profile_screen.dart`
- `test/app_router_test.dart`
- `test/ui_layout_test.dart`

## Validation

- Flutter analysis passed.
- Full Flutter suite passed: 107 tests.
- Added layout coverage for narrow screens with large text, login scrolling with a simulated keyboard, registration category visibility and long event metadata.
- Rendered and inspected the login layout using a local Flutter widget-test preview. This is not a physical-device screenshot.
- No database migrations or business-rule changes.

## Release boundary and remaining review

These are local source changes, not a deployed APK. Build and install an updated staging APK to review native keyboard behavior, file pickers and full role flows on real phones. The shared theme reaches other screens, but attendance, reports, worker management and event-detail screens have not each received a bespoke layout redesign or device visual review in this pass. Existing behavior and authorization are preserved.
