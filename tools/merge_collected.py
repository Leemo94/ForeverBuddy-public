"""Merge what players' ForeverBuddy collectors recorded, and write Data/Observed.lua.

    python3 tools/merge_collected.py ~/Desktop/ForeverAddons/inbox/*.lua

Each input is a saved-variables file (WTF/Account/<account>/SavedVariables/ForeverBuddy.lua).
The union of everything recorded lives in tools/observed/observed.json (committed), so files can
be merged one at a time as they arrive; a file already merged (same content) is skipped.
Data/Observed.lua is regenerated from the union and the addon loads it on top of the generated
data: quest items it did not know, quest givers with places, loot sources, NPC positions.

The script prints what was new (quests, reports) so it can be curated into the build scripts.
"""
import argparse
import csv
import datetime
import glob
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import lua_string, parse_lua_value  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_saved_variables(text, name="ForeverBuddyDB"):
    """The value assigned to `name` in a WoW saved-variables file."""
    m = re.search(r"^%s\s*=\s*" % re.escape(name), text, re.M)
    if not m:
        raise ValueError("no %s in file" % name)
    value, _ = parse_lua_value(text, m.end())
    return value


def objective_item_name(text):
    """Item name from an objective line: Classic 'Boar Meat: 3/8', Mainline '3/8 Boar Meat'."""
    if not isinstance(text, str):
        return None
    m = re.match(r"^\s*(.-?)\s*:\s*\d+/\d+\s*$", text) or re.match(r"^\s*(.+?)\s*:\s*\d+\s*/\s*\d+\s*$", text)
    if m:
        return m.group(1)
    m = re.match(r"^\s*\d+\s*/\s*\d+\s+(.+?)\s*$", text)
    return m.group(1) if m else None


def as_map(value):
    """A Lua table with no entries parses as a list, so an empty vendor reads as [] not {}."""
    return value if isinstance(value, dict) else {}


def merge_trainers(union, collected, new):
    """A trainer's whole offering, keyed by its NPC id. The longest list for a trainer wins:
    a character too low to see the rest of the ladder records fewer rows."""
    union.setdefault("trainers", {})
    for key, rec in (collected.get("trainers") or {}).items():
        services = rec.get("services") or []
        have = union["trainers"].get(str(key))
        if not have or len(services) > len(have.get("services") or []):
            new["trainers"] = new.get("trainers", 0) + (0 if have else 1)
            union["trainers"][str(key)] = rec
    return union


def trainer_levels(union):
    """{spell id: level} from every trainer recorded, for checking the ability ladder."""
    out = {}
    for rec in (union.get("trainers") or {}).values():
        for service in rec.get("services") or []:
            spell, level = service.get("spell"), service.get("level")
            if spell and level:
                out[int(spell)] = int(level)
    return out


def empty_union():
    return {"files": {}, "items": {}, "quests": {}, "npcs": {}, "loot": {}, "vendors": {}, "talents": {},
            "trainers": {}, "reports": []}


def merge_file(union, collected, file_id):
    """Fold one collector store into the union. Returns a summary of what was new."""
    new = {"items": 0, "quests": 0, "npcs": 0, "loot": 0, "vendors": 0, "talents": 0, "trainers": 0, "reports": 0}
    for key, rec in (collected.get("items") or {}).items():
        key = str(key)
        if key not in union["items"] or (rec.get("seen") or 0) > (union["items"][key].get("seen") or 0):
            new["items"] += key not in union["items"]
            union["items"][key] = rec
    for key, rec in (collected.get("quests") or {}).items():
        key = str(key)
        cur = union["quests"].get(key)
        if cur is None:
            new["quests"] += 1
            union["quests"][key] = dict(rec)
        else:
            for field, value in rec.items():
                if value is not None and (cur.get(field) is None or field in ("xp", "money", "rewards", "choices", "objectives", "shareable", "level", "turnin")):
                    cur[field] = value
    for key, rec in (collected.get("npcs") or {}).items():
        key = str(key)
        if key not in union["npcs"]:
            new["npcs"] += 1
            union["npcs"][key] = rec
    for key, src in (collected.get("loot") or {}).items():
        cur = union["loot"].setdefault(key, {"items": {}})
        if not cur.get("zone") and src.get("zone"):
            cur["zone"] = src["zone"]
        if not isinstance(cur.get("items"), dict):
            cur["items"] = {}
        for item, count in as_map(src.get("items")).items():
            item = str(item)
            if item not in cur["items"]:
                new["loot"] += 1
            cur["items"][item] = cur["items"].get(item, 0) + (count or 0)
    for key, rec in (collected.get("vendors") or {}).items():
        key = str(key)
        cur = union["vendors"].get(key)
        if cur is None:
            new["vendors"] += 1
            union["vendors"][key] = rec
        else:
            if not isinstance(cur.get("items"), dict):
                cur["items"] = {}
            cur["items"].update({str(k): v for k, v in as_map(rec.get("items")).items()})
    for key, rec in (collected.get("talents") or {}).items():
        if key not in union["talents"] or len(rec.get("order") or []) > len(union["talents"][key].get("order") or []):
            new["talents"] += key not in union["talents"]
            union["talents"][key] = rec
    seen = {(r.get("char"), r.get("time")) for r in union["reports"]}
    for rec in collected.get("reports") or []:
        if (rec.get("char"), rec.get("time")) not in seen:
            union["reports"].append(rec)
            new["reports"] += 1
    merge_trainers(union, collected, new)
    union["files"][file_id] = datetime.date.today().isoformat()
    return new


