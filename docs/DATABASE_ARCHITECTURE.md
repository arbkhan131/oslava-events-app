# Oslava Events Database Architecture

## Scope

This document proposes the PostgreSQL/Supabase data model needed to implement the blueprint. It is a design artifact, not a migration. Names may be refined during migration authoring, but the represented business facts and constraints must remain intact.

## Design principles

- PostgreSQL is authoritative for roles, categories, account state, event eligibility, capacity, conflicts, cancellation deadlines, waitlist priority, attendance, and audit.
- Store operational timestamps as `timestamptz` in UTC. The authoritative operational timezone is `Asia/Kolkata`; Flutter displays local times in 12-hour format.
- Use UUID primary keys for domain rows. Use a database sequence for the user-facing numeric Worker ID.
- Keep current state on the owning row and append immutable history for sensitive changes.
- Store money as `numeric(12,2)` plus ISO currency code; V1 currency is fixed to `INR` and never uses floating point.
- Use explicit enums or constrained lookup values for closed business vocabularies.
- Every exposed table has explicit grants and RLS. Sensitive writes use controlled functions.
- Durable notification/outbox rows are committed in the same transaction as the business event.

## Domain types

| Type | Values |
|---|---|
| `app_role` | `SUPER_ADMIN`, `ADMIN`, `CAPTAIN`, `SUPERVISOR`, `WORKER` |
| `worker_category` | `A`, `B`, `C`, `F` |
| `account_status` | `ACTIVE`, `SUSPENDED`, `DETAINED`, `BLACKLISTED`, `INACTIVE` |
| `event_status` | `DRAFT`, `PUBLISHED`, `UPCOMING`, `IN_PROGRESS`, `COMPLETED`, `CLOSED`, `CANCELLED` |
| `recruitment_status` | `NOT_OPEN`, `OPEN`, `FULL`, `CLOSED` |
| `tier_strategy` | `STANDARD`, `URGENT`, `EMERGENCY`, `CUSTOM` |
| `leader_role` | `CAPTAIN`, `SUPERVISOR` |
| `assignment_status` | `CONFIRMED`, `CANCELLED`, `REMOVED`, `COMPLETED` |
| `booking_result` | `PENDING`, `CONFIRMED`, `FULL`, `WAITLIST_AVAILABLE`, `WAITLISTED`, `LOCKED`, `CONFLICT`, `RESTRICTED`, `DUPLICATE`, `INVALID_REQUIREMENTS`, `EVENT_UNAVAILABLE`, `ERROR` |
| `waitlist_status` | `WAITING`, `PROMOTED`, `WITHDRAWN`, `SKIPPED`, `EXPIRED` |
| `attendance_status` | `NOT_MARKED`, `PRESENT`, `LATE`, `ABSENT` |
| `notification_type` | Blueprint notification names: `NEW_EVENT`, `TIER_OPENED`, `APPLICATION_CONFIRMED`, `WAITLIST_JOINED`, `WAITLIST_PROMOTED`, `CAPTAIN_ASSIGNED`, `SUPERVISOR_ASSIGNED`, `EVENT_FULL`, `EVENT_UPDATED`, `EVENT_CANCELLED`, `REPORTING_REMINDER`, `CATEGORY_CHANGED`, `ACCOUNT_DETAINED`, `VACANCY_REOPENED` |

PostgreSQL enum labels can be lowercase internally if the API mapping is consistent. Category rank must be defined once by a helper (`A=1`, `B=2`, `C=3`, `F=4`), never inferred alphabetically.

## Identity and people

### `auth.users`

Supabase Auth owns credentials and sessions. Every user authenticates with their unique normalized phone number plus password. Application code never reads password hashes. Numeric Worker ID is not accepted as an authentication credential. Password recovery is included in V1 through SMS OTP to the registered phone number; after OTP verification, the user can set a new password. SMS provider configuration is environment-specific and no provider secret is stored in Flutter.

### `profiles`

One row per authenticated user.

