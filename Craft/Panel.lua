local ADDON, ns = ...

-- The shopping list beside the profession window. Click a recipe in Blizzard's list, press our
-- button, say how many you want, and this says what to go and get.
--
-- Everything that reaches into Blizzard's own frame is guarded: the profession window is loaded
-- on demand and its insides are theirs to rename. When we cannot find a piece of it the button
-- goes somewhere sensible instead of erroring, and the panel still works from /fb craft.

local PANEL_W, ROW_H, ICON = 290, 22, 18
local TAB_CLEARANCE = 56 -- the width of the profession buttons down the side, plus a gap
local HINT_H = 14

local panel, button

-- Which recipe is open on the right of the profession window. Several ways in, because the
-- frame has been rearranged before and will be again.
function ns.SelectedRecipeID()
  local frame = rawget(_G, "ProfessionsFrame")
  local form = frame and frame.CraftingPage and frame.CraftingPage.SchematicForm
  if form then
    if type(form.GetRecipeInfo) == "function" then
      local ok, info = pcall(form.GetRecipeInfo, form)
      if ok and type(info) == "table" and info.recipeID then return info.recipeID end
    end
    local info = rawget(form, "currentRecipeInfo")
    if type(info) == "table" and info.recipeID then return info.recipeID end
  end
  return nil
end

-- A recipe id is a spell id; our data is keyed by the item it makes.
local bySpell
function ns.ItemForRecipe(recipeID)
  if not recipeID then return nil end
  local schematic = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
  if schematic then
    local ok, info = pcall(schematic, recipeID, false)
    if ok and type(info) == "table" and info.outputItemID and ns.CraftingRecipe(info.outputItemID) then
      return info.outputItemID
    end
  end
  if not bySpell then
    bySpell = {}
    for item, row in pairs(ns.Crafting or {}) do bySpell[row[1]] = item end
  end
  return bySpell[recipeID]
end

-- The profession the open window is for, so we know what to break down and what to shop for.
function ns.OpenProfession()
  local item = ns.ItemForRecipe(ns.SelectedRecipeID())
  local recipe = item and ns.CraftingRecipe(item)
  return recipe and recipe.profession or nil
end

------------------------------------------------------------------------------
local function Row(parent, index, rows)
  local row = rows[index]
  if row then return row end
  row = CreateFrame("Frame", nil, parent)
  row:SetSize(PANEL_W - 24, ROW_H)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.SetFontSize(row.name, 13)
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWidth(PANEL_W - 130)
  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.SetFontSize(row.count, 13)
  row.count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.hint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ns.SetFontSize(row.hint, 11)
  row.hint:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, 0)
  row.hint:SetWidth(PANEL_W - 60)
  row.hint:SetJustifyH("LEFT")
  row.hint:SetTextColor(ns.SKIN.muted[1], ns.SKIN.muted[2], ns.SKIN.muted[3])
  rows[index] = row
  return row
end

local function Heading(parent, text, rows, index)
  local row = Row(parent, index, rows)
  row.icon:Hide()
  row.name:SetText(text)
  row.name:SetTextColor(ns.SKIN.gold[1], ns.SKIN.gold[2], ns.SKIN.gold[3])
  ns.SetFontSize(row.name, 14)
  row.count:SetText("")
  row.hint:SetText("")
  return row
end

-- "Bronze Bar 30, and Mining 65 would make those from Copper Bar 15, Tin Bar 15."
function ns.HintText(hint)
  if not hint then return nil end
  local bits = {}
  for _, pair in ipairs(hint.reagents) do
    table.insert(bits, ("%s x%d"):format(ns.CraftItemName(pair.item), pair.count))
  end
  if #bits == 0 then return nil end
  return ("%s %d: %s"):format(hint.profession, hint.skill, table.concat(bits, ", "))
end

