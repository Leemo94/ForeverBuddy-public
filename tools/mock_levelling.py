#!/usr/bin/env python3
"""Draw three mock-ups of the "Where to level" screen, from the real shipped data.

    python3 tools/mock_levelling.py [--level 24] [--faction Horde]

Writes review/where-to-level-mockup.html next to the addon, to be opened in a browser and
argued with. Nothing here is Blizzard's artwork: the frames are CSS, the crests are drawn by
hand, and the colours are the ones the game uses for quest difficulty, which is the part
players already know how to read without being taught.
"""
import argparse
import html
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import parse_lua_value  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"^ns\.%s\s*=\s*" % name, text, re.M)
    value, _ = parse_lua_value(text, m.end())
    return value


# The game's own quest difficulty colours. A player reads these without thinking.
def difficulty(level, lo, hi):
    if level < lo - 4:
        return "red", "too soon"
    if level < lo:
        return "orange", "nearly"
    if level <= hi - 3:
        return "yellow", "right now"
    if level <= hi:
        return "green", "running out"
    return "grey", "behind you"


SWORD = ('<svg viewBox="0 0 12 12" class="sword"><path d="M6 .8 7.1 3v4.1H4.9V3z"/>'
         '<path d="M3.2 7.4h5.6v1.2H3.2z"/><path d="M5.5 8.6h1v2.6h-1z"/>'
         '<path d="M4.6 11.1h2.8v1H4.6z"/></svg>')

CREST = {
    "Alliance": '<svg viewBox="0 0 20 24" class="crest a"><path d="M10 1 19 4v9c0 6-5 9-9 10-4-1-9-4-9-10V4z"/><path d="M10 6v12M5 11h10" class="mark"/></svg>',
    "Horde": '<svg viewBox="0 0 20 24" class="crest h"><path d="M10 1 19 4v9c0 6-5 9-9 10-4-1-9-4-9-10V4z"/><path d="M6 8c3 2 5 2 8 0M6 15c3-2 5-2 8 0" class="mark"/></svg>',
}


def crest(faction, leaning):
    if not faction:
        return '<span class="crest none" title="both sides"></span>'
    mark = CREST[faction]
    return mark.replace('class="crest', 'class="crest lean' if leaning else 'class="crest')


def esc(text):
    return html.escape(str(text), quote=True)


def zone_rows(zones, level, faction):
    out = []
    for z in zones:
        lo, hi = z["level"]
        side = z.get("faction") or None
        if side and not z.get("leaning") and faction and side != faction:
            continue
        kind, _ = difficulty(level, lo, hi)
        out.append({"name": z["name"], "lo": lo, "hi": hi, "kind": kind, "quests": z.get("quests") or 0,
                    "faction": side, "leaning": bool(z.get("leaning")), "continent": z.get("continent") or "",
                    "alliance": z.get("alliance") or 0, "horde": z.get("horde") or 0})
    return out


def dungeon_rows(dungeons, level, faction):
    out = []
    for d in dungeons:
        band = d.get("level")
        if not isinstance(band, list):
            continue
        lo, hi = band[0], band[1] or band[0]
        kind, _ = difficulty(level, lo, hi)
        quests = d.get("quests") or []
        if isinstance(quests, dict):
            quests = list(quests.values())
        mine = [q for q in quests if not q.get("faction") or not faction or q.get("faction") == faction]
        out.append({"name": d["name"], "lo": lo, "hi": hi, "kind": kind, "quests": len(mine),
                    "faction": d.get("faction") or None})
    return out


