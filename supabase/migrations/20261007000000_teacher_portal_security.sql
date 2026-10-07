-- Teachers need assigned student rows and attendance, but no parent/guardian
-- relationship data. Keep the assignment-based scope enforced in Postgres.
revoke select (guardian_name, guardian_phone, date_of_birth, date_of_birth_year)
  on public.students from anon, authenticated;
drop policy if exists "parent_student_select_related" on public.parent_students;
create policy "parent_student_select_related" on public.parent_students
  for select to authenticated using (
    public.is_school_admin()
    or exists (
      select 1 from public.parents p
      where p.id = parent_id and p.profile_id = (select auth.uid())
    )
  );

revoke select on public.parent_students from anon, authenticated;

-- Teacher accounts may read attendance for assigned students and create
-- records for assigned classes. Corrections and deletions stay admin-only.
drop policy if exists "attendance_insert_assigned_teacher_or_admin" on public.attendance;
create policy "attendance_insert_assigned_teacher_or_admin" on public.attendance
  for insert to authenticated with check (
    recorded_by = (select auth.uid())
    and exists (
      select 1 from public.students s
      where s.id = attendance.student_id and s.class_id = attendance.class_id
    )
    and (
      public.is_school_admin()
      or (public.current_app_role() in ('teacher','form_teacher') and exists (
        select 1 from public.teacher_assignments ta
        where ta.teacher_profile_id = (select auth.uid()) and ta.class_id = attendance.class_id
      ))
    )
  );

grant select (id, student_number, class_id, status, profile_id) on public.students to authenticated;
grant select (id, attendance_date, status, student_id, class_id) on public.attendance to authenticated;
grant insert (student_id, class_id, attendance_date, status, recorded_by) on public.attendance to authenticated;
