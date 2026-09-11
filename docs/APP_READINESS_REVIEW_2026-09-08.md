# Oslava Events: app readiness review

Review date: 8 September 2026. Scope: current working copy, including existing uncommitted changes. This is an assessment, not a feature implementation or release approval.

Implementation update, 9 September 2026: **R1 has fixed issue groups 1 and 3 locally**, including privileged-target/last-Super-Admin protection, terminal assignments and reliability reconciliation. See the [R1 completion report](A:/Dev/oslava_events/docs/READINESS_R1_REPORT.md) for tests and limits. The original review below is retained as the baseline; the remaining phases and hosted validation are still outstanding.

R2 update, 9 September 2026: **Issue group 2 is fixed locally.** Committed final-seat intake, one-second category arbitration, per-request consent, safe retries, pending client handling and second-level recovery passed independent-connection tests. See the [R2 completion report](A:/Dev/oslava_events/docs/READINESS_R2_REPORT.md). Hosted/load validation and R3–R11 remain outstanding.

## Decision

**The application has substantial backend implementation and a working Android packaging path, but it is not ready for colleagues to test the complete operational workflow.** Fix the security and business-state bugs and connect the essential screens first. A supervised demonstration using synthetic data is possible; an unattended acceptance test would encounter blocked navigation, incomplete onboarding, and misleading booking states.

The Flutter application is still a functional prototype in several areas. The main remaining work is more than visual polish: backend capabilities need complete user flows, and several important backend integration rules need correction.

Do not equate a successful APK build or passing existing tests with release readiness. An existing signed release APK was found and verified, but no new APK was built or distributed in this review.

## What was examined and verified

- Read the product blueprint, finalized decision register, UI screen map, architecture/security/backend documents, phase plan, and release/privacy/operational runbooks. The later finalized decisions were used for phone/password login, Admin-only detention, and separate lifecycle/recruitment states where the original PDF is older.
- Inspected Flutter routing, authentication, registration/recovery, role homes, worker management, events, booking/waitlist, attendance, reviews, notifications, reports, and their repository/model contracts.
- Inspected the versioned SQL migrations and acceptance tests, with additional probes around authorization, final-seat arbitration, and event terminal states.
- Viewed the running Flutter web login and registration at desktop and 360 x 640 phone-sized viewports. Other screen assessments are based on source and widget probes, not a claim of physical-device visual coverage.
- Executed `flutter analyze`: **PASS**, no issues.
- Executed `flutter test`: **PASS**, 67 tests. The PDF tests emit warnings about Helvetica lacking Unicode support.
- Executed `npx supabase db lint --local`: **PASS**, no schema errors.
- Executed `npx supabase test db`: **PASS**, 16 files, 452 assertions. The first invocation encountered a CLI telemetry-file rename collision while another CLI command ran; a sequential retry passed.
- Executed two additional diagnostic widget probes: both reproduced the expected defects, namely missing return navigation/empty-state refresh and login keyboard overflow. These are evidence probes that assert the current broken behavior, not regression tests establishing correctness.
- Executed additional SQL probes using synthetic fixtures in a disposable local database. The schema was copied without owners; Supabase-managed ACL restoration produced warnings. The arbitration and privileged-erasure calls ran as `authenticated` with synthetic JWT identities. These probes establish the specific application-function bugs; they are not a complete hosted RLS certification.
- The active local database has all 15 application migrations, zero public tables without RLS, and zero public security-definer functions without an explicit search path. These are useful structural checks, not proof that every authorization predicate is correct.

Not verified: hosted staging migration/configuration parity; real SMS delivery; actual FCM delivery; physical Android install/navigation/background behavior; iOS build or devices; store-console configuration; production restore; sustained load at the blueprint's approximately 2,000-worker scale. No Android phone was connected according to `flutter devices`.

The older hardening report says 461 database assertions and 66 Flutter tests. The current measured counts are 452 and 67; its earlier completion claims must not substitute for current acceptance evidence.

