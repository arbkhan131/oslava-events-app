# Oslava Events readiness completion plan

Created: 9 September 2026.

This plan addresses the entire [readiness review](A:/Dev/oslava_events/docs/APP_READINESS_REVIEW_2026-09-08.md). It contains **11 sequential phases**, named **R1-R11** to distinguish them from the original implementation phases 0-17.

**Current authorization: R10, requested with “begin R10.” R1-R9 are complete locally; R10 produced a signed hosted staging APK after staging credentials were supplied. Physical Android smoke testing is still pending because no Android phone was detected.** Execute a phase when the user requests it, finish its defined scope, report the results, and stop before the next phase.

## Milestones and phase sequence

| Phase | Focus | Deliverable |
|---|---|---|
| R1 | Permission and event-state corrections | Protected privileged accounts; cancellation/completion/closure produce correct assignment/history/reliability states |
| R2 | Concurrent booking correctness | Real one-second category arbitration with safe retries and no capacity/conflict bypass |
| R3 | Navigation, authentication and session lifecycle | Usable role navigation, registration/recovery, logout and safe account switching |
| R4 | Team, worker directory and profiles | Staff management, searchable workforce, private photos and complete profile/history access |
| R5 | Admin event management | Real scheduling, editing, leaders, requirements, allowances and operational resolution controls |
| R6 | Worker event and work journeys | Complete discovery, Apply, waitlist withdrawal, cancellation, My Work and Worker Home |
| R7 | Field operations and reports | Practical attendance/review workflow, field dashboard, accurate reports and readable PDF exports |
| R8 | Scheduled operations and notifications | Automatic jobs, recoverable push delivery, deep links and verified cross-device refresh |
| R9 | Privacy, deletion and retention | Readable policies, user request paths and controlled, tested erasure/retention fulfillment |
| R10 | Android staging test release | Verified hosted staging, physical-device acceptance and a fresh signed colleague-testing APK |
| R11 | iOS and public-release readiness | iOS verification, production recovery evidence, store submission materials and release gates |

**After R8:** the main user journeys plus scheduled backend processors, recoverable notification outbox delivery, unread alerts and notification deep-link handling are implemented and locally tested.

**After R9:** the review's application functionality and privacy work are implemented locally; real-environment acceptance remains.

**After R10:** a signed Android staging APK is ready for colleagues, with a test guide and recorded device results.

**After R11 and colleague acceptance:** Android/iOS release candidates can be considered for public submission. Publication is a separate explicitly authorized action; approval by either store cannot be promised by this plan.

## How each phase will be executed

1. Read the phase, relevant authoritative docs, current diff and predecessor results. Preserve existing uncommitted work; do not reset the repository or change unrelated features. Record the initial baseline once in R1, rather than repeatedly auditing the entire app.
2. Implement the phase's bounded work packages. Use existing repositories, RPCs, widgets and domain models where suitable. Introduce shared patterns in R3 and reuse them in R4-R7 so later phases do not repeatedly redesign forms, loading, errors or navigation.
3. Add meaningful regression/acceptance coverage for that phase. Run `flutter analyze` after Flutter changes and applicable tests. For database changes, use new versioned migrations, `npx supabase test db`, local lint and a rebuild check in a disposable local environment. Never reset a database containing useful user data merely to run tests.
4. Verify the phase exit conditions and update the status ledger and review-to-phase coverage. Report changed files, commands/results, unresolved issues and any external validation assigned to a later phase. Stop; do not automatically start the next phase. Git commits identify approved milestones and must not silently include unrelated user work.

Backend/Supabase remains authoritative for permissions, capacity, eligibility, booking, conflicts, deadlines, cancellation and waitlist promotion. Flutter displays server outcomes. Preserve the finalized phone/password identity model, numeric Worker reference ID, F/ACTIVE registration, cumulative tiers, one-second final-seat rule, one-hour cancellation/conflict boundaries, Admin-only detention, one-step reasoned category changes, and informational-only wages.

