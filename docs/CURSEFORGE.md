# Getting ForeverBuddy onto CurseForge

Everything needed, in the order it has to happen. The release automation is already written, so most of this is decisions, artwork and one web form.

## Decisions first

- [ ] **Fix the saved-settings bug.** Friends would lose their ticks and their recorded data at every login. Nothing should ship until `/fb collect check` reports the saved file loading.
- [ ] **Pick a licence.** CurseForge requires one on the project. Our quest and dungeon data is derived from Questie's database, which is GPL-3.0. Either license ForeverBuddy as GPL-3.0 and credit Questie, which is what most Classic addons do, or rebuild that data from the game's own tables and what players record, and then license it however we like.
- [ ] **Decide whether to advertise Classic Era.** The code has Era paths and the tests cover them, but nobody has run it on an Era client. Recommended: ship Forever only at first, and add Era once someone tests it.
- [ ] **Decide about the source repository.** Linking GitHub as source and issue tracker means making it public. Nothing personal is in it, but that is a separate call.

## The listing

- [ ] CurseForge account, two-factor enabled, then the author dashboard, Create project, World of Warcraft, Addons.
- [ ] **Name**: must be unique and in English. "ForeverBuddy" gives `curseforge.com/wow/addons/foreverbuddy`.
- [ ] **Summary**: one sentence.
- [ ] **Description**: what it does, the commands, and plainly what the data recorder stores and never stores. No external download links anywhere in it, which CurseForge rejects. Donation links only at the bottom.
- [ ] **Categories**: a primary one, plus any that fit.
- [ ] **Logo**: original artwork, 400 by 400, no Blizzard images.
- [ ] Optional but nice: two or three screenshots, for example the tooltip, the dungeon window and the setup guide.

## The first file

- [ ] Build the zip: one top-level folder named `ForeverBuddy`, no development files.
- [ ] Upload it as a **Release**, with the **Forever** game version selected, and a short changelog.
- [ ] Wait for moderation. A person reviews the first file of every new project, during European office hours, usually the same day.
- [ ] After approval, put the project ID in the TOC: `## X-Curse-Project-ID: <id>`.

## Automatic releases after that

Already built in `.github/workflows/release.yml`.

- [ ] Create a CurseForge API token at authors.curseforge.com and add it to the repository as the secret `CF_API_KEY`.
- [ ] Optional, same idea for other sites: `WAGO_API_TOKEN` for wago.io with `## X-Wago-ID`, `WOWI_API_TOKEN` for WoWInterface with `## X-WoWI-ID`.
- [ ] Release by tagging: `git tag -a v1.0.0 -m "v1.0.0" && git push origin v1.0.0`. The workflow runs the tests, builds the zip and uploads it to GitHub Releases and to every site whose token is set.
- [ ] The packager reads the game version from `## Interface:`. Interface numbers starting 16 mean Forever; support for that was added on 17 September 2026 and our workflow already uses it.

## Getting it to friends before any of that

- [ ] Send them the zip directly, with the install steps from the download page. This works today.
- [ ] Or make the GitHub repository public and use Releases, so they can always grab the newest build themselves.
- [ ] Either way, tell them what the recorder does, and ask for a `/fb collect check` screenshot after their first quest.
