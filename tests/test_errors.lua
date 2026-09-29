package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UI/Errors.lua" })

local function fresh()
  Stub.reset()
  ns.db = { features = {} }
  C_CVar.SetCVar("scriptErrors", "1")
end

T.run("the switch is registered, and on by default", function()
  fresh()
  T.eq(ns.featureIndex.hideerrors.name, "Hide Lua errors")
  T.eq(ns.IsFeatureEnabled("hideerrors"), true, "an addon's errors are nobody else's business")
end)

T.run("ticking it turns the game's own error popups off, and unticking puts them back", function()
  fresh()
  T.eq(ns.CurrentScriptErrors(), "1")
  ns.SetFeatureEnabled("hideerrors", false)
  T.eq(ns.CurrentScriptErrors(), "1", "unticking shows them again")
  T.eq(ns.errorsHidden, false)
  ns.SetFeatureEnabled("hideerrors", true)
  T.eq(ns.CurrentScriptErrors(), "0", "the console setting the game shows errors with")
  T.eq(ns.errorsHidden, true)
  ns.SetFeatureEnabled("hideerrors", false)
  T.eq(ns.CurrentScriptErrors(), "1")
  T.eq(ns.errorsHidden, false)
end)

T.run("a login applies whichever way the switch is set", function()
  fresh()
  Stub.FireEvent("PLAYER_LOGIN") -- fires once a session, as in the game
  T.eq(ns.CurrentScriptErrors(), "0", "on by default, so errors are hidden from the first login")
end)

T.run("the choice is applied without being told which way", function()
  fresh()
  ns.db.features.hideerrors = true
  T.eq(ns.ApplyErrorSetting(), true, "reads the switch when not given an answer")
  T.eq(ns.CurrentScriptErrors(), "0")
  ns.db.features.hideerrors = false
  T.eq(ns.ApplyErrorSetting(), false)
  T.eq(ns.CurrentScriptErrors(), "1")
end)

T.finish()
