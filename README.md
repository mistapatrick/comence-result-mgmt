# Comence Results Portal (proof of concept, 1st Term 2026/2027)

> ## Already running an earlier version? Start here (do not reinstall)
> Your database, admin login, Supabase keys and Vercel settings stay exactly as they are. Do not run `schema.sql` again and do not delete anything.
> 1. Supabase > SQL Editor: run, **in this order and only the ones you have not run yet**, each file once (paste all of it, Run, choose "Run and enable RLS" if asked): `update-2-signatures-remarks.sql`, `update-3-classes-progress-dob.sql`, `update-4-tie-positions.sql`, `update-5-accounts.sql`, `update-6-roster.sql`.
> 2. Straight after the last SQL, push `index.html`, `api/teachers.js`, `README.md` and the new `.sql` files to GitHub. Leave your own `config.js` alone. Vercel redeploys by itself. (Push soon after update 6: the old screens do not know about the roster.)
> 3. Hard-refresh the site (Ctrl+Shift+R) and log in as admin. The sections "Update 3" to "Update 7" below describe what is new.
>
> Everything from "Step 1" to "Step 4" is the **first-time installation guide**, only for a brand-new setup.

Comence Nursery & Primary School, Narayi Highcost, Kaduna.
Teachers log in, set their class and term, add pupils, tick the subjects each pupil took and enter CA (0-40) and Exam (0-60). The admin (super user) reviews, adds the proprietress's remark and fees outstanding, then prints reports or gives parents a PIN. Parents open the portal with Admission Number + PIN until the PIN expires.

## Files
| File | What it is |
|---|---|
| `index.html` | The whole app (teacher, admin, parent screens) |
| `config.js` | **You edit this**: Supabase address and public key, school contacts |
| `logo.png` | School logo (used on screens and report cards) |
| `api/teachers.js` | Lets the admin create teacher logins and reset passwords |
| `supabase/schema.sql` | The database, grading, subjects, security rules, PIN logic. Run first. |
| `supabase/update-2-signatures-remarks.sql` | **Run second.** Signatures, class averages, preset remarks, free class names |
| `supabase/update-6-roster.sql` | **Run sixth.** School roster per term: promotion, repetition, admission numbers by year |
| `supabase/update-5-accounts.sql` | **Run fifth.** Super admin level above ordinary admins |
| `supabase/update-4-tie-positions.sql` | **Run fourth.** Tied positions (1st, 1st, 3rd) decided on the 3-decimal average |
| `supabase/update-3-classes-progress-dob.sql` | **Run third.** Real class names, Nursery progress reports, date of birth and ages, 3-decimal scores, safe admission numbers |
| `vercel.json`, `package.json`, `.gitignore` | Hosting settings |

Cost: GitHub, Vercel Hobby and Supabase Free are all free for this proof of concept.

---
## Step 1: Create the database (Supabase)
1. Go to supabase.com, sign up and click **New project**. Name it `comence-results`, set a database password (save it) and choose the nearest region offered.
2. Wait until it finishes, then open **SQL Editor > New query**, paste the whole of `supabase/schema.sql` and press **Run**. It should say "Success". This creates all tables, the first set of 18 classes (renamed to your real class names by update 3), the first Nursery and Primary subjects, the grade scale (A 90-100, B+ 70-89, B 60-69, C 50-59, D 40-49, E 0-39) and the 2026/2027 1st Term.
2b. **Run the second file:** New query, paste all of `supabase/update-2-signatures-remarks.sql`, press **Run** (choose **Run and enable RLS** if asked). It adds signatures, class averages on report cards, ready-made remarks, and lets you rename classes.
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
3. **Accounts & classes** tab: create each teacher's login (name, email, starting password), then assign classes (or let teachers pick their own class in step 1 of their screen).
4. **Reports & PINs** tab, after teachers submit: add the proprietress's remark and fees outstanding (0 if none) for each pupil, then **View / print report** or **Generate PIN**. Choose how long the PIN stays valid (7 to 45 days). The PIN is shown once.
5. Give parents the website address, their child's Admission Number and the PIN (they use the Parents section of the login page), or use "Email this to the parent". **Print all ready reports** makes one page per pupil (choose "Save as PDF" to keep a file).

**Teacher** (steps 1 to 6 on their screen): class and term, add pupils (name and date of birth, one per line), tick subjects each pupil took, enter scores or, in Nursery, subject remarks (saves as you type), general remarks (attendance and behaviour optional), then check the summary and **Submit**. After submitting, only the admin can unlock.

