package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UsedFor/QuestStatus.lua", "UsedFor/Verdict.lua", "UsedFor/Tooltip.lua" })

local BOAR = 769
local function setupBoar()
  Stub.reset()
  Stub.items[BOAR] = "Chunk of Boar Meat"
  ns.Quests[BOAR] = {
    { 86,  "Pie for Billy",     "objective", false, "A", 0 },
    { 317, "Stocking Jetsteam", "objective", false, "A", 0 },
  }
  ns.Recipes[BOAR] = { { "Roasted Boar Meat", "Cooking", 2681, "Roasted Boar Meat", 1 } }
  Stub.onQuest[317] = true
  Stub.questLog = { { title = "Stocking Jetsteam", questID = 317 } }
  Stub.objectives[317] = { { text = "Chunk of Boar Meat: 1/8", type = "item" } }
  ns.RebuildLiveIndex()
end
local function texts(tt) local out = {} for i, l in ipairs(tt.lines) do out[i] = l.text end return out end

T.run("registers a post-call for item tooltips", function()
  T.eq(Stub.postCalls[Enum.TooltipDataType.Item][1], ns.OnItemTooltip)
end)

T.run("renders verdict, quests, recipes in order with colours", function()
  setupBoar()
  ns.OnItemTooltip(GameTooltip, { id = BOAR })
  local t = texts(GameTooltip)
  T.eq(t[1], " ")
  T.eq(t[2], "KEEP: needed for Stocking Jetsteam and 1 more")
  T.eq(GameTooltip.lines[2].r, 1); T.eq(GameTooltip.lines[2].g, 0.5); T.eq(GameTooltip.lines[2].b, 0)
  T.eq(t[3], "Quest: Stocking Jetsteam (1/8)"); T.eq(GameTooltip.lines[3].g, 1); T.eq(GameTooltip.lines[3].r, 0.2)
  T.eq(t[4], "Quest: Pie for Billy");           T.eq(GameTooltip.lines[4].g, 0.82)
  T.eq(t[5], "Cooking: Roasted Boar Meat");     T.eq(GameTooltip.lines[5].r, 1); T.eq(GameTooltip.lines[5].g, 1)
  T.eq(#t, 5)
  T.eq(GameTooltip.shown, true)
end)

T.run("quest line suffixes for repeatable and done", function()
  T.eq(ns.QuestLineText({ name = "Weekly", status = "repeatable" }), "Quest: Weekly (repeatable)")
  T.eq(ns.QuestLineText({ name = "Old", status = "done" }), "Quest: Old (done)")
  T.eq(ns.QuestLineText({ name = "Loading", status = "active" }), "Quest: Loading")
end)

T.run("recipe line shows crafted item only when its name differs", function()
  T.eq(ns.RecipeLineText({ "Roasted Boar Meat", "Cooking", 2681, "Roasted Boar Meat", 1 }), "Cooking: Roasted Boar Meat")
  T.eq(ns.RecipeLineText({ "Enchant Bracer - Minor Health", "Enchanting", 0, "", 1 }), "Enchanting: Enchant Bracer - Minor Health")
  T.eq(ns.RecipeLineText({ "Copper Chain Belt", "Blacksmithing", 2852, "Copper Chain Belt", 6 }), "Blacksmithing: Copper Chain Belt")
  T.eq(ns.RecipeLineText({ "Elixir of Minor Fortitude", "Alchemy", 2458, "Elixir of Minor Fortitude", 1 }), "Alchemy: Elixir of Minor Fortitude")
  T.eq(ns.RecipeLineText({ "Rough Sharpening Stone", "Blacksmithing", 2862, "Rough Sharpening Stone (x2)", 1 }), "Blacksmithing: Rough Sharpening Stone -> Rough Sharpening Stone (x2)")
end)

T.run("caps quests and per-profession recipes, Shift lifts the caps", function()
  Stub.reset(); ns.RebuildLiveIndex()
  Stub.items[1] = "Copper Bar"
  ns.Quests[1] = {}
  for i = 1, 8 do ns.Quests[1][i] = { 1000 + i, ("Quest %02d"):format(i), "objective", false, "B", 0 } end
  ns.Recipes[1] = {}
  for i = 1, 6 do ns.Recipes[1][i] = { ("Copper Thing %d"):format(i), "Blacksmithing", 0, "", 1 } end
  for i = 7, 8 do ns.Recipes[1][i] = { ("Gadget %d"):format(i), "Engineering", 0, "", 1 } end
  ns.OnItemTooltip(GameTooltip, { id = 1 })
  local t = texts(GameTooltip)
  T.eq(t[2], "KEEP: needed for Quest 01 and 7 more")
  T.eq(t[8], "Quest: Quest 06")
  T.eq(t[9], "+2 more quests"); T.eq(GameTooltip.lines[9].r, 0.6)
  T.eq(t[10], "Blacksmithing: Copper Thing 1")
  T.eq(t[13], "Blacksmithing: Copper Thing 4")
  T.eq(t[14], "+2 more Blacksmithing recipes")
  T.eq(t[15], "Engineering: Gadget 7"); T.eq(t[16], "Engineering: Gadget 8")
  T.eq(#t, 16)
  Stub.shift = true
  GameTooltip = Stub.NewTooltip("GameTooltip", "x")
  ns.OnItemTooltip(GameTooltip, { id = 1 })
  T.eq(#GameTooltip.lines, 1 + 1 + 8 + 8)
  ns.Quests[1] = nil; ns.Recipes[1] = nil
end)

T.run("unknown item adds nothing", function()
  Stub.reset(); ns.RebuildLiveIndex()
  Stub.items[999] = "Nothing Special"
  ns.OnItemTooltip(GameTooltip, { id = 999 })
  T.eq(#GameTooltip.lines, 0); T.eq(GameTooltip.shown, false)
end)

T.run("live-only quest renders without shipped data", function()
  Stub.reset()
  Stub.items[70002] = "Skyborne Feather"
  Stub.questLog = { { title = "Feathers for Zephras", questID = 70002 } }
  Stub.objectives[70002] = { { text = "Skyborne Feather: 2/5", type = "item" } }
  ns.RebuildLiveIndex()
  ns.OnItemTooltip(GameTooltip, { id = 70002 })
  local t = texts(GameTooltip)
  T.eq(t[2], "KEEP: needed for Feathers for Zephras")
  T.eq(t[3], "Quest: Feathers for Zephras (2/5)")
end)

T.run("ignores other tooltips, forbidden tooltips, and disabled state", function()
  setupBoar()
  local other = Stub.NewTooltip("ShoppingTooltip1", "x")
  ns.OnItemTooltip(other, { id = BOAR }); T.eq(#other.lines, 0)
  GameTooltip.forbidden = true
  ns.OnItemTooltip(GameTooltip, { id = BOAR }); T.eq(#GameTooltip.lines, 0)
  GameTooltip.forbidden = false
  ns.db = { features = { usedfor = false } }
  ns.OnItemTooltip(GameTooltip, { id = BOAR }); T.eq(#GameTooltip.lines, 0)
  ns.db = nil
  ns.OnItemTooltip(ItemRefTooltip, { id = BOAR }); T.eq(#ItemRefTooltip.lines, 5)
end)

T.run("missing item id or data adds nothing", function()
  setupBoar()
  ns.OnItemTooltip(GameTooltip, nil); T.eq(#GameTooltip.lines, 0)
  ns.OnItemTooltip(GameTooltip, {}); T.eq(#GameTooltip.lines, 0)
end)

T.run("uncached item name falls back to the tooltip title and requests the item", function()
  setupBoar()
  Stub.items[BOAR] = nil
  GameTooltip = Stub.NewTooltip("GameTooltip", "Chunk of Boar Meat")
  ns.OnItemTooltip(GameTooltip, { id = BOAR })
  T.eq(Stub.requested, BOAR)
  T.eq(texts(GameTooltip)[3], "Quest: Stocking Jetsteam (1/8)")
end)

T.run("handler errors are swallowed and reported once", function()
  setupBoar()
  local printed = {}
  ns.Print = function(msg) table.insert(printed, msg) end
  local real = ns.CollectQuests
  ns.CollectQuests = function() error("boom") end
  ns.OnItemTooltip(GameTooltip, { id = BOAR })
  ns.OnItemTooltip(GameTooltip, { id = BOAR })
  ns.CollectQuests = real
  T.eq(#printed, 1)
  T.truthy(printed[1]:find("boom", 1, true), "message includes the error")
end)

T.finish()
