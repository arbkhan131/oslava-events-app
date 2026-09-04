# Oslava Events Implementation Plan

## Purpose and authority

This plan translates `Oslava_Events_Complete_Product_Blueprint.pdf` into bounded implementation work. The blueprint remains authoritative for business behavior. The companion architecture documents define a proposed technical realization and identify decisions that the blueprint intentionally leaves open.

No phase should change a finalized business rule without an explicit blueprint revision. Each phase is intended to be implemented, reviewed, tested, and committed independently.

## Non-negotiable business rules

- One Flutter application, Android first and iOS-ready.
- Roles are `SUPER_ADMIN`, `ADMIN`, `CAPTAIN`, `SUPERVISOR`, and `WORKER`; worker categories `A`, `B`, `C`, and `F` are separate from roles.
- All users authenticate with a unique phone number plus password. Numeric Worker ID is a generated operational/reference ID, not a login credential.
- Every newly registered worker starts as `F`, is `ACTIVE`, and can work immediately without approval.
- Only an active Worker has a current category. A Worker changing to Captain/Supervisor has no active category; history and the prior Worker category are retained for default restoration if they return to Worker, subject to Admin selection.
- Normal worker applications are confirmed automatically when all backend rules pass.
- Tier access is cumulative: A remains eligible when B, C, and F open.
- Exact event capacity, eligibility, account restrictions, booking conflicts, cancellations, waitlist order, and promotions are decided server-side.
- Final-seat requests received in the same one-second arbitration window compete by A>B>C>F, then earliest server-received time within the same category.
- Workers may cancel at or before `reporting_at - 1 hour`; later cancellation is blocked.
- Every pair of confirmed events must have at least one hour between one event's expected end and the other's reporting time.
- Full events offer an explicit Join Waitlist action; workers are never added automatically. A worker may leave before promotion without penalty.
- Waitlist refill revalidates account state, category eligibility, requirements, and conflicts.
- Only Super Admin/Admin may detain or release workers. Detention blocks future applications, retains existing confirmed assignments, and flags those assignments for Admin resolution.
- Captain/Supervisor may search all workers and history and may promote/demote globally. Event operations and attendance remain restricted to assigned events.
- V1 category changes are one step only (`F<->C<->B<->A`) and require a reason for promotion and demotion.
- Attendance may be corrected by field leaders and admins until the event is Closed; after Closed only Admin/Super Admin may correct it. Every change is audited.
- Performance reviews use 1-5 stars with optional tags/notes, one review per reviewer/worker/event, editable until event Close.
- Operational timezone is `Asia/Kolkata`, client time is 12-hour format, and V1 currency is INR.
- All required worker profile fields, including photo, must be complete before Apply.
- Event lifecycle and recruitment are separate state machines.
- Reliability is separate from category and never changes category automatically in V1.
- Wages and allowances are informational; payroll is out of scope.

## Finalized decision register

1. Authentication is unique phone number plus password for every role. Numeric Worker ID remains operational/reference data only.
2. Final-seat contention uses a one-second arbitration window, ordered by A>B>C>F and then earliest server-received request within a category.
3. Waitlist entry is explicit opt-in from a Full event.
4. Detain/Release authority belongs only to Super Admin and Admin.
5. Detention blocks future applications but preserves and flags existing confirmed assignments for Admin resolution.
6. Current category exists only for active Workers; role changes to Captain/Supervisor clear current category while preserving history and the last Worker category for default restoration.
7. Super Admin manages Admin, Captain, and Supervisor roles; Admin manages Captain and Supervisor roles only.
8. V1 promotion/demotion is one step along `F<->C<->B<->A`, with a mandatory reason in both directions.
9. Captain/Supervisor can search/view all workers and history and promote/demote globally; attendance and event operations require assignment to the event.
10. Captain/Supervisor/Admin/Super Admin can correct attendance until event Close; only Admin/Super Admin can correct it after Close; all changes are audited.
11. Performance review is 1-5 stars with optional tags/notes, unique per reviewer/worker/event, and editable until event Close.
12. Timezone is `Asia/Kolkata`, client display is 12-hour, and V1 currency is INR.
13. Every required worker profile field, including photo, must be complete before Apply.
14. A waitlisted worker may leave without penalty until promotion; after promotion normal cancellation rules apply.
15. Tier/vacancy notifications exclude restricted/inactive, already-confirmed, and known-conflicting workers; Apply always revalidates.
16. `event_status` is `DRAFT`, `PUBLISHED`, `UPCOMING`, `IN_PROGRESS`, `COMPLETED`, `CLOSED`, or `CANCELLED`; `recruitment_status` is `NOT_OPEN`, `OPEN`, `FULL`, or `CLOSED`.
17. Reliability weighting is deferred, with a mandatory decision before Phase 13.
18. Data-retention/privacy decisions are deferred, with a mandatory decision before Phase 16 production hardening.

