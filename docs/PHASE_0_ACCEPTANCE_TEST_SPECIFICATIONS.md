# Phase 0 Acceptance Test Specifications

## Purpose

This document completes Phase 0 of the implementation plan. It converts the finalized business rules into acceptance-test specifications before application or database implementation begins.

The product blueprint, `AGENTS.md`, `IMPLEMENTATION_PLAN.md`, and `DATABASE_ARCHITECTURE.md` are the authority for these tests. Flutter presents state and invokes operations; Supabase/database tests own authorization and all security-critical business outcomes.

## Decision-closure verification

Phase 1 and Phase 2 are not blocked by unresolved business decisions.

| Required before Phase 1 or 2 | Closed decision | Evidence |
|---|---|---|
| Client architecture | One Flutter app, Android first, Riverpod, `go_router`, feature-first structure | Implementation plan architecture section |
| Authentication | Unique normalized phone number plus password for every role | Finalized decision 1 |
| Worker identity | Numeric Worker ID is generated operational/reference data, never a login credential | Finalized decision 1 |
| Roles and categories | Roles are separate from A/B/C/F; only active Workers have current category | Finalized decision 6 |
| Role administration | Super Admin manages Admin/Captain/Supervisor; Admin manages Captain/Supervisor only | Finalized decision 7 |
| Server authority | Supabase/database owns permissions, booking, capacity, conflicts, cancellation, waitlist, and eligibility | `AGENTS.md` rules 4-5 |
| Database discipline | Versioned migrations, explicit grants/RLS, auditable critical mutations, `npx supabase` only | `AGENTS.md` rules 6-11 |
| Event state foundation | Lifecycle and recruitment use separate enums | Finalized decision 16 |
| Localization foundation | `Asia/Kolkata`, 12-hour client time, INR | Finalized decision 12 |
| Capacity contention | One-second final-seat arbitration with category/time ordering | Finalized decision 2 |

**Verification result:** PASS. The remaining choices are intentionally deferred until their named owning phases and do not prevent Phases 1-2.

## Test layers and conventions

| Layer | Responsibility |
|---|---|
| `Supabase/database` | pgTAP, transaction, RLS, RPC, scheduler, and multi-session tests. This layer is authoritative for security and business decisions. |
| `Flutter unit` | Pure formatting, mapping, and controller handling of typed server results. Never reimplements authority rules. |
| `Flutter widget` | Form state, disabled/loading/error states, role-aware presentation, and accessible user feedback. |
| `Flutter integration` | End-to-end client flow against a controlled local backend/test double, including realtime and retry behavior. |

All timestamp fixtures use `Asia/Kolkata` display expectations and a controllable backend UTC clock. Money fixtures use INR. Database tests must assert both allowed behavior and denial of unauthorized direct access.

## Acceptance specifications

### Identity, profile, and roles

| ID | Specification | Responsible layer |
|---|---|---|
| AT-001 | Register a Worker with a unique normalized phone and password. Expect one authenticated identity, generated numeric Worker ID, ACTIVE account, F category, and immediate session access. | Supabase/database; Flutter integration |
| AT-002 | Attempt registration with a phone that normalizes to an existing phone. Expect one account only and a safe duplicate-phone error. | Supabase/database |
| AT-003 | Sign in each role with phone plus password. Attempt the same password flow using only a numeric Worker ID. Expect phone login success and Worker-ID login rejection. | Supabase/database; Flutter integration |
| AT-004 | Try direct client mutation of role, account status, Worker ID, current category, and reliability. Expect denial. | Supabase/database RLS/RPC |
| AT-005 | Try Apply while any required Worker field or profile photo is incomplete. Expect an authoritative profile-incomplete rejection; complete the profile and expect the request to proceed to normal validation. | Supabase/database; Flutter widget |
| AT-006 | Change a Worker to Captain or Supervisor. Expect current category null, last Worker category retained, category history preserved, and an audit record. Return the user to Worker without an override and expect the prior category restored. | Supabase/database |
| AT-007 | Return a former Worker to Worker with an Admin-selected restoration category. Expect the selected result and an explicit audited restoration override. | Supabase/database |
| AT-008 | Verify role authority: Super Admin can create/revoke Admin, Captain, and Supervisor roles; Admin can create/revoke Captain/Supervisor only; neither can alter Super Admin outside its authority. | Supabase/database RLS/RPC |
| AT-009 | Verify Captain/Supervisor can search and view all Workers and worker history, but cannot create/revoke staff roles or Detain/Release. | Supabase/database RLS; Flutter widget |

### Event state, tiers, and discovery

