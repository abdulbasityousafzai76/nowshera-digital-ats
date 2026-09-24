import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const auth = req.headers.get('Authorization') || '';
    const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } });
    const { data: { user } } = await client.auth.getUser();
    if (!user) throw new Error('Please sign in first.');

    const { application_id } = await req.json();
    if (!application_id) throw new Error('Application is required.');
    const { data: me } = await client.from('profiles').select('role').eq('id', user.id).single();
    if (!me || !['admin', 'recruiter'].includes(me.role)) throw new Error('Only recruiters and admins can retry a summary.');

    const { data: application } = await client.from('applications').select('id,job_id').eq('id', application_id).single();
    if (!application) throw new Error('You cannot access this application.');
    if (me.role === 'recruiter') {
      const { data: assignment } = await client.from('recruiter_job_assignments').select('job_id').eq('job_id', application.job_id).eq('recruiter_id', user.id).maybeSingle();
      if (!assignment) throw new Error('You are not assigned to this job.');
    }

    const webhook = Deno.env.get('N8N_AI_SUMMARY_WEBHOOK_URL');
    const secret = Deno.env.get('ATS_WEBHOOK_SECRET');
    if (!webhook || !secret) throw new Error('AI automation is not configured yet.');
    const response = await fetch(webhook, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-ats-secret': secret }, body: JSON.stringify({ application_id }) });
    if (!response.ok) throw new Error('Could not request the AI summary. Please try again.');
    return Response.json({ ok: true }, { headers: cors });
  } catch (error) {
    return Response.json({ error: error.message }, { status: 400, headers: cors });
  }
});