| Column | Proposed type and rule |
|---|---|
| `id` | `uuid primary key references auth.users(id)` |
| `worker_number` | `bigint unique`; generated operational/reference ID for users initially registered as Workers, never a login credential |
| `role` | `app_role not null` |
| `full_name` | `text not null` |
| `initials` | `text not null` |
| `phone_e164` | `text not null unique` after normalization |
| `profile_photo_path` | `text`; required before registration completes |
| `profile_completed_at` | `timestamptz`; set only when all required Worker fields, including photo, are complete |
| `account_status` | `account_status not null default 'ACTIVE'` |
| `created_at`, `updated_at` | `timestamptz not null` |

Constraints enforce unique normalized phone for every role, Worker registration starts `ACTIVE`, numeric Worker ID remains immutable operational data, and protected columns are not directly client-writable. Worker registration requires age 18 or older on the registration date. A former Worker may retain `worker_number` after becoming Captain/Supervisor so history and references remain stable.

### `worker_profiles`

One-to-one extension retained for current and former Workers so category and operational history survive role changes.

| Column | Proposed type and rule |
|---|---|
| `user_id` | `uuid primary key references profiles(id)` |
| `category` | nullable `worker_category`; non-null only while active role is `WORKER`, default `F` at registration |
| `last_worker_category` | `worker_category not null`; remembers the previous Worker category while another role is active |
| `date_of_birth` | `date not null` |
| `address` | `text not null` |
| `native_place` | `text not null` |
| `height_cm` | `numeric(5,2) not null check (> 0)` |
| `education_status` | `text not null` |
| `has_previous_experience` | `boolean not null` |
| `experience_details` | `text`; optional |
| `reliability_score` | `numeric(5,2) check (between 0 and 100)`; server-maintained summary |
| `reliability_config_version` | foreign key to the scoring configuration used |
| `created_at`, `updated_at` | `timestamptz not null` |

### `role_history`

Append-only role changes: user, old/new role, actor, reason, selected Worker-category restoration (nullable), and timestamp. Super Admin can create/revoke Admin, Captain, and Supervisor roles. Admin can create/revoke Captain and Supervisor roles but cannot manage Admin roles.

Role/category transitions are atomic. Changing Worker to any non-Worker role sets current `worker_profiles.category` to null while preserving `last_worker_category` and history. Returning to Worker restores `last_worker_category` by default; Admin may select a different restoration category, which is explicitly audited.

Revoking a directly provisioned staff-only Captain/Supervisor with no previous Worker profile must not implicitly create a Worker. The stored staff role is retained only as historical/admin identity metadata, `account_status` is set to `INACTIVE`, and inactive accounts have no operational privileges regardless of stored role. A later Worker conversion requires an explicit Admin/Super Admin onboarding operation with all required Worker profile data and starts at category `F` because there is no previous Worker category to restore.

When an active Worker becomes Captain/Supervisor, current category is cleared and prior category/history remain preserved. Existing confirmed Worker assignments are retained and receive an Admin-resolution review flag when the assignment table exists. Active waitlist entries are automatically withdrawn without penalty when the waitlist table exists; historical waitlist records remain and are not restored automatically if the user later returns to Worker.

### `worker_category_history`

Append-only category changes: worker, old category, new category, action (`PROMOTION`/`DEMOTION`/audited role-restoration override), actor ID, actor role snapshot, related event (nullable), mandatory reason, optional notes, timestamp. Normal V1 promotion/demotion changes exactly one step along `F<->C<->B<->A`; the current category changes in the same transaction. Category history remains when current category is null.

### `account_actions`

Append-only account-state transitions: target user, old/new status, action type, reason, related event, actor ID/role snapshot, optional release time/manual-release flag, notes, timestamp. Only Super Admin/Admin can Detain or Release. Detention blocks future applications but does not cancel confirmed assignments; each retained assignment receives an Admin-resolution flag. Staff-only role revocation is also recorded here as `STAFF_ACCESS_REVOKED` with `new_status = INACTIVE`.

### `phone_change_history`

