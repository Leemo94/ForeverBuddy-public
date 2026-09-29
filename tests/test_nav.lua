package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

local ns = Stub.LoadAddon({ "Core.lua", "Nav/Arrow.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function fresh() Stub.reset(); printed = {}; ns.db = { features = {} }; ns.ClearWaypoint() end

T.run("the arrow reads the player's position, and nothing where the client hides it", function()
  fresh()
  Stub.position = { map = 1456, x = 0.7014, y = 0.3049, zone = "Thunder Bluff", sub = "" }
  local x, y = ns.PlayerMapXY()
  T.near(x, 0.7014); T.near(y, 0.3049)
  Stub.position = { map = nil, x = nil, y = nil, zone = "Ragefire Chasm", sub = "" }
  T.eq(ns.PlayerMapXY(), nil, "no position inside an instance")
end)

T.run("ArrowAngle: ahead is 0, a target to the west is a quarter turn left, facing is subtracted", function()
  fresh()
  T.near(ns.ArrowAngle(0, 0, 10, 0, 0), 0)
  T.near(ns.ArrowAngle(0, 0, 0, 10, 0), math.pi / 2)
  T.near(ns.ArrowAngle(0, 0, 0, 10, math.pi / 2), 0, "facing west already")
  T.near(ns.ArrowAngle(0, 0, -10, 0, 0), math.pi)
end)

T.run("waypoint: our arrow shows title, rotates and reports distance; cleared by the command", function()
  fresh()
  Stub.position = { map = 1456, x = 0.5, y = 0.5, zone = "Thunder Bluff", sub = "" }
  Stub.facing = 0
  local wp = ns.SetWaypoint(1456, 50, 60, "Testing an Enemy's Strength: Rahauro")
  T.truthy(wp); T.eq(wp.tomtom, nil)
  local f = _G.ForeverBuddyArrow
  T.eq(f:IsShown(), true); T.eq(f.title:GetText(), "Testing an Enemy's Strength: Rahauro")
  T.eq(f.dist:GetText(), "100 yd", "0.1 of the map at 1000 yd per map")
  local status = ns.WaypointStatus()
  T.near(status.angle, math.pi / 2, "target is +y (west) of the player")
  Stub.facing = math.pi / 2
  ns.UpdateArrow()
  T.near(ns.WaypointStatus().angle, 0)
  Stub.position.x, Stub.position.y = 0.5, 0.605
  T.eq(ns.UpdateArrow().distance < 10, true); T.eq(f.dist:GetText(), "you are here")
  SlashCmdList.FOREVERBUDDY("arrow")
  T.eq(printed[#printed], "arrow: Testing an Enemy's Strength: Rahauro, 5 yd away")
  SlashCmdList.FOREVERBUDDY("arrow clear")
  T.eq(f:IsShown(), false); T.eq(ns.ActiveWaypoint(), nil)
  SlashCmdList.FOREVERBUDDY("arrow")
  T.truthy(printed[#printed]:find("no arrow set", 1, true))
end)

T.run("waypoint reasons: hidden position in instances, another continent", function()
  fresh()
  ns.SetWaypoint(1456, 50, 60, "x")
  Stub.position = { map = nil, x = nil, y = nil, zone = "Ragefire Chasm", sub = "" }
  T.eq(ns.UpdateArrow(), "your position is hidden here")
  Stub.position = { map = 1436, x = 0.5, y = 0.5, zone = "Westfall", sub = "" }
  Stub.continents = { [1436] = 0, [1456] = 1 }
  T.eq(ns.UpdateArrow(), "on another continent")
end)

T.run("with TomTom loaded, the waypoint goes to TomTom and our arrow stays hidden", function()
  fresh()
  local got
  TomTom = { AddWaypoint = function(self, map, x, y, opts) got = { map = map, x = x, y = y, title = opts.title, crazy = opts.crazy } end }
  local wp = ns.SetWaypoint(1456, 50, 60, "Rahauro")
  T.eq(wp.tomtom, true); T.eq(got.map, 1456); T.near(got.x, 0.5); T.near(got.y, 0.6); T.eq(got.title, "Rahauro"); T.eq(got.crazy, true)
  T.eq(_G.ForeverBuddyArrow:IsShown(), false)
  TomTom = nil
end)

T.finish()
