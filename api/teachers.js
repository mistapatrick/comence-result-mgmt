// Vercel serverless function: account management (create, reset password, delete).
// Rules: the super admin manages admin and teacher accounts; an ordinary admin (e.g. the proprietress)
// manages teacher accounts only; nobody can delete the super admin or their own account.
// Needs Vercel environment variables: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
const U = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const svc = { apikey: SVC, Authorization: 'Bearer ' + SVC, 'Content-Type': 'application/json' };
const enc = encodeURIComponent;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const COMMON = ['password', 'password1', 'password12', 'password123', 'qwerty123', 'qwertyuiop', '1234567890', '0123456789', 'iloveyou12', 'comence123', 'comence2026', 'school1234', 'welcome123', 'abc1234567', 'letmein123'];

// small per-instance brake against runaway scripts (serverless instances are short-lived, so this is only a backstop)
const hits = new Map();
const tooMany = (id) => { const now = Date.now(), a = (hits.get(id) || []).filter(t => now - t < 600000); a.push(now); hits.set(id, a); return a.length > 40; };

function weakPassword(pw, email) {
  if (pw.length < 10) return 'Password must be at least 10 characters.';
  if (pw.length > 72) return 'Password is too long (maximum 72 characters).';
  const low = pw.toLowerCase();
  if (COMMON.includes(low) || /^(.)\1+$/.test(pw)) return 'That password is too easy to guess. Choose a different one.';
  const local = String(email || '').split('@')[0].toLowerCase();
  if (local.length >= 4 && low.includes(local)) return 'The password must not contain the email name.';
  return null;
}
const clean = (m, d) => (typeof m === 'string' && m.length < 200 ? m : d);

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  const fail = (c, e) => res.status(c).json({ error: e });
  try {
    if (req.method !== 'POST') return fail(405, 'POST only');
    const site = req.headers['sec-fetch-site'];
    if (site && !['same-origin', 'none'].includes(site)) return fail(403, 'Request refused.');
    if (!U || !ANON || !SVC) return fail(500, 'Server is not configured (missing environment variables).');

    // 1. who is calling? (the token is checked with the Supabase login service)
    const token = (req.headers.authorization || '').replace(/^Bearer /, '');
    if (!token) return fail(401, 'Please log in again.');
    const who = await fetch(U + '/auth/v1/user', { headers: { apikey: ANON, Authorization: 'Bearer ' + token } });
    if (!who.ok) return fail(401, 'Please log in again.');
    const me = await who.json();
    if (!me || !UUID.test(me.id || '')) return fail(401, 'Please log in again.');

    // 2. are they an approved admin, and a super admin?
    const pr = await fetch(U + '/rest/v1/profiles?id=eq.' + enc(me.id) + '&select=role,is_super,active', { headers: svc });
    const pj = await pr.json();
    if (!pr.ok || !Array.isArray(pj)) return fail(500, 'The database needs the latest update (update 7) to be run first.');
    const prof = pj[0];
    if (!prof || prof.role !== 'admin' || !prof.active) return fail(403, 'Admin only.');
    const sup = !!prof.is_super;
    if (tooMany(me.id)) return fail(429, 'Too many requests. Please wait a few minutes.');

    let b = req.body;
    if (typeof b === 'string') { try { b = JSON.parse(b); } catch (e) { return fail(400, 'Bad request.'); } }
    if (!b || typeof b !== 'object') return fail(400, 'Bad request.');

    const audit = (action, detail) => fetch(U + '/rest/v1/audit_log', { method: 'POST', headers: { ...svc, Prefer: 'return=minimal' },
      body: JSON.stringify({ user_id: me.id, action, row_new: detail }) }).catch(() => {});
    const target = async (id) => {
      const r = await fetch(U + '/rest/v1/profiles?id=eq.' + enc(id) + '&select=id,role,is_super,email', { headers: svc });
      const a = await r.json();
      return Array.isArray(a) ? a[0] : null;
    };

    if (b.action === 'create') {
      const role = b.role === 'admin' ? 'admin' : 'teacher';
      if (role === 'admin' && !sup) return fail(403, 'Only the super admin can create admin accounts.');
      const email = String(b.email || '').trim().toLowerCase(), name = String(b.full_name || '').trim();
      if (email.length > 120 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return fail(400, 'Enter a valid email address.');
      if (!name || name.length > 100) return fail(400, 'Enter the person’s name (up to 100 characters).');
      const weak = weakPassword(String(b.password || ''), email);
      if (weak) return fail(400, weak);
      const r = await fetch(U + '/auth/v1/admin/users', { method: 'POST', headers: svc,
        body: JSON.stringify({ email, password: b.password, email_confirm: true, user_metadata: { full_name: name } }) });
      const j = await r.json();
      if (!r.ok) return fail(400, /already|registered|exists/i.test(String(j.msg || j.message || '')) ? 'An account with this email already exists.' : clean(j.msg || j.message, 'Could not create the account.'));
      // approve the account (self-registered strangers are never approved) and set its role
      const p = await fetch(U + '/rest/v1/profiles?id=eq.' + enc(j.id), { method: 'PATCH', headers: { ...svc, Prefer: 'return=minimal' }, body: JSON.stringify({ role, active: true }) });
      if (!p.ok) {
        await fetch(U + '/auth/v1/admin/users/' + enc(j.id), { method: 'DELETE', headers: svc }).catch(() => {});
        return fail(500, 'The account could not be set up, so it was not created. Please try again.');
      }
      await audit('ACCOUNT_CREATE', { target: j.id, email, role });
      return res.status(200).json({ ok: true, id: j.id });
    }

    if (b.action === 'reset' || b.action === 'delete') {
      if (!UUID.test(String(b.user_id || ''))) return fail(400, 'Bad request.');
      const t = await target(b.user_id);
      if (!t) return fail(404, 'Account not found.');
      if (b.action === 'reset') {
        const weak = weakPassword(String(b.password || ''), t.email);
        if (weak) return fail(400, weak);
        if (t.is_super && t.id !== me.id) return fail(403, 'The super admin’s password can only be changed by the super admin (Change password).');
        if (t.role === 'admin' && !t.is_super && !sup) return fail(403, 'Only the super admin can reset an admin password.');
        const r = await fetch(U + '/auth/v1/admin/users/' + enc(t.id), { method: 'PUT', headers: svc, body: JSON.stringify({ password: b.password }) });
        if (!r.ok) return fail(400, 'Could not reset the password.');
        await audit('ACCOUNT_RESET_PASSWORD', { target: t.id, email: t.email });
        return res.status(200).json({ ok: true });
      }
      if (t.id === me.id) return fail(400, 'You cannot delete your own account.');
      if (t.is_super) return fail(403, 'The super admin account cannot be deleted.');
      if (t.role === 'admin' && !sup) return fail(403, 'Only the super admin can delete admin accounts.');
      const r = await fetch(U + '/auth/v1/admin/users/' + enc(t.id), { method: 'DELETE', headers: svc });
      if (!r.ok) return fail(400, 'Could not delete the account.');
      await audit('ACCOUNT_DELETE', { target: t.id, email: t.email, role: t.role });
      return res.status(200).json({ ok: true });
    }
    return fail(400, 'Unknown action.');
  } catch (e) {
    return fail(500, 'Something went wrong. Please try again.');
  }
};
