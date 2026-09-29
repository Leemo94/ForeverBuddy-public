package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UsedFor/QuestStatus.lua", "UsedFor/Verdict.lua", "Automation/SellJunk.lua", "Automation/AutoEquip.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function bags()
  Stub.reset(); printed = {}
  Stub.items[1] = { name = "Broken Fang", sellPrice = 10 }
  Stub.items[2] = { name = "Linen Cloth", sellPrice = 13 }
  Stub.items[3] = { name = "Ruined Pelt", sellPrice = 7 }
  Stub.items[4] = "Uncached Junk"
  Stub.bags[0] = {
    { itemID = 1, quality = 0, stackCount = 3 },          -- grey, 30c
    { itemID = 2, quality = 1, stackCount = 20 },         -- white, kept
    { itemID = 3, quality = 0, stackCount = 1, hasNoValue = true },
  }
  Stub.bags[4] = {
    { itemID = 3, quality = 0, stackCount = 2 },          -- grey, 14c
    { itemID = 3, quality = 0, stackCount = 1, isLocked = true },
    { itemID = 4, quality = 0, stackCount = 1 },          -- grey, price unknown -> 0
  }
end

T.run("registers the selljunk feature, on by default", function()
  T.eq(ns.featureIndex.selljunk.name, "Sell junk")
  T.eq(ns.IsFeatureEnabled("selljunk"), true)
end)

T.run("sells greys with value, skips white, valueless, and locked items", function()
  bags()
  local count, total = ns.SellJunk()
  T.eq(count, 3); T.eq(total, 44)
  local calls = Stub.calls
  T.eq(#calls, 3)
  T.eq(calls[1][1], "UseContainerItem"); T.eq(calls[1][2], 0); T.eq(calls[1][3], 1)
  T.eq(calls[2][2], 4); T.eq(calls[2][3], 1)
  T.eq(calls[3][2], 4); T.eq(calls[3][3], 3)
end)

T.run("MERCHANT_SHOW sells and prints a summary", function()
  bags()
  Stub.FireEvent("MERCHANT_SHOW")
  T.eq(printed[1], "sold 3 items for 44c")
end)

T.run("singular wording and silence when nothing sold", function()
  bags()
  Stub.bags[4] = nil
  Stub.FireEvent("MERCHANT_SHOW")
  T.eq(printed[1], "sold 1 item for 30c")
  Stub.reset(); printed = {}
  Stub.FireEvent("MERCHANT_SHOW")
  T.eq(#printed, 0)
end)

T.run("keep list protects, sell list forces, /fb junk manages both", function()
  bags(); ns.db = { features = {} }
  ns.SlashHandlers.junk("keep |Hitem:1:0:0:0:0:0:0:0|h[Broken Fang]|h")
  T.eq(printed[1], "Broken Fang will never be sold")
  ns.SlashHandlers.junk("sell 2")
  T.eq(printed[2], "Linen Cloth will always be sold")
  local count, total, reasons = ns.SellJunk()
  T.eq(count, 3); T.eq(total, 14 + 0 + 13 * 20); T.eq(reasons.listed, 1); T.eq(reasons.junk, 2)
  Stub.calls = {}
  ns.SlashHandlers.junk("clear 2"); ns.SlashHandlers.junk("clear 1")
  T.eq(printed[4], "Broken Fang follows the normal rules again")
  ns.SlashHandlers.junk("list")
  T.eq(printed[5], "keep list: empty"); T.eq(printed[6], "always sell: empty")
  ns.SlashHandlers.junk("keep 1"); ns.SlashHandlers.junk("list")
  T.eq(printed[8], "keep list: Broken Fang")
  ns.SlashHandlers.junk("wat")
  T.eq(printed[10], "usage: /fb junk keep|sell|clear <shift-click an item>, /fb junk list")
end)

T.run("sellunusable sells red-text soulbound gear unless a quest needs it", function()
  bags(); ns.db = { features = { sellunusable = true } }
  Stub.items[50] = { name = "Plate Vest", sellPrice = 100, quality = 3, equipLoc = "INVTYPE_CHEST", classID = 4 }
  Stub.items[51] = { name = "Plate Quest Vest", sellPrice = 100, quality = 3, equipLoc = "INVTYPE_CHEST", classID = 4 }
  Stub.items[52] = { name = "Fine Vest", sellPrice = 100, quality = 3, equipLoc = "INVTYPE_CHEST", classID = 4 }
  Stub.items[53] = { name = "Epic Vest", sellPrice = 100, quality = 4, equipLoc = "INVTYPE_CHEST", classID = 4 }
  Stub.bags[0] = {
    { itemID = 50, quality = 3, stackCount = 1, isBound = true },   -- unusable, sold
    { itemID = 51, quality = 3, stackCount = 1, isBound = true },   -- unusable but a quest needs it
    { itemID = 52, quality = 3, stackCount = 1, isBound = true },   -- usable, kept
    { itemID = 53, quality = 4, stackCount = 1, isBound = true },   -- epic, never
    { itemID = 50, quality = 3, stackCount = 1, isBound = false },  -- not bound, kept
  }
  Stub.bags[4] = nil
  Stub.scanLines["0:1"] = { { "Plate Vest", 1, 1, 1 }, { "Plate", 1, 0.1, 0.1 } }
  Stub.scanLines["0:2"] = { { "Plate Quest Vest", 1, 1, 1 }, { "Plate", 1, 0.1, 0.1 } }
  Stub.scanLines["0:4"] = { { "Epic Vest", 1, 1, 1 }, { "Plate", 1, 0.1, 0.1 } }
  ns.Quests[51] = { { 9, "Armour Errand", "objective", false, "B", 0 } }
  ns.RebuildLiveIndex()
  local count, total, reasons = ns.SellJunk()
  T.eq(count, 1); T.eq(reasons.unusable, 1); T.eq(Stub.calls[1][3], 1)
  ns.Quests[51] = nil
  Stub.calls = {}
  ns.db = { features = { sellunusable = false } }
  T.eq((ns.SellJunk()), 0, "off by default")
end)

T.run("does nothing when the feature is off", function()
  bags()
  ns.db = { features = { selljunk = false } }
  Stub.FireEvent("MERCHANT_SHOW")
  T.eq(#Stub.calls, 0); T.eq(#printed, 0)
  ns.db = nil
end)

T.finish()
