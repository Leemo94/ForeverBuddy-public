local _, ns = ...

-- /fb zones [level]: which zones suit a level, from the quest data in Data/Zones.lua.
-- With no level it uses the character's own, so friends can be told "you're 20, go to X".

ns.Zones = ns.Zones or {}

local MAX_LINES = 6
local SLACK = 2 -- a zone still counts when the level is this close to its band

-- Zones that fit `level` for `faction` ("Alliance"|"Horde"|nil), best fit first.
-- Returns { { zone = <entry>, fit = <levels outside the band, 0 when inside> }, ... }
function ns.ZonesForLevel(level, faction)
  local out = {}
  for _, z in ipairs(ns.Zones) do
    -- A zone that only leans the other way still has quests for you: Ashenvale is mostly the
    -- Alliance's and still holds 23 Horde quests. Only a zone that is wholly one side's drops
    -- off the other side's list.
    local theirs = z.faction and not z.leaning and faction and z.faction ~= faction
    if not theirs then
      local lo, hi = z.level[1], z.level[2]
      local fit = (level < lo and lo - level) or (level > hi and level - hi) or 0
      if fit <= SLACK then table.insert(out, { zone = z, fit = fit }) end
    end
  end
  -- Inside the band first; among those, the zone with the most levels still ahead of the
  -- character (at 11, the Barrens beats Durotar, which ends at 12); then the busier zone.
  table.sort(out, function(a, b)
    if a.fit ~= b.fit then return a.fit < b.fit end
    local ra, rb = a.zone.level[2] - level, b.zone.level[2] - level
    if ra ~= rb then return ra > rb end
    if a.zone.quests ~= b.zone.quests then return a.zone.quests > b.zone.quests end
    return a.zone.name < b.zone.name
  end)
  return out
end

function ns.ZoneLine(entry)
  local z = entry.zone
  local s = ("%s %d-%d, %d quests"):format(z.name, z.level[1], z.level[2], z.quests)
  if not z.faction then
    s = s .. ", both factions"
  elseif z.leaning then
    s = s .. (", mostly %s (%d Alliance, %d Horde)"):format(z.faction, z.alliance or 0, z.horde or 0)
  else
    s = s .. ", " .. z.faction
  end
  return s
end

ns.SlashHandlers.zones = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  local level = rest == "" and UnitLevel("player") or tonumber(rest)
  if not level or level < 1 or level > 60 then
    ns.Print("usage: /fb zones [level 1-60]")
    return
  end
  local faction = UnitFactionGroup("player")
  local list = ns.ZonesForLevel(level, faction)
  if #list == 0 then
    ns.Print(("no zone data for level %d"):format(level))
    return
  end
  if rest == "" and ns.ShowWindow then ns.ShowWindow("zones") end
  ns.Print(("Zones for level %d (%s):"):format(level, faction or "any faction"))
  for i = 1, math.min(MAX_LINES, #list) do
    ns.Print("  " .. ns.ZoneLine(list[i]))
  end
end
