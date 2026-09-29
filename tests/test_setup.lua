package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

local registered = {}
Settings = {
  RegisterCanvasLayoutCategory = function(panel, name) table.insert(registered, name); return { name = name } end,
  RegisterAddOnCategory = function(category) table.insert(registered, "addon:" .. category.name) end,
}

-- The whole addon, in the order the TOC loads it, because the setup guide describes all of it.
local FILES = { "Data/Weights.lua", "Core.lua", "Comm/Version.lua", "UsedFor/QuestStatus.lua",
                "UsedFor/Verdict.lua", "UsedFor/Tooltip.lua", "Gear/Score.lua", "Tooltips/DeleteWarn.lua",
                "Bags/Marks.lua", "Tooltips/Appearance.lua", "Collect/Collector.lua",
                "Automation/Repair.lua", "Automation/SellJunk.lua", "Automation/AutoQuest.lua",
                "Automation/AutoEquip.lua", "Nav/Arrow.lua", "Nav/MapLevels.lua", "Nav/CityPins.lua",
                "UI/Window.lua", "UI/Home.lua", "UI/Journal.lua", "UI/Zones.lua", "UI/Abilities.lua",
                "UI/Settings.lua", "UI/Errors.lua", "Dungeons/Guide.lua", "Dungeons/Zones.lua", "Setup.lua" }
local ns = Stub.LoadAddon(FILES)
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function fresh(saved)
  Stub.reset(); printed = {}; registered = {}
  ForeverBuddyDB = saved or nil
  ns.db = saved or { features = {} }
  if _G.ForeverBuddySetupFrame then _G.ForeverBuddySetupFrame:Hide() end
end

local function pages()
  return #ns.SETUP_PAGES
end

T.run("a Settings category is registered where the client has that API", function()
  T.truthy(#registered >= 1, "nothing registered")
end)

T.run("the guide describes every page, and only pages that still exist", function()
  fresh()
  local titles = {}
  for _, page in ipairs(ns.SETUP_PAGES) do table.insert(titles, page.title) end
  T.eq(table.concat(titles, " / "),
    "Welcome to ForeverBuddy / Item uses on tooltips / At the vendor / Quests / "
    .. "Help improve the data / All set")
  for _, page in ipairs(ns.SETUP_PAGES) do
    for _, key in ipairs(page.features or {}) do
      T.truthy(ns.featureIndex[key] or key == "appearance",
        page.title .. " offers " .. key .. ", which nothing registers")
    end
  end
end)

T.run("a first install says the version once and opens the guide a moment later", function()
  fresh()
  ns.OnEnteringWorld()
  local said = table.concat(printed, "\n")
  T.truthy(said:find("v1.", 1, true) or said:find("loaded", 1, true), said)
  T.truthy(#Stub.timers > 0, "the guide was never scheduled")
  for _, timer in ipairs(Stub.timers) do timer.fn() end
  local frame = _G.ForeverBuddySetupFrame
  T.truthy(frame, "no setup frame"); T.eq(frame:IsShown(), true)
  T.eq(frame.counter:GetText(), ("1 of %d"):format(pages()))
end)

T.run("Next and Back walk the pages", function()
  fresh()
  local frame = ns.ShowSetup()
  T.eq(frame.counter:GetText(), ("1 of %d"):format(pages()))
  T.eq(frame.back:IsEnabled(), false, "there is nothing before the first page")
  frame.next:Click()
  T.eq(frame.counter:GetText(), ("2 of %d"):format(pages()))
  frame.back:Click()
  T.eq(frame.counter:GetText(), ("1 of %d"):format(pages()))
  T.eq(frame.next:GetText(), "Next")
end)

T.run("a page's ticks write the settings they describe", function()
  fresh()
  local frame = ns.ShowSetup()
  ns.SetupPage(3)                                  -- At the vendor
  local check = frame.pages[3].checks[1]
  T.eq(check.featureKey, "autorepair")
  T.eq(check:GetChecked(), true, "it opens showing what the setting is")
  check:Click()
  T.eq(ns.IsFeatureEnabled("autorepair"), false)
  ns.SetupPage(1); ns.SetupPage(3)
  T.eq(frame.pages[3].checks[1]:GetChecked(), false, "and shows it again when you come back")
end)

T.run("the last page lists what is on and off, and Finish remembers you saw it", function()
  fresh()
  local frame = ns.ShowSetup()
  ns.SetupPage(pages())
  T.eq(frame.next:GetText(), "Finish")
  T.eq(frame.skip:IsShown(), false, "nothing to skip on the last page")
  local summary = frame.pages[pages()].body:GetText()
  T.truthy(summary:find("On:", 1, true), summary)
  T.truthy(summary:find("Item uses on tooltips", 1, true), summary)
  frame.next:Click()
  T.eq(ns.db.setupDone, true)
  T.eq(frame:IsShown(), false)
end)

T.run("Skip closes it and still counts as seen", function()
  fresh()
  local frame = ns.ShowSetup()
  frame.skip:Click()
  T.eq(frame:IsShown(), false)
  T.eq(ns.db.setupDone, true, "or it would open again every login")
end)

T.run("/fb opens the welcome page, /fb settings the checklist, /fb setup the guide", function()
  fresh({ features = {}, setupDone = true })
  SlashCmdList.FOREVERBUDDY("")
  T.eq(_G.ForeverBuddyFrame.current, "home")
  SlashCmdList.FOREVERBUDDY("settings")
  T.eq(_G.ForeverBuddyFrame.current, "settings")
  ns.HideWindow()
  SlashCmdList.FOREVERBUDDY("setup")
  T.eq(_G.ForeverBuddySetupFrame:IsShown(), true)
  T.eq(_G.ForeverBuddySetupFrame.counter:GetText(), ("1 of %d"):format(pages()))
  _G.ForeverBuddySetupFrame:Hide()
end)

T.run("closing the checklist does not count as seeing the guide", function()
  fresh({ features = {} })
  ns.ShowOptions()
  ns.CloseOptions(true)
  T.eq(ns.db.optionsSeen, true)
  T.eq(ns.db.setupDone, nil, "the guide should still open on the next login")
end)

T.run("someone who has seen it is left alone", function()
  fresh({ features = {}, setupDone = true, seenVersion = ns.AddonVersion() })
  ns.OnEnteringWorld()
  T.eq(#printed, 0, "nothing to say: " .. table.concat(printed, " | "))
  for _, timer in ipairs(Stub.timers) do timer.fn() end
  T.eq(_G.ForeverBuddySetupFrame:IsShown(), false)
end)

T.run("if the guide cannot open, it says so instead of failing quietly", function()
  fresh()
  local real = ns.ShowSetup
  ns.ShowSetup = function() error("no frame for you") end
  ns.OnEnteringWorld()
  T.truthy(#Stub.timers > 0, "the guide was never scheduled")
  for _, timer in ipairs(Stub.timers) do timer.fn() end
  local said = table.concat(printed, "\n")
  T.truthy(said:find("could not open", 1, true), said)
  T.truthy(said:find("/fb setup", 1, true), "it should say how to try again")
  ns.ShowSetup = real
end)

T.finish()
