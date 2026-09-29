# ForeverBuddy

A quality-of-life addon for **World of Warcraft: Forever**. Everything is a toggle: the first time you log in it shows a setup window where you tick the features you want, and `/fb` brings that window back any time.

## Features (v0.6.0)

| Feature | What it does | Default |
|---|---|---|
| **Item uses on tooltips** | Hover any item: a verdict line (`KEEP: needed for Pie for Billy`, `All quests done: safe to vendor`, `Crafting reagent (Cooking)`), the quests that need it coloured by your status (green in your log with have/need, yellow not started, blue repeatable, grey done), and the recipes that use it grouped by profession. Hold **Shift** to see everything instead of the first few. Quests already in your log are matched live, so new Forever quests show even before the shipped data knows them. | on |
| **Auto repair** | Repairs all gear at any vendor that can repair, if you can afford it. One chat line with the cost. | on |
| **Sell junk** | Sells grey items automatically at vendors. One chat line with the total. | on |
| **Automate quests** | Accepts quests and hands them in. Hold **Shift** to do it by hand. Quests that cost money are left alone, and rewards you must choose between are always left to you. | off |
| **Item scores on tooltips** | Every piece of gear gets a score for your spec from WoWSims stat weights, and the tooltip shows it next to the score of what you wear (green if better, orange if worse). The spec is guessed from your class; `/fb spec` lists the options and `/fb spec TankWarrior` changes it. | on |
| **Drops on NPC tooltips** | Hover a boss or NPC to see which of its drops would be upgrades for your spec, best first. `/fb loot <dungeon>` lists a whole instance with the boss that drops each item. | on |
| **Sell price on tooltips** | The vendor price on every tooltip, not only while a vendor is open. | on |
| **Delete warnings** | When you destroy an item a quest still needs, the confirmation says which quest. | on |
| **Tooltip IDs** | Item, spell and NPC numbers on tooltips, for bug reports. | off |
| **Alts' items and gold** | Tooltips say how many of an item your other characters and your bank hold. `/fb gold` lists everyone's gold. | on |
| **Bag icon markers** | A quest mark on items a quest still needs, a coin on junk that will be sold, a green arrow on gear that beats what you wear, and the item level on gear. | on |
| **Appearance collected** | On clients with the transmog collection (Forever, not Era): whether you already have an item's look. | on |
| **Sell unusable soulbound gear** | Also sells soulbound uncommon and rare gear your class cannot use, unless a quest needs it or it is on your keep list. | off |
| **Equip upgrade prompts** | When gear you can wear lands in your bags with a higher item level than what you have on, a popup asks whether to equip it. It never equips on its own; "Keep" silences that item for the session; in combat it waits. | on |
| **Map coordinates** | Your position under the minimap, and on the world map your position and the cursor's, to one decimal. | on |
| **Arrow to quest givers** | Click a quest in `/fb dungeon` and an arrow with the distance points to its giver, or to the first prerequisite you still need, or to the turn-in if the quest is in your log. Uses TomTom's arrow when that addon is loaded. `/fb arrow clear` removes it. | with the guide |
| **Help improve the data** | Records what the game shows you into ForeverBuddy's own saved-variables file: items you hover, quests you accept or hand in with giver, place, XP and rewards, loot sources, vendor stock, and where your talent points go. Never chat, keystrokes, other players, account details or combat, and nothing is sent anywhere. `/fb collect` explains and shows counts; `/fb collect off` stops it. `/fb report <text>` saves a note with the target, hovered item, place and quest log attached. Hand the file over and `tools/merge_collected.py` folds it into the data. | on |
| **Dungeon quest guide** | `/fb dungeon` opens a window: dungeons down the left, and for the selected one every quest with your live status, whether it can be shared (Shareable / Not shareable, chain / Not shareable), where to pick it up with zone and coordinates, the chain in front of it, and the turn-in. `/fb dungeon rfc` (or any name) jumps to one; `/fb dungeon list` prints the ones for your level. | window |
| **Zone levels** | `/fb zones` lists the zones that fit your level and faction; `/fb zones 20` does it for any level so you can tell a friend where to go. | command |

## Commands

```
/fb                    open the options checklist
/fb setup              run the guided setup again (it opens by itself on first install)
/fb list               show every feature and whether it is on
/fb <feature> on|off   e.g. /fb autoquest on   (keys: usedfor, itemscore, droptips, sellprice, deletewarn, ids, alts, bagmarks, appearance, autorepair, selljunk, sellunusable, autoquest, autoequip)
/fb info               which item data build is loaded
```

## Install

Copy the `ForeverBuddy` folder into your Forever `Interface/AddOns/` folder (the exact game folder name is confirmed on beta day; for Classic Era it is `_classic_era_`). Reload the UI. The guided setup opens a couple of seconds after you enter the world; `/fb` is the plain checklist afterwards.

