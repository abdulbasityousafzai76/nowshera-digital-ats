-- Nowshera Digital ATS: run with Supabase CLI or the SQL editor.
create extension if not exists pgcrypto;

create type public.app_role as enum ('candidate','recruiter','admin');
create type public.job_status as enum ('draft','open','closed');
create type public.application_stage as enum ('applied','shortlisted','interview','offer','hired','rejected','withdrawn');
create type public.summary_status as enum ('pending','complete','failed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '', phone text, role public.app_role not null default 'candidate',
  active boolean not null default true, created_at timestamptz not null default now()
);
create table public.jobs (
  id uuid primary key default gen_random_uuid(), title text not null, department text not null, location text not null,
  job_type text not null check(job_type in ('Full-time','Part-time','Internship')), description text not null, requirements text not null,
  last_date date not null, openings integer not null check(openings > 0), status public.job_status not null default 'draft',
  created_by uuid references public.profiles(id), created_at timestamptz not null default now(), closed_at timestamptz
);
create table public.recruiter_job_assignments (
  recruiter_id uuid not null references public.profiles(id) on delete cascade, job_id uuid not null references public.jobs(id) on delete cascade,
  primary key(recruiter_id,job_id)
);
create table public.candidate_cvs (
  id uuid primary key default gen_random_uuid(), candidate_id uuid not null references public.profiles(id) on delete cascade,
  path text not null unique, file_name text not null, created_at timestamptz not null default now()
);
create table public.applications (
  id uuid primary key default gen_random_uuid(), candidate_id uuid not null references public.profiles(id) on delete cascade,
  job_id uuid not null references public.jobs(id) on delete cascade, cv_path text not null, stage public.application_stage not null default 'applied',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(candidate_id,job_id)
);
create table public.recruiter_notes (
  id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade,
  recruiter_id uuid not null references public.profiles(id), body text not null check(char_length(body)<=5000), created_at timestamptz not null default now()
);
create table public.interviews (
  id uuid primary key default gen_random_uuid(), application_id uuid not null unique references public.applications(id) on delete cascade,
  recruiter_id uuid not null references public.profiles(id), starts_at timestamptz not null, ends_at timestamptz not null,
  location text, meeting_link text, created_at timestamptz not null default now(), check(ends_at=starts_at+interval '1 hour')
);
create table public.ai_summaries (
  id uuid primary key default gen_random_uuid(), application_id uuid not null unique references public.applications(id) on delete cascade,
  status public.summary_status not null default 'pending', profile_bullets jsonb not null default '[]', requirements_found jsonb not null default '[]',
  requirements_missing jsonb not null default '[]', interview_questions jsonb not null default '[]', error_message text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.notification_logs (
  id uuid primary key default gen_random_uuid(), application_id uuid references public.applications(id) on delete cascade,
  kind text not null, sent_at timestamptz not null default now(), provider_message_id text
);

-- Never trust user metadata for roles. New sign-ups always become candidates.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name,phone,role) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),new.raw_user_meta_data->>'phone','candidate'); return new; end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create or replace function public.is_admin() returns boolean language sql stable as $$select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin' and active)$$;
create or replace function public.is_assigned_recruiter(p_job uuid) returns boolean language sql stable as $$select exists(select 1 from public.recruiter_job_assignments r join public.profiles p on p.id=r.recruiter_id where r.job_id=p_job and r.recruiter_id=(select auth.uid()) and p.role='recruiter' and p.active)$$;
create or replace function public.set_updated_at() returns trigger language plpgsql as $$begin new.updated_at=now();return new;end;$$;
create trigger applications_updated before update on public.applications for each row execute procedure public.set_updated_at();
create trigger summaries_updated before update on public.ai_summaries for each row execute procedure public.set_updated_at();

alter table public.profiles enable row level security; alter table public.jobs enable row level security; alter table public.recruiter_job_assignments enable row level security;
alter table public.candidate_cvs enable row level security; alter table public.applications enable row level security; alter table public.recruiter_notes enable row level security;
alter table public.interviews enable row level security; alter table public.ai_summaries enable row level security; alter table public.notification_logs enable row level security;
create policy "users read their profile" on public.profiles for select to authenticated using(id=(select auth.uid()) or public.is_admin() or (role='candidate' and exists(select 1 from public.applications a where a.candidate_id=id and public.is_assigned_recruiter(a.job_id))));
create policy "admins manage profiles" on public.profiles for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "open jobs visible" on public.jobs for select to anon, authenticated using(status='open' or public.is_admin() or public.is_assigned_recruiter(id));
create policy "admins manage jobs" on public.jobs for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin manages assignments" on public.recruiter_job_assignments for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "recruiter reads assignments" on public.recruiter_job_assignments for select to authenticated using(recruiter_id=(select auth.uid()));
create policy "candidate manages own cvs" on public.candidate_cvs for all to authenticated using(candidate_id=(select auth.uid())) with check(candidate_id=(select auth.uid()));
create policy "candidate reads own applications" on public.applications for select to authenticated using(candidate_id=(select auth.uid()));
create policy "recruiter reads assigned applications" on public.applications for select to authenticated using(public.is_assigned_recruiter(job_id));
create policy "admin reads applications" on public.applications for select to authenticated using(public.is_admin());
create policy "recruiter notes are private" on public.recruiter_notes for select to authenticated using(recruiter_id=(select auth.uid()) or public.is_admin());
create policy "recruiter adds own notes" on public.recruiter_notes for insert to authenticated with check(recruiter_id=(select auth.uid()) and public.is_assigned_recruiter((select job_id from public.applications where id=application_id)));
create policy "interview visibility" on public.interviews for select to authenticated using(recruiter_id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.applications a where a.id=application_id and a.candidate_id=(select auth.uid())));
create policy "ai summary limited" on public.ai_summaries for select to authenticated using(public.is_admin() or exists(select 1 from public.applications a where a.id=application_id and public.is_assigned_recruiter(a.job_id)));
create policy "admin notification logs" on public.notification_logs for select to authenticated using(public.is_admin());

