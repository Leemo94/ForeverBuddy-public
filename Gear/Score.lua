local ADDON, ns = ...

-- Item scores on tooltips: stat weights (Data/Weights.lua) x item stats (Data/Items.lua, else GetItemStats).

-- SHELVED for the first release. Forever writes spell power as "increases damage and healing
-- done by magical spells and effects by up to N", which the stat reader does not understand,
-- so the scores come out wrong. The code and its tests are untouched: turning SHIPPING back on
-- is the whole job once that wording is read properly. Nothing registers and nothing hooks
-- while it is off, so no switch is offered for something that would mislead.
local SHIPPING = false

if SHIPPING then
  ns.RegisterFeature({
    key = "itemscore",
    name = "Item scores on tooltips",
    desc = "Scores gear for your spec with WoWSims stat weights and compares it with what you wear. /fb spec picks the spec.",
    default = true,
  })
end

-- GetItemStats keys -> weight names. Ratings do not exist in Classic; percent-based hit/crit live in the item database.
ns.ITEM_MOD_TO_STAT = {
  ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility", ITEM_MOD_STAMINA_SHORT = "Stamina",
  ITEM_MOD_INTELLECT_SHORT = "Intellect", ITEM_MOD_SPIRIT_SHORT = "Spirit",
  ITEM_MOD_SPELL_POWER_SHORT = "SpellPower", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellDamage",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HealingPower", ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
  ITEM_MOD_ATTACK_POWER_SHORT = "AttackPower", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RangedAttackPower",
  ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FeralAttackPower",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense", ITEM_MOD_DODGE_RATING_SHORT = "Dodge",
  ITEM_MOD_PARRY_RATING_SHORT = "Parry", ITEM_MOD_BLOCK_RATING_SHORT = "Block", ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",
  ITEM_MOD_CRIT_MELEE_RATING_SHORT = "MeleeCrit", ITEM_MOD_CRIT_RATING_SHORT = "MeleeCrit",
  ITEM_MOD_HIT_MELEE_RATING_SHORT = "MeleeHit", ITEM_MOD_HIT_RATING_SHORT = "MeleeHit",
  ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SpellCrit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "SpellHit",
  ITEM_MOD_HASTE_RATING_SHORT = "MeleeHaste", ITEM_MOD_EXPERTISE_RATING_SHORT = "Expertise",
  RESISTANCE0_NAME = "Armor", RESISTANCE2_NAME = "FireResistance", RESISTANCE3_NAME = "NatureResistance",
  RESISTANCE4_NAME = "FrostResistance", RESISTANCE5_NAME = "ShadowResistance", RESISTANCE6_NAME = "ArcaneResistance",
}

local RANGED_DPS_TYPES = { [1] = true, [2] = true, [3] = true, [6] = true } -- bow, crossbow, gun, thrown

local function LinkItemID(link)
  return tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
end

-- A random-suffix item ("... of the Bear") carries a non-zero 8th link field; its stats live only in the client.
local function LinkHasSuffix(link)
  if type(link) ~= "string" then return false end
  local suffix = link:match("item:%d*:%d*:%d*:%d*:%d*:%d*:(%-?%d+)")
  return suffix ~= nil and suffix ~= "0" and suffix ~= ""
end

local function ClientStats(link)
  local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
  local raw = link and getStats and getStats(link)
  if not raw then return nil end
  local stats = {}
  for key, value in pairs(raw) do
    local name = ns.ITEM_MOD_TO_STAT[key]
    if name and value and value ~= 0 then stats[name] = (stats[name] or 0) + value end
  end
  return stats
end

-- Returns stats{}, weapon{min,max,speed}|nil, handType, rangedType for an item; nil when nothing is known.
function ns.ItemStatsFor(itemID, link)
  local record = itemID and ns.Items[itemID]
  if record and not LinkHasSuffix(link) then
    return record[10], record[11] or nil, record[7], record[8]
  end
  local stats = ClientStats(link)
  if not stats then return nil end
  if record then return stats, record[11] or nil, record[7], record[8] end
  return stats, nil, 0, 0
end

-- Weighted sum of stats plus weapon DPS through the matching pseudo-stat weight.
function ns.ScoreStats(spec, stats, weapon, handType, rangedType)
  local total = 0
  for name, value in pairs(stats or {}) do
    total = total + value * (spec.stats[name] or 0)
  end
  if weapon and weapon[3] and weapon[3] > 0 then
    local dps = (weapon[1] + weapon[2]) / 2 / weapon[3]
    local key = "MainHandDps"
    if handType == 3 then key = "OffHandDps" elseif RANGED_DPS_TYPES[rangedType or 0] then key = "RangedDps" end
    total = total + dps * (spec.pseudo[key] or 0)
  end
  return total
end

function ns.ScoreItem(spec, itemID, link)
  local stats, weapon, handType, rangedType = ns.ItemStatsFor(itemID, link)
  if not stats then return nil end
  return ns.ScoreStats(spec, stats, weapon, handType, rangedType)