Every exposed new table/RPC needs appropriate grants/RLS/authorization; critical changes need audit records. Keep server secrets outside the client and Git. Always use `npx supabase`. **This plan does not authorize `npx supabase db push`, production deployment, store submission, publication or sending messages to testers.** When a later phase needs a specific external action, prepare and verify the concrete change first and use the authorization actually available at that time.

### Keep scope manageable

- Each phase has at most four related implementation packages below. The concurrency repair is deliberately its own phase.
- Navigation and reusable interaction patterns belong to R3; each feature phase completes its own UI, validation, mutation feedback and refresh. R8 connects and verifies system-wide updates; it is not a second UI rewrite.
- R10 is integration/device QA and packaging, not a holding area for known missing screens. R11 is platform/production/store readiness, not deferred core product implementation.
- New unrelated feature requests go into a separate backlog. Fix defects introduced by the current phase before closing it. If a discovered defect crosses a future phase boundary, record its owner; resolve it now only if it prevents the current phase's required outcome.
- If evidence shows a package is materially larger than expected, report that before expanding scope. Do not conceal another large phase inside a “small final fix.”

## R1 — Permission and event-state corrections

**Outcome:** the reproduced privilege and terminal-state defects are fixed before more UI is built on them.

**Work packages**

1. Record the baseline and turn the erasure and terminal-event probes into maintained regressions that expect correct behavior. Cover the real authenticated RPC boundary, not only helper functions or owner-level SQL.
2. Enforce actor/target permissions in erasure and adjacent privileged-account mutations; prevent an Admin managing Admin/Super Admin accounts through a secondary route and protect the last active Super Admin. Preserve required reasons and auditing.
3. Reconcile event cancellation/completion/closure with assignments, waitlist entries, future reminder records and worker-facing projections. Preserve management-versus-worker cancellation causes; never refill a cancelled/closed event or silently penalize the worker.
4. Reconcile completed-work and reliability metrics with those transitions. Define and test treatment of outstanding attendance/reviews using existing approved rules; retain historical records and audit data.

**Primary areas:** identity/erasure, event lifecycle, assignments/waitlist, reliability migrations and SQL tests. Only minimal client model corrections if a repaired contract requires them.

**Verification:** Admin-to-privileged-target denial; last-Super-Admin protection; cancel with confirmed/waitlisted workers; publish → book → attendance → complete → close; repeated transition calls; management cancellation has no worker penalty; full database suite and lint.

**Exit:** a cancelled event cannot appear Confirmed, closed work reaches the correct history state, metrics reconcile, and all authorization regressions pass. Booking arbitration and broader erasure fulfillment are explicitly R2 and R9.

## R2 — Concurrent booking correctness

**Depends on:** R1.

**Outcome:** actual simultaneous Apply calls satisfy priority, capacity and conflict rules.

**Work packages**

1. Separate durable contender intake from allocation so requests can join the same one-second window without being blocked by the allocator's event lock. Store each request's server receipt time, category context and its own requirement/late-booking acknowledgements.
2. Implement safe window closure/allocation with authoritative revalidation, worker/event locking and recoverability. Keep the one-second rule; do not defer resolution to a minute-level notification cron. Include a bounded completion mechanism and recovery for abandoned allocation work.
3. Define stable idempotency and typed pending/final-result contracts. An interrupted caller must be able to retrieve its original result. Add the minimum client repository/model compatibility and pending presentation needed to keep the app usable; complete visual booking flows remain R6.
4. Add a repeatable multi-connection concurrency harness with disposable synthetic fixtures. Cover competing workers, simultaneous events for one worker, and apply/cancel/refill races. Enforce time eligibility even when lifecycle jobs run late.

**Primary areas:** booking migrations/RPCs, request outcome repository/models and integration/concurrency tests.

**Verification:** lower category first followed by A inside one second; same-category ordering; calls outside the window; exactly one final seat; no oversubscription; no conflicting dual confirmation; per-request acknowledgements; duplicate/retried requests; allocator interruption and eventual resolution.