## Planned Flutter architecture

Use a feature-first Flutter structure with Riverpod for state/dependency injection and `go_router` for role-aware navigation, as directed by the blueprint.

```text
lib/
  main.dart
  app/
    app.dart
    bootstrap.dart
    router/
    theme/
  core/
    config/
    errors/
    logging/
    time/
    widgets/
  features/
    auth/
    profile/
    workers/
    events/
    booking/
    waitlist/
    attendance/
    performance/
    reliability/
    notifications/
    reports/
  data/
    supabase/
    models/
```

Each feature owns presentation, Riverpod providers/controllers, domain models, and repository adapters. Widgets never make authorization, capacity, eligibility, deadline, or conflict decisions; they display server-returned state and invoke controlled RPCs.

Environment configuration must separate local, development, and production values. Only the Supabase publishable/anon key and public project URL may ship in the client. Service-role credentials and FCM server credentials remain server-side.

## Phase sequence

### Phase 0 - Decision closure and acceptance baseline

**Objective:** Close every decision required for Phases 1-2, record later decisions with a named phase deadline, and turn the blueprint acceptance scenarios into executable test cases before feature work starts.

**Files/components involved:** `docs/IMPLEMENTATION_PLAN.md`, `docs/PHASE_0_ACCEPTANCE_TEST_SPECIFICATIONS.md`, planned `test/acceptance/`, planned `supabase/tests/`.

**Database changes:** None.

**Tests:** Write test case specifications for phone/password registration, cumulative tiers, the one-second final-seat window, explicit waitlist opt-in/withdrawal, conflict and cancellation boundaries, detention flags, role/category transitions, attendance correction, performance review, and role authority.

**Completion criteria:** All decisions required before early foundation implementation are recorded as closed. Every intentionally deferred decision has an explicit deadline before its owning phase. Each blueprint acceptance scenario has inputs, expected result, and responsible test layer.

**Dependencies:** None.

**Phase 0 completion record:** Complete. Phase 1-2 decisions are verified closed, detailed acceptance specifications are recorded in `PHASE_0_ACCEPTANCE_TEST_SPECIFICATIONS.md`, each specification has a responsible layer, and all intentional deferrals have named phase deadlines. No Flutter feature, package, migration, RPC, local database fixture, or remote Supabase change was created.

### Phase 1 - Flutter project foundation

**Objective:** Replace the starter counter structure with the application shell, environment loading, theme, Riverpod scope, `go_router`, error handling, and role-aware route guards without building business features.

**Files/components involved:** `pubspec.yaml`, `lib/main.dart`, planned `lib/app/**`, `lib/core/**`, test helpers, Android environment files.

**Database changes:** None.

**Tests:** App bootstrap widget test; route-guard unit tests with fake sessions/roles; environment validation tests; `flutter analyze`.

**Completion criteria:** App boots in local/dev modes, unauthenticated users reach Login, authenticated fake roles reach the correct empty shell, and no service secret is bundled.

**Dependencies:** Phase 0.

### Phase 2 - Supabase schema and security foundation

**Objective:** Establish reproducible local migrations, domain enums, base tables, private authorization helpers, least-privilege grants, RLS defaults, audit conventions, and pgTAP infrastructure.

**Files/components involved:** planned `supabase/migrations/*`, `supabase/tests/database/*`, `supabase/seed.sql`, local config only.

