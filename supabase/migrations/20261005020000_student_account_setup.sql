alter table public.students
  add column if not exists surname text not null default '',
  add column if not exists given_name text not null default '',
  add column if not exists middle_name text not null default '',
  add column if not exists date_of_birth date,
  add column if not exists date_of_birth_year smallint,
  add column if not exists admission_number text,
  add column if not exists guardian_name text not null default '',
  add column if not exists guardian_phone text not null default '',
  add column if not exists religion text not null default '';

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

drop policy if exists students_admin_read_register on public.students;
create policy students_admin_read_register on public.students
  for select to authenticated
  using (public.is_school_admin());

revoke select on public.students from authenticated;
revoke select (surname, given_name, middle_name, date_of_birth, date_of_birth_year,
  admission_number, guardian_name, guardian_phone, religion)
  on public.students from authenticated;
grant select (id, profile_id, student_number, class_id, status)
  on public.students to authenticated;

grant update (surname, given_name, middle_name, date_of_birth, guardian_name, guardian_phone, religion)
  on public.students to authenticated;

grant update (date_of_birth_year, admission_number)
  on public.students to authenticated;

create or replace function public.admin_student_register()
returns table (
  id uuid,
  profile_id uuid,
  student_number text,
  admission_number text,
  surname text,
  given_name text,
  middle_name text,
  date_of_birth date,
  date_of_birth_year smallint,
  guardian_name text,
  guardian_phone text,
  religion text,
  status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.profile_id, s.student_number, s.admission_number, s.surname,
    s.given_name, s.middle_name, s.date_of_birth, s.date_of_birth_year,
    s.guardian_name, s.guardian_phone, s.religion, s.status
  from public.students s
  where s.status = 'active' and public.is_school_admin()
  order by s.student_number;
$$;

revoke all on function public.admin_student_register() from public, anon;
grant execute on function public.admin_student_register() to authenticated;

grant select (must_change_password) on public.profiles to authenticated;

create or replace function public.complete_temporary_student_password()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set must_change_password = false
  where id = (select auth.uid());
end;
$$;

revoke all on function public.complete_temporary_student_password() from public, anon;
grant execute on function public.complete_temporary_student_password() to authenticated;