def item_name_tables(root):
    """Every cached client item table, newest build last so it wins."""
    paths = sorted(glob.glob(os.path.join(root, "tools", "cache", "*", "ItemSparse.csv")))
    return paths


def item_names(union, item_sparse_csv=None):
    """{lowercase name: itemID} from the client item tables, then from what players recorded."""
    names = {}
    for path in ([item_sparse_csv] if item_sparse_csv else []):
        if not path or not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                name = row.get("Display_lang")
                if name:
                    names[name.lower()] = int(row["ID"])
    for key, rec in union["items"].items():
        if rec.get("name"):
            names[rec["name"].lower()] = int(key)
    return names


def quest_items(union, names):
    """{itemID: [(questID, title)]} from item objectives of recorded quests."""
    out = {}
    for key, q in union["quests"].items():
        for o in q.get("objectives") or []:
            if o.get("type") != "item":
                continue
            name = objective_item_name(o.get("text"))
            item = names.get((name or "").lower())
            if item:
                out.setdefault(item, []).append((int(key), q.get("title") or "?"))
    return out


def lua_num(v):
    if v is None or v is False:
        return "false"
    return ("%d" % v) if float(v).is_integer() else ("%.1f" % v)


def lua_place(p, where):
    if not p:
        return "false"
    w = where or {}
    return "{ id = %d, name = %s, zone = %s, map = %s, x = %s, y = %s }" % (
        int(p.get("id") or 0), lua_string(p.get("name") or "?"), lua_string(w.get("zone")) if w.get("zone") else "false",
        lua_num(w.get("map")), lua_num(w.get("x")), lua_num(w.get("y")))


