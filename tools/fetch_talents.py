"""Fetch Wowhead's talent-calculator data for a game version and save it as JSON.

Wowhead's page at wowhead.com/<game>/talent-calc is behind a bot challenge, but
the data file it loads is served openly from nether.wowhead.com:

    https://nether.wowhead.com/data/talents-classic?dv=19&db=<any>&dataEnv=<env>

dataEnv: 4 = Classic Era, 5 = TBC, 8 = Wrath, 16 = Forever (classicplus).
The response is `WH.setPageData("<key>", {...});` with `talents` (tab id ->
talent id -> {name, row, col, ranks, requires, descriptions}) and `trees`
(tab id -> {description: "<Class><Tree>"}). For Forever the spell IDs in
`ranks` are null (not published yet); names, positions, rank counts,
prerequisites and per-rank descriptions are present.

Usage: python3 tools/fetch_talents.py [--env 16] [--out tools/data/forever-talents.json]
"""
import argparse, json, re, sys, urllib.request

URL = "https://nether.wowhead.com/data/talents-classic?dv=19&db=1789102903&dataEnv=%d"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
CLASSES = ("Mage", "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Warlock", "Druid")

def fetch(env):
    req = urllib.request.Request(URL % env, headers={"User-Agent": UA, "Referer": "https://www.wowhead.com/forever/talent-calc"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")

def parse(raw):
    m = re.match(r'WH\.setPageData\("([^"]+)",', raw)
    if not m:
        raise SystemExit("unexpected response: %r" % raw[:120])
    obj, _ = json.JSONDecoder().raw_decode(raw, m.end())
    return m.group(1), obj

def split_tree(desc):
    for c in CLASSES:
        if desc.startswith(c):
            return c, desc[len(c):]
    return "?", desc

def derive(data):
    classes = {}
    for tab, talents in data["talents"].items():
        cls, tree = split_tree(data["trees"][tab]["description"])
        classes.setdefault(cls, {})[tree] = {
            t["name"]: dict(row=t["row"], col=t["col"], maxRank=len(t["ranks"]), requires=t.get("requires") or [],
                            icon=t.get("icon"), descriptions=t.get("descriptions") or {}, spells=t["ranks"])
            for t in talents.values()
        }
    return classes

def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", type=int, default=16)
    ap.add_argument("--out", default="tools/data/forever-talents.json")
    a = ap.parse_args(argv)
    key, data = parse(fetch(a.env))
    classes = derive(data)
    n = sum(len(t) for c in classes.values() for t in c.values())
    out = dict(meta=dict(source="Wowhead talent calculator data, key %s, dataEnv %d" % (key, a.env), trees=sum(len(c) for c in classes.values()), talents=n), classes=classes)
    json.dump(out, open(a.out, "w"), indent=1, sort_keys=True)
    print("wrote %s: %d trees, %d talents" % (a.out, out["meta"]["trees"], n))

if __name__ == "__main__":
    main()
