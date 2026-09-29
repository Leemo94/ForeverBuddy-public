package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Dungeons.lua", "Data/Loot.lua", "Core.lua" })

T.run("the rewards file loads, and says where it came from", function()
  T.truthy(ns.LootInfo, "no LootInfo")
  T.truthy(ns.LootInfo.quests > 50, "quests with a known reward: " .. tostring(ns.LootInfo.quests))
  T.eq(ns.LootInfo.dungeons, 0, "boss drop tables are not shipped until they are Forever's own")
end)

T.run("no drop tables are shipped yet", function()
  local counted = 0
  for _ in pairs(ns.DungeonLoot or {}) do counted = counted + 1 end
  T.eq(counted, 0, "Classic's tables would be wrong here; the recorder will fill these in")
end)

T.run("quest rewards are keyed by quest, and name what they give", function()
  local counted = 0
  for questID, rewards in pairs(ns.QuestRewards) do
    counted = counted + 1
    T.eq(type(questID), "number")
    T.truthy(#rewards > 0, "empty reward list for quest " .. questID)
    for _, reward in ipairs(rewards) do
      T.eq(type(reward[1]), "number")
      T.truthy(reward[2] and reward[2] ~= "")
      T.truthy(reward[3] >= 0 and reward[3] <= 5, "quality out of range")
    end
  end
  T.eq(counted, ns.LootInfo.quests)
  T.truthy(ns.QuestRewards[166], "The Defias Brotherhood rewards gear")
end)

T.finish()
