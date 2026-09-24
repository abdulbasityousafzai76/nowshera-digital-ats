# Nowshera Digital Applicant Tracking System

A downloadable, full-stack recruitment website with separate candidate, recruiter, and admin dashboards. All dashboards connect to one secure Supabase database and receive live updates.

## Included

- Candidate account, PDF CV upload, job browsing, applications, and withdrawals.
- Recruiter application review, private notes, secure CV opening, AI-summary display, stage control, and protected 1-hour interview booking.
- Admin job management dashboard, recruiter invitation/activation, recruiter-to-job assignment, and secure recruiter invitation Edge Function.
- Supabase Auth, PostgreSQL schema, private Storage bucket, Row Level Security, and Realtime tables.
- n8n workflow template for safe AI CV summaries.
- n8n workflow template for application, interview, hired, and rejected emails.

## Important setup order

1. Create a new Supabase project.
2. In Supabase SQL Editor, run `supabase/migrations/20260923000000_initial_schema.sql`, then `supabase/migrations/20260923000001_security_and_cv_access.sql`.
3. In **Authentication → URL Configuration**, add your local URL such as `http://localhost:5173`.
4. Create your first account through the website. In the SQL Editor, run this once to promote it to admin:

```sql
update public.profiles set role = 'admin' where id = 'YOUR_AUTH_USER_UUID';
```

5. Deploy `supabase/functions/admin-recruiter/index.ts` as the `admin-recruiter` Edge Function and `supabase/functions/retry-ai-summary/index.ts` as the `retry-ai-summary` Edge Function. Keep JWT verification enabled.
6. Copy `.env.example` to `.env`, then add your Supabase URL and **publishable** key. Never place the service-role key in `.env` variables beginning with `VITE_`.

## Run locally

```bash
npm install
cp .env.example .env
npm run dev
```

For production:

```bash
npm run build
```

## n8n AI workflow

1. Import `n8n/application-cv-summary.workflow.json` into n8n.
2. Set these n8n environment variables: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ATS_WEBHOOK_SECRET`, and `AI_SUMMARY_ENDPOINT`.
3. Configure your AI endpoint to receive job requirements and a CV-derived document payload, then return the JSON fields shown in the workflow.
4. Add a Supabase Database Webhook on new `applications` rows that posts `application_id` to the n8n webhook with header `x-ats-secret`.
5. Import `n8n/application-notifications.workflow.json`, add your email/SMTP credential to its **Send candidate email** node, and configure a second Supabase Database Webhook for `applications` INSERT and UPDATE events. Email failures must never block application creation or stage updates.
6. Add the same `ATS_WEBHOOK_SECRET` and the n8n AI webhook URL as `N8N_AI_SUMMARY_WEBHOOK_URL` to the `retry-ai-summary` Edge Function environment. Recruiters can then use **Try again** without sending another candidate email.

## Complete requirement map

See `docs/REQUIREMENTS.md` for every requested feature, the role that uses it, and the implementation location.

## Security notes

- Every public table has Row Level Security enabled.
- User roles come from the database, not editable user metadata.
- CV storage is private; candidates only have access to their own CV objects.
- Candidates never receive recruiter notes or AI summaries.
- Recruiters can read only applications for jobs assigned to them.
- The service-role key is used only in trusted n8n and Edge Function environments.

## Live updates

The migration adds jobs, applications, interviews, and AI summaries to the Realtime publication. The app subscribes to these tables and refreshes dashboards automatically when updates arrive.
