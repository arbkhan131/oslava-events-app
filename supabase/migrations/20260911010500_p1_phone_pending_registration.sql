-- P1 phone registration foundation: phone-auth helpers, pending registration
-- metadata, private ID-card storage, and approval/rejection RPCs.

DO $$
BEGIN
  CREATE TYPE public.worker_registration_type AS ENUM ('NEW_WORKER', 'OLD_WORKER');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.worker_experience_level AS ENUM ('NO_EXPERIENCE', 'SOME_EXPERIENCE', 'HIGHLY_EXPERIENCED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.worker_profiles
  ADD COLUMN IF NOT EXISTS registration_type public.worker_registration_type NOT NULL DEFAULT 'NEW_WORKER',
  ADD COLUMN IF NOT EXISTS requested_category public.worker_category,
  ADD COLUMN IF NOT EXISTS id_card_file_path text,
  ADD COLUMN IF NOT EXISTS experience_level public.worker_experience_level DEFAULT 'NO_EXPERIENCE';

ALTER TABLE public.worker_profiles
  DROP CONSTRAINT IF EXISTS worker_profiles_requested_category_old_only;
ALTER TABLE public.worker_profiles
  ADD CONSTRAINT worker_profiles_requested_category_old_only CHECK (
    (registration_type = 'OLD_WORKER'::public.worker_registration_type AND requested_category IS NOT NULL)
    OR (registration_type = 'NEW_WORKER'::public.worker_registration_type AND requested_category IS NULL)
  );

ALTER TABLE public.worker_profiles
  DROP CONSTRAINT IF EXISTS worker_profiles_id_card_path_not_blank;
ALTER TABLE public.worker_profiles
  ADD CONSTRAINT worker_profiles_id_card_path_not_blank CHECK (
    id_card_file_path IS NULL OR btrim(id_card_file_path) <> ''
  );

ALTER TABLE public.worker_profiles
  DROP CONSTRAINT IF EXISTS worker_profiles_experience_level_required;
ALTER TABLE public.worker_profiles
  ADD CONSTRAINT worker_profiles_experience_level_required CHECK (
    experience_level IS NOT NULL
  ) NOT VALID;

CREATE OR REPLACE FUNCTION private.phone_auth_email(raw_phone text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
DECLARE
  normalized text;
  digits text;
BEGIN
  normalized := private.normalize_phone(raw_phone);
  digits := regexp_replace(normalized, '[^0-9]', '', 'g');
  RETURN digits || '@phone.oslava.local';
END;
$$;

CREATE OR REPLACE FUNCTION public.phone_auth_email(phone_e164 text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
  SELECT private.phone_auth_email(phone_e164);
$$;

CREATE OR REPLACE FUNCTION private.id_card_file_path_is_valid(
  user_id uuid,
  file_path text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
  SELECT file_path ~ ('^' || user_id::text || '/[A-Za-z0-9._ -]+\.[A-Za-z0-9]{1,12}$');
$$;

DROP FUNCTION IF EXISTS public.complete_phone_worker_registration(
  text,
  text,
  text,
  text,
  date,
  text,
  numeric,
  text,
  public.worker_experience_level,
  public.worker_registration_type,
  public.worker_category,
  text
);

CREATE OR REPLACE FUNCTION public.complete_phone_worker_registration(
  full_name text,
  phone_e164 text,
  profile_photo_path text,
  id_card_file_path text,
  date_of_birth date,
  native_place text,
  height_cm numeric,
  education_status text,
  experience_level public.worker_experience_level,
  registration_type public.worker_registration_type,
  p_requested_category public.worker_category DEFAULT NULL,
  privacy_terms_version text DEFAULT NULL
)
RETURNS TABLE (
  user_id uuid,
  worker_number bigint,
  role public.app_role,
  category public.worker_category,
  requested_category public.worker_category,
  account_status public.account_status
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  auth_user_id uuid := auth.uid();
  auth_email text;
  normalized_phone text;
  issued_worker_number bigint;
  active_terms_version text;
  safe_full_name text := btrim(coalesce(full_name, ''));
  safe_initials text;
  initial_category public.worker_category;
BEGIN
  IF auth_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  SELECT public.active_privacy_terms_version()
  INTO active_terms_version;

  IF active_terms_version IS NULL THEN
    RAISE EXCEPTION 'active privacy terms version is required';
  END IF;

  IF privacy_terms_version IS NULL
     OR btrim(privacy_terms_version) <> active_terms_version THEN
    RAISE EXCEPTION 'current privacy terms acknowledgement is required';
  END IF;

  IF safe_full_name = ''
     OR btrim(coalesce(native_place, '')) = ''
     OR btrim(coalesce(education_status, '')) = '' THEN
    RAISE EXCEPTION 'all required registration fields must be complete';
  END IF;

  IF height_cm IS NULL OR height_cm <= 0 THEN
    RAISE EXCEPTION 'height is required';
  END IF;

  IF registration_type = 'OLD_WORKER'::public.worker_registration_type
     AND p_requested_category IS NULL THEN
    RAISE EXCEPTION 'old worker category is required';
  END IF;

  IF registration_type = 'NEW_WORKER'::public.worker_registration_type
     AND p_requested_category IS NOT NULL THEN
    RAISE EXCEPTION 'new worker category is assigned during approval';
  END IF;

  SELECT email INTO auth_email
  FROM auth.users
  WHERE id = auth_user_id;

  normalized_phone := private.normalize_phone(phone_e164);

  IF auth_email IS NULL
     OR lower(btrim(auth_email)) <> private.phone_auth_email(normalized_phone) THEN
    RAISE EXCEPTION 'phone authentication identity is required';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = auth_user_id) THEN
    RAISE EXCEPTION 'profile already exists';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.phone_e164 = normalized_phone) THEN
    RAISE EXCEPTION 'phone number already belongs to another profile';
  END IF;

  IF NOT private.is_worker_adult(date_of_birth, current_date) THEN
    RAISE EXCEPTION 'worker must be at least 18 years old';
  END IF;

  IF NOT private.profile_photo_path_is_valid(auth_user_id, profile_photo_path) THEN
    RAISE EXCEPTION 'invalid profile photo path';
  END IF;

  IF NOT private.id_card_file_path_is_valid(auth_user_id, id_card_file_path) THEN
    RAISE EXCEPTION 'invalid ID card file path';
  END IF;

  safe_initials := array_to_string(
    ARRAY(
      SELECT upper(left(part, 1))
      FROM regexp_split_to_table(safe_full_name, '\s+') AS part
      WHERE part <> ''
    ),
    ''
  );
  IF safe_initials = '' THEN
    safe_initials := upper(left(safe_full_name, 2));
  END IF;

  issued_worker_number := nextval('public.worker_number_seq');
  initial_category := CASE
    WHEN registration_type = 'OLD_WORKER'::public.worker_registration_type THEN p_requested_category
    ELSE 'F'::public.worker_category
  END;

  PERFORM set_config('app.bypass_identity_protection', 'on', true);

  INSERT INTO public.profiles (
    id,
    worker_number,
    role,
    full_name,
    initials,
    phone_e164,
    profile_photo_path,
    profile_completed_at,
    account_status
  )
  VALUES (
    auth_user_id,
    issued_worker_number,
    'WORKER'::public.app_role,
    safe_full_name,
    safe_initials,
    normalized_phone,
    profile_photo_path,
    now(),
    'PENDING_APPROVAL'::public.account_status
  );

  INSERT INTO public.privacy_terms_acceptances (user_id, version, accepted_at)
  VALUES (auth_user_id, active_terms_version, now());

  INSERT INTO public.worker_profiles (
    user_id,
    category,
    last_worker_category,
    date_of_birth,
    address,
    native_place,
    height_cm,
    education_status,
    has_previous_experience,
    experience_details,
    registration_type,
    requested_category,
    id_card_file_path,
    experience_level
  )
  VALUES (
    auth_user_id,
    initial_category,
    initial_category,
    date_of_birth,
    btrim(native_place),
    btrim(native_place),
    height_cm,
    btrim(education_status),
    experience_level <> 'NO_EXPERIENCE'::public.worker_experience_level,
    experience_level::text,
    registration_type,
    p_requested_category,
    id_card_file_path,
    experience_level
  );

  INSERT INTO public.worker_category_history (
    worker_id,
    old_category,
    new_category,
    action,
    actor_id,
    actor_role,
    reason,
    notes
  )
  VALUES (
    auth_user_id,
    NULL,
    initial_category,
    'INITIAL_ASSIGNMENT',
    auth_user_id,
    'WORKER'::public.app_role,
    'Worker registration pending approval',
    CASE
      WHEN registration_type = 'OLD_WORKER'::public.worker_registration_type THEN 'Old worker requested category ' || p_requested_category::text
      ELSE 'New worker assigned default F category'
    END
  );

  INSERT INTO public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    after_values,
    source
  )
  VALUES (
    auth_user_id,
    'WORKER'::public.app_role,
    'worker_registration_submitted',
    'profile',
    auth_user_id,
    jsonb_build_object(
      'worker_number', issued_worker_number,
      'role', 'WORKER',
      'category', initial_category,
      'requested_category', p_requested_category,
      'registration_type', registration_type,
      'account_status', 'PENDING_APPROVAL',
      'privacy_terms_version', active_terms_version
    ),
    'database'
  );

  PERFORM set_config('app.bypass_identity_protection', 'off', true);

  RETURN QUERY
  SELECT
    p.id,
    p.worker_number,
    p.role,
    wp.category,
    wp.requested_category,
    p.account_status
  FROM public.profiles p
  JOIN public.worker_profiles wp ON wp.user_id = p.id
  WHERE p.id = auth_user_id;
END;
$$;

DROP FUNCTION IF EXISTS public.review_worker_registration(
  uuid,
  boolean,
  public.worker_category,
  text
);

CREATE OR REPLACE FUNCTION public.review_worker_registration(
  p_target_user_id uuid,
  p_approved boolean,
  p_category public.worker_category DEFAULT NULL,
  p_reason text DEFAULT 'Registration reviewed'
)
RETURNS TABLE (
  user_id uuid,
  account_status public.account_status,
  category public.worker_category
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor_role public.app_role;
  target public.profiles%rowtype;
  target_worker public.worker_profiles%rowtype;
  final_category public.worker_category;
  new_status public.account_status;
  action_id uuid;
BEGIN
  actor_role := private.current_actor_role();

  IF actor_role IS NULL
     OR actor_role NOT IN (
       'SUPER_ADMIN'::public.app_role,
       'ADMIN'::public.app_role,
       'CAPTAIN'::public.app_role,
       'SUPERVISOR'::public.app_role
     ) THEN
    RAISE EXCEPTION 'only admins and field leaders can review registrations';
  END IF;

  IF btrim(coalesce(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'reason is required';
  END IF;

  SELECT * INTO target
  FROM public.profiles
  WHERE id = p_target_user_id
  FOR UPDATE;

  IF target.id IS NULL THEN
    RAISE EXCEPTION 'target profile not found';
  END IF;

  IF target.role <> 'WORKER'::public.app_role THEN
    RAISE EXCEPTION 'only worker registrations can be reviewed';
  END IF;

  IF target.account_status <> 'PENDING_APPROVAL'::public.account_status THEN
    RAISE EXCEPTION 'registration is not pending approval';
  END IF;

  SELECT * INTO target_worker
  FROM public.worker_profiles wp
  WHERE wp.user_id = p_target_user_id
  FOR UPDATE;

  IF target_worker.user_id IS NULL THEN
    RAISE EXCEPTION 'worker profile not found';
  END IF;

  final_category := CASE
    WHEN p_approved THEN coalesce(p_category, target_worker.requested_category, target_worker.category, 'F'::public.worker_category)
    ELSE target_worker.category
  END;
  new_status := CASE
    WHEN p_approved THEN 'ACTIVE'::public.account_status
    ELSE 'REJECTED'::public.account_status
  END;

  PERFORM set_config('app.bypass_identity_protection', 'on', true);

  UPDATE public.profiles
  SET account_status = new_status
  WHERE id = p_target_user_id;

  IF p_approved THEN
    UPDATE public.worker_profiles wp
    SET category = final_category,
        last_worker_category = final_category
    WHERE wp.user_id = p_target_user_id;
  END IF;

  INSERT INTO public.account_actions (
    target_user_id,
    old_status,
    new_status,
    action_type,
    reason,
    actor_id,
    actor_role
  )
  VALUES (
    p_target_user_id,
    target.account_status,
    new_status,
    CASE WHEN p_approved THEN 'APPROVE_REGISTRATION' ELSE 'REJECT_REGISTRATION' END,
    p_reason,
    auth.uid(),
    actor_role
  )
  RETURNING id INTO action_id;

  IF p_approved AND final_category IS DISTINCT FROM target_worker.category THEN
    INSERT INTO public.worker_category_history (
      worker_id,
      old_category,
      new_category,
      action,
      actor_id,
      actor_role,
      reason,
      notes
    )
    VALUES (
      p_target_user_id,
      target_worker.category,
      final_category,
      CASE
        WHEN private.category_rank(final_category) < private.category_rank(target_worker.category) THEN 'PROMOTION'
        ELSE 'DEMOTION'
      END,
      auth.uid(),
      actor_role,
      p_reason,
      'Category confirmed during registration approval'
    );
  END IF;

  INSERT INTO public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values,
    reason,
    source
  )
  VALUES (
    auth.uid(),
    actor_role,
    CASE WHEN p_approved THEN 'worker_registration_approved' ELSE 'worker_registration_rejected' END,
    'profile',
    p_target_user_id,
    jsonb_build_object('account_status', target.account_status, 'category', target_worker.category),
    jsonb_build_object('account_status', new_status, 'category', final_category, 'account_action_id', action_id),
    p_reason,
    'database'
  );

  PERFORM set_config('app.bypass_identity_protection', 'off', true);

  RETURN QUERY
  SELECT p.id, p.account_status, wp.category
  FROM public.profiles p
  JOIN public.worker_profiles wp ON wp.user_id = p.id
  WHERE p.id = p_target_user_id;
END;
$$;

DROP FUNCTION IF EXISTS public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer,
  integer
);

CREATE OR REPLACE FUNCTION public.worker_directory(
  p_search_text text DEFAULT NULL,
  p_account_filter public.account_status DEFAULT NULL,
  p_category_filter public.worker_category DEFAULT NULL,
  p_result_limit integer DEFAULT 50,
  p_result_offset integer DEFAULT 0
)
RETURNS TABLE (
  user_id uuid,
  worker_number bigint,
  full_name text,
  initials text,
  phone_e164 text,
  profile_photo_path text,
  role public.app_role,
  account_status public.account_status,
  category public.worker_category,
  last_worker_category public.worker_category,
  reliability_score numeric,
  reliability_state text,
  reliability_sample_count integer,
  reliability_present_count integer,
  reliability_late_count integer,
  reliability_absent_count integer,
  reliability_worker_cancellation_count integer,
  reliability_completed_event_count integer,
  reliability_performance_event_count integer,
  reliability_performance_average numeric,
  reliability_config_version integer,
  profile_completed_at timestamptz,
  date_of_birth date,
  address text,
  native_place text,
  height_cm numeric,
  education_status text,
  has_previous_experience boolean,
  experience_details text,
  registration_type public.worker_registration_type,
  requested_category public.worker_category,
  id_card_file_path text,
  experience_level public.worker_experience_level
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  safe_limit integer := least(greatest(coalesce(p_result_limit, 50), 1), 100);
  safe_offset integer := greatest(coalesce(p_result_offset, 0), 0);
  query_text text := '%' || lower(btrim(coalesce(p_search_text, ''))) || '%';
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  IF NOT private.can_view_worker_records() THEN
    RAISE EXCEPTION 'not authorized to view worker directory';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.worker_number,
    p.full_name,
    p.initials,
    p.phone_e164,
    p.profile_photo_path,
    p.role,
    p.account_status,
    wp.category,
    wp.last_worker_category,
    wp.reliability_score,
    wp.reliability_state,
    wp.reliability_sample_count,
    wp.reliability_present_count,
    wp.reliability_late_count,
    wp.reliability_absent_count,
    wp.reliability_worker_cancellation_count,
    wp.reliability_completed_event_count,
    wp.reliability_performance_event_count,
    wp.reliability_performance_average,
    wp.reliability_config_version,
    p.profile_completed_at,
    wp.date_of_birth,
    wp.address,
    wp.native_place,
    wp.height_cm,
    wp.education_status,
    wp.has_previous_experience,
    wp.experience_details,
    wp.registration_type,
    wp.requested_category,
    wp.id_card_file_path,
    wp.experience_level
  FROM public.profiles p
  JOIN public.worker_profiles wp ON wp.user_id = p.id
  WHERE (p_account_filter IS NULL OR p.account_status = p_account_filter)
    AND (p_category_filter IS NULL OR wp.category = p_category_filter)
    AND (
      btrim(coalesce(p_search_text, '')) = ''
      OR lower(p.full_name) LIKE query_text
      OR lower(p.initials) LIKE query_text
      OR p.phone_e164 LIKE '%' || btrim(p_search_text) || '%'
      OR p.worker_number::text LIKE '%' || btrim(p_search_text) || '%'
    )
  ORDER BY
    CASE WHEN p.account_status = 'PENDING_APPROVAL'::public.account_status THEN 0 ELSE 1 END,
    p.created_at DESC,
    p.full_name,
    p.worker_number
  LIMIT safe_limit
  OFFSET safe_offset;
END;
$$;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'worker-id-cards',
  'worker-id-cards',
  false,
  10485760,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'application/octet-stream'
  ]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

DROP POLICY IF EXISTS worker_id_cards_insert_own ON storage.objects;
CREATE POLICY worker_id_cards_insert_own
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'worker-id-cards'
    AND owner = auth.uid()
    AND name LIKE auth.uid()::text || '/%'
  );

DROP POLICY IF EXISTS worker_id_cards_select_own ON storage.objects;
CREATE POLICY worker_id_cards_select_own
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'worker-id-cards'
    AND owner = auth.uid()
    AND name LIKE auth.uid()::text || '/%'
  );

DROP POLICY IF EXISTS worker_id_cards_select_staff ON storage.objects;
CREATE POLICY worker_id_cards_select_staff
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'worker-id-cards'
    AND private.can_view_worker_records()
  );

