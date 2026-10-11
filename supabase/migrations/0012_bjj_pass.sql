-- 0012: BJJ Pass – subscriptions + one-off passes (class credits), visitor drop-ins.
-- Idempotent; paste into the SQL Editor. Requires 0009 and 0011.

-- ---------- Plans: kind, credits, validity ----------
alter table public.memberships add column if not exists kind text not null default 'subscription';
alter table public.memberships add column if not exists class_credits int;
alter table public.memberships add column if not exists validity_days int;
-- Existing drop-in / class-pack plans become one-off passes with sensible defaults.
update public.memberships
   set kind = 'one_off',
       class_credits = coalesce(class_credits, case period when 'drop_in' then 1 else 10 end),
       validity_days = coalesce(validity_days, case period when 'drop_in' then 30 else 90 end)
 where period in ('drop_in', 'pack') and kind = 'subscription';
alter table public.memberships drop constraint if exists memberships_kind_check;
alter table public.memberships add constraint memberships_kind_check check (
  kind in ('subscription', 'one_off')
  and (kind = 'subscription' or (class_credits between 1 and 500 and validity_days between 1 and 730)));

-- ---------- Passes ----------
create table if not exists public.student_passes (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_id uuid references public.memberships(id) on delete set null,
  plan_name text not null default '',
  credits_total int not null check (credits_total >= 0),
  credits_left int not null check (credits_left >= 0),
  expires_at timestamptz not null,
  payment_id uuid unique references public.member_payments(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists student_passes_user_idx on public.student_passes(gym_id, user_id, expires_at);
alter table public.student_passes enable row level security;
drop policy if exists "passes read own or staff" on public.student_passes;
create policy "passes read own or staff" on public.student_passes for select to authenticated
  using (user_id = auth.uid() or public.is_gym_staff(gym_id));
drop policy if exists "passes staff update" on public.student_passes;
create policy "passes staff update" on public.student_passes for update to authenticated
  using (public.can_manage_gym(gym_id)) with check (public.can_manage_gym(gym_id));
grant select, update on public.student_passes to authenticated;

-- A recorded payment for a one-off plan creates a pass (covers staff recording and claim confirmation).
create or replace function public.member_payment_create_pass()
returns trigger language plpgsql security definer set search_path = public as $$
declare ms public.memberships;
begin
  if new.membership_id is null then return new; end if;
  select * into ms from public.memberships where id = new.membership_id;
  if found and ms.kind = 'one_off' then
    insert into public.student_passes (gym_id, user_id, membership_id, plan_name, credits_total, credits_left,
                                       expires_at, payment_id)
    values (new.gym_id, new.user_id, ms.id, ms.name, ms.class_credits, ms.class_credits,
            now() + make_interval(days => ms.validity_days), new.id)
    on conflict (payment_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists member_payment_create_pass on public.member_payments;
create trigger member_payment_create_pass after insert on public.member_payments
  for each row execute function public.member_payment_create_pass();

-- Active subscription = a subscription (or legacy, plan-less) payment whose period covers today.
create or replace function public.has_active_subscription(p_gym uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.member_payments p
      left join public.memberships ms on ms.id = p.membership_id
     where p.gym_id = p_gym and p.user_id = p_user
       and coalesce(ms.kind, 'subscription') = 'subscription'
       and (date_trunc('month', p.period_month)
            + make_interval(months => public.membership_months(coalesce(ms.period, 'monthly'))))::date
           > (now() at time zone 'Europe/Sofia')::date);
$$;

-- ---------- Attendance uses credits ----------
alter table public.attendance add column if not exists pass_id uuid references public.student_passes(id) on delete set null;
alter table public.attendance add column if not exists unpaid boolean not null default false;

-- Students without an active subscription spend one credit per check-in (earliest-expiring pass first).
-- No credits: a self check-in is blocked (error 'no_credits') if the gym sells passes; otherwise, or when staff
-- check someone in, it's allowed and flagged unpaid = true (the app shows a warning).
create or replace function public.attendance_use_credit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_pass uuid;
begin
  if not exists (select 1 from public.gym_members m where m.gym_id = new.gym_id and m.user_id = new.user_id
                 and m.role = 'student' and m.status = 'active') then
    return new;
  end if;
  if public.has_active_subscription(new.gym_id, new.user_id) then return new; end if;
  select id into v_pass from public.student_passes
   where gym_id = new.gym_id and user_id = new.user_id and credits_left > 0 and expires_at > now()
   order by expires_at limit 1 for update;
  if v_pass is not null then
    update public.student_passes set credits_left = credits_left - 1 where id = v_pass;
    new.pass_id := v_pass;
    new.unpaid := false;
    return new;
  end if;
  if new.user_id = auth.uid() and not public.is_gym_staff(new.gym_id)
     and exists (select 1 from public.memberships where gym_id = new.gym_id and kind = 'one_off' and active) then
    raise exception 'no_credits' using errcode = 'P0001', hint = 'Buy a BJJ Pass or ask your coach';
  end if;
  new.unpaid := true;
  return new;
end $$;
drop trigger if exists attendance_use_credit on public.attendance;
create trigger attendance_use_credit before insert on public.attendance
  for each row execute function public.attendance_use_credit();

-- Undoing a check-in gives the credit back.
create or replace function public.attendance_refund_credit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.pass_id is not null then
    update public.student_passes set credits_left = least(credits_total, credits_left + 1) where id = old.pass_id;
  end if;
  return old;
end $$;
drop trigger if exists attendance_refund_credit on public.attendance;
create trigger attendance_refund_credit after delete on public.attendance
  for each row execute function public.attendance_refund_credit();

-- ---------- Visitors: buy a one-off pass without being a member ----------
-- Public list of a gym's active plans plus its payment details.
drop function if exists public.gym_pass_plans(uuid);
create function public.gym_pass_plans(p_gym uuid)
returns table (id uuid, name text, kind text, price numeric, currency text, period text,
               class_credits int, validity_days int, gym_slug text, revolut_url text)
language sql stable security definer set search_path = public as $$
  select ms.id, ms.name, ms.kind, ms.price, ms.currency, ms.period, ms.class_credits, ms.validity_days,
         g.slug, g.revolut_url
    from public.memberships ms join public.gyms g on g.id = ms.gym_id
   where ms.gym_id = p_gym and ms.active
   order by ms.kind desc, ms.price;
$$;
grant execute on function public.gym_pass_plans(uuid) to anon, authenticated;

drop policy if exists "claims insert own" on public.payment_claims;
create policy "claims insert own" on public.payment_claims for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and reviewed_by is null and payment_id is null
              and (exists (select 1 from public.gym_members m where m.gym_id = payment_claims.gym_id
                           and m.user_id = auth.uid() and m.status = 'active')
                   or exists (select 1 from public.memberships ms where ms.id = payment_claims.membership_id
                              and ms.gym_id = payment_claims.gym_id and ms.kind = 'one_off' and ms.active)));

-- A visitor's claim creates a pending student membership (staff see it with the claim).
create or replace function public.payment_claim_pending_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.gym_members (gym_id, user_id, role, status)
  values (new.gym_id, new.user_id, 'student', 'pending')
  on conflict (gym_id, user_id) do nothing;
  return new;
end $$;
drop trigger if exists payment_claim_pending_member on public.payment_claims;
create trigger payment_claim_pending_member after insert on public.payment_claims
  for each row execute function public.payment_claim_pending_member();

-- Confirm also activates a pending / removed student membership.
create or replace function public.confirm_payment_claim(p_claim uuid, p_amount numeric default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  c public.payment_claims;
  v_amount numeric;
  v_payment uuid;
begin
  select * into c from public.payment_claims where id = p_claim for update;
  if not found then raise exception 'claim not found'; end if;
  if not public.can_manage_gym(c.gym_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if c.status <> 'pending' then raise exception 'claim already reviewed'; end if;
  update public.gym_members set status = 'active'
   where gym_id = c.gym_id and user_id = c.user_id and role = 'student' and status <> 'active';
  v_amount := coalesce(p_amount, c.amount, (select price from public.memberships where id = c.membership_id), 0);
  insert into public.member_payments (gym_id, user_id, membership_id, amount, method, period_month, recorded_by, note)
  values (c.gym_id, c.user_id, c.membership_id, v_amount, c.method, c.period_month, auth.uid(),
          left(coalesce(c.reference, '') || case when c.note is not null then ' · ' || c.note else '' end, 300))
  returning id into v_payment;
  update public.payment_claims
     set status = 'confirmed', reviewed_by = auth.uid(), reviewed_at = now(), payment_id = v_payment
   where id = p_claim;
  return v_payment;
end $$;

-- Staff: pending claims now include the plan name/kind.
drop function if exists public.get_payment_claims(uuid);
create function public.get_payment_claims(p_gym uuid)
returns table (id uuid, user_id uuid, display_name text, membership_id uuid, period_month date,
               amount numeric, method text, reference text, note text, created_at timestamptz,
               plan_name text, plan_kind text)
language sql stable security definer set search_path = public as $$
  select c.id, c.user_id, pr.display_name, c.membership_id, c.period_month, c.amount, c.method,
         c.reference, c.note, c.created_at, ms.name, ms.kind
    from public.payment_claims c
    left join public.profiles pr on pr.id = c.user_id
    left join public.memberships ms on ms.id = c.membership_id
   where c.gym_id = p_gym and c.status = 'pending' and public.is_gym_staff(p_gym)
   order by c.created_at;
$$;
grant execute on function public.get_payment_claims(uuid) to authenticated;

-- Staff: active passes.
drop function if exists public.get_gym_passes(uuid);
create function public.get_gym_passes(p_gym uuid)
returns table (id uuid, user_id uuid, display_name text, plan_name text, credits_left int, credits_total int,
               expires_at timestamptz)
language sql stable security definer set search_path = public as $$
  select sp.id, sp.user_id, pr.display_name, sp.plan_name, sp.credits_left, sp.credits_total, sp.expires_at
    from public.student_passes sp
    left join public.profiles pr on pr.id = sp.user_id
   where sp.gym_id = p_gym and sp.expires_at > now() and sp.credits_left > 0 and public.is_gym_staff(p_gym)
   order by sp.expires_at;
$$;
grant execute on function public.get_gym_passes(uuid) to authenticated;

-- ---------- Student: BJJ Pass overview ----------
-- One row per gym where I'm an active student (or have an active pass / pending claim).
-- status: paid | due | overdue for subscriptions, 'none' when no subscription applies.
drop function if exists public.my_bjj_pass();
create function public.my_bjj_pass()
returns table (gym_id uuid, gym_name text, gym_slug text, revolut_url text,
               membership_id uuid, membership_name text, membership_kind text, price numeric, currency text,
               period text, paid_until date, next_due date, status text, pending_claims int,
               member_status text, pass_credits int, pass_expires_at timestamptz)
language sql stable security definer set search_path = public as $$
  with base as (
    select m.gym_id, m.user_id, m.status as mstatus, m.joined_at, g.name, g.slug, g.revolut_url,
           ms.id as mid, ms.name as mname, coalesce(ms.kind, 'subscription') as mkind, ms.price,
           coalesce(ms.currency, 'EUR') as currency, coalesce(ms.period, 'monthly') as period
      from public.gym_members m
      join public.gyms g on g.id = m.gym_id
      left join public.memberships ms on ms.id = m.membership_id
     where m.user_id = auth.uid() and m.role = 'student' and m.status in ('active', 'pending')
  ), calc as (
    select b.*,
           (select (date_trunc('month', max(p.period_month))
                    + make_interval(months => public.membership_months(b.period)))::date
              from public.member_payments p
              left join public.memberships pm on pm.id = p.membership_id
             where p.gym_id = b.gym_id and p.user_id = b.user_id
               and coalesce(pm.kind, 'subscription') = 'subscription') as paid_until,
           date_trunc('month', b.joined_at at time zone 'Europe/Sofia')::date as joined_month,
           (select count(*)::int from public.payment_claims c
             where c.gym_id = b.gym_id and c.user_id = b.user_id and c.status = 'pending') as pending,
           (select coalesce(sum(sp.credits_left), 0)::int from public.student_passes sp
             where sp.gym_id = b.gym_id and sp.user_id = b.user_id and sp.expires_at > now()) as credits,
           (select min(sp.expires_at) from public.student_passes sp
             where sp.gym_id = b.gym_id and sp.user_id = b.user_id and sp.expires_at > now()
               and sp.credits_left > 0) as pass_exp
      from base b
  )
  select c.gym_id, c.name, c.slug, c.revolut_url, c.mid, c.mname, c.mkind, c.price, c.currency, c.period,
         c.paid_until,
         case when c.mkind = 'subscription' and c.mid is not null or c.paid_until is not null
              then coalesce(c.paid_until, c.joined_month) end,
         case
           when not (c.mkind = 'subscription' and c.mid is not null or c.paid_until is not null) then 'none'
           when coalesce(c.paid_until, c.joined_month) > (now() at time zone 'Europe/Sofia')::date then 'paid'
           when coalesce(c.paid_until, c.joined_month) + 7 >= (now() at time zone 'Europe/Sofia')::date then 'due'
           else 'overdue'
         end,
         c.pending, c.mstatus, c.credits, c.pass_exp
    from calc c
   order by c.name;
$$;
grant execute on function public.my_bjj_pass() to authenticated;

notify pgrst, 'reload schema';
