# Oslava Events Backend Logic

## Boundary

All decisions that reserve work, change worker standing, expose privileged data, or alter event operations run in PostgreSQL functions and/or trusted Supabase Edge Functions. Flutter requests an operation and renders its authoritative result.

Use database functions for transactional data rules. Use Edge Functions only where an external service or Auth Admin API is required, such as the approved identifier login/registration adapter and FCM dispatch.

## Common function rules

- Read `auth.uid()` and current role/account/category from the database.
- Accept a client-generated idempotency key for retryable commands.
- Use backend `now()` for release, conflict, and cancellation decisions.
- Lock worker/event/assignment rows in a documented consistent order.
- Return stable result codes, not raw constraint or policy errors.
- Commit domain state, audit history, and notification outbox together.
- Never accept a caller-supplied confirmed count, vacancy count, role, category rank, or eligibility result.

## Identity functions

### Register worker

Required outcome: one Auth account, one `profiles` row, one `worker_profiles` row, unique numeric Worker ID, category F, account ACTIVE, and immediate session access.

Proposed sequence after Phase 0 selects the Auth adapter:

1. Validate and normalize all required registration fields and phone number.
2. Validate profile photo object/token and uniqueness of normalized phone.
3. Create the Supabase Auth password identity through the approved server flow.
4. In the profile-creation transaction, allocate the next numeric Worker ID from a sequence.
5. Insert `profiles` as role Worker and state ACTIVE.
6. Insert `worker_profiles` as category F.
7. Write registration audit metadata.
8. Return the numeric Worker ID and an authenticated session/continuation.
9. If Auth and profile creation cannot share one transaction, use explicit compensation and a retry-safe registration record so neither orphan is silently retained.

### Login by identifier

The user enters numeric Worker ID or staff identifier plus password. A trusted adapter maps this to a Supabase-supported password identity, applies generic failure messages and rate limiting, and returns a normal Supabase session. Identifier lookup must not expose phone numbers or whether a particular worker exists.

### `update_own_profile`

Allow only blueprint personal fields approved for self-edit. Reject role, category, account status, reliability, identifier, and Worker ID even if present in a malicious payload.

## Event functions

### `create_event_draft`

Admin/Super Admin only. Validate required event fields, positive worker count, non-negative money, and time ordering. Create requirements, allowances, and leader assignments in one transaction. A draft is invisible to workers.

### `update_event`

Admin/Super Admin only, with expected version for optimistic concurrency.

1. Lock event and validate mutable status.
2. Reject capacity below active confirmed count unless an explicit removal workflow has already reduced assignments.
3. Validate leader roles and all child rows.
4. Detect significant field changes for notifications.
5. If reporting/end times change, scan active confirmed assignments using the one-hour predicate and create conflict flags; do not silently remove anyone.
6. If tier timing changes on a published event, apply the approved policy without revoking a tier already open.
7. Write before/after audit and affected-user notifications.

### `publish_event`

1. Lock and validate complete draft.
2. Copy selected preset offsets or validated custom offsets into four event release rows.
3. Calculate `opens_at` from publication time using non-decreasing offsets. Custom A may be delayed because the blueprint explicitly allows it.
4. Set published/recruiting state according to the finalized lifecycle mapping.
5. Mark immediately due tiers and create eligible `NEW_EVENT`/`TIER_OPENED` notifications without duplicates.
6. Write audit.

### `cancel_event`

Admin/Super Admin only. Set CANCELLED, retain assignments/history, close recruitment/waitlist according to approved states, notify affected users and leaders, and audit. Do not delete operational records.

## Tier release engine

### Eligibility predicate

`is_category_eligible(event_id, worker_id, at_time)` returns true only when:

- Event is visible/recruitable under its lifecycle state.
- Worker's current category has a release rule with `opens_at <= at_time`.
- Cumulative access follows category rank: opening B means A+B; opening C means A+B+C; opening F means all.
- Worker account is ACTIVE for application purposes.

The predicate does not reserve capacity.

### `process_due_tier_releases`

Run from Supabase Cron at a reviewed interval, with catch-up behavior after downtime.

1. Claim due unprocessed release rows using row locks and `skip locked`.
2. Mark each due row processed idempotently.
3. Re-read active confirmed count under the event lock.
4. If vacancies remain, create `TIER_OPENED` notifications for the newly eligible category audience.
5. If full, do not send the next-tier vacancy alert.
6. Update event/read-model state and audit scheduler outcome.

Eligibility derives from `opens_at`, so a delayed job cannot keep a category locked past its configured time. Scheduler processing exists for notifications and state materialization.

If capacity reopens later, refill the waitlist first. If still vacant, create `VACANCY_REOPENED` notifications for then-eligible workers according to the finalized targeting rule.

## Conflict predicate

For every active confirmed assignment of the worker, the candidate event is valid only if one of these is true:

