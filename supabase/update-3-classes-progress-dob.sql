-- UPDATE 3 for the Comence portal. Run ONCE in Supabase SQL Editor, AFTER schema.sql and update-2.
-- Adds: real class names, Nursery progress reports, date of birth and ages, 3-decimal scores.

-- 1. Classes: real names. Single-class levels have an empty arm.
alter table classes drop constraint if exists classes_level_check;
alter table classes drop constraint if exists classes_arm_check;

update classes set level='Playgroup',      arm=''      where level='Playgroup'   and arm='A';
update classes set level='Playgroup II',   arm=''      where level='Playgroup'   and arm='B';
update classes set level='Pre-Nursery',    arm=''      where level='Pre-Nursery' and arm='A';
update classes set level='Pre-Nursery II', arm=''      where level='Pre-Nursery' and arm='B';
update classes set arm='Alpha'    where level='Primary 1' and arm='A';
update classes set arm='Beta'     where level='Primary 1' and arm='B';
update classes set arm='Amazon'   where level='Primary 2' and arm='A';
update classes set arm='Benue'    where level='Primary 2' and arm='B';
update classes set arm='Orange'   where level='Primary 3' and arm='A';
update classes set arm='Anambra'  where level='Primary 3' and arm='B';
update classes set arm='Limpopo'  where level='Primary 4' and arm='A';
update classes set arm='Niger'    where level='Primary 4' and arm='B';
update classes set arm='Taraba'   where level='Primary 5' and arm='A';
update classes set arm='Senegal'  where level='Primary 5' and arm='B';
update classes set arm='Rima'     where level='Primary 6' and arm='A';
update classes set arm='Imo'      where level='Primary 6' and arm='B';

insert into classes (level, arm) values
 ('Playgroup',''),('Playgroup II',''),('Pre-Nursery',''),('Pre-Nursery II',''),
 ('Nursery 1','A'),('Nursery 1','B'),('Nursery 2','A'),('Nursery 2','B'),
 ('Primary 1','Alpha'),('Primary 1','Beta'),('Primary 2','Amazon'),('Primary 2','Benue'),
 ('Primary 3','Orange'),('Primary 3','Anambra'),('Primary 4','Limpopo'),('Primary 4','Niger'),
 ('Primary 5','Taraba'),('Primary 5','Senegal'),('Primary 6','Rima'),('Primary 6','Imo')
on conflict (level, arm) do nothing;

create or replace function section_of(lvl text) returns text
language sql immutable as $$ select case when lvl like 'Primary%' then 'Primary' else 'Nursery' end $$;

create or replace function class_label(lvl text, a text) returns text
language sql immutable as
$$ select lvl || case when coalesce(a,'') = '' then '' when length(a) = 1 then a else ' ' || a end $$;

-- 2. Nursery subjects from the progress report form (existing ones are kept)
insert into subjects (section, name, sort) values
 ('Nursery','Number Work',8),('Nursery','Colour & Shapes',9),('Nursery','Hand Control',10),('Nursery','Phonics/Reading',11),
 ('Nursery','English',12),('Nursery','Art/Craft',13),('Nursery','Physical Education',14),('Nursery','CRS/IRK',15),
 ('Nursery','Story Telling',16),('Nursery','Nature Studies',17),('Nursery','Singing',18),('Nursery','Response to Homework',19)
on conflict (section, name) do nothing;

-- 3. Date of birth, extra progress-report fields, term end date
alter table pupils   add column if not exists dob date;
alter table remarks  add column if not exists weight text, add column if not exists height text, add column if not exists appearance text;
alter table sessions add column if not exists end_date date;

-- 4. Scores allow up to 3 decimal places
alter table scores drop column total;
alter table scores alter column ca   type numeric(6,3);
alter table scores alter column exam type numeric(6,3);
alter table scores add column total numeric(7,3) generated always as (ca + exam) stored;

-- 5. Nursery progress remarks (typed by teachers, per subject)
create table if not exists progress_remarks (
  pupil_id   uuid not null references pupils(id) on delete cascade,
  subject_id uuid not null references subjects(id),
  session_id uuid not null references sessions(id),
  remark     text not null default '',
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (pupil_id, subject_id, session_id)
);
alter table progress_remarks enable row level security;
create policy admin_all on progress_remarks for all using (is_admin()) with check (is_admin());
create policy t_pr_sel on progress_remarks for select using (my_pupil(pupil_id));
create policy t_pr_ins on progress_remarks for insert with check (my_pupil(pupil_id) and is_open(pupil_id, session_id)
  and exists (select 1 from pupil_subjects x where x.pupil_id = progress_remarks.pupil_id and x.subject_id = progress_remarks.subject_id and x.session_id = progress_remarks.session_id));
create policy t_pr_upd on progress_remarks for update using (my_pupil(pupil_id) and is_open(pupil_id, session_id))
  with check (my_pupil(pupil_id) and is_open(pupil_id, session_id));
create policy t_pr_del on progress_remarks for delete using (my_pupil(pupil_id) and is_open(pupil_id, session_id));
revoke all on progress_remarks from anon;

-- generic (any-grade) preset remarks that suit the Nursery progress report
insert into remark_bank (kind, band, text, sort) values
 ('teacher',null,'Is making steady progress and enjoys learning.',20),
 ('teacher',null,'Has settled well and shows good social skills.',21),
 ('teacher',null,'Needs more practice with writing at home.',22),
 ('proprietress',null,'A pleasing report. Keep up the good work.',20),
 ('proprietress',null,'Steady progress. Parents are encouraged to practise at home.',21);