**Database changes:** Create extensions, domain enums, the `private` helper schema, audit foundation, default privilege rules, and database-test helpers. Feature tables are added by their owning phases with their grants and RLS.

**Tests:** Migration-up/local-reset test; enum and constraint tests; RLS deny-by-default tests for `anon` and `authenticated`; audit immutability tests; database lint.

**Completion criteria:** A clean local database can be rebuilt using `npx supabase ...`; all exposed relations have explicit grants and RLS; database tests pass locally. No remote push occurs.

**Dependencies:** Phase 0.

### Phase 3 - Identity, registration, and login

**Objective:** Implement unique-phone-plus-password authentication for all roles; Worker registration with generated operational Worker ID, automatic `F` category and `ACTIVE` state; session bootstrap; and logout.

**Files/components involved:** `features/auth/**`, `features/profile/**`, auth repository, phone normalization, staff-account provisioning flow, profile-photo storage adapter.

**Database changes:** `profiles`, `worker_profiles`, role/account history, numeric Worker ID sequence, profile-completeness state, registration trigger/function, profile-photo bucket policies, identity/role-management RPCs.

**Tests:** Registration field validation; duplicate normalized-phone race; phone/password login for every role; generated Worker ID uniqueness and proof it cannot authenticate; F/ACTIVE defaults; incomplete-profile Apply gate; staff-role authority; category clear/restore on role change; forbidden role/category/account edits.

**Completion criteria:** Every user signs in with unique phone plus password; a worker receives a non-login numeric reference ID and enters as F/ACTIVE; role/category transitions preserve history and restoration behavior; protected identity fields remain server-controlled.

**Dependencies:** Phases 1-2; any recovery/profile-validation details listed with a Phase 3 deadline.

### Phase 4 - Worker directory and account management

**Objective:** Provide own-profile editing, global worker search/history for authorized staff, Admin-only detention/release, staff-role management, and flagged review of restricted workers' existing assignments.

**Files/components involved:** `features/profile/**`, `features/workers/**`, shared search/filter controls, worker repository.

**Database changes:** Controlled own-profile RPC; Super Admin/Admin role-management RPCs; Admin-only account-state RPC; account action/history records; assignment-review flags; indexed worker search fields.

**Tests:** Allowed own-field updates; protected-field denial; Captain/Supervisor global worker/history reads; role creation/revocation authority; Admin-only detention/release; detention audit; future Apply blocked; existing assignments retained and flagged exactly once.

**Completion criteria:** Workers maintain only permitted fields; field leaders can search all workers; role-management boundaries are enforced; detention never auto-cancels an assignment and always creates an Admin-visible resolution flag.

**Dependencies:** Phase 3.

### Phase 5 - Event management

**Objective:** Implement Admin/Super Admin event draft, edit, publish, cancel, leader assignment, structured requirements, INR allowances/wages, instructions, dress code, separate event/recruitment state, and list/calendar views in `Asia/Kolkata`.

**Files/components involved:** `features/events/**`, Admin event form/list/detail, leader picker, requirement editor, maps-link launcher.

**Database changes:** `events` with separate `event_status` and `recruitment_status`, `event_leaders`, `event_requirements`, `event_allowances`, event audit/history; controlled event mutation RPCs; INR and timezone constraints.

**Tests:** Required fields and time ordering in `Asia/Kolkata`; 12-hour client formatting; INR-only V1 money; independent lifecycle/recruitment transitions; multiple Captains/Supervisors; role validation; draft invisibility; publish/cancel authorization; capacity reduction guard; significant edit auditing.

**Completion criteria:** Admins can manage the complete blueprint event form; lifecycle and recruitment state cannot be conflated; workers cannot see drafts; cancellation and edits retain history.

**Dependencies:** Phases 2-4.

### Phase 6 - Tier plans and scheduled release engine

**Objective:** Store Standard, Urgent, Emergency, and Custom A/B/C/F schedules; compute release times at publication; process due tiers server-side; preserve cumulative access.

**Files/components involved:** event tier editor/read model, countdown component, planned scheduled database function and durable in-app notification producer.

**Database changes:** `tier_release_presets`, `event_tier_release_rules`, initial `notifications`; `publish_event`, `process_due_tier_releases`, and eligibility helpers; scheduled local/hosted job definition in migration.

