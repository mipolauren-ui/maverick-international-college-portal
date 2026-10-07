-- Record teacher subject expertise separately from class-specific assignments.
-- This lets administrators maintain a subject list before timetable classes exist.
create table if not exists public.teacher_subjects (
  teacher_profile_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (teacher_profile_id, subject_id)
);

alter table public.teacher_subjects enable row level security;

drop policy if exists teacher_subjects_select_self_or_admin on public.teacher_subjects;
create policy teacher_subjects_select_self_or_admin on public.teacher_subjects
  for select to authenticated
  using (teacher_profile_id = (select auth.uid()) or public.is_school_admin());

drop policy if exists teacher_subjects_admin_manage on public.teacher_subjects;
create policy teacher_subjects_admin_manage on public.teacher_subjects
  for all to authenticated
  using (public.is_school_admin())
  with check (public.is_school_admin());

revoke all on public.teacher_subjects from anon, authenticated;
grant select, insert, update, delete on public.teacher_subjects to authenticated;
