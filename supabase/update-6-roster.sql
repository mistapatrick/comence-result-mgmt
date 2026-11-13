-- UPDATE 6 for the Comence portal. Run ONCE in Supabase SQL Editor, after update-5.
-- School roster: every pupil belongs to a class PER TERM. Supports promotion, repetition,
-- teachers admitting pupils, admin-added pupils, and admission numbers by year (CNP/26/0001).

-- 1. Terms can unlock the roster for teachers
alter table sessions add column if not exists roster_open boolean not null default false;

-- 2. The roster: which class each pupil is in, for each term
create table if not exists roster (
  pupil_id   uuid not null references pupils(id) on delete cascade,
  session_id uuid not null references sessions(id),
  class_id   uuid not null references classes(id),
  status     text not null default 'admitted' check (status in ('pending','admitted','removed')),
  source     text not null default 'teacher' check (source in ('teacher','admin','promoted','repeated','carried','legacy','import')),
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key (pupil_id, session_id)
);
alter table roster enable row level security;
create policy admin_all on roster for all using (is_admin()) with check (is_admin());
create policy t_roster_sel on roster for select using (class_id in (select id from classes where teacher_id = auth.uid()));
create policy t_roster_upd on roster for update using (class_id in (select id from classes where teacher_id = auth.uid()))
                                                with check (class_id in (select id from classes where teacher_id = auth.uid()));
revoke all on roster from anon;

-- teachers may only admit (pending > admitted) or remove / restore, and only while the roster is unlocked
create or replace function roster_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    if not exists (select 1 from sessions where id = old.session_id and roster_open) then
      raise exception 'The school roster is locked for this term. Ask the admin to unlock it.'; end if;
    if new.status not in ('admitted','removed') then raise exception 'Not allowed.'; end if;
    new.pupil_id := old.pupil_id; new.session_id := old.session_id; new.class_id := old.class_id; new.source := old.source;
  end if;
  return new;
end $$;
drop trigger if exists roster_guard_t on roster;
create trigger roster_guard_t before update on roster for each row execute function roster_guard();

-- 3. Bring existing pupils across: each one joins their current class in every existing term
alter table pupils alter column class_id drop not null;
insert into roster (pupil_id, session_id, class_id, status, source)
select p.id, s.id, p.class_id, case when p.active then 'admitted' else 'removed' end, 'legacy'
from pupils p cross join sessions s
where p.class_id is not null
on conflict do nothing;
update sessions set roster_open = true;     -- existing terms stay open so current testing continues

-- 4. Teachers' access now follows the roster, per term
create or replace function my_pupil(p uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from roster r join classes c on c.id = r.class_id where r.pupil_id = p and c.teacher_id = auth.uid()) $$;

create or replace function my_pupil_s(p uuid, s uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from roster r join classes c on c.id = r.class_id
                  where r.pupil_id = p and r.session_id = s and r.status = 'admitted' and c.teacher_id = auth.uid()) $$;

create or replace function is_open(p uuid, s uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select not exists (select 1 from roster r join submissions sb on sb.class_id = r.class_id and sb.session_id = r.session_id
                      where r.pupil_id = p and r.session_id = s and r.status = 'admitted' and sb.status <> 'draft') $$;

drop policy if exists t_pupils_ins on pupils;
drop policy if exists t_pupils_sel on pupils;
drop policy if exists t_pupils_upd on pupils;
create policy t_pupils_sel on pupils for select using (my_pupil(id));
create policy t_pupils_upd on pupils for update using (my_pupil(id)) with check (my_pupil(id));

create or replace function pupils_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then new.admission_no := old.admission_no; new.class_id := old.class_id; new.active := old.active; end if;
  return new;
end $$;
drop trigger if exists pupils_guard_t on pupils;
create trigger pupils_guard_t before update on pupils for each row execute function pupils_guard();

drop policy if exists t_ps_sel on pupil_subjects; drop policy if exists t_ps_ins on pupil_subjects; drop policy if exists t_ps_del on pupil_subjects;
create policy t_ps_sel on pupil_subjects for select using (my_pupil_s(pupil_id, session_id));
create policy t_ps_ins on pupil_subjects for insert with check (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));
create policy t_ps_del on pupil_subjects for delete using (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));

