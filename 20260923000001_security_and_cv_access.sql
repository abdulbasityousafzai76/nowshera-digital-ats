-- Follow-up hardening for the ATS schema.
-- Run this after 20260923000000_initial_schema.sql in a fresh project.

alter function public.is_admin() set search_path=public;
alter function public.is_assigned_recruiter(uuid) set search_path=public;
alter function public.set_updated_at() set search_path=public;

revoke all on function public.handle_new_user() from public;
revoke execute on function public.create_application(uuid), public.withdraw_application(uuid), public.advance_application(uuid,public.application_stage), public.schedule_interview(uuid,timestamptz,text,text) from anon;

create index if not exists applications_job_id_idx on public.applications(job_id);
create index if not exists candidate_cvs_candidate_id_idx on public.candidate_cvs(candidate_id);
create index if not exists interviews_recruiter_starts_at_idx on public.interviews(recruiter_id,starts_at);
create index if not exists jobs_created_by_idx on public.jobs(created_by);
create index if not exists notification_logs_application_id_idx on public.notification_logs(application_id);
create index if not exists recruiter_job_assignments_job_id_idx on public.recruiter_job_assignments(job_id);
create index if not exists recruiter_notes_application_recruiter_idx on public.recruiter_notes(application_id,recruiter_id);

create policy "assigned recruiters read application cvs" on storage.objects for select to authenticated
using (bucket_id='cvs' and exists(select 1 from public.applications a where a.cv_path=name and public.is_assigned_recruiter(a.job_id)));
create policy "admins read application cvs" on storage.objects for select to authenticated
using (bucket_id='cvs' and public.is_admin());
