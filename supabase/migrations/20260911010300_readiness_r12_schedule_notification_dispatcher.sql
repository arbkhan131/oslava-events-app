-- R12 follow-up: run the notification dispatcher every minute in hosted staging.
-- The Edge Function is deployed with JWT verification disabled and performs no
-- delivery claims until FCM credentials are configured.

create extension if not exists pg_net with schema extensions;

DO $$
DECLARE
  existing_job record;
BEGIN
  FOR existing_job IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'oslava-dispatch-notifications'
  LOOP
    PERFORM cron.unschedule(existing_job.jobid);
  END LOOP;
END $$;

SELECT cron.schedule(
  'oslava-dispatch-notifications',
  '* * * * *',
  $$
  SELECT net.http_post(
    url := 'https://vrpxpidnbhnuismbzroe.supabase.co/functions/v1/dispatch-notifications',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