**Exit:** the previously reproduced F-versus-A failure passes through the public RPC with independent connections. Requests resolve without fake client success, and capacity/conflict invariants hold. Load at the production-scale assumption is measured again in R10.

## R3 — Navigation, authentication and session lifecycle

**Depends on:** R2.

**Outcome:** users can enter, navigate, leave and resume the application reliably.

**Work packages**

1. Build the planned role navigation shells and correct detail/back behavior. Add bootstrap/loading/restricted-session handling, route guards, app-bar/system Back, and safe handling of deep links. Keep destinations for future features explicitly unavailable until their owning phase supplies them; no dead buttons presented as working features.
2. Complete registration success/Worker ID presentation and resumable partial signup. Validate photos before Auth creation where possible, preserve recoverable progress, handle interrupted upload/profile completion, and support the documented hosted phone-confirmation configuration without changing the phone/password login rule.
3. Complete logout, account switching and recovery: OTP resend/expiry/error/success, auth-state subscriptions, current server role/account refresh, cache isolation, and outgoing token invalidation while the session is still usable. Denied notification permission must not prevent app use.
4. Establish reusable scroll-safe forms and network interaction states: keyboard actions, password visibility, inline errors, busy buttons, explicit retry and friendly errors. Use the active server privacy/terms version with readable policy content; final public contact/URL and deletion work belongs to R9.

**Primary areas:** app/router/session/auth, shared form/error/loading helpers, registration/privacy read contract.

**Verification:** all five roles and cross-role deep links; Home → feature → detail → Back; phone-keyboard overflow regression; successful/resumed signup; duplicate phone/underage/invalid photo; recovery; expired/revoked sessions; switching accounts cannot reuse another account's data or token ownership. Real SMS delivery is a required R10 acceptance item.

**Exit:** users are not trapped, registration enters the correct role experience, every role can log out, and session/data isolation is tested. Domain-specific dashboards and screens belong to R4-R7.

## R4 — Team, worker directory and profiles

**Depends on:** R3.

**Outcome:** management can establish the team and field staff can identify workers without SQL intervention.

**Work packages**

1. Implement trusted staff Auth-account provisioning and Team/Admin-account screens with approved create/change/revoke/reactivation boundaries. Keep server credentials server-side and preserve the acting Admin session; handle partial provisioning and retry.
2. Connect controlled phone reassignment and existing detention/release/category-change flows with identity-verification context, reasons, correct role/category history and assignment-review effects. Show restriction explanations and permitted history; do not add unapproved account-state transitions.
3. Complete private-photo display and replacement, own-profile/staff-profile views and authorized histories. Enforce actual owned Storage-object existence/completeness on the backend; preserve upload → reference update → old-object cleanup ordering and recover failed cleanup.
4. Add debounced directory search, category/account/reliability filters and pagination beyond 50 results. Use R3's loading, error and retry patterns; refresh role/profile/history changes and invalidate signed-photo caches appropriately.

**Primary areas:** trusted provisioning endpoint, worker/team/profile repositories and screens, Storage/security migrations and tests.

**Verification:** role-target permission matrix; provisioning retries without session replacement; phone uniqueness and existing-account preservation; worker ↔ field-role category/history effects; required-photo bypass denial and private access; replacement failures; filtered pagination without duplicate/missing rows.

**Exit:** Super Admin can establish Admins, authorized management can establish field leaders, workers have usable profiles/photos/history, and role/account changes remain server-controlled and audited.

## R5 — Admin event management

**Depends on:** R4.

**Outcome:** Admin can schedule and operate a real event through the application.

**Work packages**

