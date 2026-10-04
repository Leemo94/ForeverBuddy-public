package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

local FILES = { "Core.lua", "UsedFor/QuestStatus.lua", "Nav/Arrow.lua", "UI/Window.lua", "UI/Home.lua", "UI/Journal.lua", "UI/Settings.lua", "Dungeons/Guide.lua", "Dungeons/Zones.lua" }
local ns = Stub.LoadAddon(FILES)
-- Shelved for now, so the tests register the screen and the command themselves: the code is
-- meant to keep working while it waits for the quest data to catch up.
ns.RegisterJournalScreen()
ns.RegisterDungeonCommand()
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local TB = { name = "Rahauro", where = "Thunder Bluff", map = 1456, x = 70, y = 30, kind = "npc" }
local THRALL = { name = "Thrall", where = "Orgrimmar", map = 1454, x = 32, y = 38, kind = "npc" }
local MAUR = { name = "Maur Grimtotem", where = "Ragefire Chasm", map = 213, x = false, y = false, kind = "npc" }
local JORDAN = { name = "Jordan Stilwell", where = "Dun Morogh", x = 52, y = 37, kind = "npc" }

local function fixtures()
  ns.Dungeons = {
    { key = "ragefirechasm", name = "Ragefire Chasm", zone = 2437, level = { 13, 18 }, faction = "Horde", screen = 131862, aliases = { "rfc", "ragefire" }, quests = {
      { id = 5723, name = "Testing an Enemy's Strength", level = 15, req = 9, faction = "Horde", classes = 0, share = "yes", repeatable = false, inside = false, giver = TB, turnin = TB, pre = {} },
      { id = 5728, name = "Hidden Enemies", level = 16, req = 9, faction = "Horde", classes = 0, share = "yes", repeatable = false, inside = false, giver = THRALL, turnin = THRALL,
        pre = { { id = 5726, name = "Hidden Enemies", faction = "Horde", giver = THRALL },
                { id = 5727, name = "Hidden Enemies", faction = "Horde", giver = THRALL } } },
      { id = 5724, name = "Returning the Lost Satchel", level = 16, req = 9, faction = "Horde", classes = 0, share = "chain", repeatable = false, inside = "start", giver = MAUR, turnin = TB,
        pre = { { id = 5722, name = "Searching for the Lost Satchel", giver = TB } } },
    } },
    { key = "wailingcaverns", name = "Wailing Caverns", zone = 718, level = { 17, 24 }, faction = false, screen = 131882, aliases = { "wc", "wailing" }, quests = {
      { id = 3, name = "The Glowing Shard", level = 26, req = 20, faction = false, classes = 0, share = "single", repeatable = false, inside = false,
        giver = { name = "Glowing Shard", where = false, x = false, y = false, kind = "item" }, turnin = { name = "Falla Sagewind", where = "The Barrens", x = 47, y = 36, kind = "npc" }, pre = {} },
      { id = 4, name = "Deviate Hides", level = 17, req = 12, faction = false, classes = 0, share = "yes", repeatable = false, inside = false, giver = { name = "Nalpak", where = "The Barrens", x = 46, y = 36, kind = "npc" }, turnin = { name = "Nalpak", where = "The Barrens", x = 46, y = 36, kind = "npc" }, pre = {} },
    } },
    { key = "deadmines", name = "The Deadmines", zone = 1581, level = { 17, 26 }, faction = false, aliases = { "dm", "vc", "deadmines" }, quests = {
      { id = 1651, name = "The Test of Righteousness", level = 22, req = 20, faction = "Alliance", classes = 2, share = "chain", repeatable = false, inside = false, giver = JORDAN, turnin = JORDAN,
        pre = { { id = 1, name = "The Tome of Valor", giver = JORDAN }, { id = 2, name = "The Tome of Valor", giver = JORDAN } } },
      { id = 166, name = "The Defias Brotherhood", level = 22, req = 14, faction = "Alliance", classes = 0, share = "yes", repeatable = false, inside = false,
        giver = { name = "Gryan Stoutmantle", where = "Westfall", x = 56, y = 48, kind = "npc" }, turnin = { name = "Gryan Stoutmantle", where = "Westfall", x = 56, y = 48, kind = "npc" }, pre = {} },
    } },
    { key = "stockade", name = "The Stockade", zone = 717, level = { 22, 30 }, faction = "Alliance", aliases = { "stocks" }, quests = {} },
  }
  ns.QuestRewards = { [5723] = { { 6193, "Stormpike Bracers", 2, 19 } } }
  ns.Zones = {
    { zone = 14, name = "Durotar", continent = "Kalimdor", level = { 4, 12 }, quests = 40, faction = "Horde" },
    { zone = 12, name = "Elwynn Forest", continent = "Eastern Kingdoms", level = { 5, 10 }, quests = 46, faction = "Alliance" },
    { zone = 17, name = "The Barrens", continent = "Kalimdor", level = { 10, 22 }, quests = 96, faction = "Horde", leaning = false, alliance = 3, horde = 76 },
    { zone = 406, name = "Stonetalon Mountains", continent = "Kalimdor", level = { 18, 26 }, quests = 46, faction = "Horde", leaning = true, alliance = 17, horde = 23 },
    { zone = 331, name = "Ashenvale", continent = "Kalimdor", level = { 20, 30 }, quests = 70, faction = "Alliance" },
    { zone = 267, name = "Hillsbrad Foothills", continent = "Eastern Kingdoms", level = { 24, 37 }, quests = 53, faction = "Horde" },
  }
