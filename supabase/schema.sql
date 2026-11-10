-- Comence Nursery & Primary School: result management (Supabase / Postgres)
-- Run this whole file once: Supabase > SQL Editor > New query > paste > Run.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ===================== Roles =====================
create type app_role as enum ('admin', 'teacher');

create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  full_name  text not null,
  role       app_role not null default 'teacher',
  created_at timestamptz not null default now()
);

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from profiles where id = auth.uid() and role = 'admin') $$;

-- every new login automatically gets a teacher profile
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', new.email));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ===================== Reference data =====================
create table sessions (
  id          uuid primary key default gen_random_uuid(),
  year        text not null,                                   -- 2026/2027
  term        text not null check (term in ('1st Term','2nd Term','3rd Term')),
  resume_date date,                                            -- next term begins
  unique (year, term)
);

create table classes (
  id         uuid primary key default gen_random_uuid(),
  level      text not null check (level in ('Playgroup','Pre-Nursery','Nursery 1','Primary 1','Primary 2','Primary 3','Primary 4','Primary 5','Primary 6')),
  arm        text not null check (arm in ('A','B')),
  teacher_id uuid references profiles(id) on delete set null,
  unique (level, arm)
);

create or replace function section_of(lvl text) returns text
language sql immutable as
$$ select case when lvl in ('Playgroup','Pre-Nursery','Nursery 1') then 'Nursery' else 'Primary' end $$;

create table subjects (
  id      uuid primary key default gen_random_uuid(),
  section text not null check (section in ('Nursery','Primary')),
  name    text not null,
  sort    int  not null default 0,
  active  boolean not null default true,
  unique (section, name)
);

create table grade_scale (
  min_total int primary key,
  grade     text not null
);
create or replace function grade_for(t numeric) returns text
language sql stable as
$$ select grade from grade_scale where min_total <= t order by min_total desc limit 1 $$;

-- ===================== Pupils, enrolment, scores =====================
create sequence admission_seq start 1;

create table pupils (
  id           uuid primary key default gen_random_uuid(),
  admission_no text not null unique
               default ('CNP/' || to_char(now(), 'YY') || '/' || lpad(nextval('admission_seq')::text, 4, '0')),
  full_name    text not null,
  class_id     uuid not null references classes(id),
  parent_email text,
  active       boolean not null default true
);

create table pupil_subjects (      -- which subjects a pupil took this term
  pupil_id   uuid not null references pupils(id) on delete cascade,
  subject_id uuid not null references subjects(id),
  session_id uuid not null references sessions(id),
  primary key (pupil_id, subject_id, session_id)
);

create table scores (
  pupil_id   uuid not null references pupils(id) on delete cascade,
  subject_id uuid not null references subjects(id),
  session_id uuid not null references sessions(id),
  ca         int check (ca   between 0 and 40),
  exam       int check (exam between 0 and 60),
  total      int generated always as (ca + exam) stored,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (pupil_id, subject_id, session_id)
);

create table submissions (         -- teacher hands the class's results to admin
  class_id     uuid not null references classes(id),
  session_id   uuid not null references sessions(id),
  status       text not null default 'draft' check (status in ('draft','submitted')),
  submitted_at timestamptz,
  primary key (class_id, session_id)
);

create table remarks (
  pupil_id         uuid not null references pupils(id) on delete cascade,
  session_id       uuid not null references sessions(id),
  teacher_remark   text,
  head_remark      text,              -- admin only
  fees_outstanding numeric(12,2),     -- admin only (0 = none)
  days_present     int,               -- optional
  days_open        int,               -- optional
  behaviour        jsonb,             -- optional
  primary key (pupil_id, session_id)
);

create or replace function remarks_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    if tg_op = 'INSERT' then new.head_remark := null; new.fees_outstanding := null;
    else new.head_remark := old.head_remark; new.fees_outstanding := old.fees_outstanding; end if;
  end if;
  return new;
end $$;
create trigger remarks_guard_t before insert or update on remarks
  for each row execute function remarks_guard();

create table report_cards (          -- parent access (PIN stored as a hash only)
  pupil_id         uuid not null references pupils(id) on delete cascade,
  session_id       uuid not null references sessions(id),
  pin_hash         text,
  expires_at       timestamptz,
  failed_attempts  int not null default 0,
  issued_at        timestamptz not null default now(),
  last_accessed_at timestamptz,
  primary key (pupil_id, session_id)
);

create table audit_log (
  id bigserial primary key, user_id uuid, action text, row_old jsonb, row_new jsonb, at timestamptz not null default now()
);
create or replace function log_scores() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log(user_id, action, row_old, row_new)
  values (auth.uid(), tg_op, case when tg_op = 'INSERT' then null else to_jsonb(old) end,
                              case when tg_op = 'DELETE' then null else to_jsonb(new) end);
  return coalesce(new, old);
