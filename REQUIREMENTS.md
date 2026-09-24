# Screenshot Requirement Checklist

This project implements the requested **Job Recruitment / Applicant Tracking System** as one shared system with three separate dashboards.

## Candidate workspace — `/candidate`

- Secure sign-up and sign-in with name, phone, email and password.
- PDF CV upload with a 2 MB maximum limit.
- CV versions are kept by storage path; each application saves the CV path used at application time.
- Browse open jobs, search jobs, apply once per job, see stage and interview details, and withdraw non-final applications.
- Candidates cannot see other candidates, recruiter notes or AI summaries.

## Recruiter workspace — `/recruiter`

- RLS restricts applications to only the jobs assigned to that recruiter.
- Review CV record, candidate details, AI summary, requirements found/missing, and interview questions.
- Application stages are enforced in order: Applied → Shortlisted → Interview → Offer → Hired. Rejection is allowed before Hired; final decisions are locked.
- One-hour interviews must be in the future and cannot overlap for one recruiter.
- Private recruiter notes are supported by the `recruiter_notes` table and RLS policy.

## Admin workspace — `/admin`

- Create draft jobs, open jobs, close jobs, view job states and dashboard counts.
- Invite recruiters through the protected `admin-recruiter` Edge Function.
- Assign recruiters to jobs using the `recruiter_job_assignments` table. Only an admin can manage these assignments.
- View all jobs, applications, AI summaries, and notification log data through admin-only RLS policies.

## Business rules enforced in SQL

- No duplicate application for the same candidate and job.
- No application after deadline, to closed jobs, or when openings are filled.
- A job automatically behaves as closed after its deadline or once all openings are filled.
- No skipped/backwards stages, no changed final decision, and no past/overlapping interviews.
- Every public table has RLS enabled; the browser never has a service-role key.

## AI and email automations

- `application-cv-summary.workflow.json` receives an application webhook, verifies a secret, creates/saves an AI summary, and stores a safe failure state if AI is unavailable.
- `application-notifications.workflow.json` sends the candidate email for application received, interview, hired, or rejected stages, then saves an email log.
- Configure two Supabase Database Webhooks: one for new `applications` rows to the AI workflow and one for `applications` INSERT/UPDATE events to the email workflow. Both send `x-ats-secret`.
- AI instructions prohibit scoring, ranking, hire/reject decisions, stage changes, and sensitive-personal-data summaries.

## Explicitly excluded

No AI ranking or automatic decision, LinkedIn/job-board posting, in-site video interviews, offer letters/e-signatures, payroll, real SMS/WhatsApp, mobile apps, or multi-company mode.