1. Replace fixed dates/times with explicit event date, reporting, start and expected end input in Asia/Kolkata with 12-hour display. Complete create/edit with validation, version-conflict handling, recoverable drafts and clear save/publish feedback.
2. Connect multiple leader selection, structured requirements/acknowledgement settings, wages/allowances, instructions/dress code, Maps and standard/custom cumulative tier configuration. Preview the intended schedule before publishing.
3. Connect staffing/waitlist views, capacity reduction, explicit management removal, time-edit conflicts and assignment-review resolution. Show impact and require approved reasons/confirmations; never silently drop assignments or select a worker to remove.
4. Complete Admin event list/calendar/status filters and dashboard: today's required/filled/vacant staffing, attendance summary, unresolved flags and event drill-down. Apply refresh/error/empty states as part of these screens.

**Primary areas:** event form/detail/list/dashboard, leader picker, requirements, event management RPC/read models.

**Verification:** actual chosen times round-trip correctly, including overnight events; invalid time ordering; multiple leader access; stale edit versions; significant change auditing; capacity below confirmations; conflict edit/resolution; publish/cancel/complete/close and dashboard counters.

**Exit:** an Admin can create, assign, edit, publish, inspect and resolve an event using the app. No scheduling values are silently invented. Broad reports/audit exploration remains R7.

## R6 — Worker event and work journeys

**Depends on:** R5.

**Outcome:** a worker can discover work, understand the commitment, apply, waitlist, withdraw and follow their assignment.

**Work packages**

1. Complete event cards/detail for Available/Locked/Full/Confirmed/Completed/Cancelled states, open tiers and informative countdowns. Present wages/allowances, requirements, instructions, Maps and appropriately scoped leader contacts.
2. Implement requirement checkboxes and late-booking consent, using the R2 pending/result protocol. Preserve one idempotency key across retries and show explicit submitting/confirmed/denied/uncertain-network outcomes; prevent duplicate taps.
3. Complete My Work with confirmed work, active waitlist and accurate completed/cancelled/removed history. Add withdrawal, visible cancellation deadline/consequences, event detail access and conflict/review notices. Refresh all affected providers after changes.
4. Build Worker Home around next work, category/reliability explanation and urgent alerts. Complete empty/loading/offline/retry states, including refreshing an empty event board, without deriving authoritative eligibility from cached data.

**Primary areas:** worker discovery/detail, booking/waitlist repository/controller, My Work, Worker Home.

**Verification:** mandatory acknowledgements and late-booking consent; cumulative tiers; pending-to-final booking; full/locked/restricted/conflict races; exactly-at/after cancellation cutoff; withdraw before promotion; promotion during withdrawal; removed history; network loss after server commit.

**Exit:** the complete worker work journey succeeds using real RPCs, including denied/stale/network states. No inaccessible consent, withdrawal or deadline remains.

## R7 — Field operations and reports

**Depends on:** R6.

**Outcome:** event-day staffing can be identified, marked, reviewed and reported accurately.

**Work packages**

1. Complete Captain/Supervisor Home and assigned-event details with instructions, staffing, worker photos and relevant alerts. Improve roster grouping/search and distinguish full-event attendance totals from filtered-result counts.
2. Complete attendance correction and existing-review editing with current values, allowed actions before/after Close, clear save results and audit/history access. Keep assigned-event authority server-side; reconcile displayed reliability with source records and provisional-state rules.
3. Add authorized global reports/audit views with actor/event/date filters and pagination, plus staffing/category/attendance summaries. Link Admin dashboard and worker-history drill-down to the existing approved reporting scope.
4. Finish export quality: correct informational pay/allowances, copy/share behavior, embedded font coverage, Malayalam/long names, layout and multipage rosters. Apply R3 interaction/accessibility patterns throughout these screens.

**Primary areas:** field dashboard/events/attendance, review UI, reports/audit repositories and PDF export.

**Verification:** assigned/unassigned leaders; repeated attendance changes; closure boundaries; review editing/uniqueness; filtered versus overall counts; scoped report access; source-to-metric reconciliation; visually rendered PDF cases with representative names and large rosters.

**Exit:** a field leader can manage an assigned event and an Admin can inspect/export an accurate account of it. Sensitive report content remains limited to authorized users.

