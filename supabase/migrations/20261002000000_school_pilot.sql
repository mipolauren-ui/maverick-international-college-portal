-- Initial, invite-only school portal foundation.
-- Keep sign-up disabled. Create auth users through an authorized administrator,
-- then assign roles through the Supabase SQL editor or a future admin function.

create extension if not exists pgcrypto with schema extensions;

create type public.app_role as enum (
  'super_admin', 'principal', 'vice_principal', 'admin', 'teacher',
  'form_teacher', 'bursar', 'librarian', 'parent', 'student'
);

create type public.attendance_status as enum (
  'present', 'absent', 'late', 'excused', 'sick', 'school_activity'
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role public.app_role not null default 'student',
  staff_id text unique check (staff_id is null or staff_id ~ '^MIC/STF/[0-9]{4}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  academic_session text not null,
  level text not null check (level in ('JS1','JS2','JS3','SS1','SS2','SS3')),
  arm text not null,
  created_at timestamptz not null default now(),
  unique (academic_session, level, arm)
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text unique,
  level text check (level is null or level in ('JS1','JS2','JS3','SS1','SS2','SS3')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  student_number text not null unique check (student_number ~ '^MIC/[0-9]{4}/[0-9]{4}$'),
  admission_date date,
  admission_session text,
  class_id uuid references public.classes(id) on delete set null,
  department text,
  status text not null default 'active' check (status in ('active','graduated','withdrawn','transferred')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.parents (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.parent_students (
  parent_id uuid not null references public.parents(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  relationship text,
  is_primary_contact boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (parent_id, student_id)
);

create table public.teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_profile_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null,
  assignment_kind text not null default 'subject' check (assignment_kind in ('subject','form_teacher')),
  created_at timestamptz not null default now(),
  unique (teacher_profile_id, class_id, subject_id, assignment_kind)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete restrict,
  attendance_date date not null,
  status public.attendance_status not null,
  note text,
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, attendance_date)
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'authenticated' check (audience in ('public','authenticated','staff')),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  published_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  table_name text not null,
  record_id text,
  previous_value jsonb,
  new_value jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create index students_class_id_idx on public.students(class_id);
create index parent_students_student_id_idx on public.parent_students(student_id);
create index teacher_assignments_class_idx on public.teacher_assignments(class_id);
create index attendance_student_date_idx on public.attendance(student_id, attendance_date desc);
create index announcements_published_idx on public.announcements(status, published_at desc);

-- New invited/auth-created users get a low-privilege profile by default.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'student'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_auth_user();

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = (select auth.uid())
$$;

create or replace function public.is_school_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() in ('super_admin','principal','vice_principal','admin'), false)
$$;

create or replace function public.can_access_student(target_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.students s
    where s.id = target_student_id
      and (
        s.profile_id = (select auth.uid())
        or coalesce(public.current_app_role() in ('super_admin','principal','vice_principal','admin'), false)
        or exists (
          select 1 from public.parent_students ps
          join public.parents p on p.id = ps.parent_id
          where ps.student_id = s.id and p.profile_id = (select auth.uid())
        )
        or exists (
          select 1 from public.teacher_assignments ta
          where ta.class_id = s.class_id
            and ta.teacher_profile_id = (select auth.uid())
            and public.current_app_role() in ('teacher','form_teacher')
        )
      )
  )
$$;

create or replace function public.can_access_class(target_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() in ('super_admin','principal','vice_principal','admin'), false)
    or exists (
      select 1 from public.teacher_assignments ta
      where ta.class_id = target_class_id
        and ta.teacher_profile_id = (select auth.uid())
        and public.current_app_role() in ('teacher','form_teacher')
    )
    or exists (
      select 1 from public.students s
      where s.class_id = target_class_id
        and (s.profile_id = (select auth.uid()) or exists (
          select 1 from public.parent_students ps
          join public.parents p on p.id = ps.parent_id
          where ps.student_id = s.id and p.profile_id = (select auth.uid())
        ))
    )
$$;

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  before_row jsonb;
  after_row jsonb;
  row_id text;
begin
  if tg_op <> 'INSERT' then before_row := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then after_row := to_jsonb(new); end if;
  row_id := coalesce(after_row ->> 'id', before_row ->> 'id');
  insert into public.audit_logs (actor_id, action, table_name, record_id, previous_value, new_value, reason)
  values (
    (select auth.uid()), tg_op, tg_table_name, row_id, before_row, after_row,
    nullif(current_setting('app.change_reason', true), '')
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger audit_student_changes
  after insert or update or delete on public.students
  for each row execute procedure public.write_audit_log();
create trigger audit_attendance_changes
  after insert or update or delete on public.attendance
  for each row execute procedure public.write_audit_log();
create trigger audit_announcement_changes
  after insert or update or delete on public.announcements
  for each row execute procedure public.write_audit_log();

alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.students enable row level security;
alter table public.parents enable row level security;
alter table public.parent_students enable row level security;
alter table public.teacher_assignments enable row level security;
alter table public.attendance enable row level security;
alter table public.announcements enable row level security;
alter table public.audit_logs enable row level security;

create policy "profiles_select_self_or_admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_school_admin());

create policy "classes_select_assigned_or_accessible" on public.classes
  for select to authenticated using (public.can_access_class(id));
create policy "classes_admin_manage" on public.classes
  for all to authenticated using (public.is_school_admin()) with check (public.is_school_admin());

create policy "subjects_select_authenticated" on public.subjects
  for select to authenticated using (true);
create policy "subjects_admin_manage" on public.subjects
  for all to authenticated using (public.is_school_admin()) with check (public.is_school_admin());

create policy "students_select_authorized_relationship" on public.students
  for select to authenticated using (public.can_access_student(id));
create policy "students_admin_insert" on public.students
  for insert to authenticated with check (public.is_school_admin());
create policy "students_admin_update" on public.students
  for update to authenticated using (public.is_school_admin()) with check (public.is_school_admin());

create policy "parents_select_self_or_admin" on public.parents
  for select to authenticated using (profile_id = (select auth.uid()) or public.is_school_admin());
create policy "parents_admin_manage" on public.parents
  for all to authenticated using (public.is_school_admin()) with check (public.is_school_admin());

create policy "parent_student_select_related" on public.parent_students
  for select to authenticated using (
    public.is_school_admin()
    or exists (select 1 from public.parents p where p.id = parent_id and p.profile_id = (select auth.uid()))
    or exists (
      select 1 from public.students s
      join public.teacher_assignments ta on ta.class_id = s.class_id
      where s.id = student_id and ta.teacher_profile_id = (select auth.uid())
        and public.current_app_role() in ('teacher','form_teacher')
    )
  );
create policy "parent_student_admin_manage" on public.parent_students
  for all to authenticated using (public.is_school_admin()) with check (public.is_school_admin());

create policy "teacher_assignments_select_self_or_admin" on public.teacher_assignments
  for select to authenticated using (teacher_profile_id = (select auth.uid()) or public.is_school_admin());
create policy "teacher_assignments_admin_manage" on public.teacher_assignments
  for all to authenticated using (public.is_school_admin()) with check (public.is_school_admin());

create policy "attendance_select_related" on public.attendance
  for select to authenticated using (public.can_access_student(student_id));
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
create policy "attendance_corrections_admin_only" on public.attendance
  for update to authenticated using (public.is_school_admin()) with check (public.is_school_admin());
create policy "attendance_delete_admin_only" on public.attendance
  for delete to authenticated using (public.is_school_admin());

create policy "announcements_read_published_audience" on public.announcements
  for select to anon, authenticated using (
    (status = 'published' and audience = 'public')
    or (auth.uid() is not null and status = 'published' and audience = 'authenticated')
    or (auth.uid() is not null and status = 'published' and audience = 'staff'
      and public.current_app_role() in ('super_admin','principal','vice_principal','admin','teacher','form_teacher','bursar','librarian'))
    or public.is_school_admin()
  );
create policy "announcements_admin_insert" on public.announcements
  for insert to authenticated with check (public.is_school_admin() and created_by = (select auth.uid()));
create policy "announcements_admin_update" on public.announcements
  for update to authenticated using (public.is_school_admin()) with check (public.is_school_admin());
create policy "announcements_admin_delete" on public.announcements
  for delete to authenticated using (public.is_school_admin());

create policy "audit_logs_admin_read" on public.audit_logs
  for select to authenticated using (public.is_school_admin());

grant usage on schema public to anon, authenticated;

-- No browser role receives UPDATE access on profiles or INSERT/UPDATE/DELETE on audit_logs.
-- Privileged role assignment is intentionally an administrator-controlled operation.

revoke all on public.profiles, public.classes, public.subjects, public.students,
  public.parents, public.parent_students, public.teacher_assignments, public.attendance,
  public.announcements, public.audit_logs from anon, authenticated;
grant select on public.profiles to authenticated;
grant select on public.announcements to anon, authenticated;
grant select on public.classes, public.subjects, public.students, public.parents,
  public.parent_students, public.teacher_assignments, public.attendance,
  public.audit_logs to authenticated;
grant insert, update, delete on public.classes, public.subjects, public.parents,
  public.parent_students, public.teacher_assignments to authenticated;
grant insert, update, delete on public.students, public.attendance,
  public.announcements to authenticated;
