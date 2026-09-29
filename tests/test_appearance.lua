package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

T.run("without the collection API the feature does not exist (Classic Era)", function()
  C_TransmogCollection = nil
  local ns = Stub.LoadAddon({ "Core.lua", "Tooltips/Appearance.lua" })
  T.eq(ns.featureIndex.appearance, nil)
end)

T.run("with the API it lines armour and weapons only", function()
  local collected = { [1001] = true }
  C_TransmogCollection = { PlayerHasTransmogByItemInfo = function(info) local id = tonumber(tostring(info):match("item:(%d+)")) or info; return collected[id] == true end }
  local ns = Stub.LoadAddon({ "Core.lua", "Tooltips/Appearance.lua" })
  Stub.reset(); ns.db = { features = {} }
  T.eq(ns.IsFeatureEnabled("appearance"), true)
  Stub.items[1001] = { name = "Fine Vest", equipLoc = "INVTYPE_CHEST", classID = 4, link = "|Hitem:1001:0:0:0:0:0:0:0|h[Fine Vest]|h" }
  Stub.items[1002] = { name = "Plain Vest", equipLoc = "INVTYPE_CHEST", classID = 4, link = "|Hitem:1002:0:0:0:0:0:0:0|h[Plain Vest]|h" }
  Stub.items[1003] = { name = "Ring", equipLoc = "INVTYPE_FINGER", classID = 4, link = "|Hitem:1003:0:0:0:0:0:0:0|h[Ring]|h" }
  Stub.items[1004] = { name = "Egg", equipLoc = "", classID = 0, link = "|Hitem:1004:0:0:0:0:0:0:0|h[Egg]|h" }
  T.eq(ns.AppearanceLine(1001, Stub.items[1001].link), "Appearance: collected")
  local text, color = ns.AppearanceLine(1002, Stub.items[1002].link)
  T.eq(text, "Appearance: not collected"); T.eq(color, "available")
  T.eq(ns.AppearanceLine(1003, Stub.items[1003].link), nil)
  T.eq(ns.AppearanceLine(1004, Stub.items[1004].link), nil)
  GameTooltip:SetHyperlink(Stub.items[1002].link)
  T.eq(GameTooltip.lines[1].text, "Appearance: not collected"); T.eq(GameTooltip.lines[1].g, 0.82)
  ns.db.features.appearance = false
  GameTooltip:SetHyperlink(Stub.items[1002].link)
  T.eq(#GameTooltip.lines, 0)
  C_TransmogCollection = nil
end)

T.finish()