Append-only phone reassignment audit: target user, old normalized phone, new normalized phone, Admin/Super Admin actor, actor role snapshot, mandatory reason, and timestamp. Phone reassignment is not self-service. Workers, Captains, and Supervisors cannot directly change their authentication phone number. Admin/Super Admin functions update the existing Auth user and `profiles.phone_e164` in one transaction; they must not create a second account. Normal Admins may change Worker/Captain/Supervisor phone numbers only. Admin phone numbers may only be changed by Super Admin. Super Admin phone changes require an appropriately privileged controlled flow.

### `password_recovery_challenges`

Tracks recovery initiation metadata without storing provider secrets: user, registered phone, provider environment (`local`, `development`, or `production`), provider-managed OTP hash/reference, expiry, consumption time, attempt count, and timestamps. The trusted SMS provider integration sends OTP to the registered phone and may differ by environment.

### Profile-photo storage

Profile photos are stored in a private Supabase Storage bucket named `profile-photos`. Allowed source MIME types are `image/jpeg`, `image/png`, and `image/webp`; maximum source upload size is 5 MB. Flutter should crop/resize/compress toward about 1 MB where practical, but storage/server policy remains authoritative for MIME type, size, ownership, and path restrictions.

### Authorization invariants

- Super Admin can create/revoke Admin, Captain, and Supervisor roles.
- Admin can create/revoke Captain and Supervisor roles and cannot create, revoke, or alter Admin/Super Admin roles.
- Captain/Supervisor can search and view all workers and worker history and can promote/demote Workers globally.
- Captain/Supervisor attendance and event-operation mutations require an active `event_leaders` assignment for the target event.
- Only Super Admin/Admin can Detain or Release a worker.
- Role, category, and account-state changes use controlled functions that update current state and append history atomically.

## Events and configuration

### `events`

| Column | Proposed type and rule |
|---|---|
| `id` | `uuid primary key` |
| `title`, `event_type`, `venue_name` | `text not null` |
| `maps_url` | validated `text`; optional coordinates may be separate `numeric` latitude/longitude |
| `event_date` | `date not null`; retained for calendar indexing |
| `timezone_name` | `text not null default 'Asia/Kolkata' check (= 'Asia/Kolkata')` in V1 |
| `reporting_at` | `timestamptz not null` |
| `work_starts_at` | `timestamptz not null` |
| `expected_ends_at` | `timestamptz not null` |
| `required_worker_count` | `integer not null check (> 0)` |
| `daily_wage` | `numeric(12,2) not null check (>= 0)` |
| `currency_code` | `char(3) not null default 'INR' check (= 'INR')` in V1 |
| `instructions`, `dress_code` | `text` |
| `event_status` | `event_status not null default 'DRAFT'` |
| `recruitment_status` | `recruitment_status not null default 'NOT_OPEN'` |
| `tier_strategy` | `tier_strategy not null` |
| `published_at`, `cancelled_at` | `timestamptz` |
| `created_by`, `updated_by`, `cancelled_by` | foreign keys to `profiles` |
| `created_at`, `updated_at` | `timestamptz not null` |
| `version` | integer optimistic-concurrency revision |

Constraints enforce `reporting_at <= work_starts_at < expected_ends_at`, `Asia/Kolkata`/INR V1 rules, and valid lifecycle/recruitment combinations. Lifecycle and recruitment transitions are handled separately: for example, recruitment may be FULL while event lifecycle is PUBLISHED or UPCOMING.

Admin/Super Admin may increase capacity normally. Ordinary event edits may reduce capacity only when the new `required_worker_count` is greater than or equal to active confirmed assignments. If requested capacity is lower, the ordinary edit is rejected; workers are never automatically selected or removed. The later management-removal workflow must explicitly select assignment(s), require a reason, write immutable history/audit, notify affected workers, mark assignments management-removed rather than deleting them, and carry no worker reliability penalty.

Event time edits may proceed while editable. When assignments exist, edits that create one-hour conflicts must be detected server-side, require explicit Admin/Super Admin confirmation, create `EVENT_TIME_CONFLICT` review flags with event/version/cause information, and never automatically cancel or prioritize either assignment.