drop policy if exists t_sc_sel on scores; drop policy if exists t_sc_ins on scores; drop policy if exists t_sc_upd on scores; drop policy if exists t_sc_del on scores;
create policy t_sc_sel on scores for select using (my_pupil_s(pupil_id, session_id));
create policy t_sc_ins on scores for insert with check (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id)
  and exists (select 1 from pupil_subjects x where x.pupil_id = scores.pupil_id and x.subject_id = scores.subject_id and x.session_id = scores.session_id));
create policy t_sc_upd on scores for update using (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id))
  with check (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));
create policy t_sc_del on scores for delete using (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));

drop policy if exists t_rm_sel on remarks; drop policy if exists t_rm_ins on remarks; drop policy if exists t_rm_upd on remarks;
create policy t_rm_sel on remarks for select using (my_pupil_s(pupil_id, session_id));
create policy t_rm_ins on remarks for insert with check (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));
create policy t_rm_upd on remarks for update using (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id))
  with check (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));

drop policy if exists t_pr_sel on progress_remarks; drop policy if exists t_pr_ins on progress_remarks; drop policy if exists t_pr_upd on progress_remarks; drop policy if exists t_pr_del on progress_remarks;
create policy t_pr_sel on progress_remarks for select using (my_pupil_s(pupil_id, session_id));
create policy t_pr_ins on progress_remarks for insert with check (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id)
  and exists (select 1 from pupil_subjects x where x.pupil_id = progress_remarks.pupil_id and x.subject_id = progress_remarks.subject_id and x.session_id = progress_remarks.session_id));
create policy t_pr_upd on progress_remarks for update using (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id))
  with check (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));
create policy t_pr_del on progress_remarks for delete using (my_pupil_s(pupil_id, session_id) and is_open(pupil_id, session_id));

-- 5. Adding new pupils. Admission numbers follow the year of the term: 2026/2027 -> CNP/26/0001, 2027/2028 -> CNP/27/0001
create or replace function add_pupils(c uuid, s uuid, names text[], dobs text[]) returns int
language plpgsql security definer set search_path = public as $$
declare yy text; nxt int; adm text; pid uuid; st text; src text; cnt int := 0; i int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select substr(year, 3, 2) into yy from sessions where id = s;
  if yy is null then raise exception 'Unknown term'; end if;
  if is_admin() then st := 'pending'; src := 'admin';          -- admin-confirmed pupils wait for the class teacher to admit them
  else
    if not exists (select 1 from classes where id = c and teacher_id = auth.uid()) then raise exception 'That is not your class.'; end if;
    if not exists (select 1 from sessions where id = s and roster_open) then raise exception 'The school roster is locked for this term. Ask the admin to unlock it.'; end if;
    st := 'admitted'; src := 'teacher';
  end if;
  perform pg_advisory_xact_lock(hashtext('cnp-admission-' || yy));
  select coalesce(max(substring(admission_no from '^CNP/' || yy || '/([0-9]+)$')::int), 0) into nxt
  from pupils where admission_no like 'CNP/' || yy || '/%';
  for i in 1 .. coalesce(array_length(names, 1), 0) loop
    if btrim(coalesce(names[i], '')) = '' then continue; end if;
    nxt := nxt + 1; adm := 'CNP/' || yy || '/' || lpad(nxt::text, 4, '0');
    insert into pupils (admission_no, full_name, dob) values (adm, btrim(names[i]), nullif(btrim(coalesce(dobs[i], '')), '')::date) returning id into pid;
    insert into roster (pupil_id, session_id, class_id, status, source, created_by) values (pid, s, c, st, src, auth.uid());
    cnt := cnt + 1;
  end loop;
  return cnt;
