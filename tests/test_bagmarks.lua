package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Weights.lua", "Core.lua", "UsedFor/QuestStatus.lua", "UsedFor/Verdict.lua", "UsedFor/Tooltip.lua", "Gear/Score.lua",
                            "Automation/SellJunk.lua", "Bags/Marks.lua" })

-- The markers are shelved for the first release because they do not show in the beta, so the
-- switch and the hooks are not put in place on load. The code is still meant to work, and this
-- puts both back for the test.
-- Item scores are shelved too, and the upgrade arrow is scored, so it comes back for the test.
if not ns.featureIndex.itemscore then
  ns.RegisterFeature({ key = "itemscore", name = "Item scores on tooltips", desc = "shelved", default = true })
end
if not ns.featureIndex.bagmarks then
  ns.RegisterFeature({ key = "bagmarks", name = "Bag icon markers", desc = "shelved", default = true })
end

local function fresh()
  Stub.reset(); ns.RebuildLiveIndex()
  ns.HookBagFrames()
  ns.db = { features = {}, specs = {} }
  Stub.classToken = "WARRIOR"
  Stub.items[769] = { name = "Chunk of Boar Meat", quality = 1, equipLoc = "", classID = 0, link = "|Hitem:769:0:0:0:0:0:0:0|h[Chunk of Boar Meat]|h" }
  Stub.items[1] = { name = "Broken Fang", quality = 0, sellPrice = 3, equipLoc = "", classID = 15 }
  Stub.items[2] = { name = "Fine Vest", quality = 2, ilvl = 15, equipLoc = "INVTYPE_CHEST", classID = 4, link = "|Hitem:2:0:0:0:0:0:0:0|h[Fine Vest]|h" }
  Stub.items[3] = { name = "Old Vest", quality = 1, ilvl = 10, equipLoc = "INVTYPE_CHEST", classID = 4, link = "|Hitem:3:0:0:0:0:0:0:0|h[Old Vest]|h" }
  ns.Items = {
    [2] = { "Fine Vest", 2, 15, 5, 2, 0, 0, 0, 1, { Strength = 10 }, false, false, false, false, false, false },
    [3] = { "Old Vest", 1, 10, 5, 2, 0, 0, 0, 1, { Strength = 1 }, false, false, false, false, false, false },
  }
  ns.Quests[769] = { { 86, "Pie for Billy", "objective", false, "B", 0 } }
  Stub.equipped[5] = 3
  Stub.bags[0] = {
    { itemID = 769, quality = 1, stackCount = 3 },
    { itemID = 1, quality = 0, stackCount = 1 },
    { itemID = 2, quality = 2, stackCount = 1 },
    { itemID = 3, quality = 1, stackCount = 1 },
  }
end

local function fakeFrame(bag, n)
  local frame = Stub.NewMock("Frame", "ContainerFrame" .. (bag + 1))
  frame.GetID = function() return bag end
  frame.Items = {}
  for i = 1, n do
    local b = Stub.NewMock("Button")
    b.GetID = function() return i end
    frame.Items[i] = b
  end
  return frame
end

T.run("marks: quest, junk, upgrade, and item level on gear", function()
  fresh()
  local kind, ilvl = ns.BagMarkFor(0, 1, Stub.bags[0][1]); T.eq(kind, "keep"); T.eq(ilvl, nil)
  kind = ns.BagMarkFor(0, 2, Stub.bags[0][2]); T.eq(kind, "junk")
  kind, ilvl = ns.BagMarkFor(0, 3, Stub.bags[0][3]); T.eq(kind, "upgrade"); T.eq(ilvl, 15)
  kind, ilvl = ns.BagMarkFor(0, 4, Stub.bags[0][4]); T.eq(kind, nil); T.eq(ilvl, nil, "white gear gets no item level")
  T.eq(ns.BagMarkFor(0, 9, nil), nil)
end)

