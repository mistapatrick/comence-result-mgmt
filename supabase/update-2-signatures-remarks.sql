-- UPDATE 2 for the Comence portal. Run ONCE in Supabase SQL Editor, AFTER schema.sql.
-- Adds: free class names, signatures, editable preset remarks, class averages on report cards.

-- 1. Class names can now be anything (e.g. 'Gold'), not only A or B
alter table classes drop constraint if exists classes_arm_check;

-- 2. School settings (holds the proprietress's signature image)
create table if not exists settings (key text primary key, value text);
alter table settings enable row level security;
create policy admin_all on settings for all using (is_admin()) with check (is_admin());
revoke all on settings from anon;

-- 3. Class teacher signature (typed = cursive, or an image added by admin)
create table if not exists teacher_signatures (
  class_id   uuid not null references classes(id) on delete cascade,
  session_id uuid not null references sessions(id),
  typed_name text,
  image      text,
  signed_at  timestamptz not null default now(),
  primary key (class_id, session_id)
);
alter table teacher_signatures enable row level security;
create policy admin_all  on teacher_signatures for all using (is_admin()) with check (is_admin());
create policy t_sig_sel on teacher_signatures for select using (class_id in (select id from classes where teacher_id = auth.uid()));
create policy t_sig_ins on teacher_signatures for insert with check (class_id in (select id from classes where teacher_id = auth.uid()));
create policy t_sig_upd on teacher_signatures for update using (class_id in (select id from classes where teacher_id = auth.uid()))
                                                        with check (class_id in (select id from classes where teacher_id = auth.uid()));
revoke all on teacher_signatures from anon;

create or replace function sig_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then                     -- teachers can only type-sign; images are added by admin
    if tg_op = 'INSERT' then new.image := null; else new.image := old.image; end if;
  end if;
  new.signed_at := now();
  return new;
end $$;
drop trigger if exists sig_guard_t on teacher_signatures;
create trigger sig_guard_t before insert or update on teacher_signatures
  for each row execute function sig_guard();

-- 4. Preset remarks (school management can edit these in the portal: Remark bank tab)
create table if not exists remark_bank (
  id     uuid primary key default gen_random_uuid(),
  kind   text not null check (kind in ('teacher','proprietress')),
  band   text check (band in ('A','B+','B','C','D','E')),   -- best for this grade; empty = any
  text   text not null,
  sort   int not null default 0,
  active boolean not null default true
);
alter table remark_bank enable row level security;
create policy admin_all   on remark_bank for all using (is_admin()) with check (is_admin());
create policy read_remark on remark_bank for select using (auth.uid() is not null);
revoke all on remark_bank from anon;

insert into remark_bank (kind, band, text, sort) values
 ('teacher','A','An excellent result. Keep up the good work.',1),
 ('teacher','A','Outstanding performance. Well done.',2),
 ('teacher','B+','A very good result. Keep aiming higher.',3),
 ('teacher','B+','Very good performance. Keep it up.',4),
 ('teacher','B','A good result. With more effort, better is possible.',5),
 ('teacher','B','Good performance. Aim higher next term.',6),
 ('teacher','C','A fair result. More effort is needed.',7),
 ('teacher','C','Fair performance. Needs to work harder.',8),
 ('teacher','D','A weak result. Needs to put in much more effort.',9),
 ('teacher','D','Below expectation. Extra practice at home is advised.',10),
 ('teacher','E','A poor result. Needs serious attention and extra support.',11),
 ('teacher','E','A very weak result. Please see the class teacher.',12),
 ('proprietress','A','Excellent result. The school is proud of you.',1),
 ('proprietress','A','Outstanding work. Keep shining.',2),
 ('proprietress','B+','A very good result. Keep it up.',3),
 ('proprietress','B+','Very good performance. Aim even higher.',4),
 ('proprietress','B','A good result. You can do even better.',5),
 ('proprietress','B','Good work. Keep working hard.',6),
 ('proprietress','C','A fair result. You can do better with more effort.',7),
 ('proprietress','C','Fair performance. Please work harder.',8),
 ('proprietress','D','A weak result. Parents are advised to support extra practice.',9),
 ('proprietress','D','Below expectation. More effort is needed.',10),
 ('proprietress','E','A poor result. Parents are urged to meet the class teacher.',11),
 ('proprietress','E','A very weak result. Urgent improvement is needed.',12);

-- 5. Report now includes class average per subject, overall class average and signatures
create or replace function build_report(p uuid, s uuid) returns jsonb
language sql stable security definer set search_path = public as $$
with me as (select class_id from pupils where id = p),
agg as (
  select sc.pupil_id, sum(sc.total) gt, avg(sc.total) av
  from scores sc join pupils pu on pu.id = sc.pupil_id
  where sc.session_id = s and sc.total is not null and pu.active and pu.class_id = (select class_id from me)
  group by sc.pupil_id),
ranked as (select pupil_id, gt, av, rank() over (order by av desc) pos from agg),
cavg as (select round(avg(av), 1) v from agg)
select jsonb_build_object(
  'name', pu.full_name, 'admission_no', pu.admission_no,
  'class', c.level || ' ' || c.arm, 'section', section_of(c.level),
  'session', se.year, 'term', se.term, 'resume_date', se.resume_date,
  'rows', coalesce((select jsonb_agg(jsonb_build_object('subject', sub.name, 'ca', x.ca, 'exam', x.exam, 'total', x.total,
                      'grade', grade_for(x.total),
                      'class_avg', (select round(avg(x2.total), 1) from scores x2 join pupils p2 on p2.id = x2.pupil_id
                                    where x2.subject_id = x.subject_id and x2.session_id = s and x2.total is not null
                                      and p2.active and p2.class_id = pu.class_id)) order by sub.sort)
                    from scores x join subjects sub on sub.id = x.subject_id
                    where x.pupil_id = p and x.session_id = s and x.total is not null), '[]'::jsonb),
  'grand_total', r.gt, 'average', round(r.av, 1), 'average_grade', grade_for(r.av), 'position', r.pos,
  'class_average', (select v from cavg),
  'class_size', (select count(*) from pupils q where q.class_id = pu.class_id and q.active),
  'teacher_remark', rm.teacher_remark, 'head_remark', rm.head_remark, 'fees_outstanding', rm.fees_outstanding,
  'days_present', rm.days_present, 'days_open', rm.days_open, 'behaviour', rm.behaviour,
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