def emit_observed(union, qitems, generated):
    lines = ["local _, ns = ...", "", "-- GENERATED by tools/merge_collected.py from players' saved variables; do not edit by hand.",
             "ns.ObservedInfo = { generated = %s, files = %d, items = %d, quests = %d, loot = %d, npcs = %d,"
             " trainers = %d }" % (
                 lua_string(generated), len(union["files"]), len(union["items"]), len(union["quests"]),
                 len(union["loot"]), len(union["npcs"]), len(union.get("trainers") or {})),
             "", "ns.Observed = {", "  questItems = {"]
    for item in sorted(qitems):
        entries = ", ".join("{ %d, %s }" % (qid, lua_string(title)) for qid, title in sorted(set(qitems[item])))
        lines.append("    [%d] = { %s }," % (item, entries))
    lines.append("  },")
    lines.append("  quests = {")
    for key in sorted(union["quests"], key=int):
        q = union["quests"][key]
        lines.append("    [%d] = { title = %s, level = %s, xp = %s, shareable = %s, giver = %s, turnin = %s }," % (
            int(key), lua_string(q.get("title") or "?"), lua_num(q.get("level")), lua_num(q.get("xp")),
            "true" if q.get("shareable") else "false", lua_place(q.get("giver"), q.get("where")), lua_place(q.get("turnin"), q.get("turninWhere"))))
    lines.append("  },")
    lines.append("  loot = {")
    for key in sorted(union["loot"]):
        if not key.startswith("npc:"):
            continue
        items = ", ".join(str(i) for i in sorted(int(x) for x in union["loot"][key]["items"]))
        lines.append("    [%d] = { %s }," % (int(key[4:]), items))
    lines.append("  },")
    lines.append("  trainers = {")
    for key in sorted(union.get("trainers") or {}, key=lambda k: int(k) if k.lstrip("-").isdigit() else 0):
        t = union["trainers"][key]
        lines.append("    [%s] = { name = %s, class = %s, services = {" % (
            key if key.lstrip("-").isdigit() else lua_string(key), lua_string(t.get("name") or "?"),
            lua_string(t.get("class")) if t.get("class") else "false"))
        for service in sorted(t.get("services") or [], key=lambda x: (x.get("level") or 0, x.get("name") or "")):
            lines.append("      { spell = %s, name = %s, rank = %s, level = %s, cost = %s }," % (
                lua_num(service.get("spell")), lua_string(service.get("name") or "?"),
                lua_string(service.get("rank")) if service.get("rank") else "false",
                lua_num(service.get("level")), lua_num(service.get("cost"))))
        lines.append("    } },")
    lines.append("  },")
    lines.append("  npcs = {")
    for key in sorted(union["npcs"], key=int):
        n = union["npcs"][key]
        lines.append("    [%d] = { name = %s, zone = %s, map = %s, x = %s, y = %s }," % (
            int(key), lua_string(n.get("name") or "?"), lua_string(n.get("zone")) if n.get("zone") else "false", lua_num(n.get("map")), lua_num(n.get("x")), lua_num(n.get("y"))))
    lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+", help="saved-variables files to merge")
    parser.add_argument("--observed", default=os.path.join(ROOT, "tools", "observed", "observed.json"))
    parser.add_argument("--out", default=os.path.join(ROOT, "Data", "Observed.lua"))
    parser.add_argument("--item-names", action="append", default=None,
                        help="client item tables for name lookups (default: every cached build, newest wins)")
    args = parser.parse_args(argv)
    union = empty_union()
    if os.path.exists(args.observed):
        with open(args.observed, encoding="utf-8") as f:
            union = json.load(f)
    for path in args.files:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        file_id = hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]
        if file_id in union["files"]:
            print("%s: already merged, skipped" % path)
            continue
        db = parse_saved_variables(text)
        collected = db.get("collected") if isinstance(db, dict) else None
        if not collected:
            print("%s: nothing collected in this file" % path)
            continue
        new = merge_file(union, collected, file_id)
        print("%s: new %s" % (path, ", ".join("%d %s" % (v, k) for k, v in new.items() if v)))
        client = collected.get("client") or {}
        if client:
            print("  client %s build %s, interface %s" % (client.get("version"), client.get("build"), client.get("interface")))
        for where, e in (collected.get("errors") or {}).items():
            print("  ERROR in %s (x%s): %s" % (where, e.get("count"), e.get("msg")))
        for key, q in (collected.get("quests") or {}).items():
            print("  quest %s: %s (level %s, giver %s, xp %s)" % (key, q.get("title"), q.get("level"), (q.get("giver") or {}).get("name"), q.get("xp")))
        for r in collected.get("reports") or []:
            print("  report from %s: %s" % (r.get("char"), r.get("text")))
    os.makedirs(os.path.dirname(args.observed), exist_ok=True)
    with open(args.observed, "w", encoding="utf-8") as f:
        json.dump(union, f, indent=1, sort_keys=True)
    tables = args.item_names or item_name_tables(ROOT)
    names = {}
    for path in tables:
        names.update(item_names(union, path))
    for key, rec in union["items"].items():
        if rec.get("name"):
            names[rec["name"].lower()] = int(key)
    qitems = quest_items(union, names)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(emit_observed(union, qitems, datetime.date.today().isoformat()))
    print("observed: %d items, %d quests (%d item objectives resolved), %d loot sources, %d NPCs, %d vendors, %d talent records, %d reports" % (
        len(union["items"]), len(union["quests"]), sum(len(v) for v in qitems.values()), len(union["loot"]), len(union["npcs"]), len(union["vendors"]), len(union["talents"]), len(union["reports"])))


if __name__ == "__main__":
    main()
