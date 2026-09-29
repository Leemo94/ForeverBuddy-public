package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UsedFor/Verdict.lua" })

local function q(name, status) return { questID = 1, name = name, status = status } end
local COOK = { "Roasted Boar Meat", "Cooking", 2681, "Roasted Boar Meat", 1 }
local ALCH = { "Elixir of Lion's Strength", "Alchemy", 2454, "Elixir of Lion's Strength", 1 }

T.run("ProfessionList is unique and ordered by first appearance", function()
  local list = ns.ProfessionList({ COOK, ALCH, COOK })
  T.eq(#list, 2); T.eq(list[1], "Cooking"); T.eq(list[2], "Alchemy")
  T.eq(#ns.ProfessionList(nil), 0)
end)

T.run("KEEP names the first needed quest", function()
  local text, color = ns.GetVerdict({ q("Pie for Billy", "available") }, nil)
  T.eq(text, "KEEP: needed for Pie for Billy"); T.eq(color, "keep")
end)

T.run("KEEP counts the other needed quests, ignoring done ones", function()
  local list = { q("Stocking Jetsteam", "active"), q("Pie for Billy", "available"), q("Weekly", "repeatable"), q("Old", "done") }
  local text = ns.GetVerdict(list, { COOK })
  T.eq(text, "KEEP: needed for Stocking Jetsteam and 2 more")
end)

T.run("all done but still a reagent", function()
  local text, color = ns.GetVerdict({ q("Old", "done") }, { COOK })
  T.eq(text, "All quests done: still a Cooking reagent"); T.eq(color, "white")
end)

T.run("all done and no recipes is safe to vendor", function()
  local text, color = ns.GetVerdict({ q("Old", "done") }, nil)
  T.eq(text, "All quests done: safe to vendor"); T.eq(color, "grey")
end)

T.run("reagent only lists professions", function()
  local text, color = ns.GetVerdict({}, { COOK, ALCH })
  T.eq(text, "Crafting reagent (Cooking, Alchemy)"); T.eq(color, "white")
end)

T.run("a repeatable quest alone is always KEEP", function()
  T.eq(ns.GetVerdict({ q("Cloth Donation", "repeatable") }, nil), "KEEP: needed for Cloth Donation")
end)

T.run("an unknown status is treated as needed, never safe", function()
  local text, color = ns.GetVerdict({ q("Odd", "turnedin") }, nil)
  T.eq(text, "KEEP: needed for Odd"); T.eq(color, "keep")
end)

T.run("empty profession strings are ignored", function()
  T.eq(ns.GetVerdict({}, { { "Mystery", "", 0, "", 1 } }), "Crafting reagent")
  T.eq(ns.GetVerdict({ q("Old", "done") }, { { "Mystery", "", 0, "", 1 } }), "All quests done: still a crafting reagent")
  local text, color = ns.GetVerdict({}, nil)
  T.eq(text, nil); T.eq(color, nil)
end)

T.run("no known use gives no verdict", function()
  T.eq(ns.GetVerdict({}, nil), nil)
  T.eq(ns.GetVerdict(nil, {}), nil)
end)

T.finish()
