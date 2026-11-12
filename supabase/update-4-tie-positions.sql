-- UPDATE 4 for the Comence portal. Run ONCE in Supabase SQL Editor, after update-3.
-- Positions: pupils with the same average (to 3 decimal places) share a position and the next
-- position is skipped, British style: 1st, 1st, 3rd ... and 4th, 4th, 4th, 7th.

create or replace function build_report(p uuid, s uuid, as_of date default current_date) returns jsonb
language sql stable security definer set search_path = public as $$
with me as (select class_id from pupils where id = p),
agg as (
  select sc.pupil_id, sum(sc.total) gt, avg(sc.total) av
  from scores sc join pupils pu on pu.id = sc.pupil_id
  where sc.session_id = s and sc.total is not null and pu.active and pu.class_id = (select class_id from me)
  group by sc.pupil_id),
ranked as (select pupil_id, gt, av, rank() over (order by round(av, 3) desc) pos from agg),
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
