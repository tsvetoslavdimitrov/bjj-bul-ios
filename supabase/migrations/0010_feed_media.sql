-- 0010: feed media upgrades – videos in post-media, media kind, song links on posts.
-- Idempotent; paste into the SQL Editor.

-- Bucket: allow videos (up to 50 MB per file). Images stay compressed client-side.
update storage.buckets
   set file_size_limit = 52428800,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'video/mp4', 'video/quicktime']
 where id = 'post-media';

alter table public.post_media add column if not exists kind text not null default 'image';
alter table public.post_media drop constraint if exists post_media_kind_check;
alter table public.post_media add constraint post_media_kind_check check (kind in ('image', 'video'));

-- Song link (metadata from oEmbed / Open Graph, fetched by the app). Links only; no audio is stored or mixed.
alter table public.posts add column if not exists music_url text;
alter table public.posts add column if not exists music_title text;
alter table public.posts add column if not exists music_artist text;
alter table public.posts add column if not exists music_artwork text;
alter table public.posts drop constraint if exists posts_music_check;
alter table public.posts add constraint posts_music_check check (
  (music_url is null or (char_length(music_url) <= 500 and music_url ~ '^https://(open\.spotify\.com|spotify\.link|music\.apple\.com|music\.youtube\.com|(www\.)?youtube\.com|youtu\.be|(www\.)?deezer\.com|deezer\.page\.link|link\.deezer\.com)/'))
  and (music_title is null or char_length(music_title) <= 300)
  and (music_artist is null or char_length(music_artist) <= 300)
  and (music_artwork is null or (char_length(music_artwork) <= 1000 and music_artwork ~ '^https://')));

-- Feed RPC recreated with media kinds and music fields appended (older app builds ignore extra columns).
drop function if exists public.get_feed(text, uuid, timestamptz, int);
create function public.get_feed(
  p_scope text default 'all',
  p_author uuid default null,
  p_before timestamptz default null,
  p_limit int default 20
)
returns table (
  id uuid, author_id uuid, author_name text, author_avatar text, author_belt text,
  body text, type text, gym_id uuid, gym_name text, created_at timestamptz,
  media_paths text[], like_count bigint, comment_count bigint, liked_by_me boolean,
  media_kinds text[], music_url text, music_title text, music_artist text, music_artwork text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.author_id, pr.display_name, pr.avatar_url, pr.belt::text,
         p.body, p.type::text, p.gym_id, g.name, p.created_at,
         coalesce((select array_agg(m.storage_path order by m.position)
                   from public.post_media m where m.post_id = p.id), '{}'::text[]),
         (select count(*) from public.likes l where l.post_id = p.id),
         (select count(*) from public.comments c
           where c.post_id = p.id and not public.is_blocked_pair(auth.uid(), c.author_id)),
         exists (select 1 from public.likes l where l.post_id = p.id and l.user_id = auth.uid()),
         coalesce((select array_agg(m.kind order by m.position)
                   from public.post_media m where m.post_id = p.id), '{}'::text[]),
         p.music_url, p.music_title, p.music_artist, p.music_artwork
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
grant execute on function public.get_feed(text, uuid, timestamptz, int) to anon, authenticated;

notify pgrst, 'reload schema';
