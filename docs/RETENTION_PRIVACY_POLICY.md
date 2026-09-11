# Retention And Privacy Policy

## Scope

These V1 rules are approved Phase 16 production-hardening requirements. Server-side jobs and controlled RPCs enforce retention where the current schema can safely delete data without breaking staffing, event, or audit integrity.

## Retention Periods

| Data | V1 retention |
|---|---|
| Active profile and current Worker data | Retain while account is active |
| Role/category/account-action history | Retain while active and for 3 years after account closure |
| Assignments and event participation history | Retain for 3 years after event `CLOSED` |
| Attendance | Retain for 3 years after event `CLOSED` |
| Performance reviews/history | Retain for 3 years after event `CLOSED` |
| Historical reliability snapshots | Retain for 3 years |
| Current reliability state | Retain while account is active |
| In-app notifications | Retain for 180 days |
| Push outbox terminal delivery attempts | Retain for 90 days after terminal state |
| Invalid/revoked device tokens | Delete or irreversibly invalidate promptly once known invalid |
| Application/security audit logs | Retain for 3 years unless legal hold or active investigation applies |

`INACTIVE` is not equivalent to a verified user-requested deletion.

## Privacy Notice And Terms

Worker registration requires acknowledgement of the active Privacy Notice and Terms version. V1 stores user ID, version, and acceptance timestamp.

The notice must explain phone/password authentication and recovery, required profile data, private profile-photo storage, event applications and assignments, attendance recording, performance reviews, reliability scoring, approved role-based staff access, in-app and push notifications, retention periods, correction/erasure requests, and business/privacy contact information.

V1 does not include marketing consent or unrelated analytics tracking. Push permission remains the Android/iOS OS permission; denying it must not block login or core app use.

## Erasure Requests

For a verified account-erasure request:

- disable authentication/application access immediately through `account_status = INACTIVE`
- remove unnecessary current profile PII and active profile photo within 30 days unless legal hold applies
- anonymize or pseudonymize historical operational records where identity is no longer required
- preserve records required for operational disputes, security investigations, legal obligations, or legal hold
- apply normal deletion rules once a hold or legal requirement ends

Do not hard-delete rows when deletion would destroy staffing, event, or audit integrity.

## Profile Photos

Profile photos remain in the private `profile-photos` bucket.

When a Worker replaces a photo, upload and validate the new object first, atomically update the profile reference, then delete the old object. Audit metadata records that the photo changed; old photo objects are not retained for audit.

For merely `INACTIVE` accounts, retain the current photo because reactivation may occur. For verified erasure, delete the active photo within the 30-day erasure window unless a legal hold applies.

## Cleanup Operation

`public.run_retention_cleanup(p_dry_run boolean)` records every run in `retention_cleanup_runs` and writes an audit log. Dry runs count expired rows without deleting them. Non-dry runs delete expired notifications, expired terminal delivery attempts, invalidated device tokens, and expired audit logs that are not under legal hold. Operational history/anonymization cleanup must be expanded only with reviewed migrations and legal/business approval.
