package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

local ns = Stub.LoadAddon({ "Core.lua", "UsedFor/QuestStatus.lua", "Collect/Collector.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function fresh(on)
  Stub.reset(); printed = {}
  ns.collectLast = {}
  ns.db = { features = { collect = on ~= false } }
  ns.Quests = { [769] = { { 5723, "Testing an Enemy's Strength", "item", false, "H", 0, false } } }
  ns.Dungeons = {}
end

T.run("registers the collect feature, on by default, with the explainer command", function()
  fresh()
  T.eq(ns.featureIndex.collect.name, "Help improve the data")
  SlashCmdList.FOREVERBUDDY("collect")
  T.eq(printed[1], ns.COLLECT_EXPLAINER[1])
  T.truthy(printed[#printed]:find("It is currently ON. recorded so far: 0 items, 0 quests", 1, true), printed[#printed])
  SlashCmdList.FOREVERBUDDY("collect off")
  T.eq(ns.IsFeatureEnabled("collect"), false)
  T.eq(printed[#printed], "data recording off")
end)

T.run("records a hovered item once, with stats and tooltip facts, and prints the notice the first time", function()
  fresh()
  Stub.items[2024] = { name = "Ornate Spyglass", link = "|Hitem:2024|h[Ornate Spyglass]|h", quality = 2, ilvl = 20, equipLoc = "INVTYPE_TRINKET", sellPrice = 1234, classID = 4, subclassID = 0 }
  Stub.itemStats["|Hitem:2024|h[Ornate Spyglass]|h"] = { ITEM_MOD_STAMINA_SHORT = 5 }
  Stub.tooltipLines[2024] = { "Ornate Spyglass", "Binds when picked up", "Unique", "Trinket", "Requires Level 18", "Classes: Warrior, Paladin" }
  GameTooltip:SetHyperlink("item:2024")
  local rec = ns.db.collected.items[2024]
  T.truthy(rec, "item recorded")
  T.eq(rec.name, "Ornate Spyglass"); T.eq(rec.quality, 2); T.eq(rec.ilvl, 20); T.eq(rec.slot, "INVTYPE_TRINKET"); T.eq(rec.sell, 1234)
  T.eq(rec.stats.ITEM_MOD_STAMINA_SHORT, 5)
  T.eq(rec.bind, "pickup"); T.eq(rec.unique, true); T.eq(rec.req, 18); T.eq(rec.classes, "Warrior, Paladin")
  T.truthy(printed[1] and printed[1]:find("recording game data you see", 1, true), "first notice printed")
  local before = #printed
  GameTooltip:SetHyperlink("item:2024")
  T.eq(#printed, before, "no second notice")
  T.eq(ns.db.collected.noticed, true)
end)

T.run("off: nothing is recorded", function()
  fresh(false)
  Stub.items[2024] = { name = "Ornate Spyglass" }
  GameTooltip:SetHyperlink("item:2024")
  T.eq(ns.db.collected, nil)
  Stub.quest = { id = 5723, title = "Testing an Enemy's Strength" }
  Stub.FireEvent("QUEST_DETAIL")
  T.eq(ns.db.collected, nil)
end)

T.run("quest offer, acceptance and turn-in build one record with giver, place, level, objectives, XP and rewards", function()
  fresh()
  Stub.units.npc = { guid = "Creature-0-1-2-3-3442-000001", name = "Rahauro" }
  Stub.position = { map = 88, x = 0.701, y = 0.304, zone = "Thunder Bluff", sub = "Elder Rise" }
  Stub.quest = { id = 5723, title = "Testing an Enemy's Strength", objectives = "Kill 8 Ragefire Troggs and 8 Ragefire Shaman.", xp = 1150 }
  Stub.FireEvent("QUEST_DETAIL")
  local q = ns.db.collected.quests[5723]
  T.eq(q.title, "Testing an Enemy's Strength"); T.eq(q.giver.id, 3442); T.eq(q.giver.name, "Rahauro")
  T.eq(q.where.zone, "Thunder Bluff"); T.eq(q.where.sub, "Elder Rise"); T.eq(q.where.map, 88); T.eq(q.where.x, 70.1); T.eq(q.where.y, 30.4)
  T.eq(q.xp, 1150)
  Stub.questLog = { { title = "Testing an Enemy's Strength", questID = 5723 } }
  Stub.questLevels[5723] = 15
  Stub.pushable[5723] = true
  Stub.objectives[5723] = { { text = "Ragefire Trogg slain: 0/8", type = "monster", numRequired = 8 }, { text = "Ragefire Shaman slain: 0/8", type = "monster", numRequired = 8 } }
  if Stub.mainline then Stub.FireEvent("QUEST_ACCEPTED", 5723) else Stub.FireEvent("QUEST_ACCEPTED", 1, 5723) end
  T.eq(q.level, 15); T.eq(q.shareable, true)
  T.eq(#q.objectives, 2); T.eq(q.objectives[1].need, 8); T.eq(q.objectives[1].type, "monster")
  T.truthy(q.accepted)
  T.eq(printed[#printed] == nil or not printed[#printed]:find("did not know", 1, true), true, "5723 is known to the data, no new-quest line")
  Stub.units.npc = { guid = "Creature-0-1-2-3-3442-000001", name = "Rahauro" }
  Stub.quest = { id = 5723, title = "Testing an Enemy's Strength", xp = 1150, money = 250, rewards = { "|Hitem:2024|h[Ornate Spyglass]|h" }, choices = { "|Hitem:100|h[A]|h", "|Hitem:101|h[B]|h" } }
  Stub.questChoices = 2
  Stub.FireEvent("QUEST_COMPLETE")
  T.eq(q.turnin.id, 3442); T.eq(q.money, 250); T.eq(q.rewards[1], 2024); T.eq(#q.choices, 2); T.eq(q.choices[2], 101)
  T.truthy(q.done)
end)

T.run("accepting a quest the data does not know prints one line saying so", function()
  fresh()
  Stub.questLog = { { title = "A Brand New Forever Quest", questID = 90001 } }
  Stub.quest = { id = 90001, title = "A Brand New Forever Quest" }
  Stub.FireEvent("QUEST_DETAIL")
  if Stub.mainline then Stub.FireEvent("QUEST_ACCEPTED", 90001) else Stub.FireEvent("QUEST_ACCEPTED", 1, 90001) end
  T.eq(printed[#printed], "recorded a quest the database did not know: A Brand New Forever Quest")
end)

T.run("loot sources: item counts per NPC or object", function()
  fresh()
  Stub.position.zone = "Ragefire Chasm"
  Stub.loot = {
    { link = "|Hitem:2024|h[x]|h", sources = { "Creature-0-1-2-3-11520-000001", 1 } },
    { link = "|Hitem:2589|h[Linen]|h", sources = { "Creature-0-1-2-3-11520-000001", 2, "Creature-0-1-2-3-11318-000002", 1 } },
    { link = "|Hitem:3000|h[Chest thing]|h", sources = { "GameObject-0-1-2-3-4-000003", 1 } },
  }
  T.eq(ns.CollectLoot(), 4)
  local c = ns.db.collected
  T.eq(c.loot["npc:11520"].items[2024], 1); T.eq(c.loot["npc:11520"].items[2589], 2); T.eq(c.loot["npc:11318"].items[2589], 1)
  T.eq(c.loot["obj:4"].items[3000], 1); T.eq(c.loot["npc:11520"].zone, "Ragefire Chasm")
  ns.CollectLoot()
  T.eq(c.loot["npc:11520"].items[2024], 2, "counts add up over openings")
end)

T.run("vendors: stock with prices, repair flag, place", function()
  fresh()
  Stub.units.npc = { guid = "Creature-0-1-2-3-3488-000001", name = "Mahu" }
  Stub.canRepair = true
  Stub.merchant = { { link = "|Hitem:159|h[Refreshing Spring Water]|h", price = 25, name = "Refreshing Spring Water" }, { link = "|Hitem:4540|h[Tough Hunk of Bread]|h", price = 25, name = "Tough Hunk of Bread" } }
  Stub.FireEvent("MERCHANT_SHOW")
  local v = ns.db.collected.vendors[3488]
  T.eq(v.name, "Mahu"); T.eq(v.repair, true); T.eq(v.items[159], 25); T.eq(v.items[4540], 25); T.eq(v.zone, "Nowhere")
end)

T.run("talents: snapshot on login, then every new point is logged with the level it went in at", function()
  fresh()
  Stub.level = 10
  Stub.talents = { { name = "Arms", talents = { { name = "Improved Heroic Strike", tier = 1, column = 1, rank = 0, maxRank = 3 }, { name = "Deflection", tier = 1, column = 2, rank = 0, maxRank = 5 } } },
                   { name = "Fury", talents = { { name = "Cruelty", tier = 1, column = 3, rank = 0, maxRank = 5 } } } }
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  local rec = ns.db.collected.talents["Tester-Realm"]
  T.truthy(rec); T.eq(rec.class, "WARRIOR"); T.eq(#rec.tabs, 2); T.eq(rec.tabs[1].talents[2].name, "Deflection"); T.eq(#rec.order, 0)
  Stub.talents[2].talents[1].rank = 1
  Stub.FireEvent("CHARACTER_POINTS_CHANGED")
  T.eq(#rec.order, 1); T.eq(rec.order[1].name, "Cruelty"); T.eq(rec.order[1].level, 10); T.eq(rec.order[1].rank, 1); T.eq(rec.order[1].tab, 2)
  Stub.level = 12
  Stub.talents[2].talents[1].rank = 3
  Stub.FireEvent("PLAYER_TALENT_UPDATE")
  T.eq(#rec.order, 3); T.eq(rec.order[3].level, 12); T.eq(rec.order[3].rank, 3)
end)

T.run("no talent API (a client without the old tree functions): nothing breaks", function()
  fresh()
  Stub.talents = nil
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  T.eq(next(ns.db.collected.talents), nil)
end)

T.run("/fb report saves the note with target, item, place and quest log", function()
  fresh()
  Stub.units.target = { guid = "Creature-0-1-2-3-11517-000001", name = "Oggleflint" }
  Stub.questLog = { { title = "Header", isHeader = true }, { title = "Testing an Enemy's Strength", questID = 5723 } }
  Stub.items[2024] = { name = "Ornate Spyglass", link = "|Hitem:2024|h[Ornate Spyglass]|h" }
  GameTooltip:SetHyperlink("item:2024"); GameTooltip:Show()
  SlashCmdList.FOREVERBUDDY("report this boss should be listed for rfc")
  local r = ns.db.collected.reports[1]
  T.eq(r.text, "this boss should be listed for rfc"); T.eq(r.target.id, 11517); T.eq(r.target.name, "Oggleflint")
  T.eq(r.item, "|Hitem:2024|h[Ornate Spyglass]|h"); T.eq(r.quests[1], 5723); T.eq(#r.quests, 1); T.eq(r.where.zone, "Nowhere"); T.eq(r.char, "Tester-Realm")
  T.eq(printed[#printed], "report saved with target Oggleflint, item |Hitem:2024|h[Ornate Spyglass]|h, Nowhere. Thank you.")
  printed = {}
  SlashCmdList.FOREVERBUDDY("report")
  T.truthy(printed[1]:find("usage: /fb report", 1, true))
  SlashCmdList.FOREVERBUDDY("collect stats")
  T.eq(printed[#printed], "recorded so far: 1 items, 0 quests, 0 NPCs, 0 loot sources, 0 vendors, 0 characters' talents, 1 reports")
end)

T.run("unit tooltips record the NPC's name and the player's position once", function()
  fresh()
  Stub.position = { map = 1, x = 0.4, y = 0.6, zone = "Durotar", sub = "" }
  _G.GameTooltipTextLeft1 = { GetText = function() return "Sarkoth" end }
  Stub.ShowUnitTooltip(GameTooltip, "Creature-0-1-2-3-3281-000001")
  local n = ns.db.collected.npcs[3281]
  T.eq(n.name, "Sarkoth"); T.eq(n.zone, "Durotar"); T.eq(n.x, 40); T.eq(n.y, 60)
end)

T.run("observed data: quest items are added to the generated data once, and the known-quest set sees them", function()
  fresh()
  ns.Quests = { [769] = { { 5723, "Testing an Enemy's Strength", "objective", false, "H", 0, false } } }
  ns.Observed = { questItems = { [769] = { { 5723, "Testing an Enemy's Strength" }, { 90001, "A Brand New Forever Quest" } }, [2589] = { { 90002, "Linen Run" } } }, quests = { [90003] = { title = "Seen once" } }, loot = {}, npcs = {} }
  T.eq(ns.ApplyObserved(), 2)
  T.eq(#ns.Quests[769], 2); T.eq(ns.Quests[769][2][1], 90001); T.eq(ns.Quests[769][2][5], false, "either faction")
  T.eq(ns.Quests[2589][1][2], "Linen Run")
  T.eq(ns.ApplyObserved(), 0, "second application adds nothing")
  T.eq(ns.IsKnownQuest(90001), true); T.eq(ns.IsKnownQuest(90003), true); T.eq(ns.IsKnownQuest(90009), false)
end)

local function lineStarting(lines, prefix)
  for _, l in ipairs(lines) do if l:sub(1, #prefix) == prefix then return l end end
  return nil
end

T.run("check reports whether the game handed back the saved file", function()
  fresh()
  ns.savedLoaded, ns.savedSummary = true, "2 features set, 45 quests and 131 items recorded, setup done"
  local lines, result = ns.CollectCheck()
  T.eq(lineStarting(lines, "saved file"), "saved file: loaded at login with 2 features set, 45 quests and 131 items recorded, setup done.")
  ns.savedLoaded, ns.savedSummary = false, "nothing"
  lines, result = ns.CollectCheck()
  T.truthy(lineStarting(lines, "saved file: NOT loaded at login"))
  T.eq(result, "problems", "a file that never loads is a problem worth reporting")
  T.truthy(lines[#lines]:find("the saved file was not loaded at login", 1, true))
  ns.savedLoaded, ns.savedSummary = true, "nothing"
end)

T.run("check on a fresh install: client line, all APIs present, nothing recorded yet", function()
  fresh()
  ns.savedLoaded, ns.savedSummary = true, "nothing"
  local lines, result = ns.CollectCheck()
  T.eq(result, "untested")
  if Stub.mainline then
    T.eq(lines[1], "client 12.1.5 build 69999, interface 120105. Recording is ON.")
  else
    T.eq(lines[1], "client 1.15.9 build 69722, interface 11509. Recording is ON.")
  end
  T.eq(lineStarting(lines, "APIs:"), "APIs: everything the recorder uses exists on this client.")
  T.eq(lineStarting(lines, "item:"), "item: nothing yet. Hover any item in your bags.")
  T.eq(lineStarting(lines, "quest:"), "quest: nothing yet. Talk to a quest giver and accept a quest.")
  T.eq(lines[#lines], "RESULT: nothing recorded yet. Hover an item and accept a quest, then run /fb collect check again.")
  T.eq(ns.db.collected.client.interface, Stub.mainline and 120105 or 11509, "client info is kept in the file")
end)

T.run("check after the first quest: item and quest OK, loot and vendors still untested", function()
  fresh()
  Stub.items[2024] = { name = "Ornate Spyglass", link = "|Hitem:2024|h[Ornate Spyglass]|h", sellPrice = 1234 }
  GameTooltip:SetHyperlink("item:2024")
  Stub.units.npc = { guid = "Creature-0-1-2-3-3442-000001", name = "Rahauro" }
  Stub.position = { map = 1456, x = 0.701, y = 0.295, zone = "Thunder Bluff", sub = "" }
  Stub.quest = { id = 5723, title = "Testing an Enemy's Strength", xp = 1150 }
  Stub.FireEvent("QUEST_DETAIL")
  Stub.questLog = { { title = "Testing an Enemy's Strength", questID = 5723 } }
  Stub.questLevels[5723] = 15; Stub.pushable[5723] = true
  Stub.objectives[5723] = { { text = "Ragefire Trogg slain: 0/8", type = "monster", numRequired = 8 } }
  if Stub.mainline then Stub.FireEvent("QUEST_ACCEPTED", 5723) else Stub.FireEvent("QUEST_ACCEPTED", 1, 5723) end
  local lines, result = ns.CollectCheck()
  T.eq(result, "working")
  T.eq(lineStarting(lines, "item"), "item OK: Ornate Spyglass (2024), stats none, sell price 1234.")
  T.eq(lineStarting(lines, "quest"), "quest OK: Testing an Enemy's Strength (5723): giver Rahauro (3442) at Thunder Bluff 70.1, 29.5, level 15, xp 1150, shareable yes, 1 objectives, handed in not yet.")
  T.eq(lineStarting(lines, "loot"), "loot: nothing yet. Kill a mob and loot it.")
  T.eq(lines[#lines], "RESULT: WORKING. Not tested yet: loot, vendors.")
  printed = {}
  SlashCmdList.FOREVERBUDDY("collect check")
  T.eq(printed[#printed], "check: RESULT: WORKING. Not tested yet: loot, vendors.")
end)

T.run("check finds the latest quest from the file after a reload, and flags a quest with no level", function()
  fresh()
  ns.db.collected = { version = 1, items = {}, npcs = {}, loot = {}, vendors = {}, talents = {}, reports = {},
    quests = { [1] = { title = "Old", accepted = 100, level = 5, where = { zone = "Durotar" } }, [2] = { title = "New", accepted = 200, where = { zone = "Durotar" } } } }
  local lines, result = ns.CollectCheck()
  T.eq(result, "problems")
  T.truthy(lineStarting(lines, "quest PROBLEM: New (2)"), "latest quest picked")
  T.truthy(lineStarting(lines, "quest note: no giver recorded"))
  T.eq(lines[#lines], "RESULT: PROBLEMS: quest no level. Screenshot these lines and send them.")
end)

T.run("check names a missing client function and what it stops", function()
  fresh()
  local saved, savedDead = GetLootSourceInfo, UnitIsDead
  GetLootSourceInfo = nil
  local lines, result = ns.CollectCheck()
  T.eq(lineStarting(lines, "APIs:"), "APIs: everything the recorder uses exists on this client.", "the dead-target fallback covers a missing GetLootSourceInfo")
  UnitIsDead = nil
  lines, result = ns.CollectCheck()
  GetLootSourceInfo, UnitIsDead = saved, savedDead
  T.eq(lineStarting(lines, "APIs:"), "APIs: MISSING GetLootSourceInfo or UnitIsDead, so loot sources will not be recorded.")
  T.eq(result, "problems")
  local savedTabs, savedTraits = GetNumTalentTabs, C_Traits
  GetNumTalentTabs = nil
  lines = ns.CollectCheck()
  T.eq(lineStarting(lines, "APIs:"), "APIs: everything the recorder uses exists on this client.", "the trait tree covers missing classic talent functions")
  C_Traits = nil
  lines, result = ns.CollectCheck()
  GetNumTalentTabs, C_Traits = savedTabs, savedTraits
  T.eq(lineStarting(lines, "APIs:"), "APIs: MISSING GetNumTalentTabs or C_Traits.GetTreeNodes, so talent order will not be recorded.")
  T.eq(result, "untested", "talent order alone is not a blocking problem")
end)

T.run("errors: printed once per kind, counted in the file, and shown by check", function()
  fresh()
  local savedEntries = ns.NumQuestLogEntries
  ns.NumQuestLogEntries = function() error("boom") end
  if Stub.mainline then Stub.FireEvent("QUEST_ACCEPTED", 7) else Stub.FireEvent("QUEST_ACCEPTED", 1, 7) end
  if Stub.mainline then Stub.FireEvent("QUEST_ACCEPTED", 8) else Stub.FireEvent("QUEST_ACCEPTED", 1, 8) end
  ns.NumQuestLogEntries = savedEntries
  local shown = 0
  for _, p in ipairs(printed) do if p:find("data recording error in QUEST_ACCEPTED", 1, true) then shown = shown + 1 end end
  T.eq(shown, 1)
  T.eq(ns.db.collected.errors.QUEST_ACCEPTED.count, 2)
  local lines, result = ns.CollectCheck()
  T.eq(result, "problems")
  T.truthy(lineStarting(lines, "ERROR in QUEST_ACCEPTED (x2):"))
  T.truthy(lines[#lines]:find("errors in QUEST_ACCEPTED", 1, true))
end)

T.run("a quest offered by an object records the object as the giver", function()
  fresh()
  Stub.units.npc = { guid = "GameObject-0-1-2-3-35251-000001", name = "Wanted Poster" }
  Stub.quest = { id = 176, title = "Wanted: \"Hogger\"" }
  Stub.FireEvent("QUEST_DETAIL")
  local q = ns.db.collected.quests[176]
  T.eq(q.giver.id, 35251); T.eq(q.giver.object, true); T.eq(q.giver.name, "Wanted Poster")
end)

T.run("check with recording off or settings missing says so", function()
  fresh(false)
  local lines, result = ns.CollectCheck()
  T.eq(result, "problems")
  T.truthy(lines[#lines]:find("recording is off (/fb collect on)", 1, true))
  ns.db = nil
  lines, result = ns.CollectCheck()
  T.eq(lines[#lines], "RESULT: settings are not loaded, so nothing can be recorded. Is the addon folder named ForeverBuddy?")
end)

local function foreverTree()
  return {
    configID = 7001, treeID = 850, specGroup = 1,
    groups = { { groupID = 21, displayName = "Fury", orderIndex = 1 }, { groupID = 20, displayName = "Arms", orderIndex = 0 } },
    nodes = {
      [101] = { ID = 101, posX = 300, posY = 1200, activeRank = 0, maxRanks = 3, entryIDs = { 501 }, groupIDs = { 20 }, isVisible = true },
      [102] = { ID = 102, posX = 600, posY = 1200, activeRank = 0, maxRanks = 5, entryIDs = { 502 }, groupIDs = { 20 }, isVisible = true },
      [201] = { ID = 201, posX = 300, posY = 1200, activeRank = 0, maxRanks = 5, entryIDs = { 601 }, groupIDs = { 21 }, isVisible = true },
      [301] = { ID = 301, posX = 0, posY = 0, activeRank = 0, maxRanks = 1, entryIDs = { 701 }, groupIDs = { 99 }, isVisible = true },
      [302] = { ID = 0 },
    },
    entries = { [501] = { definitionID = 9001 }, [502] = { definitionID = 9002 }, [601] = { definitionID = 9003 }, [701] = { definitionID = 9004 } },
    defs = { [9001] = { spellID = 12282 }, [9002] = { spellID = 16462 }, [9003] = { spellID = 12320 }, [9004] = { spellID = 0, overrideName = "Weaponmaster" } },
    spells = { [12282] = "Improved Heroic Strike", [16462] = "Deflection", [12320] = "Cruelty" },
  }
end

T.run("Forever talents: reads the trait tree grouped into the class trees, then logs points with their level", function()
  fresh()
  Stub.talents = nil
  Stub.traits = foreverTree()
  Stub.level = 10
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  local rec = ns.db.collected.talents["Tester-Realm"]
  T.truthy(rec, "snapshot taken")
  T.eq(rec.configID, 7001)
  T.eq(#rec.tabs, 3, "Arms, Fury, and Other for a node outside the groups")
  T.eq(rec.tabs[1].name, "Arms"); T.eq(rec.tabs[2].name, "Fury"); T.eq(rec.tabs[3].name, "Other")
  T.eq(rec.tabs[1].talents[101].name, "Improved Heroic Strike"); T.eq(rec.tabs[1].talents[101].maxRank, 3); T.eq(rec.tabs[1].talents[101].spell, 12282)
  T.eq(rec.tabs[3].talents[301].name, "Weaponmaster", "override name used when present")
  T.eq(rec.tabs[1].talents[302], nil, "nodes with ID 0 are skipped")
  T.eq(#rec.order, 0)
  Stub.traits.nodes[201].activeRank = 2
  Stub.FireEvent("TRAIT_CONFIG_UPDATED", 7001)
  T.eq(#rec.order, 2); T.eq(rec.order[1].name, "Cruelty"); T.eq(rec.order[1].rank, 1); T.eq(rec.order[2].rank, 2); T.eq(rec.order[2].level, 10); T.eq(rec.order[2].tab, 2)
  Stub.level = 11
  Stub.traits.nodes[101].activeRank = 1
  Stub.FireEvent("PLAYER_TALENT_UPDATE")
  T.eq(#rec.order, 3); T.eq(rec.order[3].name, "Improved Heroic Strike"); T.eq(rec.order[3].level, 11)
  local lines = ns.CollectCheck()
  T.eq(lineStarting(lines, "talents OK"), "talents OK: 3 trees, 4 talents read, 3 points logged.")
end)

T.run("Forever talents: switching spec group takes a new baseline instead of logging the other build as spent points", function()
  fresh()
  Stub.talents = nil
  Stub.traits = foreverTree()
  Stub.traits.configs = { [1] = 7001, [2] = 7002 }
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  local rec = ns.db.collected.talents["Tester-Realm"]
  Stub.traits.specGroup = 2
  Stub.traits.nodes[102].activeRank = 5
  Stub.FireEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
  T.eq(#rec.order, 0, "the second spec's existing points are not logged")
  T.eq(rec.configID, 7002)
end)

T.run("loot without GetLootSourceInfo: items are credited to the dead target, marked as a guess; item loot is skipped", function()
  fresh()
  local saved = GetLootSourceInfo
  GetLootSourceInfo = nil
  Stub.units.target = { guid = "Creature-0-1-2-3-3100-000009", name = "Mottled Boar" }
  Stub.targetDead = true
  Stub.loot = { { link = "|Hitem:769|h[Chunk of Boar Meat]|h", sources = {} }, { link = "|Hitem:2589|h[Linen Cloth]|h", sources = {} } }
  Stub.lootSlots = { [1] = 1, [2] = 3 }
  T.eq(ns.CollectLoot(false), 2)
  local src = ns.db.collected.loot["npc:3100"]
  T.eq(src.items[769], 1); T.eq(src.items[2589], 3); T.eq(src.fromTarget, true)
  T.truthy(lineStarting(ns.CollectCheck(), "loot OK: 2 items from npc:3100 (credited to the dead mob you looted"))
  T.eq(ns.CollectLoot(true), 0, "loot from an item (a clam) has no creature to credit")
  Stub.targetDead = false
  T.eq(ns.CollectLoot(false), 0, "no dead target, no guess")
  Stub.units.mouseover = { guid = "Creature-0-1-2-3-3101-000010", name = "Elder Mottled Boar" }
  Stub.deadUnits.mouseover = true
  T.eq(ns.CollectLoot(false), 2, "right-click looting: the dead mob under the mouse")
  T.eq(ns.db.collected.loot["npc:3101"].items[769], 1)
  Stub.deadUnits.mouseover = nil
  Stub.units.softinteract = { guid = "Creature-0-1-2-3-3102-000011", name = "Bristleback Quilboar" }
  Stub.deadUnits.softinteract = true
  T.eq(ns.CollectLoot(false), 2, "interact key: the dead soft-interact target")
  T.eq(ns.db.collected.loot["npc:3102"].items[2589], 3)
  GetLootSourceInfo = saved
end)

T.run("secret values from unit functions are skipped, not stored and not an error", function()
  fresh()
  local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
  issecretvalue = function(v) return v == SECRET end
  local savedGUID, savedName = UnitGUID, UnitName
  UnitGUID = function(unit) return SECRET end
  Stub.quest = { id = 5723, title = "Testing an Enemy's Strength" }
  Stub.FireEvent("QUEST_DETAIL")
  local q = ns.db.collected.quests[5723]
  T.eq(q.giver, nil, "no giver from a secret GUID")
  T.eq(next(ns.db.collected.errors), nil, "no error recorded")
  UnitGUID = function(unit) return "Creature-0-1-2-3-3442-000001" end
  UnitName = function(unit) return SECRET end
  Stub.FireEvent("QUEST_DETAIL")
  T.eq(q.giver.id, 3442); T.eq(q.giver.name, nil, "a secret name is left out")
  UnitGUID, UnitName, issecretvalue = savedGUID, savedName, nil
end)

T.run("with quest automation on, the title and giver still come from the quest log and the target", function()
  fresh()
  -- the quest window is already gone: no GetQuestID, no GetTitleText
  Stub.quest = {}
  Stub.units.target = { guid = "Creature-0-1-2-3-1569-000001", name = "Shadow Priest Sarvis" }
  Stub.position = { map = 1420, x = 0.309, y = 0.662, zone = "Tirisfal Glades", sub = "Deathknell" }
  Stub.questLog = { { title = "Rude Awakening", questID = 363 } }
  Stub.questLevels[363] = 1
  if Stub.mainline then Stub.FireEvent("QUEST_ACCEPTED", 363) else Stub.FireEvent("QUEST_ACCEPTED", 1, 363) end
  local q = ns.db.collected.quests[363]
  T.eq(q.title, "Rude Awakening"); T.eq(q.level, 1)
  T.eq(q.giver.id, 1569); T.eq(q.giver.name, "Shadow Priest Sarvis")
  T.eq(q.where.zone, "Tirisfal Glades"); T.eq(q.where.sub, "Deathknell")
end)

T.run("the turn-in event records the rewards and who took the quest, without the window", function()
  fresh()
  Stub.quest = {}
  Stub.questLog = { { title = "Rude Awakening", questID = 363 } }
  Stub.units.target = { guid = "Creature-0-1-2-3-2123-000002", name = "Dark Cleric Duesten" }
  Stub.position = { map = 1420, x = 0.311, y = 0.661, zone = "Tirisfal Glades", sub = "Deathknell" }
  Stub.FireEvent("QUEST_TURNED_IN", 363, 40, 150)
  local q = ns.db.collected.quests[363]
  T.eq(q.title, "Rude Awakening"); T.eq(q.xp, 40); T.eq(q.money, 150)
  T.eq(q.turnin.id, 2123); T.eq(q.turnin.name, "Dark Cleric Duesten")
  T.eq(q.turninWhere.sub, "Deathknell")
  T.truthy(q.done)
  local line = lineStarting(ns.CollectCheck(), "quest ")
  T.truthy(line and line:find("Rude Awakening (363)", 1, true), tostring(line))
  T.truthy(line and line:find("handed in yes", 1, true), "the check shows it was handed in")
end)

T.run("the quest giver is remembered from the gossip window when automation closes it", function()
  fresh()
  Stub.units.npc = { guid = "Creature-0-1-2-3-1569-000001", name = "Shadow Priest Sarvis" }
  Stub.FireEvent("GOSSIP_SHOW")           -- we saw who we were talking to
  Stub.units.npc = nil; Stub.units.target = nil  -- the window is gone by the time the quest is accepted
  Stub.questLog = { { title = "Rude Awakening", questID = 363 } }
  if Stub.mainline then Stub.FireEvent("QUEST_ACCEPTED", 363) else Stub.FireEvent("QUEST_ACCEPTED", 1, 363) end
  local q = ns.db.collected.quests[363]
  T.eq(q.giver.id, 1569); T.eq(q.giver.name, "Shadow Priest Sarvis")
  Stub.FireEvent("QUEST_TURNED_IN", 363, 40, 0)
  T.eq(q.turnin.id, 1569, "the same NPC is used for the turn-in when nothing else is known")
end)

T.finish()