**Parent:** website address, Admission Number + PIN, then Print / Save as PDF. After the PIN expires or after 5 wrong tries the report cannot be opened until the school issues a new PIN.

## Notes
- **Position** is ranked by the pupil's average across the subjects taken, so a pupil who took fewer subjects is not unfairly ranked. Class size is the number of active pupils in the class.
- **Expired PINs:** access stops the moment a PIN expires. To also wipe expired PIN data nightly, enable `pg_cron` in Supabase (Database > Extensions) and run the commented `cron.schedule` line at the end of `schema.sql`.
- **Contact details:** parents see the address, 09128982879 (call/WhatsApp) and comence.schools@gmail.com. The technical support number 09053903530 shows only on staff screens. Change any of these in `config.js`.
- **Before real data:** keep the repository private. Supabase Free pauses a project after about a week with no activity (open the dashboard to resume it) and Vercel Hobby is for non-commercial use, so move both to paid plans for long-term or multi-school use. Pupils are children: keep access limited to staff, and follow the Nigeria Data Protection Act 2023.
- **Backups:** each term, use Supabase > Table Editor > Export to CSV for `pupils`, `scores` and `remarks`.
- **Not included yet:** admin editing of scores directly (the admin unlocks and the teacher edits) and automatic emailing with an attached PDF (the email button opens your mail app with the PIN message). Pupils and scores can be loaded in bulk through the Excel import.
- **Troubleshooting:** blank page or "Failed to fetch" means `config.js` still has the placeholder values. "Create login" failing means the three Vercel environment variables are missing (redeploy after adding them).


## Update 3: classes, Nursery progress report, ages, decimals
Run `supabase/update-3-classes-progress-dob.sql` once (after update-2), then deploy the new `index.html`.
- **Classes** become: Playgroup, Playgroup II, Pre-Nursery, Pre-Nursery II, Nursery 1A, 1B, 2A, 2B, Primary 1 Alpha/Beta, 2 Amazon/Benue, 3 Orange/Anambra, 4 Limpopo/Niger, 5 Taraba/Senegal, 6 Rima/Imo. The script renames the old A/B classes in place (pupils and teachers stay attached). At the end it lists all classes: if you renamed any earlier by hand, an extra row may remain. Delete an unused leftover with `delete from classes where level='Primary 3' and arm='Gold';` (only if it has no pupils).
- **Nursery section** (Playgroup, Pre-Nursery, Nursery) uses a **Progress Report**: teachers type a remark for each subject (no scores). Step 4 becomes "Subject remarks" with a British English check under each box (spelling such as colour/behaviour/maths, common typing mistakes, capital letters, full stops, a/an and basic verb agreement). It runs in the browser, is free and sends nothing anywhere. It is a helper, not a full proofreader. Step 5 collects general remarks, appearance, weight, height and attendance. The Primary section keeps the scored Terminal Report.
- **Nursery subjects** now include those on the paper form (Number Work, Colour & Shapes, Hand Control, Phonics/Reading, English, Art/Craft, Physical Education, CRS/IRK, Story Telling, Nature Studies, Singing, Response to Homework) alongside the earlier list. Switch any off, or rename one, in the admin **Subjects** tab (the form printed "Signing"; it was added as "Singing").
- **Date of birth:** teachers enter it for every pupil (step 2, or paste `Name, dd/mm/yyyy` lines). It is required before a report can be issued.
- **Age:** each report shows the pupil's age and the class average age. For a PIN report the age is fixed at the date the PIN was issued; for admin preview and print it is the day you generate it.
- **Decimals:** CA, Exam, totals and averages accept up to 3 decimal places.
- **Terms tab** now also has "Term ends", shown as "Report for term ending" on the progress report.
- The login page is one page with two clearly separate sections: **Staff and Admin login** and **Parents** (admission number and PIN). Everyone uses the same website address.
- Admission numbers generated by the portal never clash with numbers brought in from Excel.

