# Security audit: Comence Results Portal
Audit date: 15 November 2026. Scope: browser pages (`index.html`, `app.js`, `style.css`, `config.js`), the account function (`api/teachers.js`), hosting settings (`vercel.json`), and the Supabase database (schema, row-level security, functions, permissions, updates 2 to 7).

## 1. How the audit was done
| Layer | Method |
|---|---|
| Database | Ran all scripts on a real PostgreSQL 16 with Supabase-style roles. Automated checks (row-level security on every table, fixed search path on privileged functions, public permissions), then hands-on attacks as an outsider, a self-registered stranger, a teacher, an admin and a parent. |
| Account function | Wrote 19 abuse tests against a simulated Supabase (wrong roles, weak passwords, malformed input, cross-site calls, partial failures, runaway requests). |
| Browser | Loaded every screen (21 views, both report types, import preview, error messages) with hostile script-injection text in every field and checked nothing executed. Scanned the code for dangerous constructs. Tested the new protections. |
| Third-party code | Checked pinned versions for known vulnerabilities; computed integrity hashes. |
| Not possible from here | Your live Supabase and Vercel dashboards, a real-browser test of the content security policy, and a professional penetration test. See section 5. |

## 2. Findings and fixes
Severity is my judgement for a school holding children's records. "Fixed" means fixed in the files you push and verified by tests.

