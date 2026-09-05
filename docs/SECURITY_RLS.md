# Oslava Events Security and RLS Design

## Security boundary

The distributed Flutter application is untrusted. Hiding a button is never authorization. Supabase Auth establishes identity; PostgreSQL grants, Row Level Security, constraints, and controlled functions establish authority.

The client contains only public Supabase configuration and FCM client configuration. Supabase service-role credentials, Auth admin credentials, FCM server credentials, and database credentials never ship in Flutter.

## Authorization model

- `auth.uid()` identifies the caller.
- Current role and account status are read from `profiles`, not trusted from client parameters.
- Current worker category is read from `worker_profiles` at the moment a rule is evaluated.
- Role/category/account changes must take effect without waiting for a stale client cache. JWT custom claims must not be the sole authority for mutable role or category state.
- Private helper functions answer questions such as `current_role()`, `is_admin()`, `is_super_admin()`, `is_field_leader()`, `is_assigned_leader(event_id)`, and `is_active_worker()`.
- Helpers that require `SECURITY DEFINER` live in a non-exposed `private` schema, pin `search_path = ''`, schema-qualify every object, and have explicit `EXECUTE` grants.

## Grants before policies

For every table in an exposed schema:

1. Revoke default privileges from `anon` and remove unnecessary operations from `authenticated`.
2. Enable RLS.
3. Grant only the SQL operations a client actually needs.
4. Add one policy per allowed operation and explicit deny tests for every role.

Sensitive tables should have no direct client mutation grant. Their public interface is an RPC with narrowly granted `EXECUTE` permission. Views exposed to clients use `security_invoker = true` or are replaced with policy-aware read RPCs.

## Capability matrix

| Capability | Super Admin | Admin | Captain | Supervisor | Worker |
|---|---:|---:|---:|---:|---:|
| Manage Admin accounts | Yes | No | No | No | No |
| Create/edit/cancel events | Yes | Yes | No | No | No |
| Assign Captains/Supervisors | Yes | Yes | No | No | No |
| View all workers/history | Yes | Yes | Yes | Yes | Own only |
| Mark attendance | Yes | Yes | Assigned scope | Assigned scope | No |
| Rate workers | Yes | Yes | Assigned/relevant scope | Assigned/relevant scope | No |
| Promote/demote workers | Yes | Yes | Yes; row scope to confirm | Yes; row scope to confirm | No |
| Detain/release workers | Yes | Yes | Blueprint says "Recommended yes" | Blueprint says "Recommended yes" | No |
| Apply/join waitlist | No | No | No | No | Yes |

Captain/Supervisor detention and exact worker-management row scope remain decision gates. The blueprint definitively grants direct promotion/demotion capability; implementation must not add an Admin approval step. Detention remains disabled for field roles until the "Recommended yes" wording is resolved.

## Table policy plan

### `profiles`

**Select**

- Worker: own full allowed profile only.
- Captain/Supervisor: all workers as required by the permission matrix, through a safe projection that excludes credential mapping and internal fields.
- Admin/Super Admin: all application profiles through a management projection.
- Confirmed worker: safe contact projection for leaders assigned to that event, only while the assignment/event context requires it.

**Insert**

- No general client insert. Registration flow/trigger creates the row.

**Update**

- No direct client update. `update_own_profile` permits only approved personal fields.
- Role, account status, login identifier, Worker ID, category, and reliability are excluded.

**Delete**

- No client role. Retention/deletion is an administrative governance process.

### `worker_profiles`

**Select:** Worker own; Captain/Supervisor all or approved scope; Admin/Super Admin all. Expose reliability and category, but not more personal detail than needed.

**Mutation:** No direct client DML. Registration, category-change, and reliability functions own writes.

### History tables

For `worker_category_history`, `account_actions`, and `role_history`:

- Worker reads own relevant history.
- Captain/Supervisor reads worker history within approved management scope.
- Admin/Super Admin reads all.
- No client inserts/updates/deletes. Controlled mutation functions append records.
- Role history management is Super Admin only.

### `events`

**Select**

- Worker: published/recruiting/full/upcoming/in-progress/completed/closed/cancelled event data designated worker-visible; never drafts. Cancelled-event visibility may be narrowed to affected users if later approved.
- Captain/Supervisor: worker-visible events plus assigned events and operational fields.
- Admin/Super Admin: all rows including drafts.

**Mutation:** No direct Worker/field mutation. Admin/Super Admin use event RPCs so validation, versioning, audit, conflict scanning, and notifications are inseparable.

### `event_leaders`

- Worker reads leader names/contact only through confirmed-assignment projection.
- Captain/Supervisor reads own assignments and authorized event context.
- Admin/Super Admin reads all.
- Assignment/removal only through Admin event RPC, with role validation and audit.

### Requirements, allowances, and tier rules

- A caller may read child rows only when permitted to read the parent event.
- Worker reads published-event rules needed to show requirements, allowances, open categories, and own countdown.
- Exact internal notification/scheduler markers are not exposed.
- Admin/Super Admin mutate only through event draft/publish/edit RPCs.

### `booking_requests`

- Worker reads own requests/results.
- Admin/Super Admin reads event operational records.
- Assigned Captain/Supervisor reads confirmed roster context, not rejected credential-like request metadata.
- Insert/update occurs only inside Apply/allocator functions.

### `assignments`

- Worker reads own assignments.
- Assigned Captain/Supervisor reads assignments for assigned events.
- Admin/Super Admin reads all.
- No direct client insert/update/delete. Apply, waitlist promotion, cancellation, attendance completion, and authorized removal functions mutate.
- Phase 8 creates the assignment table for conflict checks with direct client writes disabled; later mutation phases add the controlled write RPCs.

