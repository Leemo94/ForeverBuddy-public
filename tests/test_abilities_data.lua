package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Abilities.lua", "Core.lua" })

T.run("every class has a ladder, and it says where it came from", function()
  T.eq(ns.AbilityInfo.classes, 9)
  T.eq(ns.AbilityInfo.build, "1.60.1.69893")
  local counted = 0
  for class, list in pairs(ns.Abilities) do
    T.truthy(#list > 80, class .. " has only " .. #list)  -- rogues are the shortest ladder
    counted = counted + #list
  end
  T.eq(counted, ns.AbilityInfo.abilities)
end)

T.run("each ability is whole, in level order, and inside 1 to 60", function()
  for class, list in pairs(ns.Abilities) do
    local last = 0
    for _, row in ipairs(list) do
      local id, name, level, rank = row[1], row[2], row[3], row[4]
      T.eq(type(id), "number", class)
      T.truthy(name and name ~= "", class .. " ability with no name")
      T.truthy(level >= 1 and level <= 60, ("%s: %s at level %s"):format(class, name, tostring(level)))
      T.truthy(rank >= 0, class .. " rank")
      T.truthy(level >= last, ("%s is out of order at %s"):format(class, name))
      last = level
    end
  end
end)

T.run("the levels are Forever's, not Classic's", function()
  local function find(class, name)
    for _, row in ipairs(ns.Abilities[class]) do
      if row[2] == name then return row[3] end
    end
    return nil
  end
  -- Ranks are rows of their own, so find returns the first, which is rank 1.
  T.eq(find("PALADIN", "Hammer of Justice"), 8, "Forever hands it over at 8; Classic waits until 20")
  T.eq(find("ROGUE", "Between the Eyes"), nil, "a rune ability, not something a trainer teaches")
  T.eq(find("PRIEST", "Engrave Chest - Prayer"), nil)
  T.eq(find("PALADIN", "Holy Light"), 1, "and the ranks climb from there")
  T.truthy(find("PALADIN", "Holy Strike"), "a Paladin ability Classic never had")
  T.eq(find("WARRIOR", "Mortal Strike"), 40)
  T.eq(find("MAGE", "Fireball"), 1)
end)

T.finish()
