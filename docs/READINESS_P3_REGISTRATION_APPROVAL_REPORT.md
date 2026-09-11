# Readiness P3 - Registration approval UI

Date: 2026-09-11

## Completed

- Added a P3 migration that extends `worker_profile_detail` with the new registration review fields:
  - `registration_type`
  - `requested_category`
  - `id_card_file_path`
  - `experience_level`
- Added worker domain parsing and labels for pending/rejected statuses, registration type, requested category, experience level, ID-card path, and complete-years age display.
- Added repository support for:
  - creating signed URLs for private worker ID-card files
  - calling `review_worker_registration` for approval/rejection
- Updated the worker directory with a `Pending approvals` shortcut and richer row text for new/old worker + requested category.
- Updated worker detail with a registration review card showing the submitted fields and an `Open ID card` action.
- Added approve/reject actions for captains, supervisors, admins, and super admins. Approvals choose the final category and rejections require a reason.
- Added a widget test covering the pending registration detail screen and approval RPC call.

## Validation

Passed:

- `flutter analyze`
- `flutter test test/worker_management_test.dart`
- `flutter test`
- `npx supabase db reset`

Database test result:

- `npx supabase test db` still fails only in the older `readiness_r1_permissions_event_states.sql` erasure-permission checks. The P1 phone-registration database test and the new P3 migration chain pass.

## Hosted staging

- The P3 migration is local only at this point. Run `npx supabase db push --project-ref vrpxpidnbhnuismbzroe` when approval is given to apply it to hosted staging.

## Outstanding

- P4 should harden the final worker restrictions and verify pending/rejected workers cannot receive work or event notifications.
- Build a new staging APK only after the hosted P3 migration is pushed.
