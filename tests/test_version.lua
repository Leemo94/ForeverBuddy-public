package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "Comm/Version.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end
ns.AddonVersion = function() return "0.19.1" end

local function fresh()
  Stub.reset(); printed = {}
  ns.db = { features = {} }
  ns.newerVersion, ns.newerVersionTold = nil, nil
end

T.run("versions compare piece by piece, not as text", function()
  fresh()
  T.eq(ns.CompareVersions("0.19.1", "0.19.1"), 0)
  T.eq(ns.CompareVersions("0.9.0", "0.19.0"), -1, "9 is not more than 19")
  T.eq(ns.CompareVersions("1.0", "0.19.1"), 1)
  T.eq(ns.CompareVersions("0.19.2", "0.19.1"), 1)
  T.eq(ns.CompareVersions("0.19", "0.19.0"), 0, "a missing piece counts as zero")
  T.eq(ns.CompareVersions("", "0.1"), -1, "nonsense loses")
end)

T.run("a higher version from anyone is remembered and said once", function()
  fresh()
  T.eq(ns.NewerVersion(), nil)
  T.eq(ns.NoteVersion("0.19.0"), nil, "older than ours")
  T.eq(ns.NoteVersion("0.19.1"), nil, "the same as ours")
  T.eq(ns.NoteVersion("0.20.0"), "0.20.0")
  T.eq(ns.NewerVersion(), "0.20.0")
  T.eq(#printed, 1)
  T.truthy(printed[1]:find("version 0.20.0 is out", 1, true), printed[1])
  ns.NoteVersion("0.21.0")
  T.eq(ns.NewerVersion(), "0.21.0", "a higher one still updates")
  T.eq(#printed, 1, "but nobody is told twice")
  ns.NoteVersion("0.20.5")
  T.eq(ns.NewerVersion(), "0.21.0", "and a lower one does not walk it back")
end)

T.run("it speaks to the guild and the group, and only that", function()
  fresh()
  T.eq(ns.AnnounceVersion(), false, "alone, there is nobody to tell")
  Stub.guild = true
  T.eq(ns.AnnounceVersion(true), true)
  T.eq(#Stub.sent, 1)
  T.eq(Stub.sent[1].prefix, "ForeverBuddy")
  T.eq(Stub.sent[1].message, "V:0.19.1")
  T.eq(Stub.sent[1].channel, "GUILD")
  Stub.group = "party"
  Stub.sent = {}
  ns.AnnounceVersion(true)
  local channels = {}
  for _, message in ipairs(Stub.sent) do channels[message.channel] = true end
  T.eq(channels.PARTY, true); T.eq(channels.GUILD, true)
  Stub.group = "raid"
  Stub.sent = {}
  ns.AnnounceVersion(true)
  channels = {}
  for _, message in ipairs(Stub.sent) do channels[message.channel] = true end
  T.eq(channels.RAID, true); T.eq(channels.PARTY, nil, "a raid is not also a party")
end)

T.run("a busy guild is not chatted at", function()
  fresh()
  Stub.guild = true
  Stub.now = 100
  T.eq(ns.AnnounceVersion(true), true)
  Stub.sent = {}
  Stub.now = 120
  T.eq(ns.AnnounceVersion(), false, "twenty seconds later is too soon")
  Stub.now = 200
  T.eq(ns.AnnounceVersion(), true, "a minute later is fine")
end)

T.run("only our own prefix and shape is read", function()
  fresh()
  T.eq(ns.ReadVersionMessage("SomeoneElse", "V:9.9.9", "GUILD", "Someone"), nil)
  T.eq(ns.ReadVersionMessage("ForeverBuddy", "hello", "GUILD", "Someone"), nil)
  T.eq(ns.ReadVersionMessage("ForeverBuddy", "V:0.20.0", "GUILD", "Someone"), "0.20.0")
  T.eq(ns.NewerVersion(), "0.20.0")
end)

T.run("entering the world registers the prefix and says hello", function()
  fresh()
  Stub.guild = true
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  T.eq(Stub.registeredPrefix, "ForeverBuddy")
  T.eq(#Stub.sent, 0, "it waits for the world to finish loading first")
  T.eq(#Stub.timers, 1)
  Stub.timers[1].fn()
  T.truthy(#Stub.sent > 0, "nothing was announced")
  T.eq(Stub.sent[1].message, "V:0.19.1")
end)

T.run("a build out of the working repository keeps its mouth shut", function()
  fresh()
  ns.AddonVersion = function() return "1.0.1-dev" end
  Stub.guild = true
  T.eq(ns.IsReleaseVersion("1.0.1"), true)
  T.eq(ns.IsReleaseVersion("1.0.1-dev"), false)
  T.eq(ns.IsReleaseVersion("v1.0.1"), false)

  T.eq(ns.AnnounceVersion(true), false, "nothing is sent from an unreleased build")
  T.eq(#Stub.sent, 0)

  -- but it still hears a real release going past it
  T.eq(ns.NoteVersion("1.0.2"), "1.0.2")
  T.eq(ns.NewerVersion(), "1.0.2")
  -- and somebody else's dev build is not believed either
  T.eq(ns.NoteVersion("9.9.9-dev"), nil)
  T.eq(ns.NewerVersion(), "1.0.2")

  ns.AddonVersion = function() return "1.0.1" end
  T.eq(ns.AnnounceVersion(true), true, "a release speaks as before")
  T.eq(#Stub.sent, 1)
  ns.AddonVersion = function() return "0.19.1" end
end)

T.run("a dev build does not even open the channel, so nothing can reach it", function()
  fresh()
  ns.AddonVersion = function() return "1.0.1-dev" end
  Stub.guild = true
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  Stub.RunTimers()
  T.eq(Stub.registeredPrefix, nil, "the prefix is never registered, so the client delivers nothing")
  T.eq(#Stub.sent, 0)
  T.eq(ns.ReadVersionMessage("ForeverBuddy", "V:9.9.9", nil, "Someone"), nil, "and a message is ignored")
  T.eq(ns.NewerVersion(), nil)

  fresh()
  ns.AddonVersion = function() return "1.0.1" end
  Stub.guild = true
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  Stub.RunTimers()
  T.eq(Stub.registeredPrefix, "ForeverBuddy", "a release opens it as before")
  T.eq(#Stub.sent, 1)
  ns.AddonVersion = function() return "0.19.1" end
end)

T.finish()
