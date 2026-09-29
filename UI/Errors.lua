local ADDON, ns = ...

-- Lua error popups are the game's own, switched by the scriptErrors console setting, which is
-- what /console scriptErrors 0 sets. Ticking this turns it off and unticking it puts it back.
-- Nothing is swallowed: an error still happens, you are simply not shown it.

local CVAR = "scriptErrors"

local function SetCVar(value)
  if not (C_CVar and C_CVar.SetCVar) then return false end
  return (pcall(C_CVar.SetCVar, CVAR, value))
end

function ns.CurrentScriptErrors()
  if not (C_CVar and C_CVar.GetCVar) then return nil end
  local ok, value = pcall(C_CVar.GetCVar, CVAR)
  return ok and value or nil
end

-- true when errors are hidden from now on, false when they are shown again, nil when this
-- client will not let us set it.
function ns.ApplyErrorSetting(hide)
  if hide == nil then hide = ns.IsFeatureEnabled("hideerrors") end
  if not SetCVar(hide and "0" or "1") then return nil end
  ns.errorsHidden = hide and true or false
  return ns.errorsHidden
end

ns.RegisterFeature({
  key = "hideerrors",
  name = "Hide Lua errors",
  desc = "Stops the game showing Lua error popups, from this addon or any other. Turn it off while you are chasing a bug: with it on, our own mistakes are silent too.",
  default = true,
  apply = function(enabled) ns.ApplyErrorSetting(enabled) end,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  ns.ApplyErrorSetting()
end)
