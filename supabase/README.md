# Supabase pilot setup

This folder contains the first invite-only school portal schema. It is a pilot foundation, not the complete MIS database.

## Included in this migration

- Role-backed profiles for the ten school roles, with low-privilege student as the default.
- Classes, subjects and staff teaching/form-teacher assignments.
- Student records with permanent ID format `MAV/{J1|J2|J3|S1|S2|S3}/9NN`. The final two digits are the entry order; for example, `MAV/J2/901` is the first entry in J2.
- Parent accounts and explicit parent-to-student links.
- Daily attendance with the requested statuses and correction restrictions.
- Public, authenticated-community and staff announcements.
- Audit records for student, attendance and announcement changes.
- Row-level policies that limit students to themselves, parents to linked children and teachers to assigned classes.

Medical, financial, result and certificate records are intentionally out of this first schema. Add those only after their retention rules, access groups and approval workflows are agreed and separately reviewed.

## Connect a hosted project

1. Create a Supabase project owned by the school. Do not send database passwords, secret keys or service-role keys in chat.
2. In the project dashboard, open **Project Settings → API Keys** and copy the project URL and the `publishable` key.
3. Copy `.env.example` to `.env.local`, then set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`. These browser-exposed values are not database passwords; RLS is the authorization boundary.
4. Apply `migrations/20261002000000_school_pilot.sql` in the project’s SQL editor, after reviewing it with the school’s project owner. Alternatively, install the Supabase CLI, authenticate with `npx supabase login`, link this folder using `npx supabase link --project-ref YOUR_PROJECT_REF`, and deploy with `npx supabase db push`.
5. Keep public sign-ups disabled. Invite users through an authorized admin path. The profile creation trigger always assigns the `student` role; change privileged roles using the Supabase dashboard/SQL with an authorized school admin. Never allow a browser form to set its own role.
6. Set the project Auth URL allow-list for the local site and eventual production domain. Configure the project password strength policy and email sender before sending recovery links to users.
7. Restart the Vite dev server after creating `.env.local`.

## Vercel deployment

1. Import this repository into the school's Vercel account. The checked-in `vercel.json` sets the Vite build and rewrites direct page requests to the SPA entry point.
2. In Vercel → Project Settings → Environment Variables, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` for Production and Preview. Set `VITE_SITE_URL` to the canonical production origin (for example, `https://school.example`) in Production. For Preview, leave it unset to use that deployment's current URL, and allow the matching Preview domain in Supabase. Redeploy after changing environment values; Vite embeds them during the build.
3. In Supabase → Authentication → URL Configuration, set the Site URL to the production domain and add the production URL plus the Vercel preview URL patterns to the redirect allow-list. Add `https://YOUR_DOMAIN/login` and `https://YOUR_DOMAIN/login?mode=reset` (or a matching redirect pattern) so password recovery returns to the deployed site.
4. Apply the reviewed migration to the hosted project, then create and promote the school's first authorized administrator. Configure a production email sender, password strength and privileged-role MFA before inviting real users.
5. Deploy a Preview first. Verify the home page, a direct route such as `/admissions`, portal sign-in, password recovery redirect, sign-out and role access using non-production accounts. Only then promote the production deployment.

Never add a Supabase service-role/secret key or database password to Vercel client environment variables. Only the URL and publishable key belong in this browser application; database policies must enforce access.

## Local Supabase CLI workflow

The CLI workflow needs a Docker-compatible runtime. Install Docker Desktop (or another supported Docker-compatible runtime), then run `npm run db:start` and `npm run db:reset` to apply this migration to a disposable local database. Use `npm run db:lint` to check migrations against that local database and `npm run db:stop` when finished. The local Supabase stack is for development; do not expose it publicly or use its default credentials for production.

## Initial administrator bootstrap

Create the first account through the Supabase dashboard, then set that account's role in the SQL editor using the profile UUID shown in Authentication → Users:

```sql
update public.profiles
set role = 'super_admin'
where id = 'REPLACE-WITH-THE-UUID-FROM-AUTH-USERS';
```

This one-time action must be performed by the project owner. The browser client has no permission to update `profiles.role`.

## Before real school data

- Review each RLS rule with test accounts for every role, including negative-access checks.
- Configure Auth password requirements, recovery email delivery, redirect URLs and privileged-role MFA in the hosted project.
- Confirm the school's data retention, guardian verification, student-consent, backup and incident-response processes.
- Add result approval, finance, timetable, assignments, documents, clubs, events and gallery storage in separate reviewed migrations.
