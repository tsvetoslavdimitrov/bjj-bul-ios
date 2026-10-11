-- 0009: athlete profile + Smoothcomp record, gym management (members, claims, invites, promotions,
-- attendance, classes, memberships, payments), BJJ Bul subscriptions for gyms (manual now, Stripe-ready).
-- Idempotent; paste into the SQL Editor.

-- ======================= Athlete profile =======================
alter table public.profiles add column if not exists team text check (char_length(team) <= 120);
alter table public.profiles add column if not exists team_gym_id uuid references public.gyms(id) on delete set null;
alter table public.profiles add column if not exists smoothcomp_profile_url text;
alter table public.profiles add column if not exists smoothcomp_synced_at timestamptz;
alter table public.profiles add column if not exists smoothcomp_status text;
alter table public.profiles drop constraint if exists profiles_smoothcomp_url_check;
alter table public.profiles add constraint profiles_smoothcomp_url_check check (
  smoothcomp_profile_url is null
  or smoothcomp_profile_url ~ '^https://(www\.)?smoothcomp\.com/([a-z]{2}/)?profile/[0-9]+/?$');

-- Public profile (recreated with the new columns).
drop function if exists public.get_public_profile(uuid);
create function public.get_public_profile(p_user uuid)
returns table (
  id uuid, display_name text, avatar_url text, belt text, stripes smallint, home_gym_id uuid,
  follower_count bigint, following_count bigint, post_count bigint,
  followed_by_me boolean, blocked boolean,
  team text, team_gym_id uuid, smoothcomp_profile_url text
)
language sql stable security definer set search_path = public as $$
  select pr.id, pr.display_name, pr.avatar_url, pr.belt::text, pr.stripes, pr.home_gym_id,
         (select count(*) from public.follows f where f.followee_id = pr.id),
         (select count(*) from public.follows f where f.follower_id = pr.id),
         (select count(*) from public.posts p where p.author_id = pr.id),
         exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = pr.id),
         public.is_blocked_pair(auth.uid(), pr.id),
         pr.team, pr.team_gym_id, pr.smoothcomp_profile_url
  from public.profiles pr
  where pr.id = p_user;
$$;
grant execute on function public.get_public_profile(uuid) to anon, authenticated;

-- ======================= Smoothcomp record =======================
create table if not exists public.athlete_records (
  user_id uuid primary key references auth.users(id) on delete cascade,
  wins int not null default 0 check (wins >= 0),
  losses int not null default 0 check (losses >= 0),
  wins_submission int not null default 0 check (wins_submission >= 0),
  wins_points int not null default 0 check (wins_points >= 0),
  source text not null default 'smoothcomp',
  synced_at timestamptz not null default now()
);
alter table public.athlete_records enable row level security;
drop policy if exists "records public read" on public.athlete_records;
create policy "records public read" on public.athlete_records for select using (true);
grant select on public.athlete_records to anon, authenticated;
-- Written only by the smoothcomp-sync Edge Function (service role).

create table if not exists public.athlete_medals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  event_name text not null check (char_length(event_name) <= 200),
  placement smallint not null check (placement between 1 and 3),
  division text check (char_length(division) <= 200),
  event_date date,
  source text not null default 'manual' check (source in ('manual', 'smoothcomp')),
  verified boolean not null default false,
  external_id text,
  created_at timestamptz not null default now()
);
create index if not exists athlete_medals_user_idx on public.athlete_medals(user_id, event_date desc);
create unique index if not exists athlete_medals_external_uidx on public.athlete_medals(user_id, external_id)
  where external_id is not null;

-- App users can only add manual, unverified medals.
create or replace function public.athlete_medals_guard()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then
    new.source := 'manual';
    new.verified := false;
    new.external_id := null;
  end if;
  return new;
end $$;
drop trigger if exists athlete_medals_guard on public.athlete_medals;
create trigger athlete_medals_guard before insert or update on public.athlete_medals
  for each row execute function public.athlete_medals_guard();

