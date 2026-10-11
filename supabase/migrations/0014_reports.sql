-- 0014: Gym reports for staff (visits, classes/heatmap, revenue, members/MRR, CSV lists).
-- Idempotent; paste into the SQL Editor. Requires 0009–0013. All dates are Europe/Sofia.
-- Every function is security definer and returns nothing unless the caller is staff of the gym.

create or replace function public.report_bucket(p_date date, p_bucket text)
returns date language sql immutable as $$
  select case coalesce(p_bucket, 'day')
    when 'week' then date_trunc('week', p_date)::date
    when 'month' then date_trunc('month', p_date)::date
    else p_date end;
$$;

-- All visits (members + guests) in a range, with Sofia date/hour.
create or replace function public.report_visits_raw(p_gym uuid, p_from date, p_to date)
returns table (visit_date date, visit_hour int, weekday int, kind text, user_id uuid, guest_id uuid,
               class_id uuid, unpaid boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.class_date,
         coalesce(extract(hour from cs.start_time)::int, extract(hour from a.created_at at time zone 'Europe/Sofia')::int),
         extract(isodow from a.class_date)::int, 'member', a.user_id, null::uuid, a.class_schedule_id, a.unpaid, a.created_at
    from public.attendance a left join public.class_schedules cs on cs.id = a.class_schedule_id
   where a.gym_id = p_gym and a.class_date between p_from and p_to
  union all
  select ga.class_date,
         coalesce(extract(hour from cs.start_time)::int, extract(hour from ga.created_at at time zone 'Europe/Sofia')::int),
         extract(isodow from ga.class_date)::int, 'guest', null::uuid, ga.guest_id, ga.class_schedule_id, not ga.paid, ga.created_at
    from public.guest_attendance ga left join public.class_schedules cs on cs.id = ga.class_schedule_id
   where ga.gym_id = p_gym and ga.class_date between p_from and p_to;
$$;
revoke all on function public.report_visits_raw(uuid, date, date) from public, anon, authenticated;

-- Visits: buckets + totals.
create or replace function public.gym_report_visits(p_gym uuid, p_from date, p_to date, p_bucket text default 'day')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with v as (select * from public.report_visits_raw(p_gym, p_from, p_to))
    select jsonb_build_object(
      'buckets', coalesce((
        select jsonb_agg(b order by b->>'bucket_start') from (
          select jsonb_build_object(
                   'bucket_start', public.report_bucket(visit_date, p_bucket),
                   'checkins', count(*),
                   'unique_members', count(distinct user_id),
                   'guests', count(*) filter (where kind = 'guest'),
                   'unpaid', count(*) filter (where unpaid)) as b
            from v group by public.report_bucket(visit_date, p_bucket)) x), '[]'::jsonb),
      'totals', (select jsonb_build_object(
                   'checkins', count(*),
                   'unique_members', count(distinct user_id),
                   'guests', count(*) filter (where kind = 'guest'),
                   'unpaid', count(*) filter (where unpaid)) from v)));
end $$;
grant execute on function public.gym_report_visits(uuid, date, date, text) to authenticated;

-- Classes: top classes + weekday × hour heatmap.
create or replace function public.gym_report_classes(p_gym uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with v as (select * from public.report_visits_raw(p_gym, p_from, p_to))
    select jsonb_build_object(
      'top_classes', coalesce((
        select jsonb_agg(t order by (t->>'visits')::int desc) from (
          select jsonb_build_object(
                   'class_id', cs.id, 'weekday', cs.weekday,
                   'start_time', to_char(cs.start_time, 'HH24:MI'), 'end_time', to_char(cs.end_time, 'HH24:MI'),
                   'type', cs.type::text, 'visits', count(*),
                   'sessions', count(distinct v.visit_date),
                   'avg_per_session', round(count(*)::numeric / greatest(count(distinct v.visit_date), 1), 1)) as t
            from v join public.class_schedules cs on cs.id = v.class_id
           group by cs.id
           order by count(*) desc limit 10) x), '[]'::jsonb),
      'heatmap', coalesce((
        select jsonb_agg(jsonb_build_object('weekday', weekday, 'hour', visit_hour, 'visits', n))
          from (select weekday, visit_hour, count(*) as n from v group by weekday, visit_hour) h), '[]'::jsonb)));
end $$;
grant execute on function public.gym_report_classes(uuid, date, date) to authenticated;

-- Payments in a range (members + paid guests), with plan kind: subscription | one_off | drop_in.
create or replace function public.report_payments_raw(p_gym uuid, p_from date, p_to date)
returns table (paid_on date, paid_at timestamptz, source text, display_name text, plan_name text, plan_kind text,
               method text, amount numeric, period_month date)
language sql stable security definer set search_path = public as $$
  select (p.paid_at at time zone 'Europe/Sofia')::date, p.paid_at, 'member', pr.display_name, ms.name,
         case when ms.kind = 'one_off' and ms.class_credits = 1 then 'drop_in'
              when ms.kind = 'one_off' then 'one_off' else 'subscription' end,
         p.method, p.amount, p.period_month
    from public.member_payments p
    left join public.memberships ms on ms.id = p.membership_id
    left join public.profiles pr on pr.id = p.user_id
   where p.gym_id = p_gym and (p.paid_at at time zone 'Europe/Sofia')::date between p_from and p_to
  union all
  select ga.class_date, ga.created_at, 'guest', g.name, ms.name, 'drop_in', ga.method, coalesce(ga.amount, 0), null::date
    from public.guest_attendance ga
    join public.kiosk_guests g on g.id = ga.guest_id
    left join public.memberships ms on ms.id = ga.membership_id
   where ga.gym_id = p_gym and ga.paid and ga.class_date between p_from and p_to;