**Tests:** Every preset; delayed custom A; cumulative A+B+C+F access; idempotent repeated scheduler runs; no next-tier vacancy alert when recruitment is FULL; reopened-vacancy behavior; exclusion of restricted/inactive, confirmed, and known-conflicting recipients.

**Completion criteria:** Backend time alone controls eligibility; every tier opens once at its configured threshold; higher tiers never lose access; FULL recruitment suppresses the next-tier vacancy alert; targeting applies all approved exclusions while Apply remains authoritative.

**Dependencies:** Phase 5.

### Phase 7 - Worker event discovery

**Objective:** Build worker Home, Events, event detail, and My Work read experiences for Available, Locked, Full, Confirmed, Completed, and Cancelled states.

**Files/components involved:** `features/events/presentation/worker/**`, server-projected event board query/view, countdowns, maps links.

**Database changes:** Security-invoker read views or stable read RPCs for worker-visible events, vacancy counts, tier state, and own assignment summary.

**Tests:** Category-specific board states; locked detail visibility; no draft leakage; independent event/recruitment status rendering; Full event shows explicit Join Waitlist and never auto-enrolls; confirmed-only leader contact; `Asia/Kolkata` 12-hour countdown/display boundaries.

**Completion criteria:** Workers see full event information and the correct server-derived action state; Full presents explicit waitlist opt-in; no client-side eligibility or lifecycle inference controls a mutation.

**Dependencies:** Phases 3, 5-6.

### Phase 8 - One-hour conflict engine

**Objective:** Implement one reusable server predicate for bidirectional one-hour event separation and conflict flags caused by later event edits.

**Files/components involved:** booking domain service contract, Admin conflict-warning UI, shared time utilities.

**Database changes:** Core `assignments` relation with client writes disabled, `has_booking_conflict`, supporting indexes, shared `assignment_review_flags`, and event-edit conflict scan.

**Tests:** 60-minute boundary allowed; 59-minute gap blocked; overlap blocked; reverse-order same-day booking; overnight events; cancelled/removed assignments ignored; edit-created conflict flagged.

**Completion criteria:** All booking paths and waitlist promotion can call one transaction-safe conflict check; event edits warn and flag without silently removing assignments.

**Dependencies:** Phases 2 and 5.

### Phase 9 - Atomic booking and capacity

**Objective:** Implement idempotent Apply with server-authoritative account, event, tier, requirement, duplicate, conflict, capacity, and priority checks.

**Files/components involved:** `features/booking/**`, Apply state/result UI, controlled booking RPC, realtime event counters.

**Database changes:** `booking_requests`, one-second `booking_arbitration_windows`, `assignments`, requirement acknowledgements, `apply_for_event`, capacity/recruitment-status update logic, uniqueness constraints.

**Tests:** Each rejection/result code; duplicate taps; required-profile/photo completeness; requests inside/outside the one-second window; A>B>C>F ordering; earliest server receipt within one category; capacity invariant under load; rollback on failure.

**Completion criteria:** Confirmed assignments never exceed target; Apply is idempotent; incomplete profiles cannot Apply; the final-seat decision waits for the one-second window to close and passes concurrent category/time priority tests.

**Dependencies:** Phases 6-8.

### Phase 10 - Cancellation and waitlist

**Objective:** Enforce the exact cancellation boundary, explicit late-booking acknowledgement, explicit waitlist opt-in, penalty-free pre-promotion withdrawal, priority ordering, and automatic vacancy refill.

**Files/components involved:** `features/booking/cancellation/**`, `features/waitlist/**`, My Work cancellation state, waitlist status UI.

**Database changes:** `cancellations`, `waitlist_entries`; `cancel_assignment`, `join_waitlist`, `withdraw_waitlist`, `promote_waitlist`; row/advisory locking for one refill worker.

**Tests:** Before/at/after deadline; late booking accepted only after warning acknowledgement; no automatic waitlist insertion; duplicate Join protection; penalty-free withdrawal before promotion; normal cancellation after promotion; A>B>C>F ordering; same-tier join-time ordering; revalidation skip; simultaneous cancel/refill; promoted-worker notification record.

