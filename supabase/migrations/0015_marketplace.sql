-- 0015 Marketplace: partners, products, affiliate clicks, order requests, commissions.
-- Safe to re-run.

create extension if not exists pgcrypto with schema extensions;

-- Partners --------------------------------------------------------------
create table if not exists public.partners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique,
  logo_url text,
  description text,
  website text,
  contact_email text,
  revolut_url text check (revolut_url is null or revolut_url ~ '^https://revolut\.me/[A-Za-z0-9._-]+/?$'),
  commission_pct numeric(5,2) not null default 10 check (commission_pct >= 0 and commission_pct <= 100),
  status text not null default 'pending' check (status in ('pending', 'approved', 'suspended')),
  owner_user_id uuid references auth.users(id) on delete set null,
  -- true for brands added by BJJ Bul before they agreed ("unconfirmed partner" badge)
  seeded boolean not null default false,
  admin_note text,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

create table if not exists public.partner_members (
  partner_id uuid not null references public.partners(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'staff' check (role in ('owner', 'staff')),
  created_at timestamptz not null default now(),
  primary key (partner_id, user_id)
);

create or replace function public.is_partner_member(p_partner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.partner_members m
                  join public.partners p on p.id = m.partner_id
                 where m.partner_id = p_partner and m.user_id = auth.uid() and p.status <> 'suspended');
$$;
grant execute on function public.is_partner_member(uuid) to authenticated;

alter table public.partners enable row level security;
alter table public.partner_members enable row level security;

drop policy if exists "partners public read" on public.partners;
create policy "partners public read" on public.partners for select
  using (status in ('approved', 'pending') or owner_user_id = auth.uid());
-- "Become a partner": a signed-in user applies; always pending, commission default.
drop policy if exists "partners apply" on public.partners;
create policy "partners apply" on public.partners for insert to authenticated
  with check (owner_user_id = auth.uid() and status = 'pending' and seeded = false and commission_pct = 10);
drop policy if exists "partner members read" on public.partner_members;
create policy "partner members read" on public.partner_members for select to authenticated
  using (user_id = auth.uid() or public.is_partner_member(partner_id));

-- Partner members edit their profile (not status / commission).
create or replace function public.update_partner_profile(p_partner uuid, p_name text, p_description text,
  p_website text, p_contact_email text, p_logo_url text, p_revolut_url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_partner_member(p_partner) then raise exception 'not a partner member'; end if;
  update public.partners set name = coalesce(nullif(trim(p_name), ''), name), description = p_description,
         website = p_website, contact_email = p_contact_email, logo_url = p_logo_url,
         revolut_url = nullif(trim(p_revolut_url), '')
   where id = p_partner;
end $$;
grant execute on function public.update_partner_profile(uuid, text, text, text, text, text, text) to authenticated;

-- Admin (SQL editor only): approve / suspend; also lets a real brand take over a seeded listing.
create or replace function public.admin_approve_partner(p_partner uuid, p_owner uuid default null,
  p_commission_pct numeric default null)
returns void language plpgsql security definer set search_path = public as $$
declare p public.partners; v_owner uuid;
begin
  select * into p from public.partners where id = p_partner for update;
  if not found then raise exception 'partner % not found', p_partner; end if;
  v_owner := coalesce(p_owner, p.owner_user_id);
  update public.partners set status = 'approved', approved_at = now(), owner_user_id = v_owner,
         commission_pct = coalesce(p_commission_pct, commission_pct)
   where id = p_partner;
  if v_owner is not null then
    insert into public.partner_members (partner_id, user_id, role) values (p_partner, v_owner, 'owner')
    on conflict (partner_id, user_id) do update set role = 'owner';
  end if;
end $$;

create or replace function public.admin_set_partner_status(p_partner uuid, p_status text, p_note text default null)
returns void language sql security definer set search_path = public as $$
  update public.partners set status = p_status, admin_note = coalesce(p_note, admin_note) where id = p_partner;
$$;

-- Users see the partners they belong to.
create or replace function public.my_partners()
returns table (id uuid, name text, slug text, status text, role text, commission_pct numeric,
               revolut_url text, website text, contact_email text, description text, logo_url text)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.slug, p.status, m.role, p.commission_pct, p.revolut_url, p.website,
         p.contact_email, p.description, p.logo_url
    from public.partner_members m join public.partners p on p.id = m.partner_id
   where m.user_id = auth.uid()
  union all
  select p.id, p.name, p.slug, p.status, 'applicant', p.commission_pct, p.revolut_url, p.website,
         p.contact_email, p.description, p.logo_url
    from public.partners p
   where p.owner_user_id = auth.uid() and p.status = 'pending'
     and not exists (select 1 from public.partner_members m where m.partner_id = p.id and m.user_id = auth.uid());
$$;
grant execute on function public.my_partners() to authenticated;

-- Products --------------------------------------------------------------
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  title_bg text not null,
  title_en text,
  description_bg text,
  description_en text,
  category text not null default 'other'
    check (category in ('gi', 'rashguard', 'shorts', 'belts', 'gear', 'supplements', 'apparel', 'other')),
  price_eur numeric(10,2) not null check (price_eur >= 0),
  compare_at_price numeric(10,2),
  image_urls text[] not null default '{}',
  sizes jsonb not null default '[]'::jsonb,
  variants jsonb not null default '[]'::jsonb,
  stock int,
  external_url text,
  fulfillment text not null default 'order_request' check (fulfillment in ('affiliate_link', 'order_request')),
  active boolean not null default true,
  source_checked_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_affiliate_needs_url check (fulfillment <> 'affiliate_link' or external_url is not null)
);
create index if not exists products_partner_idx on public.products (partner_id);
create index if not exists products_category_idx on public.products (category) where active;

alter table public.products enable row level security;
drop policy if exists "products public read" on public.products;
create policy "products public read" on public.products for select
  using ((active and exists (select 1 from public.partners p where p.id = partner_id and p.status in ('approved', 'pending')))
         or public.is_partner_member(partner_id));
drop policy if exists "products partner insert" on public.products;
create policy "products partner insert" on public.products for insert to authenticated
  with check (public.is_partner_member(partner_id));
drop policy if exists "products partner update" on public.products;
create policy "products partner update" on public.products for update to authenticated
  using (public.is_partner_member(partner_id)) with check (public.is_partner_member(partner_id));
drop policy if exists "products partner delete" on public.products;
create policy "products partner delete" on public.products for delete to authenticated
  using (public.is_partner_member(partner_id));

-- Product images: public read; partner members write "<partner_id>/...".
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-media', 'product-media', true, 5242880, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;
drop policy if exists "product-media public read" on storage.objects;
create policy "product-media public read" on storage.objects for select using (bucket_id = 'product-media');
drop policy if exists "product-media partner upload" on storage.objects;
create policy "product-media partner upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'product-media' and public.is_partner_member(((storage.foldername(name))[1])::uuid));
drop policy if exists "product-media partner delete" on storage.objects;
create policy "product-media partner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'product-media' and public.is_partner_member(((storage.foldername(name))[1])::uuid));

-- Affiliate clicks -----------------------------------------------------
create table if not exists public.affiliate_clicks (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  ref_code text not null,
  created_at timestamptz not null default now()
);
create index if not exists affiliate_clicks_partner_idx on public.affiliate_clicks (partner_id, created_at);
alter table public.affiliate_clicks enable row level security;
drop policy if exists "affiliate clicks partner read" on public.affiliate_clicks;
create policy "affiliate clicks partner read" on public.affiliate_clicks for select to authenticated
  using (public.is_partner_member(partner_id));

-- Logs a click and returns the tracked URL (?ref=bjjbul-<code>&utm_...). Works for anon too.
create or replace function public.track_affiliate_click(p_product uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare pr public.products; v_code text; v_sep text;
begin
  select * into pr from public.products where id = p_product and active;
  if not found or pr.external_url is null then raise exception 'product not available'; end if;
  v_code := substr(encode(gen_random_bytes(6), 'hex'), 1, 10);
  insert into public.affiliate_clicks (product_id, partner_id, user_id, ref_code)
  values (pr.id, pr.partner_id, auth.uid(), v_code);
  v_sep := case when position('?' in pr.external_url) > 0 then '&' else '?' end;
  return pr.external_url || v_sep || 'ref=bjjbul-' || v_code
         || '&utm_source=bjjbul&utm_medium=app&utm_campaign=marketplace';
end $$;
grant execute on function public.track_affiliate_click(uuid) to anon, authenticated;

-- Order requests -------------------------------------------------------
create table if not exists public.marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete restrict,
  items jsonb not null,
  total_eur numeric(10,2) not null,
  commission_pct numeric(5,2) not null,
  commission_amount numeric(10,2) not null,
  status text not null default 'requested'
    check (status in ('requested', 'confirmed', 'paid', 'shipped', 'completed', 'cancelled')),
  payment_method text not null default 'revolut' check (payment_method in ('revolut', 'cash', 'card')),
  shipping_name text not null,
  shipping_phone text not null,
  delivery_type text not null default 'econt_office'
    check (delivery_type in ('econt_office', 'speedy_office', 'address')),
  shipping_address text not null,
  notes text,
  reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists marketplace_orders_partner_idx on public.marketplace_orders (partner_id, created_at desc);
create index if not exists marketplace_orders_buyer_idx on public.marketplace_orders (buyer_id, created_at desc);
alter table public.marketplace_orders enable row level security;
drop policy if exists "orders buyer or partner read" on public.marketplace_orders;
create policy "orders buyer or partner read" on public.marketplace_orders for select to authenticated
  using (buyer_id = auth.uid() or public.is_partner_member(partner_id));
-- Writes only through the RPCs below.

-- Creates an order request; prices come from products, commission is snapshotted.
-- p_items: [{"product_id": "...", "size": "M", "qty": 1}]
create or replace function public.create_marketplace_order(p_partner uuid, p_items jsonb, p_payment_method text,
  p_shipping_name text, p_shipping_phone text, p_delivery_type text, p_shipping_address text, p_notes text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_partner public.partners; v_items jsonb := '[]'::jsonb; v_total numeric := 0; it jsonb;
        pr public.products; v_qty int; v_id uuid;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  select * into v_partner from public.partners where id = p_partner and status in ('approved', 'pending');
  if not found then raise exception 'partner not available'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'empty cart'; end if;
  if coalesce(trim(p_shipping_name), '') = '' or coalesce(trim(p_shipping_phone), '') = ''
     or coalesce(trim(p_shipping_address), '') = '' then raise exception 'shipping details required'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into pr from public.products
     where id = (it->>'product_id')::uuid and partner_id = p_partner and active and fulfillment = 'order_request';
    if not found then raise exception 'product not available'; end if;
    v_qty := greatest(1, least(coalesce((it->>'qty')::int, 1), 20));
    if pr.stock is not null and pr.stock < v_qty then raise exception 'out of stock: %', pr.title_bg; end if;
    v_total := v_total + pr.price_eur * v_qty;
    v_items := v_items || jsonb_build_object('product_id', pr.id, 'title', coalesce(pr.title_en, pr.title_bg),
               'title_bg', pr.title_bg, 'size', it->>'size', 'qty', v_qty, 'price_eur', pr.price_eur);
  end loop;
  insert into public.marketplace_orders (buyer_id, partner_id, items, total_eur, commission_pct, commission_amount,
         payment_method, shipping_name, shipping_phone, delivery_type, shipping_address, notes)
  values (auth.uid(), p_partner, v_items, v_total, v_partner.commission_pct,
          round(v_total * v_partner.commission_pct / 100, 2), p_payment_method, trim(p_shipping_name),
          trim(p_shipping_phone), p_delivery_type, trim(p_shipping_address), p_notes)
  returning id into v_id;
  update public.marketplace_orders
     set reference = 'BJJ-' || upper(substr(replace(v_id::text, '-', ''), 1, 8)) where id = v_id;
  return v_id;
end $$;
grant execute on function public.create_marketplace_order(uuid, jsonb, text, text, text, text, text, text) to authenticated;

-- Partner moves the status forward; the buyer may cancel while still 'requested'.
create or replace function public.set_marketplace_order_status(p_order uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare o public.marketplace_orders; it jsonb;
begin
  select * into o from public.marketplace_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if public.is_partner_member(o.partner_id) then
    if p_status not in ('requested', 'confirmed', 'paid', 'shipped', 'completed', 'cancelled') then
      raise exception 'bad status';
    end if;
  elsif o.buyer_id = auth.uid() then
    if not (p_status = 'cancelled' and o.status = 'requested') then raise exception 'buyers can only cancel requested orders'; end if;
  else
    raise exception 'not allowed';
  end if;
  -- decrement stock once, when the partner confirms
  if p_status = 'confirmed' and o.status = 'requested' then
    for it in select * from jsonb_array_elements(o.items) loop
      update public.products set stock = greatest(0, stock - (it->>'qty')::int)
       where id = (it->>'product_id')::uuid and stock is not null;
    end loop;
  end if;
  update public.marketplace_orders set status = p_status, updated_at = now() where id = p_order;
end $$;
grant execute on function public.set_marketplace_order_status(uuid, text) to authenticated;

-- Commissions ----------------------------------------------------------
create table if not exists public.commission_payouts (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  month date not null,
  amount_eur numeric(10,2) not null,
  method text,
  note text,
  paid_at timestamptz not null default now()
);
alter table public.commission_payouts enable row level security;
drop policy if exists "payouts partner read" on public.commission_payouts;
create policy "payouts partner read" on public.commission_payouts for select to authenticated
  using (public.is_partner_member(partner_id));

-- Per partner per month (Europe/Sofia). Sales count once paid/shipped/completed.
create or replace view public.partner_commission_ledger as
with sales as (
  select partner_id, date_trunc('month', created_at at time zone 'Europe/Sofia')::date as month,
         count(*) as orders, sum(total_eur) as sales_eur, sum(commission_amount) as commission_eur
    from public.marketplace_orders
   where status in ('paid', 'shipped', 'completed')
   group by 1, 2
), paid as (
  select partner_id, date_trunc('month', month)::date as month, sum(amount_eur) as paid_eur
    from public.commission_payouts group by 1, 2
)
select coalesce(s.partner_id, p.partner_id) as partner_id, coalesce(s.month, p.month) as month,
       coalesce(s.orders, 0) as orders, coalesce(s.sales_eur, 0) as sales_eur,
       coalesce(s.commission_eur, 0) as commission_eur, coalesce(p.paid_eur, 0) as paid_eur,
       coalesce(s.commission_eur, 0) - coalesce(p.paid_eur, 0) as owed_eur
  from sales s full join paid p on p.partner_id = s.partner_id and p.month = s.month;
revoke all on public.partner_commission_ledger from anon, authenticated;

create or replace function public.partner_ledger(p_partner uuid)
returns table (month date, orders bigint, sales_eur numeric, commission_eur numeric, paid_eur numeric, owed_eur numeric,
               clicks bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_partner_member(p_partner) then raise exception 'not a partner member'; end if;
  return query
  with c as (
    select date_trunc('month', created_at at time zone 'Europe/Sofia')::date as month, count(*) as clicks
      from public.affiliate_clicks where partner_id = p_partner group by 1
  )
  select coalesce(l.month, c.month), coalesce(l.orders, 0), coalesce(l.sales_eur, 0), coalesce(l.commission_eur, 0),
         coalesce(l.paid_eur, 0), coalesce(l.owed_eur, 0), coalesce(c.clicks, 0)
    from (select * from public.partner_commission_ledger where partner_id = p_partner) l
    full join c on c.month = l.month
   order by 1 desc;
end $$;
grant execute on function public.partner_ledger(uuid) to authenticated;

create or replace function public.admin_record_commission_payout(p_partner uuid, p_month date, p_amount numeric,
  p_method text default 'revolut', p_note text default null)
returns uuid language sql security definer set search_path = public as $$
  insert into public.commission_payouts (partner_id, month, amount_eur, method, note)
  values (p_partner, date_trunc('month', p_month)::date, p_amount, p_method, p_note)
  returning id;
$$;

revoke all on function public.admin_approve_partner(uuid, uuid, numeric) from public, anon, authenticated;
revoke all on function public.admin_set_partner_status(uuid, text, text) from public, anon, authenticated;
revoke all on function public.admin_record_commission_payout(uuid, date, numeric, text, text) from public, anon, authenticated;

-- Seed: real brands, status 'pending' (shown as "unconfirmed partner") until they agree.
-- Products verified on the official shops on 2026-10-11; affiliate links only; image URLs are
-- the shops' own product image URLs (not copied). See data/marketplace_seed.csv.
insert into public.partners (id, name, slug, website, description, status, seeded)
values ('33ba6dca-d304-520a-9f9d-91ad2c8cf936', 'Art of Flow', 'art-of-flow', 'https://artofflow.eu', 'Rashguards, grappling shorts and apparel.', 'pending', true)
on conflict (id) do update set name = excluded.name, website = excluded.website, description = excluded.description
  where public.partners.seeded;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('67f1ddc9-ad9d-55bb-991c-3d4ce1d8c81a', '33ba6dca-d304-520a-9f9d-91ad2c8cf936', 'Ranked Black', 'Ranked Black', 'rashguard', 35.00, 45.00, array['https://artofflow.eu/wp-content/uploads/2026/02/EL103726-scaled.jpg'], 'https://artofflow.eu/product/ranked-black/', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('e327640f-9c71-546e-ab1f-31d2f819fafc', '33ba6dca-d304-520a-9f9d-91ad2c8cf936', 'Mamba', 'Mamba', 'rashguard', 35.00, 45.00, array['https://artofflow.eu/wp-content/uploads/2025/11/EL100280.jpg'], 'https://artofflow.eu/product/mamba/', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('4cfb0d6e-69df-5d06-a448-502807790d4e', '33ba6dca-d304-520a-9f9d-91ad2c8cf936', 'Wave 1', 'Wave 1', 'rashguard', 35.00, 45.00, array['https://artofflow.eu/wp-content/uploads/2025/11/EL108506.jpg'], 'https://artofflow.eu/product/wave-1-2/', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('a7901fa5-84ef-5ba6-b72a-aa965681b7fb', '33ba6dca-d304-520a-9f9d-91ad2c8cf936', 'Grappling Shorts', 'Grappling Shorts', 'shorts', 35.00, 45.00, array['https://artofflow.eu/wp-content/uploads/2025/11/EL100380.jpg'], 'https://artofflow.eu/product/grappling-shorts/', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('17193985-ddd5-568b-80b3-d7c1d111bde7', '33ba6dca-d304-520a-9f9d-91ad2c8cf936', 'Fluffy SP26 Black', 'Fluffy SP26 Black', 'apparel', 36.00, 45.00, array['https://artofflow.eu/wp-content/uploads/2026/03/Image-6-5.jpeg'], 'https://artofflow.eu/product/fluffy-sp26-black/', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('592b6441-5bd0-5687-a487-b8569feecf0d', '33ba6dca-d304-520a-9f9d-91ad2c8cf936', 'Performance Tee Black', 'Performance Tee Black', 'apparel', 25.00, null, array['https://artofflow.eu/wp-content/uploads/2026/08/ELB06457-scaled.jpg'], 'https://artofflow.eu/product/performance-tee-black/', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.partners (id, name, slug, website, description, status, seeded)
values ('a16706ac-103c-5266-ac28-00c0d482a849', 'Mata Leão', 'mata-leao', 'https://mataleao.shop', 'Jiu-jitsu gear designed and made in Bulgaria.', 'pending', true)
on conflict (id) do update set name = excluded.name, website = excluded.website, description = excluded.description
  where public.partners.seeded;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('afbafa95-f914-588f-ba07-f607bf08587c', 'a16706ac-103c-5266-ac28-00c0d482a849', 'Choke Club Rashguard', 'Choke Club Rashguard', 'rashguard', 57.00, null, array['https://mataleao.shop/image/cache/catalog/Mataleao/CHOKECLUB_FRONT-1-600x315w.png'], 'https://mataleao.shop/en/choke-club-rashguard-en', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('31a2fe06-939d-5035-8b32-404b12675c71', 'a16706ac-103c-5266-ac28-00c0d482a849', 'Bandido Rashguard', 'Bandido Rashguard', 'rashguard', 57.00, null, array['https://mataleao.shop/image/cache/catalog/Mataleao/BANDIDO1-600x315w.png'], 'https://mataleao.shop/en/bandido-rashguard-en', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('b94fcd32-e53c-5e97-9417-795d6856c1e3', 'a16706ac-103c-5266-ac28-00c0d482a849', 'Essentials Black Rashguard', 'Essentials Black Rashguard', 'rashguard', 40.00, null, array['https://mataleao.shop/image/cache/catalog/Mataleao/ESSENTIALSBLACK-600x315w.png'], 'https://mataleao.shop/en/essentials-black-rashguard-en', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('46ae8940-9047-5459-bbd8-6cd3c2d1c06b', 'a16706ac-103c-5266-ac28-00c0d482a849', 'Arte Suave Black Rashguard', 'Arte Suave Black Rashguard', 'rashguard', 40.00, null, array['https://mataleao.shop/image/cache/catalog/Mataleao/BLACK-600x315w.png'], 'https://mataleao.shop/en/arte-sueve-black-rashguard-en', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.partners (id, name, slug, website, description, status, seeded)
values ('75f3cb07-391e-5d4b-a5d6-16b7732794d5', 'RUSH (RushguardBJJ)', 'rushguard', 'https://rushguardbjj.com', 'Bulgarian BJJ & MMA rashguards and shorts.', 'pending', true)
on conflict (id) do update set name = excluded.name, website = excluded.website, description = excluded.description
  where public.partners.seeded;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('47c05679-628a-548d-a6d9-96bc19989fc0', '75f3cb07-391e-5d4b-a5d6-16b7732794d5', 'Rushguard Submission - Red', 'Rushguard Submission - Red', 'rashguard', 50.00, null, array['https://cdn.shopify.com/s/files/1/0821/2113/0332/files/Submission_red_Rash_front.png'], 'https://rushguardbjj.com/en/products/submission-rashguard-red', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('dbb46451-649f-5250-983a-1923e14883cc', '75f3cb07-391e-5d4b-a5d6-16b7732794d5', 'RUSH Shorts Submission - Red', 'RUSH Shorts Submission - Red', 'shorts', 50.00, null, array['https://cdn.shopify.com/s/files/1/0821/2113/0332/files/Untitled_Project_-_Artboard_5.png'], 'https://rushguardbjj.com/en/products/submission-shorts-red', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('214dc491-9d6a-500a-a558-360c5ef35369', '75f3cb07-391e-5d4b-a5d6-16b7732794d5', 'Rushguard Submission - Red - Women''s', 'Rushguard Submission - Red - Women''s', 'rashguard', 50.00, null, array['https://cdn.shopify.com/s/files/1/0821/2113/0332/files/Submission_red_womans_front.png'], 'https://rushguardbjj.com/en/products/submission-rashguard-red-womens', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('8da243f0-5895-5450-b1ab-bcc7de9be150', '75f3cb07-391e-5d4b-a5d6-16b7732794d5', 'Rushguard Traditional - Purple', 'Rushguard Traditional - Purple', 'rashguard', 34.00, null, array['https://cdn.shopify.com/s/files/1/0821/2113/0332/files/17.09Rush05737.jpg'], 'https://rushguardbjj.com/en/products/traditional-rashguard-purple', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;
insert into public.products (id, partner_id, title_bg, title_en, category, price_eur, compare_at_price, image_urls, external_url, fulfillment, source_checked_at)
values ('a9b45dce-e1a0-5ad2-8340-fc2739b87da2', '75f3cb07-391e-5d4b-a5d6-16b7732794d5', 'Rushguard 01 - Ice Blue', 'Rushguard 01 - Ice Blue', 'rashguard', 34.00, null, array['https://cdn.shopify.com/s/files/1/0821/2113/0332/files/17.09Rush05721.jpg'], 'https://rushguardbjj.com/en/products/volume-01-rashguard-ice-blue', 'affiliate_link', '2026-10-11')
on conflict (id) do update set price_eur = excluded.price_eur, compare_at_price = excluded.compare_at_price,
  external_url = excluded.external_url, image_urls = excluded.image_urls, source_checked_at = excluded.source_checked_at;

notify pgrst, 'reload schema';