## Feature coverage

| Area | Implemented | Still incomplete or incorrect |
|---|---|---|
| Authentication | Phone/password repository, role routing, persisted Supabase session, recovery screen | No logout UI, registration does not enter the app, recovery completion is disconnected from app session, no auth-event subscription |
| Worker registration | Personal fields, DOB picker, photo picker/compression, F/ACTIVE defaults, backend age check, consent record | No resumable partial signup, no registration SMS verification step if hosted Auth requires one, no readable Terms/Privacy link, hardcoded terms version |
| Role home/navigation | Five role namespaces and feature shortcuts | Placeholder home, no required bottom navigation/dashboard, flat navigation loses return path |
| Worker management | Directory, detail/history, personal edits, detention/release, one-step category changes | Team/staff creation and role controls, phone reassignment UI, actual profile-photo display/replacement, directory filters/pagination |
| Event management | Draft creation, tier presets/custom offsets, publish/cancel/complete/close RPCs and basic buttons | Date/time input, editing, leaders, requirements, allowances, conflict resolution/removal, full staffing dashboard/calendar |
| Booking | Server-side capacity, eligibility/conflict predicates, typed results, requirement enforcement | Final-seat priority is wrong under real concurrent requests; UI cannot acknowledge requirements or late-booking rules |
| Waitlist/cancellation | Explicit join RPC, backend withdrawal/refill/cancellation | No withdrawal UI or waitlist tab, incomplete deadline presentation, weak error/retry behavior |
| Attendance/reviews | Assigned-event roster, search/counters, four attendance states, review entry, audited category action | No leader-assignment UI to establish field access, no realtime refresh, limited review editing context/photo identification |
| Reliability | Versioned calculations, provisional state, raw metrics, profile display | Event completion does not resolve assignments, undermining completed-work metrics; real operational reconciliation still needed |
| Notifications | In-app alerts, device-token registration, outbox/retry records, dispatcher source | No scheduled job wiring in repo/local DB, no push-open handling, abandoned claims cannot retry, hosted delivery unverified |
| Reports | Event staffing report, copyable summary, PDF generator, limited history | Global reports/audit screens, broader filters and pagination, Unicode/local-language PDF font support |
| Privacy/operations | Consent records, erasure-request ledger, partial retention cleanup, runbooks | Erasure authorization bug, no user deletion request path or fulfillment worker, no verified production restore |
| Android/iOS | Android identity/icons/signing configuration, existing signed APK, iOS project/Firebase options | Exact staging artifact provenance/device pass; iOS permissions, APNs/signing and release verification |

## Must fix before a full colleague test

### 1. Admin can deactivate Super Admin through the erasure RPC — high severity

`request_account_erasure` checks that the actor can manage events, then sets any target profile INACTIVE. It does not enforce privileged-target boundaries. An authenticated synthetic Admin successfully deactivated a synthetic Super Admin in the probe. This bypasses the restrictions in the normal role-management flow and can lock out the owner account.

Fix: apply the approved role-target permissions to erasure, protect the last active Super Admin, and add explicit denial tests for Admin-to-Admin/Super-Admin targets. Preserve the controlled identity-verification process.

Evidence: [erasure RPC](A:/Dev/oslava_events/supabase/migrations/20260907010100_phase_16_hardening.sql:326). Probe result: `SUPER_ADMIN status: INACTIVE`; rolled back.

### 2. Final-seat category priority fails with real simultaneous calls — high severity

`apply_for_event` locks the event before adding its request to an arbitration window. It holds that lock while the allocator sleeps. Another caller cannot join the same window through the public RPC before the first transaction allocates and commits.

Reproduction: one vacancy, eligible F and A workers. Start F; observe F inside the one-second sleep; start A. The server receipt timestamps were **0.719249 seconds apart**. F returned CONFIRMED and A returned WAITLIST_AVAILABLE. The required result was A winning this shared arbitration window. Capacity stayed at one; this is a priority/fairness bug rather than reproduced overbooking.