## R8 — Scheduled operations and notifications

**Depends on:** R7.

**Outcome:** automation happens without manual SQL calls and devices receive usable updates.

**Work packages**

1. Wire reproducible lifecycle/tier/reminder/dispatch jobs with server time, overlapping-run safety, catch-up behavior and operational health records. Verify cancellation/removal/time-edit effects on future reminders. Reuse R2's allocator rather than replacing its one-second completion mechanism with a coarse schedule.
2. Repair outbox claiming with expiring leases and safe completion ownership, per-delivery timeout/error isolation, bounded retry/backoff and invalid-token handling. Implement renewable FCM authorization or an explicit tested proxy contract; secure dispatcher invocation.
3. Complete foreground/background/terminated notification handling, authenticated deep links, permission-denied UX, token rotation and account switching. Do not claim external push delivery is exactly-once when provider acknowledgements are ambiguous.
4. Connect realtime or an explicit refresh fallback for role/account/category, events, assignments/waitlist, rosters and alerts. Audit provider invalidation across completed screens; show reconnecting/stale states and refresh on resume without leaking data across sessions.

**Primary areas:** job/notification migrations, Edge Functions, FCM integration, shared realtime/app-lifecycle coordination.

**Verification:** jobs advance without manual RPC calls; missed/overlapping runs; cancelled/removed reminders suppressed; dispatcher death after claim; provider timeout/auth expiry; expired-lease recovery; token changes; foreground and push-tap routing; two-client update/reconnect scenarios.

**Exit:** scheduled operations and recovery pass in a controlled environment. Record exact hosted schedules/secrets needed for R10. Real phone delivery and permission behavior must pass R10 rather than being inferred from a token-registration test.

## R9 — Privacy, deletion and retention

**Depends on:** R8.

**Outcome:** the stated privacy lifecycle exists in the product and backend, with controlled fulfillment.

**Work packages**

1. Finalize readable in-app Privacy Notice/Terms, active-version presentation and acceptance records, support/privacy contacts, and correction/deletion instructions. Preserve the approved collection and retention rules; never invent business contact details.
2. Provide a discoverable in-app deletion initiation flow and a matching external web request resource for Google Play. A user request must enter the controlled verification process; it must not acquire Admin erasure authority. Show request status and the expected handling period.
3. Implement verified erasure fulfillment: appropriate Auth/session/device-token disabling, private-photo/current-PII removal, and historical anonymization/pseudonymization where the approved policy permits. Preserve required records and legal holds, enforce privileged-target safeguards from R1, and make retries resumable/auditable.
4. Complete the documented retention categories with dry-run reporting, safe ordering, hold-aware deletion/anonymization and scheduled processing through R8's job infrastructure. Document exactly what is retained and why. Resolve any genuinely unspecified retention/legal-hold decision before destructive implementation; do not silently change finalized periods.

**Primary areas:** privacy/settings UI, deletion-request resource, trusted fulfillment/Storage work, retention migrations/jobs, policy/runbook documentation.

**Verification:** active-version change; authorized self-request versus unauthorized execution; privileged-target denial; verification and fulfillment transitions; 30-day due handling; Auth/session restriction; photo cleanup retry; repeated jobs; dry-run versus live results; legal holds; historical integrity. Use synthetic data for destructive tests.

**Exit:** users can read policies and initiate requests, the server can actually fulfill verified requests, and retention promises have executable tests. Required contact details and a functioning external request URL must be supplied/verified; unfinished placeholders do not count as complete.

## R10 — Android staging test release

**Depends on:** R9.

**Outcome:** produce the APK the user can confidently give to colleagues for acceptance testing.

**Work packages**

