-- 0003: coach bio, account deletion RPC, schema reload. Idempotent; paste into the SQL Editor.

-- Coach bio (shown on coach detail)
alter table public.coaches add column if not exists bio text;

-- Self-service account deletion (App Store requirement).
-- Deleting auth.users cascades to profiles and favorite_gyms; suggestions.user_id is set null,
-- so delete them explicitly to remove the user's content.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.suggestions where user_id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Make sure API roles can reach tables/view (RLS still applies).
grant usage on schema public to anon, authenticated;
grant select on public.cities, public.gyms, public.coaches, public.gym_coaches, public.class_schedules to anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, delete on public.favorite_gyms to authenticated;
grant select, insert on public.suggestions to authenticated;
grant select on public.gyms_with_coords to anon, authenticated;

-- Ask PostgREST to reload its schema cache (fixes PGRST205 for newly created views).
notify pgrst, 'reload schema';