end $$;
create trigger scores_audit after insert or update or delete on scores
  for each row execute function log_scores();

-- ===================== Seed data =====================
insert into grade_scale values (0,'E'),(40,'D'),(50,'C'),(60,'B'),(70,'B+'),(90,'A');

insert into classes (level, arm)
select l, a from unnest(array['Playgroup','Pre-Nursery','Nursery 1','Primary 1','Primary 2','Primary 3','Primary 4','Primary 5','Primary 6']) l,
                 unnest(array['A','B']) a;

insert into sessions (year, term) values ('2026/2027','1st Term');

insert into subjects (section, name, sort) values
 ('Nursery','English Skill/Literacy',1),('Nursery','Writing Skill/Handwriting',2),('Nursery','Mathematics Skill/Numeracy',3),
 ('Nursery','Social Habits',4),('Nursery','Health Habits',5),('Nursery','Cultural and Creative Arts',6),('Nursery','Rhymes and Poems',7),
 ('Primary','English Studies',1),('Primary','Verbal Aptitude',2),('Primary','Mathematics',3),('Primary','Quantitative Aptitude',4),
 ('Primary','Nigerian Languages',5),('Primary','Basic Science and Technology',6),('Primary','Physical and Health Education',7),
 ('Primary','National Values Curriculum (Civic Education)',8),('Primary','Social Studies',9),('Primary','Christian Religious Studies (CRS)',10),
 ('Primary','Cultural and Creative Arts',11),('Primary','Pre-Vocational Studies (Vocational Aptitude)',12),
 ('Primary','French Language',13),('Primary','Basic Digital Literacy (Computer Studies)',14);

-- ===================== Helper checks =====================
create or replace function my_pupil(p uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from pupils pu join classes c on c.id = pu.class_id where pu.id = p and c.teacher_id = auth.uid()) $$;