-- Fills the panel from a plan. Returns how many rows it used, for the tests.
function ns.FillCraftPanel(frame, plan)
  local rows = frame.rows
  if not plan then
    frame.title:SetText("Nothing selected")
    for _, row in ipairs(rows) do row:Hide() end
    frame.used = 0
    return 0
  end
  frame.title:SetText(plan.name)
  -- A recipe that makes a batch says what the batch comes to, so "2" does not look like two
  -- bullets when it is four hundred.
  frame.subtitle:SetText(plan.makes > 1
    and ("%s %d  -  %d in all"):format(plan.profession, plan.skill, plan.produced)
    or ("%s %d"):format(plan.profession, plan.skill))

  local used, y = 0, 0
  local function place(row, height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, y)
    row:SetHeight(height)
    row:Show()
    y = y - height
  end

  -- What to go and get. The recipe's own reagent list is on Blizzard's window two inches to the
  -- left, so repeating it here only pushed the useful part off the bottom.
  used = used + 1
  place(Heading(frame.list, "Shopping", rows, used), ROW_H)
  for _, entry in ipairs(plan.base) do
    used = used + 1
    local row = Row(frame.list, used, rows)
    row.icon:SetTexture(ns.ItemIcon(entry.item))
    row.icon:Show()
    ns.SetFontSize(row.name, 13)
    row.name:SetText(ns.CraftItemName(entry.item))
    row.count:SetText(entry.have > 0 and ("%d / %d"):format(entry.have, entry.need) or tostring(entry.need))
    local colour = entry.short > 0 and ns.SKIN.body or ns.SKIN.muted
    row.count:SetTextColor(colour[1], colour[2], colour[3])
    row.name:SetTextColor(colour[1], colour[2], colour[3])
    local hint = ns.HintText(entry.hint)
    row.hint:SetText(hint or "")
    place(row, hint and (ROW_H + HINT_H) or ROW_H)
  end

  -- Then what to make with it, in the order you would make it.
  if #plan.steps > 0 then
    used = used + 1
    place(Heading(frame.list, "To make", rows, used), ROW_H + 6)
    for _, step in ipairs(plan.steps) do
      used = used + 1
      local row = Row(frame.list, used, rows)
      row.icon:SetTexture(ns.ItemIcon(step.item))
      row.icon:Show()
      ns.SetFontSize(row.name, 13)
      row.name:SetText(step.name)
      row.name:SetTextColor(ns.SKIN.body[1], ns.SKIN.body[2], ns.SKIN.body[3])
      row.count:SetText(ns.CraftStepCount(step))
      row.count:SetTextColor(ns.SKIN.body[1], ns.SKIN.body[2], ns.SKIN.body[3])
      row.hint:SetText(ns.CraftStepHint(step))
      place(row, ROW_H + HINT_H)
    end
  end

  for index = used + 1, #rows do rows[index]:Hide() end
  frame.list:SetHeight(math.max(10, -y))
  frame:SetHeight(math.min(520, 86 + (-y)))
  frame.used = used
  return used
end

------------------------------------------------------------------------------
local function Build()
  local frame = ns.Panel(UIParent, ns.SKIN.panel)
  frame:SetSize(PANEL_W, 300)
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  -- The profession goes in first, because the title is cut to whatever room it leaves. A fixed
  -- width cannot do that job: "Engineering 230" and "Leatherworking 310" are not the same size,
  -- and the long one ran straight through "Gnomish Net-o-Matic Projector".
  frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ns.SetFontSize(frame.subtitle, 11)
  frame.subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -16)
  frame.subtitle:SetTextColor(ns.SKIN.muted[1], ns.SKIN.muted[2], ns.SKIN.muted[3])

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ns.SetFontSize(frame.title, 17)
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  frame.title:SetPoint("RIGHT", frame.subtitle, "LEFT", -10, 0)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWordWrap(false)
  frame.title:SetTextColor(ns.SKIN.gold[1], ns.SKIN.gold[2], ns.SKIN.gold[3])

  frame.qtyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.SetFontSize(frame.qtyLabel, 14)
  frame.qtyLabel:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
  frame.qtyLabel:SetText("Qty:")
  frame.qtyLabel:SetTextColor(ns.SKIN.body[1], ns.SKIN.body[2], ns.SKIN.body[3])

  frame.qty = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.qty:SetSize(56, 20)
  frame.qty:SetPoint("LEFT", frame.qtyLabel, "RIGHT", 10, 0)
  frame.qty:SetAutoFocus(false)
  frame.qty:SetNumeric(true)
  frame.qty:SetMaxLetters(4)
  frame.qty:SetText("1")
  frame.qty:SetScript("OnTextChanged", function() ns.RefreshCraftPanel() end)
  frame.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  frame.qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
  frame.close:SetScript("OnClick", function() frame:Hide() end)

  frame.list = CreateFrame("Frame", nil, frame)
  frame.list:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -62)
  frame.list:SetSize(PANEL_W - 24, 10)
  frame.rows = {}
  frame:Hide()
  return frame
end

function ns.CraftPanel()
  panel = panel or Build()
  return panel
end

function ns.CraftPanelQuantity()
  local frame = ns.CraftPanel()
  return math.max(1, math.floor(tonumber(frame.qty:GetText()) or 1))
end

-- Works out the plan for whatever is selected and draws it.
function ns.RefreshCraftPanel()
  local frame = ns.CraftPanel()
  if not frame:IsShown() then return nil end
  local item = frame.item or ns.ItemForRecipe(ns.SelectedRecipeID())
  if not item then return ns.FillCraftPanel(frame, nil) end
  local recipe = ns.CraftingRecipe(item)
  local plan = ns.CraftingPlan(item, ns.CraftPanelQuantity(), {
    includeBank = true,
    profession = recipe and recipe.profession or nil,
    expandEverything = ns.db and ns.db.craftExpandAll or false,
  })
  return ns.FillCraftPanel(frame, plan)
