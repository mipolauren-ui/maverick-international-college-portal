-- Maverick student IDs use the year group at admission and a 9-series entry order.
-- Example: MAV/J2/901 means J2 and entry order 01.
-- NOT VALID keeps legacy rows readable until the school assigns their new IDs.
alter table public.students
  drop constraint if exists students_student_number_check;

alter table public.students
  add constraint students_student_number_check
  check (student_number ~ '^MAV/(J1|J2|J3|S1|S2|S3)/9(0[1-9]|[1-9][0-9])$')
  not valid;
