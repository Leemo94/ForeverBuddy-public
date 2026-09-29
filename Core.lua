local ADDON, ns = ...

ns.ADDON = ADDON

-- Shared colour table; keys are used by UsedFor/Verdict.lua and UsedFor/Tooltip.lua.
ns.COLORS = {
  active     = { 0.2, 1,    0.2 },
  available  = { 1,   0.82, 0   },
  repeatable = { 0.4, 0.7,  1   },
  done       = { 0.6, 0.6,  0.6 },
  keep       = { 1,   0.5,  0   },
  white      = { 1,   1,    1   },
  grey       = { 0.6, 0.6,  0.6 },
  horde      = { 0.77, 0.12, 0.23 },
  alliance   = { 0.0,  0.44, 0.87 },
}

-- Item quality colours, for naming an item we only know from our own data files.
ns.QUALITY_COLOR = {
  [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
}

function ns.QualityText(name, quality)
  local hex = ns.QUALITY_COLOR[quality or 1] or "ffffff"
  return ("|cff%s%s|r"):format(hex, tostring(name))
end

-- The client's name for an item, or a placeholder until the client has loaded it.
function ns.ItemName(itemID)
  local get = C_Item and C_Item.GetItemInfo
  local name = get and get(itemID)
  return name or ("item " .. tostring(itemID))
end

function ns.ItemIcon(itemID)
  local get = (C_Item and (C_Item.GetItemIconByID or C_Item.GetItemIcon)) or GetItemIcon
  local ok, icon = pcall(get, itemID)
  return (ok and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Generated data files load before Core.lua; guard so the addon still loads without them.
ns.Recipes = ns.Recipes or {}
ns.Quests = ns.Quests or {}
ns.Weights = ns.Weights or {}
ns.Items = ns.Items or {}

-- Equip location -> inventory slots it can go in. Missing entries (shirt, tabard, bags, ammo) are ignored.
ns.EQUIP_SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Modules may register extra /fb subcommands: ns.SlashHandlers[name] = function(rest) end
ns.SlashHandlers = {}

function ns.Print(msg)
  print("|cff33ff99ForeverBuddy|r: " .. tostring(msg))
end

-- Feature registry -------------------------------------------------------------
-- Modules call ns.RegisterFeature at file load; registration order is display order.
ns.features = {}      -- ordered array of { key, name, desc, default }
ns.featureIndex = {}  -- key -> definition

function ns.RegisterFeature(def)
  assert(type(def.key) == "string" and def.key ~= "", "feature key required")
  assert(not ns.featureIndex[def.key], "duplicate feature " .. def.key)
  def.default = def.default == true
  table.insert(ns.features, def)
  ns.featureIndex[def.key] = def
  return def
end

-- Unknown key -> false. Before the DB loads, or when the user never set the key -> default.
function ns.IsFeatureEnabled(key)
  local def = ns.featureIndex[key]
  if not def then return false end
  local features = ns.db and ns.db.features
  if not features or features[key] == nil then return def.default end
  return features[key] == true
end

function ns.SetFeatureEnabled(key, enabled)
  if not ns.featureIndex[key] then
    ns.Print("unknown feature: " .. tostring(key))
    return false
  end
  if not (ns.db and ns.db.features) then
    ns.Print("settings are not loaded yet")
    return false
  end
  ns.db.features[key] = enabled == true
  ns.SaveSettingsFallback()
  -- A switch that changes something outside the addon (a console setting, say) applies it here.
  local def = ns.featureIndex[key]
  if def.apply then pcall(def.apply, enabled == true) end
  return true
end

-- City map pins -------------------------------------------------------------------
-- Five switches of their own, set on the map itself rather than in the checklist, and kept
-- with the rest of the settings so they survive a login.
ns.PIN_KINDS = {
  { key = "class", name = "Class trainers", icon = "Interface\\Minimap\\Tracking\\Class", color = { 1, 0.82, 0 } },
  { key = "profession", name = "Profession trainers", icon = "Interface\\Minimap\\Tracking\\Profession", color = { 0.2, 0.8, 0.4 } },
  { key = "weapon", name = "Weapon masters", icon = "Interface\\Icons\\INV_Sword_04", color = { 0.75, 0.75, 0.8 } },
  { key = "flight", name = "Flight master", icon = "Interface\\Minimap\\Tracking\\FlightMaster", color = { 0.4, 0.7, 1 } },
  { key = "bank", name = "Bank", icon = "Interface\\Minimap\\Tracking\\Banker", color = { 0.85, 0.75, 0.55 } },
  { key = "auction", name = "Auction house", icon = "Interface\\Minimap\\Tracking\\Auctioneer", color = { 0.9, 0.5, 0.9 } },
}

ns.pinIndex = {}
for _, def in ipairs(ns.PIN_KINDS) do ns.pinIndex[def.key] = def end

function ns.PinEnabled(kind)
  if not ns.pinIndex[kind] then return false end
  local saved = ns.db and ns.db.pins and ns.db.pins[kind]
  if saved == nil then return true end -- every kind is on until someone turns it off
  return saved and true or false
end

-- Inside class and profession trainers, each class and each profession is its own tick, so a
-- warlock hunting only their own trainer is not reading past eight others. On until turned off.
function ns.TagEnabled(tag)
  if not tag then return true end
  local saved = ns.db and ns.db.pins and ns.db.pins.tags and ns.db.pins.tags[tag]
  if saved == nil then return true end
  return saved and true or false
end

function ns.SetTagEnabled(tag, on)
  if not (tag and ns.db) then return false end
  ns.db.pins = ns.db.pins or {}
  ns.db.pins.tags = ns.db.pins.tags or {}
  ns.db.pins.tags[tag] = on and true or false
  ns.SaveSettingsFallback()
  return true
end

function ns.SetPinEnabled(kind, on)
  if not (ns.pinIndex[kind] and ns.db) then return false end
  ns.db.pins = ns.db.pins or {}
  ns.db.pins[kind] = on and true or false
  ns.SaveSettingsFallback()
  return true
end

-- Settings fallback ---------------------------------------------------------------
-- The Forever beta client writes our saved-variables file at logout but does not read it
-- back at login, so ticks and the setup guide reset every session. The game's own settings
-- file is written separately, and addons may keep a value in it, so the switches are mirrored
-- there and restored when the saved file comes back empty. Recorded data is far too big for
-- this, and still lives in the saved file.
local SETTINGS_CVAR = "ForeverBuddySettings"

local function CVarReady()
  return C_CVar and C_CVar.GetCVar and C_CVar.SetCVar and true or false
end

function ns.SettingsString()
  if not (ns.db and ns.db.features) then return nil end
  local flags = {}
  for _, def in ipairs(ns.features) do
    local saved = ns.db.features[def.key]
    if saved ~= nil and saved ~= def.default then
      table.insert(flags, def.key .. ":" .. (saved and "1" or "0"))
    end
  end
  local pins = {}
  for _, def in ipairs(ns.PIN_KINDS) do
    if ns.db.pins and ns.db.pins[def.key] == false then table.insert(pins, def.key .. ":0") end
  end
  local tags = {}
  for tag, value in pairs((ns.db.pins and ns.db.pins.tags) or {}) do
    if value == false then table.insert(tags, tag) end -- only the ones turned off need keeping
  end
  table.sort(tags)
  return ("v1;setup=%d;f=%s;p=%s;t=%s"):format(ns.db.setupDone and 1 or 0,
    table.concat(flags, ","), table.concat(pins, ","), table.concat(tags, ","))
end

function ns.SaveSettingsFallback()
  if not CVarReady() then return nil end
  local text = ns.SettingsString()
  if not text then return nil end
  local ok = pcall(C_CVar.SetCVar, SETTINGS_CVAR, text)
  return ok and text or nil
end

-- Returns how many switches were restored, or nil when there was nothing to restore.
function ns.RestoreSettingsFallback()
  if not (CVarReady() and ns.db and ns.db.features) then return nil end
  local ok, raw = pcall(C_CVar.GetCVar, SETTINGS_CVAR)
  if not ok or type(raw) ~= "string" or raw == "" then return nil end
  local setup = raw:match("setup=(%d)")
  if setup then ns.db.setupDone = setup == "1" end
  local restored = 0
  for key, value in (raw:match("f=([^;]*)") or ""):gmatch("([%w_]+):(%d)") do
    if ns.featureIndex[key] then
      ns.db.features[key] = value == "1"
      restored = restored + 1
    end
  end
  ns.db.pins = ns.db.pins or {}
  for key, value in (raw:match("p=([^;]*)") or ""):gmatch("([%w_]+):(%d)") do
    if ns.pinIndex[key] then
      ns.db.pins[key] = value == "1"
      restored = restored + 1
    end
  end
  ns.db.pins.tags = ns.db.pins.tags or {}
  for tag in (raw:match("t=([^;]*)") or ""):gmatch("([^,]+)") do
    ns.db.pins.tags[tag] = false
    restored = restored + 1
  end
  return restored
end

-- Saved variables ----------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
  if name ~= ADDON then return end
  -- Did the game hand us back what it saved last time? Anything else (ticks resetting, the
  -- setup guide returning every login) follows from this being false.
  ns.savedLoaded = type(ForeverBuddyDB) == "table" and next(ForeverBuddyDB) ~= nil
  ns.savedSummary = "nothing"
  if ns.savedLoaded then
    local features, quests, items = 0, 0, 0
    for _ in pairs(ForeverBuddyDB.features or {}) do features = features + 1 end
    for _ in pairs((ForeverBuddyDB.collected or {}).quests or {}) do quests = quests + 1 end
    for _ in pairs((ForeverBuddyDB.collected or {}).items or {}) do items = items + 1 end
    ns.savedSummary = ("%d features set, %d quests and %d items recorded, setup %s"):format(
      features, quests, items, ForeverBuddyDB.setupDone and "done" or "not done")
  end
  if type(ForeverBuddyDB) ~= "table" then ForeverBuddyDB = {} end
  if type(ForeverBuddyDB.features) ~= "table" then ForeverBuddyDB.features = {} end
  if ForeverBuddyDB.setupDone == nil then ForeverBuddyDB.setupDone = false end
  ns.db = ForeverBuddyDB
  if C_CVar and C_CVar.RegisterCVar then pcall(C_CVar.RegisterCVar, SETTINGS_CVAR, "") end
  if not ns.savedLoaded then
    local restored = ns.RestoreSettingsFallback()
    if restored and (restored > 0 or ns.db.setupDone) then
      ns.restoredSettings = restored
    end
  end
  ns.SaveSettingsFallback()
  self:UnregisterEvent("ADDON_LOADED")
end)

-- Slash command ------------------------------------------------------------------
local USAGE = "usage: /fb | /fb settings | /fb setup | /fb list | /fb dungeon [name] | /fb zones [level] | /fb spec [key] | /fb <feature> on|off | /fb info"

function ns.DataInfoLine()
  local d = ns.DataInfo or {}
  return ("data build %s generated %s: %d reagent items, %d quest items"):format(
    d.build or "?", d.generated or "?", d.recipes or 0, d.quests or 0)
end

SLASH_FOREVERBUDDY1 = "/fb"
SLASH_FOREVERBUDDY2 = "/foreverbuddy"
SlashCmdList.FOREVERBUDDY = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "" then
    -- Always the welcome page, whatever was last open: /fb is how someone finds their way around.
    if ns.ShowWindow then ns.ShowWindow("home") else ns.Print(USAGE) end
    return
  end
  if msg == "setup" then
    if ns.ShowSetup then ns.ShowSetup() else ns.Print(USAGE) end
    return
  end
  if msg == "info" then
    ns.Print(ns.DataInfoLine())
    if GetBuildInfo then
      local version, build, _, interface = GetBuildInfo()
      ns.Print(("client %s build %s, interface %s, addon %s"):format(tostring(version), tostring(build), tostring(interface),
        ns.AddonVersion and ns.AddonVersion() or "?"))
    end
    return
  end
  if msg == "list" then
    for _, def in ipairs(ns.features) do
      ns.Print(("%s %s  %s"):format(def.key, ns.IsFeatureEnabled(def.key) and "on" or "off", def.name))
    end
    return
  end
  local command, rest = msg:match("^(%S+)%s*(.-)$")
  if command and ns.SlashHandlers[command] then
    ns.SlashHandlers[command](rest)
    return
  end
  local key, state = msg:match("^(%S+)%s+(%S+)$")
  local def = key and ns.featureIndex[key]
  if def and (state == "on" or state == "off") then
    if ns.SetFeatureEnabled(key, state == "on") then
      ns.Print(def.name .. (state == "on" and " enabled" or " disabled"))
    end
    return
  end
  ns.Print(USAGE)
end
