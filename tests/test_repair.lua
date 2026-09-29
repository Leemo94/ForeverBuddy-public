package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "Automation/Repair.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function merchant(canRepair, cost, money)
  Stub.reset(); printed = {}
  Stub.canRepair = canRepair; Stub.repairCost = cost; Stub.money = money
end

T.run("registers the autorepair feature, on by default", function()
  T.eq(ns.featureIndex.autorepair.name, "Auto repair")
  T.eq(ns.IsFeatureEnabled("autorepair"), true)
end)

T.run("repairs and reports the cost when affordable", function()
  merchant(true, 1234, 5000)
  Stub.FireEvent("MERCHANT_SHOW")
  T.eq(Stub.CallNames()[1], "RepairAllItems")
  T.eq(printed[1], "repaired for 1234c")
end)

T.run("skips with a message when unaffordable", function()
  merchant(true, 1234, 100)
  T.eq(ns.AutoRepair(), "unaffordable")
  T.eq(#Stub.calls, 0)
  T.eq(printed[1], "repair skipped, it needs 1234c")
end)

T.run("does nothing when the vendor cannot repair or nothing is damaged", function()
  merchant(false, 1234, 5000)
  T.eq(ns.AutoRepair(), nil)
  merchant(true, 0, 5000)
  T.eq(ns.AutoRepair(), nil)
  T.eq(#Stub.calls, 0); T.eq(#printed, 0)
end)

T.run("does nothing when the feature is off", function()
  merchant(true, 1234, 5000)
  ns.db = { features = { autorepair = false } }
  Stub.FireEvent("MERCHANT_SHOW")
  T.eq(#Stub.calls, 0)
  ns.db = nil
end)

T.finish()