1. Finish release reproducibility: resolve README conflict markers, remove generated dependency files from Git tracking without deleting needed local installations, preserve lockfiles/intended config, pin the tested toolchain where appropriate and reconcile stale verification documentation. Fix build-script exit-code checks and reject missing/stale output. Record source milestone, version, environment and artifact checksum.
2. Verify hosted staging parity for migrations/RLS/private Storage, Auth/SMS, trusted provisioning, jobs and FCM. Prepare reviewed deployment/configuration steps; apply only with the required authorization. Establish role/category test accounts and events through the completed app flows wherever those flows are under test.
3. Run the review's full acceptance matrix on physical Android devices: install/upgrade/restart, all roles, real registration/recovery/SMS/push, mobile data/Wi-Fi, offline retry after commit, two-device races, Back navigation, small screens/keyboard/large text/TalkBack and exports. Load-test representative activity with approximately 2,000 synthetic workers and record latency, query plans and capacity/conflict invariants; fix measured release blockers.
4. Build a fresh signed staging APK, verify its signature/environment/provenance and install that exact artifact for the final smoke test. Supply release notes, known limitations, role-based tester instructions and a reproducible bug-report template. Do not message colleagues or publish the app as part of producing the package.

**Primary areas:** build/CI/scripts, repository hygiene, staging runbooks, integration/load/device tests and APK artifact.

**Verification:** full Flutter/SQL/concurrency suites; staging authorization smoke tests; no secret leakage into client/logs; clean build failure does not report success; current APK installs/upgrades; all required physical-device and notification scenarios; reviewed load measurements.

**Exit:** no unresolved security/core-workflow blocker from the review, required matrix scenarios pass, and the exact signed APK is installed and verified. Missing staging access or a physical device is an explicit outstanding gate, not a passing test. Cosmetic limitations may be recorded only if they do not prevent required behavior.

**Milestone:** ready for colleague testing. Their acceptance results remain required input to the final release decision. Findings should be assigned back to the responsible phase/area for focused corrections and retesting rather than causing the whole plan to restart.

## R11 — iOS and public-release readiness

**Depends on:** R10; colleague acceptance is required before the final release gate.

**Outcome:** close platform, production-operations and store-readiness gaps without altering core V1 scope.

**Work packages**

1. Configure the required iOS photo/privacy permissions, signing/provisioning, Firebase/APNs capabilities and release build. Verify on Mac/iOS hardware: fresh install, authentication/photo selection, notifications/deep links, navigation, accessibility/VoiceOver, exports and upgrade. Android evidence does not substitute for iOS testing.
2. Verify the production deployment and recovery plan: RLS/configuration parity, secret ownership, job/dispatcher monitoring, PITR/backup suitability, Storage/Edge Function/config/credential restoration, incident contacts and a timed isolated restore rehearsal. Measure recovery against documented RPO/RTO targets; record any owner-accepted operational deviation explicitly.
3. Prepare current Google Play/App Store submissions: signed AAB/iOS build, versioning, screenshots/listing/support material, privacy/data disclosures, deletion URLs, reviewer access and testing-track results. Re-check official store/platform requirements at execution time rather than freezing policy assumptions from the review date.
4. Consolidate colleague/device feedback, fix release-blocking regressions, rerun affected checks and prepare a concrete launch/rollout/rollback decision with exact artifacts. Obtain the required authorization for external submissions/deployment/publication at the applicable step; do not treat completion of this plan as permission to launch.

**Primary areas:** iOS platform setup, production recovery/incident runbooks, release artifacts and store materials.

**Verification:** signed iOS archive and real-device pass; required testing-track/pre-launch results; public policy/deletion resources; isolated recovery evidence; production-safe authorization checks; reconciled colleague findings and exact artifact/version checklist.

**Exit:** both intended platforms and production operations have recorded evidence and submission materials are complete. Missing Mac/iPhone access, developer accounts or backup capability remains an explicit gate. Store approval and actual public launch are external outcomes, reported separately.

## Complete review-to-phase coverage

The numbered references below are the 12 issue groups in the readiness review. An implementation owner fixes the behavior; R10/R11 validate the relevant environment/platform rather than duplicating implementation.

