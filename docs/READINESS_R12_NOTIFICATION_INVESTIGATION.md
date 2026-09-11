# R12 Notification Investigation Update

Date: 2026-09-11
Project: hosted staging `vrpxpidnbhnuismbzroe`

## User-reported issue

A Super Admin created and published an event, assigned a friend as Captain, and the friend could see the event after opening the app but did not receive a push notification.

## Cause found

The event visibility path was working. The Captain could see the event in-app because `event_leaders` access and field event listing were correct.

Push delivery was not working for two backend reasons:

1. The hosted `dispatch-notifications` Edge Function was not deployed. The endpoint previously returned 404.
2. Published event leader assignments did not create notification rows when an event moved from draft to published with an existing Captain/Supervisor assignment.

Phone-side token registration is working in hosted staging: the database currently has 2 active device tokens.

## Fixes applied to hosted staging

- Pushed `20260911010100_readiness_r12_leader_push_notifications.sql`.
  - Adds leader notification creation when a draft event is published.
  - Adds leader notification creation when a leader is assigned to an already-active event.
- Pushed `20260911010200_readiness_r12_backfill_existing_leader_notifications.sql`.
  - Backfills notifications for already-published active events.
- Pushed `20260911010300_readiness_r12_schedule_notification_dispatcher.sql`.
  - Enables `pg_net`.
  - Schedules `oslava-dispatch-notifications` every minute through Supabase Cron.
- Deployed `dispatch-notifications` Edge Function to hosted staging.
- Updated the dispatcher to support `FCM_SERVICE_ACCOUNT_JSON` and `FCM_SERVICE_ACCOUNT_JSON_BASE64` so Firebase OAuth tokens are generated automatically instead of relying on a short-lived `FCM_AUTHORIZATION` value.
- Set hosted secret `FCM_PROJECT_ID=oslava-events-dev`.

## Current hosted state

- Active device tokens: 2
- Notifications: 1 `CAPTAIN_ASSIGNED`
- Deliveries: 1 `PENDING`
- Cron job: `oslava-dispatch-notifications`, active, every minute
- Dispatcher endpoint response: `FCM authorization, service account, or proxy shared secret is required`

## Remaining required action

Configure the Supabase secret `FCM_SERVICE_ACCOUNT_JSON_BASE64` or `FCM_SERVICE_ACCOUNT_JSON` from Firebase Console. Once that secret is set, the scheduled dispatcher should claim the pending delivery and send it to Firebase within about one minute.

Do not paste the service-account JSON into chat. It is sensitive.

## Verification performed

- `npx supabase db push --project-ref vrpxpidnbhnuismbzroe`
- `npx supabase functions deploy dispatch-notifications --project-ref vrpxpidnbhnuismbzroe --use-api --no-verify-jwt`
- `npx supabase secrets set FCM_PROJECT_ID=oslava-events-dev --project-ref vrpxpidnbhnuismbzroe`
- Hosted SQL checks for migrations, device tokens, notifications, deliveries, and cron job.
- Direct dispatcher endpoint check with `curl`.

## Not run

Local `npx supabase test db` was not run in this update because the local Supabase database was not running earlier in this investigation. Hosted staging was verified directly.

