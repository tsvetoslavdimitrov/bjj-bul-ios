-- 0013: Gym Kiosk (front desk): member QR / PIN, leads, guests, kiosk RPCs.
-- Idempotent; paste into the SQL Editor. Requires 0009–0012.
-- All kiosk RPCs run as the signed-in STAFF user on the kiosk device and check is_gym_staff(gym).

create extension if not exists pgcrypto with schema extensions;

-- Short display name for the kiosk: "Ivan P."
create or replace function public.kiosk_short_name(p_name text)
returns text language sql immutable as $$
  select case
    when coalesce(btrim(p_name), '') = '' then '—'
    when position(' ' in btrim(p_name)) = 0 then btrim(p_name)
    else split_part(btrim(p_name), ' ', 1) || ' ' ||
         left(split_part(btrim(p_name), ' ', array_length(regexp_split_to_array(btrim(p_name), '\s+'), 1)), 1) || '.'
  end;
$$;

-- ---------- Member secrets (never readable by clients) ----------
create table if not exists public.member_secrets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  member_code text unique,
  pin_hash text,
  failed_count int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.member_secrets enable row level security;
revoke all on public.member_secrets from anon, authenticated;

create table if not exists public.member_qr_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null
);
create index if not exists member_qr_tokens_user_idx on public.member_qr_tokens(user_id);
alter table public.member_qr_tokens enable row level security;
revoke all on public.member_qr_tokens from anon, authenticated;

create or replace function public.ensure_member_code(p_user uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_code text;
begin
  select member_code into v_code from public.member_secrets where user_id = p_user;
  if v_code is not null then return v_code; end if;
  loop
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8));
    begin
      insert into public.member_secrets (user_id, member_code) values (p_user, v_code)
      on conflict (user_id) do update set member_code = coalesce(member_secrets.member_code, excluded.member_code);
      exit;
    exception when unique_violation then
      -- code collision, try again
    end;
  end loop;
  select member_code into v_code from public.member_secrets where user_id = p_user;
  return v_code;
end $$;
revoke all on function public.ensure_member_code(uuid) from public, anon, authenticated;