Lifecycle timing is fixed in V1: `DRAFT` is worker-invisible; manual publish sets `PUBLISHED`, or `UPCOMING` immediately if the event is published on its event date after `Asia/Kolkata` midnight; automatic processing sets `PUBLISHED -> UPCOMING` at local event-date midnight and `PUBLISHED/UPCOMING -> IN_PROGRESS` at `reporting_at`; `IN_PROGRESS -> COMPLETED` is manual; `COMPLETED -> CLOSED` is manual; `DRAFT/PUBLISHED/UPCOMING` may be cancelled; `IN_PROGRESS` supports emergency cancellation with mandatory reason; `CANCELLED` and `CLOSED` are terminal.

Recruitment is independent: Phase 6 opens recruitment when the first tier becomes eligible; booking phases set FULL/OPEN from active confirmed counts; reporting time closes recruitment; cancellation forces recruitment `CLOSED`; completed/closed event lifecycle requires recruitment `CLOSED`; recruitment `CLOSED` is terminal in V1.

### `event_leaders`

Many-to-many event assignments: `(event_id, user_id, leader_role)` unique, assigned/removed metadata, and active flag or removal timestamp. A trigger/function validates that the profile role matches the assigned leader role. Events can have zero or more of each.

### `event_requirements`

Ordered structured requirements: event, name, description, `is_mandatory`, `acknowledgement_required`, `extra_allowance_amount`, currency, display order. Acknowledgement-required items must be acknowledged during Apply.

### `event_allowances`

Ordered event-level allowances not tied to one requirement: event, label, description, amount, currency. This preserves the event-level "additional allowances" field while `event_requirements.extra_allowance_amount` covers requirement-linked amounts.

### `tier_release_presets`

Versioned reusable preset rows with four non-negative offsets in minutes. Initial blueprint defaults:

| Preset | A | B | C | F |
|---|---:|---:|---:|---:|
| Standard | 0 | 30 | 60 | 180 |
| Urgent | 0 | 15 | 30 | 60 |
| Emergency | 0 | 5 | 10 | 15 |

Presets are copied into per-event rules at publication so later preset edits do not rewrite published event behavior.

### `event_tier_release_rules`

Exactly one row per event/category: release offset, calculated `opens_at`, `processed_at`, notification state, and source preset/version. `opens_at` is the eligibility truth; scheduler markers make notifications idempotent. Offsets must be non-decreasing in category order so access expands A -> B -> C -> F.

## Booking, assignment, and waitlist

### `booking_requests`

The application-attempt ledger: event, worker, client idempotency key, trusted `server_received_at`, worker-category snapshot, arbitration-window ID (nullable), result, result detail code, resulting assignment ID, and completion time. A booking request never creates a waitlist entry automatically. Apply also requires `profile_completed_at` and all required Worker fields/photo to remain complete.

Unique constraints:

- `(worker_id, event_id, client_idempotency_key)`.
- At most one unresolved request per worker/event.

### `booking_arbitration_windows`

Final-seat contention windows: event, `opened_at`, `closes_at = opened_at + interval '1 second'`, state, remaining-seat snapshot, and allocator timestamps. A window is half-open, `[opened_at, closes_at)`, so every request belongs to at most one window. When allocation reaches the final available seat, server-received requests admitted to the same one-second window compete in this order:

1. Current category rank A>B>C>F at allocation time.
2. Earliest trusted `server_received_at` within the same category.
3. Stable request UUID as a deterministic last tie-breaker.

The allocator revalidates every candidate before assignment and serializes on the event. Requests outside the window do not compete with that window.

### `requirement_acknowledgements`

Links a booking request to each acknowledged event requirement and records requirement version/snapshot plus timestamp. The Apply function compares the submitted set with all currently mandatory acknowledgement-required items.

### `assignments`

Authoritative reserved seats: event, worker, status, source (`DIRECT_APPLY`, `WAITLIST_PROMOTION`, or authorized management path if approved), confirmed timestamp, category-at-confirmation, booking request/waitlist source, cancellation-lock acknowledgement for late bookings, and completion timestamp.

Use a partial unique index for one active confirmed assignment per `(event_id, worker_id)`. Capacity is also enforced inside the event-locked allocation function; no client may insert an assignment directly.

### `waitlist_entries`