```text
existing.expected_ends_at + 1 hour <= candidate.reporting_at
candidate.expected_ends_at + 1 hour <= existing.reporting_at
```

Equality at exactly one hour is allowed. Overlap and 59 minutes or less are blocked. The check runs inside Apply and waitlist promotion after the relevant worker is locked, preventing two concurrent applications by the same worker from both passing.

Cancelled and removed assignments do not conflict. The treatment of completed events and event-edit conflict resolution must follow the approved lifecycle decisions.

## Apply and capacity transaction

### `apply_for_event(event_id, acknowledgement_ids, accept_locked_cancellation, idempotency_key)`

Validation order mirrors the blueprint:

1. Authenticate and lock Worker profile; verify role Worker and account ACTIVE.
2. Lock/read event; reject cancelled, closed, or non-recruitable state.
3. Verify current category is open.
4. Return the prior result for a repeated idempotency key.
5. Reject an existing active assignment/request/waitlist state that makes this a duplicate.
6. Validate all mandatory acknowledgement-required requirements against the current event version.
7. Run the one-hour conflict predicate while the worker is locked.
8. If backend time is after the cancellation deadline, require explicit late-booking acknowledgement; the resulting assignment is immediately cancellation-locked.
9. Enter the approved final-seat arbitration mechanism.
10. Under the event allocation lock, count active confirmed assignments.
11. If below target, insert exactly one confirmed assignment and attendance row, record `CONFIRMED`, update FULL state when target is reached, and enqueue confirmation/full notifications.
12. If capacity is full, return `WAITLIST_AVAILABLE` or create a waitlist row only if Phase 0 approves automatic join.
13. Commit and return typed result plus assignment/waitlist/event counter data.

Database uniqueness and capacity tests are the final backstop. A displayed vacancy count is never accepted as input.

### Cross-tier final-seat arbitration

The finalized Phase 9 rule treats final-seat requests received within the same one-second arbitration window as competing. The server stores pending `booking_requests`, waits for the window to close, then allocates by category rank A>B>C>F, earliest trusted `server_received_at` inside the same category, then request UUID only as a deterministic final tie-breaker.

Requests outside the active one-second window do not compete with that window. Losing valid contenders receive `WAITLIST_AVAILABLE`; they are not automatically waitlisted.

## Waitlist functions

### `join_waitlist`

1. Verify authenticated ACTIVE Worker, recruitable/full event, current category eligibility, requirements, no active assignment, and no duplicate waiting entry.
2. Re-run conflict check or record that it will be authoritative again at promotion; the promotion check is mandatory either way.
3. Insert one WAITING row with category-at-join and immutable join time.
4. Enqueue `WAITLIST_JOINED` and return state/position according to the approved visibility rule.

### `promote_waitlist(event_id)`

Called in the same transaction as a valid cancellation/removal where possible, or by a retry-safe worker.

1. Lock event and verify active confirmed count is below target.
2. Lock candidate waiting rows in priority order based on current category A>B>C>F, then earliest valid join time.
3. For each candidate, revalidate account ACTIVE, current tier eligibility, requirements, no active assignment, and one-hour conflict.
4. Mark invalid candidates SKIPPED with a reason and continue.
5. Convert the first valid candidate to one confirmed assignment exactly once; mark waitlist PROMOTED.
6. Enqueue `WAITLIST_PROMOTED`; update event FULL if target restored.
7. Continue only if more than one vacancy exists.

Multiple refill workers must serialize on the same event lock or advisory key.

### `withdraw_waitlist`

Workers may withdraw a `WAITING` entry without penalty. A `PROMOTED` waitlist entry cannot be withdrawn; after promotion, normal assignment cancellation rules apply.

## Cancellation functions

### `cancel_assignment(assignment_id, reason, idempotency_key)`

Worker flow:

1. Authenticate and lock own active confirmed assignment and event.
2. Calculate deadline from current authoritative `reporting_at - interval '1 hour'`.
3. Allow when backend `now() <= deadline`; block when `now() > deadline`.
4. Mark assignment CANCELLED, append cancellation history, update event capacity/status, and audit.
5. Promote the highest-priority valid waitlist worker transactionally/retry-safely.
6. Enqueue affected notifications.

Management removal uses a separate RPC with explicit role, reason, audit, notification, and reliability semantics. It must not impersonate worker cancellation.

## Attendance

### `set_attendance(assignment_id, new_status, notes, idempotency_key)`

1. Require Admin/Super Admin or an assigned Captain/Supervisor within approved scope.
2. Verify assignment belongs to the event and is eligible for attendance.
3. Insert/update the single attendance row.
4. Audit old/new status, actor, role, and time.
5. Refresh counters and enqueue reliability recomputation.

`LATE` is an explicit status; it is not inferred only in Flutter. The approved correction window must be enforced here.

## Performance and category changes

### `record_performance_review`

Authorize the reviewer against event/worker scope, validate the approved rating model, append an immutable review, audit it, and enqueue reliability recomputation.

