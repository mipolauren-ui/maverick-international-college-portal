import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const redirectTo = 'https://maverick-international-college-port.vercel.app/login?role=teacher';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return respond({ error: 'Method not allowed.' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return respond({ error: 'Teacher account service is not configured.' }, 500);

  const authorization = request.headers.get('Authorization');
  if (!authorization) return respond({ error: 'Sign in as an authorized school administrator.' }, 401);
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return respond({ error: 'Your administrator session is invalid or expired.' }, 401);
  const { data: callerProfile } = await caller.from('profiles').select('role').eq('id', user.id).single();
  if (!callerProfile || !['super_admin', 'principal', 'vice_principal', 'admin'].includes(callerProfile.role)) {
    return respond({ error: 'Only an authorized school administrator can create teacher accounts.' }, 403);
  }

  const body = await request.json().catch(() => ({}));
  const fullName = String(body.fullName || '').trim().replace(/\s+/g, ' ');
  const preferredName = String(body.preferredName || '').trim().replace(/\s+/g, ' ');
  const email = String(body.email || '').trim().toLowerCase();
  const phone = String(body.phone || '').trim();
  const subjectName = String(body.subject || '').trim().replace(/\s+/g, ' ');
  const photoBase64 = String(body.photoBase64 || '');
  const photoMime = String(body.photoMime || '');
  if (fullName.length < 3 || preferredName.length < 1 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return respond({ error: 'Enter a valid full name, preferred name, and email address.' }, 400);
  }
  if (!/^\+?[0-9(). -]{7,24}$/.test(phone)) return respond({ error: 'Enter a valid phone number.' }, 400);
  if (!subjectName || subjectName.length > 100) return respond({ error: 'Enter at least one teaching subject.' }, 400);
  if (photoBase64 && (!['image/jpeg', 'image/png', 'image/webp'].includes(photoMime) || photoBase64.length > 7_000_000)) {
    return respond({ error: 'Choose a JPG, PNG, or WebP portrait smaller than 5 MB.' }, 400);
  }

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  for (let page = 1; ; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) return respond({ error: 'Could not verify existing accounts: ' + error.message }, 500);
    if ((data.users || []).some((account) => account.email?.toLowerCase() === email)) {
      return respond({ error: 'An account already exists for this email. Review the existing account before creating another.' }, 409);
    }
    if (!data.users || data.users.length < 1000) break;
  }

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo,
    data: { full_name: fullName, preferred_name: preferredName, phone, role: 'teacher' },
  });
  if (inviteError || !invited.user) return respond({ error: inviteError?.message || 'The invitation could not be sent.' }, 400);
  const profileId = invited.user.id;
  let avatarPath: string | null = null;

  try {
    const { data: subjectRows, error: subjectLookupError } = await admin.from('subjects')
      .select('id,name').ilike('name', subjectName).limit(1);
    if (subjectLookupError) throw subjectLookupError;
    let subjectId = subjectRows?.[0]?.id;
    if (!subjectId) {
      const { data: insertedSubject, error: insertSubjectError } = await admin.from('subjects')
        .insert({ name: subjectName }).select('id').single();
      if (insertSubjectError) throw insertSubjectError;
      subjectId = insertedSubject.id;
    }

    if (photoBase64) {
      const bytes = Uint8Array.from(atob(photoBase64), (character) => character.charCodeAt(0));
      const extension = photoMime === 'image/jpeg' ? 'jpg' : photoMime.split('/')[1];
      avatarPath = `${profileId}/profile.${extension}`;
      const { error: uploadError } = await admin.storage.from('profile-photos').upload(
        avatarPath, bytes, { contentType: photoMime, upsert: true },
      );
      if (uploadError) throw uploadError;
    }

    const { error: profileError } = await admin.from('profiles').update({
      full_name: fullName, preferred_name: preferredName, contact_email: email,
      phone, role: 'teacher', avatar_path: avatarPath,
    }).eq('id', profileId);
    if (profileError) throw profileError;

    const { error: subjectLinkError } = await admin.from('teacher_subjects')
      .insert({ teacher_profile_id: profileId, subject_id: subjectId });
    if (subjectLinkError) throw subjectLinkError;

    await admin.from('audit_logs').insert({
      actor_id: user.id, action: 'teacher_account_invited', table_name: 'profiles',
      record_id: profileId, new_value: { full_name: fullName, email, subject: subjectName },
      reason: 'Teacher account created through the administrator workflow.',
    });
    return respond({ invited: true, teacher: fullName, email, subject: subjectName, photoUploaded: Boolean(avatarPath) });
  } catch (error) {
    if (avatarPath) await admin.storage.from('profile-photos').remove([avatarPath]);
    await admin.auth.admin.deleteUser(profileId);
    return respond({ error: 'Account setup did not finish: ' + (error instanceof Error ? error.message : String(error)) }, 500);
  }
});

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
