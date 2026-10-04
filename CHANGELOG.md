# Changelog

## 1.0.1

Built against client 1.60.1.70178.

- **Shopping lists, for every profession.** Open a profession, pick what to make, press Shopping list and say how many. It breaks the recipe down to the things nobody can craft and counts what is already in your bags and bank. The quantity is presses of Create, the same as Blizzard's own box. 2,329 recipes across all 13 professions, and `/fb craft <item> [n]` does the same into chat.
- **A minimap button**, with the addon's own logo on it, which the welcome screen now wears too.
- **Search the ability list.** Type "kidney shot" on a rogue and it tells you the level.
- **Talents are marked.** 135 abilities say so, from Forever's own talent trees, so Trueshot Aura no longer reads as something to buy. Aimed Shot, a talent in Classic, is baseline here and says nothing.
- **Abilities shows the whole ladder, 1 to 60**, instead of guessing what you have learnt, and the data was rebuilt: 1,424 abilities across 9 classes. A class-mask assumption had been throwing away 2,260 rows, which is why Shadow Word: Death was missing along with 39 others. Checked against eleven trainer windows recorded in game.
- **"Where to level" rebuilt as two panes**, like the quest log: a level band on the left, the zones and the dungeons to run on the right, coloured the way the game colours quest difficulty. Zones of one side wear that side's emblem.
- **Ctrl + right click an item in your bags** to mark it as junk to be sold, or to protect a grey you want to keep.
- **City map pins stay under Blizzard's `!` and `?`** rather than covering them.
- Dungeon data went from 22 dungeons to 31, and 299 quests to 306, including the ones Forever has built but not released. Every faction tag audited.

The dungeon journal and `/fb dungeon` are switched off until their quest data is complete. The data is still there and still feeds the levelling screen.

Fixed: a shopping list for two Gyrochronatoms said to make three Gold Power Cores, counting the batch instead of the one press needed; the ability search box lost focus after every keystroke; the open level band's card had no label on it; the panel title ran through the profession name; the line under the abilities heading ran through the search box; the shopping list button sometimes stayed hidden until you switched profession and back; and the list offered leatherworking lessons to people who are not leatherworkers.

## 1.0.0

First public release, built against the World of Warcraft: Forever beta, client 1.60.1.69893.

- **Dungeon journal.** 22 dungeons and 299 quests: who gives each one and where, whether the group can share it, and the chain before it. Faction emblems and colours run the length of a chain, ticks mark what you have finished, and clicking a step points an arrow at the NPC.
- **Abilities.** Every class ability by level to 60, taken from the Forever client rather than Classic, with the price a trainer charges where a player has recorded one.
- **Where to level.** Every zone by level, and a level range written over each zone of a continent map.
- **City maps.** Class trainers, profession trainers, weapon masters, bank, auction house and flight master in all six capitals, each its own switch, each class and profession its own tick.
- **Tooltips.** What quests and recipes need an item, and whether it is safe to vendor.
- **At the vendor.** Auto repair, sell greys, and optionally sell soulbound gear your class cannot use.
- **Quests.** Accept and hand in automatically, with Shift to do it by hand. Off by default.
- **Data recording.** Records what the game shows you into its own file, to fill in what Forever publishes nowhere. Nothing is sent anywhere.

Switched off for this release because they do not work on the beta: item scores on tooltips, equip upgrade prompts, delete warnings, bag icon markers, and lighting a zone up on the map. Each is one constant away from returning.