| Review item | Implementation owner | Final verification |
|---|---|---|
| 1. Admin can deactivate Super Admin | R1 — fixed locally; see R1 report | R9 erasure flow; R10 hosted permissions |
| 2. Final-seat priority fails | R2 — fixed locally; see R2 report | R6 client result flow; R10 multi-device/load |
| 3. Cancelled/closed events remain Confirmed | R1 — fixed locally; see R1 report | R5/R6/R7 journeys; R10 full lifecycle |
| 4. Navigation traps | R3 — fixed locally; see R3 report | Every feature phase; R10 Android; R11 iOS |
| 5. Registration/logout/recovery/session gaps | R3 — fixed locally; see R3 report | R10 real Auth/SMS and account switching |
| 6. Fixed event times/missing event controls | R5 — fixed locally; see R5 report | R10 event administration |
| 7. Missing team management | R4 — fixed locally; see R4 report | R5 leader assignment; R10 team bootstrap |
| 8. Missing Apply acknowledgements | R6 — fixed locally; see R6 report | R10 requirements/late-booking races |
| 9. Waitlist withdrawal/My Work gaps | R6 — fixed locally; see R6 report | R10 cancellation/promotion/withdrawal |
| 10. Missing schedules/stale state | R3 session foundation fixed locally; R4 worker/profile refresh fixed locally; R5-R7 feature refresh; R8 job/realtime integration | R10 cross-device/real jobs |
| 11. Mutation feedback and retries | R3 shared pattern fixed locally; R4-R7 each feature; R2 booking idempotency | R10 lost-response/double-tap/offline |
| 12. Stuck push deliveries and missing push-open handling | R8 | R10 Android push; R11 iOS push |
| Login/recovery keyboard, password and validation UX | R3 — fixed locally; see R3 report | R10/R11 devices |
| Grouped registration, photo preview/upload progress, readable consent | R3 — fixed locally; see R3 report | R9 final content; R10 signup |
| Worker Home/event cards/Maps/leader contact/deadlines | R6 — fixed locally; see R6 report | R10 worker journey |
| Admin dashboard/calendar/staffing/conflicts | R5 — fixed locally; see R5 report | R10 management journey |
| Field Home/roster photos/counters/review editing | R7 — fixed locally; see R7 report, using R4 photo contract | R10 field journey |
| Worker search/filter/pagination, profile/history/category/reliability explanation | R4 — fixed locally; R6 Worker Home; R7 operational metric verification | R10 representative dataset |
| Backend required-photo bypass and replacement lifecycle | R4 — fixed locally for own-profile replacement and signed access; R9 erasure | R9 erasure; R10 private Storage |
| Global reports/audit, filters/pagination, Unicode/multipage exports | R7 — event-scoped reports fixed locally; see R7 report | R10/R11 export device checks |
| Raw enum/developer/error copy, loading/empty/offline/retry states | R3 conventions fixed locally; R4-R8 screen owners | R10 consistency/accessibility |
| Touch targets, text scaling, contrast, screen readers | R3 conventions fixed locally; R4-R8 screen owners | R10 TalkBack; R11 VoiceOver |
| Privacy/deletion initiation, external request resource and actual fulfillment | R9 | R10 staging; R11 store/production |
| Full retention coverage, holds, Auth revocation and 30-day erasure | R9 | R11 production operation |
| Staging parity, real SMS/FCM and physical-device evidence | R10, using R3/R8 integrations | R10 exit gate |
| APK signature/provenance, stale output, build-script failure, CI/toolchain | R10 | Exact artifact installed in R10 |
| README conflicts, tracked node_modules, intended files, stale test counts | R10 | Reproducible source milestone |
| Production PITR/Storage/config recovery and incident contacts | R11 | Timed isolated restore and owner review |
| iOS permissions, signing/APNs and device/release tests | R11 | Mac/iOS evidence |
| Store disclosures, screenshots/reviewer access/testing tracks | R11 | Submission-readiness checklist |

