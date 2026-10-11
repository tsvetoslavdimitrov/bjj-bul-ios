-- 0006: upcoming competitions (Phase 3). Idempotent.
-- Source: Smoothcomp public upcoming-events listing (https://smoothcomp.com/en/events/upcoming).
-- Facts + link back only; registration happens on Smoothcomp.

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  smoothcomp_id bigint unique not null,
  name text not null,
  starts_at date not null,
  ends_at date,
  city text,
  country text not null default 'BG',
  venue text,
  latitude double precision,
  longitude double precision,
  url text not null,
  image_url text,
  registration_url text,
  registration_deadline date,
  registration_info text,
  category_groups text,
  source text not null default 'smoothcomp',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists events_starts_idx on public.events(starts_at);

drop trigger if exists events_updated on public.events;
create trigger events_updated before update on public.events
  for each row execute function set_updated_at();

alter table public.events enable row level security;
drop policy if exists "events public read" on public.events;
create policy "events public read" on public.events for select using (true);
-- Writes only via service role (sync script) or dashboard.
grant select on public.events to anon, authenticated;

-- Seed: Bulgarian events listed on Smoothcomp as of 2026-10-11.
insert into public.events (smoothcomp_id, name, starts_at, ends_at, city, country, latitude, longitude, url, image_url, registration_url, category_groups)
values
  (33584, 'ADCC Sofia Winter Open 2026', '2026-10-25', '2026-10-25', 'Sofia', 'BG', 42.6662831, 23.3240722, 'https://smoothcomp.com/en/event/33584', 'https://smoothcomp.com/pictures/t/9300768-udvi/adcc-sofia-winter-open-2026.jpg', 'https://smoothcomp.com/en/event/33584', '4'),
  (33192, 'FUJI European Open 2026', '2026-11-14', '2026-11-14', 'Sofia', 'BG', 42.6977082, 23.3218675, 'https://fujibjj.smoothcomp.com/en/event/33192', 'https://smoothcomp.com/pictures/t/9089119-ljn8/fuji-european-open-2026.jpg', 'https://fujibjj.smoothcomp.com/en/event/33192', '1,7'),
  (34839, 'TFR VI- Time for rolling VI', '2026-11-21', '2026-11-21', 'Стара Загора', 'BG', 42.4277477, 25.6576647, 'https://smoothcomp.com/en/event/34839', 'https://smoothcomp.com/pictures/t/9567962-2h9h/tfr-vi-time-for-rolling-vi-2026.jpg', 'https://smoothcomp.com/en/event/34839', '7'),
  (32871, 'Grappling Industries SOFIA', '2026-12-19', '2026-12-19', 'Sofia', 'BG', 42.6663411, 23.3237631, 'https://grapplingindustries.smoothcomp.com/en/event/32871', 'https://smoothcomp.com/pictures/t/8948373-oc0b/grappling-industries-sofia-2026.jpg', 'https://grapplingindustries.smoothcomp.com/en/event/32871', '1,7,3')
on conflict (smoothcomp_id) do update set
  name = excluded.name, starts_at = excluded.starts_at, ends_at = excluded.ends_at,
  city = excluded.city, latitude = excluded.latitude, longitude = excluded.longitude,
  url = excluded.url, image_url = excluded.image_url, registration_url = excluded.registration_url,
  category_groups = excluded.category_groups, updated_at = now();

notify pgrst, 'reload schema';
