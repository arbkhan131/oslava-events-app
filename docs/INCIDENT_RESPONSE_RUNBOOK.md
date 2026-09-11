# Incident Response Runbook

## Standard Flow

Every incident follows:

detect -> contain -> preserve evidence -> assess scope -> recover -> verify -> communicate where required -> post-incident review

Maintain an incident record with time detected, severity, systems/users affected, actions taken, actor, recovery result, and follow-up actions.

## Credential Leak

- Revoke affected Supabase, Firebase, API, or dispatcher credentials.
- Rotate secrets in the approved secret store or platform console.
- Redeploy affected Edge Functions/jobs only after configuration is corrected.
- Review audit logs, function logs, and notification delivery state.
- Verify no service-role or server credential entered Flutter, Git, logs, or user-visible output.

## Compromised User Or Admin Account

- Revoke sessions/tokens.
- Deactivate or detain the compromised privileged account as appropriate.
- Review role, phone, account-action, category, event, attendance, and audit histories.
- Reassign or revoke staff permissions through controlled audited flows.
- Restore access only after identity verification.

## Unauthorized Or RLS Data Exposure

- Disable or restrict affected RPCs, Edge Functions, or policies.
- Preserve relevant audit evidence and request logs.
- Patch with a reviewed migration and add deny/allow regression tests.
- Re-run the RLS allow/deny matrix before re-enabling.

## Bad Migration Or Data Corruption

- Stop dependent jobs/dispatchers.
- Preserve evidence and current state.
- Use a forward-fix migration where possible.
- Restore from verified backup/PITR when necessary.
- Re-run local and restored-environment migration/test suites.

## Notification Misfire

- Disable the notification dispatcher or affected Edge Function/job.
- Quarantine incorrect pending delivery rows.
- Identify recipient scope and message content.
- Preserve delivery outbox state and provider responses.
- Send correction/update only after business owner approval.

## Firebase/FCM Or Service Outage

- Keep durable in-app notifications available.
- Pause/retry dispatcher according to backoff rules.
- Preserve unsent delivery records.
- Resume only after provider health is confirmed.

## Lost Or Stolen Privileged Device

- Revoke sessions and invalidate device tokens.
- Review recent privileged actions.
- Rotate credentials if device stored administrative access.
- Require reauthentication before returning access.

Security/privacy incidents that legally require user or regulatory notification must be escalated to the business owner for reviewed notification handling. Do not hard-code legal deadlines without legal review.
