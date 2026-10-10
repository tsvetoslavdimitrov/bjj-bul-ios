-- 0004: Phase 2 social feed. Idempotent; safe to re-run in the SQL Editor.

-- Types
do $$ begin
  create type post_type as enum ('progress','promotion','competition','training');
exception when duplicate_object then null; end $$;

-- Tables
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  body text not null default '' check (char_length(body) <= 2000),
  type post_type not null default 'progress',
  gym_id uuid references public.gyms(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists posts_created_idx on public.posts(created_at desc);
create index if not exists posts_author_idx on public.posts(author_id, created_at desc);

create table if not exists public.post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  storage_path text not null,
  position smallint not null default 0 check (position between 0 and 3),
  created_at timestamptz not null default now()
);
create index if not exists post_media_post_idx on public.post_media(post_id, position);

create table if not exists public.likes (
  post_id uuid references public.posts(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists likes_user_idx on public.likes(user_id);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments(post_id, created_at);

create table if not exists public.follows (
  follower_id uuid references auth.users(id) on delete cascade default auth.uid(),
  followee_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists follows_followee_idx on public.follows(followee_id);

create table if not exists public.blocks (
  blocker_id uuid references auth.users(id) on delete cascade default auth.uid(),
  blocked_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists blocks_blocked_idx on public.blocks(blocked_id);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users(id) on delete set null default auth.uid(),
  post_id uuid references public.posts(id) on delete set null,
  comment_id uuid references public.comments(id) on delete set null,
  reported_user_id uuid references auth.users(id) on delete set null,
  reason text not null check (char_length(reason) <= 500),
  status review_status not null default 'needs_review',
  created_at timestamptz not null default now(),
  check (post_id is not null or comment_id is not null or reported_user_id is not null)
);

-- Helpers
create or replace function public.is_blocked_pair(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select a is not null and b is not null and exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

-- Feed: newest first, keyset pagination by created_at. Blocked users are excluded both ways.
create or replace function public.get_feed(
  p_scope text default 'all',
  p_author uuid default null,
  p_before timestamptz default null,
  p_limit int default 20
)
returns table (
  id uuid, author_id uuid, author_name text, author_avatar text, author_belt text,
  body text, type text, gym_id uuid, gym_name text, created_at timestamptz,
  media_paths text[], like_count bigint, comment_count bigint, liked_by_me boolean
)
language sql stable security definer set search_path = public as $$
  select p.id, p.author_id, pr.display_name, pr.avatar_url, pr.belt::text,
         p.body, p.type::text, p.gym_id, g.name, p.created_at,
         coalesce((select array_agg(m.storage_path order by m.position)
                   from public.post_media m where m.post_id = p.id), '{}'::text[]),
         (select count(*) from public.likes l where l.post_id = p.id),
         (select count(*) from public.comments c
           where c.post_id = p.id and not public.is_blocked_pair(auth.uid(), c.author_id)),
         exists (select 1 from public.likes l where l.post_id = p.id and l.user_id = auth.uid())
  from public.posts p
  left join public.profiles pr on pr.id = p.author_id
  left join public.gyms g on g.id = p.gym_id
  where (p_author is null or p.author_id = p_author)
    and (p_before is null or p.created_at < p_before)
    and not public.is_blocked_pair(auth.uid(), p.author_id)
    and (p_scope <> 'following'
         or p.author_id = auth.uid()
         or exists (select 1 from public.follows f
                    where f.follower_id = auth.uid() and f.followee_id = p.author_id))
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function public.get_comments(p_post uuid)
returns table (id uuid, post_id uuid, author_id uuid, author_name text, author_avatar text, body text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.post_id, c.author_id, pr.display_name, pr.avatar_url, c.body, c.created_at
  from public.comments c
  left join public.profiles pr on pr.id = c.author_id
  where c.post_id = p_post
    and not public.is_blocked_pair(auth.uid(), c.author_id)
  order by c.created_at asc
  limit 500;
$$;

-- Public profile card (only non-sensitive fields).
create or replace function public.get_public_profile(p_user uuid)
returns table (
  id uuid, display_name text, avatar_url text, belt text, stripes smallint, home_gym_id uuid,
  follower_count bigint, following_count bigint, post_count bigint,
  followed_by_me boolean, blocked boolean
)
language sql stable security definer set search_path = public as $$
  select pr.id, pr.display_name, pr.avatar_url, pr.belt::text, pr.stripes, pr.home_gym_id,
         (select count(*) from public.follows f where f.followee_id = pr.id),
         (select count(*) from public.follows f where f.follower_id = pr.id),
         (select count(*) from public.posts p where p.author_id = pr.id),
         exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = pr.id),
         public.is_blocked_pair(auth.uid(), pr.id)
  from public.profiles pr
  where pr.id = p_user;
$$;

-- RLS
alter table public.posts enable row level security;
alter table public.post_media enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

drop policy if exists "posts read unblocked" on public.posts;
create policy "posts read unblocked" on public.posts for select
  using (not public.is_blocked_pair(auth.uid(), author_id));
drop policy if exists "posts insert own" on public.posts;
create policy "posts insert own" on public.posts for insert to authenticated
  with check (auth.uid() = author_id);
drop policy if exists "posts update own" on public.posts;
create policy "posts update own" on public.posts for update to authenticated
  using (auth.uid() = author_id) with check (auth.uid() = author_id);
drop policy if exists "posts delete own" on public.posts;
create policy "posts delete own" on public.posts for delete to authenticated
  using (auth.uid() = author_id);

drop policy if exists "media read" on public.post_media;
create policy "media read" on public.post_media for select
  using (exists (select 1 from public.posts p where p.id = post_id
                 and not public.is_blocked_pair(auth.uid(), p.author_id)));
drop policy if exists "media insert own post" on public.post_media;
create policy "media insert own post" on public.post_media for insert to authenticated
  with check (exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid()));
drop policy if exists "media delete own post" on public.post_media;
create policy "media delete own post" on public.post_media for delete to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid()));

drop policy if exists "likes read" on public.likes;
create policy "likes read" on public.likes for select using (true);
drop policy if exists "likes insert own" on public.likes;
create policy "likes insert own" on public.likes for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "likes delete own" on public.likes;
create policy "likes delete own" on public.likes for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "comments read unblocked" on public.comments;
create policy "comments read unblocked" on public.comments for select
  using (not public.is_blocked_pair(auth.uid(), author_id));
drop policy if exists "comments insert own" on public.comments;
create policy "comments insert own" on public.comments for insert to authenticated
  with check (auth.uid() = author_id
              and exists (select 1 from public.posts p where p.id = post_id
                          and not public.is_blocked_pair(auth.uid(), p.author_id)));
drop policy if exists "comments delete own" on public.comments;
create policy "comments delete own" on public.comments for delete to authenticated
  using (auth.uid() = author_id);

drop policy if exists "follows read" on public.follows;
create policy "follows read" on public.follows for select using (true);
drop policy if exists "follows insert own" on public.follows;
create policy "follows insert own" on public.follows for insert to authenticated
  with check (auth.uid() = follower_id and not public.is_blocked_pair(follower_id, followee_id));
drop policy if exists "follows delete own" on public.follows;
create policy "follows delete own" on public.follows for delete to authenticated
  using (auth.uid() = follower_id);

drop policy if exists "blocks read own" on public.blocks;
create policy "blocks read own" on public.blocks for select to authenticated
  using (auth.uid() = blocker_id);
drop policy if exists "blocks insert own" on public.blocks;
create policy "blocks insert own" on public.blocks for insert to authenticated
  with check (auth.uid() = blocker_id);
drop policy if exists "blocks delete own" on public.blocks;
create policy "blocks delete own" on public.blocks for delete to authenticated
  using (auth.uid() = blocker_id);

drop policy if exists "reports insert signed in" on public.reports;
create policy "reports insert signed in" on public.reports for insert to authenticated
  with check (auth.uid() = reporter_id);
-- No select policy: reports are only visible to admins (service role / dashboard).

-- Grants
grant select on public.posts, public.post_media, public.likes, public.comments, public.follows to anon, authenticated;
grant insert, update, delete on public.posts to authenticated;
grant insert, delete on public.post_media, public.likes, public.comments, public.follows, public.blocks to authenticated;
grant select on public.blocks to authenticated;
grant insert on public.reports to authenticated;
grant execute on function public.get_feed(text, uuid, timestamptz, int) to anon, authenticated;
grant execute on function public.get_comments(uuid) to anon, authenticated;
grant execute on function public.get_public_profile(uuid) to anon, authenticated;
grant execute on function public.is_blocked_pair(uuid, uuid) to anon, authenticated;

-- Storage bucket for post photos: public read, uploads only into "<auth.uid()>/..." folders.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-media', 'post-media', true, 5242880, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

drop policy if exists "post-media public read" on storage.objects;
create policy "post-media public read" on storage.objects for select
  using (bucket_id = 'post-media');
drop policy if exists "post-media upload own folder" on storage.objects;
create policy "post-media upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'post-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "post-media delete own folder" on storage.objects;
create policy "post-media delete own folder" on storage.objects for delete to authenticated
  using (bucket_id = 'post-media' and (storage.foldername(name))[1] = auth.uid()::text);

notify pgrst, 'reload schema';