Fix: separate durable request intake from allocation so contenders can commit into the window, store each request's own acknowledgements, then lock/revalidate/allocate after the window closes. Use real multi-connection tests for both category priority and same-category ordering. The existing test manually inserts contenders and therefore misses the public-RPC locking problem.

Evidence: [event lock](A:/Dev/oslava_events/supabase/migrations/20260905050100_phase_9_atomic_booking.sql:505), [allocator wait](A:/Dev/oslava_events/supabase/migrations/20260905050100_phase_9_atomic_booking.sql:328), [allocator invocation](A:/Dev/oslava_events/supabase/migrations/20260905050100_phase_9_atomic_booking.sql:588).

### 3. Cancelled and closed events leave workers Confirmed — high severity

Event cancellation/completion/closure update the event, but do not reconcile assignment states. The worker board checks for an existing confirmed assignment before checking cancellation. My Work reads the assignment status directly.

Reproduced results:

| Action | Event | Assignment | Worker-facing result |
|---|---|---|---|
| Cancel an event with a confirmed worker | CANCELLED | CONFIRMED | Board and My Work both say CONFIRMED |
| Complete and close an event | CLOSED | CONFIRMED | Assignment remains in confirmed work |

This can send workers to cancelled work and prevent work from reaching the Completed tab. Reliability also counts completed assignment rows, so its completed-event metric cannot reconcile to normal event closure.

Fix: implement approved, audited assignment/waitlist/notification handling for terminal event transitions. Management cancellation must remain distinguishable from worker cancellation and must not unfairly penalize worker reliability. Add an end-to-end publish → book → attend → complete → close test and a cancellation test starting with real assignments/waitlist entries.

Evidence: [event transitions](A:/Dev/oslava_events/supabase/migrations/20260905010100_phase_5_event_management.sql:625), [worker board precedence](A:/Dev/oslava_events/supabase/migrations/20260905060100_phase_10_cancellation_waitlist.sql:856), [My Work projection](A:/Dev/oslava_events/supabase/migrations/20260905060100_phase_10_cancellation_waitlist.sql:719).

### 4. Navigation traps users inside screens

Feature screens are top-level sibling routes and navigation uses `context.go`. Moving from Home to Events replaces Home instead of retaining it below the new screen. There is no bottom navigation or explicit Home action. The widget probe confirmed `router.canPop() == false`, no Back button, and no navigation bar after Home → Events. Registration similarly has no visible return-to-login control.

Fix: implement the planned role navigation shell and appropriate detail-page push/nested routes. Verify Android system Back, app-bar Back, tab switching, and deep-link entry for every role.

Evidence: [router](A:/Dev/oslava_events/lib/app/router/app_router.dart), [home shortcuts](A:/Dev/oslava_events/lib/features/shell/presentation/role_home_screen.dart:31).

### 5. Registration, logout, and session recovery are incomplete

The registration repository returns an AppSession, but the screen discards it and shows “Registration submitted.” It neither updates the app session nor navigates to Worker Home. There is no logout button anywhere, even though `signOut()` exists in the repository. Password reset verifies the OTP and changes the password but leaves the user in the recovery form.

Signup, image preparation/upload, and profile completion are separate steps. A photo error, network loss, or profile rejection after Auth signup can leave an Auth account without a usable profile; retry starts another signup rather than resuming. If hosted phone confirmation is enabled, the code has no signup OTP screen before the authenticated Storage upload.

Fix: explicit onboarding states, resumable completion, success navigation, logout for every role, recovery completion, and tests for interrupted signup. Configure and test the intended hosted phone-auth behavior. Reset user-scoped providers and invalidate notification tokens while the outgoing user's session is still available.

