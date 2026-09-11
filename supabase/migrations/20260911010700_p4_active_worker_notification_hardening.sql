CREATE OR REPLACE FUNCTION private.enqueue_notification_deliveries()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.notification_deliveries (
    notification_id,
    device_token_id,
    channel,
    state,
    next_attempt_at
  )
  SELECT
    NEW.id,
    dt.id,
    'fcm',
    'PENDING',
    now()
  FROM public.device_tokens dt
  JOIN public.profiles p ON p.id = dt.user_id
  WHERE dt.user_id = NEW.recipient_id
    AND dt.active
    AND p.account_status = 'ACTIVE'::public.account_status
  ON CONFLICT (notification_id, device_token_id, channel) DO NOTHING;

  UPDATE public.notifications
  SET delivery_created_at = coalesce(delivery_created_at, now())
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.deactivate_tokens_for_non_active_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.account_status <> 'ACTIVE'::public.account_status THEN
    UPDATE public.device_tokens
    SET active = false,
        invalidated_at = coalesce(invalidated_at, now()),
        updated_at = now()
    WHERE user_id = NEW.id
      AND active;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_deactivate_tokens_for_non_active ON public.profiles;
CREATE TRIGGER profiles_deactivate_tokens_for_non_active
  AFTER UPDATE OF account_status ON public.profiles
  FOR EACH ROW
  WHEN (OLD.account_status IS DISTINCT FROM NEW.account_status)
  EXECUTE FUNCTION private.deactivate_tokens_for_non_active_profile();

CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token text,
  p_platform text,
  p_device_id text DEFAULT NULL,
  p_app_environment text DEFAULT 'local'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  caller_status public.account_status;
  normalized_platform text := lower(btrim(coalesce(p_platform, 'other')));
  normalized_environment text := lower(btrim(coalesce(p_app_environment, 'local')));
  hashed_token text := encode(extensions.digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex');
  upserted_id uuid;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  SELECT account_status
  INTO caller_status
  FROM public.profiles
  WHERE id = caller_id;

  IF caller_status IS DISTINCT FROM 'ACTIVE'::public.account_status THEN
    RAISE EXCEPTION 'only active accounts can register device tokens';
  END IF;

  IF btrim(coalesce(p_token, '')) = '' THEN
    RAISE EXCEPTION 'device token is required';
  END IF;

  IF normalized_platform NOT IN ('android', 'ios', 'web', 'other') THEN
    normalized_platform := 'other';
  END IF;

  IF normalized_environment NOT IN ('local', 'development', 'production') THEN
    RAISE EXCEPTION 'invalid app environment';
  END IF;

  UPDATE public.device_tokens
  SET active = false,
      invalidated_at = now(),
      updated_at = now()
  WHERE token_hash = hashed_token
    AND user_id <> caller_id
    AND active;

  INSERT INTO public.device_tokens (
    user_id,
    token_hash,
    token,
    platform,
    device_id,
    app_environment,
    active,
    last_seen_at,
    invalidated_at
  )
  VALUES (
    caller_id,
    hashed_token,
    btrim(p_token),
    normalized_platform,
    nullif(btrim(coalesce(p_device_id, '')), ''),
    normalized_environment,
    true,
    now(),
    null
  )
  ON CONFLICT (user_id, token_hash) DO UPDATE
  SET token = excluded.token,
      platform = excluded.platform,
      device_id = excluded.device_id,
      app_environment = excluded.app_environment,
      active = true,
      last_seen_at = now(),
      invalidated_at = null,
      updated_at = now()
  RETURNING id INTO upserted_id;

  INSERT INTO public.notification_deliveries (
    notification_id,
    device_token_id,
    channel,
    state,
    next_attempt_at
  )
  SELECT
    n.id,
    upserted_id,
    'fcm',
    'PENDING',
    now()
  FROM public.notifications n
  WHERE n.recipient_id = caller_id
    AND n.created_at >= now() - interval '7 days'
  ON CONFLICT (notification_id, device_token_id, channel) DO NOTHING;

  RETURN upserted_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_notification_deliveries(
  p_worker_id text,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  delivery_id uuid,
  notification_id uuid,
  device_token_id uuid,
  recipient_id uuid,
  fcm_token text,
  notification_type public.notification_type,
  title text,
  body text,
  related_event_id uuid,
  deep_link_path text,
  attempts integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  safe_worker_id text := nullif(btrim(coalesce(p_worker_id, '')), '');
BEGIN
  IF safe_worker_id IS NULL THEN
    RAISE EXCEPTION 'worker id is required';
  END IF;

  RETURN QUERY
  WITH claimable AS (
    SELECT nd.id
    FROM public.notification_deliveries nd
    JOIN public.device_tokens dt ON dt.id = nd.device_token_id
    JOIN public.profiles p ON p.id = dt.user_id
    WHERE nd.attempts < nd.max_attempts
      AND dt.active
      AND p.account_status = 'ACTIVE'::public.account_status
      AND (
        (nd.state IN ('PENDING', 'FAILED') AND nd.next_attempt_at <= now())
        OR (nd.state = 'CLAIMED' AND coalesce(nd.claim_expires_at, nd.claimed_at + interval '2 minutes') <= now())
      )
    ORDER BY nd.next_attempt_at, nd.created_at
    LIMIT safe_limit
    FOR UPDATE OF nd SKIP LOCKED
  ),
  updated AS (
    UPDATE public.notification_deliveries nd
    SET state = 'CLAIMED',
        claimed_at = now(),
        claim_expires_at = now() + interval '2 minutes',
        claimed_by = safe_worker_id,
        attempts = nd.attempts + 1,
        updated_at = now()
    FROM claimable
    WHERE nd.id = claimable.id
    RETURNING nd.*
  )
  SELECT
    u.id,
    u.notification_id,
    u.device_token_id,
    n.recipient_id,
    dt.token,
    n.notification_type,
    n.title,
    n.body,
    n.related_event_id,
    n.deep_link_path,
    u.attempts
  FROM updated u
  JOIN public.notifications n ON n.id = u.notification_id
  JOIN public.device_tokens dt ON dt.id = u.device_token_id
  JOIN public.profiles p ON p.id = dt.user_id
  WHERE p.account_status = 'ACTIVE'::public.account_status;
END;
$$;

REVOKE ALL ON FUNCTION private.enqueue_notification_deliveries() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.deactivate_tokens_for_non_active_profile() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.register_device_token(text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.claim_notification_deliveries(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_device_token(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_deliveries(text, integer) TO service_role;