create or replace function is_open(p uuid, s uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select not exists (select 1 from submissions sb join pupils pu on pu.class_id = sb.class_id
                      where pu.id = p and sb.session_id = s and sb.status <> 'draft') $$;

-- ===================== Row-level security =====================
do $$ declare t text; begin
  foreach t in array array['profiles','sessions','classes','subjects','grade_scale','pupils','pupil_subjects','scores','submissions','remarks','report_cards','audit_log']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy admin_all on %I for all using (is_admin()) with check (is_admin())', t);
  end loop;
end $$;

-- signed-in users can read reference data
create policy read_sessions on sessions    for select using (auth.uid() is not null);
create policy read_classes  on classes     for select using (auth.uid() is not null);
create policy read_subjects on subjects    for select using (auth.uid() is not null);
create policy read_grades   on grade_scale for select using (auth.uid() is not null);
create policy read_self     on profiles    for select using (id = auth.uid());

-- teachers: only their own class
create policy t_pupils_sel on pupils for select using (my_pupil(id));
create policy t_pupils_ins on pupils for insert with check (class_id in (select id from classes where teacher_id = auth.uid()));
create policy t_pupils_upd on pupils for update using (my_pupil(id)) with check (class_id in (select id from classes where teacher_id = auth.uid()));

create policy t_ps_sel on pupil_subjects for select using (my_pupil(pupil_id));
create policy t_ps_ins on pupil_subjects for insert with check (my_pupil(pupil_id) and is_open(pupil_id, session_id));
create policy t_ps_del on pupil_subjects for delete using (my_pupil(pupil_id) and is_open(pupil_id, session_id));

create policy t_sc_sel on scores for select using (my_pupil(pupil_id));
create policy t_sc_ins on scores for insert with check (my_pupil(pupil_id) and is_open(pupil_id, session_id)
  and exists (select 1 from pupil_subjects x where x.pupil_id = scores.pupil_id and x.subject_id = scores.subject_id and x.session_id = scores.session_id));
create policy t_sc_upd on scores for update using (my_pupil(pupil_id) and is_open(pupil_id, session_id))
  with check (my_pupil(pupil_id) and is_open(pupil_id, session_id));
create policy t_sc_del on scores for delete using (my_pupil(pupil_id) and is_open(pupil_id, session_id));

create policy t_rm_sel on remarks for select using (my_pupil(pupil_id));
create policy t_rm_ins on remarks for insert with check (my_pupil(pupil_id) and is_open(pupil_id, session_id));
create policy t_rm_upd on remarks for update using (my_pupil(pupil_id) and is_open(pupil_id, session_id))
  with check (my_pupil(pupil_id) and is_open(pupil_id, session_id));

create policy t_sub_sel on submissions for select using (class_id in (select id from classes where teacher_id = auth.uid()));

revoke all on all tables in schema public from anon;      -- the public never touches tables directly

-- ===================== Functions the app calls =====================
create or replace function ensure_session(y text, t text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into sessions (year, term) values (trim(y), t) on conflict (year, term) do nothing;
  select id into v from sessions where year = trim(y) and term = t;
  return v;
end $$;

create or replace function claim_class(lvl text, a text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if exists (select 1 from classes where teacher_id = auth.uid()) then
    raise exception 'You already have a class. Ask the admin to change it.'; end if;
  update classes set teacher_id = auth.uid() where level = lvl and arm = a and teacher_id is null returning id into v;
  if v is null then raise exception 'That class already has a teacher. Ask the admin.'; end if;
  return v;
end $$;

create or replace function submit_class(c uuid, s uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from classes where id = c and teacher_id = auth.uid()) then raise exception 'Not your class'; end if;
  insert into submissions (class_id, session_id, status, submitted_at) values (c, s, 'submitted', now())
  on conflict (class_id, session_id) do update set status = 'submitted', submitted_at = now();
end $$;

-- Builds one pupil's report. Internal only: not callable from the app directly.
create or replace function build_report(p uuid, s uuid) returns jsonb
language sql stable security definer set search_path = public as $$
with me as (select class_id from pupils where id = p),
agg as (
  select sc.pupil_id, sum(sc.total) gt, avg(sc.total) av
  from scores sc join pupils pu on pu.id = sc.pupil_id
  where sc.session_id = s and sc.total is not null and pu.class_id = (select class_id from me)
  group by sc.pupil_id),
ranked as (select pupil_id, gt, av, rank() over (order by av desc) pos from agg)
select jsonb_build_object(
  'name', pu.full_name, 'admission_no', pu.admission_no,
  'class', c.level || ' ' || c.arm, 'section', section_of(c.level),
  'session', se.year, 'term', se.term, 'resume_date', se.resume_date,
  'rows', coalesce((select jsonb_agg(jsonb_build_object('subject', sub.name, 'ca', x.ca, 'exam', x.exam, 'total', x.total, 'grade', grade_for(x.total)) order by sub.sort)
                    from scores x join subjects sub on sub.id = x.subject_id
                    where x.pupil_id = p and x.session_id = s and x.total is not null), '[]'::jsonb),
  'grand_total', r.gt, 'average', round(r.av, 1), 'average_grade', grade_for(r.av), 'position', r.pos,
  'class_size', (select count(*) from pupils q where q.class_id = pu.class_id and q.active),
  'teacher_remark', rm.teacher_remark, 'head_remark', rm.head_remark, 'fees_outstanding', rm.fees_outstanding,
  'days_present', rm.days_present, 'days_open', rm.days_open, 'behaviour', rm.behaviour)
from pupils pu
join classes c  on c.id = pu.class_id
join sessions se on se.id = s
left join ranked r on r.pupil_id = pu.id
left join remarks rm on rm.pupil_id = pu.id and rm.session_id = s
where pu.id = p
$$;
revoke all on function build_report(uuid, uuid) from public, anon, authenticated;

create or replace function admin_report(p uuid, s uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Admin only'; end if;
  return build_report(p, s);
end $$;

create or replace function issue_pin(p uuid, s uuid, days int) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v text;
begin
  if not is_admin() then raise exception 'Admin only'; end if;
  select string_agg(substr(alpha, 1 + (get_byte(gen_random_bytes(1), 0) % 32), 1), '') into v from generate_series(1, 8);
  insert into report_cards (pupil_id, session_id, pin_hash, expires_at, failed_attempts, issued_at)
  values (p, s, crypt(v, gen_salt('bf')), now() + make_interval(days => days), 0, now())
  on conflict (pupil_id, session_id) do update
    set pin_hash = excluded.pin_hash, expires_at = excluded.expires_at, failed_attempts = 0, issued_at = now();
  return v;
end $$;

-- Parent portal: works without an account. Returns a status object, never raises
-- (so the wrong-attempt counter is kept).
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
  return jsonb_build_object('ok', true, 'expires_at', rc.expires_at, 'report', build_report(v_p, rc.session_id));
end $$;

-- "Scrapping": expired PINs are wiped so the report can no longer be opened.
create or replace function purge_expired_pins() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is not null and not is_admin() then raise exception 'Admin only'; end if;
  update report_cards set pin_hash = null where pin_hash is not null and expires_at < now();
  get diagnostics n = row_count; return n;
end $$;

revoke all on function ensure_session, claim_class, submit_class, admin_report, issue_pin, parent_report, purge_expired_pins from public, anon;
grant execute on function ensure_session, claim_class, submit_class, admin_report, issue_pin, purge_expired_pins to authenticated;
grant execute on function parent_report to anon, authenticated;

-- Optional: wipe expired PINs automatically every night (enable pg_cron in Database > Extensions first):
-- select cron.schedule('purge-pins', '0 2 * * *', $$ select purge_expired_pins() $$);
