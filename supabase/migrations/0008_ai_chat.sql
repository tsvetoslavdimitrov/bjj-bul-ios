-- 0008: Ask BJJ AI chat – daily usage limits and conversation history.
-- Idempotent; paste into the SQL Editor. Written by/for the ask-bjj Edge Function (service role).

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null default ((now() at time zone 'Europe/Sofia')::date),
  count int not null default 0 check (count >= 0),
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;
drop policy if exists "ai usage read own" on public.ai_usage;
create policy "ai usage read own" on public.ai_usage for select to authenticated
  using (auth.uid() = user_id);
grant select on public.ai_usage to authenticated;

-- Atomically take one message from today's quota. Returns remaining after this one, or -1 if over the limit.
create or replace function public.ai_try_consume(p_user uuid, p_limit int)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_day date := (now() at time zone 'Europe/Sofia')::date;
  v_count int;
begin
  insert into public.ai_usage (user_id, day, count) values (p_user, v_day, 0)
  on conflict (user_id, day) do nothing;
  update public.ai_usage set count = count + 1
   where user_id = p_user and day = v_day and count < p_limit
  returning count into v_count;
  if v_count is null then return -1; end if;
  return p_limit - v_count;
end $$;

-- Give a message back when the model call failed.
create or replace function public.ai_refund(p_user uuid)
returns void language sql security definer set search_path = public as $$
  update public.ai_usage set count = greatest(count - 1, 0)
   where user_id = p_user and day = (now() at time zone 'Europe/Sofia')::date;
$$;

create or replace function public.ai_used_today(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select count from public.ai_usage
                    where user_id = p_user and day = (now() at time zone 'Europe/Sofia')::date), 0);
$$;

revoke all on function public.ai_try_consume(uuid, int) from public, anon, authenticated;
revoke all on function public.ai_refund(uuid) from public, anon, authenticated;
revoke all on function public.ai_used_today(uuid) from public, anon, authenticated;
grant execute on function public.ai_try_consume(uuid, int) to service_role;
grant execute on function public.ai_refund(uuid) to service_role;
grant execute on function public.ai_used_today(uuid) to service_role;

-- ---------- History (owner-only read/delete; rows written by the Edge Function) ----------
create table if not exists public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '' check (char_length(title) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ai_conversations_user_idx on public.ai_conversations(user_id, updated_at desc);

create table if not exists public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.ai_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) <= 20000),
  created_at timestamptz not null default now()
);
create index if not exists ai_messages_conv_idx on public.ai_messages(conversation_id, created_at);

alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;
drop policy if exists "ai conversations own read" on public.ai_conversations;
create policy "ai conversations own read" on public.ai_conversations for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists "ai conversations own delete" on public.ai_conversations;
create policy "ai conversations own delete" on public.ai_conversations for delete to authenticated
  using (auth.uid() = user_id);
drop policy if exists "ai messages own read" on public.ai_messages;
create policy "ai messages own read" on public.ai_messages for select to authenticated
  using (auth.uid() = user_id);
grant select, delete on public.ai_conversations to authenticated;
grant select on public.ai_messages to authenticated;

notify pgrst, 'reload schema';
