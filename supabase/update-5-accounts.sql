-- UPDATE 5 for the Comence portal. Run ONCE in Supabase SQL Editor, after update-4.
-- Adds a "super admin" level above the ordinary admin (for example the proprietress).

alter table profiles add column if not exists is_super boolean not null default false;

-- Your existing admin (the earliest one created) becomes the super admin.
update profiles set is_super = true
where id = (select id from profiles where role = 'admin' order by created_at limit 1)
  and not exists (select 1 from profiles where is_super);

-- Admins can READ all profiles but can no longer write them from the browser.
-- Accounts are created, reset and deleted only through the portal's server function,
-- which enforces who may do what.
drop policy if exists admin_all on profiles;
create policy admin_read_profiles on profiles for select using (is_admin());

select email, full_name, role, is_super from profiles order by created_at;