alter table public.athlete_medals enable row level security;
drop policy if exists "medals public read" on public.athlete_medals;
create policy "medals public read" on public.athlete_medals for select using (true);
drop policy if exists "medals insert own manual" on public.athlete_medals;
create policy "medals insert own manual" on public.athlete_medals for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "medals delete own manual" on public.athlete_medals;
create policy "medals delete own manual" on public.athlete_medals for delete to authenticated
  using (auth.uid() = user_id and source = 'manual');
grant select on public.athlete_medals to anon, authenticated;
grant insert, delete on public.athlete_medals to authenticated;

-- ======================= BJJ Bul plans & gym subscriptions =======================
create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  price_monthly_eur numeric(10,2) not null check (price_monthly_eur >= 0),
  features text[] not null default '{}',
  active boolean not null default true,
  sort smallint not null default 0
);
-- Placeholder prices; edit in the Table Editor.
insert into public.plans (code, name, price_monthly_eur, features, sort) values
  ('basic', 'Basic', 19.00, array['members','classes','attendance','payments'], 1),
  ('pro', 'Pro', 39.00, array['members','classes','attendance','payments','promotions_feed','priority_support'], 2)
on conflict (code) do nothing;
alter table public.plans enable row level security;
drop policy if exists "plans public read" on public.plans;
create policy "plans public read" on public.plans for select using (active);
grant select on public.plans to anon, authenticated;

create table if not exists public.gym_subscriptions (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  plan_id uuid references public.plans(id) on delete set null,
  status text not null default 'trialing' check (status in ('trialing', 'active', 'past_due', 'cancelled')),
  trial_ends_at timestamptz,
  current_period_end timestamptz,
  method text check (method in ('cash', 'revolut', 'stripe')),
  stripe_customer_id text,
  stripe_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists gym_subscriptions_updated on public.gym_subscriptions;
create trigger gym_subscriptions_updated before update on public.gym_subscriptions
  for each row execute function set_updated_at();

create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  amount numeric(10,2) not null check (amount >= 0),
  currency text not null default 'EUR',
  method text not null check (method in ('cash', 'revolut', 'stripe')),
  reference text,
  months int not null default 1 check (months between 1 and 24),
  paid_at timestamptz not null default now(),
  stripe_invoice_id text
);
create index if not exists subscription_payments_gym_idx on public.subscription_payments(gym_id, paid_at desc);

-- ======================= Gym members & helpers =======================
create table if not exists public.gym_members (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'coach', 'student')),
  status text not null default 'pending' check (status in ('pending', 'active', 'removed')),
  membership_id uuid,
  joined_at timestamptz not null default now(),
  unique (gym_id, user_id)
);
create index if not exists gym_members_user_idx on public.gym_members(user_id);
create index if not exists gym_members_gym_idx on public.gym_members(gym_id, role, status);

create or replace function public.is_gym_staff(p_gym uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.gym_members m
                 where m.gym_id = p_gym and m.user_id = p_user
                   and m.role in ('owner', 'coach') and m.status = 'active');
$$;

create or replace function public.is_gym_owner(p_gym uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.gym_members m
                 where m.gym_id = p_gym and m.user_id = p_user and m.role = 'owner' and m.status = 'active');
$$;

-- Subscription gate: trialing or active, and not past the period end.
create or replace function public.gym_has_access(p_gym uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.gym_subscriptions s
                 where s.gym_id = p_gym
                   and (   (s.status = 'trialing' and coalesce(s.trial_ends_at, now()) >= now())
                        or (s.status = 'active' and coalesce(s.current_period_end, now()) >= now())));
$$;