DROP POLICY IF EXISTS worker_id_cards_update_own_pending ON storage.objects;
CREATE POLICY worker_id_cards_update_own_pending
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'worker-id-cards'
    AND owner = auth.uid()
    AND name LIKE auth.uid()::text || '/%'
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.account_status <> 'PENDING_APPROVAL'::public.account_status
    )
  )
  WITH CHECK (
    bucket_id = 'worker-id-cards'
    AND owner = auth.uid()
    AND name LIKE auth.uid()::text || '/%'
  );

DROP POLICY IF EXISTS worker_id_cards_service_all ON storage.objects;
CREATE POLICY worker_id_cards_service_all
  ON storage.objects
  FOR ALL
  TO service_role
  USING (bucket_id = 'worker-id-cards')
  WITH CHECK (bucket_id = 'worker-id-cards');

REVOKE ALL ON FUNCTION public.phone_auth_email(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phone_auth_email(text) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.complete_phone_worker_registration(
  text,
  text,
  text,
  text,
  date,
  text,
  numeric,
  text,
  public.worker_experience_level,
  public.worker_registration_type,
  public.worker_category,
  text
) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_phone_worker_registration(
  text,
  text,
  text,
  text,
  date,
  text,
  numeric,
  text,
  public.worker_experience_level,
  public.worker_registration_type,
  public.worker_category,
  text
) TO authenticated;

REVOKE ALL ON FUNCTION public.review_worker_registration(
  uuid,
  boolean,
  public.worker_category,
  text
) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_worker_registration(
  uuid,
  boolean,
  public.worker_category,
  text
) TO authenticated;

REVOKE ALL ON FUNCTION public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer,
  integer
) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.worker_directory(
  text,
  public.account_status,
  public.worker_category,
  integer,
  integer
) TO authenticated;

REVOKE ALL ON FUNCTION private.phone_auth_email(text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION private.id_card_file_path_is_valid(uuid, text) FROM public, anon, authenticated;