STYLE = """
:root {
  --stone: #0a0805; --panel: #1b1510; --panel-deep: #150f0a; --edge: #665226; --edge-bright: #c29c4d;
  --parchment: #e8dcc0; --ink: #e8dcc0; --ink-dim: #998e78; --gold: #ffd100;
  --red: #ff4040; --orange: #ff8a2a; --yellow: #ffe14d; --green: #4ddb4d; --grey: #9d9d9d;
  --alliance: #3e7fd6; --horde: #c4343f;
}
* { box-sizing: border-box; }
body { margin: 0; background: #06060a; color: var(--ink);
  font: 15px/1.5 "Roboto Condensed", "Arial Narrow", Arial, sans-serif; }
h1, h2, h3, .display { font-family: Cinzel, Georgia, serif; margin: 0; letter-spacing: .02em; }
.wrap { max-width: 1180px; margin: 0 auto; padding: 28px 20px 80px; }
.intro { color: var(--ink-dim); max-width: 62em; }
.intro b { color: var(--gold); }
nav.jump { position: sticky; top: 0; z-index: 9; background: #06060acc; backdrop-filter: blur(6px);
  border-bottom: 1px solid #221d2e; padding: 10px 20px; display: flex; gap: 18px; align-items: center; }
nav.jump a { color: var(--ink); text-decoration: none; font-family: Cinzel, serif; font-size: .82rem;
  letter-spacing: .14em; text-transform: uppercase; }
nav.jump a:hover { color: var(--gold); }
nav.jump .who { margin-left: auto; color: var(--ink-dim); font-size: .85rem; }

/* the game frame: dark panel, gold rule, squared corners */
.frame { background: linear-gradient(180deg, #241a10 0%, #1a130c 100%);
  border: 1px solid var(--edge); box-shadow: 0 0 0 1px #000, 0 18px 50px rgba(0,0,0,.55); padding: 0; }
.frame > header { display: flex; align-items: baseline; gap: 14px; padding: 12px 16px 10px;
  border-bottom: 1px solid var(--edge); background: linear-gradient(180deg, #3a2b19, #291e11); }
.frame > header h2 { color: var(--gold); font-size: 1.05rem; }
.frame > header .sub { color: var(--ink-dim); font-size: .86rem; }
.frame > .body { padding: 14px 16px 18px; }
.variant { margin: 34px 0 10px; }
.variant .label { font-family: Cinzel, serif; color: var(--edge-bright); letter-spacing: .22em;
  text-transform: uppercase; font-size: .74rem; margin-bottom: 8px; }
.variant .note { color: var(--ink-dim); margin: 10px 2px 0; font-size: .92rem; max-width: 70em; }

.red { color: var(--red); } .orange { color: var(--orange); } .yellow { color: var(--yellow); }
.green { color: var(--green); } .grey { color: var(--grey); }

.crest { width: 13px; height: 16px; vertical-align: -3px; }
.crest path { fill: #2b2b33; stroke: #000; stroke-width: .8; }
.crest.a path { fill: var(--alliance); } .crest.h path { fill: var(--horde); }
.crest .mark { fill: none; stroke: #f0e6cf; stroke-width: 1.4; }
.crest.lean { opacity: .45; }
.crest.none { display: inline-block; width: 13px; }

/* --- 1. level bands ---------------------------------------------------- */
.band { border-top: 1px solid #241f30; padding: 12px 0 14px; display: grid; grid-template-columns: 92px 1fr; gap: 16px; }
.band:first-child { border-top: 0; }
.band.here { background: linear-gradient(90deg, rgba(255,209,0,.08), transparent 60%); }
.band .lv { font-family: Cinzel, serif; color: var(--gold); font-size: 1.1rem; text-align: right; padding-top: 2px; }
.band .lv small { display: block; color: var(--ink-dim); font-size: .68rem; letter-spacing: .16em; text-transform: uppercase; }
.band .you { color: #000; background: var(--gold); font-size: .62rem; padding: 1px 5px; letter-spacing: .1em; }
.pills { display: flex; flex-wrap: wrap; gap: 7px; }
.pill { display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--edge); background: #2b2114;
  padding: 4px 9px; font-size: .9rem; }
.pill b { font-weight: 600; }
.pill .range { color: var(--ink-dim); font-variant-numeric: tabular-nums; font-size: .82rem; }
.pill.dungeon { border-color: #7a5e2c; background: #35270f; }
.sword { width: 11px; height: 11px; vertical-align: -1px; }
.sword path { fill: var(--edge-bright); }
.pills .heading { color: var(--ink-dim); font-size: .72rem; letter-spacing: .16em; text-transform: uppercase;
  width: 100%; margin: 6px 0 -2px; }

/* --- 2. the road ------------------------------------------------------- */
.road { position: relative; padding: 6px 0 0; }
.road .rail { position: absolute; left: 50%; top: 0; bottom: 0; width: 3px; margin-left: -1.5px;
  background: linear-gradient(180deg, #4a3c1e, #8a6f33 10%, #8a6f33 90%, #4a3c1e); }
.stop { position: relative; display: grid; grid-template-columns: 1fr 86px 1fr; gap: 10px; align-items: center;
  padding: 9px 0; }
.stop .mid { text-align: center; }
.stop .dot { width: 11px; height: 11px; background: #0c0b10; border: 2px solid var(--edge-bright);
  transform: rotate(45deg); margin: 0 auto 4px; }
.stop.here .dot { background: var(--gold); box-shadow: 0 0 10px var(--gold); }
.stop .lv { font-family: Cinzel, serif; color: var(--gold); font-size: .95rem; }
.stop .left { text-align: right; } .stop .right { text-align: left; }
.stop .side { display: inline-flex; flex-wrap: wrap; gap: 6px; justify-content: inherit; }
.stop .left .side { justify-content: flex-end; }
.stop .dmark { display: block; margin-top: 3px; font-size: .74rem; color: var(--edge-bright);
  letter-spacing: .08em; }

/* --- 3. two pane ------------------------------------------------------- */
.pane { display: grid; grid-template-columns: 180px 1fr; gap: 0; min-height: 420px; }
.pane .list { padding: 6px; display: grid; gap: 3px; align-content: start; background: #15100a;
  border-right: 1px solid var(--edge); }
.pane .list button { display: block; width: 100%; text-align: left; font: inherit; cursor: default;
  color: var(--ink); background: #2b2114; border: 1px solid var(--edge); padding: 5px 9px; }
.pane .list button.on { background: #4d3a1e; border-color: var(--edge-bright); color: var(--gold); }
.pane .list button small { color: var(--ink-dim); display: block; font-size: .74rem; }
.pane .detail { padding: 14px 18px; }
.pane .detail h3 { color: var(--gold); font-size: 1rem; margin-bottom: 2px; }
.pane .detail .sub { color: var(--ink-dim); font-size: .86rem; margin-bottom: 14px; }
.pane table { width: 100%; border-collapse: collapse; }
.pane th { text-align: left; color: var(--ink-dim); font-weight: 400; font-size: .72rem;
  letter-spacing: .16em; text-transform: uppercase; padding: 12px 8px 5px; border-bottom: 1px solid var(--edge); }
.pane td { padding: 7px 8px; border-bottom: 0; font-size: 1rem; }
.pane tbody tr:nth-child(even) td { background: rgba(120,92,48,.10); }
.pane td.r { text-align: right; color: var(--ink-dim); font-variant-numeric: tabular-nums; }
.pane tr:hover td { background: rgba(160,124,62,.18); }
.advice { border: 1px solid var(--edge); background: #2b2114; padding: 11px 15px; margin: 0 0 14px;
  font-size: 1.04rem; }
.advice .at { font-family: Cinzel, serif; color: var(--gold); margin-right: 8px; letter-spacing: .08em; }
.advice b { color: var(--parchment); font-weight: 600; }

/* the parchment skin: the same screen, Classic's quest log rather than its dungeon journal */
.skin-parchment { color: #2f2113; --panel: #e3d3ab; --panel-deep: #d8c69a; --ink: #2f2113; --ink-dim: #6b5942;
  --edge: #6b5020; --edge-bright: #8a6a2c; --gold: #5a3d12; --parchment: #2f2113;
  --red: #a11b1b; --orange: #a35b10; --yellow: #6b5a00; --green: #1f6b14; --grey: #7b7366; }
.skin-parchment .frame > header { background: linear-gradient(180deg, #d2bd8e, #c4ab77); border-bottom-color: #8a6a2c; }
.skin-parchment .pill { background: #efe2c2; border-color: #b9a176; }
.skin-parchment .pill.dungeon { background: #f0e0b4; border-color: #a9833c; }
.skin-parchment .band.here { background: linear-gradient(90deg, rgba(120,80,0,.14), transparent 60%); }
.skin-parchment .band .you { background: #6b5020; color: #f3e7c8; }
.skin-parchment .pane .list { background: #d8c69a; border-right-color: #a9833c; }
.skin-parchment .pane .list button { background: #e7d8b2; border-color: #b49c6c; color: #2f2113; }
.skin-parchment .pane .list button small { color: #6b5942; }
.skin-parchment .pane .list button.on { background: #c9ae73; border-color: #6b5020; color: #35240c; }
.skin-parchment .pane .detail h3 { color: #4a3209; }
.skin-parchment .pane tbody tr:nth-child(even) td { background: rgba(120,92,48,.10); }
.skin-parchment .pane tr:hover td { background: rgba(120,92,48,.20); }
.skin-parchment .pane td { border-bottom-color: #cbb68f; }
.skin-parchment .pane th { border-bottom-color: #a9915f; }
.skin-parchment .pane tr:hover td { background: #e9d9b3; }
.skin-parchment .pane .list { border-right-color: #b49c6c; }
.skin-parchment .advice { background: #efe2c2; border-color: #8a6a2c; }
.skin-parchment .crest path { stroke: #3a2c18; }

.legend { display: flex; gap: 16px; flex-wrap: wrap; color: var(--ink-dim); font-size: .82rem; margin-top: 14px; }
.legend span b { font-weight: 600; }
"""


