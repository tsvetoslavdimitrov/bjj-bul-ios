-- 0011: student "My payments", gym Revolut link, payment claims ("I've paid").
-- Idempotent; paste into the SQL Editor.

-- Gym's own Revolut.me link (students pay the gym directly).
alter table public.gyms add column if not exists revolut_url text;
alter table public.gyms drop constraint if exists gyms_revolut_url_check;
alter table public.gyms add constraint gyms_revolut_url_check
  check (revolut_url is null or (char_length(revolut_url) <= 200
         and revolut_url ~ '^https://revolut\.me/[A-Za-z0-9._-]+/?$'));

create or replace function public.set_gym_revolut_url(p_gym uuid, p_url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_gym(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.gyms set revolut_url = nullif(btrim(p_url), '') where id = p_gym;
end $$;
revoke all on function public.set_gym_revolut_url(uuid, text) from public, anon;
grant execute on function public.set_gym_revolut_url(uuid, text) to authenticated;

-- Months covered by one payment of a membership period.
create or replace function public.membership_months(p_period text)
returns int language sql immutable as $$
  select case p_period when 'quarterly' then 3 when 'yearly' then 12 else 1 end;
$$;

-- "I've paid" claims, confirmed or rejected by gym staff.
create table if not exists public.payment_claims (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  membership_id uuid references public.memberships(id) on delete set null,
  period_month date not null,
  amount numeric(10,2) check (amount is null or amount >= 0),
  method text not null check (method in ('cash', 'revolut', 'card')),
  reference text check (char_length(reference) <= 100),
  note text check (char_length(note) <= 300),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text check (char_length(review_note) <= 300),
  payment_id uuid references public.member_payments(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists payment_claims_gym_idx on public.payment_claims(gym_id, status, created_at desc);
create index if not exists payment_claims_user_idx on public.payment_claims(user_id, created_at desc);
create unique index if not exists payment_claims_pending_uidx
  on public.payment_claims(gym_id, user_id, period_month) where status = 'pending';

alter table public.payment_claims enable row level security;
drop policy if exists "claims read own or staff" on public.payment_claims;
create policy "claims read own or staff" on public.payment_claims for select to authenticated
  using (user_id = auth.uid() or public.is_gym_staff(gym_id));
drop policy if exists "claims insert own" on public.payment_claims;
create policy "claims insert own" on public.payment_claims for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and reviewed_by is null and payment_id is null
              and exists (select 1 from public.gym_members m where m.gym_id = payment_claims.gym_id
                          and m.user_id = auth.uid() and m.status = 'active'));
drop policy if exists "claims staff update" on public.payment_claims;
create policy "claims staff update" on public.payment_claims for update to authenticated
  using (public.is_gym_staff(gym_id)) with check (public.is_gym_staff(gym_id));
drop policy if exists "claims delete own pending" on public.payment_claims;
create policy "claims delete own pending" on public.payment_claims for delete to authenticated
  using (user_id = auth.uid() and status = 'pending');
grant select, insert, update, delete on public.payment_claims to authenticated;

-- One row per gym where I'm an active student.
-- paid_until = first day after the last paid period; status: paid | due (≤7 days grace) | overdue.
drop function if exists public.my_student_memberships();
create function public.my_student_memberships()
returns table (gym_id uuid, gym_name text, gym_slug text, revolut_url text,
               membership_id uuid, membership_name text, price numeric, currency text, period text,
               paid_until date, next_due date, status text, pending_claims int)
language sql stable security definer set search_path = public as $$
  with base as (
    select m.gym_id, g.name, g.slug, g.revolut_url, ms.id as mid, ms.name as mname, ms.price,
           coalesce(ms.currency, 'EUR') as currency, coalesce(ms.period, 'monthly') as period,
           (select (date_trunc('month', max(p.period_month))
                    + make_interval(months => public.membership_months(coalesce(ms.period, 'monthly'))))::date
              from public.member_payments p
             where p.gym_id = m.gym_id and p.user_id = m.user_id) as paid_until,
           date_trunc('month', m.joined_at at time zone 'Europe/Sofia')::date as joined_month,
           (select count(*)::int from public.payment_claims c
             where c.gym_id = m.gym_id and c.user_id = m.user_id and c.status = 'pending') as pending
      from public.gym_members m
      join public.gyms g on g.id = m.gym_id
      left join public.memberships ms on ms.id = m.membership_id
     where m.user_id = auth.uid() and m.role = 'student' and m.status = 'active'
  )
  select b.gym_id, b.name, b.slug, b.revolut_url, b.mid, b.mname, b.price, b.currency, b.period,
         b.paid_until,
         coalesce(b.paid_until, b.joined_month) as next_due,
         case
           when coalesce(b.paid_until, b.joined_month) > (now() at time zone 'Europe/Sofia')::date then 'paid'
           when coalesce(b.paid_until, b.joined_month) + 7 >= (now() at time zone 'Europe/Sofia')::date then 'due'
           else 'overdue'
         end,
         b.pending
    from base b
   order by b.name;
$$;
grant execute on function public.my_student_memberships() to authenticated;

-- Pending claims for staff, with the student's name.
drop function if exists public.get_payment_claims(uuid);
create function public.get_payment_claims(p_gym uuid)
returns table (id uuid, user_id uuid, display_name text, membership_id uuid, period_month date,
               amount numeric, method text, reference text, note text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.user_id, pr.display_name, c.membership_id, c.period_month, c.amount, c.method,
         c.reference, c.note, c.created_at
    from public.payment_claims c
    left join public.profiles pr on pr.id = c.user_id
   where c.gym_id = p_gym and c.status = 'pending' and public.is_gym_staff(p_gym)
   order by c.created_at;
$$;
grant execute on function public.get_payment_claims(uuid) to authenticated;

-- Confirm: records the member payment (amount from the claim, else the plan price).
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
revoke all on function public.confirm_payment_claim(uuid, numeric) from public, anon;
grant execute on function public.confirm_payment_claim(uuid, numeric) to authenticated;

create or replace function public.reject_payment_claim(p_claim uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_gym uuid;
begin
  select gym_id into v_gym from public.payment_claims where id = p_claim and status = 'pending';
  if v_gym is null then raise exception 'claim not found'; end if;
  if not public.is_gym_staff(v_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.payment_claims
     set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(p_note, 300)
   where id = p_claim;
end $$;
revoke all on function public.reject_payment_claim(uuid, text) from public, anon;
grant execute on function public.reject_payment_claim(uuid, text) to authenticated;

notify pgrst, 'reload schema';
