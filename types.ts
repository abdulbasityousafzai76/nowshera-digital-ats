export type Role='candidate'|'recruiter'|'admin';
export type Stage='applied'|'shortlisted'|'interview'|'offer'|'hired'|'rejected'|'withdrawn';
export type Job={id:string;title:string;department:string;location:string;job_type:string;description:string;requirements:string;last_date:string;openings:number;status:'draft'|'open'|'closed';created_at:string};
export type Profile={id:string;full_name:string;phone:string|null;role:Role;active?:boolean};
export type RecruiterNote={id:string;body:string;created_at:string;recruiter?:Profile};
export type Application={id:string;stage:Stage;created_at:string;cv_path:string;job:Job;interview?:{starts_at:string;location:string|null;meeting_link:string|null}|null;ai_summary?:{status:string;profile_bullets:string[];requirements_found:string[];requirements_missing:string[];interview_questions:string[]}|null;candidate?:Profile;notes?:RecruiterNote[]};