# "At 24: quest in Hillsbrad Foothills, and Blackfathom Deeps is the dungeon to run." The
# single sentence somebody wants when they open this screen at all.
def advice(zones, dungeons, level):
    def centre(x):
        return abs((x["lo"] + x["hi"]) / 2 - level)
    here = sorted([z for z in zones if z["lo"] <= level <= z["hi"]], key=lambda z: (centre(z), -z["quests"]))
    runs = sorted([d for d in dungeons if d["lo"] - 2 <= level <= d["hi"]], key=centre)
    zone = here[0]["name"] if here else None
    second = here[1]["name"] if len(here) > 1 else None
    dungeon = runs[0] if runs else None
    bits = []
    if zone:
        bits.append("quest in <b>%s</b>%s" % (esc(zone), (" or <b>%s</b>" % esc(second)) if second else ""))
    if dungeon:
        bits.append("run <b>%s</b> (%d-%d)" % (esc(dungeon["name"]), dungeon["lo"], dungeon["hi"]))
    nxt = sorted([d for d in dungeons if d["lo"] > level], key=lambda d: d["lo"])
    tail = (' Next dungeon: <b>%s</b> at %d.' % (esc(nxt[0]["name"]), nxt[0]["lo"])) if nxt else ""
    return '<div class="advice"><span class="at">At %d</span> %s.%s</div>' % (level, ", ".join(bits), tail)


