-- Shared 2026/2027 Lagos State harmonised calendar for Maverick.
-- State-issued dates are read-only; authorized school administrators can add
-- school-specific dates such as exams, PTA meetings, and events.

create table if not exists public.school_calendar_events (
  id uuid primary key default gen_random_uuid(),
  academic_session text not null,
  term text not null check (term in ('First Term', 'Second Term', 'Third Term')),
  title text not null check (length(trim(title)) between 1 and 180),
  event_type text not null check (event_type in (
    'staff_development', 'resumption', 'term_half', 'open_day', 'midterm_break',
    'public_holiday', 'observance', 'vacation', 'end_of_session', 'examination',
    'pta', 'school_event', 'other'
  )),
  start_date date not null,
  end_date date not null,
  source text not null check (source in ('lagos_state', 'school')),
  visibility text not null default 'public' check (visibility in ('public', 'portal')),
  source_url text,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_calendar_event_dates_valid check (end_date >= start_date),
  constraint school_calendar_state_source_has_reference check (
    source <> 'lagos_state' or source_url is not null
  )
);

create unique index if not exists school_calendar_state_event_unique
  on public.school_calendar_events (academic_session, term, title, start_date, source);
create index if not exists school_calendar_events_date_idx
  on public.school_calendar_events (academic_session, start_date, end_date);

alter table public.school_calendar_events enable row level security;
revoke all on public.school_calendar_events from anon, authenticated;
grant select on public.school_calendar_events to anon, authenticated;
grant insert, update, delete on public.school_calendar_events to authenticated;

drop policy if exists school_calendar_public_read on public.school_calendar_events;
create policy school_calendar_public_read on public.school_calendar_events
  for select to anon using (visibility = 'public');

drop policy if exists school_calendar_authenticated_read on public.school_calendar_events;
create policy school_calendar_authenticated_read on public.school_calendar_events
  for select to authenticated using (
    visibility = 'public' or public.is_school_admin()
  );

drop policy if exists school_calendar_admin_insert_school_events on public.school_calendar_events;
create policy school_calendar_admin_insert_school_events on public.school_calendar_events
  for insert to authenticated with check (
    public.is_school_admin() and source = 'school' and created_by = (select auth.uid())
  );

drop policy if exists school_calendar_admin_update_school_events on public.school_calendar_events;
create policy school_calendar_admin_update_school_events on public.school_calendar_events
  for update to authenticated using (
    public.is_school_admin() and source = 'school'
  ) with check (
    public.is_school_admin() and source = 'school'
  );

drop policy if exists school_calendar_admin_delete_school_events on public.school_calendar_events;
create policy school_calendar_admin_delete_school_events on public.school_calendar_events
  for delete to authenticated using (
    public.is_school_admin() and source = 'school'
  );

create or replace function public.protect_lagos_state_calendar_events()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.source = 'lagos_state' then
    raise exception 'Lagos State calendar dates are read-only';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists protect_lagos_state_calendar_events on public.school_calendar_events;
create trigger protect_lagos_state_calendar_events
  before update or delete on public.school_calendar_events
  for each row execute function public.protect_lagos_state_calendar_events();

create or replace function public.set_school_calendar_event_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_school_calendar_event_updated_at on public.school_calendar_events;
create trigger set_school_calendar_event_updated_at
  before update on public.school_calendar_events
  for each row execute function public.set_school_calendar_event_updated_at();

insert into public.school_calendar_events
  (academic_session, term, title, event_type, start_date, end_date, source, visibility, source_url, notes)
values
  ('2026/2027','First Term','Staff professional development','staff_development','2026-09-07','2026-09-11','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Schools select any two days in this window.'),
  ('2026/2027','First Term','First term resumption','resumption','2026-09-14','2026-09-14','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','First Term','First half of term','term_half','2026-09-14','2026-10-30','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','34 school days.'),
  ('2026/2027','First Term','Independence Day','public_holiday','2026-10-01','2026-10-01','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Subject to Federal Government announcement.'),
  ('2026/2027','First Term','World Teachers’ Day','observance','2026-10-05','2026-10-05','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','First Term','Primary Open Day','open_day','2026-10-29','2026-10-29','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Mandatory; timing is at the school’s discretion.'),
  ('2026/2027','First Term','Secondary Open Day','open_day','2026-10-30','2026-10-30','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Mandatory; timing is at the school’s discretion.'),
  ('2026/2027','First Term','Mid-term break','midterm_break','2026-11-02','2026-11-06','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','First Term','Second half of term','term_half','2026-11-09','2026-12-18','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','30 school days.'),
  ('2026/2027','First Term','First-term vacation','vacation','2026-12-21','2027-01-08','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','15 days.'),
  ('2026/2027','Second Term','Second term resumption','resumption','2027-01-11','2027-01-11','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','Second Term','First half of term','term_half','2027-01-11','2027-02-19','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','30 school days.'),
  ('2026/2027','Second Term','Primary Open Day','open_day','2027-02-18','2027-02-18','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Mandatory; timing is at the school’s discretion.'),
  ('2026/2027','Second Term','Secondary Open Day','open_day','2027-02-19','2027-02-19','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Mandatory; timing is at the school’s discretion.'),
  ('2026/2027','Second Term','Mid-term break','midterm_break','2027-02-22','2027-02-26','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','Second Term','Second half of term','term_half','2027-03-01','2027-04-16','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','31 school days.'),
  ('2026/2027','Second Term','Eid-el-Fitr','public_holiday','2027-03-10','2027-03-11','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Subject to Federal Government announcement.'),
  ('2026/2027','Second Term','Good Friday','public_holiday','2027-03-26','2027-03-26','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Subject to Federal Government announcement.'),
  ('2026/2027','Second Term','Easter Monday','public_holiday','2027-03-29','2027-03-29','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Subject to Federal Government announcement.'),
  ('2026/2027','Second Term','Second-term vacation','vacation','2027-04-19','2027-04-30','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','10 days.'),
  ('2026/2027','Third Term','Third term resumption','resumption','2027-05-03','2027-05-03','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','Third Term','First half of term','term_half','2027-05-03','2027-06-11','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','27 school days.'),
  ('2026/2027','Third Term','Workers’ Day','public_holiday','2027-05-01','2027-05-01','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Subject to Federal Government announcement.'),
  ('2026/2027','Third Term','Eid-el-Kabir','public_holiday','2027-05-17','2027-05-18','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Subject to Federal Government announcement.'),
  ('2026/2027','Third Term','Children’s Day','observance','2027-05-27','2027-05-27','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','Third Term','Primary Open Day','open_day','2027-06-10','2027-06-10','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Mandatory; timing is at the school’s discretion.'),
  ('2026/2027','Third Term','Secondary Open Day','open_day','2027-06-11','2027-06-11','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Mandatory; timing is at the school’s discretion.'),
  ('2026/2027','Third Term','Democracy Day','public_holiday','2027-06-12','2027-06-12','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','Subject to Federal Government announcement.'),
  ('2026/2027','Third Term','Mid-term break','midterm_break','2027-06-14','2027-06-18','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','Third Term','Second half of term','term_half','2027-06-21','2027-07-30','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf','30 school days.'),
  ('2026/2027','Third Term','End of session','end_of_session','2027-07-30','2027-07-30','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null),
  ('2026/2027','Third Term','Long vacation begins','vacation','2027-08-02','2027-08-02','lagos_state','public','https://oeqalagos.com/wp-content/uploads/2026/07/APPROVED-2026_2027-HARMONISED-ACADEMIC-CALENDAR-AS-RELEASED.pdf',null)
on conflict (academic_session, term, title, start_date, source) do nothing;
