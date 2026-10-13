#!/usr/bin/env python3
"""
Sale Hunter — Ounass Bahrain sale scraper.

Pages through Ounass Bahrain's public listing API for each configured
section (e.g. men/sale), keeps a compact copy in docs/data/sales.json for the
web app, remembers when each item was first seen and its previous price, and
optionally sends a push notification (via ntfy.sh) for new items or price
drops that match the filters in config.json.

Standard library only — no pip install needed.
"""

import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(ROOT, "config.json")
DATA_DIR = os.path.join(ROOT, "docs", "data")
SALES_PATH = os.path.join(DATA_DIR, "sales.json")

BASE = "https://bahrain.ounass.com"
PAGE_SIZE = 24
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    ),
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
}


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def get_json(url, retries=4):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
            last = e
            wait = 2 ** attempt + random.random()
            print(f"  retry {attempt + 1}/{retries} after error: {e} (sleep {wait:.1f}s)")
            time.sleep(wait)
    raise RuntimeError(f"failed to fetch {url}: {last}")


def abs_url(u):
    if not u:
        return ""
    if u.startswith("//"):
        return "https:" + u
    if u.startswith("/"):
        return BASE + u
    return u


def compact(p, section):
    """Keep only what the app needs, with short keys to keep the file small."""
    sizes = [
        s.get("sizeCode")
        for s in (p.get("sizes") or [])
        if s.get("sizeCode") and (s.get("stock") or 0) > 0
    ]
    return {
        "id": p.get("styleColorId"),
        "b": (p.get("designerCategoryEnglishName") or p.get("designerCategoryName") or "").strip(),
        "n": (p.get("nameInEnglish") or p.get("name") or "").strip(),
        "p": p.get("price"),
        "o": p.get("slashedPrice"),
        "d": p.get("discountPercent") or 0,
        "c": p.get("productClassInEnglish") or "",
        "t": p.get("class") or "",
        "col": p.get("colorInEnglish") or "",
        "img": abs_url(p.get("thumbnail")),
        "u": abs_url(p.get("url")),
        "sz": sizes,
        "s": section,
    }


def scrape_section(section, delay):
    """section like 'men/sale'. Returns list of compact items."""
    items, start, total = [], 0, None
    while True:
        url = f"{BASE}/api/v2/{section}?fh_start_index={start}"
        data = get_json(url)
        plp = data.get("plp") or {}
        if total is None:
            total = (plp.get("pagination") or {}).get("totalItems") or 0
            print(f"{section}: {total} items")
        batch = plp.get("styleColors") or []
        for p in batch:
            if p.get("styleColorId") and not p.get("outOfStock"):
                items.append(compact(p, section))
        start += PAGE_SIZE
        nxt = ((plp.get("pagination") or {}).get("nextPage") or {}).get("href")
        if not batch or not nxt or start >= total:
            break
        if (start // PAGE_SIZE) % 25 == 0:
            print(f"  ...{start}/{total}")
        time.sleep(delay)
    return items, total


def matches(item, w):
    if item["d"] < (w.get("min_discount") or 0):
        return False
    if w.get("max_price") and item["p"] and item["p"] > w["max_price"]:
        return False
    brands = [b.lower() for b in w.get("brands") or []]
    if brands and item["b"].lower() not in brands:
        return False
    cats = [c.lower() for c in w.get("categories") or []]
    if cats and item["c"].lower() not in cats:
        return False
    sizes = set(w.get("sizes") or []) | set(w.get("shoe_sizes") or [])
    if sizes and item["sz"] and not (sizes & set(item["sz"])):
        return False
    return True


def notify(topic, title, lines, click_url):
    body = "\n".join(lines).encode("utf-8")
    req = urllib.request.Request(
        f"https://ntfy.sh/{urllib.parse.quote(topic)}",
        data=body,
        method="POST",
        headers={
            "Title": title.encode("utf-8").decode("latin-1", "ignore") or "Sale Hunter",
            "Tags": "shopping_bags",
            "Click": click_url,
        },
    )
    try:
        urllib.request.urlopen(req, timeout=20).read()
        print("notification sent")
    except Exception as e:  # never fail the run because of a notification
        print(f"notification failed: {e}")


def main():
    cfg = load_json(CONFIG_PATH, {})
    sections = cfg.get("sections") or ["men/sale"]
    delay = float(cfg.get("request_delay_seconds", 1.0))

    prev = load_json(SALES_PATH, {})
    prev_items = {i["id"]: i for i in prev.get("items", [])}
    first_run = not prev_items
    ts = now_iso()

    all_items, expected = [], 0
    for section in sections:
        items, total = scrape_section(section, delay)
        all_items += items
        expected += total

    # Safety: don't wipe good data with a broken/partial scrape.
    if expected and len(all_items) < expected * 0.5:
        print(f"Only got {len(all_items)} of {expected} — keeping previous data.")
        sys.exit(1)

    seen, items, new_items, drops = set(), [], [], []
    for it in all_items:
        if it["id"] in seen:
            continue
        seen.add(it["id"])
        old = prev_items.get(it["id"])
        if old:
            it["f"] = old.get("f", ts)
            # remember the last higher sale price so the app can show "price dropped"
            if old.get("p") and it["p"] and it["p"] < old["p"]:
                it["pp"] = old["p"]
                it["pd"] = ts
                drops.append(it)
            elif old.get("pp") and old.get("pd"):
                it["pp"], it["pd"] = old["pp"], old["pd"]
        else:
            it["f"] = ts
            if not first_run:
                new_items.append(it)
        items.append(it)

    os.makedirs(DATA_DIR, exist_ok=True)
    out = {"updated": ts, "currency": "BHD", "count": len(items), "items": items}
    tmp = SALES_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, SALES_PATH)
    print(f"saved {len(items)} items ({len(new_items)} new, {len(drops)} price drops)")

    # Push notification
    topic = os.environ.get("NTFY_TOPIC", "").strip()
    watch = cfg.get("watch") or {}
    if topic and not first_run:
        hits_new = [i for i in new_items if matches(i, watch)]
        hits_drop = [i for i in drops if matches(i, watch)]
        if hits_new or hits_drop:
            hits = sorted(hits_new + hits_drop, key=lambda i: -i["d"])
            lines = [
                f"{'⬇️ ' if i in hits_drop else '🆕 '}{i['b']} – {i['n']}: {i['p']} BHD (-{i['d']}%)"
                for i in hits[:10]
            ]
            if len(hits) > 10:
                lines.append(f"+ {len(hits) - 10} more")
            title = f"Sale Hunter: {len(hits_new)} new, {len(hits_drop)} price drops"
            notify(topic, title, lines, cfg.get("app_url") or BASE)


if __name__ == "__main__":
    main()