-- 6. Age text and the report builder (terminal report for Primary, progress report for Nursery)
create or replace function age_text(m int) returns text
language sql immutable as $$
  select case when m is null then null else
    (m / 12) || case when m / 12 = 1 then ' year ' else ' years ' end ||
    (m % 12) || case when m % 12 = 1 then ' month' else ' months' end end $$;

create or replace function build_report(p uuid, s uuid, as_of date default current_date) returns jsonb
language sql stable security definer set search_path = public as $$
with me as (select class_id from pupils where id = p),
agg as (
  select sc.pupil_id, sum(sc.total) gt, avg(sc.total) av
  from scores sc join pupils pu on pu.id = sc.pupil_id
  where sc.session_id = s and sc.total is not null and pu.active and pu.class_id = (select class_id from me)
  group by sc.pupil_id),
ranked as (select pupil_id, gt, av, rank() over (order by av desc) pos from agg),
cavg as (select round(avg(av), 3) v from agg),
ages as (
  select q.id, (extract(year from age(as_of, q.dob)) * 12 + extract(month from age(as_of, q.dob)))::int m
  from pupils q where q.class_id = (select class_id from me) and q.active and q.dob is not null)
select jsonb_build_object(
  'name', pu.full_name, 'admission_no', pu.admission_no, 'dob', pu.dob,
  'age', age_text((select m from ages where id = p)),
  'class_avg_age', age_text((select round(avg(m))::int from ages)),
  'class', class_label(c.level, c.arm), 'section', section_of(c.level),
  'session', se.year, 'term', se.term, 'resume_date', se.resume_date, 'term_end_date', se.end_date,
  'rows', coalesce((select jsonb_agg(jsonb_build_object('subject', sub.name, 'ca', x.ca, 'exam', x.exam, 'total', x.total,
                      'grade', grade_for(x.total),
                      'class_avg', (select round(avg(x2.total), 3) from scores x2 join pupils p2 on p2.id = x2.pupil_id
                                    where x2.subject_id = x.subject_id and x2.session_id = s and x2.total is not null
                                      and p2.active and p2.class_id = pu.class_id)) order by sub.sort)
                    from scores x join subjects sub on sub.id = x.subject_id
                    where x.pupil_id = p and x.session_id = s and x.total is not null), '[]'::jsonb),
  'progress', coalesce((select jsonb_agg(jsonb_build_object('subject', sub.name, 'remark', pr.remark) order by sub.sort)
                    from progress_remarks pr join subjects sub on sub.id = pr.subject_id
                    where pr.pupil_id = p and pr.session_id = s and btrim(pr.remark) <> ''), '[]'::jsonb),
  'grand_total', r.gt, 'average', round(r.av, 3), 'average_grade', grade_for(r.av), 'position', r.pos,
  'class_average', (select v from cavg),
  'class_size', (select count(*) from pupils q where q.class_id = pu.class_id and q.active),
  'teacher_remark', rm.teacher_remark, 'head_remark', rm.head_remark, 'fees_outstanding', rm.fees_outstanding,
  'days_present', rm.days_present, 'days_open', rm.days_open, 'behaviour', rm.behaviour,
  'weight', rm.weight, 'height', rm.height, 'appearance', rm.appearance,
  'teacher_sig', (select jsonb_build_object('typed', ts.typed_name, 'image', ts.image) from teacher_signatures ts
                  where ts.class_id = pu.class_id and ts.session_id = s),
  'proprietress_signature', (select value from settings where key = 'proprietress_signature'))
from pupils pu
join classes c  on c.id = pu.class_id
join sessions se on se.id = s
left join ranked r on r.pupil_id = pu.id
left join remarks rm on rm.pupil_id = pu.id and rm.session_id = s
where pu.id = p
$$;
revoke all on function build_report(uuid, uuid, date) from public, anon, authenticated;

create or replace function admin_report(p uuid, s uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Admin only'; end if;
  return build_report(p, s, current_date);
end $$;

-- parent_report: age is fixed at the date the PIN was issued
create or replace function parent_report(adm text, pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_p uuid; rc report_cards%rowtype; bad jsonb := jsonb_build_object('ok', false, 'error', 'Admission number or PIN is not correct.');
begin
  select id into v_p from pupils where admission_no = upper(trim(adm)) and active;
  if v_p is null then return bad; end if;
  select * into rc from report_cards where pupil_id = v_p and pin_hash is not null order by issued_at desc limit 1;
  if not found then return bad; end if;
  if rc.failed_attempts >= 5 then return jsonb_build_object('ok', false, 'error', 'Too many wrong tries. Please contact the school for a new PIN.'); end if;
  if now() > rc.expires_at then return jsonb_build_object('ok', false, 'error', 'This PIN has expired. Please contact the school for a new one.'); end if;
  if rc.pin_hash <> crypt(upper(trim(pin)), rc.pin_hash) then
    update report_cards set failed_attempts = failed_attempts + 1 where pupil_id = rc.pupil_id and session_id = rc.session_id;
    return bad;
  end if;
  update report_cards set failed_attempts = 0, last_accessed_at = now() where pupil_id = rc.pupil_id and session_id = rc.session_id;
  return jsonb_build_object('ok', true, 'expires_at', rc.expires_at, 'report', build_report(v_p, rc.session_id, rc.issued_at::date));
end $$;

drop function if exists build_report(uuid, uuid);

-- 7. Admission numbers never clash with numbers brought in from Excel
create or replace function next_admission_no() returns text
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  loop
    v := 'CNP/' || to_char(now(), 'YY') || '/' || lpad(nextval('admission_seq')::text, 4, '0');
    exit when not exists (select 1 from pupils where admission_no = v);
  end loop;
  return v;
end $$;
alter table pupils alter column admission_no set default next_admission_no();

-- Check your classes (remove or rename any leftovers from earlier renames):
select level, arm, teacher_id from classes order by level, arm;
