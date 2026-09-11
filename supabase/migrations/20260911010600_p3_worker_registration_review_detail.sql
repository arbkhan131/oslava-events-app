DROP FUNCTION IF EXISTS public.worker_profile_detail(uuid);

CREATE OR REPLACE FUNCTION public.worker_profile_detail(p_target_user_id uuid)
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
  date_of_birth date,
  address text,
  native_place text,
  height_cm numeric,
  education_status text,
  has_previous_experience boolean,
  experience_details text,
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
  reliability_computed_at timestamptz,
  profile_completed_at timestamptz,
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
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  IF p_target_user_id <> auth.uid() AND NOT private.can_view_worker_records() THEN
    RAISE EXCEPTION 'not authorized to view worker profile';
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
    wp.date_of_birth,
    wp.address,
    wp.native_place,
    wp.height_cm,
    wp.education_status,
    wp.has_previous_experience,
    wp.experience_details,
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
    wp.reliability_computed_at,
    p.profile_completed_at,
    wp.registration_type,
    wp.requested_category,
    wp.id_card_file_path,
    wp.experience_level
  FROM public.profiles p
  JOIN public.worker_profiles wp ON wp.user_id = p.id
  WHERE p.id = p_target_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.worker_profile_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.worker_profile_detail(uuid) TO authenticated;