-- Secure business operations. Functions verify both identity and role; direct writes are unavailable.
create or replace function public.create_application(p_job_id uuid) returns text language plpgsql security definer set search_path=public as $$
declare p_path text; v_job public.jobs;
begin
 if auth.uid() is null then raise exception 'Please sign in first.'; end if;
 select * into v_job from public.jobs where id=p_job_id;
 if not found or v_job.status<>'open' or v_job.last_date<current_date then raise exception 'This job is closed and no longer accepts applications.'; end if;
 if (select count(*) from public.applications where job_id=p_job_id and stage='hired') >= v_job.openings then raise exception 'This job is closed and no longer accepts applications.'; end if;
 select path into p_path from public.candidate_cvs where candidate_id=auth.uid() order by created_at desc limit 1;
 if p_path is null then raise exception 'Please upload your PDF CV before applying.'; end if;
 insert into public.applications(candidate_id,job_id,cv_path) values(auth.uid(),p_job_id,p_path);
 insert into public.ai_summaries(application_id) select id from public.applications where candidate_id=auth.uid() and job_id=p_job_id;
 return 'Application submitted successfully.';
exception when unique_violation then raise exception 'You have already applied for this job.'; end; $$;
create or replace function public.withdraw_application(p_application_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin update public.applications set stage='withdrawn' where id=p_application_id and candidate_id=auth.uid() and stage not in('hired','rejected'); if not found then raise exception 'This application cannot be withdrawn.'; end if; end; $$;
create or replace function public.advance_application(p_application_id uuid,p_stage public.application_stage) returns void language plpgsql security definer set search_path=public as $$
declare v public.applications;
begin select * into v from public.applications where id=p_application_id; if not found then raise exception 'Application not found.'; end if;
 if not (public.is_admin() or public.is_assigned_recruiter(v.job_id)) then raise exception 'You are not assigned to this job.'; end if;
 if v.stage in('hired','rejected','withdrawn') then raise exception 'This final application stage cannot be changed.'; end if;
 if p_stage='rejected' then update public.applications set stage=p_stage where id=v.id; return; end if;
 if (v.stage='applied' and p_stage='shortlisted') or (v.stage='shortlisted' and p_stage='interview') or (v.stage='interview' and p_stage='offer') or (v.stage='offer' and p_stage='hired') then update public.applications set stage=p_stage where id=v.id; else raise exception 'Stages cannot be skipped or moved backwards.'; end if; end; $$;
create or replace function public.schedule_interview(p_application_id uuid,p_starts_at timestamptz,p_location text,p_meeting_link text) returns void language plpgsql security definer set search_path=public as $$
declare v public.applications; v_end timestamptz:=p_starts_at+interval '1 hour';
begin select * into v from public.applications where id=p_application_id; if not found or not public.is_assigned_recruiter(v.job_id) then raise exception 'You are not assigned to this application.'; end if;
 if v.stage<>'shortlisted' then raise exception 'Only shortlisted applicants can be scheduled.'; end if; if p_starts_at<=now() then raise exception 'An interview cannot be in the past.'; end if;
 if exists(select 1 from public.interviews i where i.recruiter_id=auth.uid() and i.starts_at<v_end and i.ends_at>p_starts_at) then raise exception 'This interview time conflicts with another interview.'; end if;
 insert into public.interviews(application_id,recruiter_id,starts_at,ends_at,location,meeting_link) values(p_application_id,auth.uid(),p_starts_at,v_end,p_location,p_meeting_link);
 update public.applications set stage='interview' where id=p_application_id; end; $$;
revoke all on function public.create_application(uuid),public.withdraw_application(uuid),public.advance_application(uuid,public.application_stage),public.schedule_interview(uuid,timestamptz,text,text) from public;
grant execute on function public.create_application(uuid),public.withdraw_application(uuid),public.advance_application(uuid,public.application_stage),public.schedule_interview(uuid,timestamptz,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('cvs','cvs',false,2097152,array['application/pdf']) on conflict(id) do nothing;
create policy "candidates upload private cvs" on storage.objects for insert to authenticated with check(bucket_id='cvs' and (storage.foldername(name))[1]=(select auth.uid()::text) and storage.extension(name)='pdf');
create policy "candidates read own cvs" on storage.objects for select to authenticated using(bucket_id='cvs' and owner_id=(select auth.uid()::text));
create policy "candidates replace own cvs" on storage.objects for update to authenticated using(bucket_id='cvs' and owner_id=(select auth.uid()::text)) with check(bucket_id='cvs' and owner_id=(select auth.uid()::text));
create policy "candidates remove own cvs" on storage.objects for delete to authenticated using(bucket_id='cvs' and owner_id=(select auth.uid()::text));

alter publication supabase_realtime add table public.jobs,public.applications,public.interviews,public.ai_summaries;
