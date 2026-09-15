-- Fix attendance roster return type after the hosted staging function started
-- returning performance_reviews.stars as smallint for an integer result column.

create or replace function public.event_attendance_roster_v2(
  p_event_id uuid,
  p_search_text text default null
)
returns table (
  assignment_id uuid,
  event_id uuid,
  worker_id uuid,
  worker_number bigint,
  full_name text,
  phone_e164 text,
  profile_photo_path text,
  category_at_confirmation public.worker_category,
  current_category public.worker_category,
  assignment_status public.assignment_status,
  attendance_status public.attendance_status,
  marked_by uuid,
  marker_role public.app_role,
  marked_at timestamptz,
  notes text,
  total_count integer,
  filtered_count integer,
  not_marked_count integer,
  present_count integer,
  late_count integer,
  absent_count integer,
  review_id uuid,
  review_stars integer,
  review_tags text[],
  review_notes text,
  review_updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_view_event_operations(p_event_id) then
    raise exception 'not authorized for event operations';
  end if;

  return query
  with base as (
    select
      a.id as assignment_id,
      a.event_id,
      p.id as worker_id,
      p.worker_number,
      p.full_name,
      p.phone_e164,
      p.profile_photo_path,
      a.category_at_confirmation,
      wp.category as current_category,
      a.status as assignment_status,
      coalesce(att.status, 'NOT_MARKED'::public.attendance_status) as attendance_status,
      att.marked_by,
      att.marker_role,
      att.marked_at,
      att.notes,
      pr.id as review_id,
      pr.stars::integer as review_stars,
      pr.tags as review_tags,
      pr.notes as review_notes,
      pr.updated_at as review_updated_at
    from public.assignments a
    join public.profiles p on p.id = a.worker_id
    left join public.worker_profiles wp on wp.user_id = p.id
    left join public.attendance att on att.assignment_id = a.id
    left join public.performance_reviews pr on pr.assignment_id = a.id and pr.reviewer_id = auth.uid()
    where a.event_id = p_event_id
      and a.status in ('CONFIRMED'::public.assignment_status, 'COMPLETED'::public.assignment_status)
  ), filtered as (
    select b.* from base b
    where nullif(btrim(coalesce(p_search_text, '')), '') is null
       or b.full_name ilike '%' || btrim(p_search_text) || '%'
       or b.phone_e164 ilike '%' || btrim(p_search_text) || '%'
       or b.worker_number::text ilike '%' || btrim(p_search_text) || '%'
       or b.category_at_confirmation::text ilike btrim(p_search_text) || '%'
  ), counters as (
    select
      (select count(*)::integer from base) as total_count,
      (select count(*)::integer from filtered) as filtered_count,
      (select count(*)::integer from base b where b.attendance_status = 'NOT_MARKED'::public.attendance_status) as not_marked_count,
      (select count(*)::integer from base b where b.attendance_status = 'PRESENT'::public.attendance_status) as present_count,
      (select count(*)::integer from base b where b.attendance_status = 'LATE'::public.attendance_status) as late_count,
      (select count(*)::integer from base b where b.attendance_status = 'ABSENT'::public.attendance_status) as absent_count
  )
  select
    f.assignment_id,
    f.event_id,
    f.worker_id,
    f.worker_number,
    f.full_name,
    f.phone_e164,
    f.profile_photo_path,
    f.category_at_confirmation,
    f.current_category,
    f.assignment_status,
    f.attendance_status,
    f.marked_by,
    f.marker_role,
    f.marked_at,
    f.notes,
    c.total_count,
    c.filtered_count,
    c.not_marked_count,
    c.present_count,
    c.late_count,
    c.absent_count,
    f.review_id,
    f.review_stars,
    f.review_tags,
    f.review_notes,
    f.review_updated_at
  from filtered f
  cross join counters c
  order by private.category_rank(f.category_at_confirmation), f.full_name, f.worker_number;
end;
$$;

revoke all on function public.event_attendance_roster_v2(uuid, text) from public, anon;
grant execute on function public.event_attendance_roster_v2(uuid, text) to authenticated;

notify pgrst, 'reload schema';