$$;
revoke all on function public.report_payments_raw(uuid, date, date) from public, anon, authenticated;

create or replace function public.gym_report_revenue(p_gym uuid, p_from date, p_to date, p_bucket text default 'month')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with p as (select * from public.report_payments_raw(p_gym, p_from, p_to))
    select jsonb_build_object(
      'rows', coalesce((
        select jsonb_agg(r order by r->>'bucket_start') from (
          select jsonb_build_object('bucket_start', public.report_bucket(paid_on, p_bucket),
                                    'plan_kind', plan_kind, 'method', coalesce(method, 'cash'),
                                    'amount', sum(amount), 'payments', count(*)) as r
            from p group by public.report_bucket(paid_on, p_bucket), plan_kind, coalesce(method, 'cash')) x), '[]'::jsonb),
      'total', (select coalesce(sum(amount), 0) from p),
      'payments', (select count(*) from p),
      'confirmed_claims', (select count(*) from public.payment_claims c
                            where c.gym_id = p_gym and c.status = 'confirmed'
                              and (c.reviewed_at at time zone 'Europe/Sofia')::date between p_from and p_to)));
end $$;
grant execute on function public.gym_report_revenue(uuid, date, date, text) to authenticated;

-- Members: active, new this month, churned (no visit in 30 days), overdue (+ list), MRR estimate.
create or replace function public.gym_report_members(p_gym uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Europe/Sofia')::date;
begin
  if not public.is_gym_staff(p_gym) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with s as (
      select m.user_id, m.joined_at, pr.display_name, ms.id as mid, ms.name as plan_name, ms.price, ms.kind,
             coalesce(ms.period, 'monthly') as period,
             public.has_active_subscription(p_gym, m.user_id) as sub_ok,
             (select max(a.class_date) from public.attendance a where a.gym_id = p_gym and a.user_id = m.user_id) as last_visit,
             (select (date_trunc('month', max(pp.period_month))
                      + make_interval(months => public.membership_months(coalesce(ms.period, 'monthly'))))::date
                from public.member_payments pp left join public.memberships pm on pm.id = pp.membership_id
               where pp.gym_id = p_gym and pp.user_id = m.user_id
                 and coalesce(pm.kind, 'subscription') = 'subscription') as paid_until
        from public.gym_members m
        join public.profiles pr on pr.id = m.user_id
        left join public.memberships ms on ms.id = m.membership_id
       where m.gym_id = p_gym and m.role = 'student' and m.status = 'active'
    ), o as (
      select s.*, coalesce(s.paid_until, date_trunc('month', s.joined_at at time zone 'Europe/Sofia')::date) as due
        from s where s.kind = 'subscription' and not s.sub_ok
    )
    select jsonb_build_object(
      'active', (select count(*) from s),
      'new_this_month', (select count(*) from s
                          where (s.joined_at at time zone 'Europe/Sofia')::date >= date_trunc('month', v_today)::date),
      'churned', (select count(*) from s
                   where coalesce(s.last_visit, (s.joined_at at time zone 'Europe/Sofia')::date) < v_today - 30),
      'overdue', (select count(*) from o where o.due + 7 < v_today),
      'mrr', (select coalesce(round(sum(s.price / public.membership_months(s.period)), 2), 0)
                from s where s.kind = 'subscription' and s.sub_ok),
      'overdue_list', coalesce((
        select jsonb_agg(jsonb_build_object('user_id', o.user_id, 'display_name', o.display_name,
                                            'plan_name', o.plan_name, 'price', o.price, 'due', o.due,
                                            'days_overdue', v_today - o.due) order by o.due)
          from o where o.due + 7 < v_today), '[]'::jsonb)));
end $$;
grant execute on function public.gym_report_members(uuid) to authenticated;

-- CSV sources (staff only).
drop function if exists public.gym_report_visits_list(uuid, date, date);
create function public.gym_report_visits_list(p_gym uuid, p_from date, p_to date)
returns table (visit_date date, visit_time text, kind text, display_name text, class_start text, class_type text,
               unpaid boolean)
language sql stable security definer set search_path = public as $$
  select v.visit_date, to_char(v.created_at at time zone 'Europe/Sofia', 'HH24:MI'), v.kind,
         coalesce(pr.display_name, g.name), to_char(cs.start_time, 'HH24:MI'), cs.type::text, v.unpaid
    from public.report_visits_raw(p_gym, p_from, p_to) v
    left join public.profiles pr on pr.id = v.user_id
    left join public.kiosk_guests g on g.id = v.guest_id
    left join public.class_schedules cs on cs.id = v.class_id
   where public.is_gym_staff(p_gym)
   order by v.created_at;
$$;
grant execute on function public.gym_report_visits_list(uuid, date, date) to authenticated;

drop function if exists public.gym_report_payments_list(uuid, date, date);
create function public.gym_report_payments_list(p_gym uuid, p_from date, p_to date)
returns table (paid_on date, source text, display_name text, plan_name text, plan_kind text, method text,
               amount numeric, period_month date)
language sql stable security definer set search_path = public as $$
  select p.paid_on, p.source, p.display_name, p.plan_name, p.plan_kind, p.method, p.amount, p.period_month
    from public.report_payments_raw(p_gym, p_from, p_to) p
   where public.is_gym_staff(p_gym)
   order by p.paid_at;
$$;
grant execute on function public.gym_report_payments_list(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
