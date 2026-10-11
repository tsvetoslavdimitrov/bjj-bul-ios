#!/usr/bin/env python3
"""Sync upcoming Bulgarian BJJ/grappling events into the Supabase `events` table.

Two sources:
  --source smoothcomp   One polite GET of https://smoothcomp.com/en/events/upcoming
                        (robots.txt allows /en/events with Crawl-delay: 10). Reads the
                        event list embedded in the page and keeps country == BG.
  --source csv FILE     Manual import from a CSV (see data/events_bulgaria.csv).
                        Use this if Smoothcomp asks you not to fetch automatically.

Writes nothing unless --apply is given (the default is a dry run that prints the events).

Env (only needed with --apply; never commit these):
  SUPABASE_PROJECT_URL       https://<ref>.supabase.co  (a trailing /rest/v1 is stripped)
  SUPABASE_SERVICE_ROLE_KEY  service role / secret key (server-side only, never in the app)

Run at most once a day (e.g. cron: `0 6 * * * python3 scripts/sync_events.py --apply`).
Only facts and a link back are stored; registration stays on Smoothcomp.
"""
import argparse
import csv
import json
import os
import re
import sys
import urllib.request

LISTING_URL = "https://smoothcomp.com/en/events/upcoming"
USER_AGENT = "BJJBul-events-sync/1.0 (+admin@bjjbul.com)"
COUNTRY = "BG"


def fetch_listing() -> str:
    req = urllib.request.Request(LISTING_URL, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def extract_events(page: str) -> list:
    """Find JSON objects shaped like {"id":123,"title":...} embedded in the page."""
    events = {}
    for match in re.finditer(r'\{"id":(\d+),"title":', page):
        start, depth, in_str, esc = match.start(), 0, False, False
        end = None
        for i in range(start, min(start + 20000, len(page))):
            ch = page[i]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        if end is None:
            continue
        try:
            obj = json.loads(page[start:end])
        except ValueError:
            continue
        if "startdate" in obj:
            events[obj["id"]] = obj
    return list(events.values())


def to_row(obj: dict) -> dict:
    def num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None
    return {
        "smoothcomp_id": int(obj["id"]),
        "name": obj.get("title"),
        "starts_at": obj.get("startdate"),
        "ends_at": obj.get("enddate") or obj.get("startdate"),
        "city": obj.get("location_city"),
        "country": obj.get("location_country") or COUNTRY,
        "latitude": num(obj.get("location_lat")),
        "longitude": num(obj.get("location_long")),
        "url": obj.get("url"),
        "image_url": obj.get("cover_image"),
        "registration_url": obj.get("url"),
        "category_groups": ",".join(obj.get("categoryGroups") or []) or None,
        "source": "smoothcomp",
    }


def rows_from_csv(path: str) -> list:
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            row = {
                "smoothcomp_id": int(r["smoothcomp_id"]),
                "name": r["name"],
                "starts_at": r["starts_at"],
                "ends_at": r.get("ends_at") or r["starts_at"],
                "city": r.get("city") or None,
                "country": r.get("country") or COUNTRY,
                "latitude": float(r["latitude"]) if r.get("latitude") else None,
                "longitude": float(r["longitude"]) if r.get("longitude") else None,
                "url": r["url"],
                "image_url": r.get("image_url") or None,
                "registration_url": r.get("registration_url") or r["url"],
                "registration_deadline": r.get("registration_deadline") or None,
                "venue": r.get("venue") or None,
                "registration_info": r.get("registration_info") or None,
                "source": "csv",
            }
            rows.append(row)
    return rows


def upsert(rows: list) -> None:
    base = os.environ.get("SUPABASE_PROJECT_URL", "").rstrip("/")
    base = re.sub(r"/rest/v1$", "", base)
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not base or not key:
        sys.exit("Set SUPABASE_PROJECT_URL and SUPABASE_SERVICE_ROLE_KEY to use --apply.")
    # PostgREST bulk upsert needs every row to have the same keys.
    keys = sorted({k for r in rows for k in r})
    payload = [{k: r.get(k) for k in keys} for r in rows]
    req = urllib.request.Request(
        f"{base}/rest/v1/events?on_conflict=smoothcomp_id",
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"Upserted {len(rows)} events (HTTP {resp.status}).")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", choices=["smoothcomp", "csv"], default="smoothcomp")
    parser.add_argument("csv_path", nargs="?", help="CSV file when --source csv")
    parser.add_argument("--apply", action="store_true", help="write to Supabase (default: dry run)")
    args = parser.parse_args()

    if args.source == "csv":
        if not args.csv_path:
            sys.exit("Usage: sync_events.py --source csv data/events_bulgaria.csv [--apply]")
        rows = rows_from_csv(args.csv_path)
    else:
        events = extract_events(fetch_listing())
        rows = [to_row(e) for e in events if e.get("location_country") == COUNTRY and not e.get("eventEnded")]
        print(f"Listing contained {len(events)} events; {len(rows)} in Bulgaria.")

    rows.sort(key=lambda r: r["starts_at"] or "")
    for r in rows:
        print(f"  {r['starts_at']}  {r['name']}  ({r['city']})  {r['url']}")

    if args.apply and rows:
        upsert(rows)
    elif not args.apply:
        print("Dry run: nothing written. Add --apply to upsert.")


if __name__ == "__main__":
    main()
