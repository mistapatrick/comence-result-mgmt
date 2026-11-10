# Architecture
GitHub (code) -> Vercel (static site + one small API function) -> Supabase (Postgres, Auth, row-level security).

- Browser talks to Supabase directly with the public anon key; every table is protected by row-level security (teachers see only their class; admin sees all; the public sees nothing).
- Parents have no account: the `parent_report(admission_no, pin)` database function checks the PIN hash, expiry and failed attempts, then returns the report.
- `api/teachers.js` is the only server code. It uses the service-role key (kept in Vercel, never in the browser) to create teacher logins.
- Scores: CA 0-40, Exam 0-60, total 100 per subject. Grades from table `grade_scale`. Position by average within class and term.
- Report card compulsory: position and class size, class teacher's and head teacher's remarks, next term's resumption date, fees outstanding. Optional: attendance, behaviour ratings.
