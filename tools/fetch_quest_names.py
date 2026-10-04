#!/usr/bin/env python3
"""Name every quest id the client knows, from Wowhead's Forever data.

    python3 tools/fetch_quest_names.py --build 1.60.1.70178 [--new-only] [--delay 0.15]

The client's QuestV2 lists 6,609 quest ids and nothing else. Questie knows 4,244 of them; the
rest are Forever's own and have no name anywhere we can read offline. Wowhead's Forever data
(dataEnv 16) names some of them, one tooltip at a time, which is enough to answer "what is the
id of the quest somebody just told me about".

Each tooltip is cached under tools/cache/wowhead-forever/quests, so a second run is free and an
interrupted one carries on. Output: tools/data/forever-quest-names.json, {id: {name, text}}.

The proper answer to the same question is ForeverBuddyScan, which asks the server and gets every
one of them. This is the stopgap for when nobody has run it yet.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import fetch  # noqa: E402

TOOLTIP = "https://nether.wowhead.com/tooltip/quest/{id}?dataEnv=16&locale=0"
WAGO = "https://wago.tools/db2/QuestV2/csv?build={build}"
TAG = re.compile(r"<[^>]+>")


def quest_ids(cache, build):
    import csv
    import io
    text = fetch(WAGO.format(build=build), os.path.join(cache, build, "QuestV2.csv"))
    return sorted({int(r["ID"]) for r in csv.DictReader(io.StringIO(text)) if r.get("ID")})


def questie_ids(cache):
    path = os.path.join(cache, "questie", "classicQuestDB.lua")
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8", errors="replace") as f:
        return {int(m) for m in re.findall(r"^\s*\[(\d+)\]\s*=\s*\{", f.read(), re.M)}


def one(quest_id, folder, delay):
    """{name, text} for a quest, {} when Wowhead has never heard of it. Cached on disk."""
    path = os.path.join(folder, "%d.json" % quest_id)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    try:
        request = urllib.request.Request(TOOLTIP.format(id=quest_id),
                                         headers={"User-Agent": "ForeverBuddy fetch_quest_names.py"})
        with urllib.request.urlopen(request, timeout=20) as response:
            body = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError):
        return None  # a failure is not cached, so the next run tries again
    out = {}
    if body.get("name"):
        out["name"] = body["name"]
        text = TAG.sub(" ", body.get("tooltip") or "")
        out["text"] = " ".join(text.split())[:400]
    os.makedirs(folder, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f)
    time.sleep(delay)
    return out


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", default="1.60.1.70178")
    parser.add_argument("--delay", type=float, default=0.15)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--min-id", type=int, default=0,
                        help="start here: Forever's own quests cluster above 60000")
    parser.add_argument("--new-only", action="store_true",
                        help="only the ids Questie has never heard of, which is where Forever's own are")
    parser.add_argument("--cache", default=os.path.join(root, "tools", "cache"))
    parser.add_argument("--out", default=os.path.join(root, "tools", "data", "forever-quest-names.json"))
    args = parser.parse_args(argv)

    ids = quest_ids(args.cache, args.build)
    if args.new_only:
        known = questie_ids(args.cache)
        ids = [q for q in ids if q not in known]
    if args.min_id:
        ids = [q for q in ids if q >= args.min_id]
    folder = os.path.join(args.cache, "wowhead-forever", "quests")
    found, asked = {}, 0
    for quest_id in ids:
        record = one(quest_id, folder, args.delay)
        asked += 1
        if record and record.get("name"):
            found[str(quest_id)] = record
        if args.limit and asked >= args.limit:
            break
        if asked % 250 == 0:
            print("%d/%d asked, %d named" % (asked, len(ids), len(found)), flush=True)

    previous = {}
    if os.path.exists(args.out):
        with open(args.out, encoding="utf-8") as f:
            previous = json.load(f).get("quests", {})
    previous.update(found)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"build": args.build, "quests": previous}, f, indent=1, sort_keys=True)
    print("%d asked, %d named, %d in the file -> %s" % (asked, len(found), len(previous), args.out))


if __name__ == "__main__":
    main()
