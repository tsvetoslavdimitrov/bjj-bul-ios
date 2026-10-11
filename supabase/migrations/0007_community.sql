-- 0007: Explore contributions, reviews, open mats, drop-ins, training log,
-- notifications (APNs-ready), Instagram embed. Idempotent; paste into the SQL Editor.

-- ---------- Gyms: Instagram embed (admin-set) ----------
alter table public.gyms add column if not exists instagram_embed_url text;

-- ---------- Reviews ----------
create table if not exists public.gym_reviews (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  rating smallint not null check (rating between 1 and 5),
  body text not null default '' check (char_length(body) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (gym_id, user_id)
);
create index if not exists gym_reviews_gym_idx on public.gym_reviews(gym_id, created_at desc);
drop trigger if exists gym_reviews_updated on public.gym_reviews;
create trigger gym_reviews_updated before update on public.gym_reviews
  for each row execute function set_updated_at();

alter table public.gym_reviews enable row level security;
drop policy if exists "reviews read unblocked" on public.gym_reviews;
create policy "reviews read unblocked" on public.gym_reviews for select
  using (not public.is_blocked_pair(auth.uid(), user_id));
drop policy if exists "reviews insert own" on public.gym_reviews;
create policy "reviews insert own" on public.gym_reviews for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "reviews update own" on public.gym_reviews;
create policy "reviews update own" on public.gym_reviews for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "reviews delete own" on public.gym_reviews;
create policy "reviews delete own" on public.gym_reviews for delete to authenticated
  using (auth.uid() = user_id);
grant select on public.gym_reviews to anon, authenticated;
grant insert, update, delete on public.gym_reviews to authenticated;

create or replace function public.get_gym_reviews(p_gym uuid)
returns table (id uuid, gym_id uuid, user_id uuid, author_name text, rating smallint, body text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, r.gym_id, r.user_id, pr.display_name, r.rating, r.body, r.created_at
  from public.gym_reviews r
  left join public.profiles pr on pr.id = r.user_id
  where r.gym_id = p_gym and not public.is_blocked_pair(auth.uid(), r.user_id)
  order by r.created_at desc
  limit 200;
$$;
grant execute on function public.get_gym_reviews(uuid) to anon, authenticated;

-- Reports can target reviews
alter table public.reports add column if not exists review_id uuid references public.gym_reviews(id) on delete set null;
alter table public.reports drop constraint if exists reports_check;
alter table public.reports drop constraint if exists reports_target_check;
alter table public.reports add constraint reports_target_check
  check (post_id is not null or comment_id is not null or reported_user_id is not null or review_id is not null);

-- Gyms view with coordinates + rating (recreated so new columns appear)
drop view if exists public.gyms_with_coords;
create view public.gyms_with_coords with (security_invoker = true) as
select g.*,
       case when g.location is null then null else st_y(g.location::geometry) end as lat,
       case when g.location is null then null else st_x(g.location::geometry) end as lng,
       r.rating_avg,
       coalesce(r.rating_count, 0) as rating_count
from public.gyms g
left join lateral (
  select round(avg(x.rating)::numeric, 2)::float8 as rating_avg, count(*)::int as rating_count
  from public.gym_reviews x where x.gym_id = g.id
) r on true;
grant select on public.gyms_with_coords to anon, authenticated;

-- ---------- Gym submissions (new gym / location fix) ----------
create table if not exists public.gym_submissions (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('new_gym', 'location_fix')),
  gym_id uuid references public.gyms(id) on delete cascade,
  submitted_by uuid references auth.users(id) on delete set null default auth.uid(),
  name text check (char_length(name) <= 200),
  affiliation text,
  phone text,
  instagram text,
  website text,
  city_name text,
  address text,
  latitude double precision check (latitude between 41 and 44.5),
  longitude double precision check (longitude between 22 and 29),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  check (kind <> 'location_fix' or gym_id is not null),
  check (kind <> 'new_gym' or name is not null)
);
create index if not exists gym_submissions_status_idx on public.gym_submissions(status, created_at);
alter table public.gym_submissions enable row level security;
drop policy if exists "submissions insert own" on public.gym_submissions;
create policy "submissions insert own" on public.gym_submissions for insert to authenticated
  with check (auth.uid() = submitted_by and status = 'pending');
drop policy if exists "submissions read own" on public.gym_submissions;
create policy "submissions read own" on public.gym_submissions for select to authenticated
  using (auth.uid() = submitted_by);
grant select, insert on public.gym_submissions to authenticated;

-- Admin (dashboard / service role only): approve a submission. Returns the gym id.
create or replace function public.approve_gym_submission(p_id uuid, p_city_slug text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  s public.gym_submissions;
  v_city uuid;
  v_gym uuid;
begin
  select * into s from public.gym_submissions where id = p_id for update;
  if not found then raise exception 'submission % not found', p_id; end if;
  if s.status <> 'pending' then raise exception 'submission % is already %', p_id, s.status; end if;

  if s.kind = 'location_fix' then
    if s.latitude is null or s.longitude is null then raise exception 'no coordinates'; end if;
    update public.gyms
       set location = st_setsrid(st_makepoint(s.longitude, s.latitude), 4326)::geography,
           address = coalesce(nullif(s.address, ''), address)
     where id = s.gym_id;
    v_gym := s.gym_id;
  else
    if p_city_slug is not null then
      select id into v_city from public.cities where slug = p_city_slug;
    else
      select id into v_city from public.cities
       where lower(name_bg) = lower(trim(s.city_name)) or lower(name_en) = lower(trim(s.city_name))
       limit 1;
    end if;
    if v_city is null then
      raise exception 'unknown city "%": pass p_city_slug (see cities.slug)', s.city_name;
    end if;
    insert into public.gyms (slug, name, city_id, address, location, affiliation, phone,
                             website, instagram, source_url, verified, review_status)
    values ('sub-' || left(s.id::text, 8), s.name, v_city, s.address,
            case when s.latitude is null then null
                 else st_setsrid(st_makepoint(s.longitude, s.latitude), 4326)::geography end,
            nullif(s.affiliation, ''), nullif(s.phone, ''), nullif(s.website, ''),
            nullif(s.instagram, ''), 'user-submission:' || s.id::text, false, 'needs_review')
    returning id into v_gym;
  end if;

  update public.gym_submissions set status = 'approved', reviewed_at = now() where id = p_id;
  return v_gym;
end $$;

create or replace function public.reject_gym_submission(p_id uuid, p_note text default null)
returns void language sql security definer set search_path = public as $$
  update public.gym_submissions
     set status = 'rejected', admin_note = p_note, reviewed_at = now()
   where id = p_id and status = 'pending';
$$;
revoke all on function public.approve_gym_submission(uuid, text) from public, anon, authenticated;
revoke all on function public.reject_gym_submission(uuid, text) from public, anon, authenticated;

-- ---------- Open mats ----------
create table if not exists public.open_mats (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  style text not null default 'both' check (style in ('gi', 'nogi', 'both')),
  fee numeric(10,2) check (fee is null or fee >= 0),
  currency text not null default 'EUR',
  notes text check (char_length(notes) <= 1000),
  verified boolean not null default false,
  posted_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists open_mats_starts_idx on public.open_mats(starts_at);
create index if not exists open_mats_gym_idx on public.open_mats(gym_id, starts_at);

-- Verified only when posted by the gym owner (admins in the dashboard may set it freely).
create or replace function public.open_mats_set_verified()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.verified := exists (select 1 from public.gyms g
                            where g.id = new.gym_id and g.owner_user_id = new.posted_by);
  end if;
  return new;
end $$;
drop trigger if exists open_mats_verified on public.open_mats;
create trigger open_mats_verified before insert or update on public.open_mats
  for each row execute function public.open_mats_set_verified();

alter table public.open_mats enable row level security;
drop policy if exists "open mats read" on public.open_mats;
create policy "open mats read" on public.open_mats for select using (true);
drop policy if exists "open mats insert own" on public.open_mats;
create policy "open mats insert own" on public.open_mats for insert to authenticated
  with check (auth.uid() = posted_by);
drop policy if exists "open mats update own" on public.open_mats;
create policy "open mats update own" on public.open_mats for update to authenticated
  using (auth.uid() = posted_by) with check (auth.uid() = posted_by);
drop policy if exists "open mats delete own" on public.open_mats;
create policy "open mats delete own" on public.open_mats for delete to authenticated
  using (auth.uid() = posted_by);
grant select on public.open_mats to anon, authenticated;
grant insert, update, delete on public.open_mats to authenticated;

-- ---------- Drop-in requests ----------
create table if not exists public.drop_in_requests (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  preferred_date date,
  preferred_class text check (char_length(preferred_class) <= 200),
  message text not null default '' check (char_length(message) <= 1000),
  status text not null default 'pending' check (status in ('pending', 'contacted', 'closed')),
  created_at timestamptz not null default now()
);
create index if not exists drop_in_user_idx on public.drop_in_requests(user_id, created_at desc);
create index if not exists drop_in_gym_idx on public.drop_in_requests(gym_id, created_at desc);
alter table public.drop_in_requests enable row level security;
drop policy if exists "drop-in insert own" on public.drop_in_requests;
create policy "drop-in insert own" on public.drop_in_requests for insert to authenticated
  with check (auth.uid() = user_id and status = 'pending');
drop policy if exists "drop-in read own or gym owner" on public.drop_in_requests;
create policy "drop-in read own or gym owner" on public.drop_in_requests for select to authenticated
  using (auth.uid() = user_id
         or exists (select 1 from public.gyms g where g.id = gym_id and g.owner_user_id = auth.uid()));
drop policy if exists "drop-in gym owner update" on public.drop_in_requests;
create policy "drop-in gym owner update" on public.drop_in_requests for update to authenticated
  using (exists (select 1 from public.gyms g where g.id = gym_id and g.owner_user_id = auth.uid()));
drop policy if exists "drop-in delete own" on public.drop_in_requests;
create policy "drop-in delete own" on public.drop_in_requests for delete to authenticated
  using (auth.uid() = user_id);
grant select, insert, update, delete on public.drop_in_requests to authenticated;

-- ---------- Training log (private) ----------
create table if not exists public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  date date not null,
  duration_minutes int not null check (duration_minutes between 1 and 1440),
  type text not null check (type in ('gi', 'nogi', 'openmat', 'competition')),
  gym_id uuid references public.gyms(id) on delete set null,
  techniques text[] not null default '{}',
  sparring_rounds int not null default 0 check (sparring_rounds between 0 and 100),
  notes text not null default '' check (char_length(notes) <= 4000),
  rating smallint check (rating is null or rating between 1 and 5),
  created_at timestamptz not null default now()
);
create index if not exists training_user_date_idx on public.training_sessions(user_id, date desc);
alter table public.training_sessions enable row level security;
drop policy if exists "training owner only" on public.training_sessions;
create policy "training owner only" on public.training_sessions for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.training_sessions to authenticated;

-- ---------- Gym follows ----------
create table if not exists public.gym_follows (
  user_id uuid references auth.users(id) on delete cascade default auth.uid(),
  gym_id uuid references public.gyms(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, gym_id)
);
create index if not exists gym_follows_gym_idx on public.gym_follows(gym_id);
alter table public.gym_follows enable row level security;
drop policy if exists "gym follows own" on public.gym_follows;
create policy "gym follows own" on public.gym_follows for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, delete on public.gym_follows to authenticated;

-- ---------- Notifications ----------
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'ios',
  environment text not null default 'production' check (environment in ('development', 'production')),
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens(user_id);
alter table public.device_tokens enable row level security;
drop policy if exists "device tokens read own" on public.device_tokens;
create policy "device tokens read own" on public.device_tokens for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists "device tokens delete own" on public.device_tokens;
create policy "device tokens delete own" on public.device_tokens for delete to authenticated
  using (auth.uid() = user_id);
grant select, delete on public.device_tokens to authenticated;

-- Upsert a token for the signed-in user (moves the token if the device changed account).
create or replace function public.register_device(p_token text, p_environment text default 'production')
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  insert into public.device_tokens (token, user_id, environment, updated_at)
  values (p_token, auth.uid(), p_environment, now())
  on conflict (token) do update
    set user_id = auth.uid(), environment = excluded.environment, updated_at = now();
end $$;
revoke all on function public.register_device(text, text) from public, anon;
grant execute on function public.register_device(text, text) to authenticated;

create table if not exists public.notification_prefs (
  user_id uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  new_events boolean not null default true,
  open_mats_followed boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.notification_prefs enable row level security;
drop policy if exists "prefs own" on public.notification_prefs;
create policy "prefs own" on public.notification_prefs for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update on public.notification_prefs to authenticated;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null default '',
  data jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "notifications read own" on public.notifications;
create policy "notifications read own" on public.notifications for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists "notifications mark read own" on public.notifications;
create policy "notifications mark read own" on public.notifications for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, update on public.notifications to authenticated;

create table if not exists public.notifications_outbox (
  id bigint generated always as identity primary key,
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  attempts int not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index if not exists outbox_pending_idx on public.notifications_outbox(status, created_at);
alter table public.notifications_outbox enable row level security;
-- No policies: only the service role (Edge Function) reads/writes the outbox.

-- Enqueue a push for every new notification when the user has a device token.
create or replace function public.enqueue_push()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.device_tokens d where d.user_id = new.user_id) then
    insert into public.notifications_outbox (notification_id, user_id) values (new.id, new.user_id);
  end if;
  return new;
end $$;
drop trigger if exists notifications_enqueue_push on public.notifications;
create trigger notifications_enqueue_push after insert on public.notifications
  for each row execute function public.enqueue_push();

-- New competition -> everyone who wants event notifications.
create or replace function public.notify_new_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, kind, title, body, data)
  select p.id, 'new_event',
         case when p.locale = 'bg' then 'Ново състезание: ' else 'New competition: ' end || new.name,
         coalesce(new.city || ' · ', '') || to_char(new.starts_at, 'DD.MM.YYYY'),
         jsonb_build_object('event_id', new.id::text, 'url', new.url)
  from public.profiles p
  left join public.notification_prefs np on np.user_id = p.id
  where coalesce(np.new_events, true);
  return new;
end $$;
drop trigger if exists events_notify on public.events;
create trigger events_notify after insert on public.events
  for each row execute function public.notify_new_event();

-- New open mat -> followers of that gym (except the poster).
create or replace function public.notify_open_mat()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_gym text;
begin
  select name into v_gym from public.gyms where id = new.gym_id;
  insert into public.notifications (user_id, kind, title, body, data)
  select f.user_id, 'open_mat',
         case when p.locale = 'bg' then 'Свободни борби: ' else 'Open mat: ' end || coalesce(v_gym, ''),
         to_char(new.starts_at at time zone 'Europe/Sofia', 'DD.MM.YYYY HH24:MI'),
         jsonb_build_object('open_mat_id', new.id::text, 'gym_id', new.gym_id::text)
  from public.gym_follows f
  left join public.profiles p on p.id = f.user_id
  left join public.notification_prefs np on np.user_id = f.user_id
  where f.gym_id = new.gym_id
    and f.user_id is distinct from new.posted_by
    and coalesce(np.open_mats_followed, true);
  return new;
end $$;
drop trigger if exists open_mats_notify on public.open_mats;
create trigger open_mats_notify after insert on public.open_mats
  for each row execute function public.notify_open_mat();

-- ---------- Motivational quotes (Feed) ----------
create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  text_en text not null unique,
  text_bg text not null,
  author text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.quotes enable row level security;
drop policy if exists "quotes public read" on public.quotes;
create policy "quotes public read" on public.quotes for select using (active);
grant select on public.quotes to anon, authenticated;

-- Attributed lines are well-known quotes; author null = original, unattributed.
insert into public.quotes (text_en, text_bg, author) values
  ('Always assume that your opponent is going to be bigger, stronger and faster than you.', 'Винаги приемай, че противникът ти ще е по-голям, по-силен и по-бърз от теб.', 'Hélio Gracie'),
  ('Flow with the go.', 'Следвай потока.', 'Rickson Gracie'),
  ('Be water, my friend.', 'Бъди вода, приятелю.', 'Bruce Lee'),
  ('I fear not the man who has practiced 10,000 kicks once, but I fear the man who has practiced one kick 10,000 times.', 'Не се страхувам от човека, който е упражнил 10 000 ритника по веднъж, а от онзи, който е упражнил един ритник 10 000 пъти.', 'Bruce Lee'),
  ('I hated every minute of training, but I said, "Don''t quit. Suffer now and live the rest of your life as a champion."', 'Мразех всяка минута от тренировките, но си казвах: „Не се отказвай. Страдай сега и живей остатъка от живота си като шампион.“', 'Muhammad Ali'),
  ('Maximum efficiency, minimum effort.', 'Максимална ефективност с минимално усилие.', 'Jigoro Kano'),
  ('Everyone has a plan until they get punched in the mouth.', 'Всеки има план, докато не го ударят в устата.', 'Mike Tyson'),
  ('A black belt is a white belt who never quit.', 'Черният колан е бял колан, който никога не се е отказал.', null),
  ('There is no losing in jiu-jitsu. You either win or you learn.', 'В джиу-джицу няма загуба. Или печелиш, или се учиш.', null),
  ('Tap early, tap often, train tomorrow.', 'Предавай се навреме, предавай се често, тренирай и утре.', null),
  ('The mat doesn''t care about your excuses.', 'Татамито не се интересува от извиненията ти.', null),
  ('Position before submission.', 'Първо позиция, после предаване.', null),
  ('Show up. That''s half the technique.', 'Ела на тренировка. Това е половината техника.', null),
  ('Every roll is a conversation. Listen.', 'Всяка борба е разговор. Слушай.', null),
  ('Breathe. Frame. Escape.', 'Дишай. Рамкирай. Излез.', null),
  ('Comfort in bad positions is a superpower.', 'Да си спокоен в лоша позиция е суперсила.', null),
  ('Small progress is still progress.', 'Малкият прогрес пак е прогрес.', null),
  ('Leave your ego at the door, not your effort.', 'Остави егото на вратата, не усилието.', null),
  ('Today''s white belt is tomorrow''s training partner you''ll be proud of.', 'Днешният бял колан е утрешният партньор, с когото ще се гордееш.', null),
  ('Drill it until you can''t get it wrong.', 'Повтаряй, докато не можеш да го сбъркаш.', null),
  ('Your hardest rounds build your easiest days.', 'Най-тежките ти рундове изграждат най-леките ти дни.', null),
  ('The guard is a place to attack, not to rest.', 'Гардът е място за атака, не за почивка.', null),
  ('Patience wins more matches than strength.', 'Търпението печели повече мачове от силата.', null),
  ('Be the partner you want to train with.', 'Бъди партньорът, с когото би искал да тренираш.', null),
  ('Consistency beats intensity.', 'Постоянството побеждава интензивността.', null),
  ('Every expert was once pinned under side control.', 'Всеки експерт някога е бил притиснат в странично задържане.', null),
  ('Lose the round, win the lesson.', 'Загуби рунда, спечели урока.', null),
  ('Technique is how the small win against the strong.', 'Техниката е начинът малкият да победи силния.', null),
  ('Don''t count the stripes. Count the mat hours.', 'Не брой лентите. Брой часовете на татамито.', null),
  ('Calm is a skill. Train it.', 'Спокойствието е умение. Тренирай го.', null),
  ('The submission comes to those who wait in the right position.', 'Предаването идва при онези, които чакат в правилната позиция.', null),
  ('You don''t have to be great to start, but you have to start to be great.', 'Не е нужно да си велик, за да започнеш, но трябва да започнеш, за да станеш велик.', null),
  ('Respect your partner. Without them, there is no training.', 'Уважавай партньора си. Без него няма тренировка.', null),
  ('One more round.', 'Още един рунд.', null),
  ('Defense first. Everything else follows.', 'Първо защитата. Всичко останало идва след това.', null),
  ('A bad day on the mat beats a good day on the couch.', 'Лош ден на татамито е по-добър от добър ден на дивана.', null),
  ('Make the technique work, then make it beautiful.', 'Накарай техниката да работи, после я направи красива.', null),
  ('Bulgaria rolls together.', 'България тренира заедно.', null),
  ('Fall seven times, recover guard eight.', 'Падни седем пъти, възстанови гарда осем.', null),
  ('Rest between rounds, not instead of them.', 'Почивай между рундовете, не вместо тях.', null)
on conflict (text_en) do nothing;

notify pgrst, 'reload schema';