| ID | Specification | Responsible layer |
|---|---|---|
| AT-010 | Create a valid event in `Asia/Kolkata` with INR wages/allowances. Verify `reporting_at <= work_starts_at < expected_ends_at`, 12-hour client display, and distinct `event_status`/`recruitment_status`. | Supabase/database; Flutter widget |
| AT-011 | Try to create/edit an event as Worker, Captain, or Supervisor. Expect denial. Verify Admin/Super Admin can perform allowed event mutations. | Supabase/database RLS/RPC |
| AT-012 | Publish Standard, Urgent, Emergency, and Custom tier plans. Verify A/B/C/F opening times, including a deliberately delayed custom A. | Supabase/database |
| AT-013 | At each tier opening, verify eligibility is cumulative: opening B retains A, opening C retains A+B, and opening F retains A+B+C. | Supabase/database |
| AT-014 | A Worker below the open tier can view full event detail as Locked but cannot Apply. When eligible, the same event becomes Available without client-side category calculation deciding the mutation. | Supabase/database; Flutter widget/integration |
| AT-015 | When recruitment is FULL at a later tier threshold, process the tier release. Expect no next-tier vacancy notification. If a vacancy later remains after waitlist processing, notify only currently eligible targets. | Supabase/database scheduler |
| AT-016 | For tier/vacancy notices, exclude restricted/inactive Workers, already-confirmed Workers, and Workers with a known conflict. Verify a later Apply still revalidates every rule. | Supabase/database; Flutter integration |

### Booking, capacity, conflict, and cancellation

| ID | Specification | Responsible layer |
|---|---|---|
| AT-017 | Submit two Apply requests with the same idempotency key. Expect one booking request and one authoritative result. | Supabase/database; Flutter integration retry handling |
| AT-018 | Apply with missing mandatory requirement acknowledgement. Expect `INVALID_REQUIREMENTS`; acknowledge all required current requirements and expect normal booking validation. | Supabase/database; Flutter widget |
| AT-019 | With multiple vacancies, accept eligible valid applications without exceeding required capacity. When the final vacancy is reached, expect `recruitment_status = FULL`. | Supabase/database multi-session |
| AT-020 | With one final seat, submit A and C requests inside the same one-second arbitration window. Expect A confirmed and C receives the authoritative non-confirmed result. | Supabase/database multi-session |
| AT-021 | With one final seat, submit two same-category requests inside the same window. Expect earliest server-received request to win; UUID is deterministic only when receipt timestamps tie. | Supabase/database multi-session |
| AT-022 | Submit a request outside a closed final-seat arbitration window. Expect it not to compete with the previous window. | Supabase/database multi-session |
| AT-023 | Confirm event A ending 4:00 PM and apply for event B reporting at 5:00 PM. Expect success. Repeat with A ending 4:30 PM or after B reporting time. Expect `CONFLICT`. | Supabase/database |
| AT-024 | Edit an event time so existing confirmed assignments violate the one-hour rule. Expect retained assignments plus an Admin review flag; no silent cancellation. | Supabase/database |
| AT-025 | For a 4:00 PM reporting time, cancel at 2:45 PM and exactly 3:00 PM. Expect success. Cancel at 3:01 PM. Expect `CANCELLATION_LOCKED`. | Supabase/database; Flutter widget boundary messaging |
| AT-026 | Apply after the cancellation deadline without acknowledgement. Expect a late-booking warning/result requiring acknowledgement. With acknowledgement, allow normal Apply validation but keep cancellation locked on confirmation. | Supabase/database; Flutter widget |

### Waitlist and detention

| ID | Specification | Responsible layer |
|---|---|---|
| AT-027 | Attempt Apply to a Full event. Expect `WAITLIST_AVAILABLE` and no waitlist row. Invoke explicit Join Waitlist and expect one WAITING row and `WAITLIST_JOINED`. | Supabase/database; Flutter widget/integration |
| AT-028 | Attempt duplicate Join Waitlist. Expect one active waiting row only. | Supabase/database |
| AT-029 | Withdraw while WAITING. Expect WITHDRAWN state, no cancellation record, no reliability penalty, and no future promotion. | Supabase/database; Flutter integration |
| AT-030 | Promote a waiting worker, then attempt waitlist withdrawal. Expect denial; normal assignment cancellation policy applies instead. | Supabase/database |
| AT-031 | Refill a vacancy from waiting A, B, C, and F Workers. Expect current category priority A>B>C>F, then earliest valid join time within a category. | Supabase/database multi-session |
| AT-032 | Before promoting a queued Worker, make the account restricted, introduce a conflict, or invalidate requirements. Expect the candidate skipped with an audit reason and the next valid candidate considered. | Supabase/database |
| AT-033 | Have Admin Detain a Worker with no assignment. Expect future Apply and waitlist promotion blocked. Try the same mutation as Captain/Supervisor. Expect denial. | Supabase/database RLS/RPC |
| AT-034 | Detain a Worker with confirmed assignments. Expect assignments retained, one Admin review flag per unresolved assignment, and no duplicate flag on an idempotent retry. | Supabase/database |

### Attendance, performance, category, and reliability boundaries

