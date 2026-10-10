-- 0005: Terms of Use acceptance (Apple Guideline 1.2). Idempotent.
alter table public.profiles add column if not exists terms_accepted_at timestamptz;
alter table public.profiles add column if not exists terms_version text;

-- Records acceptance with server time for the signed-in user.
create or replace function public.accept_terms(p_version text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  insert into public.profiles (id, terms_accepted_at, terms_version)
  values (auth.uid(), now(), p_version)
  on conflict (id) do update
    set terms_accepted_at = now(), terms_version = excluded.terms_version;
end;
$$;

revoke all on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated;

notify pgrst, 'reload schema';
