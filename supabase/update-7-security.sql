-- UPDATE 7 (security hardening) for the Comence portal. Run ONCE in Supabase SQL Editor, after update-6.
-- 1. Staff approval gate: a stranger who registers by themselves gets NO access
-- 2. Internal functions are no longer callable by the public
-- 3. The parent PIN portal: no lock-out attacks, no way to discover which admission numbers exist
-- 4. Limits on what can be stored, and an audit trail for PIN issuing

-- ============ 1. Staff approval gate ============
alter table profiles add column if not exists active boolean not null default false;
update profiles set active = true where not active;      -- everyone who exists today is approved (run this script only once)

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from profiles where id = auth.uid() and active) $$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from profiles where id = auth.uid() and role = 'admin' and active) $$;

drop policy if exists read_sessions on sessions;  create policy read_sessions on sessions    for select using (is_staff());
drop policy if exists read_classes  on classes;   create policy read_classes  on classes     for select using (is_staff());
drop policy if exists read_subjects on subjects;  create policy read_subjects on subjects    for select using (is_staff());
drop policy if exists read_grades   on grade_scale; create policy read_grades on grade_scale for select using (is_staff());
drop policy if exists read_remark   on remark_bank; create policy read_remark on remark_bank for select using (is_staff());

-- ============ 2. Functions the app calls (now with approval checks and limits) ============
create or replace function ensure_session(y text, t text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid; a int; b int;
begin
  if not is_admin() then raise exception 'Admin only'; end if;
  if t not in ('1st Term','2nd Term','3rd Term') then raise exception 'Invalid term'; end if;
  if trim(y) !~ '^[0-9]{4}/[0-9]{4}$' then raise exception 'The session must look like 2026/2027'; end if;
  a := substr(trim(y), 1, 4)::int; b := substr(trim(y), 6, 4)::int;
  if b <> a + 1 or a < 2020 or a > 2100 then raise exception 'The two years of a session must follow each other, for example 2026/2027'; end if;
  insert into sessions (year, term) values (trim(y), t) on conflict (year, term) do nothing;
  select id into v from sessions where year = trim(y) and term = t;
  return v;
end $$;

create or replace function claim_class(lvl text, a text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not is_staff() then raise exception 'Your account has not been approved.'; end if;
  if exists (select 1 from classes where teacher_id = auth.uid()) then
    raise exception 'You already have a class. Ask the admin to change it.'; end if;
  update classes set teacher_id = auth.uid() where level = lvl and arm = a and teacher_id is null returning id into v;
  if v is null then raise exception 'That class already has a teacher. Ask the admin.'; end if;
  return v;
end $$;

create or replace function submit_class(c uuid, s uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Your account has not been approved.'; end if;
  if not exists (select 1 from classes where id = c and teacher_id = auth.uid()) then raise exception 'Not your class'; end if;
  insert into submissions (class_id, session_id, status, submitted_at) values (c, s, 'submitted', now())
  on conflict (class_id, session_id) do update set status = 'submitted', submitted_at = now();
end $$;

create or replace function add_pupils(c uuid, s uuid, names text[], dobs text[]) returns int
language plpgsql security definer set search_path = public as $$
declare yy text; nxt int; adm text; pid uuid; st text; src text; cnt int := 0; i int; d date;
begin
  if not is_staff() then raise exception 'Your account has not been approved.'; end if;
  if coalesce(array_length(names, 1), 0) > 200 then raise exception 'Add at most 200 pupils at a time.'; end if;
  select substr(year, 3, 2) into yy from sessions where id = s;
  if yy is null then raise exception 'Unknown term'; end if;
  if is_admin() then st := 'pending'; src := 'admin';
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
    if char_length(btrim(names[i])) > 120 then raise exception 'A name is too long (maximum 120 characters).'; end if;
    begin d := nullif(btrim(coalesce(dobs[i], '')), '')::date;
    exception when others then raise exception 'The date of birth for % is not understood.', btrim(names[i]); end;
    if d is not null and (d < date '2000-01-01' or d > current_date) then raise exception 'The date of birth for % is not realistic.', btrim(names[i]); end if;
    nxt := nxt + 1; adm := 'CNP/' || yy || '/' || lpad(nxt::text, 4, '0');
    insert into pupils (admission_no, full_name, dob) values (adm, btrim(names[i]), d) returning id into pid;
    insert into roster (pupil_id, session_id, class_id, status, source, created_by) values (pid, s, c, st, src, auth.uid());
    cnt := cnt + 1;
  end loop;
  return cnt;
end $$;

-- audit trail for PIN issuing
create or replace function issue_pin(p uuid, s uuid, days int) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v text;
begin
  if not is_admin() then raise exception 'Admin only'; end if;
  if days < 1 or days > 120 then raise exception 'A PIN can be valid for 1 to 120 days.'; end if;
  select string_agg(substr(alpha, 1 + (get_byte(gen_random_bytes(1), 0) % 32), 1), '') into v from generate_series(1, 8);
  insert into report_cards (pupil_id, session_id, pin_hash, expires_at, failed_attempts, issued_at)
  values (p, s, crypt(v, gen_salt('bf', 8)), now() + make_interval(days => days), 0, now())
  on conflict (pupil_id, session_id) do update
    set pin_hash = excluded.pin_hash, expires_at = excluded.expires_at, failed_attempts = 0, issued_at = now();
  update report_cards set locked_until = null where pupil_id = p and session_id = s;
  insert into audit_log (user_id, action, row_new) values (auth.uid(), 'ISSUE_PIN', jsonb_build_object('pupil', p, 'session', s, 'days', days));
  return v;
end $$;

-- ============ 3. Parent portal: no lock-out attacks, no discovery of admission numbers ============
alter table report_cards add column if not exists locked_until timestamptz;
create table if not exists parent_attempts (id bigserial primary key, ip text not null, at timestamptz not null default now());
create index if not exists parent_attempts_ip_at on parent_attempts (ip, at);
alter table parent_attempts enable row level security;     -- no policies: invisible through the API
revoke all on parent_attempts from anon, authenticated;

create or replace function parent_report(adm text, pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_p uuid; rc report_cards%rowtype; v_hdr json; v_ip text; v_pin text := upper(trim(coalesce(pin, '')));
  v_bad jsonb := jsonb_build_object('ok', false, 'error', 'The admission number or PIN is not correct, or access is paused after too many tries. Please check and try again in a few minutes, or contact the school.');
begin
  begin v_hdr := nullif(current_setting('request.headers', true), '')::json; exception when others then v_hdr := null; end;
  v_ip := coalesce(nullif(trim(v_hdr->>'cf-connecting-ip'), ''), nullif(trim(v_hdr->>'x-real-ip'), ''), nullif(trim(split_part(coalesce(v_hdr->>'x-forwarded-for', ''), ',', 1)), ''), 'unknown');
  delete from parent_attempts where at < now() - interval '1 day';
  if (select count(*) from parent_attempts where ip = v_ip and at > now() - interval '15 minutes') >= 20 then
    return jsonb_build_object('ok', false, 'error', 'Too many attempts from this device. Please wait 15 minutes, or contact the school.');
  end if;
  if length(v_pin) < 4 or length(v_pin) > 32 or length(coalesce(adm, '')) > 40 then
    insert into parent_attempts (ip) values (v_ip); return v_bad;
  end if;
  select id into v_p from pupils where admission_no = upper(trim(adm)) and active;
  if v_p is not null then
    select * into rc from report_cards where pupil_id = v_p and pin_hash is not null order by issued_at desc limit 1;
  end if;
  if v_p is null or rc.pupil_id is null then
    perform crypt(v_pin, gen_salt('bf', 8));                 -- same effort as a real check: timing reveals nothing
    insert into parent_attempts (ip) values (v_ip); return v_bad;
  end if;
  if rc.locked_until is not null and rc.locked_until <= now() then
    update report_cards set failed_attempts = 0, locked_until = null where pupil_id = rc.pupil_id and session_id = rc.session_id;
    rc.failed_attempts := 0; rc.locked_until := null;
  end if;
  if rc.locked_until is not null then                         -- paused for 15 minutes (it unlocks itself)
    perform crypt(v_pin, gen_salt('bf', 8)); insert into parent_attempts (ip) values (v_ip); return v_bad;
  end if;
  if rc.pin_hash <> crypt(v_pin, rc.pin_hash) then
    update report_cards set failed_attempts = failed_attempts + 1,
           locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end
     where pupil_id = rc.pupil_id and session_id = rc.session_id;
    insert into parent_attempts (ip) values (v_ip); return v_bad;
  end if;
  if now() > rc.expires_at then                               -- only someone holding the correct PIN is told it expired
    return jsonb_build_object('ok', false, 'error', 'This PIN has expired. Please contact the school for a new one.');
  end if;
  update report_cards set failed_attempts = 0, locked_until = null, last_accessed_at = now() where pupil_id = rc.pupil_id and session_id = rc.session_id;
  return jsonb_build_object('ok', true, 'expires_at', rc.expires_at, 'report', build_report(v_p, rc.session_id, rc.issued_at::date) - 'dob');
end $$;

-- ============ 4. Permissions: only what the app really needs ============
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon, authenticated;

grant execute on function parent_report(text, text) to anon, authenticated;
grant execute on function is_admin(), is_staff(), my_pupil(uuid), my_pupil_s(uuid, uuid), is_open(uuid, uuid) to authenticated;
grant execute on function ensure_session(text, text), claim_class(text, text), submit_class(uuid, uuid),
                          add_pupils(uuid, uuid, text[], text[]), admin_report(uuid, uuid), issue_pin(uuid, uuid, int),
                          purge_expired_pins() to authenticated;

-- ============ 5. Limits on what can be stored ============
alter table pupils drop constraint if exists pupils_email_chk, drop constraint if exists pupils_name_len;
alter table pupils add constraint pupils_email_chk check (parent_email is null or parent_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') not valid;
alter table pupils add constraint pupils_name_len check (char_length(full_name) between 1 and 120) not valid;
alter table remarks drop constraint if exists remarks_len;
alter table remarks add constraint remarks_len check (coalesce(char_length(teacher_remark), 0) <= 1000 and coalesce(char_length(head_remark), 0) <= 1000
  and coalesce(char_length(appearance), 0) <= 200 and coalesce(char_length(weight), 0) <= 40 and coalesce(char_length(height), 0) <= 40) not valid;
alter table progress_remarks drop constraint if exists prog_len;
alter table progress_remarks add constraint prog_len check (char_length(remark) <= 2000) not valid;
alter table teacher_signatures drop constraint if exists sig_len;
alter table teacher_signatures add constraint sig_len check (coalesce(char_length(typed_name), 0) <= 100 and coalesce(char_length(image), 0) <= 400000) not valid;
alter table settings drop constraint if exists settings_len;
alter table settings add constraint settings_len check (char_length(value) <= 400000) not valid;

select email, role, is_super, active from profiles order by created_at;
