local ADDON, ns = ...

-- An addon cannot ask the internet whether it is out of date. What it can do is listen: everyone
-- running ForeverBuddy says its version to their guild and their group, and a number higher than
-- ours means there is a newer build to fetch. No names, no data, one short line per player.

local PREFIX = "ForeverBuddy"
local ANNOUNCE_EVERY = 60          -- seconds, so a busy guild is not chatted at
local FIRST_DELAY = 8              -- let the world finish loading before saying anything

local lastSent = 0

-- A release version is digits and dots and nothing else. A build straight out of the working
-- repository carries a suffix ("1.0.1-dev"), and one of those keeps quiet: it would otherwise
-- walk into a guild and tell everybody an update is out for something they cannot download.
-- It still listens, so a dev build is told when a real release passes it.
function ns.IsReleaseVersion(text)
  return type(text) == "string" and text:match("^%d+[%d%.]*$") ~= nil
end

-- "0.19.1" -> { 0, 19, 1 }. Anything unparseable comes back empty and loses every comparison.
function ns.VersionNumbers(text)
  local out = {}
  for piece in tostring(text or ""):gmatch("%d+") do table.insert(out, tonumber(piece)) end
  return out
end

-- -1 when a is older than b, 0 when they match, 1 when a is newer.
function ns.CompareVersions(a, b)
  local left, right = ns.VersionNumbers(a), ns.VersionNumbers(b)
  for i = 1, math.max(#left, #right) do
    local one, two = left[i] or 0, right[i] or 0
    if one ~= two then return one < two and -1 or 1 end
  end
  return 0
end

-- The newest version anyone has told us about, when it beats our own.
function ns.NewerVersion()
  return ns.newerVersion
end

function ns.NoteVersion(seen)
  if not ns.IsReleaseVersion(seen) then return nil end
  local mine = ns.AddonVersion and ns.AddonVersion() or "0"
  if ns.CompareVersions(seen, mine) <= 0 then return nil end
  if ns.newerVersion and ns.CompareVersions(seen, ns.newerVersion) <= 0 then return ns.newerVersion end
  ns.newerVersion = seen
  if not ns.newerVersionTold then
    ns.newerVersionTold = true
    ns.Print(("version %s is out, you have %s. Grab it from CurseForge or wherever you installed it."):format(seen, mine))
  end
  return seen
end

local function Channels()
  local out = {}
  if IsInRaid and IsInRaid() then
    table.insert(out, "RAID")
  elseif IsInGroup and IsInGroup() then
    table.insert(out, "PARTY")
  end
  if IsInGuild and IsInGuild() then table.insert(out, "GUILD") end
  return out
end

local function Send(message, channel)
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not send then return false end
  return (pcall(send, PREFIX, message, channel))
end

-- Says our version to whoever can hear it, at most once a minute.
function ns.AnnounceVersion(force)
  local mine = ns.AddonVersion and ns.AddonVersion() or "0"
  if not ns.IsReleaseVersion(mine) then return false end -- an unreleased build says nothing
  local now = (GetTime and GetTime()) or 0
  if not force and lastSent > 0 and now - lastSent < ANNOUNCE_EVERY then return false end
  local channels = Channels()
  if #channels == 0 then return false end
  lastSent = now
  local message = "V:" .. mine
  for _, channel in ipairs(channels) do Send(message, channel) end
  return true
end

function ns.ReadVersionMessage(prefix, message, _, sender)
  if not ns.VersionGossipAllowed() then return nil end
  if prefix ~= PREFIX or type(message) ~= "string" then return nil end
  local seen = message:match("^V:([%d%.]+)$")
  if not seen then return nil end
  return ns.NoteVersion(seen)
end

-- A build from the working repository has no business on the addon channel at all: it does not
-- speak, and it does not open the channel to listen either, so nothing it does can reach
-- anybody else's chat frame. Registering the prefix is what makes the client deliver
-- CHAT_MSG_ADDON for it, so leaving that undone is the whole of it.
function ns.VersionGossipAllowed()
  return ns.IsReleaseVersion(ns.AddonVersion and ns.AddonVersion() or "0")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(self, event, ...)
  if event == "CHAT_MSG_ADDON" then
    ns.ReadVersionMessage(...)
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not ns.VersionGossipAllowed() then return end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(FIRST_DELAY, function() ns.AnnounceVersion(true) end)
    else
      ns.AnnounceVersion(true)
    end
  else
    ns.AnnounceVersion()
  end
end)