### `change_worker_category`

1. Require Captain, Supervisor, Admin, or Super Admin under approved scope.
2. Lock target Worker and verify role Worker.
3. Validate old/current category and approved transition rules.
4. Require the approved details; demotion reason is always mandatory and blueprint Appendix A says promotion/demotion details are mandatory/audited.
5. Update current category and append old/new history in one transaction.
6. Enqueue `CATEGORY_CHANGED`.
7. Make new category visible immediately to future eligibility and waitlist promotion checks.

Never update reliability as a side effect and never auto-change category from reliability.

## Account actions

### `change_account_status`

Admin/Super Admin, plus Captain/Supervisor only if approved. Validate scope and transition, update current state, append account action, enqueue `ACCOUNT_DETAINED` when relevant, and audit. Future Apply and waitlist promotion fail unless ACTIVE.

Existing confirmed assignments are never silently removed. Apply the Phase 0 decision to retain with warning, flag for management, or invoke an explicit audited removal workflow.

## Reliability

### `recompute_worker_reliability(worker_id, config_version)`

Read source facts through a fixed cutoff and calculate:

- Attendance rate.
- Completed event count.
- Late count/rate.
- Absence/no-show count/rate.
- Valid cancellation count/rate.
- Performance aggregate.
- Approved recency behavior, if V1 includes it.

Store raw values, configuration version, cutoff, and bounded 0-100 score in a snapshot; update current summary atomically. Exact weights and rating scale are blocked pending business approval. The function has no permission or code path to mutate category.

## Notifications

### Domain transaction behavior

Insert one `notifications` row per recipient with a deterministic deduplication key, plus a pending delivery row. The originating business transaction succeeds even if FCM is unavailable because push is asynchronous.

### Dispatcher Edge Function

1. Claim due deliveries with a lease.
2. Read active device tokens server-side.
3. Send FCM payload with a stable deep-link target.
4. Mark success, retryable failure with backoff, or permanent failure.
5. Retire invalid tokens and release expired claims.

Scheduled reporting reminders use backend time and deduplication keys. Reminder lead times are an unresolved product setting.

## Event lifecycle

The blueprint names these states but does not fully define every transition. Implement one reviewed transition function rather than scattered updates. At minimum:

- `DRAFT`: worker-invisible.
- `PUBLISHED`: publication accepted and tier plan initialized.
- `RECRUITING`: at least one tier open and vacancy remains.
- `FULL`: active confirmed count equals required count.
- `UPCOMING`: recruitment complete or near reporting, according to approved timing.
- `IN_PROGRESS`: event running.
- `COMPLETED`: work ended; attendance/reviews may remain open.
- `CLOSED`: administratively final.
- `CANCELLED`: terminal management cancellation, with retained history.

FULL may reopen to RECRUITING after cancellation/removal if refill does not restore capacity. Tier eligibility remains separate from lifecycle state.

## Stable result contract

Flutter should switch on typed codes such as:

| Code | Meaning |
|---|---|
| `CONFIRMED` | Seat allocated atomically |
| `WAITLIST_AVAILABLE` | Full; explicit waitlist join may be offered |
| `WAITLISTED` | Waitlist entry created |
| `LOCKED` | Worker's category is not open |
| `CONFLICT` | One-hour rule failed |
| `RESTRICTED` | Account is not ACTIVE |
| `INVALID_REQUIREMENTS` | Mandatory acknowledgement missing/stale |
| `DUPLICATE` | Existing active request/assignment/waitlist |
| `EVENT_UNAVAILABLE` | Draft/cancelled/closed/not recruitable |
| `CANCELLATION_LOCKED` | Backend time is after the deadline |
| `STALE_VERSION` | Event changed; refresh and retry |

Return safe display metadata such as deadline or conflicting event summary only when the caller is authorized to see it.

## Backend test strategy

- pgTAP unit tests for helpers, constraints, transitions, priority ordering, and RLS.
- Multi-connection integration tests for final-seat allocation, duplicate Apply, two simultaneous events for one worker, cancel/refill races, and scheduler claims.
- Property/invariant tests: confirmed count never exceeds target; one active assignment per worker/event; no active assignment and waitlist pair; all confirmed event pairs satisfy the buffer unless explicitly conflict-flagged by a later edit.
- Time-boundary tests use a controllable database clock parameter in test-only wrappers; production functions always use backend time.
- Edge Function tests cover Auth mapping, generic errors/rate limits, FCM retries, invalid tokens, and absence of service secrets in client output.

All local Supabase commands use `npx supabase ...`. No remote function deployment, database push, or linked test is part of this design step.

## Technical references

- [Supabase password authentication](https://supabase.com/docs/guides/auth/passwords)
- [Supabase Cron quickstart](https://supabase.com/docs/guides/cron/quickstart)
- [Supabase database functions](https://supabase.com/docs/guides/database/functions)
