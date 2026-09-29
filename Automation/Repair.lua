local ADDON, ns = ...

ns.RegisterFeature({
  key = "autorepair",
  name = "Auto repair",
  desc = "Repairs all your gear when you open a vendor that can repair, if you can afford it.",
  default = true,
})

-- Returns "repaired", "unaffordable", or nil when there was nothing to do.
function ns.AutoRepair()
  if not CanMerchantRepair() then return nil end
  local cost, canRepair = GetRepairAllCost()
  if not canRepair or not cost or cost <= 0 then return nil end
  if GetMoney() < cost then
    ns.Print("repair skipped, it needs " .. GetMoneyString(cost, true))
    return "unaffordable"
  end
  RepairAllItems()
  ns.Print("repaired for " .. GetMoneyString(cost, true))
  return "repaired"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function()
  if ns.IsFeatureEnabled("autorepair") then ns.AutoRepair() end
end)