| # | Severity | Layer | Finding | How it was shown | Fix | Status |
|---|---|---|---|---|---|---|
| 1 | **High** (if public sign-up is on, which is Supabase's default) | Database | Anyone could register themselves and automatically receive a teacher-level login. A stranger could read subjects and remark lists, invent fake terms, and claim an unassigned class (then add pupils while a roster is open). | Created a stranger account and ran each action. | Staff approval gate: new accounts are inactive until the portal's account function approves them. Every staff permission now requires an approved account; the page signs an unapproved account straight out. | Fixed. Still switch sign-ups off (section 4). |
| 2 | Medium | Database | The public could run internal helper functions, for example burn admission numbers or probe whether a class has submitted. | Called them as the public role. | All function permissions removed, then only the ones the app needs granted back. Only the parent PIN function is public. | Fixed |
| 3 | Medium | Database | **Parent lock-out attack.** Admission numbers are sequential, and 5 wrong tries locked a PIN until an admin intervened, so anyone could lock out every parent. | Locked a real parent out with 5 guesses. | Pause is 15 minutes and lifts by itself. One device making more than 20 failed tries in 15 minutes is throttled. | Fixed |
| 4 | Low to medium | Database | The parent portal gave different messages for "locked", "expired" and "wrong", revealing which admission numbers have PINs. Timing also differed. | Compared messages. | One message for every failure. "Expired" is only shown to someone holding the correct PIN. Equal work is done for unknown numbers. | Fixed |
| 5 | Medium | Database and page | Any teacher could create arbitrary terms (for example 9999/0000). | Called the function as a teacher. | Only admins can create terms, with format checks. Teachers pick from the existing list. | Fixed |
| 6 | Low | Database | No size limits: a 100,000-character name or thousands of pupils in one call were accepted. | Tested both. | Maximum 200 pupils per call, names up to 120 characters, dates of birth must be realistic, plus database limits on remark and signature sizes. | Fixed |
| 7 | Medium | Page | The Excel library (SheetJS 0.18.5) has known weaknesses when reading crafted spreadsheets (CVE-2023-30533, CVE-2024-22363). Import is admin-only, but a booby-trapped file could be emailed to the admin. | Version check. | Import only runs with the current official reader (0.20.3). If it cannot load, import is switched off and export still works from a pinned copy with an integrity hash. Import also rejects non-.xlsx files, files over 10 MB, and sheets over 50,000 rows. | Fixed. Small residual risk below. |
| 8 | Medium | Hosting | No content security policy, so any future script-injection mistake could steal a login (the login token is kept in the browser). | Header check. | Code moved to separate files so no inline scripts are needed; a strict policy now allows scripts only from this site and two named libraries. Also HSTS, Permissions-Policy, frame blocking, no-referrer and same-origin isolation. | Fixed. Untested in a real browser. |
| 9 | Low | Page | The main library was loaded from a public CDN without an integrity check. | Code review. | Integrity hash added; a tampered file will not run. | Fixed |
| 10 | Low | Account function | Weak password rule (8 characters), no check that the user ID is a real ID, no cross-site check, no audit trail, and a half-created account could be left behind if setup failed. | Abuse tests. | 10+ characters with common and repeated passwords refused; IDs validated; cross-site calls refused; every create, reset and delete is recorded; a failed setup deletes the half-made login; a brake on runaway requests. | Fixed |
| 11 | Low | Database | PIN issuing and account actions left no record. | Code review. | Recorded in `audit_log` (who, what, when). | Fixed. There is no screen to read the log yet; use the Supabase Table Editor. |
| 12 | Low | Page | New passwords were typed into a plain-text prompt box. | Code review. | Masked password dialog, minimum 10 characters. | Fixed |
| 13 | Low | Database | Parent reports included the pupil's date of birth, which is not displayed. | Inspected the report data. | Removed from the parent response. | Fixed |
| 14 | Low | Page | A badly formed parent email could add extra recipients to the email-the-PIN link. | Code review. | Only plain, valid addresses are accepted. | Fixed |
| 15 | Low | Page | If the secret `service_role` key were pasted into `config.js` it would be published to the world. | Code review. | The page refuses to start and shows a warning if it finds that key. | Fixed |

### Checked and found sound
- Row-level security is switched on for all 18 tables, and every privileged function pins its search path (automated check, repeated after the fixes).
- The public role has no table access at all; after the fixes it can run only the parent PIN function.
- A teacher cannot read other classes, PIN hashes, settings, the audit log or other accounts, cannot change their own role, move a pupil's class or change an admission number, and cannot admit pupils into a locked term. Roster promotion and admission rules were tested.
- Script injection: hostile text through all 21 screens, both report types, import preview and error messages did not execute or create elements.
- PINs: 8 characters from a 32-character alphabet (40 bits) generated with a secure random source, stored only as bcrypt hashes, shown once.
- The secret service key is used only inside the Vercel function; no secrets are in the project files.
- Cross-site request forgery is not possible against the account function (bearer token plus same-origin check). No SQL injection path: the app calls fixed functions with parameters.

## 3. Residual risks (accepted or for later)
1. **Login token in browser storage.** The Supabase library keeps it in localStorage; the content security policy is the main defence. A server-side session timeout needs a paid Supabase plan. The 30-minute idle logout is enforced in the page.
2. **No multi-factor sign-in.** Supabase supports it; the portal does not yet ask for it. Recommended for the super admin and proprietress.
3. **Excel reader (0.20.3) is loaded without an integrity hash** because the vendor's hash could not be fetched here. Safer option: download that file once from the vendor's site, put it in the project, and load it from there.
4. **Throttling by device** relies on address headers added by Supabase's network. If a header is missing or forged, only that extra throttle is weakened; the per-pupil 15-minute pause still stops guessing.
5. **PIN sent in an email** is plain text (inherent to email). Giving it on paper or by WhatsApp is equivalent or safer.
6. **Staff can see children's names, dates of birth and parent emails** in their own scope. This is by design; keep accounts personal and delete accounts of people who leave.
7. **The audit log has no screen.**
8. **Older Supabase library (2.45.4)** is pinned because it is tested and working. Plan a tested upgrade.

## 4. Actions for you (checklist)
**Before running `update-7-security.sql`**
- [ ] Supabase > Authentication > **Users**: look for any account you do not recognise and delete it. Update 7 approves every account that exists when it runs. You can also run `select email, role, created_at from profiles order by created_at;`.

**Deploy order:** run `update-7-security.sql`, then push the files straight after (listed in the README).

**Supabase dashboard**
- [ ] Authentication > Sign In / Providers > Email: switch **off** "Allow new users to sign up". (Update 7 protects you if it stays on, but there is no reason to leave it on.)
- [ ] Authentication > password settings: minimum length 10 or more.
- [ ] Authentication > Multi-factor: enable TOTP and enrol the super admin and proprietress.
- [ ] Authentication > URL Configuration: only your real site address in Site URL and Redirect URLs.
- [ ] Backups: export the data to Excel at the end of each term (Excel data tab). Confirm what backup your Supabase plan includes.
- [ ] If the `service_role` key was ever pasted anywhere public (chat, GitHub, screenshot), rotate it (Project Settings > API) and update the Vercel variable.

**Vercel**
- [ ] Turn on two-factor sign-in for your Vercel account.
- [ ] Project Settings > Deployment Protection: protect preview deployments.
- [ ] Project Settings > Functions: set the function region to Dublin (also speeds up account actions).

**GitHub**
- [ ] Repository is **private**; two-factor sign-in on; secret scanning with push protection on (Settings > Code security).
- [ ] Check the history for leaked keys: `git log -p -S service_role` and `git log -p -S "eyJ"` (the second finds the public anon key, which is fine; it should show no service key).

**Data protection (Nigeria Data Protection Act 2023; seek advice for your situation)**
- [ ] Tell parents what is kept (names, dates of birth, results, parent email), why, and for how long.
- [ ] Decide how long leavers' records are kept and delete or export them when that ends.
- [ ] Know the process for reporting a breach to the Nigeria Data Protection Commission (within 72 hours) and to affected parents.

## 5. What is not covered
This audit did not test your live Supabase and Vercel settings, the content security policy in real browsers, mobile devices, or network-level attacks, and it is not a professional penetration test. Before selling the system to other schools, commission an independent penetration test and a data protection review.