-- My QR: a random token valid 2 minutes (the app refreshes it every 60 s), plus my static member code.
drop function if exists public.my_member_qr();
create function public.my_member_qr()
returns table (token text, expires_at timestamptz, member_code text, has_pin boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare v_token text; v_exp timestamptz; v_code text;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  delete from public.member_qr_tokens where user_id = auth.uid() and expires_at < now();
  v_token := encode(extensions.gen_random_bytes(18), 'hex');
  v_exp := now() + interval '2 minutes';
  insert into public.member_qr_tokens (token, user_id, expires_at) values (v_token, auth.uid(), v_exp);
  v_code := public.ensure_member_code(auth.uid());
  return query select v_token, v_exp, v_code,
    exists (select 1 from public.member_secrets s where s.user_id = auth.uid() and s.pin_hash is not null);
end $$;
grant execute on function public.my_member_qr() to authenticated;

create or replace function public.set_member_pin(p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN must be 4 digits'; end if;
  perform public.ensure_member_code(auth.uid());
  update public.member_secrets
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')), failed_count = 0, locked_until = null,
         updated_at = now()
   where user_id = auth.uid();
end $$;
grant execute on function public.set_member_pin(text) to authenticated;

-- ---------- Gym kiosk settings (PIN hash + waiver; not in the public gyms table) ----------
create table if not exists public.gym_kiosk_settings (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  pin_hash text,
  waiver_text text check (char_length(waiver_text) <= 5000),
  updated_at timestamptz not null default now()
);
alter table public.gym_kiosk_settings enable row level security;
revoke all on public.gym_kiosk_settings from anon, authenticated;

drop function if exists public.get_kiosk_settings(uuid);
create function public.get_kiosk_settings(p_gym uuid)
returns table (waiver_text text, has_pin boolean)
language sql stable security definer set search_path = public as $$
  select s.waiver_text, s.pin_hash is not null
    from (select 1) x left join public.gym_kiosk_settings s on s.gym_id = p_gym
   where public.is_gym_staff(p_gym);
$$;
grant execute on function public.get_kiosk_settings(uuid) to authenticated;

-- p_pin null = keep, '' = clear. p_waiver null = keep.
create or replace function public.set_kiosk_settings(p_gym uuid, p_pin text default null, p_waiver text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.can_manage_gym(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_pin is not null and p_pin <> '' and p_pin !~ '^[0-9]{4,6}$' then raise exception 'PIN must be 4–6 digits'; end if;
  insert into public.gym_kiosk_settings (gym_id) values (p_gym) on conflict (gym_id) do nothing;
  update public.gym_kiosk_settings
     set pin_hash = case when p_pin is null then pin_hash
                         when p_pin = '' then null
                         else extensions.crypt(p_pin, extensions.gen_salt('bf')) end,
         waiver_text = coalesce(p_waiver, waiver_text),
         updated_at = now()
   where gym_id = p_gym;
end $$;
grant execute on function public.set_kiosk_settings(uuid, text, text) to authenticated;

create or replace function public.kiosk_staff_pin_ok(p_gym uuid, p_pin text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select s.pin_hash is null or s.pin_hash = extensions.crypt(coalesce(p_pin, ''), s.pin_hash)
                     from public.gym_kiosk_settings s where s.gym_id = p_gym), true);
$$;
revoke all on function public.kiosk_staff_pin_ok(uuid, text) from public, anon, authenticated;

create or replace function public.verify_kiosk_pin(p_gym uuid, p_pin text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  return public.kiosk_staff_pin_ok(p_gym, p_pin);
end $$;
grant execute on function public.verify_kiosk_pin(uuid, text) to authenticated;

-- ---------- Member lookup ----------
-- Name search: min 2 chars, members of this gym only, short name + belt, max 8 rows.
drop function if exists public.kiosk_search_members(uuid, text);
create function public.kiosk_search_members(p_gym uuid, p_query text)
returns table (user_id uuid, short_name text, belt text, has_pin boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_query, ''))) < 2 then return; end if;
  return query
    select m.user_id, public.kiosk_short_name(pr.display_name), pr.belt::text,
           exists (select 1 from public.member_secrets s where s.user_id = m.user_id and s.pin_hash is not null)
      from public.gym_members m
      join public.profiles pr on pr.id = m.user_id
     where m.gym_id = p_gym and m.status in ('active', 'pending')
       and pr.display_name ilike '%' || replace(replace(btrim(p_query), '%', ''), '_', '') || '%'
     order by pr.display_name
     limit 8;
end $$;
grant execute on function public.kiosk_search_members(uuid, text) to authenticated;

-- Resolve a scanned QR ("bjjbul:t:<token>" or "bjjbul:c:<member code>") to a user.
create or replace function public.kiosk_user_from_proof(p_proof text)
returns uuid language sql stable security definer set search_path = public as $$
  select case
    when p_proof like 'bjjbul:t:%' then
      (select t.user_id from public.member_qr_tokens t where t.token = substr(p_proof, 10) and t.expires_at > now())
    when p_proof like 'bjjbul:c:%' then
      (select s.user_id from public.member_secrets s where s.member_code = upper(substr(p_proof, 10)))
  end;
$$;
revoke all on function public.kiosk_user_from_proof(text) from public, anon, authenticated;

drop function if exists public.kiosk_resolve_qr(uuid, text);
create function public.kiosk_resolve_qr(p_gym uuid, p_payload text)
returns table (user_id uuid, short_name text, belt text, member_status text)
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid;
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  v_user := public.kiosk_user_from_proof(p_payload);
  if v_user is null then return; end if;
  return query
    select pr.id, public.kiosk_short_name(pr.display_name), pr.belt::text,
           (select m.status from public.gym_members m where m.gym_id = p_gym and m.user_id = pr.id)
      from public.profiles pr where pr.id = v_user;
end $$;
grant execute on function public.kiosk_resolve_qr(uuid, text) to authenticated;

-- PIN check with lockout (5 wrong tries → 5 minutes).
create or replace function public.kiosk_member_pin_ok(p_user uuid, p_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare s public.member_secrets;
begin
  select * into s from public.member_secrets where user_id = p_user for update;
  if not found or s.pin_hash is null then return false; end if;
  if s.locked_until is not null and s.locked_until > now() then return false; end if;
  if s.pin_hash = extensions.crypt(coalesce(p_pin, ''), s.pin_hash) then
    update public.member_secrets set failed_count = 0, locked_until = null where user_id = p_user;
    return true;
  end if;
  update public.member_secrets
     set failed_count = failed_count + 1,
         locked_until = case when failed_count + 1 >= 5 then now() + interval '5 minutes' else locked_until end
   where user_id = p_user;
  return false;
end $$;
revoke all on function public.kiosk_member_pin_ok(uuid, text) from public, anon, authenticated;

-- Credits left (active passes) for a member.
create or replace function public.kiosk_credits_left(p_gym uuid, p_user uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(credits_left), 0)::int from public.student_passes
   where gym_id = p_gym and user_id = p_user and expires_at > now();
$$;
revoke all on function public.kiosk_credits_left(uuid, uuid) from public, anon, authenticated;

-- ---------- Member check-in ----------
-- p_proof: a QR payload ("bjjbul:t:…"/"bjjbul:c:…") or the 4-digit PIN of p_user.
-- p_allow_unpaid: "Pay later" – check in even without credits (flagged unpaid).
-- status: ok | unpaid | no_credits | bad_proof | not_member | already
drop function if exists public.kiosk_check_in(uuid, uuid, uuid, text, boolean);
create function public.kiosk_check_in(p_gym uuid, p_class uuid, p_user uuid, p_proof text,
                                      p_allow_unpaid boolean default false)
returns table (status text, short_name text, belt text, credits_left int, has_subscription boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := p_user;
  v_status text;
  v_unpaid boolean;
  v_sub boolean;
  v_credits int;
  v_name text;
  v_belt text;
  v_date date := (now() at time zone 'Europe/Sofia')::date;
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_proof like 'staff:%' then
    -- New registrations at the desk: staff vouch with the gym PIN (only when a gym PIN is set).
    if v_user is null or not exists (select 1 from public.gym_kiosk_settings s where s.gym_id = p_gym
                                     and s.pin_hash is not null)
       or not public.kiosk_staff_pin_ok(p_gym, substr(p_proof, 7)) then
      return query select 'bad_proof'::text, null::text, null::text, 0, false; return;
    end if;
  elsif p_proof like 'bjjbul:%' then
    v_user := public.kiosk_user_from_proof(p_proof);
    if v_user is null or (p_user is not null and v_user <> p_user) then
      return query select 'bad_proof'::text, null::text, null::text, 0, false; return;
    end if;
  elsif v_user is null or not public.kiosk_member_pin_ok(v_user, p_proof) then
    return query select 'bad_proof'::text, null::text, null::text, 0, false; return;
  end if;

  select public.kiosk_short_name(pr.display_name), pr.belt::text into v_name, v_belt
    from public.profiles pr where pr.id = v_user;
  if not exists (select 1 from public.gym_members m where m.gym_id = p_gym and m.user_id = v_user
                 and m.status in ('active', 'pending')) then
    return query select 'not_member'::text, v_name, v_belt, 0, false; return;
  end if;

  v_sub := public.has_active_subscription(p_gym, v_user);
  v_credits := public.kiosk_credits_left(p_gym, v_user);

  if exists (select 1 from public.attendance a where a.user_id = v_user and a.class_date = v_date
             and a.class_schedule_id is not distinct from p_class) then
    return query select 'already'::text, v_name, v_belt, v_credits, v_sub; return;
  end if;

  if not v_sub and v_credits = 0 and not coalesce(p_allow_unpaid, false) then
    return query select 'no_credits'::text, v_name, v_belt, 0, false; return;
  end if;

  insert into public.attendance (gym_id, class_schedule_id, user_id, class_date)
  values (p_gym, p_class, v_user, v_date)
  returning unpaid into v_unpaid;
  v_credits := public.kiosk_credits_left(p_gym, v_user);
  v_status := case when v_unpaid or (not v_sub and v_credits = 0 and v_unpaid is not distinct from false
                                     and not exists (select 1 from public.attendance a2 where a2.user_id = v_user
                                                     and a2.class_date = v_date and a2.pass_id is not null
                                                     and a2.class_schedule_id is not distinct from p_class))
                   then 'unpaid' else 'ok' end;
  return query select v_status, v_name, v_belt, public.kiosk_credits_left(p_gym, v_user), v_sub;
end $$;
grant execute on function public.kiosk_check_in(uuid, uuid, uuid, text, boolean) to authenticated;

-- ---------- Payments at the desk ----------
-- Records a member payment immediately (creates a pass for one-off plans, activates a pending membership).
-- Requires the gym's staff PIN when one is set.
create or replace function public.kiosk_record_payment(p_gym uuid, p_user uuid, p_membership uuid,
                                                       p_method text, p_staff_pin text)
returns int language plpgsql security definer set search_path = public as $$
declare v_price numeric; v_ref text;
begin
  if not public.can_manage_gym(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not public.kiosk_staff_pin_ok(p_gym, p_staff_pin) then raise exception 'bad_staff_pin' using errcode = 'P0001'; end if;
  if p_method not in ('cash', 'revolut', 'card') then raise exception 'bad method'; end if;
  select price into v_price from public.memberships where id = p_membership and gym_id = p_gym and active;
  if v_price is null then raise exception 'plan not found'; end if;
  update public.gym_members set status = 'active'
   where gym_id = p_gym and user_id = p_user and role = 'student' and status <> 'active';
  v_ref := 'kiosk';
  insert into public.member_payments (gym_id, user_id, membership_id, amount, method, recorded_by, note)
  values (p_gym, p_user, p_membership, v_price, p_method, auth.uid(), v_ref);
  return public.kiosk_credits_left(p_gym, p_user);
end $$;
grant execute on function public.kiosk_record_payment(uuid, uuid, uuid, text, text) to authenticated;

-- ---------- Leads (new people without an account yet) ----------
create table if not exists public.kiosk_leads (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  email text check (char_length(email) <= 200),
  phone text check (char_length(phone) <= 40),
  belt text not null default 'white',
  user_id uuid references auth.users(id) on delete set null,
  invited_at timestamptz,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists kiosk_leads_gym_idx on public.kiosk_leads(gym_id, created_at desc);
alter table public.kiosk_leads enable row level security;
drop policy if exists "leads staff read" on public.kiosk_leads;
create policy "leads staff read" on public.kiosk_leads for select to authenticated using (public.is_gym_staff(gym_id));
grant select on public.kiosk_leads to authenticated;

create or replace function public.kiosk_create_lead(p_gym uuid, p_name text, p_email text, p_phone text, p_belt text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into public.kiosk_leads (gym_id, name, email, phone, belt)
  values (p_gym, btrim(p_name), nullif(lower(btrim(p_email)), ''), nullif(btrim(p_phone), ''),
          coalesce(nullif(p_belt, ''), 'white'))
  returning id into v_id;
  return v_id;
end $$;
grant execute on function public.kiosk_create_lead(uuid, text, text, text, text) to authenticated;
-- The Edge Function kiosk-invite (service role) invites the email, fills the profile, links lead.user_id and
-- adds a pending student membership.

-- ---------- Guests ----------
create table if not exists public.kiosk_guests (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  phone text check (char_length(phone) <= 40),
  email text check (char_length(email) <= 200),
  waiver_accepted_at timestamptz not null,
  waiver_text text,
  created_at timestamptz not null default now()
);
create index if not exists kiosk_guests_gym_idx on public.kiosk_guests(gym_id, created_at desc);
alter table public.kiosk_guests enable row level security;
drop policy if exists "guests staff read" on public.kiosk_guests;
create policy "guests staff read" on public.kiosk_guests for select to authenticated using (public.is_gym_staff(gym_id));
grant select on public.kiosk_guests to authenticated;

create table if not exists public.guest_attendance (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  guest_id uuid not null references public.kiosk_guests(id) on delete cascade,
  class_schedule_id uuid references public.class_schedules(id) on delete set null,
  class_date date not null default ((now() at time zone 'Europe/Sofia')::date),
  membership_id uuid references public.memberships(id) on delete set null,
  amount numeric(10,2),
  method text check (method in ('cash', 'revolut', 'card')),
  paid boolean not null default false,
  recorded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists guest_attendance_gym_idx on public.guest_attendance(gym_id, class_date desc);
alter table public.guest_attendance enable row level security;
drop policy if exists "guest attendance staff read" on public.guest_attendance;
create policy "guest attendance staff read" on public.guest_attendance for select to authenticated
  using (public.is_gym_staff(gym_id));
drop policy if exists "guest attendance staff update" on public.guest_attendance;
create policy "guest attendance staff update" on public.guest_attendance for update to authenticated
  using (public.can_manage_gym(gym_id)) with check (public.can_manage_gym(gym_id));
grant select, update on public.guest_attendance to authenticated;

-- Guest check-in. p_method null = pay later (unpaid). A paid method requires the staff PIN (if set).
create or replace function public.kiosk_guest_check_in(p_gym uuid, p_class uuid, p_name text, p_phone text,
                                                       p_email text, p_waiver_accepted boolean, p_membership uuid,
                                                       p_method text, p_staff_pin text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_guest uuid; v_price numeric; v_waiver text;
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not coalesce(p_waiver_accepted, false) then raise exception 'waiver_required' using errcode = 'P0001'; end if;
  if p_method is not null then
    if not public.kiosk_staff_pin_ok(p_gym, p_staff_pin) then raise exception 'bad_staff_pin' using errcode = 'P0001'; end if;
    if p_method not in ('cash', 'revolut', 'card') then raise exception 'bad method'; end if;
  end if;
  if p_membership is not null then
    select price into v_price from public.memberships where id = p_membership and gym_id = p_gym and active;
  end if;
  select waiver_text into v_waiver from public.gym_kiosk_settings where gym_id = p_gym;
  insert into public.kiosk_guests (gym_id, name, phone, email, waiver_accepted_at, waiver_text)
  values (p_gym, btrim(p_name), nullif(btrim(p_phone), ''), nullif(lower(btrim(p_email)), ''), now(), v_waiver)
  returning id into v_guest;
  insert into public.guest_attendance (gym_id, guest_id, class_schedule_id, membership_id, amount, method, paid)
  values (p_gym, v_guest, p_class, p_membership, v_price, p_method, p_method is not null);
  return v_guest;
end $$;
grant execute on function public.kiosk_guest_check_in(uuid, uuid, text, text, text, boolean, uuid, text, text) to authenticated;

-- ---------- Staff: today's attendance (members + guests) ----------
drop function if exists public.kiosk_attendance_today(uuid);
create function public.kiosk_attendance_today(p_gym uuid)
returns table (id uuid, kind text, display_name text, belt text, class_id uuid, class_start text,
               unpaid boolean, credits_left int, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, 'member'::text, pr.display_name, pr.belt::text, a.class_schedule_id,
         to_char(cs.start_time, 'HH24:MI'), a.unpaid, public.kiosk_credits_left(p_gym, a.user_id), a.created_at
    from public.attendance a
    left join public.profiles pr on pr.id = a.user_id
    left join public.class_schedules cs on cs.id = a.class_schedule_id
   where a.gym_id = p_gym and a.class_date = (now() at time zone 'Europe/Sofia')::date and public.is_gym_staff(p_gym)
  union all
  select ga.id, 'guest'::text, g.name, null::text, ga.class_schedule_id,
         to_char(cs.start_time, 'HH24:MI'), not ga.paid, null::int, ga.created_at
    from public.guest_attendance ga
    join public.kiosk_guests g on g.id = ga.guest_id
    left join public.class_schedules cs on cs.id = ga.class_schedule_id
   where ga.gym_id = p_gym and ga.class_date = (now() at time zone 'Europe/Sofia')::date and public.is_gym_staff(p_gym)
  order by 9 desc;
$$;
grant execute on function public.kiosk_attendance_today(uuid) to authenticated;

notify pgrst, 'reload schema';

-- Used only by the kiosk-invite Edge Function (service role).
create or replace function public.kiosk_find_user_by_email(p_email text)
returns uuid language sql stable security definer set search_path = public, auth as $$
  select id from auth.users where lower(email) = lower(btrim(p_email)) limit 1;
$$;
revoke all on function public.kiosk_find_user_by_email(text) from public, anon, authenticated;
grant execute on function public.kiosk_find_user_by_email(text) to service_role;
grant execute on function public.is_gym_staff(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