end

-- Spec selection ----------------------------------------------------------------
local function CharacterKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function ns.SpecsForClass(classToken)
  local keys = {}
  for key, spec in pairs(ns.Weights) do
    if spec.class == classToken then table.insert(keys, key) end
  end
  table.sort(keys)
  return keys
end

function ns.PlayerSpecKey()
  local _, classToken = UnitClass("player")
  local chosen = ns.db and ns.db.specs and ns.db.specs[CharacterKey()]
  if chosen and ns.Weights[chosen] then return chosen end
  local keys = ns.SpecsForClass(classToken)
  for _, key in ipairs(keys) do
    if key:upper() == classToken then return key end -- "Warrior" over "TankWarrior"
  end
  return keys[1]
end

function ns.SetPlayerSpec(key)
  if not (ns.db and key and ns.Weights[key]) then return false end
  ns.db.specs = ns.db.specs or {}
  ns.db.specs[CharacterKey()] = key
  return true
end

ns.SlashHandlers.spec = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  local _, classToken = UnitClass("player")
  local keys = ns.SpecsForClass(classToken)
  if rest ~= "" then
    for _, key in ipairs(keys) do
      if key:lower() == rest:lower() then
        ns.SetPlayerSpec(key)
        ns.Print("scoring items for " .. ns.Weights[key].name)
        return
      end
    end
    ns.Print("unknown spec '" .. rest .. "' for your class")
  end
  local current = ns.PlayerSpecKey()
  ns.Print("current spec: " .. (current and ns.Weights[current].name or "none") .. ". Options: " .. (#keys > 0 and table.concat(keys, ", ") or "none for this class"))
end

-- Equip location for a database record (type, handType, weaponType, rangedType), so it can be compared with worn gear.
local TYPE_TO_EQUIPLOC = {
  [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_CLOAK", [5] = "INVTYPE_CHEST",
  [6] = "INVTYPE_WRIST", [7] = "INVTYPE_HAND", [8] = "INVTYPE_WAIST", [9] = "INVTYPE_LEGS", [10] = "INVTYPE_FEET",
  [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET",
}
function ns.RecordEquipLoc(record)
  local itemType, weaponType, handType, rangedType = record[4], record[6], record[7], record[8]
  if itemType == 13 then
    if weaponType == 7 then return "INVTYPE_SHIELD" end
    if weaponType == 5 then return "INVTYPE_HOLDABLE" end
    if handType == 4 then return "INVTYPE_2HWEAPON" end
    if handType == 3 then return "INVTYPE_WEAPONOFFHAND" end
    if handType == 1 then return "INVTYPE_WEAPONMAINHAND" end
    return "INVTYPE_WEAPON"
  elseif itemType == 14 then
    if rangedType == 4 or rangedType == 5 or rangedType == 7 or rangedType == 9 then return "INVTYPE_RELIC" end
    return "INVTYPE_RANGED"
  end
  return TYPE_TO_EQUIPLOC[itemType]
end

-- Tooltip line -------------------------------------------------------------------
function ns.EquippedScore(spec, equipLoc)
  local slots = ns.EQUIP_SLOTS[equipLoc]
  if not slots then return nil end
  local worst
  for _, slot in ipairs(slots) do
    local link = GetInventoryItemLink("player", slot)
    local score = link and ns.ScoreItem(spec, LinkItemID(link), link) or 0
    if worst == nil or score < worst then worst = score end
  end
  return worst
end

function ns.ScoreLine(itemID, link)
  local specKey = ns.PlayerSpecKey()
  local spec = specKey and ns.Weights[specKey]
  if not spec then return nil end
  local score = ns.ScoreItem(spec, itemID, link)
  if not score then return nil end
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
  local equipped = ns.EquippedScore(spec, equipLoc)
  local text = ("Score (%s): %.1f"):format(spec.name, score)
  local color = "white"
  if equipped then
    local diff = score - equipped
    text = text .. ("  vs equipped %.1f (%+.1f)"):format(equipped, diff)
    color = diff > 0 and "active" or (diff < 0 and "keep" or "white")
  end
  return text, color
end

local function OnItemTooltip(tooltip, data)
  if not ns.IsFeatureEnabled("itemscore") then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  if tooltip:IsForbidden() then return end
  local itemID = data and data.id
  if not itemID then return end
  local link = select(2, C_Item.GetItemInfo(itemID))
  local text, colorKey = ns.ScoreLine(itemID, link)
  if not text then return end
  local c = ns.COLORS[colorKey] or ns.COLORS.white
  tooltip:AddLine(text, c[1], c[2], c[3])
  tooltip:Show()
end

local reported = false
function ns.HookItemScoreTooltip()
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
  local ok, err = pcall(OnItemTooltip, tooltip, data)
  if not ok and not reported then
    reported = true
    ns.Print("score tooltip error (reported once per session): " .. tostring(err))
  end
end)

  return true
end

if SHIPPING then ns.HookItemScoreTooltip() end