Evidence: [registration success](A:/Dev/oslava_events/lib/features/auth/presentation/worker_registration_screen.dart:144), [auth repository](A:/Dev/oslava_events/lib/features/auth/data/auth_repository.dart:69), [app session](A:/Dev/oslava_events/lib/features/auth/application/auth_session.dart).

### 6. Event creation silently chooses dates and times

The form has no event date, reporting time, start time, or expected end controls. Saving chooses seven days from now, reporting at 09:00 UTC (**2:30 PM India time**), starting one hour later, and ending nine hours after reporting. An Admin cannot schedule the real event they intend to create.

The screen/repository also omit event editing, leader selection, structured requirements/allowances, and management conflict/removal flows even though corresponding backend concepts exist.

Fix: complete the event form with India-time input and backend validation; connect edit/version handling, leader assignments and operational management. This is essential for colleague testing of field roles.

Evidence: [fixed scheduling](A:/Dev/oslava_events/lib/features/events/presentation/admin_event_form_screen.dart:270), [repository surface](A:/Dev/oslava_events/lib/features/events/data/event_repository.dart).

### 7. Team management cannot be done through the app

No Team/Admin-accounts routes, staff creation screen, role change UI, or phone reassignment UI exist. The staging runbook instructs Super Admin to create Admins and Admin to create field leaders through the app, but those flows are absent. Merely exposing the existing profile-provisioning RPC is insufficient: staff Auth-account creation must be handled through a trusted server flow without replacing the current Admin session.

Fix: implement the approved staff lifecycle. For a narrowly scoped early test, pre-provision synthetic role accounts and leader assignments in staging and explicitly document that this does not test in-app team management.

Evidence: [route inventory](A:/Dev/oslava_events/lib/app/router/app_router.dart), [staging instructions](A:/Dev/oslava_events/docs/STAGING_TESTER_SETUP.md).

### 8. Apply cannot satisfy required acknowledgements

Worker detail never presents requirement checkboxes or a late-cancellation warning. Apply calls the repository with its defaults: an empty acknowledgement list and `lateCancellationAcknowledged = false`. An event requiring acknowledgement is rejected; booking inside the final hour is also rejected with no UI path to resolve it. Waitlist joining has the same requirement-acknowledgement omission.

Fix: display backend-provided requirements, allowances, cancellation deadline and late-booking warning, then submit the user's acknowledgements. Keep eligibility and deadlines authoritative on the backend.

Evidence: [Apply/Join calls](A:/Dev/oslava_events/lib/features/events/presentation/worker_event_detail_screen.dart:118), [RPC defaults](A:/Dev/oslava_events/lib/features/events/data/event_repository.dart:95).

### 9. Waitlist withdrawal and complete My Work are missing

The backend offers `withdraw_waitlist`, but Flutter has no corresponding repository method or action. My Work has only Confirmed/Completed/Cancelled tabs, no waitlist view, and filters out REMOVED assignments entirely. It parses the cancellation deadline but does not show it; rows do not open event details or leader contacts.

Fix: add active waitlist status and withdrawal, visible cancellation deadlines, event/leader access, and accurate removed/cancelled/completed history. A worker must be able to withdraw before automatic promotion without a penalty.

Evidence: [My Work](A:/Dev/oslava_events/lib/features/events/presentation/worker_my_work_screen.dart), [assignment model](A:/Dev/oslava_events/lib/features/booking/domain/worker_assignment.dart).

### 10. Scheduled operations and reliable refresh are not wired

The repo defines lifecycle/tier/reminder functions, but contains no job registration to run them or dispatch pushes. The local database has no `pg_cron` extension installed. Hosted scheduling may have been configured externally, but was not inspected. Function definitions and tests that call them manually do not establish automatic operation.

There are no Supabase realtime subscriptions or auth-state subscriptions in Flutter. Several providers remain cached, and Apply invalidates event providers but not My Work. Most screens lack refresh/retry; even the Events and Alerts empty states omit pull-to-refresh. A newly eligible event, promoted waitlist entry, changed role, or corrected attendance can remain stale on another device.