def band_html(zones, dungeons, level, faction, step=5):
    rows = []
    for lo in range(1, 60, step):
        hi = lo + step - 1
        here = lo <= level <= hi
        z = [x for x in zones if x["lo"] <= hi and x["hi"] >= lo]
        d = [x for x in dungeons if x["lo"] <= hi and x["hi"] >= lo]
        if not z and not d:
            continue
        zp = "".join(
            '<span class="pill">%s<b class="%s">%s</b><span class="range">%d-%d</span></span>' % (
                crest(x["faction"], x["leaning"]), x["kind"], esc(x["name"]), x["lo"], x["hi"]) for x in z)
        dp = "".join(
            '<span class="pill dungeon">%s<b class="%s">%s</b><span class="range">%d-%d</span></span>' % (
                SWORD, x["kind"], esc(x["name"]), x["lo"], x["hi"]) for x in d)
        rows.append(
            '<div class="band%s"><div class="lv">%d-%d<small>%s</small></div><div class="pills">%s%s</div></div>' % (
                " here" if here else "", lo, hi, '<span class="you">you</span>' if here else "level",
                zp, ('<span class="heading">Dungeons</span>' + dp) if dp else ""))
    return "".join(rows)


def road_html(zones, dungeons, level, step=4):
    rows = ['<div class="rail"></div>']
    for lo in range(1, 61, step):
        hi = lo + step - 1
        here = lo <= level <= hi
        left = [x for x in zones if x["lo"] <= hi and x["hi"] >= lo and x["continent"] == "Eastern Kingdoms"]
        right = [x for x in zones if x["lo"] <= hi and x["hi"] >= lo and x["continent"] == "Kalimdor"]
        opens = [x for x in dungeons if lo <= x["lo"] <= hi]
        if not (left or right or opens):
            continue
        def side(items):
            return "".join('<span class="pill">%s<b class="%s">%s</b></span>' % (
                crest(x["faction"], x["leaning"]), x["kind"], esc(x["name"])) for x in items)
        rows.append(
            '<div class="stop%s"><div class="left"><span class="side">%s</span></div>'
            '<div class="mid"><div class="dot"></div><div class="lv">%d</div>%s</div>'
            '<div class="right"><span class="side">%s</span></div></div>' % (
                " here" if here else "", side(left), lo,
                "".join('<span class="dmark">%s %s</span>' % (SWORD, esc(x["name"])) for x in opens),
                side(right)))
    return "".join(rows)


