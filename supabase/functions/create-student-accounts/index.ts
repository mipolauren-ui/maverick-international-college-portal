import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const loginDomain = 'students.maverick-international-college-port.vercel.app';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return respond({ error: 'Method not allowed.' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) return respond({ error: 'Sign in as an authorized school administrator.' }, 401);

  const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: userError } = await callerClient.auth.getUser();
  if (userError || !user) return respond({ error: 'Your session is invalid or has expired.' }, 401);
  const { data: callerProfile } = await callerClient.from('profiles').select('role').eq('id', user.id).single();
  if (!callerProfile || !['super_admin', 'principal', 'vice_principal', 'admin'].includes(callerProfile.role)) {
    return respond({ error: 'Only an authorized school administrator can create student accounts.' }, 403);
  }

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const body = await request.json().catch(() => ({}));
  const level = String(body.level || 'J3').toUpperCase();
  if (!['J1', 'J2', 'J3', 'S1', 'S2', 'S3'].includes(level)) {
    return respond({ error: 'Choose a valid class level.' }, 400);
  }
  const levelIds: Record<string, string> = { J1: 'J1', J2: 'J2', J3: 'J3', S1: 'S1', S2: 'S2', S3: 'S3' };
  const prefix = `MAV/${levelIds[level]}/`;
  const { data: roster, error: rosterError } = await admin.from('students')
    .select('id,profile_id,student_number,surname,given_name,middle_name,status')
    .eq('status', 'active').like('student_number', `${prefix}%`).order('student_number');
  if (rosterError) return respond({ error: 'Could not read the student register: ' + rosterError.message }, 500);

  const eligible = (roster || []).filter((student) => !student.profile_id && student.surname.trim());
  const results = [];
  for (const student of eligible) {
    const studentId = student.student_number.trim().toUpperCase();
    const email = `${studentId.toLowerCase().replaceAll('/', '-')}@${loginDomain}`;
    const passwordBase = `${student.surname.trim()[0].toUpperCase()}${student.surname.trim().slice(1).toLowerCase()}@6`;
    // Supabase enforces a six-character minimum; pad short surnames (for example, Ani@6).
    const temporaryPassword = passwordBase.length < 6 ? `${passwordBase}0` : passwordBase;
    const fullName = [student.given_name, student.middle_name, student.surname].filter(Boolean).join(' ').trim();
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email, password: temporaryPassword, email_confirm: true,
      user_metadata: { full_name: fullName, must_change_password: true },
    });
    if (createError || !created.user) {
      results.push({ studentId, name: fullName, status: 'failed', error: createError?.message || 'Account was not returned.' });
      continue;
    }

    const { error: profileError } = await admin.from('profiles').update({
      full_name: fullName, role: 'student', must_change_password: true,
    }).eq('id', created.user.id);
    const { error: linkError } = await admin.from('students').update({ profile_id: created.user.id }).eq('id', student.id);
    if (profileError || linkError) {
      await admin.auth.admin.deleteUser(created.user.id);
      results.push({ studentId, name: fullName, status: 'failed', error: 'Could not link account to student register.' });
      continue;
    }
    results.push({ studentId, name: fullName, username: studentId, temporaryPassword, status: 'created' });
  }

  return respond({
    created: results.filter((item) => item.status === 'created').length,
    skipped: (roster || []).length - eligible.length,
    failed: results.filter((item) => item.status === 'failed').length,
    accounts: results,
  }, 200);
});

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