| ID | Specification | Responsible layer |
|---|---|---|
| AT-035 | An assigned Captain/Supervisor marks NOT_MARKED, PRESENT, LATE, and ABSENT on an event roster. Expect one attendance row per assignment, realtime counter change, and old/new audit on every edit. | Supabase/database; Flutter integration |
| AT-036 | An unassigned Captain/Supervisor attempts attendance/event-operation mutation. Expect denial. | Supabase/database RLS/RPC |
| AT-037 | Before event Close, Captain/Supervisor/Admin/Super Admin correct attendance. After Close, expect Captain/Supervisor denial and Admin/Super Admin success. | Supabase/database; Flutter widget |
| AT-038 | Captain/Supervisor promotes or demotes any Worker globally by exactly one step, with a mandatory reason. Expect current category, immutable history, actor role, and future eligibility update. | Supabase/database; Flutter integration |
| AT-039 | Attempt a skipped category transition, category change on a non-Worker, or category change without reason. Expect denial. | Supabase/database |
| AT-040 | Create a 1-5-star review with optional tags/notes. Expect exactly one review per reviewer/worker/event; edit it before event Close and reject edit after Close. | Supabase/database; Flutter widget |
| AT-041 | Update attendance, cancellation, and performance source facts. Expect a queued/recomputed reliability result when Phase 13 exists, but no automatic category change. | Supabase/database |

### Security, audit, presentation, and release boundaries

| ID | Specification | Responsible layer |
|---|---|---|
| AT-042 | Attempt direct insert/update/delete of assignments, attendance, category history, account actions, notification deliveries, and audit rows as a client. Expect denial; only approved RPCs can mutate them. | Supabase/database RLS/grants |
| AT-043 | For every critical mutation above, verify actor, actor role, target, old/new values where relevant, reason, related event, and timestamp are retained in domain history/audit. | Supabase/database |
| AT-044 | Supply stale client vacancy/category/account values to Apply, cancellation, waitlist, and category-change requests. Expect server-derived outcome, not client-supplied authority. | Supabase/database; Flutter integration |
| AT-045 | Render server result codes for Locked, Conflict, Restricted, Full/Waitlist Available, Confirmed, and Cancellation Locked. Expect clear UI state with no premature local success claim. | Flutter unit/widget |
| AT-046 | Verify role route guards and deep links hide unavailable experiences, then verify server access denial still protects direct requests. | Flutter integration; Supabase/database RLS |
| AT-047 | Verify application configuration and release output contain no service-role key, database password, or server credential. | Flutter integration/release inspection |

## Execution mapping

| Future phase | Acceptance IDs to automate before phase completion |
|---|---|
| Phase 1 | AT-045, AT-046, AT-047 |
| Phase 2 | AT-004, AT-008, AT-011, AT-042, AT-043, AT-044 |
| Phase 3 | AT-001 to AT-009 |
| Phase 4 | AT-009, AT-033, AT-034, plus role/category restoration coverage |
| Phase 5 | AT-010, AT-011, AT-024 |
| Phase 6 | AT-012 to AT-016 |
| Phase 7 | AT-014, AT-015, AT-027, AT-045 |
| Phase 8 | AT-023, AT-024 |
| Phase 9 | AT-017 to AT-022 |
| Phase 10 | AT-025 to AT-032 |
| Phase 11 | AT-035 to AT-037 |
| Phase 12 | AT-038 to AT-040 |
| Phase 13 | AT-041 after weighting is approved |
| Phase 14 | AT-015, AT-016 and delivery/retry tests |
| Phase 16 | Full acceptance suite, including AT-042 to AT-047 |

## Explicitly deferred decisions and deadlines

| Decision | Required before | Effect on Phase 0 |
|---|---|---|
| Password reset/recovery, phone reassignment, minimum Worker age, and profile-photo file limits | Phase 3 | Documented as deferred; does not block Phases 1-2. |
| Staff-only Captain/Supervisor role revocation destination and Worker-to-field-role effect on existing assignments/waitlist rows | Phase 4 | Documented as deferred; role authority model is sufficient for Phases 1-2. |
| Capacity-reduction/removal workflow, event-time-conflict resolution, and exact automatic/manual lifecycle transition timing | Phase 5 | Documented as deferred; split state model is closed. |
| Reliability weights, minimum sample, cancellation contribution, performance aggregation, and recompute timing | Phase 13 | Intentionally deferred; no scoring formula is selected. |
| Reporting reminder lead time and notification quiet-time behavior | Phase 14 | Documented as deferred. |
| Retention/deletion, privacy consent, profile-photo lifecycle, audit retention, backup/restore, and incident response | Phase 16 | Intentionally deferred; production hardening cannot complete without it. |

## Phase 0 result

Phase 0 is complete when this document and the completion record in `IMPLEMENTATION_PLAN.md` remain current, all Phase 1-2 decisions are closed, every acceptance specification has a responsible layer, and every deferred item has a phase deadline. No acceptance tests are executed in Phase 0 because no Flutter feature, migration, RPC, or local database test fixture is created in this phase.