**Completion criteria:** Workers enter the waitlist only by explicit action, may leave without penalty before promotion, and use normal cancellation after promotion; refill occurs once and never promotes an invalid/restricted/conflicting worker.

**Dependencies:** Phase 9.

### Phase 11 - Field operations and attendance

**Objective:** Deliver assigned-event worker lists, category grouping/search, realtime counters, and audited attendance entry/correction with authority changing at event Close.

**Files/components involved:** `features/attendance/**`, field Home/Events, worker roster and counters.

**Database changes:** `attendance`; controlled `set_attendance` RPC; attendance audit trigger; realtime publication for safe tables/read models.

**Tests:** Assigned leader authorization and unassigned leader denial for event operations; all four states; Captain/Supervisor/Admin/Super Admin correction before Close; field-leader denial after Close; Admin/Super Admin correction after Close; old/new audit on every change; one row per assignment; realtime counters.

**Completion criteria:** Assigned field leaders and admins can correct attendance until Close, only Admin/Super Admin can correct after Close, every change is audited, and workers cannot alter attendance.

**Dependencies:** Phases 5 and 9.

### Phase 12 - Performance and category changes

**Objective:** Add 1-5-star event performance reviews and global, direct, one-step promotion/demotion by Captain, Supervisor, Admin, or Super Admin.

**Files/components involved:** `features/performance/**`, worker profile/history, rating form, category-change dialog.

**Database changes:** `performance_reviews` with unique reviewer/worker/event key and edit cutoff at event Close; `worker_category_history`; `record_performance_review`, `change_worker_category`; mandatory reason and one-step transition validation.

**Tests:** 1-5 rating bounds; optional tags/notes; one review per reviewer/worker/event; editable before Close and immutable after Close; Captain/Supervisor global category change without approval; one-step transitions only; mandatory promotion/demotion reason; old/new history; non-worker rejection; immediate eligibility refresh.

**Completion criteria:** Review cardinality/edit cutoff is enforced; authorized one-step category changes require a reason, apply globally, take effect immediately for future eligibility, and remain permanently attributable; reliability stays independent.

**Dependencies:** Phases 4, 5, and 11.

### Phase 13 - Reliability scoring

**Objective:** Compute and display a 0-100 score plus raw attendance, completed-event, late, absence, cancellation, and performance metrics using a versioned configuration.

**Files/components involved:** `features/reliability/**`, worker and management profile summaries.

**Database changes:** `reliability_configs`, `worker_reliability_snapshots`; recompute function/trigger or scheduled refresh; current summary projection.

**Tests:** Approved weighting fixtures; score bounds; zero-history worker; attendance/cancellation/review updates; config version reproducibility; proof that score never changes category.

**Completion criteria:** Raw metrics reconcile to source records, score is reproducible and versioned, and no automatic category mutation exists.

**Dependencies:** Phases 10-12. Reliability weights, minimum-sample behavior, cancellation effect, and recompute policy must be approved before Phase 13 starts.

### Phase 14 - Push notifications and alerts

**Objective:** Deliver FCM push while retaining in-app notification history and retryable delivery state in Supabase.

**Files/components involved:** `features/notifications/**`, FCM client setup, device registration, server notification dispatcher, Alerts tabs.

**Database changes:** `device_tokens`, `notification_deliveries/outbox`, delivery fields/indexes on existing notifications; claim/retry functions; cleanup schedule.

**Tests:** All blueprint notification types; exclude restricted/inactive, already-confirmed, and known-conflicting users from tier/vacancy targeting; prove Apply still revalidates; duplicate suppression; invalid-token retirement; retry/backoff; unread/read state; no service credential in Flutter.

**Completion criteria:** Tier, assignment, waitlist, leader, event, reminder, category, account, and vacancy events create durable in-app records and best-effort push delivery.

**Dependencies:** Phases 3, 5-6, 9-13.

### Phase 15 - Audit, histories, and basic reports

**Objective:** Expose authorized operational history and generate the MVP confirmed staffing list, attendance list, PDF export, and shareable text summary.

**Files/components involved:** `features/reports/**`, audit/history screens, export/share adapters.