Event, worker, status, joined timestamp, category-at-join snapshot, current priority metadata, originating booking request (nullable reference only), promoted assignment, withdrawal timestamp, skip reason, and timestamps. One active waiting entry per worker/event. Rows are created only by explicit Join Waitlist action after recruitment is FULL. Promotion order uses the worker's current category at promotion, then original valid join time; the snapshot remains for audit. A worker may withdraw while WAITING without penalty. After PROMOTED, withdrawal is unavailable and assignment cancellation rules apply.

### `cancellations`

Append-only history: assignment, event, worker, actor, actor role, cancellation type (`WORKER`, `MANAGEMENT`, `EVENT`), reason, requested timestamp, deadline snapshot, whether within deadline, and refill result. Worker cancellation after the deadline is rejected and should be recorded as an audit event/attempt only if that retention is approved.

### `assignment_review_flags`

Admin-resolution queue for retained confirmed assignments. Stores assignment, flag type (`EVENT_TIME_CONFLICT`, `WORKER_DETAINED`, `WORKER_ROLE_CHANGED`, or `ROLE_CHANGED`), related assignment/event where applicable, detected time, cause/event version or account action, state, resolver, resolution notes, and resolution time. Event edits that create a one-hour conflict, detention after confirmation, and Worker-to-field-role changes create flags when the assignments table exists; none of these conditions silently cancels an assignment.

## Operations and quality

### `attendance`

One row per assignment: status default `NOT_MARKED`, marked by, marker role snapshot, marked timestamp, optional notes, and updated timestamp. An update trigger writes old/new values to audit. Only confirmed/completed assignments are eligible. Captain/Supervisor may create or correct attendance only for assigned events and only before event `CLOSED`; Admin/Super Admin may correct before or after `CLOSED`.

### `performance_reviews`

Event-based feedback: event, assignment/worker, reviewer, reviewer role snapshot, `stars smallint check (between 1 and 5)`, optional tags, optional notes, created timestamp, and updated timestamp. A unique `(reviewer_id, worker_id, event_id)` constraint permits one review per reviewer/worker/event. The same reviewer may edit that row until the event becomes `CLOSED`; no review edit is accepted after Close.

### `reliability_configs`

Versioned, effective-dated score configuration with named weights/penalties and minimum-sample rules. Published versions are immutable. Weighting, minimum-sample behavior, cancellation contribution, performance aggregation, and recompute timing remain intentionally deferred and must be approved before Phase 13; they do not block foundation work.

### `worker_reliability_snapshots`

Worker, computed score, configuration version, raw attendance/completed/late/absent/cancellation/performance metrics, source-through timestamp, and computed timestamp. Current score may be cached on `worker_profiles`; snapshots preserve reproducibility.

## Notifications and devices

### `device_tokens`

User, FCM token hash/token, platform, device identifier, active state, last-seen timestamp, and invalidated timestamp. Users may register only their own device. Tokens are never readable by other client users.

### `notifications`

Durable in-app record: recipient, type, title/body or template payload, related event/assignment, deduplication key, created/read timestamps. One recipient/deduplication key pair prevents duplicate user-visible alerts.

Tier-opened and vacancy-reopened audience queries exclude restricted/inactive workers in Phase 6. Once the assignment and conflict tables exist, the same targeting contract must also exclude workers already confirmed for the event and workers with a known one-hour conflict. This is notification targeting only; `apply_for_event` always revalidates profile completeness, account state, category eligibility, requirements, conflicts, and capacity.

### `notification_deliveries`

Outbox/delivery attempts: notification, channel, state, attempts, next attempt, claimed timestamp/worker, provider response code, sent/failed timestamps. Business transactions insert notifications; a trusted dispatcher sends FCM and retries independently.

## Audit

### `audit_logs`

Append-only critical-operation ledger: actor ID and role snapshot, action, entity type/ID, before/after JSON, reason, related event, request/correlation ID, timestamp, and trusted source. Client roles receive no insert/update/delete privileges. Dedicated domain-history tables remain the primary readable history; `audit_logs` is the security/operations record.

## Relationships

