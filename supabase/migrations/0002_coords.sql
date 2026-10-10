-- 0002: gym coordinates (OSM Nominatim, (c) OpenStreetMap contributors, ODbL) + gyms_with_coords view. Idempotent.

update gyms set location = st_setsrid(st_makepoint(23.2545085, 42.6691113), 4326)::geography where slug = 'bagir-bjj-sofia';  -- Nominatim building бул. Никола Петков 52
update gyms set location = st_setsrid(st_makepoint(23.3179386, 42.6619185), 4326)::geography where slug = 'twisted-jiu-jitsu-sofia';  -- Nominatim building бул. Черни връх 47 (Бизнес център Витоша)
update gyms set location = st_setsrid(st_makepoint(23.3410148, 42.6532646), 4326)::geography where slug = '23-fight-academy-sofia';  -- Nominatim building ул. Д-р Йордан Йосифов 11
update gyms set location = st_setsrid(st_makepoint(23.3148513, 42.7363544), 4326)::geography where slug = 'pitbulls-grappling-sofia';  -- Nominatim building бул. Рожен 23

create or replace view public.gyms_with_coords with (security_invoker = true) as
select g.*,
       case when g.location is null then null else st_y(g.location::geometry) end as lat,
       case when g.location is null then null else st_x(g.location::geometry) end as lng
from public.gyms g;

grant select on public.gyms_with_coords to anon, authenticated;
