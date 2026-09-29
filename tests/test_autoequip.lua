package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "Automation/AutoEquip.lua" })

local CHEST_OLD, CHEST_NEW, CHEST_WORSE, CHEST_GREY, CHEST_RARE, CHEST_DECLINED = 100, 101, 102, 103, 104, 105
local RING_A, RING_B, RING_NEW, SHIRT, PLATE = 200, 201, 202, 300, 400
local MAIL_CHEST, CLOTH_CHEST, CLOAK, SHIELD, IDOL, SWORD, LATE_ITEM = 500, 501, 502, 503, 504, 505, 506

local function items()
  Stub.items[CHEST_OLD]   = { name = "Old Vest",   quality = 1, ilvl = 10, equipLoc = "INVTYPE_CHEST" }
  Stub.items[CHEST_NEW]   = { name = "Fine Vest",  quality = 2, ilvl = 15, equipLoc = "INVTYPE_CHEST", link = "|Hitem:101|h[Fine Vest]|h" }
  Stub.items[CHEST_WORSE] = { name = "Rag Vest",   quality = 1, ilvl = 5,  equipLoc = "INVTYPE_CHEST" }
  Stub.items[CHEST_GREY]  = { name = "Torn Vest",  quality = 0, ilvl = 20, equipLoc = "INVTYPE_CHEST" }
  Stub.items[CHEST_RARE]  = { name = "Blue Vest",  quality = 3, ilvl = 10, equipLoc = "INVTYPE_CHEST" }
  Stub.items[CHEST_DECLINED] = { name = "Declined Vest", quality = 2, ilvl = 15, equipLoc = "INVTYPE_CHEST" }
  Stub.items[RING_A]      = { name = "Ring A",     quality = 2, ilvl = 20, equipLoc = "INVTYPE_FINGER" }
  Stub.items[RING_B]      = { name = "Ring B",     quality = 2, ilvl = 12, equipLoc = "INVTYPE_FINGER" }
  Stub.items[RING_NEW]    = { name = "Ring New",   quality = 2, ilvl = 15, equipLoc = "INVTYPE_FINGER" }
  Stub.items[SHIRT]       = { name = "Shirt",      quality = 1, ilvl = 50, equipLoc = "INVTYPE_BODY" }
  Stub.items[PLATE]       = { name = "Plate Vest", quality = 2, ilvl = 30, equipLoc = "INVTYPE_CHEST" }
  -- classID 4 = Armor; subclass 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 0 misc (rings, necks)
  Stub.items[MAIL_CHEST]  = { name = "Mail Vest",  quality = 2, ilvl = 30, equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 3, link = "|Hitem:500|h[Mail Vest]|h" }
  Stub.items[CLOTH_CHEST] = { name = "Cloth Vest", quality = 2, ilvl = 25, equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 1, link = "|Hitem:501|h[Cloth Vest]|h" }
  Stub.items[CLOAK]       = { name = "Good Cloak", quality = 2, ilvl = 30, equipLoc = "INVTYPE_CLOAK", classID = 4, subclassID = 1, link = "|Hitem:502|h[Good Cloak]|h" }
  Stub.items[SHIELD]      = { name = "Big Shield", quality = 2, ilvl = 30, equipLoc = "INVTYPE_SHIELD", classID = 4, subclassID = 6, link = "|Hitem:503|h[Big Shield]|h" }
  Stub.items[IDOL]        = { name = "Idol",       quality = 2, ilvl = 30, equipLoc = "INVTYPE_RELIC", classID = 4, subclassID = 8, link = "|Hitem:504|h[Idol]|h" }
  Stub.items[SWORD]       = { name = "Big Sword",  quality = 2, ilvl = 30, equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 7, link = "|Hitem:505|h[Big Sword]|h" }
  Stub.items[LATE_ITEM]   = { name = "Late Vest",  quality = 2, ilvl = 40, equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 1, link = "|Hitem:506|h[Late Vest]|h" }
end

local function world(bag0)
  Stub.reset(); items()
  Stub.equipped[5] = CHEST_OLD
  Stub.equipped[11] = RING_A; Stub.equipped[12] = RING_B
  Stub.bags[0] = bag0 or {}
  ns.db = { features = {} }
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
end

local function loot(itemID)
  table.insert(Stub.bags[0], { itemID = itemID, quality = Stub.items[itemID].quality, stackCount = 1 })
  Stub.FireEvent("BAG_UPDATE_DELAYED")
end

-- Equip upgrade prompts is shelved for the first release, so it registers nothing on load. It is still
-- meant to work, and these tests hold it to that.
if not ns.featureIndex.autoequip then
  ns.RegisterFeature({ key = "autoequip", name = "Equip upgrade prompts", desc = "shelved", default = true })
end
ns.HookEquipPrompts()

T.run("registers the autoequip feature, on by default", function()
  T.eq(ns.featureIndex.autoequip.name, "Equip upgrade prompts")
  T.eq(ns.IsFeatureEnabled("autoequip"), true)
end)