def pane_html(zones, dungeons, level, step=5):
    bands, bodies = [], []
    for lo in range(1, 60, step):
        hi = lo + step - 1
        z = [x for x in zones if x["lo"] <= hi and x["hi"] >= lo]
        d = [x for x in dungeons if x["lo"] <= hi and x["hi"] >= lo]
        if not z and not d:
            continue
        here = lo <= level <= hi
        bands.append('<button class="%s">Level %d-%d<small>%d zones, %d dungeons</small></button>' % (
            "on" if here else "", lo, hi, len(z), len(d)))
        if here:
            zr = "".join(
                '<tr><td>%s <span class="%s">%s</span></td><td class="r">%d-%d</td><td class="r">%s</td>'
                '<td class="r">%d quests</td></tr>' % (
                    crest(x["faction"], x["leaning"]), x["kind"], esc(x["name"]), x["lo"], x["hi"],
                    esc(x["continent"]), x["quests"]) for x in z)
            dr = "".join(
                '<tr><td>%s <span class="%s">%s</span></td><td class="r">%d-%d</td><td class="r">%s</td>'
                '<td class="r">%s</td></tr>' % (
                    SWORD, x["kind"], esc(x["name"]), x["lo"], x["hi"], esc(x["faction"] or "both sides"),
                    ("%d quests" % x["quests"]) if x["quests"] else "—") for x in d)
            bodies.append(
                '<h3>Levels %d to %d</h3><div class="sub">You are %d. Yellow is where you should be now.</div>'
                '<table><tr><th>Zone</th><th class="r">Levels</th><th class="r">Continent</th><th class="r">Quests</th></tr>%s'
                '<tr><th>Dungeon</th><th class="r">Levels</th><th class="r">Side</th><th class="r">Quests</th></tr>%s</table>'
                % (lo, hi, level, zr, dr))
    return '<div class="pane"><div class="list">%s</div><div class="detail">%s</div></div>' % (
        "".join(bands), "".join(bodies) or "<p>Nothing here.</p>")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--level", type=int, default=24)
    parser.add_argument("--faction", default="Horde", choices=["Horde", "Alliance"])
    parser.add_argument("--out", default=os.path.join(os.path.dirname(ROOT), "review", "where-to-level-mockup.html"))
    args = parser.parse_args(argv)

    zones = zone_rows(load("Zones", "Data/Zones.lua"), args.level, args.faction)
    dungeons = dungeon_rows(load("Dungeons", "Data/Dungeons.lua"), args.level, args.faction)

    legend = ('<div class="legend">'
              '<span class="red"><b>red</b> too soon</span><span class="orange"><b>orange</b> nearly</span>'
              '<span class="yellow"><b>yellow</b> go here now</span><span class="green"><b>green</b> running out</span>'
              '<span class="grey"><b>grey</b> behind you</span></div>')

    page = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>Where to level - three ways</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cinzel:wght@500;700&family=Roboto+Condensed:wght@400;600&display=swap">
