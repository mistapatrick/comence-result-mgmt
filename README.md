# Comence Results Portal (proof of concept, 1st Term 2026/2027)

Comence Nursery & Primary School, Narayi Highcost, Kaduna.
Teachers log in, set their class and term, add pupils, tick the subjects each pupil took and enter CA (0-40) and Exam (0-60). The admin (super user) reviews, adds the head teacher's remark and fees outstanding, then prints reports or gives parents a PIN. Parents open the portal with Admission Number + PIN until the PIN expires.

## Files
| File | What it is |
|---|---|
| `index.html` | The whole app (teacher, admin, parent screens) |
| `config.js` | **You edit this**: Supabase address and public key, school contacts |
| `logo.png` | School logo (used on screens and report cards) |
| `api/teachers.js` | Lets the admin create teacher logins and reset passwords |
| `supabase/schema.sql` | The database, grading, subjects, security rules, PIN logic |
| `vercel.json`, `package.json`, `.gitignore` | Hosting settings |

Cost: GitHub, Vercel Hobby and Supabase Free are all free for this proof of concept.

---
## Step 1: Create the database (Supabase)
1. Go to supabase.com, sign up and click **New project**. Name it `comence-results`, set a database password (save it) and choose the nearest region offered.
2. Wait until it finishes, then open **SQL Editor > New query**, paste the whole of `supabase/schema.sql` and press **Run**. It should say "Success". This creates all tables, the 18 classes (Playgroup to Primary 6, arms A and B), the 7 Nursery and 14 Primary subjects, the grade scale (A 90-100, B+ 70-89, B 60-69, C 50-59, D 40-49, E 0-39) and the 2026/2027 1st Term.
3. **Create the admin login:** Authentication > Users > **Add user > Create new user**. Enter the admin email and password and tick **Auto Confirm User**.
4. **Make that user the admin:** SQL Editor, run (use the admin's email):
```
update profiles set role = 'admin' where email = 'ADMIN-EMAIL-HERE';
```
5. **Collect three values** (Project Settings > API):
   - Project URL
   - `anon` `public` key
   - `service_role` key (secret: never put it in a file or share it)
6. Authentication > Sign In / Providers > Email: turn **off** "Allow new users to sign up" (only the admin creates logins).

## Step 2: Put the code on GitHub
1. Open `config.js` and replace `SUPABASE_URL` and `SUPABASE_ANON_KEY` with the values from step 1.5 (URL and anon key only).
2. Create a **private** repository on github.com named `comence-results` (do not add a README there). In this folder run:
```
git init
git add .
git commit -m "Comence results portal"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/comence-results.git
git push -u origin main
```

## Step 3: Deploy on Vercel
1. vercel.com > sign in with GitHub > **Add New > Project** > import `comence-results`.
2. Framework Preset: **Other**. Leave build and output settings empty.
3. Open **Environment Variables** and add (needed for the "create teacher login" feature):
   - `SUPABASE_URL` = your Project URL
   - `SUPABASE_ANON_KEY` = your anon key
   - `SUPABASE_SERVICE_ROLE_KEY` = your service_role key
4. Click **Deploy**. Every later `git push` redeploys.
5. Supabase > Authentication > URL Configuration: set **Site URL** to your Vercel address.

## Step 4: First-term use
**Admin**
1. Log in. **Terms** tab: set "Next term begins" for 1st Term 2026/2027 (compulsory on reports).
2. **Subjects** tab: check or rename subjects if needed.
3. **Teachers & classes** tab: create each teacher's login (name, email, starting password), then assign classes (or let teachers pick their own class in step 1 of their screen).
4. **Reports & PINs** tab, after teachers submit: add the head teacher's remark and fees outstanding (0 if none) for each pupil, then **View / print report** or **Generate PIN**. Choose how long the PIN stays valid (7 to 45 days). The PIN is shown once.
5. Give parents the website address with `#parent` at the end, their child's Admission Number and the PIN, or use "Email this to the parent". **Print all ready reports** makes one page per pupil (choose "Save as PDF" to keep a file).

**Teacher** (steps 1 to 6 on their screen): class and term, add pupils (one name per line), tick subjects each pupil took, enter scores (saves as you type), class teacher's remark (attendance and behaviour optional), then **Submit**. After submitting, only the admin can unlock.

**Parent:** website address, Admission Number + PIN, then Print / Save as PDF. After the PIN expires or after 5 wrong tries the report cannot be opened until the school issues a new PIN.

## Notes
- **Position** is ranked by the pupil's average across the subjects taken, so a pupil who took fewer subjects is not unfairly ranked. Class size is the number of active pupils in the class.
- **Expired PINs:** access stops the moment a PIN expires. To also wipe expired PIN data nightly, enable `pg_cron` in Supabase (Database > Extensions) and run the commented `cron.schedule` line at the end of `schema.sql`.
- **Contact details:** parents see the address, 09128982879 (call/WhatsApp) and comence.schools@gmail.com. The technical support number 09053903530 shows only on staff screens. Change any of these in `config.js`.
- **Before real data:** keep the repository private. Supabase Free pauses a project after about a week with no activity (open the dashboard to resume it) and Vercel Hobby is for non-commercial use, so move both to paid plans for long-term or multi-school use. Pupils are children: keep access limited to staff, and follow the Nigeria Data Protection Act 2023.
- **Backups:** each term, use Supabase > Table Editor > Export to CSV for `pupils`, `scores` and `remarks`.
- **Not included yet:** CSV import of pupils, admin editing of scores (the admin unlocks and the teacher edits), and automatic emailing with an attached PDF (the email button opens your mail app with the PIN message).
- **Troubleshooting:** blank page or "Failed to fetch" means `config.js` still has the placeholder values. "Create login" failing means the three Vercel environment variables are missing (redeploy after adding them).
