# Releasing 1.0.1

Written 4 October 2026, against `f4caa3c`. 1.0.0 went to CurseForge on 28 September as commit
`9d95e96`; everything below is the difference between that and now, which is 28 commits.

---

## 1. Changelog

Paste into the release notes. Ordered by what somebody actually notices.

### New

- **Shopping list, for every profession.** Open a profession, pick a recipe, press **Shopping
  list**, say how many you want to make. It breaks the recipe down to the things nobody can
  craft and counts what is already in your bags and bank. The quantity is presses of Create, so
  2 of a recipe that makes 200 is 400 slugs, not 400 presses. Also `/fb craft <item> [n]` in
  chat, and `/fb craft <item> [n] all` to take every branch apart including the ones you would
  normally just buy.
- **A minimap button**, with the addon's logo on it. Left click opens the window, right click
  goes to the settings.
- **Search the ability list.** Type "kidney shot" on a rogue and it tells you the level.
- **Ctrl + right click an item in your bags** to mark it as junk to be sold, or to protect a
  grey you want to keep.
- **Faction emblems** on the zone list and the whole length of every quest chain.

### Changed

- **Abilities shows the whole ladder, 1 to 60**, instead of guessing what you have learnt. It
  was not noticing level-ups, so it was showing the wrong half of the list.
- **Ability data rebuilt on client 1.60.1.70178**: 1,424 abilities across 9 classes. A class-mask
  assumption had been throwing away 2,260 rows, which is why Shadow Word: Death was missing
  along with 39 others. Checked against eleven trainer windows recorded in game.
- **Talents are marked.** 135 abilities now say `(talent)`, from Forever's own talent trees, so
  Trueshot Aura no longer reads as something you can walk in and buy. Aimed Shot, which is a
  talent in Classic, is baseline here and says nothing.
- **"Where to level" rebuilt as two panes**, like the quest log: a level band on the left, the
  zones and what to run on the right, coloured the way the game colours quest difficulty.
- **Dungeon data**: 31 dungeons and 306 quests, up from 22, including the ones Forever has built
  but not released. Every faction tag audited.
- **City map pins stay under Blizzard's `!` and `?`** instead of covering them.
- **A build from the development repository says nothing on the addon channel** — it does not
  announce versions and does not open the channel to listen, so it cannot reach anybody's chat.

### Removed

- **The dungeon journal and `/fb dungeon` are shelved** until the quest data is complete. The
  data and the code are still there and still feed the levelling screen; this is a switch.
- **"Click to see it on the map"** is gone from the zone list. It never highlighted anything.

### Fixed

- The shopping list counted the batch instead of the presses: asking for two Gyrochronatoms told
  you to make three Gold Power Cores, because a core comes three to a craft and one press was
  the whole job.
- The ability search box lost focus after every keystroke.
- The shopping list offered leatherworking lessons to people who are not leatherworkers, and
  broke Heavy Leather down into Medium Leather when nobody asked.
- The **Shopping list** button appeared on the professions summary page, where there is no
  recipe to shop for.
- A Lua error in the shopping panel was swallowed by our own "hide Lua errors" setting, leaving
  a panel with a title and nothing under it. There is now a lint for the thing that caused it.

---

## 2. Uploading it

The automation is already written. `.github/workflows/release.yml` runs on any `v*` tag: it
installs luajit, runs `sh tests/run.sh` and `python3 -m unittest discover -s tools`, builds the
zip with BigWigsMods/packager and uploads to GitHub Releases plus CurseForge, Wago and
WoWInterface for whichever tokens are set.

**Nothing is wired up yet.** As of `f4caa3c`:

| Needed | State |
|---|---|
| CurseForge project approved | Submitted 28 September, check the dashboard |
| `## X-Curse-Project-ID` in the TOC | **absent** |
| `CF_API_KEY` repository secret | not set as far as this repo shows |
| A `v*` tag | **none exist**, `git tag -l` is empty |
| Version in the TOC | `1.0.1-dev`, needs to lose the `-dev` |

### In order

1. Check the project was approved and copy its numeric **Project ID** from the CurseForge
   dashboard.
2. Add to `ForeverBuddy.toc`, under `## Author`:
   ```
   ## X-Curse-Project-ID: <id>
   ```
3. Create an API token at `authors.curseforge.com` → My API Tokens.
4. Put it in the **private** repo at Settings → Secrets and variables → Actions → New repository
   secret, named `CF_API_KEY`.
5. Set `## Version: 1.0.1` in the TOC and commit.
6. Tag and push:
   ```sh
   git tag -a v1.0.1 -m "v1.0.1" && git push origin v1.0.1
   ```
7. Watch the Actions tab. The packager reads the game version from `## Interface: 11509, 16001`;
   16001 is Forever, which the packager has supported since 17 September 2026.

A tag before 4 October would have failed on the test step — three emitter tests were red on the
shape of their own output. They are green now, both suites.

**If the automation misbehaves**, the manual route still works: build the zip with the same
filter `.pkgmeta` uses (everything except `tests`, `tools`, `docs`, `site`, `.github`,
`.gitignore`, `.pkgmeta`, `*.zip`), one top-level `ForeverBuddy` folder, and upload it as a
**Release** with **Forever** ticked.

### Which repository releases

The public repo `ForeverBuddy-public` still holds 1.0.0. Decide whether the tag goes there or on
the private one before adding the secret, because the secret has to live wherever the tag lands.

---

## 3. What the listing now gets wrong

The listing was written from the README as it stood at 1.0.0. These parts no longer describe the
addon.

### Must come out

| Where | What it says | Why it is wrong |
|---|---|---|
| Description, first feature | **Dungeon journal** — every quest tied to a dungeon, who gives it, the chain before it | Shelved. `UI/Journal.lua` does not register, `/fb dungeon` is not a command. |
| Description, commands | `/fb dungeon` | Not registered. |
| Description, Where to level | "one click to light a zone up on it" | The click and the wording were both removed. The level ranges written over the continent map are still there and still true. |
| Screenshot | `dungeons.jpg`, the dungeon journal | Shows the shelved screen. |
| Screenshot | `chain.jpg`, a dungeon's quest chains | Same. |
| `ForeverBuddy.toc`, `## Notes` | "Dungeon quests, class ability levels, …" | Ships in the addon list in game. Dungeon quests lead a feature that is off. |
| `docs/CURSEFORGE.md` | suggests screenshotting "the dungeon window" | Same reason. |

### Stale rather than wrong

Every screenshot is from 28 September and predates all of it. `abilities.jpg` has no search box
and the old partial ladder; `city-map.jpg` and `world-map.jpg` are still accurate; `welcome.jpg`
is the setup guide, unchanged.

### Missing, and worth adding

- The shopping list, which is the largest thing in this release and has no screenshot at all.
- The minimap button.
- Ctrl + right click to mark junk.
- The ability search, and the `(talent)` marks.
- The two-pane "Where to level".

### Still accurate

Abilities, city maps, tooltips, the vendor automation, the data recorder and everything under
"Where the data comes from", the licence, and the install instructions.
