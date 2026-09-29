#!/usr/bin/env python3
"""Rebuild the zones workbook from Data/Zones.lua, the same list /fb zones shows.

Usage: python3 tools/zones_xlsx.py [--out ~/Desktop/ForeverAddons/ForeverBuddy-zones.xlsx]

Sheet one is every zone the addon knows a level range for. Sheet two is Forever's own areas,
whose names come from the client's area table but whose ranges are only what players report.
"""
import argparse
import os
import re
import sys

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill

ROW = re.compile(
    r'\{ zone = (\d+), name = "([^"]+)", continent = "([^"]*)", level = \{ (\d+), (\d+) \},'
    r' quests = (\d+), faction = (false|"[A-Za-z]+"), source = "([a-z]+)" \}')

# Forever's own areas: client area ids, and ranges only as reported by players and previews.
FOREVER = [
    ("Zephras Isle", 16593, "1 to 12", "Reported",
     "Starting zone for the new Skyborne race, per public previews"),
    ("The Hall of Thanes", 16919, "13 to 20", "Reported",
     "Dungeon under Ironforge; range from the client's own content tuning"),
    ("Ruins of Lordaeron", 16611, "15 to 22", "Reported",
     "Forsaken dungeon under Undercity; range from the client's own content tuning"),
    ("Riverglades", 16591, "33 to 45", "Reported",
     "Described as mid-30s to mid-40s, about the size of Stranglethorn, close to 200 quests"),
    ("Shen'dralas", 16651, "unknown", "Unknown",
     "South of Desolace, tied to Dire Maul and the centaur tribes; no range announced"),
    ("Darkspear Islands", 16606, "unknown", "Unknown", "New area in the client; no range announced"),
    ("Gilneas / Ruins of Gilneas", 17065, "unknown", "Unknown", "New areas in the client; no range announced"),
    ("Battle for Gilneas", 16653, "not a levelling zone", "Reported", "Battleground"),
    ("Excavation Site: Wetlands", 16732, "26 to 33", "Reported",
     "Dungeon in the Wetlands; range from the client's own content tuning"),
]

FONT = "Arial"
HEAD = PatternFill("solid", fgColor="1F3864")
NOTE = PatternFill("solid", fgColor="FFF2CC")


def read_zones(path):
    zones = []
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    for m in ROW.finditer(text):
        zone, name, continent, lo, hi, quests, faction, source = m.groups()
        zones.append({"zone": int(zone), "name": name, "continent": continent,
                      "lo": int(lo), "hi": int(hi), "quests": int(quests),
                      "faction": faction.strip('"') if faction != "false" else "",
                      "source": source})
    return zones


def title(ws, cell, text, size=14):
    ws[cell] = text
    ws[cell].font = Font(name=FONT, size=size, bold=True)


def header_row(ws, row, names, widths):
    for i, (name, width) in enumerate(zip(names, widths), start=1):
        c = ws.cell(row=row, column=i, value=name)
        c.font = Font(name=FONT, bold=True, color="FFFFFF")
        c.fill = HEAD
        ws.column_dimensions[c.column_letter].width = width


def body(cell, value, italic=False):
    cell.value = value
    cell.font = Font(name=FONT, italic=italic)


def build(zones, out):
    wb = Workbook()
    ws = wb.active
    ws.title = "Classic zones"
    title(ws, "A1", "Where to quest, by level")
    ws["A2"] = ("What /fb zones uses. Bands come from the quests in each zone: the narrowest level span "
                "holding 75% of them, from Questie's Classic database. A zone marked reported was set by "
                "hand instead. Faction is set when 60% or more of a zone's quests belong to one side.")
    ws["A2"].font = Font(name=FONT, italic=True, size=9)
    ws["A2"].alignment = Alignment(wrap_text=False)
    header_row(ws, 4, ["Zone", "Continent", "From", "To", "Span", "Quests", "Faction", "Set by", "Your note"],
               [26, 18, 7, 7, 7, 8, 10, 10, 40])
    for i, z in enumerate(sorted(zones, key=lambda z: (z["lo"], z["hi"], z["name"])), start=5):
        body(ws.cell(row=i, column=1), z["name"])
        body(ws.cell(row=i, column=2), z["continent"])
        body(ws.cell(row=i, column=3), z["lo"])
        body(ws.cell(row=i, column=4), z["hi"])
        ws.cell(row=i, column=5, value="=D%d-C%d" % (i, i)).font = Font(name=FONT)
        body(ws.cell(row=i, column=6), z["quests"])
        body(ws.cell(row=i, column=7), z["faction"] or "both")
        body(ws.cell(row=i, column=8), "quests" if z["source"] == "quests" else z["source"], italic=True)
        ws.cell(row=i, column=9).fill = NOTE
    ws.freeze_panes = "A5"

    fw = wb.create_sheet("New Forever zones")
    title(fw, "A1", "Forever's own areas")
    fw["A2"] = ("Names come from the beta client's area table, so they are certain. Ranges are not in the "
                "client: they are what previews, guides and the content tuning table say, and are marked "
                "as such. Anything already in /fb zones also appears on the first sheet.")
    fw["A2"].font = Font(name=FONT, italic=True, size=9)
    header_row(fw, 4, ["Area", "Area ID", "Level range", "Confidence", "Where the range came from", "Your note"],
               [28, 10, 18, 12, 62, 40])
    for i, (name, area, band, confidence, where) in enumerate(FOREVER, start=5):
        body(fw.cell(row=i, column=1), name)
        body(fw.cell(row=i, column=2), area)
        body(fw.cell(row=i, column=3), band)
        body(fw.cell(row=i, column=4), confidence)
        body(fw.cell(row=i, column=5), where, italic=True)
        fw.cell(row=i, column=6).fill = NOTE
    last = len(FOREVER) + 6
    fw.cell(row=last, column=1, value="Fill in what you learn in game and I will fold it into /fb zones.").font = \
        Font(name=FONT, italic=True, size=9)
    fw.freeze_panes = "A5"
    wb.save(out)
    return len(zones)


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zones", default=os.path.join(root, "Data", "Zones.lua"))
    parser.add_argument("--out", default=os.path.expanduser("~/Desktop/ForeverAddons/ForeverBuddy-zones.xlsx"))
    args = parser.parse_args(argv)
    zones = read_zones(args.zones)
    if not zones:
        sys.exit("no zones parsed from %s" % args.zones)
    build(zones, args.out)
    print("%d zones written to %s" % (len(zones), args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
