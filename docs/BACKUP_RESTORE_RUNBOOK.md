# Backup And Restore Runbook

## Targets

- Desired RPO: 1 hour or less where the selected Supabase production plan supports PITR.
- Desired RTO: 4 hours or less.
- Routine backup retention target: about 30 days unless the selected provider plan defines another reviewed policy.

Do not claim these targets are satisfied until the actual Supabase production plan, PITR configuration, Storage backup strategy, and restore rehearsal prove them.

## Backup Scope

- Supabase Postgres database, including auth/application schemas and migrations.
- Supabase Storage objects, especially private `profile-photos`.
- Edge Functions source and deployment configuration.
- Runtime secrets and environment variables, restored from the approved secret manager or console, never from Git.
- Firebase/FCM project configuration and dispatcher environment.

## Restore Procedure

1. Detect and classify the restore need.
2. Preserve evidence and current database/storage state before destructive recovery.
3. Restore into an isolated non-production Supabase project first.
4. Validate migrations, RLS, auth users, Storage policies, Edge Functions, and notification dispatcher configuration.
5. Run the database test suite and Flutter smoke tests against the restored environment.
6. Decide whether to promote the restore, forward-fix, or roll back using a reviewed migration.
7. Restore secrets through the approved secure channel.
8. Verify application login, booking, waitlist, attendance, notifications, reports, and profile-photo access.
9. Record actual RPO/RTO, recovery actor, timestamps, and follow-up work.

## Migration Recovery

Prefer forward-fix migrations for production. Rollback is allowed only when the rollback script has been reviewed and data loss is understood. Never run `npx supabase db push` against production without explicit approval.

## Rehearsal Result

Phase 16 local rehearsal: local Supabase was stopped without backup, restarted cleanly from migrations, and `npx supabase db reset` reapplied all migrations through Phase 16. This validates local migration reproducibility only; a production PITR/storage restore rehearsal remains a launch dependency.
