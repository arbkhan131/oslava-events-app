# Oslava Events UI Screen Map

## Navigation contract

One Flutter application selects a role shell after session/profile bootstrap. Route guards use the server-loaded current role; deep links are checked again when opened. UI visibility improves usability but never replaces RLS/RPC authorization.

Proposed top-level route groups:

```text
/auth/*
/worker/*
/field/*
/admin/*
```

Captain and Supervisor share `/field/*` screens and capabilities while retaining distinct role labels. Super Admin and Admin share `/admin/*`; Super Admin alone sees Admin-account controls.

## Shared authentication screens

| Route/screen | Users | Purpose and states | Backend interaction |
|---|---|---|---|
| `/splash` Session bootstrap | All | Restore session, load profile/role/account state, route to role shell; loading, offline, expired session, restricted account | Auth session + own profile read |
| `/auth/login` Login | All | Identifier and password; generic invalid-credential/rate-limit state | Approved identifier login adapter |
| `/auth/register` Worker registration | New workers | Required profile photo, name/initials, phone/WhatsApp, DOB, address/native place, height, education, experience, password | Registration flow; returns numeric Worker ID, F, ACTIVE |
| `/auth/registration-complete` Worker ID receipt | New worker | Prominently present generated numeric ID and continue into app | Registration result only |
| `/auth/recovery` Recovery | All | Deferred unless Phase 0 includes password reset in V1 | Approved recovery channel |
| `/restricted` Account state | Restricted user | Show Suspended/Detained/Blacklisted/Inactive status and permitted support/history information; no Apply | Own profile/account action projection |

Registration must not expose category selection or require Admin approval.

## Worker shell

Bottom navigation matches the blueprint: Home, Events, My Work, Alerts, Profile.

### Home

| Screen/section | Content/actions |
|---|---|
| Worker Home | Current category, reliability score plus raw summary, next confirmed work, available jobs, urgent notices |
| Next work | Reporting time, venue, countdown, maps action, cancellation deadline/state |
| Available jobs preview | Server-derived Available cards; never infer eligibility from cached category alone |
| Urgent notices | Event updates, cancellation, tier opening, detention/category notices |

### Events

| Route/screen | Required states and actions | Backend source/action |
|---|---|---|
| `/worker/events` Job board | Available, Locked for category, Full, Confirmed, Completed, Cancelled; refresh/realtime/offline states | Worker event-board read model |
| `/worker/events/:id` Event detail | Title/type, venue/maps, date, reporting/start/end, wage/allowances, structured requirements, dress code/instructions, vacancy count, open categories, own tier countdown | Event detail read model |
| Available action | Requirement acknowledgements and Apply button | `apply_for_event` |
| Locked action | Apply disabled; open categories and optional own-tier countdown | No mutation |
| Full action | Join Waitlist after explicit consent if Phase 0 confirms blueprint UI behavior | `join_waitlist` |
| Confirmed state | Leader names/contact, cancellation deadline/countdown, Cancel action until exact boundary | `cancel_assignment` |
| Late booking warning | If applying after cancellation deadline, require explicit acknowledgement that cancellation is already locked | Apply parameter validated server-side |
| Result dialog/state | Confirmed, Waitlist available/joined, Locked, Conflict, Restricted, requirements changed, event unavailable, error | Typed RPC result |

Vacancy and countdowns are informative. Apply remains enabled/disabled according to fresh server state, and the server may still return a different result after a race.

### My Work

| Route/screen | Content/actions |
|---|---|
| `/worker/work` | Tabs/segments for Confirmed, Completed, Cancelled; waitlist state may be a separate segment or card treatment |
| `/worker/work/:assignmentId` | Event/assignment details, reporting and leaders, requirements, cancellation deadline, attendance/history when available |
| Cancel confirmation | Shows exact deadline and consequence; disabled after server deadline; handles race with promotion/refill |
| Conflict warning | Flag created by later event edit; instructs worker to contact management, with no silent cancellation |

### Alerts

| Route/screen | Content/actions |
|---|---|
| `/worker/alerts` | In-app notification history, unread/read state, type/time, deep link to related event/work/profile |

Includes all worker-audience blueprint types: new/tier-opened, application confirmed, waitlist joined/promoted, event updated/cancelled, reminder, category changed, detained, and vacancy reopened.

### Profile

| Route/screen | Content/actions |
|---|---|
| `/worker/profile` | Photo, name, numeric Worker ID, phone, category, reliability 0-100 and raw metrics, account state |
| `/worker/profile/edit` | Only approved personal fields; no role/category/reliability/account controls |
| `/worker/profile/history` | Work and attendance history, cancellations, performance visibility as approved |
| `/worker/profile/category-history` | Promotion/demotion old/new, reason/details, actor role/name, event, timestamp |

## Captain/Supervisor shell

Bottom navigation matches the blueprint: Home, Events, Workers, Alerts, Profile.

### Field Home

| Route/screen | Content/actions |
|---|---|
| `/field/home` | Today's assigned events, confirmed/vacancy status, attendance counters, field alerts |
| Event shortcut | Opens assigned event operations directly |

### Assigned Events and attendance

| Route/screen | Content/actions | Backend action |
|---|---|---|
| `/field/events` | Assigned/relevant event list according to approved scope | Assigned-event projection |
| `/field/events/:id` | Event details, instructions, leaders, staffing status | Field event projection |
| `/field/events/:id/roster` | Confirmed workers, search, category grouping, Present/Late/Absent/Not Marked counters | Roster read model/realtime |
| Attendance row/action | Set or correct one of four attendance states, optional notes | `set_attendance` |
| Worker quick view | Photo/ID/category/reliability/history needed for field work | Safe worker projection |

