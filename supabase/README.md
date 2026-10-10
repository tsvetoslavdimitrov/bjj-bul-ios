# Supabase

- `migrations/0001_init.sql`: schema (PostGIS, tables, indexes, RLS, `gyms_near(lat, lng, radius_m)`)
- `seed.sql`: cities plus gyms researched from public sources. All gyms are `verified=false` / `needs_review`, and each has a `source_url`.
- `../data/gyms_bulgaria.csv`: the same gym list as CSV.

## Apply with the Supabase CLI
```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref <your-project-ref>
supabase db push                      # runs migrations
psql "$(supabase db url)" -f supabase/seed.sql   # or: supabase db reset (local, runs seed.sql automatically)
```
Local dev: `supabase start && supabase db reset`.

## Apply with the SQL editor
In Dashboard → SQL Editor, paste and run `migrations/0001_init.sql`, then `seed.sql`.

## Notes
- Gym coordinates are mostly null. Only add them after checking each gym (e.g. Apple Maps), then set `verified=true`, `review_status='verified'`, `last_verified_at=now()`.
- Directory tables are read-only for clients. Admin writes use the service role or the dashboard.
- Example query: `select * from gyms_near(42.6977, 23.3219, 10000);`