<style>%s</style></head><body>
<nav class="jump"><a href="#one">1. Level bands</a><a href="#two">2. The road</a><a href="#three">3. Two pane</a><a href="#four">4. Parchment</a>
<span class="who">Mocked at level %d, %s, from the shipped data: %d zones, %d dungeons</span></nav>
<div class="wrap">
<h1 style="color:var(--gold);font-size:1.5rem">Where to level</h1>
<p class="intro">Three ways to show the same thing: <b>where to quest</b> and <b>which dungeon to run</b> at
every level. The colours are the game's own quest-difficulty colours, which every player already reads without
being told: yellow is where you should be, grey is behind you, red is too soon. The crests mark a zone one side
owns, faint where it only leans that way. Nothing here uses Blizzard artwork.</p>

<div class="variant" id="one"><div class="label">Variant 1 &mdash; level bands</div>
<div class="frame"><header><h2>Where to level</h2><span class="sub">You are level %d. Scroll to your band, or let it jump there.</span></header>
<div class="body">%s%s</div></div>
<p class="note"><b>Why it works:</b> one glance, no clicking, and the dungeons sit with the zones they belong
beside instead of in a screen of their own. <b>Why it might not:</b> at five levels a band it is a long page,
and a zone that spans 37-60 shows up in five bands.</p></div>

<div class="variant" id="two"><div class="label">Variant 2 &mdash; the road</div>
<div class="frame"><header><h2>Where to level</h2><span class="sub">Eastern Kingdoms on the left, Kalimdor on the right, dungeons on the road itself.</span></header>
<div class="body"><div class="road">%s</div>%s</div></div>
<p class="note"><b>Why it works:</b> it reads as a journey, which is what levelling is, and the two continents
never get mixed up. <b>Why it might not:</b> it is the least like anything else in the game, and a long zone
list on one side leaves the other looking bare.</p></div>

<div class="variant" id="three"><div class="label">Variant 3 &mdash; two pane, like the quest log <span style="color:var(--gold)">&nbsp;&larr; my pick</span></div>
<div class="frame"><header><h2>Where to level</h2><span class="sub">Bands down the left, the one you are in opened on the right.</span></header>
<div class="body">%s%s%s</div></div>
<p class="note"><b>Why it works:</b> it is the shape of Blizzard's own quest log and character sheet, so it
needs no explaining; the rail down the left is the whole 1-60 ladder at a glance; and there is room for the
detail the other two cannot fit. <b>Why it might not:</b> you only see one band's detail at a time.</p></div>

<div class="variant" id="four"><div class="label">Variant 4 &mdash; the same screen, parchment</div>
<div class="skin-parchment">
<div class="frame"><header><h2>Where to level</h2><span class="sub">Classic's quest log is parchment; its dungeon journal is slate. Both are "Classic-esque".</span></header>
<div class="body">%s%s%s</div></div></div>
<p class="note"><b>Why it works:</b> parchment is what Classic players picture when they picture the quest
log, and the difficulty colours still read on it. <b>Why it might not:</b> every other screen in ForeverBuddy
is dark, so this one would stand alone unless they all change.</p></div>
</div></body></html>""" % (
        STYLE, args.level, args.faction, len(zones), len(dungeons),
        args.level, advice(zones, dungeons, args.level) + band_html(zones, dungeons, args.level, args.faction), legend,
        road_html(zones, dungeons, args.level), legend,
        advice(zones, dungeons, args.level), pane_html(zones, dungeons, args.level), legend,
        advice(zones, dungeons, args.level), pane_html(zones, dungeons, args.level), legend)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(page)
    print("%d zones, %d dungeons -> %s" % (len(zones), len(dungeons), args.out))


if __name__ == "__main__":
    main()