end $$;
revoke all on function add_pupils(uuid, uuid, text[], text[]) from public, anon;
grant execute on function add_pupils(uuid, uuid, text[], text[]) to authenticated;

-- 6. Reports follow the roster: class, class average, class size and class average age come from that term's classmates
create or replace function build_report(p uuid, s uuid, as_of date default current_date) returns jsonb
language sql stable security definer set search_path = public as $$
with me as (select class_id from roster where pupil_id = p and session_id = s and status = 'admitted'),
mates as (select r.pupil_id from roster r where r.session_id = s and r.status = 'admitted' and r.class_id = (select class_id from me)),
agg as (
  select sc.pupil_id, sum(sc.total) gt, avg(sc.total) av
  from scores sc
  where sc.session_id = s and sc.total is not null and sc.pupil_id in (select pupil_id from mates)
  group by sc.pupil_id),
ranked as (select pupil_id, gt, av, rank() over (order by round(av, 3) desc) pos from agg),
cavg as (select round(avg(av), 3) v from agg),
ages as (
  select q.id, (extract(year from age(as_of, q.dob)) * 12 + extract(month from age(as_of, q.dob)))::int m
  from pupils q where q.id in (select pupil_id from mates) and q.dob is not null)
select jsonb_build_object(
  'name', pu.full_name, 'admission_no', pu.admission_no, 'dob', pu.dob,
  'age', age_text((select m from ages where id = p)),
  'class_avg_age', age_text((select round(avg(m))::int from ages)),
  'class', class_label(c.level, c.arm), 'section', section_of(c.level),
  'session', se.year, 'term', se.term, 'resume_date', se.resume_date, 'term_end_date', se.end_date,
  'rows', coalesce((select jsonb_agg(jsonb_build_object('subject', sub.name, 'ca', x.ca, 'exam', x.exam, 'total', x.total,
                      'grade', grade_for(x.total),
                      'class_avg', (select round(avg(x2.total), 3) from scores x2
                                    where x2.subject_id = x.subject_id and x2.session_id = s and x2.total is not null
                                      and x2.pupil_id in (select pupil_id from mates))) order by sub.sort)
                    from scores x join subjects sub on sub.id = x.subject_id
                    where x.pupil_id = p and x.session_id = s and x.total is not null), '[]'::jsonb),
  'progress', coalesce((select jsonb_agg(jsonb_build_object('subject', sub.name, 'remark', pr.remark) order by sub.sort)
                    from progress_remarks pr join subjects sub on sub.id = pr.subject_id
                    where pr.pupil_id = p and pr.session_id = s and btrim(pr.remark) <> ''), '[]'::jsonb),
  'grand_total', r.gt, 'average', round(r.av, 3), 'average_grade', grade_for(round(r.av, 3)), 'position', r.pos,
  'class_average', (select v from cavg),
  'class_size', (select count(*) from mates),
  'teacher_remark', rm.teacher_remark, 'head_remark', rm.head_remark, 'fees_outstanding', rm.fees_outstanding,
  'days_present', rm.days_present, 'days_open', rm.days_open, 'behaviour', rm.behaviour,
  'weight', rm.weight, 'height', rm.height, 'appearance', rm.appearance,
  'teacher_sig', (select jsonb_build_object('typed', ts.typed_name, 'image', ts.image) from teacher_signatures ts
                  where ts.class_id = c.id and ts.session_id = s),
  'proprietress_signature', (select value from settings where key = 'proprietress_signature'))
from pupils pu
join me on true
join classes c on c.id = me.class_id
join sessions se on se.id = s
left join ranked r on r.pupil_id = pu.id
left join remarks rm on rm.pupil_id = pu.id and rm.session_id = s
where pu.id = p
$$;

select s.year, s.term, s.roster_open, count(r.*) filter (where r.status = 'admitted') as admitted_pupils
from sessions s left join roster r on r.session_id = s.id group by s.year, s.term, s.roster_open order by 1, 2;