### `requirement_acknowledgements`

- Worker reads own acknowledgements.
- Admin/Super Admin and assigned field leaders read acknowledgements needed for the event roster.
- Only Apply creates immutable acknowledgement rows.

### `waitlist_entries`

- Worker reads own position/state, subject to the approved decision about exposing exact position.
- Admin/Super Admin reads all event entries.
- Captain/Supervisor reads waitlist only if operationally required for assigned events.
- Join, withdraw, skip, and promote happen only through RPCs.
- Apply never creates waitlist rows automatically; explicit Join Waitlist is required.

### `cancellations` and `assignment_conflict_flags`

- Worker reads own cancellation history and own unresolved conflict warnings.
- Assigned leaders read affected assigned-event records if required.
- Admin/Super Admin reads and resolves all.
- Writes are function-only and append-only except controlled conflict resolution state.
- Worker cancellation uses `cancel_assignment`, rejects after `reporting_at - 1 hour`, and writes successful cancellation history with refill results.

### `attendance`

- Worker reads own records.
- Assigned Captain/Supervisor reads event roster attendance and changes it via `set_attendance`.
- Admin/Super Admin reads all and may correct through the same RPC.
- Worker has no mutation path.
- Policy/function verifies event assignment and caller role at write time.

### `performance_reviews`

- Worker reads own review/history according to the approved visibility level.
- Captain/Supervisor reads and creates reviews only within approved event/worker scope.
- Admin/Super Admin reads and creates all authorized reviews.
- Reviews are immutable; corrections append or use an audited superseding record.

### Reliability tables

- Worker reads own current score, raw metrics, and approved history.
- Field/Admin roles read worker reliability within their worker-directory scope.
- No client mutations. Versioned configuration is Admin/Super Admin read; configuration changes require the approved authority and audit.
- Reliability functions cannot update worker category.

### Notifications and device tokens

- User reads/marks read only their own notifications.
- User inserts/refreshes/deactivates only their own device token through RPC.
- No user may read another user's token or delivery provider response.
- Notification and delivery rows are inserted/claimed/updated only by trusted functions/dispatcher.

### `audit_logs`

- No client insert/update/delete.
- Admin/Super Admin may read according to audit responsibility.
- Captain/Supervisor sees domain history, not unrestricted security logs.
- Audit owner/trigger design prevents normal application roles from altering old/new data.

## Controlled RPC authorization

Every mutation RPC must:

1. Reject unauthenticated callers unless it is the approved registration/login endpoint.
2. Derive caller ID/role/account state server-side.
3. Validate target IDs and current row state; never trust submitted role/category/status.
4. Lock rows in a consistent order for concurrency-sensitive operations.
5. Apply domain change and audit/outbox writes in one transaction.
6. Return a typed result code with no sensitive internal error detail.
7. Be idempotent when mobile retries are plausible.

Revoke function execution from `PUBLIC` and `anon` by default. Grant only the named registration/login surface to unauthenticated callers and rate-limit it at the Edge/API boundary. Grant each authenticated RPC explicitly.

## Storage policy for profile photos

Use a private bucket.

- Worker may upload/replace only the object path assigned to their own user ID through a controlled flow.
- Worker may read their own photo.
- Authorized staff may read worker photos needed for identification.
- Other workers cannot browse the bucket.
- Serve short-lived signed URLs or authenticated object requests; never expose a public bucket by default.
- File type, size, and image validation must be enforced server-side. Retention after account closure is a governance decision.

## Realtime security

Realtime subscriptions inherit table access concerns. Publish only tables/read models needed for:

- Event capacity/status updates.
- Own assignment/waitlist state.
- Assigned-event attendance counters.
- Own notification/account/category changes.

Do not publish device tokens, delivery attempts, login mappings, or unrestricted audit logs. Realtime payloads must not reveal rows the subscriber could not select normally.

## RLS test matrix

Each table/RPC needs pgTAP allow and deny tests for:

- `anon`.
- Active Worker owner and non-owner.
- Restricted Worker (`SUSPENDED`, `DETAINED`, `BLACKLISTED`, `INACTIVE`).
- Assigned and unassigned Captain.
- Assigned and unassigned Supervisor.
- Admin.
- Super Admin.
- Stale or malicious submitted role/category/account values.

High-risk assertions include:

- Worker cannot set category, role, account status, Worker ID, or reliability.
- Worker cannot insert/update an assignment, attendance, category history, account action, notification delivery, or audit row.
- Normal Admin cannot create/revoke Admin-level accounts or alter Super Admin.
- Unassigned field user cannot mutate an event roster.
- Draft events and other users' assignment/waitlist/notification rows do not leak.
- Restricted workers cannot Apply or join/promote from waitlist even if direct table access is attempted.
- Every security-definer function has pinned `search_path`, qualified names, explicit grants, and adversarial tests.

Run database checks locally with `npx supabase test db` after the local stack is started. Linked/remote tests or schema pushes require separate explicit authorization.

## Security review gates

- Review every exposed relation and function before Phase 3.
- Threat-model registration/login enumeration, brute force, and credential recovery before choosing numeric-ID auth mechanics.
- Re-run the full RLS matrix whenever a new table, view, role capability, or RPC is introduced.
- Verify the built Android artifact contains no service credentials before release.
- Complete privacy, data-retention, audit-retention, incident-response, and backup decisions before production.

## Technical references

- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase database functions and function privileges](https://supabase.com/docs/guides/database/functions)
- [Supabase database testing](https://supabase.com/docs/guides/database/testing)
