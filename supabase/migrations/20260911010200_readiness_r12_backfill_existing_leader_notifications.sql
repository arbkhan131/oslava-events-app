-- R12 follow-up: backfill leader assignment notifications for events that were
-- already active before the R12 leader-notification triggers were installed.

DO $$
DECLARE
  event_record record;
BEGIN
  FOR event_record IN
    SELECT id
    FROM public.events
    WHERE event_status IN (
      'PUBLISHED'::public.event_status,
      'UPCOMING'::public.event_status,
      'IN_PROGRESS'::public.event_status
    )
  LOOP
    PERFORM private.enqueue_event_leader_notifications(event_record.id);
  END LOOP;
END $$;