## Merging what players recorded

    python3 tools/merge_collected.py ~/Desktop/ForeverAddons/inbox/*.lua

Reads one or more `ForeverBuddy.lua` saved-variables files (from `WTF/Account/<account>/SavedVariables/`), merges everything the collector recorded into `tools/observed/observed.json`, and writes `Data/Observed.lua`, which the addon loads on top of the generated data: quest items it did not know, quest givers with places, loot sources, NPC positions. It also prints the quests, items and reports that were new, for curating into the build scripts.

## Regenerating the dungeon and zone data

    python3 tools/build_dungeons.py

Fetches Questie's Classic quest, NPC, object and item databases into `tools/cache/questie/` and writes `Data/Dungeons.lua` (every quest tied to each dungeon: giver, chain, turn-in, share status) and `Data/Zones.lua` (each zone's level band, from the narrowest span holding 75% of its quests). The matching rules are in the script header. Raids are not included yet.

## Regenerating the item data

`Data/Recipes.lua` and `Data/Quests.lua` are generated. To rebuild for a new client build:

    python3 tools/build_data.py --build 1.15.9.69722

Recipes come from Blizzard's client tables (SpellReagents, SkillLineAbility, SkillLine, SpellEffect, SpellName, ItemSparse) as exported by [wago.tools](https://wago.tools). Quest requirements come from [Questie](https://github.com/Questie/Questie)'s classic quest database. Downloads are cached under `tools/cache/`. Python 3, standard library only.

## Stat weights

`Data/Weights.lua` holds per-spec stat weights for the gear planner, pulled from the open-source [WoWSims](https://github.com/wowsims) simulators (MIT). Rebuild with:

    python3 tools/build_weights.py --game classic      # or sod, tbc, wotlk

Classic weights are the alpha stand-in until a Forever source exists.

`Data/Items.lua` is the item database behind the scores: every equippable Classic item of uncommon quality and up with resolved stats, weapon damage, sources, sets and class locks, from the same WoWSims project. Rebuild with:

    python3 tools/build_items.py --game classic

Items missing from it (greys, whites, random-suffix greens) are scored from the client's own stat data instead.

## Releasing

Releases are automated with the BigWigs packager (`.github/workflows/release.yml`, `.pkgmeta`). Push an annotated tag and the workflow runs the test suite, builds the zip, and uploads it to GitHub Releases and to every site whose token is set as a repository secret:

    git tag -a v0.5.1 -m "v0.5.1"
    git push origin v0.5.1

| Site | Secret | TOC line |
|---|---|---|
| CurseForge | `CF_API_KEY` (authors.curseforge.com → API tokens) | `## X-Curse-Project-ID: <id>` |
| Wago Addons | `WAGO_API_TOKEN` (addons.wago.io → API keys) | `## X-Wago-ID: <id>` |
| WoWInterface | `WOWI_API_TOKEN` | `## X-WoWI-ID: <id>` |
| GitHub Releases | built-in `GITHUB_TOKEN` (needs read-write workflow permissions) | none |

Bump `## Version:` in the TOC before tagging. The game versions the file is tagged with come from `## Interface:`; add Forever's number there on beta day.

## Tests

    sh tests/run.sh                              # Lua units under luajit, run twice: Classic and Mainline fake clients
    python3 -m unittest discover -s tools -v     # data build

## Classic Era test (before the beta)

The item scores and the item database are Classic data, so they can be tried on Classic Era right now: install into `_classic_era_/Interface/AddOns/`, log in, run steps 2, 3, 8 to 14 of the checklist below. Everything else on the list is beta-day only.

## Beta-day checklist (2026-09-17)

See `docs/BETA-DAY.md`. The first hour is about one thing: `/fb collect check` must report WORKING after the first quest before the addon goes to friends. `/fb collect check` prints the client version, which client functions the recorder needs are missing, what it captured from the last item, quest, loot and vendor, and any recorded errors.

## Credits

Quest data derived from Questie. Client tables via wago.tools. Not affiliated with Blizzard Entertainment.

## Shelved for the first release

Five things are written, tested and switched off, because they do not work on the Forever beta.
Each has a `local SHIPPING = false` at the top of its file: nothing registers and nothing hooks
while it is off, so no switch is offered for something that would not work. Their tests register
the feature and install the hooks themselves, so the code does not rot.

| What | File | Why |
|---|---|---|
| Item scores on tooltips | `Gear/Score.lua` | Forever writes spell power as "increases damage and healing done by magical spells and effects by up to N", which the stat reader does not parse |
| Equip upgrade prompts | `Automation/AutoEquip.lua` | judges upgrades by those scores |
| Delete warnings | `Tooltips/DeleteWarn.lua` | the warning never appears on Forever's confirmation |
| Bag icon markers | `Bags/Marks.lua` | the markers do not paint on Forever's bag frames |
| Lighting a zone on the map | `Nav/MapLevels.lua` | the client's highlight art covers the map in grey. Clicking a zone still opens the map at it |