T.run("quest beats junk, keep-list removes the coin, feature toggles matter", function()
  fresh()
  Stub.bags[0][1].quality = 0
  T.eq(ns.BagMarkFor(0, 1, Stub.bags[0][1]), "keep")
  ns.db.junk = { keep = { [1] = true }, sell = {} }
  T.eq(ns.BagMarkFor(0, 2, Stub.bags[0][2]), nil)
  ns.db = { features = { usedfor = false }, specs = {} }
  T.eq(ns.BagMarkFor(0, 1, Stub.bags[0][1]), "junk")
  ns.db = { features = { itemscore = false }, specs = {} }
  T.eq(ns.BagMarkFor(0, 3, Stub.bags[0][3]), nil)
end)

if Stub.mainline then
  T.skip("the container hook paints icons and item levels onto the buttons", "Classic bag hook")
else
T.run("the container hook paints icons and item levels onto the buttons", function()
  fresh()
  local frame = fakeFrame(0, 4)
  Stub.CallHook("ContainerFrame_Update", frame)
  local o = ns.BagOverlay
  local b1, b2, b3, b4 = frame.Items[1], frame.Items[2], frame.Items[3], frame.Items[4]
  T.eq(o(b1).icon:GetTexture(), ns.BAG_MARK_ICONS.keep); T.eq(o(b1).icon:IsShown(), true); T.eq(o(b1).text:IsShown(), false)
  T.eq(o(b2).icon:GetTexture(), ns.BAG_MARK_ICONS.junk)
  T.eq(o(b3).icon:GetTexture(), ns.BAG_MARK_ICONS.upgrade); T.eq(o(b3).text:GetText(), "15"); T.eq(o(b3).text:IsShown(), true)
  T.eq(o(b4).icon:IsShown(), false); T.eq(o(b4).text:IsShown(), false)
  Stub.bags[0][1] = { itemID = 3, quality = 1, stackCount = 1 }
  Stub.CallHook("ContainerFrame_Update", frame)
  T.eq(o(b1).icon:IsShown(), false, "overlays are reused and cleared")
  T.eq(o(b1), ns.BagOverlay(b1), "one overlay per button")
  ns.db = { features = { bagmarks = false }, specs = {} }
  Stub.CallHook("ContainerFrame_Update", frame)
  T.eq(o(b3).icon:IsShown(), false); T.eq(o(b3).text:IsShown(), false)
end)
end

T.run("Mainline container frames are hooked through ContainerFrameMixin and EnumerateValidItems", function()
  fresh()
  ContainerFrame_Update = nil
  ContainerFrameMixin = { UpdateItems = function() end }
  local fresh_ns = Stub.LoadAddon({ "Data/Weights.lua", "Core.lua", "UsedFor/QuestStatus.lua", "UsedFor/Verdict.lua", "UsedFor/Tooltip.lua", "Gear/Score.lua", "Automation/SellJunk.lua", "Bags/Marks.lua" })
  if not fresh_ns.featureIndex.bagmarks then
    fresh_ns.RegisterFeature({ key = "bagmarks", name = "Bag icon markers", desc = "shelved", default = true })
  end
  fresh_ns.HookBagFrames()
  fresh_ns.db = { features = {}, specs = {} }
  fresh_ns.Items = ns.Items; fresh_ns.Quests[769] = ns.Quests[769]
  local frame = Stub.NewMock("Frame", "ContainerFrameCombinedBags")
  frame.GetID = function() return 0 end
  local buttons = {}
  for i = 1, 2 do local bt = Stub.NewMock("Button"); bt.GetID = function() return i end; buttons[i] = bt end
  frame.EnumerateValidItems = function() local i = 0; return function() i = i + 1; if buttons[i] then return i, buttons[i] end end end
  ContainerFrameMixin.UpdateItems(frame)
  T.eq(fresh_ns.BagOverlay(buttons[1]).icon:GetTexture(), fresh_ns.BAG_MARK_ICONS.keep)
  T.eq(fresh_ns.BagOverlay(buttons[2]).icon:GetTexture(), fresh_ns.BAG_MARK_ICONS.junk)
  if Stub.mainline then ContainerFrameMixin = { UpdateItems = function() end } else ContainerFrameMixin = nil; ContainerFrame_Update = function() end end
end)

T.finish()
