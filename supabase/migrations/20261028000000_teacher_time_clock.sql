-- Daily staff time clock. Teachers can read only their own records; all writes
-- go through role-checked RPCs so a client cannot edit timestamps or coworkers.
create table if not exists public.teacher_time_clock (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  work_date date not null,
  clocked_in_at timestamptz not null default now(),
  clocked_out_at timestamptz,
  created_at timestamptz not null default now(),
  constraint teacher_time_clock_one_record_per_day unique (profile_id, work_date),
  constraint teacher_time_clock_valid_out_time
    check (clocked_out_at is null or clocked_out_at >= clocked_in_at)
);

create index if not exists teacher_time_clock_date_idx
  on public.teacher_time_clock (work_date desc, profile_id);

alter table public.teacher_time_clock enable row level security;

drop policy if exists teacher_time_clock_read_self_or_admin on public.teacher_time_clock;
create policy teacher_time_clock_read_self_or_admin on public.teacher_time_clock
  for select to authenticated
  using (profile_id = (select auth.uid()) or public.is_school_admin());

revoke all on public.teacher_time_clock from anon, authenticated;
grant select on public.teacher_time_clock to authenticated;

create or replace function public.teacher_clock_in()
returns public.teacher_time_clock
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  result public.teacher_time_clock;
begin
  if actor is null then raise exception 'Sign in is required.'; end if;
  if public.current_app_role() not in ('teacher', 'form_teacher') then
    raise exception 'Only teacher accounts can use the teacher time clock.';
  end if;

  insert into public.teacher_time_clock (profile_id, work_date, clocked_in_at)
  values (actor, (now() at time zone 'Africa/Lagos')::date, now())
  on conflict (profile_id, work_date) do nothing
  returning * into result;

  if not found then
    raise exception 'A time-clock record already exists for today.';
  end if;
  return result;
end;
$$;

create or replace function public.teacher_clock_out()
returns public.teacher_time_clock
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  result public.teacher_time_clock;
begin
  if actor is null then raise exception 'Sign in is required.'; end if;
  if public.current_app_role() not in ('teacher', 'form_teacher') then
    raise exception 'Only teacher accounts can use the teacher time clock.';
  end if;

  update public.teacher_time_clock
  set clocked_out_at = now()
  where profile_id = actor
    and work_date = (now() at time zone 'Africa/Lagos')::date
    and clocked_out_at is null
  returning * into result;

  if not found then
    raise exception 'There is no open clock-in record for today.';
  end if;
  return result;
end;
$$;

revoke all on function public.teacher_clock_in() from public, anon;
revoke all on function public.teacher_clock_out() from public, anon;
grant execute on function public.teacher_clock_in() to authenticated;
grant execute on function public.teacher_clock_out() to authenticated;
