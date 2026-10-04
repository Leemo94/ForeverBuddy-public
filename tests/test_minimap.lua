package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "Comm/Version.lua", "UI/Window.lua", "UI/Home.lua", "UI/Settings.lua", "UI/Minimap.lua" })

local function fresh()
  Stub.reset()
  ns.db = { features = {} }
  local b = ns.MinimapButton()
  b.points = {}
  function b:SetPoint(point, parent, relative, x, y) table.insert(self.points, { x, y }) end
  function b:ClearAllPoints() end
  return b
end

-- Where the button ended up, as x, y from the minimap centre.
local function lastPoint(b)
  local p = b.points[#b.points]
  return p and p[1], p and p[2]
end

T.run("the switch is registered, and on by default", function()
  fresh()
  T.eq(ns.featureIndex.minimapbutton.name, "Minimap button")
  T.eq(ns.IsFeatureEnabled("minimapbutton"), true)
end)

T.run("the button is built once, named, and wears our own logo", function()
  local b = fresh()
  T.eq(b:GetName(), "ForeverBuddyMinimapButton")
  T.eq(b.icon:GetTexture(), "Interface\\AddOns\\ForeverBuddy\\Media\\logo")
  T.eq(b.border:GetTexture(), "Interface\\Minimap\\MiniMap-TrackingBorder")
  T.eq(ns.MinimapButton(), b, "asking again gives the same button, not a second one")
end)

T.run("it sits on the ring, and moves where it is told", function()
  local b = fresh()
  ns.SetMinimapAngle(0)
  local x, y = lastPoint(b)
  T.eq(math.floor(x + 0.5), 80, "due right of the centre")
  T.eq(math.floor(y + 0.5), 0)
  ns.SetMinimapAngle(90)
  x, y = lastPoint(b)
  T.eq(math.floor(x + 0.5), 0)
  T.eq(math.floor(y + 0.5), 80, "straight above it")
  T.eq(ns.SetMinimapAngle(-90), 270, "an angle is kept between 0 and 360")
  T.eq(ns.MinimapAngle(), 270)
end)

T.run("the switch shows and hides it, and a login applies whichever way it is set", function()
  local b = fresh()
  T.eq(ns.ApplyMinimapButton(), true)
  T.eq(b:IsShown(), true)
  ns.SetFeatureEnabled("minimapbutton", false)
  T.eq(b:IsShown(), false, "unticking takes it off the minimap")
  ns.SetFeatureEnabled("minimapbutton", true)
  T.eq(b:IsShown(), true)

  b:Hide()
  Stub.FireEvent("PLAYER_LOGIN")
  T.eq(b:IsShown(), true, "it comes back on its own at login")
end)

T.run("left click opens the window and closes it again, right click opens the settings", function()
  local b = fresh()
  b.scripts.OnClick(b, "LeftButton")
  T.eq(_G.ForeverBuddyFrame:IsShown(), true)
  T.eq(_G.ForeverBuddyFrame.current, "home", "the welcome page, as /fb does")
  b.scripts.OnClick(b, "LeftButton")
  T.eq(_G.ForeverBuddyFrame:IsShown(), false, "a second click puts it away")
  b.scripts.OnClick(b, "RightButton")
  T.eq(_G.ForeverBuddyFrame:IsShown(), true)
  T.eq(_G.ForeverBuddyFrame.current, "settings")
  ns.HideWindow()
end)

T.run("dragging follows the cursor and is written down once, on drop", function()
  local b = fresh()
  ns.SetMinimapAngle(180)
  function Minimap:GetCenter() return 500, 500 end
  function Minimap:GetEffectiveScale() return 1 end
  _G.GetCursorPosition = function() return 580, 500 end -- due right of the centre

  T.eq(math.floor(ns.MinimapCursorAngle() + 0.5), 0)
  b.scripts.OnDragStart(b)
  T.truthy(b:GetScript("OnUpdate"), "it follows the cursor while held")
  b:GetScript("OnUpdate")(b)
  T.eq(math.floor(ns.MinimapAngle() + 0.5), 0, "the button has moved with the cursor")
  T.truthy(C_CVar.GetCVar("ForeverBuddySettings"):find("m=180", 1, true),
    "but the settings are not rewritten on every frame of the drag")

  b.scripts.OnDragStop(b)
  T.eq(b:GetScript("OnUpdate"), nil)
  T.truthy(C_CVar.GetCVar("ForeverBuddySettings"):find("m=0", 1, true), "the drop writes where it landed")
  _G.GetCursorPosition = nil
end)

T.run("where it was dragged to survives a login that loses the saved file", function()
  fresh()
  ns.SetMinimapAngle(137)
  local text = ns.SettingsString()
  T.truthy(text:find("m=137", 1, true), text)

  ns.db = { features = {} } -- the beta client handing us an empty file
  T.eq(ns.MinimapAngle(), 205, "the default until it is restored")
  ns.RestoreSettingsFallback()
  T.eq(ns.MinimapAngle(), 137)
end)

T.run("a client with no cursor to read leaves the button where it is", function()
  fresh()
  ns.SetMinimapAngle(90)
  _G.GetCursorPosition = nil
  T.eq(ns.MinimapCursorAngle(), nil)
  local b = ns.MinimapButton()
  b.scripts.OnDragStart(b)
  b:GetScript("OnUpdate")(b)
  T.eq(ns.MinimapAngle(), 90, "nothing moved")
  b.scripts.OnDragStop(b)
end)

T.finish()