**Database changes:** Security-invoker report views/read RPCs; no payroll tables; retention/index tuning for audit queries.

**Tests:** Category-sorted staffing list; attendance totals; allowance/wage display; PDF golden/layout checks; text snapshot; RLS on reports and histories.

**Completion criteria:** Authorized users can export accurate event lists and inspect required audit history; exports contain no unauthorized data and no payment processing.

**Dependencies:** Phases 5 and 9-14.

### Phase 16 - QA, security, and operational hardening

**Objective:** Validate the complete system under concurrent, offline, retry, authorization, and event-edit edge cases.

**Files/components involved:** integration tests, database load tests, RLS suite, CI workflow, observability/error reporting configuration.

**Database changes:** Performance indexes and policy/function corrections only through reviewed migrations; no business-rule changes.

**Tests:** Full acceptance suite; multi-client concurrency; RLS allow/deny matrix; offline stale-state UX; scheduler idempotency; notification retries; backup/restore rehearsal; `flutter analyze`; unit/widget/integration tests.

**Completion criteria:** Data-retention/privacy decisions have been approved before this phase starts; all blueprint acceptance scenarios pass; no capacity or RLS invariant fails under load; known operational alerts and recovery procedures are documented.

**Dependencies:** Phases 1-15.

### Phase 17 - Android release

**Objective:** Produce a signed Android release candidate and complete Play testing readiness while retaining iOS-compatible application architecture.

**Files/components involved:** Android application ID/name/icons, signing configuration, flavors, Firebase Android config, privacy disclosures, CI release workflow, release notes.

**Database changes:** Production environment configuration and seed of approved admin accounts/presets through reviewed migrations/admin tooling; never embed secrets.

**Tests:** Release-mode build; install/upgrade; supported-device smoke tests; notification deep links; network-loss recovery; accessibility; Play pre-launch report; production RLS smoke test with test accounts.

**Completion criteria:** Signed AAB is reproducible, secrets are externalized, Play internal testing passes, rollback plan exists, and production launch is explicitly approved.

**Dependencies:** Phase 16.

## Proposed implementation order

Execute phases strictly in numeric order. The critical dependency path is decisions -> app/database foundations -> identity -> events -> tier discovery -> conflict/booking -> cancellation/waitlist -> field operations -> quality systems -> notifications/reports -> hardening -> Android release.

FCM delivery is deliberately integrated after the domain events are reliable; earlier phases write durable notification/outbox records so no business transaction depends on push availability.

## Decision status and phase deadlines

### Closed for early implementation

The decisions needed to start Phases 1-2 are closed: phone/password authentication; operational-only Worker ID; role/category lifecycle; role-management authority; split event/recruitment status enums; `Asia/Kolkata`/12-hour/INR conventions; one-second final-seat arbitration; explicit waitlist; detention authority/effect; one-step category changes; field-leader worker/event scope; attendance correction; performance review shape; profile-completeness gate; waitlist withdrawal; and notification targeting.

These decisions are normative and are listed in the Finalized decision register. They are no longer implementation ambiguities.

### Explicitly deferred with deadlines

1. **Before Phase 3:** Decide whether password reset/recovery is included in V1, its recovery channel, phone-reassignment handling, minimum worker age if any, and photo file validation limits. These do not block Phases 1-2.
2. **Before Phase 4:** Decide the destination role/account state when a staff-only Captain/Supervisor role is revoked and no previous Worker role exists, plus how a Worker-to-field-role change affects existing assignments and waitlist entries.
3. **Before Phase 5:** Decide the explicit capacity-reduction/removal workflow, resolution rules for conflicts created by event time edits, and exact automatic/manual transition timing within the finalized split status model.
4. **Before Phase 13:** Approve reliability weights, minimum-sample behavior, cancellation contribution, performance aggregation, and recompute timing. Reliability remains non-blocking for foundation and Phases 1-12.
5. **Before Phase 14:** Approve reporting-reminder lead time and any configurable notification quiet-time behavior.
6. **Before Phase 16:** Approve data retention/deletion, privacy consent, profile-photo lifecycle, audit retention, backup/restore, and incident-response requirements. Production hardening cannot complete without these decisions.