create or replace function public.can_manage_gym(p_gym uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_gym_staff(p_gym) and public.gym_has_access(p_gym);
$$;
grant execute on function public.is_gym_staff(uuid, uuid) to authenticated;
grant execute on function public.is_gym_owner(uuid, uuid) to authenticated;
grant execute on function public.gym_has_access(uuid) to authenticated;
grant execute on function public.can_manage_gym(uuid) to authenticated;

alter table public.gym_members enable row level security;
drop policy if exists "members read self or staff" on public.gym_members;
create policy "members read self or staff" on public.gym_members for select to authenticated
  using (user_id = auth.uid() or public.is_gym_staff(gym_id));
drop policy if exists "members staff update" on public.gym_members;
create policy "members staff update" on public.gym_members for update to authenticated
  using (public.can_manage_gym(gym_id)) with check (public.can_manage_gym(gym_id));
drop policy if exists "members leave" on public.gym_members;
create policy "members leave" on public.gym_members for delete to authenticated
  using (user_id = auth.uid() and role <> 'owner');
grant select, update, delete on public.gym_members to authenticated;
-- Inserts go through RPCs below (claims, invites, join requests).

-- Coaches may not change roles to/from owner; only owners manage coaches.
create or replace function public.gym_members_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if tg_op = 'UPDATE' then
    if new.gym_id <> old.gym_id or new.user_id <> old.user_id then
      raise exception 'cannot move membership';
    end if;
    if (old.role <> 'student' or new.role <> 'student') and not public.is_gym_owner(new.gym_id) then
      raise exception 'only the owner can manage coaches';
    end if;
    if old.role = 'owner' and new.user_id = auth.uid() and new.status <> 'active' then
      raise exception 'owner cannot remove themselves';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists gym_members_guard on public.gym_members;
create trigger gym_members_guard before update on public.gym_members
  for each row execute function public.gym_members_guard();

alter table public.gym_subscriptions enable row level security;
drop policy if exists "subscription staff read" on public.gym_subscriptions;
create policy "subscription staff read" on public.gym_subscriptions for select to authenticated
  using (public.is_gym_staff(gym_id));
grant select on public.gym_subscriptions to authenticated;

alter table public.subscription_payments enable row level security;
drop policy if exists "subscription payments owner read" on public.subscription_payments;
create policy "subscription payments owner read" on public.subscription_payments for select to authenticated
  using (public.is_gym_owner(gym_id));
grant select on public.subscription_payments to authenticated;

-- ======================= Claims =======================
create table if not exists public.gym_claims (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  role text not null default 'owner' check (role in ('owner', 'coach')),
  message text not null default '' check (char_length(message) <= 1000),
  contact text check (char_length(contact) <= 200),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create unique index if not exists gym_claims_pending_uidx on public.gym_claims(gym_id, user_id) where status = 'pending';
alter table public.gym_claims enable row level security;
drop policy if exists "claims insert own" on public.gym_claims;
create policy "claims insert own" on public.gym_claims for insert to authenticated
  with check (auth.uid() = user_id and status = 'pending');
drop policy if exists "claims read own" on public.gym_claims;
create policy "claims read own" on public.gym_claims for select to authenticated
  using (auth.uid() = user_id);
grant select, insert on public.gym_claims to authenticated;

-- Admin: approve a claim. Owner claims set gyms.owner_user_id and start a 30-day trial.
create or replace function public.admin_approve_gym_claim(p_claim uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.gym_claims;
begin
  select * into c from public.gym_claims where id = p_claim for update;
  if not found then raise exception 'claim % not found', p_claim; end if;
  if c.status <> 'pending' then raise exception 'claim % is already %', p_claim, c.status; end if;

  insert into public.gym_members (gym_id, user_id, role, status)
  values (c.gym_id, c.user_id, c.role, 'active')
  on conflict (gym_id, user_id) do update set role = excluded.role, status = 'active';

  if c.role = 'owner' then
    update public.gyms set owner_user_id = c.user_id, claim_status = 'approved' where id = c.gym_id;
    insert into public.gym_subscriptions (gym_id, plan_id, status, trial_ends_at)
    values (c.gym_id, (select id from public.plans where code = 'basic'), 'trialing', now() + interval '30 days')
    on conflict (gym_id) do nothing;
  end if;

  update public.gym_claims set status = 'approved', reviewed_at = now() where id = p_claim;
end $$;

create or replace function public.admin_reject_gym_claim(p_claim uuid, p_note text default null)
returns void language sql security definer set search_path = public as $$
  update public.gym_claims set status = 'rejected', admin_note = p_note, reviewed_at = now()
   where id = p_claim and status = 'pending';
$$;

-- Admin: record a subscription payment (cash / Revolut / Stripe) and extend the period.
create or replace function public.admin_record_subscription_payment(
  p_gym uuid, p_amount numeric, p_method text, p_reference text default null, p_months int default 1)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_end timestamptz;
begin
  if p_method not in ('cash', 'revolut', 'stripe') then raise exception 'bad method %', p_method; end if;
  insert into public.subscription_payments (gym_id, amount, method, reference, months)
  values (p_gym, p_amount, p_method, p_reference, p_months);

  insert into public.gym_subscriptions (gym_id, plan_id, status)
  values (p_gym, (select id from public.plans where code = 'basic'), 'active')
  on conflict (gym_id) do nothing;

  update public.gym_subscriptions
     set status = 'active', method = p_method,
         current_period_end = greatest(coalesce(current_period_end, now()), now()) + make_interval(months => p_months)
   where gym_id = p_gym
  returning current_period_end into v_end;
  return v_end;
end $$;

create or replace function public.admin_set_subscription(p_gym uuid, p_status text, p_plan_code text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.gym_subscriptions (gym_id, status) values (p_gym, p_status)
  on conflict (gym_id) do update set status = excluded.status;
  if p_plan_code is not null then
    update public.gym_subscriptions set plan_id = (select id from public.plans where code = p_plan_code)
     where gym_id = p_gym;
  end if;
end $$;

-- Daily housekeeping (optional pg_cron): expire trials/periods.
create or replace function public.admin_expire_subscriptions()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.gym_subscriptions set status = 'past_due'
   where (status = 'trialing' and trial_ends_at < now())
      or (status = 'active' and current_period_end < now());
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.admin_approve_gym_claim(uuid) from public, anon, authenticated;
revoke all on function public.admin_reject_gym_claim(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_record_subscription_payment(uuid, numeric, text, text, int) from public, anon, authenticated;
revoke all on function public.admin_set_subscription(uuid, text, text) from public, anon, authenticated;
revoke all on function public.admin_expire_subscriptions() from public, anon, authenticated;

-- ======================= Invites & join requests =======================
create table if not exists public.gym_invites (
  code text primary key default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  role text not null check (role in ('coach', 'student')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  expires_at timestamptz not null default now() + interval '14 days',
  max_uses int not null default 1 check (max_uses between 1 and 500),
  uses int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.gym_invites enable row level security;
drop policy if exists "invites staff read" on public.gym_invites;
create policy "invites staff read" on public.gym_invites for select to authenticated
  using (public.is_gym_staff(gym_id));
drop policy if exists "invites staff delete" on public.gym_invites;
create policy "invites staff delete" on public.gym_invites for delete to authenticated
  using (public.is_gym_staff(gym_id));
grant select, delete on public.gym_invites to authenticated;

-- Staff create invites (coach invites: owner only).
create or replace function public.create_gym_invite(p_gym uuid, p_role text, p_max_uses int default 1)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if not public.can_manage_gym(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_role = 'coach' and not public.is_gym_owner(p_gym) then
    raise exception 'only the owner can invite coaches' using errcode = '42501';
  end if;
  insert into public.gym_invites (gym_id, role, max_uses) values (p_gym, p_role, greatest(1, least(p_max_uses, 500)))
  returning code into v_code;
  return v_code;
end $$;

-- Anyone signed in redeems a code; invited members become active immediately.
create or replace function public.redeem_gym_invite(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare i public.gym_invites;
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into i from public.gym_invites where code = upper(trim(p_code)) for update;
  if not found or i.expires_at < now() or i.uses >= i.max_uses then
    raise exception 'invalid or expired code' using errcode = 'P0002';
  end if;
  insert into public.gym_members (gym_id, user_id, role, status)
  values (i.gym_id, auth.uid(), i.role, 'active')
  on conflict (gym_id, user_id) do update
    set status = 'active',
        role = case when public.gym_members.role = 'owner' then 'owner' else excluded.role end;
  update public.gym_invites set uses = uses + 1 where code = i.code;
  return i.gym_id;
end $$;

-- A student asks to join (pending until staff approve).
create or replace function public.request_gym_membership(p_gym uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  insert into public.gym_members (gym_id, user_id, role, status)
  values (p_gym, auth.uid(), 'student', 'pending')
  on conflict (gym_id, user_id) do update
    set status = case when public.gym_members.status = 'removed' then 'pending' else public.gym_members.status end;
end $$;
grant execute on function public.create_gym_invite(uuid, text, int) to authenticated;
grant execute on function public.redeem_gym_invite(text) to authenticated;
grant execute on function public.request_gym_membership(uuid) to authenticated;

-- Staff roster with profile info.
create or replace function public.get_gym_roster(p_gym uuid)
returns table (member_id uuid, user_id uuid, display_name text, avatar_url text, belt text, stripes smallint,
               role text, status text, membership_id uuid, joined_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.id, m.user_id, pr.display_name, pr.avatar_url, pr.belt::text, pr.stripes,
         m.role, m.status, m.membership_id, m.joined_at
  from public.gym_members m
  left join public.profiles pr on pr.id = m.user_id
  where m.gym_id = p_gym and public.is_gym_staff(p_gym) and m.status <> 'removed'
  order by case m.role when 'owner' then 0 when 'coach' then 1 else 2 end, pr.display_name;
$$;
grant execute on function public.get_gym_roster(uuid) to authenticated;

-- Gyms where I'm a member (any role), with access flag.
create or replace function public.my_gyms()
returns table (gym_id uuid, gym_name text, gym_slug text, role text, status text, has_access boolean)
language sql stable security definer set search_path = public as $$
  select m.gym_id, g.name, g.slug, m.role, m.status, public.gym_has_access(m.gym_id)
  from public.gym_members m join public.gyms g on g.id = m.gym_id
  where m.user_id = auth.uid() and m.status <> 'removed'
  order by case m.role when 'owner' then 0 when 'coach' then 1 else 2 end, g.name;
$$;
grant execute on function public.my_gyms() to authenticated;

-- ======================= Promotions =======================
create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  belt belt not null,
  stripes smallint not null default 0 check (stripes between 0 and 4),
  note text check (char_length(note) <= 500),
  promoted_by uuid references auth.users(id) on delete set null,
  post_id uuid references public.posts(id) on delete set null,
  promoted_at timestamptz not null default now()
);
create index if not exists promotions_user_idx on public.promotions(user_id, promoted_at desc);
alter table public.promotions enable row level security;
drop policy if exists "promotions read" on public.promotions;
create policy "promotions read" on public.promotions for select using (true);
grant select on public.promotions to anon, authenticated;

create or replace function public.promote_member(p_gym uuid, p_user uuid, p_belt text, p_stripes int,
                                                 p_note text default null, p_post boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_post uuid; v_name text;
begin
  if not public.can_manage_gym(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from public.gym_members where gym_id = p_gym and user_id = p_user and status = 'active') then
    raise exception 'not an active member';
  end if;
  update public.profiles set belt = p_belt::belt, stripes = p_stripes where id = p_user;
  if p_post then
    select name into v_name from public.gyms where id = p_gym;
    insert into public.posts (author_id, body, type, gym_id)
    values (p_user,
            '🥋 ' || initcap(p_belt) || ' belt' ||
              case when p_stripes > 0 then ' · ' || p_stripes || ' stripe(s)' else '' end ||
              ' – ' || coalesce(v_name, '') ||
              case when coalesce(p_note, '') <> '' then E'\n' || p_note else '' end,
            'promotion', p_gym)
    returning id into v_post;
  end if;
  insert into public.promotions (gym_id, user_id, belt, stripes, note, promoted_by, post_id)
  values (p_gym, p_user, p_belt::belt, p_stripes, p_note, auth.uid(), v_post)
  returning id into v_id;
  return v_id;
end $$;
grant execute on function public.promote_member(uuid, uuid, text, int, text, boolean) to authenticated;

-- ======================= Classes (staff CRUD) & attendance =======================
drop policy if exists "schedules staff insert" on public.class_schedules;
create policy "schedules staff insert" on public.class_schedules for insert to authenticated
  with check (public.can_manage_gym(gym_id));
drop policy if exists "schedules staff update" on public.class_schedules;
create policy "schedules staff update" on public.class_schedules for update to authenticated
  using (public.can_manage_gym(gym_id)) with check (public.can_manage_gym(gym_id));
drop policy if exists "schedules staff delete" on public.class_schedules;
create policy "schedules staff delete" on public.class_schedules for delete to authenticated
  using (public.can_manage_gym(gym_id));
grant insert, update, delete on public.class_schedules to authenticated;

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  class_schedule_id uuid references public.class_schedules(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  class_date date not null default ((now() at time zone 'Europe/Sofia')::date),
  checked_in_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index if not exists attendance_uidx on public.attendance(user_id, class_schedule_id, class_date);
create index if not exists attendance_gym_idx on public.attendance(gym_id, class_date desc);
alter table public.attendance enable row level security;
drop policy if exists "attendance read own or staff" on public.attendance;
create policy "attendance read own or staff" on public.attendance for select to authenticated
  using (user_id = auth.uid() or public.is_gym_staff(gym_id));
-- Staff check anyone in; active students may check themselves in (gym needs an active subscription).
drop policy if exists "attendance insert" on public.attendance;
create policy "attendance insert" on public.attendance for insert to authenticated
  with check (
    public.gym_has_access(gym_id) and (
      public.is_gym_staff(gym_id)
      or (user_id = auth.uid() and exists (select 1 from public.gym_members m
             where m.gym_id = attendance.gym_id and m.user_id = auth.uid() and m.status = 'active'))));
drop policy if exists "attendance staff delete" on public.attendance;
create policy "attendance staff delete" on public.attendance for delete to authenticated
  using (public.is_gym_staff(gym_id));
grant select, insert, delete on public.attendance to authenticated;

-- ======================= Memberships & member payments =======================
create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null check (char_length(name) <= 100),
  price numeric(10,2) not null check (price >= 0),
  currency text not null default 'EUR',
  period text not null default 'monthly' check (period in ('monthly', 'quarterly', 'yearly', 'drop_in', 'pack')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.gym_members drop constraint if exists gym_members_membership_fk;
alter table public.gym_members add constraint gym_members_membership_fk
  foreign key (membership_id) references public.memberships(id) on delete set null;

alter table public.memberships enable row level security;
drop policy if exists "memberships read staff or member" on public.memberships;
create policy "memberships read staff or member" on public.memberships for select to authenticated
  using (public.is_gym_staff(gym_id)
         or exists (select 1 from public.gym_members m where m.membership_id = memberships.id and m.user_id = auth.uid()));
drop policy if exists "memberships staff write" on public.memberships;
create policy "memberships staff write" on public.memberships for all to authenticated
  using (public.can_manage_gym(gym_id)) with check (public.can_manage_gym(gym_id));
grant select, insert, update, delete on public.memberships to authenticated;

create table if not exists public.member_payments (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_id uuid references public.memberships(id) on delete set null,
  amount numeric(10,2) not null check (amount >= 0),
  currency text not null default 'EUR',
  method text not null check (method in ('cash', 'revolut', 'card')),
  period_month date not null default (date_trunc('month', now() at time zone 'Europe/Sofia'))::date,
  paid_at timestamptz not null default now(),
  recorded_by uuid references auth.users(id) on delete set null default auth.uid(),
  note text check (char_length(note) <= 300)
);
create index if not exists member_payments_gym_idx on public.member_payments(gym_id, period_month);
create index if not exists member_payments_user_idx on public.member_payments(user_id, paid_at desc);
alter table public.member_payments enable row level security;
drop policy if exists "payments read own or staff" on public.member_payments;
create policy "payments read own or staff" on public.member_payments for select to authenticated
  using (user_id = auth.uid() or public.is_gym_staff(gym_id));
drop policy if exists "payments staff insert" on public.member_payments;
create policy "payments staff insert" on public.member_payments for insert to authenticated
  with check (public.can_manage_gym(gym_id) and recorded_by = auth.uid());
drop policy if exists "payments staff delete" on public.member_payments;
create policy "payments staff delete" on public.member_payments for delete to authenticated
  using (public.can_manage_gym(gym_id));
grant select, insert, delete on public.member_payments to authenticated;

-- Who has paid for a month (default: current month, Sofia time). Students only.
create or replace function public.gym_payment_status(p_gym uuid, p_month date default null)
returns table (user_id uuid, display_name text, membership_name text, price numeric,
               paid boolean, paid_amount numeric, last_paid_at timestamptz)
language sql stable security definer set search_path = public as $$
  with month as (
    select coalesce(date_trunc('month', p_month)::date,
                    date_trunc('month', now() at time zone 'Europe/Sofia')::date) as m
  )
  select mem.user_id, pr.display_name, ms.name, ms.price,
         coalesce(sum(p.amount), 0) > 0,
         coalesce(sum(p.amount), 0),
         max(p.paid_at)
  from public.gym_members mem
  cross join month
  left join public.profiles pr on pr.id = mem.user_id
  left join public.memberships ms on ms.id = mem.membership_id
  left join public.member_payments p
         on p.gym_id = mem.gym_id and p.user_id = mem.user_id and p.period_month = month.m
  where mem.gym_id = p_gym and mem.role = 'student' and mem.status = 'active'
    and public.is_gym_staff(p_gym)
  group by mem.user_id, pr.display_name, ms.name, ms.price
  order by 5, pr.display_name;
$$;
grant execute on function public.gym_payment_status(uuid, date) to authenticated;

-- ======================= Gym profile editing (staff) =======================
create or replace function public.update_gym_profile(
  p_gym uuid, p_name text, p_address text, p_phone text, p_email text, p_website text,
  p_instagram text, p_facebook text, p_affiliation text,
  p_price_drop_in numeric, p_price_monthly numeric, p_price_kids numeric,
  p_has_kids boolean, p_has_women_only boolean, p_photo_urls text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_gym(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.gyms set
    name = coalesce(nullif(trim(p_name), ''), name),
    address = nullif(trim(p_address), ''),
    phone = nullif(trim(p_phone), ''),
    email = nullif(trim(p_email), ''),
    website = nullif(trim(p_website), ''),
    instagram = nullif(trim(p_instagram), ''),
    facebook = nullif(trim(p_facebook), ''),
    affiliation = nullif(trim(p_affiliation), ''),
    price_drop_in = p_price_drop_in,
    price_monthly = p_price_monthly,
    price_kids = p_price_kids,
    has_kids = coalesce(p_has_kids, has_kids),
    has_women_only = coalesce(p_has_women_only, has_women_only),
    photo_urls = coalesce(p_photo_urls, photo_urls)
  where id = p_gym;
end $$;
grant execute on function public.update_gym_profile(uuid, text, text, text, text, text, text, text, text,
  numeric, numeric, numeric, boolean, boolean, text[]) to authenticated;

-- Gym photos: public read; staff upload into "<gym_id>/..." folders.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gym-media', 'gym-media', true, 5242880, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;
drop policy if exists "gym-media public read" on storage.objects;
create policy "gym-media public read" on storage.objects for select
  using (bucket_id = 'gym-media');
drop policy if exists "gym-media staff upload" on storage.objects;
create policy "gym-media staff upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'gym-media'
              and public.can_manage_gym(((storage.foldername(name))[1])::uuid));
drop policy if exists "gym-media staff delete" on storage.objects;
create policy "gym-media staff delete" on storage.objects for delete to authenticated
  using (bucket_id = 'gym-media'
         and public.is_gym_staff(((storage.foldername(name))[1])::uuid));

notify pgrst, 'reload schema';