Fix: versioned or otherwise reproducibly documented scheduler setup, monitored execution, server-timed state checks, provider invalidation, and realtime or lifecycle refresh for critical screens. Display stale/offline states honestly.

Evidence: [notification migration](A:/Dev/oslava_events/supabase/migrations/20260906010100_phase_14_notifications.sql), [app lifecycle](A:/Dev/oslava_events/lib/app/app.dart), [worker events](A:/Dev/oslava_events/lib/features/events/presentation/worker_event_list_screen.dart).

### 11. Mutations have weak failure and retry UX

Apply/Join have no in-flight state or exception handling and generate a new timestamp key for every tap. Cancellation, publish, event save and profile save also have incomplete error handling. Raw backend exception text is displayed on many screens. A failed request can appear to do nothing, and double taps can send multiple logical operations. Server constraints help protect data but do not give the user a reliable outcome.

Fix: disable duplicate submissions, retain one idempotency key across retries of an operation, show clear pending/success/denied/network states, and refresh all affected views after a committed mutation. Test connection loss after server commit.

### 12. Notification retries can become permanently stuck

The dispatcher claims a batch, then uses `fetch` without a per-delivery catch or timeout. A network exception or process termination leaves claimed deliveries in CLAIMED. The claim RPC selects only PENDING/FAILED and has no expired-claim recovery. This can strand the entire unfinished batch.

