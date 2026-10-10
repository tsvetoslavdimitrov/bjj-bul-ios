-- BJJ Bul: initial schema
create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- Enums
create type belt as enum ('white','blue','purple','brown','black','coral','red');
create type class_type as enum ('gi','nogi','kids','fundamentals','competition','openmat','women');
create type class_level as enum ('all','beginner','advanced');
create type coach_role as enum ('head','instructor','assistant');
create type claim_status as enum ('none','pending','approved');
create type review_status as enum ('needs_review','verified','rejected');

-- updated_at helper
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- Cities
create table cities (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name_bg text not null,
  name_en text not null,
  oblast text,
  location geography(Point, 4326)
);

-- Gyms
create table gyms (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  name_latin text,
  city_id uuid not null references cities(id) on delete restrict,
  address text,
  location geography(Point, 4326),          -- null until verified coordinates exist
  affiliation text,
  phone text,
  email text,
  website text,
  instagram text,
  facebook text,
  photo_urls text[] not null default '{}',
  price_drop_in numeric(10,2),
  price_monthly numeric(10,2),
  price_kids numeric(10,2),
  currency text not null default 'EUR',
  has_kids boolean,
  has_women_only boolean,
  verified boolean not null default false,
  review_status review_status not null default 'needs_review',
  source_url text not null,
  notes text,
  last_verified_at timestamptz,
  owner_user_id uuid references auth.users(id) on delete set null,   -- Phase 2
  claim_status claim_status not null default 'none',                 -- Phase 2
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index gyms_city_idx on gyms(city_id);
create index gyms_location_idx on gyms using gist(location);
create index gyms_name_idx on gyms(lower(name));
create trigger gyms_updated before update on gyms for each row execute function set_updated_at();

-- Coaches
create table coaches (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  full_name_latin text,
  photo_url text,
  belt belt,
  degree smallint check (degree between 0 and 10),
  promoted_by_coach_id uuid references coaches(id) on delete set null,
  lineage_text text,
  achievements jsonb not null default '[]',
  instagram text,
  user_id uuid references auth.users(id) on delete set null,          -- Phase 2
  source_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger coaches_updated before update on coaches for each row execute function set_updated_at();

create table gym_coaches (
  gym_id uuid references gyms(id) on delete cascade,
  coach_id uuid references coaches(id) on delete cascade,
  role coach_role not null default 'instructor',
  primary key (gym_id, coach_id)
);
create index gym_coaches_coach_idx on gym_coaches(coach_id);

-- Schedules
create table class_schedules (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references gyms(id) on delete cascade,
  coach_id uuid references coaches(id) on delete set null,
  weekday smallint not null check (weekday between 1 and 7),   -- 1 = Monday
  start_time time not null,
  end_time time not null,
  type class_type not null,
  level class_level not null default 'all',
  notes text,
  check (end_time > start_time)
);
create index class_schedules_gym_idx on class_schedules(gym_id, weekday);

-- Profiles
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  belt belt not null default 'white',
  stripes smallint not null default 0 check (stripes between 0 and 4),
  home_gym_id uuid references gyms(id) on delete set null,
  training_since date,
  locale text not null default 'bg',
  is_public boolean not null default false,       -- Phase 2
  smoothcomp_profile_url text,                    -- Phase 3
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profiles_updated before update on profiles for each row execute function set_updated_at();

create table favorite_gyms (
  user_id uuid references auth.users(id) on delete cascade,
  gym_id uuid references gyms(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, gym_id)
);

-- Auto-create profile on signup
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Suggestions
create table suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null default auth.uid(),
  entity_type text not null check (entity_type in ('gym','coach','schedule','new_gym')),
  entity_id uuid,
  payload jsonb not null,
  status review_status not null default 'needs_review',
  created_at timestamptz not null default now()
);

-- Gyms near me (meters)
create or replace function gyms_near(lat double precision, lng double precision, radius_m double precision default 50000)
returns table (id uuid, name text, city_id uuid, address text, lat double precision, lng double precision, distance_m double precision)
language sql stable as $$
  select g.id, g.name, g.city_id, g.address,
         st_y(g.location::geometry), st_x(g.location::geometry),
         st_distance(g.location, st_makepoint(lng, lat)::geography)
  from gyms g
  where g.location is not null
    and st_dwithin(g.location, st_makepoint(lng, lat)::geography, radius_m)
  order by 7;
$$;

-- RLS
alter table cities enable row level security;
alter table gyms enable row level security;
alter table coaches enable row level security;
alter table gym_coaches enable row level security;
alter table class_schedules enable row level security;
alter table profiles enable row level security;
alter table favorite_gyms enable row level security;
alter table suggestions enable row level security;

create policy "public read" on cities for select using (true);
create policy "public read" on gyms for select using (true);
create policy "public read" on coaches for select using (true);
create policy "public read" on gym_coaches for select using (true);
create policy "public read" on class_schedules for select using (true);

create policy "read own or public profile" on profiles for select using (auth.uid() = id or is_public);
create policy "update own profile" on profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "insert own profile" on profiles for insert with check (auth.uid() = id);

create policy "own favorites" on favorite_gyms for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "users insert suggestions" on suggestions for insert to authenticated with check (auth.uid() = user_id);
create policy "users read own suggestions" on suggestions for select using (auth.uid() = user_id);
-- Writes to directory tables happen via service_role (bypasses RLS) / dashboard.