### Workers

| Route/screen | Content/actions | Backend action |
|---|---|---|
| `/field/workers` | Search all workers or approved scope; filter category/account/reliability | Worker directory projection |
| `/field/workers/:id` | Profile, work/attendance/performance/category history | Scoped worker detail |
| Rate worker | Approved rating scale/details and related event | `record_performance_review` |
| Promote/demote | Current and target category, action, mandatory reason/details, related event, notes; no approval step | `change_worker_category` |
| Detain/release | Visible only if Phase 0 approves field authority; reason/event/notes/duration/manual release | `change_account_status` |

The category-change result updates immediately. Every repeated change appears as a distinct history record.

### Field Alerts and Profile

| Route/screen | Content/actions |
|---|---|
| `/field/alerts` | Leader assignment, event update/cancellation, event full, operational notifications |
| `/field/profile` | Own account details and role label |

## Admin/Super Admin shell

Navigation matches the blueprint: Dashboard, Events, Workers, Team, More.

### Dashboard

| Route/screen | Content/actions |
|---|---|
| `/admin/dashboard` | Today's events, slots required/filled/vacant, category counts, event state, attendance summary, conflicts and operational alerts |
| Event status drill-down | Opens event staffing/operations; realtime where useful |

### Events

| Route/screen | Content/actions | Backend action |
|---|---|---|
| `/admin/events` | Calendar/list, status filters, staffing counts, create action | Admin event projection |
| `/admin/events/new` | Complete draft form | `create_event_draft` |
| `/admin/events/:id` | Details, staffing, waitlist, leaders, requirements, tier plan, conflicts, history, export | Admin event projection |
| `/admin/events/:id/edit` | Venue/maps, reporting/start/end, count, wage, allowances, structured requirements, instructions, dress code, leaders, cancellation policy, tier strategy | `update_event` with version |
| Tier strategy editor | Standard/Urgent/Emergency/Custom A/B/C/F offsets; preview cumulative opening times | Saved/published by event RPC |
| Publish action | Validates complete form and initializes tier schedule | `publish_event` |
| Cancel action | Requires confirmation/reason; preserves records and notifies affected users | `cancel_event` |
| Capacity reduction flow | Blocks below confirmations and routes to explicit removal workflow after Phase 0 decision | Management removal RPC |
| Conflict resolution | Lists conflicts caused by time edits; explicit audited resolution only | Conflict resolution RPC |
| Export | Confirmed list by category, attendance list, PDF, shareable text | Report read RPC/export service |

### Workers

| Route/screen | Content/actions |
|---|---|
| `/admin/workers` | Search/filter by ID, name, phone, category, account status, reliability |
| `/admin/workers/:id` | Full authorized profile and work/attendance/performance/category/account history |
| Category action | Same direct audited promotion/demotion flow as field roles |
| Account action | Detain/release/suspend/blacklist/inactivate with reason/event/notes and approved release handling |

### Team

| Route/screen | Content/actions |
|---|---|
| `/admin/team` | Captains and Supervisors; create/change/deactivate according to approved identity workflow |
| `/admin/team/:id` | Role/account details, assignments, history |
| `/admin/admin-accounts` | Super Admin only; create/revoke Admin accounts and inspect role history |

Normal Admin must receive both a hidden/disabled navigation state and a server denial for Admin-account management.

### More

| Route/screen | Content/actions |
|---|---|
| `/admin/more` | Settings, notification presets, audit/history, reports |
| `/admin/reports` | Staffing, attendance, worker history, category distribution, staffing analytics |
| `/admin/audit` | Authorized critical action history with actor/entity/time filters |
| `/admin/settings` | Approved release presets, reminder timing, reliability config when authority is defined |

## Shared interaction states

Every network-backed screen must design for:

- Initial loading and pull-to-refresh.
- Empty state appropriate to role and filter.
- Offline cached data clearly marked as potentially stale.
- Realtime reconnecting state.
- Server-denied action after stale UI.
- Idempotent retry for Apply/cancel/attendance/category actions.
- Event version changed while editing.
- Account/category changed during an active session.
- Event became full, reopened, or cancelled while visible.
- Accessible text scaling, touch targets, contrast, and screen-reader labels.

Do not show a locally calculated success before the RPC commits. Optimistic presentation may show "Submitting," but Confirmed/Waitlisted/Cancelled/Attendance changed must come from the backend result.

## Route guard rules

- No session -> Auth routes only.
- Worker -> Worker shell; restricted account may view own history/status but cannot reach Apply actions.
- Captain/Supervisor -> Field shell.
- Admin/Super Admin -> Admin shell.
- Super Admin-only route performs both route guard and server authorization.
- A deep-linked event/worker route rechecks row access; unauthorized and missing are not distinguishable where that prevents enumeration.
- Role/account changes invalidate relevant providers and redirect immediately.

## Screen test coverage

- Golden/widget tests for each role shell and every worker event state.
- Route-guard tests for all roles and Super Admin-only paths.
- Widget tests for cancellation boundary, locked countdown, late-booking warning, requirement acknowledgement, and typed Apply results.
- Field tests for roster search/category grouping and all attendance states.
- Admin tests for full event form, multiple leaders, tier preset/custom editor, capacity warning, conflict warning, and cancellation.
- Realtime integration tests for vacancy, assignment/waitlist promotion, attendance counters, and account/category refresh.
- Offline tests verify cached display never claims a booking mutation succeeded.
- Android device tests cover maps deep links, notification deep links, photo selection/upload, and release-mode navigation.
