# Events (Smoothcomp) — data source and sync

## How the listing loads
`https://smoothcomp.com/en/events/upcoming` is server-rendered. The whole upcoming list is embedded in the HTML as JSON objects. On 2026-10-11 the page held about 1,650 events in a single ~1.2 MB response, with fields `id, title, startdate, enddate, location_country, location_city, location_lat, location_long, url, cover_image, categoryGroups`. The page has a country picker, but there's no documented public JSON API, so we filter `location_country == "BG"` locally from that one response. Venue, divisions and registration details are only on each event's own page; we don't fetch those.

## What's allowed
- **robots.txt:** `User-agent: *` disallows only `/order/`, `/checkout` and `/scoreboard`, and sets `Crawl-delay: 10`. `/en/events/...` isn't disallowed.
- **Terms of Service** (https://smoothcomp.com/en/agreements?t=tos): the full text is rendered by JavaScript and we couldn't read all of it. The parts we could see ban unauthorised access and anything that disrupts the platform or uses too many resources. We didn't find an explicit "no scraping" clause, but we haven't confirmed there isn't one. The SaaS terms for organisers ban copying or republishing the service and moving registrations to other platforms.
- **Our approach:** at most one request per day from a server (never from the phone), with an identifying User-Agent. We store only the basic facts plus a link back, and registration always happens on Smoothcomp. Event cover images belong to the organisers/Smoothcomp; the app loads them from Smoothcomp's URL (it doesn't copy them).
- **Recommended:** email support@smoothcomp.com to ask for permission or partner/API access. If they say no, switch to the CSV import (`--source csv`), which needs no fetching at all.

## Sync
```bash
python3 scripts/sync_events.py                       # dry run: fetch once, print BG events
SUPABASE_PROJECT_URL=https://<ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<secret> \
python3 scripts/sync_events.py --apply               # upsert into public.events
python3 scripts/sync_events.py --source csv data/events_bulgaria.csv --apply   # manual import
```
The service-role key is server-side only. Never put it in the app or commit it. Run the sync at most once a day (cron or a GitHub Actions schedule with repository secrets).
