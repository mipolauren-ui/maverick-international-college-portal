-- Allow authorized school relationships to read learner names from the
-- student register. Existing row-level policies still limit each user to
-- their own, linked, assigned, or administratively managed student records.
grant select (surname, given_name, middle_name)
  on public.students to authenticated;