## Update 4: check summary, analytics, Excel (no extra SQL needed)
- **Teacher step 6 "Check & submit":** a summary table of everything entered (date of birth, every subject's total with CA + Exam underneath, average, grade, position, remark, class average per subject; for Nursery a tick matrix and a readable list of the remarks). Missing items show in red. Submitting is only allowed when nothing is missing.
- **Admin > Analytics** (Primary classes, which have scores):
  - *Class performance:* class average over terms, subject averages now against an earlier term, every pupil ranked with change since the earlier term and difference from the class average, pass rate (average 40 or more) and grade spread.
  - *Individual pupil:* pupil average against the class average over time, each subject now against the earlier term and against the class average (table and bars), strongest and weakest subject.
  - "Compare with" defaults to the previous term that has scores; pick any other term if you prefer. Past terms use the pupils who are in the class now, so if pupils are moved between classes, earlier figures reflect today's class list.
- **Admin > Excel data:**
  - *Export* downloads one workbook (Pupils with date of birth, Scores, Enrolment, ProgressRemarks, Remarks, Subjects, Sessions, RemarkBank, Classes). Signatures, PINs and passwords are never included. Do it at the end of every term as a backup.
  - *Import* reads a workbook in the same layout (or the blank template). It shows what it found and any problem rows (sheet and row number) before you confirm. Rows are added or updated, **nothing is deleted**, bad rows are skipped, missing terms are created, and classes must already exist. Use it to bring back earlier terms or last year's results. Pupils can be on the Pupils sheet or already in the portal. Dates use yyyy-mm-dd (real Excel dates also work). Blank cells in a row you import replace the saved value with blank.
  - The Excel library is loaded from cdnjs only when you press Export or choose a file, so other screens stay light. It needs an internet connection.

## Clearing test data (start afresh)
- **In the portal (admin):** Reports & PINs > choose the class > **Delete all pupils in this class…** (type DELETE to confirm), or **Delete pupil permanently** on one pupil. This removes the pupils with their scores, subject ticks, remarks, PINs, the class's submission status and the teacher's signature for that class. Classes, subjects, terms, teacher logins and class assignments stay. Export to Excel first if you may want the data back.
- **Teacher "Remove" button** only hides a pupil from the class list (the records stay, so nothing is lost by accident). Permanent deletion is for the admin only.
- **With SQL (Supabase SQL Editor):**
```
delete from submissions        where class_id in (select id from classes where level = 'Primary 6');
delete from teacher_signatures where class_id in (select id from classes where level = 'Primary 6');
delete from pupils             where class_id in (select id from classes where level = 'Primary 6');
```
Deleting pupils automatically deletes their scores, subject ticks, remarks, progress remarks and PINs.
- **Admin class results sheet:** the Reports & PINs tab now shows a full results table for the chosen class and term (the same summary the teacher sees). "View report" and "Generate PIN" stay greyed until every compulsory item is present; the line "Still needed" under each pupil says which.
- **Admin Reports & PINs tab opens on a class that has been submitted** (or has pupils), and a **Class submissions** table at the top lists every class that has a teacher or pupils, with the teacher, number of pupils and status. Press **Open** on a class to see it, and **Refresh data** to pick up what teachers entered after you logged in. The class dropdown also shows each class's teacher and a "✓ submitted" tick.

## Printing report cards (A4, one page each)
- Every terminal report and progress report is laid out as one A4 page with wide margins (20 mm left and right, 18 mm top and bottom). Up to 14 subjects fit; if a report has unusually long remarks, the page shrinks very slightly so it still stays on one sheet.
- To print: open the report, press **Print or save as PDF**, choose paper size **A4**, margins **Default**, and turn **off** "Headers and footers" (and leave scale at 100%). "Print all ready reports" prints one pupil per page.
- CA, Exam, Total, Class avg, grand total and the averages always show three decimal places (for example 35.000).
- On a phone or tablet the report shows as a scaled-down A4 sheet; pinch to zoom, or use Print > Save as PDF.

## Update 5: tied positions (run `supabase/update-4-tie-positions.sql` once)
Pupils with the same average share a position and the next position is skipped, British style: two pupils tied 1st are followed by 3rd; three tied 4th are followed by 7th. Ties are decided on the average shown to three decimal places, so two pupils who both show 80.000 always share a position. This applies to report cards, the teacher's check summary and Analytics.

## Update 6: super admin and admin accounts (run `supabase/update-5-accounts.sql` once, BEFORE pushing the new files)
- **Super admin** (your existing admin account): sees and does everything, creates and deletes **Admin and Teacher** accounts, resets any other account's password.
- **Admin** (for example the proprietress): sees everything and does everything the super admin does in the portal (reports, PINs, signatures, subjects, terms, remark bank, analytics, Excel, deleting pupils). In **Accounts & classes** she can create, reset and delete **Teacher** accounts only.
- **Protected:** nobody can delete the super admin, and nobody can delete their own account. An ordinary admin cannot create, reset or delete other admins. The super admin password is changed only by the super admin (Change password).
- **How to add the proprietress:** log in as super admin > Accounts & classes > Create an account > choose **Admin** > give her name, email and a starting password.
- The update marks your earliest existing admin as the super admin and checks it at the end of the script (the `is_super` column should show `t` for you only). To make a different account the super admin, in the SQL Editor: `update profiles set is_super = false; update profiles set is_super = true where email = 'THE-EMAIL';`
- Accounts can no longer be edited straight from the browser, only through the portal's server function, so a copied admin login cannot promote itself.
- Only two account types exist today (Admin and Teacher). If the school needs other staff types (for example a bursar who sees fees only), tell me what each should see and do.

## Update 7: school roster, promotion and repetition (run `supabase/update-6-roster.sql` once)
**What changed:** every pupil now belongs to a class *per term* (the roster). Old report cards keep the class and class averages of that term even after a pupil is promoted. Existing pupils are placed in their current class for every existing term, and existing terms stay unlocked so your testing continues.

**Admission numbers** follow the year of the term in which the pupil is admitted: 2026/2027 gives CNP/26/0001, CNP/26/0002…, and 2027/2028 starts again at CNP/27/0001. Numbers are made by the portal when pupils are added (teacher, admin) and never repeat. Existing numbers are kept.

**Launch (1st Term 2026/2027):** in the Terms tab make sure “Roster open to teachers” is ticked. Each teacher goes to step 2 Pupils and adds the class (name, date of birth). You can also add pupils yourself: School roster tab > Add new pupils (admin-confirmed admissions). Those wait in their class for the teacher to admit them.

**Pupils stay in their class for all three terms of a session. Promotion and repetition happen only from one session to the next.**

*Within a session (2nd and 3rd Term):*
1. Terms tab: add the new term. The portal asks "Carry all pupils from the previous term into this one?" Answer OK and everyone stays in the same class, already admitted (no teacher action). You can also do it later from School roster > choose the term > **Carry … pupil(s) forward into the same classes**.
2. Only if a teacher needs to add a late arrival, unlock that term's roster (it is locked by default for new terms).

*Into a new session (promotion and repetition):*
1. Terms tab: add **1st Term** of the new session (for example 2027/2028).
2. School roster tab: *Term to prepare* = that 1st Term, *Take pupils from* = the **3rd Term** of the session just ended (the portal warns if you pick another term).
3. For each pupil, decide **Promote to a named class** (for example Primary 1 Alpha to Amazon or Benue), **Repeat** the class, or **Leaves school** (Primary 6 leavers, withdrawals). A whole class can be set at once. Under each name you see the session average (the average of that session's term averages), the last term's average, a red "below 40" flag, and the proprietress's remark from the last term (where she can record her recommendation), to support the decision. Press **Place these pupils**.
4. Add any new admissions in the same tab, then **unlock the roster** for the new term.
5. Class teachers open step 2 Pupils and see "Waiting to join [class]": promoted pupils, repeaters and pupils you added. They press **Admit** (or **Admit all**) for those present, and can add other new pupils. Only admitted pupils appear in scores, summaries and reports.
6. Lock the roster again when admissions are done.

**Rules:** a teacher can only admit or remove pupils while the term's roster is unlocked, only for their own class, and cannot change a pupil's class or admission number. “Remove” takes a pupil out of that term's class list only (the admin can still see them under “Removed” counts). The class teacher assignments (Accounts & classes tab) are not per term, so reassign a class teacher there when a teacher changes class.

**Excel:** export now has a `Roster` sheet (pupil, term, class, status) and the Pupils sheet no longer has a class. Import reads the same layout.

**Analytics** uses each term's real class list for the class you choose. A promoted pupil's earlier terms are still compared; the earlier class average is taken over today's classmates.

## Remarks follow the Grand total grade
Ready-made remarks offered to the class teacher and the proprietress are limited to the pupil's **Grand total grade**, the grade in the last row of the report card's Grade column. A B+ pupil sees only B+ remarks; a pupil with no scores yet is asked to enter the scores first. Nursery progress reports use the “Any grade” remarks. In the Remark bank, give each grade several remarks so there is always a choice. The grade is worked out from the average shown to three decimals, so what the teacher sees matches the report.