```text
auth.users 1---1 profiles 1---0..1 worker_profiles
profiles   1---* role_history / account_actions / worker_category_history
events     1---* event_leaders ---1 profiles
events     1---* event_requirements / event_allowances / event_tier_release_rules
events     1---* booking_requests / booking_arbitration_windows / assignments / waitlist_entries
workers    1---* booking_requests / assignments / waitlist_entries
assignments 1---0..1 attendance
assignments 1---* cancellations / performance_reviews / assignment_review_flags
workers    1---* worker_reliability_snapshots
profiles   1---* device_tokens / notifications
notifications 1---* notification_deliveries
```

## Required constraints and indexes

- Unique normalized phone for every Auth/application user; phone plus password is the only V1 login credential.
- Unique numeric Worker ID, generated only by the database.
- Worker registration rejects date of birth values that make the worker younger than 18 on the registration date.
- Phone reassignment is never self-service, is audited, and updates the existing account instead of creating a duplicate. Admin may change Worker/Captain/Supervisor phones only; Admin phones require Super Admin; Super Admin phone changes require an appropriately privileged controlled flow.
- Password recovery challenge metadata records the target environment while SMS provider secrets stay outside Flutter and outside exposed tables.
- Profile photos live in a private bucket with JPEG/PNG/WebP and 5 MB source-upload restrictions.
- Current `worker_profiles.category` is non-null exactly when active role is Worker; all new Workers start at F, role changes preserve `last_worker_category` and history.
- One event/category release rule and non-decreasing offsets.
- One-second final-seat arbitration windows use trusted server receipt times and deterministic category/time/UUID ordering.
- One active assignment and one active waitlist entry per worker/event.
- No worker can be both actively confirmed and actively waiting for the same event.
- One attendance row per assignment.
- One performance review per reviewer/worker/event, with stars constrained to 1-5.
- Event indexes on lifecycle status/recruitment status/reporting time, tier `opens_at`, active confirmed assignment count, waitlist priority/join time, worker confirmed-event time range, notification retry time, and history target/time.
- Foreign keys use deliberate delete behavior. Operational/audit rows should normally restrict deletion or retain a safe identity snapshot; production hard-delete policy is a governance decision.

## Derived read models

Prefer security-invoker views or read RPCs for:

- Worker event board state derived from separate event lifecycle and recruitment status: Available, Locked, Full, Confirmed, Completed, Cancelled.
- Event confirmed/vacancy and attendance counters.
- Worker own work/history summary.
- Admin dashboard event/category counts.
- Field roster grouped by category.
- Reliability raw metrics and current score.
- Export-ready staffing and attendance lists.

No derived client read model is an authorization or mutation authority.

## Deferred design gates

- Reliability weighting and calculation policy must be finalized before Phase 13. The schema reserves versioned configuration/snapshots without selecting weights now.
- Data retention/deletion, privacy consent, profile-photo lifecycle, audit retention, backup/restore, and incident-response rules must be finalized before Phase 16 production hardening.
- Other later-phase workflow details and their deadlines are tracked in `IMPLEMENTATION_PLAN.md`; none may be filled by an unreviewed schema assumption.

Phase 4 role/account decisions are closed. Assignment-review flagging for existing confirmed assignments is integrated when `assignments` is created, and management role-change withdrawal of active waitlist rows is integrated when `waitlist_entries` is created. Those are implementation dependencies, not open business-rule decisions.

## Migration grouping

1. Extensions, private schema, enums, sequences, grants defaults.
2. Profiles, worker extension, identity triggers, role/account/category history.
3. Events, leaders, requirements, allowances, tier presets/rules.
4. Durable notifications needed by tier/domain operations.
5. Booking requests, one-second arbitration windows, acknowledgements, assignments, review flags, explicit waitlist, cancellations.
6. Attendance, reviews, reliability configuration/snapshots.
7. Devices, push-delivery outbox/dispatcher support.
8. Audit triggers, read models, RPCs, scheduled jobs, Realtime publication.
9. Seed only approved initial Super Admin/Admin accounts and release presets through a secure bootstrap process.

Every migration group must include its grants/RLS and pgTAP tests. All development commands use `npx supabase ...`; remote application requires separate explicit approval and must never happen during planning.