T.run("a higher item level drop prompts, naming what it replaces", function()
  world()
  loot(CHEST_NEW)
  T.eq(#Stub.popups, 1)
  local p = Stub.popups[1]
  T.eq(p[1], "FOREVERBUDDY_EQUIP"); T.eq(p[2], "|Hitem:101|h[Fine Vest]|h"); T.eq(p[3], "[Old Vest]")
  T.eq(p[4].slot, 5); T.eq(p[4].itemID, CHEST_NEW)
end)

T.run("Equip button equips into the chosen slot; nothing is equipped on its own", function()
  world(); loot(CHEST_NEW)
  T.eq(#Stub.calls, 0)
  local dialog = StaticPopupDialogs.FOREVERBUDDY_EQUIP
  dialog.OnAccept(nil, Stub.popups[1][4])
  T.eq(Stub.calls[1][1], "EquipItemByName"); T.eq(Stub.calls[1][2], "|Hitem:101|h[Fine Vest]|h"); T.eq(Stub.calls[1][3], 5)
end)

T.run("Keep remembers the decline for the session", function()
  world(); loot(CHEST_DECLINED)
  T.eq(#Stub.popups, 1)
  StaticPopupDialogs.FOREVERBUDDY_EQUIP.OnCancel(nil, Stub.popups[1][4])
  Stub.popups = {}
  Stub.bags[0] = {}
  Stub.FireEvent("BAG_UPDATE_DELAYED")
  loot(CHEST_DECLINED)
  T.eq(#Stub.popups, 0, "declined items stay quiet for the session")
end)

T.run("lower item level, greys, shirts, and pre-existing items never prompt", function()
  world({ { itemID = CHEST_NEW, quality = 2, stackCount = 1 } })
  Stub.FireEvent("BAG_UPDATE_DELAYED")
  T.eq(#Stub.popups, 0, "already in bags at login")
  loot(CHEST_WORSE); loot(CHEST_GREY); loot(SHIRT)
  T.eq(#Stub.popups, 0)
end)

T.run("equal item level with higher quality prompts", function()
  world(); loot(CHEST_RARE)
  T.eq(#Stub.popups, 1)
end)

T.run("rings compare against the weaker of the two", function()
  world(); loot(RING_NEW)
  T.eq(#Stub.popups, 1)
  T.eq(Stub.popups[1][4].slot, 12); T.eq(Stub.popups[1][3], "[Ring B]")
end)

T.run("an empty slot is always an upgrade", function()
  world(); Stub.equipped[5] = nil
  loot(CHEST_WORSE)
  T.eq(#Stub.popups, 1); T.eq(Stub.popups[1][3], "an empty slot")
end)

T.run("the client's own answer decides whether the item is usable", function()
  world()
  Stub.canUseItem = { [PLATE] = false }
  loot(PLATE)
  T.eq(#Stub.popups, 0, "the client says this class cannot use it")
  T.eq(ns.IsBagItemUsable(0, 1, PLATE), false)
  Stub.canUseItem = nil
  T.eq(ns.IsBagItemUsable(0, 1, PLATE), true)
end)

T.run("without that API, red tooltip text still suppresses the prompt", function()
  world()
  local saved = C_PlayerInfo
  C_PlayerInfo = nil
  Stub.scanLines["0:1"] = { { "Plate Vest", 1, 1, 1 }, { "Chest", 1, 1, 1 }, { "Plate", 1, 0.1, 0.1 } }
  loot(PLATE)
  T.eq(#Stub.popups, 0)
  T.eq(ns.IsBagItemUsable(0, 1, PLATE), false)
  Stub.scanLines["0:1"] = nil
  T.eq(ns.IsBagItemUsable(0, 1, PLATE), true)
  C_PlayerInfo = saved
end)

T.run("in combat the prompt waits until combat ends", function()
  world(); Stub.inCombat = true
  loot(CHEST_NEW)
  T.eq(#Stub.popups, 0)
  Stub.inCombat = false
  Stub.FireEvent("PLAYER_REGEN_ENABLED")
  T.eq(#Stub.popups, 1)
  Stub.FireEvent("PLAYER_REGEN_ENABLED")
  T.eq(#Stub.popups, 1, "prompted once")
end)

T.run("feature off: no prompts, and turning it on later does not prompt for old loot", function()
  world(); ns.db = { features = { autoequip = false } }
  loot(CHEST_NEW)
  T.eq(#Stub.popups, 0)
  ns.db = { features = { autoequip = true } }
  Stub.FireEvent("BAG_UPDATE_DELAYED")
  T.eq(#Stub.popups, 0)
end)

T.run("stat weights decide when both items can be scored, not item level", function()
  world()
  local scores = { [CHEST_NEW] = 5, [CHEST_RARE] = 40 }
  local worn = 20
  ns.Weights = { Priest = { class = "PRIEST", name = "Priest", stats = {}, pseudo = {} } }
  ns.PlayerSpecKey = function() return "Priest" end
  ns.ScoreItem = function(_, itemID) return scores[itemID] end
  ns.EquippedScore = function() return worn end
  loot(CHEST_NEW)
  T.eq(#Stub.popups, 0, "higher item level but worse for the spec, like a dps weapon with no spell power")
  loot(CHEST_RARE)
  T.eq(#Stub.popups, 1, "lower item level but better for the spec")
  T.eq(Stub.popups[1][2], "|Hitem:104|h[Blue Vest]|h" == Stub.popups[1][2] and Stub.popups[1][2] or Stub.popups[1][2])
  ns.PlayerSpecKey, ns.ScoreItem, ns.EquippedScore, ns.Weights = nil, nil, nil, nil
end)

T.run("with no stat weights for the spec it still falls back to item level", function()
  world()
  ns.Weights = {}
  ns.PlayerSpecKey = function() return nil end
  loot(CHEST_NEW)
  T.eq(#Stub.popups, 1)
  ns.PlayerSpecKey, ns.Weights = nil, nil
end)

T.run("armour too heavy for the class is never offered, whatever the tooltip says", function()
  world(); Stub.classToken = "MAGE"; Stub.level = 60
  loot(MAIL_CHEST)
  T.eq(#Stub.popups, 0, "a mage is not offered mail")
  loot(CLOTH_CHEST)
  T.eq(#Stub.popups, 1, "cloth still is")
  T.eq(ns.IsArmorWearable(MAIL_CHEST), false)
  T.eq(ns.IsArmorWearable(CLOTH_CHEST), true)
end)

T.run("mail at level 40 for hunters and shamans, leather before that", function()
  world(); Stub.classToken = "HUNTER"; Stub.level = 39
  T.eq(ns.IsArmorWearable(MAIL_CHEST), false)
  Stub.level = 40
  T.eq(ns.IsArmorWearable(MAIL_CHEST), true)
  loot(MAIL_CHEST)
  T.eq(#Stub.popups, 1)
  Stub.classToken = "WARRIOR"; Stub.level = 10
  T.eq(ns.IsArmorWearable(MAIL_CHEST), true, "warriors wear mail from the start")
end)

T.run("cloaks, jewellery, shields, relics and weapons", function()
  world(); Stub.classToken = "PRIEST"; Stub.level = 60
  T.eq(ns.IsArmorWearable(CLOAK), true, "everyone wears cloaks")
  T.eq(ns.IsArmorWearable(RING_NEW), true, "rings have no armour type")
  T.eq(ns.IsArmorWearable(SHIELD), false, "a priest is not offered a shield")
  T.eq(ns.IsArmorWearable(IDOL), false, "a priest is not offered a druid idol")
  T.eq(ns.IsArmorWearable(SWORD), true, "weapons are left to the tooltip check")
  Stub.classToken = "WARRIOR"
  T.eq(ns.IsArmorWearable(SHIELD), true)
  Stub.classToken = "DRUID"
  T.eq(ns.IsArmorWearable(IDOL), true)
end)

T.run("a tooltip colour the client hides is ignored instead of breaking the check", function()
  world()
  local SECRET = {}
  issecretvalue = function(v) return v == SECRET end
  Stub.scanLines["0:1"] = { { "Fine Vest", 1, 1, 1 }, { "Requires Level 60", SECRET, SECRET, SECRET } }
  T.eq(ns.IsBagItemUsable(0, 1), true)
  issecretvalue = nil
end)

T.run("item data that arrives late still prompts, once the server sends it", function()
  world(); Stub.classToken = "WARRIOR"; Stub.level = 60
  local saved = Stub.items[LATE_ITEM]
  Stub.items[LATE_ITEM] = { name = "Late Vest", equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 1 } -- no ilvl yet
  loot(LATE_ITEM)
  T.eq(#Stub.popups, 0, "nothing to compare yet")
  T.eq(Stub.requested, LATE_ITEM, "the addon asked the server for it")
  Stub.items[LATE_ITEM] = saved
  Stub.FireEvent("GET_ITEM_INFO_RECEIVED", LATE_ITEM)
  T.eq(#Stub.popups, 1, "prompted when the data arrived")
  T.eq(Stub.popups[1][2], "|Hitem:506|h[Late Vest]|h")
  loot(CHEST_NEW) -- leave it counted, so the next test's own copy of the addon is the only one that reacts
end)

T.run("bag updates before entering the world are ignored", function()
  Stub.reset(); items()
  local fresh = Stub.LoadAddon({ "Core.lua", "Automation/AutoEquip.lua" })
  fresh.db = { features = {} }
  Stub.bags[0] = { { itemID = CHEST_NEW, quality = 2, stackCount = 1 } }
  Stub.FireEvent("BAG_UPDATE_DELAYED")
  T.eq(#Stub.popups, 0)
end)

T.finish()
