// Vercel serverless function: lets the admin create teacher logins and reset passwords.
// Needs Vercel environment variables: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
const U = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const svc = { apikey: SVC, Authorization: 'Bearer ' + SVC, 'Content-Type': 'application/json' };

module.exports = async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    if (!U || !ANON || !SVC) return res.status(500).json({ error: 'Server is not configured (missing environment variables).' });

    // 1. who is calling?
    const token = (req.headers.authorization || '').replace('Bearer ', '');
    const who = await fetch(U + '/auth/v1/user', { headers: { apikey: ANON, Authorization: 'Bearer ' + token } });
    if (!who.ok) return res.status(401).json({ error: 'Please log in again.' });
    const me = await who.json();

    // 2. are they an admin?
    const pr = await fetch(U + '/rest/v1/profiles?id=eq.' + encodeURIComponent(me.id) + '&select=role', { headers: svc });
    const prof = (await pr.json())[0];
    if (!prof || prof.role !== 'admin') return res.status(403).json({ error: 'Admin only.' });

    const b = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    if (b.action === 'create') {
      const email = String(b.email || '').trim().toLowerCase(), name = String(b.full_name || '').trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: 'Enter a valid email address.' });
      if (!name) return res.status(400).json({ error: 'Enter the teacher’s name.' });
      if (String(b.password || '').length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters.' });
      const r = await fetch(U + '/auth/v1/admin/users', { method: 'POST', headers: svc,
        body: JSON.stringify({ email, password: b.password, email_confirm: true, user_metadata: { full_name: name } }) });
      const j = await r.json();
      if (!r.ok) return res.status(400).json({ error: j.msg || j.message || 'Could not create the account.' });
      return res.status(200).json({ ok: true, id: j.id });
    }
    if (b.action === 'reset') {
      if (String(b.password || '').length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters.' });
      const r = await fetch(U + '/auth/v1/admin/users/' + encodeURIComponent(b.user_id), { method: 'PUT', headers: svc,
        body: JSON.stringify({ password: b.password }) });
      const j = await r.json();
      if (!r.ok) return res.status(400).json({ error: j.msg || j.message || 'Could not reset the password.' });
      return res.status(200).json({ ok: true });
    }
    return res.status(400).json({ error: 'Unknown action.' });
  } catch (e) {
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
};
