// Vercel serverless function: account management (create, reset password, delete).
// Rules: super admin manages admin and teacher accounts; an ordinary admin (e.g. the proprietress)
// manages teacher accounts only; nobody can delete the super admin or their own account.
// Needs Vercel environment variables: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
const U = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const svc = { apikey: SVC, Authorization: 'Bearer ' + SVC, 'Content-Type': 'application/json' };
const enc = encodeURIComponent;

module.exports = async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    if (!U || !ANON || !SVC) return res.status(500).json({ error: 'Server is not configured (missing environment variables).' });

    // 1. who is calling?
    const token = (req.headers.authorization || '').replace('Bearer ', '');
    const who = await fetch(U + '/auth/v1/user', { headers: { apikey: ANON, Authorization: 'Bearer ' + token } });
    if (!who.ok) return res.status(401).json({ error: 'Please log in again.' });
    const me = await who.json();

    // 2. are they an admin, and a super admin?
    const pr = await fetch(U + '/rest/v1/profiles?id=eq.' + enc(me.id) + '&select=role,is_super', { headers: svc });
    const pj = await pr.json();
    if (!pr.ok || !Array.isArray(pj)) return res.status(500).json({ error: 'The database needs “update 5” (supabase/update-5-accounts.sql) to be run first.' });
    const prof = pj[0];
    if (!prof || prof.role !== 'admin') return res.status(403).json({ error: 'Admin only.' });
    const sup = !!prof.is_super;

    const target = async (id) => {
      const r = await fetch(U + '/rest/v1/profiles?id=eq.' + enc(id) + '&select=id,role,is_super', { headers: svc });
      const a = await r.json();
      return Array.isArray(a) ? a[0] : null;
    };
    const b = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});

    if (b.action === 'create') {
      const role = b.role === 'admin' ? 'admin' : 'teacher';
      if (role === 'admin' && !sup) return res.status(403).json({ error: 'Only the super admin can create admin accounts.' });
      const email = String(b.email || '').trim().toLowerCase(), name = String(b.full_name || '').trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: 'Enter a valid email address.' });
      if (!name) return res.status(400).json({ error: 'Enter the person’s name.' });
      if (String(b.password || '').length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters.' });
      const r = await fetch(U + '/auth/v1/admin/users', { method: 'POST', headers: svc,
        body: JSON.stringify({ email, password: b.password, email_confirm: true, user_metadata: { full_name: name } }) });
      const j = await r.json();
      if (!r.ok) return res.status(400).json({ error: j.msg || j.message || 'Could not create the account.' });
      if (role === 'admin') {
        const p = await fetch(U + '/rest/v1/profiles?id=eq.' + enc(j.id), { method: 'PATCH', headers: { ...svc, Prefer: 'return=minimal' }, body: JSON.stringify({ role: 'admin' }) });
        if (!p.ok) return res.status(500).json({ error: 'The account was created but could not be made an admin. Please try again or check the Supabase profiles table.' });
      }
      return res.status(200).json({ ok: true, id: j.id });
    }

    if (b.action === 'reset' || b.action === 'delete') {
      const t = await target(b.user_id);
      if (!t) return res.status(404).json({ error: 'Account not found.' });
      if (b.action === 'reset') {
        if (String(b.password || '').length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters.' });
        if (t.is_super && t.id !== me.id) return res.status(403).json({ error: 'The super admin’s password can only be changed by the super admin (Change password).' });
        if (t.role === 'admin' && !t.is_super && !sup) return res.status(403).json({ error: 'Only the super admin can reset an admin password.' });
        const r = await fetch(U + '/auth/v1/admin/users/' + enc(t.id), { method: 'PUT', headers: svc, body: JSON.stringify({ password: b.password }) });
        const j = await r.json();
        if (!r.ok) return res.status(400).json({ error: j.msg || j.message || 'Could not reset the password.' });
        return res.status(200).json({ ok: true });
      }
      if (t.id === me.id) return res.status(400).json({ error: 'You cannot delete your own account.' });
      if (t.is_super) return res.status(403).json({ error: 'The super admin account cannot be deleted.' });
      if (t.role === 'admin' && !sup) return res.status(403).json({ error: 'Only the super admin can delete admin accounts.' });
      const r = await fetch(U + '/auth/v1/admin/users/' + enc(t.id), { method: 'DELETE', headers: svc });
      if (!r.ok) return res.status(400).json({ error: 'Could not delete the account.' });
      return res.status(200).json({ ok: true });
    }
    return res.status(400).json({ error: 'Unknown action.' });
  } catch (e) {
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
};