## External prerequisites to prepare early

These are dependencies to arrange in advance, not permission requests or actions authorized by this planning document. Local implementation and synthetic tests should proceed within the active phase while unrelated future prerequisites are being prepared.

| Needed by | Dependency |
|---|---|
| R3 configuration design / R10 delivery proof | Intended hosted phone-confirmation mode and usable SMS provider/test numbers |
| R8 integration / R10 delivery proof | Firebase project access, server-side renewable credentials/proxy configuration and approved scheduler/dispatcher environment |
| R9 | Business-approved policy wording, support/privacy contacts and a host/domain for the external deletion resource |
| R10 | Hosted staging access, explicit approval for the actual migration push when needed, protected signing setup and representative physical Android devices |
| R11 | Mac/iPhone access, Apple/Google developer accounts, APNs/provisioning, production backup plan/artifacts and named operations/privacy owners |

## Status ledger

Record evidence as work completes. “Implemented locally” does not mean “tested on hosted staging” or “approved for publication.” External checks explicitly assigned to R10/R11 are tracked there; a phase with an unmet own exit gate stays open.

| Phase | Status | Evidence / outstanding gate | Approved milestone |
|---|---|---|---|
| R1 | Complete locally — 9 September 2026 | [R1 report](A:/Dev/oslava_events/docs/READINESS_R1_REPORT.md): 502 assertions, clean lint, disposable replay/legacy repair and concurrent permission test passed; hosted acceptance remains R10 | Execution authorized; no commit created |
| R2 | Complete locally — 9 September 2026 | [R2 report](A:/Dev/oslava_events/docs/READINESS_R2_REPORT.md): 519 DB assertions, 40 replay/concurrency/recovery checks, 72 Flutter tests, clean analysis/lint; hosted/load acceptance remains R10 | Execution authorized; no commit created |
| R3 | Complete locally — 9 September 2026 | [R3 report](A:/Dev/oslava_events/docs/READINESS_R3_REPORT.md): 17 focused R3 tests, 89 Flutter tests, 519 DB assertions and clean Flutter analysis; hosted SMS/FCM and physical-device acceptance remain R10 | Execution authorized; no commit created |
| R4 | Complete locally — 9 September 2026 | [R4 report](A:/Dev/oslava_events/docs/READINESS_R4_REPORT.md): 16 focused R4 DB assertions, 535 DB assertions, 12 focused worker-management tests, 91 Flutter tests and clean Flutter analysis; hosted Edge Function/Auth/Storage acceptance remains R10 | Execution authorized; no commit created |
| R5 | Complete locally — 9 September 2026 | [R5 report](A:/Dev/oslava_events/docs/READINESS_R5_REPORT.md): explicit Asia/Kolkata scheduling/editing, leaders/requirements/allowances, admin detail/dashboard read models, lifecycle actions, 93 Flutter tests and 545 DB assertions; hosted/device acceptance remains R10 | Execution authorized; no commit created |
| R6 | Complete locally — 10 September 2026 | [R6 report](A:/Dev/oslava_events/docs/READINESS_R6_REPORT.md): worker event detail, acknowledgements, Apply pending/result retry, waitlist join/withdraw, My Work/Worker Home, 95 Flutter tests and 551 DB assertions; device/offline/push acceptance remains R10 | Execution authorized; no commit created |
| R7 | Complete locally — 10 September 2026 | [R7 report](A:/Dev/oslava_events/docs/READINESS_R7_REPORT.md): field dashboard, enhanced roster counters/search/photos, attendance correction, editable reviews, report filters/history and export checks; 97 Flutter tests and 557 DB assertions; device/export acceptance remains R10/R11 | Execution authorized; no commit created |
| R8 | Not started | — | — |
| R9 | Not started | — | — |
| R10 | Not started | — | — |
| R11 | Not started | — | — |

Next available phase: **R8 — Scheduled operations and notifications.** Each request names the phase to execute; a completed phase does not authorize advancing automatically.