end

local function fresh(level, faction, classToken)
  Stub.reset(); printed = {}
  Stub.level = level or 16
  Stub.faction = faction or "Horde"
  Stub.classToken = classToken or "WARRIOR"
  fixtures()
end

T.run("FindDungeon matches keys, aliases and name fragments", function()
  fresh()
  T.eq(ns.FindDungeon("rfc").name, "Ragefire Chasm")
  T.eq(ns.FindDungeon("Ragefire Chasm").name, "Ragefire Chasm")
  T.eq(ns.FindDungeon("dead").name, "The Deadmines")
  T.eq(ns.FindDungeon("VC").name, "The Deadmines")
  T.eq(ns.FindDungeon("wailing caverns").name, "Wailing Caverns")
  T.eq(ns.FindDungeon("nowhere"), nil)
  T.eq(ns.FindDungeon(""), nil)
end)

T.run("DungeonForLevel fits the band, respects the entrance faction, and breaks ties by centre", function()
  fresh()
  T.eq(ns.DungeonForLevel(15, "Horde").name, "Ragefire Chasm")
  T.eq(ns.DungeonForLevel(15, "Alliance").name, "Wailing Caverns", "RFC is Horde-only; WC and DM both 2 away, WC centre is closer")
  T.eq(ns.DungeonForLevel(25, "Alliance").name, "The Stockade", "DM centre 21.5 vs Stockade 26")
  T.eq(ns.DungeonForLevel(25, "Horde").name, "The Deadmines")
  T.eq(#ns.DungeonsForLevel(20, "Horde"), 3, "RFC (2 away), WC, DM")
  T.eq(#ns.DungeonsForLevel(20, "Alliance"), 3, "WC, DM, Stockade (2 away)")
end)

T.run("CanTakeQuest checks faction and class", function()
  fresh(22, "Horde", "WARRIOR")
  local rfc = ns.Dungeons[1].quests[1]
  local pally = ns.Dungeons[3].quests[1]
  T.eq(ns.CanTakeQuest(rfc), true)
  T.eq(ns.CanTakeQuest(pally), false, "Alliance quest for a Horde character")
  Stub.faction = "Alliance"
  T.eq(ns.CanTakeQuest(pally), false, "paladin-only quest for a warrior")
  Stub.classToken = "PALADIN"
  T.eq(ns.CanTakeQuest(pally), true)
  T.eq(ns.CanTakeQuest(rfc), false)
end)

T.run("quest lines: share tag, pick-up, collapsed chain, turn-in, item start", function()
  fresh()
  local title, details = ns.DungeonQuestLines(ns.Dungeons[1].quests[2], "available")
  T.eq(title, "[16] Hidden Enemies")
  T.eq(details[1], "Shareable")
  T.eq(details[2], "Pick up: Thrall, Orgrimmar (32.0, 38.0)")
  T.eq(details[3], "Before it: Hidden Enemies (2 parts) from Thrall, Orgrimmar (32.0, 38.0)")
  T.eq(details[4], nil, "turn-in equals the giver, so no line")
  title, details = ns.DungeonQuestLines(ns.Dungeons[1].quests[3], "active")
  T.eq(title, "[16] Returning the Lost Satchel - in your log")
  T.eq(details[1], "Not shareable (chain)")
  T.eq(details[2], "Pick up: Maur Grimtotem, Ragefire Chasm")
  T.eq(details[3], "Before it: Searching for the Lost Satchel from Rahauro, Thunder Bluff (70.0, 30.0)")
  T.eq(details[4], "Turn in: Rahauro, Thunder Bluff (70.0, 30.0)")
  title, details = ns.DungeonQuestLines(ns.Dungeons[2].quests[1], "done")
  T.eq(title, "[26] The Glowing Shard - done")
  T.eq(details[1], "Not shareable")
  T.eq(details[2], "Starts from item: Glowing Shard")
  T.eq(details[3], "Turn in: Falla Sagewind, The Barrens (47.0, 36.0)")
  title = ns.DungeonQuestLines(ns.Dungeons[3].quests[1], "available")
  T.eq(title, "[22] The Test of Righteousness (Paladin)")
end)

T.run("the journal browses dungeons as cards, with how many quests you can take", function()
  fresh(16, "Horde", "WARRIOR")
  Stub.completed[5723] = true
  local w = ns.ShowWindow("journal")
  T.eq(w:IsShown(), true); T.eq(w.current, "journal")
  T.eq(w.title:GetText(), "ForeverBuddy - Dungeon journal")
  local page = w.pages.journal
  T.eq(page.shownCards, 4, "one card per dungeon")
  T.eq(page.cards[1].dungeon.name, "Ragefire Chasm")
  T.eq(page.cards[1].name:GetText(), "Ragefire Chasm")
  T.eq(page.cards[1].level:GetText(), "LV 13-18")
  T.eq(page.cards[1].count:GetText(), "3 quests")
  T.eq(page.cards[3].dungeon.name, "The Deadmines")
  T.eq(page.cards[3].count:GetText(), "0 quests", "a Horde warrior can take none of the Deadmines quests")
  T.eq(page.browse:IsShown(), true); T.eq(page.detail:IsShown(), false)
end)

T.run("a dungeon opens as a tree of chains, each step saying where to go", function()
  fresh(16, "Horde", "WARRIOR")
  Stub.onQuest[5728] = true
  Stub.completed[5723] = true
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  T.eq(page.detail:IsShown(), true); T.eq(page.browse:IsShown(), false)
  T.eq(page.heading:GetText(), "Ragefire Chasm")
  T.eq(page.subheading:GetText(), "Level 13-18. 3 quests for you, 1 done. Click a step for an arrow to it.")
  T.eq(page.shownColumns, 3, "three chains: two single quests and the satchel chain")
  T.eq(page.nodes[1].node.level, 15, "the earliest chain comes first")
  local first = page.nodes[1]
  T.eq(first.name:GetText(), "[15] Testing an Enemy's Strength")
  T.eq(first.sub:GetText(), "Done - Pick up in Thunder Bluff", "a faction-coloured name puts the progress in the subtitle")
  T.eq(first.status, "done")
end)

T.run("the tree shows the chain before a quest, and its turn-in when it is elsewhere", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  local labels = {}
  for i = 1, page.shownNodes do labels[#labels + 1] = page.nodes[i].sub:GetText() end
  T.truthy(table.concat(labels, "|"):find("Turn in at Thunder Bluff", 1, true), table.concat(labels, "|"))
  local columns = ns.DungeonChains(ns.FindDungeon("rfc"), true)
  local satchel
  for _, column in ipairs(columns) do
    for _, node in ipairs(column.nodes) do
      if node.name == "Returning the Lost Satchel" then satchel = column end
    end
  end
  T.truthy(satchel, "the satchel chain exists")
  T.eq(satchel.nodes[1].name, "Searching for the Lost Satchel", "its prerequisite comes first in the column")
end)

T.run("only quests I can take filters the tree", function()
  fresh(22, "Horde", "WARRIOR")
  local page = ns.SelectScreen("journal", ns.FindDungeon("dm"))
  T.eq(page.shownColumns, 0, "both Deadmines quests are Alliance")
  page.onlyMine:Click()
  T.truthy(page.shownColumns > 0, "unticked, the other faction's quests show")
end)

T.run("clicking a step sets the arrow to it", function()
  fresh(16, "Horde", "WARRIOR")
  Stub.position = { map = 1454, x = 0.3, y = 0.3, zone = "Orgrimmar", sub = "" }
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  page.nodes[1]:Click()
  T.eq(printed[#printed], "arrow set: Testing an Enemy's Strength: Rahauro")
  T.eq(ns.ActiveWaypoint().map, 1456)
end)

T.run("the tree follows your quest log while it is open", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  T.eq(page.nodes[1].status, "available")
  T.eq(ns.IsJournalShown(), true)
  Stub.completed[5723] = true
  Stub.FireEvent("QUEST_LOG_UPDATE")
  T.eq(page.nodes[1].status, "done")
  ns.HideWindow()
  T.eq(ns.IsJournalShown(), false)
end)

T.run("/fb dungeon opens the journal, by level or by name, and lists in chat", function()
  fresh(15, "Horde", "WARRIOR")
  SlashCmdList.FOREVERBUDDY("dungeon")
  local w = _G.ForeverBuddyFrame
  T.eq(w.current, "journal"); T.eq(w:IsShown(), true)
  T.eq(w.pages.journal.selected.name, "Ragefire Chasm", "the dungeon for your level")
  SlashCmdList.FOREVERBUDDY("dungeon wc")
  T.eq(w.pages.journal.selected.name, "Wailing Caverns")
  SlashCmdList.FOREVERBUDDY("dungeon Naxxramas")
  T.eq(printed[#printed], "no dungeon called 'naxxramas'. /fb dungeon list shows the ones for your level.")
  printed = {}
  SlashCmdList.FOREVERBUDDY("dungeon list")
  T.eq(printed[1], "Dungeons around level 15:")
  T.eq(printed[2], "  Ragefire Chasm 13-18, 3 quests you can take (/fb dungeon rfc)")
  ns.HideWindow()
end)

T.run("ZonesForLevel: inside the band first, most levels ahead next, faction respected", function()
  fresh()
  local list = ns.ZonesForLevel(20, "Horde")
  local names = {}
  for _, e in ipairs(list) do table.insert(names, e.zone.name .. ":" .. e.fit) end
  T.eq(names[1], "Stonetalon Mountains:0", "6 levels left there vs 2 in the Barrens")
  T.eq(names[2], "The Barrens:0")
  T.eq(#names, 2, "Hillsbrad is 4 away, Ashenvale is Alliance")
  list = ns.ZonesForLevel(22, "Alliance")
  T.eq(list[1].zone.name, "Ashenvale", "8 levels ahead beats Stonetalon's 4")
  T.eq(list[2].zone.name, "Stonetalon Mountains")
  T.eq(ns.ZoneLine(list[2]), "Stonetalon Mountains 18-26, 46 quests, mostly Horde (17 Alliance, 23 Horde)")
  list = ns.ZonesForLevel(16, "Horde")
  T.eq(list[1].zone.name, "The Barrens"); T.eq(list[2].zone.name, "Stonetalon Mountains"); T.eq(list[2].fit, 2)
end)

T.run("/fb zones prints for the character's level or a given one, and rejects bad levels", function()
  fresh(11, "Horde")
  SlashCmdList.FOREVERBUDDY("zones")
  T.eq(printed[1], "Zones for level 11 (Horde):")
  T.eq(printed[2], "  The Barrens 10-22, 96 quests, Horde")
  T.eq(printed[3], "  Durotar 4-12, 40 quests, Horde")
  T.eq(printed[4], nil)
  printed = {}
  SlashCmdList.FOREVERBUDDY("zones 20")
  T.eq(printed[1], "Zones for level 20 (Horde):")
  printed = {}
  SlashCmdList.FOREVERBUDDY("zones 99")
  T.eq(printed[1], "usage: /fb zones [level 1-60]")
  printed = {}
  SlashCmdList.FOREVERBUDDY("zones 1")
  T.eq(printed[1], "no zone data for level 1")
end)

T.run("share status: the client wins for a quest in your log, then recorded data, then the shipped flag", function()
  fresh(16, "Horde", "WARRIOR")
  local q = ns.Dungeons[1].quests[1] -- shipped as shareable, like The Power to Destroy... in the real data
  T.eq(q.share, "yes")
  T.eq(ns.QuestShareText(q), "Shareable", "the shipped Classic flag")
  ns.Observed = { quests = { [q.id] = { title = q.name, shareable = false } } }
  T.eq(ns.QuestShareText(q), "Not shareable", "what players recorded on Forever beats the shipped flag")
  Stub.onQuest[q.id] = true
  Stub.pushable[q.id] = true
  T.eq(ns.QuestShareText(q), "Shareable", "the client wins while the quest is in your log")
  Stub.pushable[q.id] = false
  T.eq(ns.QuestShareText(q), "Not shareable")
  local chain = ns.Dungeons[1].quests[3] -- Returning the Lost Satchel, a chain quest
  Stub.onQuest[chain.id] = true
  Stub.pushable[chain.id] = false
  T.eq(ns.QuestShareText(chain), "Not shareable (chain)", "a chain quest keeps its reason")
  ns.Observed = nil
  Stub.onQuest[q.id] = nil
  local _, details = ns.DungeonQuestLines(q, "available")
  T.eq(details[1], "Shareable")
end)

T.run("a step that is only a prerequisite still points the way", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  local pre
  for i = 1, page.shownNodes do
    if page.nodes[i].node.name == "Searching for the Lost Satchel" then pre = page.nodes[i] end
  end
  T.truthy(pre, "the prerequisite has its own step")
  pre:Click()
  T.eq(printed[#printed], "arrow set: Searching for the Lost Satchel: Rahauro")
end)

T.run("hovering a step shows everything known about it, including a written note", function()
  fresh(16, "Horde", "WARRIOR")
  ns.Dungeons[1].quests[1].note = "Outside the Undercity, near the skinning trainer"
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  local lines = ns.NodeTooltipLines(page.nodes[1].node)
  T.eq(lines[1], "[15] Testing an Enemy's Strength")
  T.eq(lines[2], "Shareable")
  T.eq(lines[3], "Pick up: Rahauro, Thunder Bluff (70.0, 30.0)")
  T.truthy(lines[4]:find("Reward:", 1, true), "what it gives you comes before the written note")
  T.eq(lines[5], "Outside the Undercity, near the skinning trainer")
  T.eq(lines[#lines], "Click for an arrow to it.")
  ns.Dungeons[1].quests[1].note = nil
end)

T.run("a quest for one side wears its emblem and its colour; a neutral one keeps its progress colour", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  local node = page.nodes[1]
  T.eq(node.node.quest.faction, "Horde")
  T.eq(node.faction:IsShown(), true)
  T.eq(node.faction:GetTexture(), "Interface\\TargetingFrame\\UI-PVP-Horde")
  local colour, byFaction = ns.NodeNameColor(node.node.quest, "done")
  T.eq(colour, ns.COLORS.horde); T.eq(byFaction, true)
  local alliance = { faction = "Alliance" }
  T.eq((ns.NodeNameColor(alliance, "available")), ns.COLORS.alliance)
  local neutralColour, neutralByFaction = ns.NodeNameColor({ faction = false }, "active")
  T.eq(neutralColour, ns.COLORS.active); T.eq(neutralByFaction, false)
  page = ns.SelectScreen("journal", ns.FindDungeon("wc"))
  local neutral
  for i = 1, page.shownNodes do
    if page.nodes[i].node.quest and not page.nodes[i].node.quest.faction then neutral = page.nodes[i] end
  end
  T.truthy(neutral, "Wailing Caverns has a quest for both sides")
  T.eq(neutral.faction:IsShown(), false)
end)

T.run("the status moves into the subtitle when the name is coloured by faction", function()
  fresh(16, "Horde", "WARRIOR")
  Stub.completed[5723] = true
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  T.eq(page.nodes[1].sub:GetText(), "Done - Pick up in Thunder Bluff")
  local q = ns.Dungeons[2].quests[2]
  T.eq(ns.NodeSubtitle({ kind = "pickup", place = q.giver }, "available", false), "Pick up in The Barrens")
  T.eq(ns.NodeSubtitle({ kind = "turnin", place = q.turnin }, "active", true), "In your log - Turn in at The Barrens")
end)

T.run("a dungeon's own loading screen sits behind its card, cropped to the middle of the picture", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.ShowWindow("journal").pages.journal
  T.eq(page.cards[1].art:GetTexture(), 131862)
  T.eq(page.cards[1].art:IsShown(), true)
  T.eq(page.cards[1].scrim:IsShown(), true, "a wash under the text, so the name reads over the picture")
  T.eq(page.cards[3].art:IsShown(), false, "nothing known for the Deadmines here, so the plain panel stays")
  ns.HideWindow()
end)

T.run("the tree is built no wider than the window, and a box holds two lines of name", function()
  local m = ns.TREE_METRICS
  local width = m.columns * (m.nodeWidth + m.gapX) - m.gapX
  T.truthy(width <= ns.PAGE_WIDTH - 30, ("tree %d wide against a %d page"):format(width, ns.PAGE_WIDTH))
  T.truthy(m.nodeHeight >= m.nameHeight + 20, "room under the name for the subtitle")
end)

T.run("the filter works on the grid too, so a Horde player can count a friend's quests", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.ShowWindow("journal").pages.journal
  T.eq(page.onlyMine:IsShown(), true, "the switch is on the grid as well")
  page.onlyMine:SetChecked(true)              -- the switch keeps its state across the session
  page = ns.SelectScreen("journal")
  T.eq(page.cards[3].count:GetText(), "0 quests", "none of the Deadmines quests are for a Horde warrior")
  page.onlyMine:Click()
  T.eq(page.cards[3].count:GetText(), "2 quests", "with the filter off, every quest in it")
  T.truthy(page.subheading:GetText():find("every quest, either side", 1, true), page.subheading:GetText())
  page.onlyMine:Click()
  T.eq(page.cards[3].count:GetText(), "0 quests", "and back")
  ns.HideWindow()
end)

T.run("a step you have finished wears a tick, and one in your log a question mark", function()
  fresh(16, "Horde", "WARRIOR")
  Stub.completed[5726] = true -- the first half of the Hidden Enemies chain, a prerequisite only
  Stub.onQuest[5728] = true
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  local prerequisite, inLog
  for i = 1, page.shownNodes do
    local node = page.nodes[i]
    if node.node.id == 5726 then prerequisite = node end
    if node.node.id == 5728 then inLog = node end
  end
  T.truthy(prerequisite, "the prerequisite is drawn")
  T.eq(prerequisite.status, "done")
  T.eq(prerequisite.mark:IsShown(), true)
  T.eq(prerequisite.mark:GetTexture(), "Interface\\RaidFrame\\ReadyCheck-Ready")
  T.eq(prerequisite.sub:GetText(), "Done - Pick up in Orgrimmar", "the word, not only the colour")
  T.truthy(inLog, "the quest itself is drawn")
  T.eq(inLog.mark:GetTexture(), "Interface\\GossipFrame\\ActiveQuestIcon")
  ns.HideWindow()
end)

T.run("a prerequisite counts as done once you hold the quest it leads to", function()
  fresh(16, "Horde", "WARRIOR")
  local later = ns.Dungeons[1].quests[2]                       -- Hidden Enemies, 5728
  local step = { id = 5727, name = "Hidden Enemies", kind = "pickup", leadsTo = later }
  T.eq(ns.NodeStatus(step), "available", "nothing says you have been here yet")
  Stub.onQuest[5728] = true
  T.eq(ns.NodeStatus(step), "done", "you could not hold the later quest otherwise")
  Stub.onQuest[5728] = nil
  Stub.completed[5728] = true
  T.eq(ns.NodeStatus(step), "done")
  T.eq(ns.NodeStatus({ id = 999, kind = "pickup" }), "available", "a step leading nowhere known")
end)

T.run("each chain sits on a panel of its own", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  T.eq(#page.chains, page.shownColumns, "one panel per chain")
  T.eq(page.chains[1].fill:IsShown(), true)
  T.eq(page.chains[1].bar:IsShown(), true)
  page = ns.SelectScreen("journal", ns.FindDungeon("stocks"))
  for i = 1, #page.chains do T.eq(page.chains[i].fill:IsShown(), false, "no quests, no panels") end
  ns.HideWindow()
end)

T.run("the emblem follows the quests: the Deadmines is Alliance even to a Horde player", function()
  fresh(16, "Horde", "WARRIOR")
  T.eq(ns.DungeonFaction(ns.Dungeons[3]), "Alliance", "every Deadmines quest is an Alliance quest")
  T.eq(ns.DungeonFaction(ns.Dungeons[1]), "Horde", "Ragefire, all Horde")
  T.eq(ns.DungeonFaction(ns.Dungeons[2]), nil, "Wailing Caverns takes both sides")
  T.eq(ns.DungeonFaction(ns.Dungeons[4]), "Alliance", "the Stockade has no quests here, so its city decides")
  local page = ns.ShowWindow("journal").pages.journal
  T.eq(page.cards[3].faction:IsShown(), true)
  T.eq(page.cards[3].faction:GetTexture(), "Interface\\TargetingFrame\\UI-PVP-Alliance")
  T.eq(page.cards[2].faction:IsShown(), false, "nothing on a dungeon both sides quest in")
  ns.HideWindow()
end)

T.run("the line under a step is grey to pick up, orange in your log, green done", function()
  fresh(16, "Horde", "WARRIOR")
  T.eq(ns.SubtitleColor("available"), ns.SubtitleColor("nonsense"), "anything not started reads the same")
  T.eq(ns.SubtitleColor("active")[1], 1); T.eq(ns.SubtitleColor("active")[2], 0.55)
  T.eq(ns.SubtitleColor("done")[2], 0.85)
  Stub.completed[5723] = true
  Stub.onQuest[5728] = true
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  local done, inLog
  for i = 1, page.shownNodes do
    if page.nodes[i].node.id == 5723 then done = page.nodes[i] end
    if page.nodes[i].node.id == 5728 then inLog = page.nodes[i] end
  end
  local function sameColour(got, want, what)
    T.eq(got[1], want[1], what); T.eq(got[2], want[2], what); T.eq(got[3], want[3], what)
  end
  sameColour(done.sub.color, ns.SubtitleColor("done"), "a finished step reads green")
  sameColour(inLog.sub.color, ns.SubtitleColor("active"), "one in your log reads orange")
  ns.HideWindow()
end)

T.run("a step's tooltip names what the quest rewards", function()
  fresh(16, "Horde", "WARRIOR")
  local lines = ns.NodeTooltipLines({ id = 5723, name = "Testing an Enemy's Strength", level = 15,
                                      kind = "pickup", place = TB })
  local reward
  for _, line in ipairs(lines) do
    if line:find("Reward:", 1, true) then reward = line end
  end
  T.truthy(reward, "no reward line")
  T.truthy(reward:find("Stormpike Bracers", 1, true))
  T.truthy(reward:find("item level 19", 1, true))
  T.truthy(reward:find("|cff1eff00", 1, true), "coloured by quality")
end)

T.run("a step wears its own side, even with no quest of its own", function()
  fresh(16, "Horde", "WARRIOR")
  local page = ns.SelectScreen("journal", ns.FindDungeon("rfc"))
  local step
  for i = 1, page.shownNodes do
    if page.nodes[i].node.id == 5726 and not page.nodes[i].node.quest then step = page.nodes[i] end
  end
  T.truthy(step, "the prerequisite is drawn")
  T.eq(step.node.faction, "Horde")
  T.eq(step.faction:IsShown(), true, "with the emblem the quest it leads to wears")
  T.eq(step.faction:GetTexture(), "Interface\\TargetingFrame\\UI-PVP-Horde")
  local colour = ns.NodeNameColor({ faction = "Horde" }, "available")
  T.eq(colour, ns.COLORS.horde)
  ns.HideWindow()
end)

T.run("a dungeon Forever has not tuned shows as unknown rather than inventing a range", function()
  fresh(15)
  ns.Dungeons = {
    { key = "rfc", name = "Ragefire Chasm", zone = 1, level = { 13, 18 }, faction = false, aliases = { "rfc" }, quests = {} },
    { key = "dalaran", name = "City of Dalaran", zone = 2, level = { 28, 0 }, faction = false, aliases = { "cod" }, quests = {} },
    { key = "crypts", name = "Karazhan Crypts", zone = 3, level = false, faction = false, aliases = { "crypts" }, quests = {} },
  }
  local rfc, dalaran, crypts = ns.Dungeons[1], ns.Dungeons[2], ns.Dungeons[3]

  local lo, hi = ns.DungeonLevels(rfc)
  T.eq(lo, 13); T.eq(hi, 18)
  lo, hi = ns.DungeonLevels(dalaran)
  T.eq(lo, 28); T.eq(hi, nil, "a floor with no ceiling")
  lo, hi = ns.DungeonLevels(crypts)
  T.eq(lo, nil); T.eq(hi, nil)

  T.eq(ns.DungeonLevelText(rfc), "LV 13-18")
  T.eq(ns.DungeonLevelText(dalaran), "LV 28+")
  T.eq(ns.DungeonLevelText(crypts), "LV ?")
  T.eq(ns.DungeonLevelText(crypts, "long"), "Level not set yet")
  T.eq(ns.DungeonLevelText(dalaran, "long"), "Level 28 and up")
  T.eq(ns.DungeonLevelText(rfc, "bare"), "13-18")

  -- and it is never the answer to "where should I go at this level"
  T.eq(ns.DungeonForLevel(60, nil).key, "dalaran", "the tuned one, even far above its floor")
  T.eq(#ns.DungeonsForLevel(15, nil), 1)
  T.eq(ns.DungeonsForLevel(15, nil)[1].key, "rfc")
end)

T.run("a zone that only leans one way stays on both sides' lists, and says so", function()
  fresh(20, "Alliance")
  local names = {}
  for _, entry in ipairs(ns.ZonesForLevel(20, "Alliance")) do names[entry.zone.name] = true end
  T.eq(names["Stonetalon Mountains"], true, "mostly Horde, but 17 Alliance quests are still 17")
  T.eq(names["The Barrens"], nil, "wholly Horde, so not on an Alliance list")

  local stonetalon
  for _, z in ipairs(ns.Zones) do if z.name == "Stonetalon Mountains" then stonetalon = z end end
  T.eq(ns.ZoneLine({ zone = stonetalon }),
    "Stonetalon Mountains 18-26, 46 quests, mostly Horde (17 Alliance, 23 Horde)")
end)

T.run("a quest nobody has tried to share says nothing, rather than that it cannot be", function()
  fresh(25, "Horde")
  T.eq(ns.QuestShareText({ id = 95697, share = "unknown" }), nil)
  T.eq(ns.QuestShareText({ id = 95697, share = "single" }), "Not shareable")
  T.eq(ns.QuestShareText({ id = 95697, share = "yes" }), "Shareable")
end)

T.run("one quest is not enough to fly a side's emblem over a dungeon", function()
  fresh(25, "Horde")
  local lonely = { key = "esw", name = "Excavation Site: Wetlands", zone = 1, level = { 26, 33 },
                   faction = false, aliases = { "esw" },
                   quests = { { id = 95697, name = "Changing Tastes", faction = "Horde" } } }
  T.eq(ns.DungeonFaction(lonely), nil, "one Horde quest in Wetlands proves nothing")
  table.insert(lonely.quests, { id = 2, name = "Another", faction = "Horde" })
  T.eq(ns.DungeonFaction(lonely), "Horde", "two of a side, and it is theirs")

  local entrance = { key = "hot", name = "The Hall of Thanes", zone = 2, level = { 13, 20 },
                     faction = "Alliance", aliases = { "hot" },
                     quests = { { id = 3, name = "One", faction = "Alliance" } } }
  T.eq(ns.DungeonFaction(entrance), "Alliance", "the city holding the entrance still stands in")
end)

T.finish()
