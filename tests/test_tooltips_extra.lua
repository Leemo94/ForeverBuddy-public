package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UsedFor/QuestStatus.lua", "UsedFor/Verdict.lua", "UsedFor/Tooltip.lua",
                            "Tooltips/DeleteWarn.lua" })

-- Delete warnings is shelved for the first release, so it registers nothing on load. It is still
-- meant to work, and these tests hold it to that.
if not ns.featureIndex.deletewarn then
  ns.RegisterFeature({ key = "deletewarn", name = "Delete warnings", desc = "shelved", default = true })
end
ns.HookDeleteWarning()

local function fresh()
  Stub.reset(); ns.RebuildLiveIndex()
  ns.db = { features = {} }
  Stub.items[769] = { name = "Chunk of Boar Meat", sellPrice = 5, link = "|Hitem:769:0:0:0:0:0:0:0|h[Chunk of Boar Meat]|h" }
  Stub.items[2589] = { name = "Linen Cloth", sellPrice = 13, link = "|Hitem:2589:0:0:0:0:0:0:0|h[Linen Cloth]|h" }
  Stub.items[13098] = { name = "Painweaver Band", sellPrice = 12345, link = "|Hitem:13098:0:0:0:0:0:0:0|h[Painweaver Band]|h" }
  Stub.items[4] = { name = "Worthless", sellPrice = 0 }
  ns.Quests[769] = { { 86, "Pie for Billy", "objective", false, "B", 0, { { 72, 150 } } } }
  ns.Quests[2589] = { { 5000, "Cloth Donation", "objective", true, "B", 0, { { 72, 75 } } } }
  Stub.factions[72] = "Stormwind"
end
local function texts(tt) local out = {} for i, l in ipairs(tt.lines) do out[i] = l.text end return out end

T.run("features registered with the intended defaults", function()
  T.eq(ns.IsFeatureEnabled("deletewarn"), true)
  T.eq(ns.featureIndex.sellprice, nil, "the game shows a sell price itself now")
  T.eq(ns.featureIndex.ids, nil); T.eq(ns.featureIndex.alts, nil)
end)

T.run("repeatable turn-ins show the reputation per turn-in", function()
  fresh()
  GameTooltip:SetHyperlink(Stub.items[2589].link)
  local t = texts(GameTooltip)
  T.truthy(t[3] == "Quest: Cloth Donation (repeatable, +75 Stormwind per turn-in)", table.concat(t, " | "))
  Stub.factions[72] = nil
  T.eq(ns.RepText({ { 72, 75 } }), "+75 faction 72")
  T.eq(ns.RepText(nil), nil)
  T.eq(ns.QuestLineText({ name = "Pie for Billy", status = "available", rep = { { 72, 150 } } }), "Quest: Pie for Billy", "rep shows for repeatable quests only")
end)

T.run("delete confirmation gains a warning for items a quest still needs", function()
  fresh()
  local dialog = { text = Stub.NewMock("FontString") }
  dialog.text:SetText("Do you want to destroy Chunk of Boar Meat?")
  Stub.dialogs.DELETE_ITEM = dialog
  Stub.CallHook("StaticPopup_Show", "DELETE_ITEM", Stub.items[769].link)
  T.eq(dialog.text:GetText(), "Do you want to destroy Chunk of Boar Meat?\n\n|cffff8a1fForeverBuddy: KEEP: needed for Pie for Billy|r")
  T.eq(Stub.resized[1], "DELETE_ITEM")
  Stub.CallHook("StaticPopup_Show", "DELETE_ITEM", Stub.items[769].link)
  T.eq(#Stub.resized, 1, "not appended twice")
end)

T.run("no warning once the quest is done, for unknown items, or with the feature off", function()
  fresh()
  Stub.completed[86] = true
  T.eq(ns.DeleteWarning(Stub.items[769].link), nil)
  T.eq(ns.DeleteWarning(Stub.items[13098].link), nil)
  T.eq(ns.DeleteWarning(nil), nil)
  Stub.completed[86] = nil
  ns.db = { features = { deletewarn = false } }
  local dialog = { text = Stub.NewMock("FontString") }; dialog.text:SetText("x"); Stub.dialogs.DELETE_ITEM = dialog
  Stub.CallHook("StaticPopup_Show", "DELETE_ITEM", Stub.items[769].link)
  T.eq(dialog.text:GetText(), "x")
end)

T.finish()
