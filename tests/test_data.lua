package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Recipes.lua", "Data/Quests.lua", "Core.lua" })

T.run("data files load and report plausible counts", function()
  T.truthy(ns.DataInfo.build:match("^%d+%.%d+%.%d+%.%d+$"), "build number")
  T.truthy(ns.DataInfo.recipes > 400, "reagent item count " .. ns.DataInfo.recipes)
  T.truthy(ns.DataInfo.quests > 2500, "quest item count " .. ns.DataInfo.quests)
end)

T.run("Small Egg is used by Cooking recipes, the Classic ones among them", function()
  local byName = {}
  for _, r in ipairs(ns.Recipes[6889]) do byName[r[1]] = r[2] end
  T.eq(byName["Herb Baked Egg"], "Cooking")
  T.eq(byName["Gingerbread Cookie"], "Cooking")
  T.eq(byName["Egg Nog"], "Cooking")
  T.truthy(#ns.Recipes[6889] >= 3, "Forever may add more: " .. #ns.Recipes[6889])
end)

T.run("Chunk of Boar Meat is needed by Pie for Billy and Stocking Jetsteam", function()
  local byID = {}
  for _, q in ipairs(ns.Quests[769]) do byID[q[1]] = q end
  T.eq(byID[86][2], "Pie for Billy");        T.eq(byID[86][5], "A");  T.eq(byID[86][4], false)
  T.eq(byID[317][2], "Stocking Jetsteam");   T.eq(byID[317][3], "objective")
  local cooks = {}
  for _, r in ipairs(ns.Recipes[769]) do cooks[r[1]] = r[2] end
  T.eq(cooks["Roasted Boar Meat"], "Cooking")
end)

T.run("recipes within an item are sorted by profession then name", function()
  for _, entries in pairs(ns.Recipes) do
    for i = 2, #entries do
      local a, b = entries[i - 1], entries[i]
      T.truthy(a[2] < b[2] or (a[2] == b[2] and a[1] <= b[1]), a[2] .. "/" .. a[1] .. " before " .. b[2] .. "/" .. b[1])
    end
  end
end)

T.run("no riding or racial skill line leaked in as a profession", function()
  for _, entries in pairs(ns.Recipes) do
    for _, r in ipairs(entries) do
      T.truthy(not r[2]:find("Riding") and not r[2]:find("Racial"), r[2])
    end
  end
end)

T.finish()