end

function ns.ShowCraftPanel(item)
  local frame = ns.CraftPanel()
  frame.item = item or ns.ItemForRecipe(ns.SelectedRecipeID())
  local anchor = rawget(_G, "ProfessionsFrame")
  frame:ClearAllPoints()
  if anchor and anchor:IsShown() then
    -- The profession buttons hang off the right edge of that window, outside its own frame, so
    -- sitting flush against it lands on top of them.
    frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", TAB_CLEARANCE, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
  end
  frame:Show()
  ns.RefreshCraftPanel()
  return frame
end

------------------------------------------------------------------------------
-- The button on Blizzard's own window.
-- Parented to the crafting page rather than to the window, so it is only ever on screen when
-- that page is: the window also shows a summary of every profession you have, and a shopping
-- list button over the top of Mining's skill bar belongs to nothing.
local function ButtonParent()
  local frame = rawget(_G, "ProfessionsFrame")
  local page = frame and frame.CraftingPage
  if not page then return nil end
  return (page.SchematicForm or page), page
end

function ns.CraftButton()
  if button then return button end
  local parent = ButtonParent()
  if not parent then return nil end
  button = CreateFrame("Button", "ForeverBuddyCraftButton", parent, "UIPanelButtonTemplate")
  button:SetSize(96, 22)
  button:SetFrameStrata("HIGH")
  button:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
  button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)
  button:SetText("Shopping list")
  button:SetScript("OnClick", function()
    local frame = ns.CraftPanel()
    if frame:IsShown() and frame.item == ns.ItemForRecipe(ns.SelectedRecipeID()) then
      frame:Hide()
    else
      ns.ShowCraftPanel()
    end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Shopping list")
    GameTooltip:AddLine("Everything this recipe needs, broken down as far as this profession can make it.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return button
end

-- The window is loaded on demand, and which event announces it has moved between versions, so
-- every plausible one has a go. Making the button twice is not possible; not making it at all
-- would mean nobody can see the thing.
-- Up only when a recipe is actually open, so it does not sit on a page it means nothing on.
function ns.UpdateCraftButton()
  if not button then return nil end
  local shown = ns.SelectedRecipeID() ~= nil
  button:SetShown(shown)
  return shown
end

local function TryButton()
  local made = ns.CraftButton()
  ns.UpdateCraftButton()
  if made and not ns.craftButtonHooked and rawget(_G, "ProfessionsFrame") then
    ns.craftButtonHooked = true
    ProfessionsFrame:HookScript("OnShow", function() ns.CraftButton() end)
    ProfessionsFrame:HookScript("OnHide", function() ns.CraftPanel():Hide() end)
  end
  return made
end
ns.TryCraftButton = TryButton

-- A way in that does not depend on finding Blizzard's window at all.
ns.SlashHandlers.shopping = function(rest)
  local item = ns.FindCraftable(rest or "") or ns.ItemForRecipe(ns.SelectedRecipeID())
  if not item then
    ns.Print("open a profession and pick a recipe, or /fb shopping <item>")
    return nil
  end
  return ns.ShowCraftPanel(item)
end

-- Picking a recipe out of the list announces nothing: no event fires for it, so the button's
-- visibility was only ever recomputed when something else happened. Opening a profession ran the
-- check before Blizzard had restored the recipe you had open last, so the button hid, and it
-- stayed hidden until an event arrived - which is why switching to another profession and back
-- appeared to fix it. While the window is open, just look.
local POLL_SECONDS = 0.2

function ns.PollCraftButton()
  local frame = rawget(_G, "ProfessionsFrame")
  if not (frame and frame.IsShown and frame:IsShown()) then return nil end
  if not button then return ns.TryCraftButton() and ns.UpdateCraftButton() end
  return ns.UpdateCraftButton()
end

local events = CreateFrame("Frame")
local sinceLook = 0
events:SetScript("OnUpdate", function(self, elapsed)
  sinceLook = sinceLook + (elapsed or 0)
  if sinceLook < POLL_SECONDS then return end
  sinceLook = 0
  ns.PollCraftButton()
end)
for _, event in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
                         "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE",
                         "ITEM_DATA_LOAD_RESULT" }) do
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(self, event, name)
  if event == "ITEM_DATA_LOAD_RESULT" then
    if ns.CraftPanel():IsShown() then ns.RefreshCraftPanel() end
    return
  end
  if event == "TRADE_SKILL_CLOSE" then
    ns.CraftPanel():Hide()
    return
  end
  if event == "ADDON_LOADED" and name ~= "Blizzard_Professions" then return end
  TryButton()
  local frame = ns.CraftPanel()
  if frame:IsShown() then
    frame.item = ns.ItemForRecipe(ns.SelectedRecipeID()) or frame.item
    ns.RefreshCraftPanel()
  end
end)