It reads one `FCM_AUTHORIZATION` value from the environment. If the endpoint is Google's HTTP v1 API, a static access token needs automatic renewal; if an external authenticated proxy handles renewal, that dependency must be explicit and tested. Google's API uses short-lived OAuth tokens. [Firebase authorization documentation](https://firebase.google.com/docs/cloud-messaging/send/v1-api).

Flutter registers tokens but has no `getInitialMessage`/`onMessageOpenedApp` handling for opening the relevant screen from a push. Foreground message handling is also absent. These are distinct from tapping an in-app alert. [Firebase Flutter message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

Fix: claim leases, safe retries, per-delivery exception handling, renewable credentials/proxy contract, scheduler integration, and background/terminated/foreground device tests.

Evidence: [dispatcher](A:/Dev/oslava_events/supabase/functions/dispatch-notifications/index.ts:22), [claim selection](A:/Dev/oslava_events/supabase/migrations/20260906010100_phase_14_notifications.sql:367).

## UI and UX changes

The current Material theme is a reasonable foundation. The priority is to provide context and usable navigation before investing in animation or decorative redesign.

| Screen/area | Recommended change |
|---|---|
| Login/recovery | Scroll-safe form, keyboard actions, password visibility toggle, clear field validation, recovery resend/change-number/success path |
| Registration | Group personal/contact/work details; show selected-photo preview and upload progress; inline field errors; preserve inputs after recoverable errors; readable Privacy/Terms |
| Worker Home | Next confirmed event, reporting time, venue, cancellation deadline, current category, and relevant alerts |
| Worker Events | Clear Available/Locked/Full/Confirmed states, open-tier explanation, vacancy/wage/time hierarchy, useful empty states and refresh |
| Worker event detail | Requirements/allowances, clickable Maps, leaders where access permits, confirmation summary and cancellation implications |
| My Work | Upcoming/Waitlisted/History, deadline, event links, visible status changes and understandable cancellation/removal reasons |
| Field Home/roster | Today's assigned events, event context, actual worker photos, clear attendance controls, full-event totals distinct from filtered totals |
| Admin Home | Today's staffing required/filled/vacant, unresolved assignment flags, event status and attendance drill-down |
| Workers | Category/account/reliability filters, debounced search and pagination; current query is capped at 50 results without a next-page control |
| Profiles | Render signed private photos, allow approved photo replacement, explain provisional reliability, expose own relevant history |
| Destructive actions | Explain impact, show affected event/worker, require the approved reason, then show committed outcome |
| Language/copy | Replace developer labels such as “Workspace shell ready,” raw enum names and Supabase/FCM setup messages with operational language |

The phone-keyboard widget probe at 360 x 640 with a 300-pixel keyboard reproduced a **108-pixel bottom overflow on Login**. Recovery uses the same unscrollable Column pattern and needs equivalent testing. Actual TalkBack/VoiceOver, large text, contrast and touch-target checks remain outstanding; they were not certified by viewing web screenshots.

The required profile photo is stored but not rendered in the directory/profile/roster screens. This directly reduces its identification value for field leaders. Server registration validates the photo path's shape, not that the referenced Storage object exists; the Apply completeness helper also accepts a nonempty path. Review this backend gap so a direct RPC caller cannot bypass the required-photo rule.

PDF export uses default Helvetica. The test suite reports missing Unicode support; add an embedded font with suitable coverage and verify Malayalam names, long names and multipage rosters before operational use.

## APK and store readiness

### Android packaging evidence

Existing artifact: `build/app/outputs/flutter-apk/app-release.apk`.

| Check | Observed |
|---|---|
| Package | `com.oslavaevents.oslava_events` |
| Version | `1.0.0`, build `1` |
| Size | 62,294,419 bytes, approximately 59.4 MiB |
| Minimum Android API | 24 |
| Target Android API | 36 |
| Signature | `apksigner verify --verbose`: verifies, v2 signature, one signer |
| Local signing config | `android/key.properties` exists; its contents were not printed |

This proves the existing artifact is a signed APK, not that it matches every current file or connects to the intended hosted environment. No APK was installed during this review. Rebuild from an approved, identifiable source milestone after fixes, record the build number/commit/environment, and verify on physical phones using mobile data as well as Wi-Fi.

Use hosted staging for colleagues. Localhost/emulator addresses and `adb reverse` are development conveniences and do not support remote testers. Verify migrations, private Storage, role accounts, Auth/SMS settings, scheduled jobs and notification secrets in that staging project before distribution. No remote migration push or hosted mutation was performed here.

The staging build script prints “Built staging APK” without checking `$LASTEXITCODE` after Flutter. Add an exit-code and output validation gate so a failed build cannot appear successful or lead to sharing an old APK.

### Before public store submission

- Provide an accessible Privacy Notice/Terms and an account-deletion initiation path. Google Play requires an in-app path and an external web resource for apps with account creation; Apple requires users to be able to initiate deletion inside the app. The present Admin-only erasure RPC, with no request UI, does not supply these paths. A controlled verification/fulfillment backend can remain, but users need a supported initiation flow. [Google Play requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en), [Apple requirements](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- Complete actual erasure fulfillment and retention operations. The present cleanup only handles notifications/deliveries/tokens/audit logs; it does not implement the promised profile/photo erasure or all operational-history retention. Setting INACTIVE alone does not remove the Auth account or prove session revocation. Resolve the documented 30-day fulfillment promise before relying on it.
- Complete store privacy/data disclosures and contact/support information, screenshots, reviewer test access, signed release provenance, and the appropriate testing tracks. No store acceptance is implied by this review.
- Verify the documented backup/PITR/Storage restore targets and perform an isolated restore rehearsal. The existing runbooks correctly list these as unverified deployment activities.
- iOS: `Info.plist` lacks `NSPhotoLibraryUsageDescription` despite the gallery picker; the plugin documents this setup requirement. Configure the used permissions, signing/provisioning and APNs capabilities, then test on a Mac/iOS device. APKs only cover Android. [image_picker platform setup](https://pub.dev/packages/image_picker).

### Repository handoff quality

The worktree already contains extensive changed and untracked application/migration/release files. The README still contains merge-conflict markers. Git tracks 759 files under `node_modules`, including platform-specific CLI dependencies. These are maintainability/reproducibility issues, not reasons to discard the existing feature work. Resolve the README, stop tracking generated dependencies in an explicitly scoped cleanup, ensure all intended source/config files are included, and mark the approved working milestone with a commit before building the tester artifact.

## Recommended next work order

Treat these as proposed bounded scopes; this review does not automatically start any of them or alter approved business rules.

1. **Backend correctness:** privileged-erasure authorization, actual concurrent final-seat arbitration, terminal-event assignment/waitlist reconciliation and reliability effects. Add tests that fail on today's implementations.
2. **Usable core flows:** role navigation, logout/session handling, resumable registration/recovery, real event date/time/edit/leader input, staff provisioning, requirement/late-booking acknowledgements and waitlist withdrawal.
3. **Operational reliability:** scheduled jobs, refresh/realtime behavior, mutation failures/retries, notification claim recovery and push deep links, profile-photo display and core accessibility.
4. **Staging test release:** verify hosted configuration, build a fresh signed staging APK, install it on physical phones, and run the matrix below with synthetic data.
5. **Store preparation:** user-facing privacy/deletion, retention fulfillment, store disclosures/assets, production operations and iOS verification.

Avoid adding payroll, automatic category changes, additional approval steps for normal applications, or changing the cancellation/conflict rules as part of these fixes. Those would expand or alter the approved scope.

## Colleague acceptance test matrix

Use separate accounts for Super Admin, Admin, Captain, Supervisor, and several workers spanning A/B/C/F. Use a one-seat test event, a requirements event, conflicting/nonconflicting events, and events near the cancellation boundary. Do not use real operational bookings while correcting the reproduced defects.

| Scenario | Pass condition |
|---|---|
| Fresh installation, restart and account switching | Correct role and data every time; logout accessible; no previous-user cached data or push routing |
| Registration and interrupted signup | Complete profile/photo leads to Worker Home; retry resumes safely; duplicate number/age/photo errors are understandable |
| Recovery | Real OTP delivery, invalid/expired code handling, resend, password change and usable return/login flow |
| Event administration | Choose actual date/times, requirements/allowances/leaders; edit safely; publish; field users see assigned events |
| Cumulative tier access | Higher categories retain access; lower categories unlock at server time; devices refresh |
| Concurrent final seat | A beats lower category in the same one-second window; same-category order is correct; exactly one confirmation |
| Conflict boundaries | Less than one-hour gap rejected; exactly one hour accepted; concurrent applications cannot bypass the rule |
| Cancellation boundary | Allowed at the cutoff, blocked after it; deadline/reason visible; no misleading UI success |
| Waitlist | Explicit join, withdrawal before promotion, eligible priority refill, restrictions/conflicts revalidated |
| Management cancellation and closure | All affected devices show correct event/assignment history; reminders stop; no unfair worker penalty |
| Detention and role changes | New applications blocked as required, assignments retained/flagged, waitlist handled, UI refreshes role/access |
| Attendance and review | Assigned leaders only; correction/close permissions correct; audit and reliability reconcile |
| Push lifecycle | Foreground, background and terminated app; allowed/denied permission; failed delivery retry; correct deep link |
| Connectivity and accessibility | Slow/no network, retry after commit, keyboard, small screen, large font, screen reader, Android Back |
| Exports | Correct staffing/attendance/pay display, Unicode names, multipage PDF and share behavior |

Record build number, role, device/Android version, steps, expected/actual result, and screenshot/video for each issue. A full rehearsal should finish without SQL intervention once the core UI is complete.

## Changes made by this review

- Added this review document.
- Created ignored diagnostic files under `.dart_tool/readiness_audit` for local evidence gathering.
- No application source, business rule, migration, remote database, or store configuration was changed. Existing user changes were preserved. No commit, deployment, APK distribution, email or colleague message was made.
