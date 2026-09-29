package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua" })

local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end
local function lastPrint() return printed[#printed] end

T.run("data tables default to empty when no Data files are loaded", function()
  T.eq(type(ns.Recipes), "table")
  T.eq(type(ns.Quests), "table")
end)

T.run("RegisterFeature keeps order, indexes by key, normalises default", function()
  local a = ns.RegisterFeature({ key = "alpha", name = "Alpha", desc = "first", default = true })
  local b = ns.RegisterFeature({ key = "beta", name = "Beta", desc = "second" })
  T.eq(ns.features[1], a); T.eq(ns.features[2], b)
  T.eq(ns.featureIndex.beta, b)
  T.eq(b.default, false)
  local ok = pcall(ns.RegisterFeature, { key = "alpha", name = "Dup" })
  T.eq(ok, false, "duplicate keys are rejected")
end)

T.run("IsFeatureEnabled: unknown false, defaults before the DB exists", function()
  T.eq(ns.IsFeatureEnabled("nope"), false)
  T.eq(ns.IsFeatureEnabled("alpha"), true)
  T.eq(ns.IsFeatureEnabled("beta"), false)
end)

T.run("SetFeatureEnabled before the DB loads warns and does nothing", function()
  T.eq(ns.SetFeatureEnabled("alpha", false), false)
  T.eq(lastPrint(), "settings are not loaded yet")
  T.eq(ns.IsFeatureEnabled("alpha"), true)
end)

T.run("ADDON_LOADED creates the DB shape and ignores other addons", function()
  ForeverBuddyDB = nil
  Stub.FireEvent("ADDON_LOADED", "SomeOtherAddon")
  T.eq(ForeverBuddyDB, nil)
  Stub.FireEvent("ADDON_LOADED", "ForeverBuddy")
  T.eq(ForeverBuddyDB.setupDone, false)
  T.eq(type(ForeverBuddyDB.features), "table")
  T.eq(ns.db, ForeverBuddyDB)
end)

T.run("SetFeatureEnabled writes the DB and IsFeatureEnabled reads it back", function()
  T.eq(ns.SetFeatureEnabled("alpha", false), true)
  T.eq(ForeverBuddyDB.features.alpha, false)
  T.eq(ns.IsFeatureEnabled("alpha"), false)
  T.eq(ns.SetFeatureEnabled("beta", true), true)
  T.eq(ns.IsFeatureEnabled("beta"), true)
  T.eq(ns.SetFeatureEnabled("nope", true), false)
  T.eq(lastPrint(), "unknown feature: nope")
end)

T.run("/fb with no window loaded prints usage", function()
  SlashCmdList.FOREVERBUDDY("")
  T.eq(lastPrint(), "usage: /fb | /fb settings | /fb setup | /fb list | /fb dungeon [name] | /fb zones [level] | /fb spec [key] | /fb <feature> on|off | /fb info")
end)

T.run("/fb always opens the welcome page, whatever was last open", function()
  local opened
  ns.ShowWindow = function(key) opened = key end
  SlashCmdList.FOREVERBUDDY("  ")
  T.eq(opened, "home")
  opened = nil
  SlashCmdList.FOREVERBUDDY("")
  T.eq(opened, "home")
  ns.ShowWindow = nil
end)

T.run("/fb setup opens the guided setup when Setup is loaded", function()
  local opened = false
  ns.ShowSetup = function() opened = true end
  SlashCmdList.FOREVERBUDDY("setup")
  T.eq(opened, true)
  ns.ShowSetup = nil
  SlashCmdList.FOREVERBUDDY("setup")
  T.eq(lastPrint(), "usage: /fb | /fb settings | /fb setup | /fb list | /fb dungeon [name] | /fb zones [level] | /fb spec [key] | /fb <feature> on|off | /fb info")
end)

T.run("modules can register /fb subcommands", function()
  local got
  ns.SlashHandlers.echo = function(rest) got = rest end
  SlashCmdList.FOREVERBUDDY("echo hello there")
  T.eq(got, "hello there")
  ns.SlashHandlers.echo = nil
end)

T.run("/fb info prints the data build line, then the client version and interface number", function()
  ns.DataInfo = { build = "1.15.9.69722", generated = "2026-09-13", recipes = 501, quests = 2755 }
  SlashCmdList.FOREVERBUDDY("INFO")
  T.eq(printed[#printed - 1], "data build 1.15.9.69722 generated 2026-09-13: 501 reagent items, 2755 quest items")
  if Stub.mainline then
    T.eq(lastPrint(), "client 12.1.5 build 69999, interface 120105, addon ?")
  else
    T.eq(lastPrint(), "client 1.15.9 build 69722, interface 11509, addon ?")
  end
  ns.DataInfo = nil
  SlashCmdList.FOREVERBUDDY("info")
  T.eq(printed[#printed - 1], "data build ? generated ?: 0 reagent items, 0 quest items")
end)

T.run("/fb list prints one line per feature with its state", function()
  printed = {}
  SlashCmdList.FOREVERBUDDY("list")
  T.eq(#printed, 2)
  T.eq(printed[1], "alpha off  Alpha")
  T.eq(printed[2], "beta on  Beta")
end)

T.run("/fb <feature> on|off sets and prints; bad input prints usage", function()
  SlashCmdList.FOREVERBUDDY("alpha on")
  T.eq(ns.IsFeatureEnabled("alpha"), true)
  T.eq(lastPrint(), "Alpha enabled")
  SlashCmdList.FOREVERBUDDY("Beta OFF")
  T.eq(ns.IsFeatureEnabled("beta"), false)
  T.eq(lastPrint(), "Beta disabled")
  SlashCmdList.FOREVERBUDDY("alpha maybe")
  T.eq(lastPrint(), "usage: /fb | /fb settings | /fb setup | /fb list | /fb dungeon [name] | /fb zones [level] | /fb spec [key] | /fb <feature> on|off | /fb info")
  SlashCmdList.FOREVERBUDDY("gamma on")
  T.eq(lastPrint(), "usage: /fb | /fb settings | /fb setup | /fb list | /fb dungeon [name] | /fb zones [level] | /fb spec [key] | /fb <feature> on|off | /fb info")
  T.eq(ns.IsFeatureEnabled("alpha"), true, "bad input changes nothing")
end)

T.run("ADDON_LOADED keeps saved values", function()
  ForeverBuddyDB = { setupDone = true, features = { alpha = false } }
  local fresh = Stub.LoadAddon({ "Core.lua" })
  fresh.RegisterFeature({ key = "alpha", name = "Alpha", default = true })
  Stub.FireEvent("ADDON_LOADED", "ForeverBuddy")
  T.eq(fresh.IsFeatureEnabled("alpha"), false)
  T.eq(ForeverBuddyDB.setupDone, true)
end)

T.run("switches are mirrored into the game's settings file", function()
  Stub.reset(); Stub.cvars = {}
  ForeverBuddyDB = nil
  Stub.FireEvent("ADDON_LOADED", "ForeverBuddy")
  ns.SetFeatureEnabled("beta", true)    -- default off
  ns.SetFeatureEnabled("alpha", false)  -- default on
  local text = Stub.cvars.ForeverBuddySettings
  T.truthy(text and text:find("beta:1", 1, true), tostring(text))
  T.truthy(text:find("alpha:0", 1, true))
  T.truthy(text:find("setup=0", 1, true))
end)

T.run("when the saved file comes back empty, the switches are restored from the settings file", function()
  Stub.reset()
  Stub.cvars = { ForeverBuddySettings = "v1;setup=1;f=beta:1,alpha:0" }
  ForeverBuddyDB = nil  -- the client did not hand our file back
  local fresh = Stub.LoadAddon({ "Core.lua" })
  fresh.Print = function() end
  fresh.RegisterFeature({ key = "alpha", name = "Alpha", default = true })
  fresh.RegisterFeature({ key = "beta", name = "Beta" })
  Stub.FireEvent("ADDON_LOADED", "ForeverBuddy")
  T.eq(fresh.savedLoaded, false)
  T.eq(fresh.restoredSettings, 2)
  T.eq(fresh.IsFeatureEnabled("beta"), true, "stayed on across the login")
  T.eq(fresh.IsFeatureEnabled("alpha"), false)
  T.eq(ForeverBuddyDB.setupDone, true, "the setup guide does not run again")
end)

T.run("a saved file that did load is left alone", function()
  Stub.reset()
  Stub.cvars = { ForeverBuddySettings = "v1;setup=1;f=beta:1" }
  ForeverBuddyDB = { features = { alpha = false }, setupDone = false, seenVersion = "0.9.4" }
  local fresh = Stub.LoadAddon({ "Core.lua" })
  fresh.Print = function() end
  fresh.RegisterFeature({ key = "alpha", name = "Alpha", default = true })
  fresh.RegisterFeature({ key = "beta", name = "Beta" })
  Stub.FireEvent("ADDON_LOADED", "ForeverBuddy")
  T.eq(fresh.savedLoaded, true)
  T.eq(fresh.restoredSettings, nil, "nothing restored over a file that loaded")
  T.eq(fresh.IsFeatureEnabled("alpha"), false, "the saved file wins")
  T.eq(fresh.IsFeatureEnabled("beta"), false, "the settings file did not override it")
  T.truthy(Stub.cvars.ForeverBuddySettings:find("alpha:0", 1, true), "the settings file is brought up to date")
end)

T.finish()
