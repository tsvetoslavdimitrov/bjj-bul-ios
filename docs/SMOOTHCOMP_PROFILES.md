# Smoothcomp athlete records

Smoothcomp has no public API (see docs/EVENTS.md). Users paste their own public profile URL
(`https://smoothcomp.com/en/profile/<id>`) in Profile → Edit.

## Sync (`supabase/functions/smoothcomp-sync`)
- Deploy: `supabase functions deploy smoothcomp-sync` (uses the automatic SUPABASE_* secrets).
- The app calls it from the record card ("Sync Smoothcomp"). The function needs the user's JWT and syncs only that user's saved URL.
- Politeness: one GET per call with `User-Agent: BJJBul/1.0 (+https://bjjbul.com; admin@bjjbul.com)`, at most once every 24 h per user
  (`profiles.smoothcomp_synced_at`). robots.txt (checked 11 Oct 2026) disallows only `/order/`, `/checkout`, `/scoreboard`; `/profile` is allowed.
- **Finding (11 Oct 2026):** a request from our server to a public profile got **HTTP 403 with a Cloudflare bot challenge**.
  We don't try to get around this. The function then records `smoothcomp_status = 'blocked'`.
  The parser is generic (it looks for embedded JSON with placement/event or match result fields) and **hasn't been tested on a real page**,
  because we couldn't fetch one. Treat imported data as best-effort and check it before relying on it.
- Fallback (works today): users add medals manually; they're shown with an **Unverified** badge.
- The proper long-term route is a data agreement with Smoothcomp (partner/API access). Ask them before scaling this.
