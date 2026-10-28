-- Keep teachers scoped to their own time records and make the administrative
-- history permission explicit for Super Admin and other school administrators.
drop policy if exists teacher_time_clock_read_self_or_admin on public.teacher_time_clock;
drop policy if exists teacher_time_clock_read_self on public.teacher_time_clock;
drop policy if exists teacher_time_clock_admin_read on public.teacher_time_clock;

create policy teacher_time_clock_read_self on public.teacher_time_clock
  for select to authenticated
  using (profile_id = (select auth.uid()));

create policy teacher_time_clock_admin_read on public.teacher_time_clock
  for select to authenticated
  using (public.is_school_admin());

create index if not exists teacher_time_clock_profile_work_date_idx
  on public.teacher_time_clock (profile_id, work_date desc);
