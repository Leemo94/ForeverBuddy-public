local ADDON, ns = ...

-- The dungeon journal: a grid of dungeon covers, and behind each one the quest chains that lead
-- into it, drawn as a tree the way the quest log never does. Data from Data/Dungeons.lua; the
-- status of every quest is live from your own quest log.


-- SHELVED while "Where to level" grows to carry dungeons itself. The journal promises every
-- quest for a dungeon and can only keep that promise for the ones Questie wrote down: of
-- Forever's own dungeons, one has seven quests and the other eight have none at all. A screen
-- that is mostly empty cards teaches people not to open it.
--
-- Nothing is deleted. The code and its tests are untouched, the data it reads is still built
-- and still feeds the levelling screen, and ns.RegisterJournalScreen() turns it back on in one
-- line once the quest scanner has filled the gaps in.
local SHIPPING = false
ns.JournalShipping = SHIPPING -- Dungeons/Guide.lua shelves /fb dungeon alongside it

local CARD_W, CARD_H, CARD_GAP, CARD_COLUMNS = 396, 92, 10, 2
local NODE_W, NODE_H, NODE_GAP_X, NODE_GAP_Y = 248, 54, 18, 16
local TREE_COLUMNS = 3
local NAME_HEIGHT = 26            -- two lines of the name, so the subtitle never rides over it

-- A dungeon's own loading screen sits behind its card. The band is the middle of the picture:
-- the logo and the tip text live at the top and bottom of a loading screen, and the middle is
-- also close to the shape of the card, so nothing is stretched.
local ART_TOP, ART_BOTTOM = 0.32, 0.66

-- The sizes the layout is built from, so a test can prove the tree still fits the window.
ns.TREE_METRICS = { columns = TREE_COLUMNS, nodeWidth = NODE_W, nodeHeight = NODE_H,
                    gapX = NODE_GAP_X, nameHeight = NAME_HEIGHT }

local FACTION_ICON = {
  Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
  Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
}

-- A tick on what you have finished and a question mark on what is in your log, so a step you
-- have already done reads at a glance instead of by the colour of its name.
local STATUS_MARK = {
  done = "Interface\\RaidFrame\\ReadyCheck-Ready",
  active = "Interface\\GossipFrame\\ActiveQuestIcon",
}

-- The side a dungeon belongs to, for the emblem on its card. Quests decide it: every quest in
-- the Deadmines is an Alliance quest, so a Horde player should see whose it is rather than a
-- bare zero. Only when the quests say nothing does the city holding the entrance stand in.
function ns.DungeonFaction(dungeon)
  local only, count = nil, 0
  for _, q in ipairs(dungeon.quests) do
    if not q.faction then return dungeon.faction or nil end -- a quest for both sides settles it
    if only and q.faction ~= only then return dungeon.faction or nil end
    only = q.faction
    count = count + 1
  end
  -- One quest is not evidence that a dungeon belongs to a side; it is usually evidence that we
  -- have only written one up. The Excavation Site sits in Wetlands with a single Horde quest
  -- found so far, and flying a Horde emblem over it would be a guess.
  if count < 2 then return dungeon.faction or nil end
  return only or dungeon.faction or nil
end

-- How many of a dungeon's quests this character could take, or every quest in it when the
-- filter is off: someone on the other side still wants to answer a friend's question.
function ns.DungeonQuestCount(dungeon, onlyMine)
  if onlyMine == nil then onlyMine = true end
  local mine, done = 0, 0
  for _, q in ipairs(dungeon.quests) do
    if not onlyMine or ns.CanTakeQuest(q) then
      mine = mine + 1
      if ns.DungeonQuestStatus(q) == "done" then done = done + 1 end
    end
  end
  return mine, done
end

-- Every chain that leads into a dungeon, as columns of nodes. A node is one step: pick this up,
-- hand this in, or find this item. Quests that share a first step share a column.
function ns.DungeonChains(dungeon, onlyMine)
  local columns, byRoot = {}, {}
  for _, q in ipairs(dungeon.quests) do
    if not onlyMine or ns.CanTakeQuest(q) then
      local root = (q.pre and q.pre[1] and q.pre[1].id) or q.id
      local column = byRoot[root]
      if not column then
        column = { root = root, nodes = {}, seen = {} }
        byRoot[root] = column
        table.insert(columns, column)
      end
      for _, step in ipairs(q.pre or {}) do
        if not column.seen[step.id] then
          column.seen[step.id] = true
          table.insert(column.nodes, { name = step.name, id = step.id, place = step.giver, kind = "pickup",
                                       faction = step.faction or nil, leadsTo = q })
        end
      end
      if not column.seen[q.id] then
        column.seen[q.id] = true
        local kind = (q.giver and q.giver.kind == "item") and "item" or "pickup"
        table.insert(column.nodes, { name = q.name, id = q.id, place = q.giver, kind = kind, quest = q, level = q.level })
        if q.turnin and (not q.giver or q.turnin.name ~= q.giver.name) then
          table.insert(column.nodes, { name = q.name, id = q.id, place = q.turnin, kind = "turnin", quest = q })
        end
      end
    end
  end
  -- Earliest chain first, by the lowest quest level anywhere in the column.
  for _, column in ipairs(columns) do
    local lowest
    for _, node in ipairs(column.nodes) do
      if node.level and (not lowest or node.level < lowest) then lowest = node.level end
    end
    column.level = lowest or 0
  end
  table.sort(columns, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return (a.nodes[1] and a.nodes[1].name or "") < (b.nodes[1] and b.nodes[1].name or "")
  end)
  return columns
end

local STATUS_WORD = { active = "In your log", done = "Done", repeatable = "Repeatable" }

-- Grey still to pick up, orange in your log, green done.
local SUB_COLOR = {
  active = { 1, 0.55, 0.1 },
  done = { 0.25, 0.85, 0.35 },
  repeatable = { 0.4, 0.7, 1 },
}
local SUB_PLAIN = { 0.6, 0.6, 0.6 }

function ns.SubtitleColor(status)
  return SUB_COLOR[status] or SUB_PLAIN
end

-- Where a step stands. A prerequisite is often not flagged on its own, because the game only
-- remembers the one of its versions you took; holding the quest it leads to is proof enough
-- that you are past it.
function ns.NodeStatus(node)
  if node.quest then return ns.DungeonQuestStatus(node.quest) end
  if C_QuestLog.IsQuestFlaggedCompleted(node.id) then return "done" end
  if node.leadsTo then
    local later = ns.DungeonQuestStatus(node.leadsTo)
    if later == "done" or later == "active" then return "done" end
  end
  return "available"
end

-- "Pick up in Orgrimmar", and for a quest coloured by faction rather than progress, the
-- progress moves here: "Done - Pick up in Orgrimmar".
function ns.NodeSubtitle(node, status, showStatus)
  local where = node.place and (node.place.where or node.place.name)
  local text
  if node.kind == "item" then
    text = "Starts from an item"
  elseif node.kind == "turnin" then
    text = where and ("Turn in at " .. where) or "Turn in"
  else
    text = where and ("Pick up in " .. where) or "Pick up"
  end
  local word = showStatus and STATUS_WORD[status]
  return word and (word .. " - " .. text) or text
end

------------------------------------------------------------------------------
-- Browse: the grid of dungeon covers
------------------------------------------------------------------------------
local function CardClicked(card)
  ns.SelectScreen("journal", card.dungeon)
end

local function BuildCard(parent, index)
  local card = CreateFrame("Button", nil, parent)
  card:SetSize(CARD_W, CARD_H)
  -- The frame sits under everything, so the dark panel and the picture cover all but its 1px edge.
  card.edge = card:CreateTexture(nil, "BACKGROUND", nil, 0)
  card.edge:SetPoint("TOPLEFT", card, "TOPLEFT", -1, 1)
  card.edge:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 1, -1)
  card.edge:SetColorTexture(0.45, 0.36, 0.17, 0.9)
  card.bg = card:CreateTexture(nil, "BACKGROUND", nil, 1)
  card.bg:SetAllPoints()
  card.bg:SetColorTexture(0.07, 0.07, 0.10, 0.94)
  card.art = card:CreateTexture(nil, "BORDER", nil, 0)
  card.art:SetAllPoints()
  card.art:SetTexCoord(0, 1, ART_TOP, ART_BOTTOM)
  card.art:SetVertexColor(0.85, 0.85, 0.85)
  card.scrim = card:CreateTexture(nil, "BORDER", nil, 1)
  card.scrim:SetAllPoints()
  card.scrim:SetColorTexture(1, 1, 1, 1)
  ns.DarkenLeft(card.scrim)
  card:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
  card.name:SetShadowOffset(1, -1)
  card.level = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  card.level:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 10)
  card.level:SetShadowOffset(1, -1)
  card.count = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  card.count:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -11)
  card.count:SetShadowOffset(1, -1)
  card.faction = card:CreateTexture(nil, "OVERLAY")
  card.faction:SetSize(20, 20)
  card.faction:SetPoint("RIGHT", card.count, "LEFT", -6, 0)
  card:SetScript("OnClick", function(self) CardClicked(self) end)
  return card
end

local function ShowBrowse(page)
  page.detail:Hide()
  page.browse:Show()
  page.selected = false -- back on the grid, so the filter switch refreshes the grid
  local onlyMine = page.onlyMine:GetChecked() and true or false
  local level = UnitLevel("player") or 1
  local shown = 0
  for i, dungeon in ipairs(ns.Dungeons or {}) do
    local card = page.cards[i]
    if not card then
      card = BuildCard(page.content, i)
      page.cards[i] = card
    end
    local column, row = (shown % CARD_COLUMNS), math.floor(shown / CARD_COLUMNS)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", page.content, "TOPLEFT", column * (CARD_W + CARD_GAP), -row * (CARD_H + CARD_GAP))
    card.dungeon = dungeon
    card.name:SetText(dungeon.name)
    local mine, done = ns.DungeonQuestCount(dungeon, onlyMine)
    card.count:SetText(("%d quest%s"):format(mine, mine == 1 and "" or "s"))
    local c = mine == 0 and ns.COLORS.grey or (done == mine and ns.COLORS.done or ns.COLORS.available)
    card.count:SetTextColor(c[1], c[2], c[3])
    card.level:SetText(ns.DungeonLevelText(dungeon))
    if dungeon.screen then
      card.art:SetTexture(dungeon.screen)
      card.art:Show()
      card.scrim:Show()
    else
      card.art:Hide()
      card.scrim:Hide()
    end
    local side = ns.DungeonFaction(dungeon)
    if side and FACTION_ICON[side] then
      card.faction:SetTexture(FACTION_ICON[side])
      card.faction:Show()
    else
      card.faction:Hide()
    end
    -- Nothing to measure yourself against on an untuned dungeon, so it is never "yours yet".
    local lo = ns.DungeonLevels(dungeon)
    local fits = lo ~= nil and level >= lo - 2
    card.name:SetTextColor(fits and 1 or 0.6, fits and 0.82 or 0.6, fits and 0 or 0.6)
    card:Show()
    shown = shown + 1
  end
  for i = shown + 1, #page.cards do page.cards[i]:Hide() end
  page.content:SetHeight(math.max(10, math.ceil(shown / CARD_COLUMNS) * (CARD_H + CARD_GAP)))
  page.heading:SetText("Browse dungeons")
  page.subheading:SetText(("Select a dungeon to see its quests. %d dungeons, your level is %d. Counts are %s."):format(
    shown, level, onlyMine and "quests you can take" or "every quest, either side"))
  page.shownCards = shown
  return shown
end

------------------------------------------------------------------------------
-- Detail: the quest tree for one dungeon
------------------------------------------------------------------------------
local function NodeClicked(node)
  -- A step with no quest of its own (a prerequisite, or a turn-in) still knows its place.
  if not node.quest then
    local p = node.place
    if not (p and p.map and p.x and p.y) then
      ns.Print(("%s has no known position"):format(p and p.name or node.name))
      return nil
    end
    local title = ("%s: %s"):format(node.name, p.name)
    ns.SetWaypoint(p.map, p.x, p.y, title)
    ns.Print("arrow set: " .. title)
    return title
  end
  local status = ns.DungeonQuestStatus(node.quest)
  local mapID, x, y, title = ns.DungeonQuestTarget(node.quest, status)
  if not mapID then
    ns.Print(x)
    return nil
  end
  ns.SetWaypoint(mapID, x, y, title)
  ns.Print("arrow set: " .. title)
  return title
end

-- Every chain gets a panel of its own with a bar down its left edge. Without it a quest that
-- happens to sit under another one reads as the next step of that chain.
local function ChainPanel(page, index)
  local panel = page.chains[index]
  if not panel then
    panel = { fill = page.treeContent:CreateTexture(nil, "BACKGROUND", nil, 0),
              bar = page.treeContent:CreateTexture(nil, "BACKGROUND", nil, 1) }
    panel.fill:SetColorTexture(0.05, 0.05, 0.04, 0.6)
    panel.bar:SetColorTexture(0.45, 0.36, 0.17, 0.9)
    page.chains[index] = panel
  end
  return panel
end

local function BuildNode(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(NODE_W, NODE_H)
  b.edge = b:CreateTexture(nil, "BACKGROUND", nil, 0)
  b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
  b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(0.42, 0.34, 0.18, 0.85)
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.bg:SetAllPoints()
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b.faction = b:CreateTexture(nil, "ARTWORK")
  b.faction:SetSize(14, 14)
  b.faction:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -6)
  b.faction:SetTexCoord(0.08, 0.58, 0.06, 0.55) -- crop the banner art down to the emblem
  -- The name gets two lines and no more; the subtitle gets one and is cut short rather than
  -- wrapped. Between them nothing can grow into its neighbour.
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -6)
  b.name:SetWidth(NODE_W - 16)
  b.name:SetHeight(NAME_HEIGHT)
  b.name:SetJustifyH("LEFT")
  b.name:SetJustifyV("TOP")
  ns.LimitLines(b.name, 2)
  b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.sub:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 7)
  b.sub:SetWidth(NODE_W - 16)
  b.sub:SetJustifyH("LEFT")
  b.sub:SetWordWrap(false)
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetSize(16, 16)
  b.mark:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -4)
  b.link = b:CreateTexture(nil, "ARTWORK")
  b.link:SetColorTexture(0.45, 0.36, 0.17, 0.9)
  b.link:SetSize(2, NODE_GAP_Y)
  b.link:SetPoint("TOP", b, "BOTTOM", 0, 0)
  b:SetScript("OnClick", function(self) NodeClicked(self.node) end)
  b:SetScript("OnEnter", function(self) ns.ShowNodeTooltip(self) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- Everything known about one step, on hover.
function ns.NodeTooltipLines(node)
  local q = node.quest
  local lines = { node.level and ("[%d] %s"):format(node.level, node.name) or node.name }
  if q then
    local share = ns.QuestShareText(q)
    if share then table.insert(lines, share) end -- nil when nobody knows yet
  end
  local place = node.place
  if place then
    local where = ns.PlaceText and ns.PlaceText(place) or place.name
    table.insert(lines, (node.kind == "turnin" and "Turn in: " or "Pick up: ") .. tostring(where))
  end
  if q and q.pre and #q.pre > 0 then
    local chain = ns.ChainText(q.pre)
    if chain then table.insert(lines, "Before it: " .. chain) end
  end
  for _, reward in ipairs((ns.QuestRewards and ns.QuestRewards[node.id]) or {}) do
    local itemLevel = reward[4] and reward[4] > 0 and (" (item level %d)"):format(reward[4]) or ""
    table.insert(lines, "Reward: " .. ns.QualityText(reward[2], reward[3]) .. itemLevel)
  end
  if q and q.note then table.insert(lines, q.note) end
  if q and q.classes and q.classes ~= 0 then table.insert(lines, ns.ClassListText(q.classes) .. " only") end
  table.insert(lines, "Click for an arrow to it.")
  return lines
end

function ns.ShowNodeTooltip(button)
  local node = button.node
  if not node then return nil end
  local lines = ns.NodeTooltipLines(node)
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  for i, line in ipairs(lines) do
    if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
  end
  GameTooltip:Show()
  return lines
end

local STATUS_COLOR = { active = "active", available = "available", done = "done", repeatable = "repeatable" }

-- One side's quest takes that side's colour; anything either side can take is coloured by how
-- far you are through it.
function ns.NodeNameColor(quest, status)
  local faction = quest and quest.faction
  if faction == "Horde" then return ns.COLORS.horde, true end
  if faction == "Alliance" then return ns.COLORS.alliance, true end
  return ns.COLORS[STATUS_COLOR[status] or "white"], false
end

local function ShowDetail(page, dungeon)
  page.browse:Hide()
  page.detail:Show()
  page.selected = dungeon
  page.heading:SetText(dungeon.name)
  local onlyMine = page.onlyMine:GetChecked() and true or false
  local mine, done = ns.DungeonQuestCount(dungeon, onlyMine)
  page.subheading:SetText(("%s. %d quest%s %s, %d done. Click a step for an arrow to it.")
    :format(ns.DungeonLevelText(dungeon, "long"), mine, mine == 1 and "" or "s",
            onlyMine and "for you" or "in all", done))

  local columns = ns.DungeonChains(dungeon, onlyMine)
  local used, x, y, rowHeight = 0, 0, 0, 0
  for index, column in ipairs(columns) do
    local col = (index - 1) % TREE_COLUMNS
    if col == 0 and index > 1 then
      y = y - rowHeight - NODE_GAP_Y * 3
      rowHeight = 0
    end
    local nodeY = y
    for depth, node in ipairs(column.nodes) do
      used = used + 1
      local b = page.nodes[used]
      if not b then
        b = BuildNode(page.treeContent)
        page.nodes[used] = b
      end
      b.node = node
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", page.treeContent, "TOPLEFT", col * (NODE_W + NODE_GAP_X), nodeY)
      b.name:SetText(node.level and ("[%d] %s"):format(node.level, node.name) or node.name)
      local status = ns.NodeStatus(node)
      -- A quest for one side wears its emblem and its colour; a neutral one is coloured by how
      -- far you are through it, so the subtitle carries the status for the coloured ones.
      -- A step with no quest of its own still belongs to a side: the Defias chain is Alliance
      -- from its first step, because only Alliance can talk to the man who starts it.
      local faction = (node.quest and node.quest.faction) or node.faction
      local colour = ns.NodeNameColor(node.quest or { faction = faction }, status)
      b.name:ClearAllPoints()
      if faction and FACTION_ICON[faction] then
        b.faction:SetTexture(FACTION_ICON[faction])
        b.faction:Show()
        b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 24, -6)
        b.name:SetWidth(NODE_W - 52)
      else
        b.faction:Hide()
        b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -6)
        b.name:SetWidth(NODE_W - 36)
      end
      b.name:SetTextColor(colour[1], colour[2], colour[3])
      if STATUS_MARK[status] then
        b.mark:SetTexture(STATUS_MARK[status])
        b.mark:Show()
      else
        b.mark:Hide()
      end
      -- Every step says where it stands, prerequisites included; they carry no colour of their own.
      b.sub:SetText(ns.NodeSubtitle(node, status, true))
      local sub = ns.SubtitleColor(status)
      b.sub:SetTextColor(sub[1], sub[2], sub[3])
      b.bg:SetColorTexture(0.19, 0.17, 0.14, 0.95)
      b.link:SetShown(depth < #column.nodes)
      b.status = status
      b:Show()
      nodeY = nodeY - NODE_H - NODE_GAP_Y
    end
    local extent = #column.nodes * NODE_H + math.max(0, #column.nodes - 1) * NODE_GAP_Y
    local panel = ChainPanel(page, index)
    panel.fill:ClearAllPoints()
    panel.fill:SetPoint("TOPLEFT", page.treeContent, "TOPLEFT", col * (NODE_W + NODE_GAP_X) - 7, y + 7)
    panel.fill:SetSize(NODE_W + 14, extent + 14)
    panel.fill:Show()
    panel.bar:ClearAllPoints()
    panel.bar:SetPoint("TOPLEFT", panel.fill, "TOPLEFT", 0, 0)
    panel.bar:SetSize(3, extent + 14)
    panel.bar:Show()
    local height = #column.nodes * (NODE_H + NODE_GAP_Y)
    if height > rowHeight then rowHeight = height end
  end
  for i = used + 1, #page.nodes do page.nodes[i]:Hide() end
  for i = #columns + 1, #page.chains do
    page.chains[i].fill:Hide()
    page.chains[i].bar:Hide()
  end
  page.treeContent:SetHeight(math.max(10, -y + rowHeight + 20))
  page.shownNodes = used
  page.shownColumns = #columns
  return columns
end

------------------------------------------------------------------------------
local function Build(page)
  page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -6)
  page.subheading = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.subheading:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -4)

  page.back = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  page.back:SetSize(90, 22)
  page.back:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -4)
  page.back:SetText("All dungeons")
  page.back:SetScript("OnClick", function() ns.SelectScreen("journal") end)

  -- Right-aligned as a pair, so the label cannot run off the edge of the window. It belongs to
  -- both views: on the grid it decides whether a card counts everyone's quests or only yours.
  page.onlyMineLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.onlyMineLabel:SetText("Only quests I can take")
  page.onlyMine = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
  page.onlyMine:SetSize(22, 22)
  page.onlyMine:SetPoint("RIGHT", page.onlyMineLabel, "LEFT", -2, 0)
  page.onlyMine:SetChecked(true)
  page.onlyMine:SetScript("OnClick", function()
    if page.selected then ShowDetail(page, page.selected) else ShowBrowse(page) end
  end)

  page.browse = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  page.browse:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -48)
  page.browse:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -26, 8)
  page.content = CreateFrame("Frame", nil, page.browse)
  page.content:SetSize(CARD_COLUMNS * (CARD_W + CARD_GAP), 10)
  page.browse:SetScrollChild(page.content)
  page.cards = {}

  page.detail = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  page.detail:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -68) -- clear of the heading and the checkbox
  page.detail:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -26, 8)
  page.treeContent = CreateFrame("Frame", nil, page.detail)
  page.treeContent:SetSize(TREE_COLUMNS * (NODE_W + NODE_GAP_X), 10)
  page.detail:SetScrollChild(page.treeContent)
  page.detail:Hide()
  page.nodes = {}
  page.chains = {}
  page.selected = false
  return page
end

local function Refresh(page, dungeon)
  page.back:SetShown(dungeon ~= nil)
  -- Under the All dungeons button on a dungeon's own page, at the top of the grid otherwise.
  page.onlyMineLabel:ClearAllPoints()
  page.onlyMineLabel:Show()
  page.onlyMine:Show()
  if dungeon then
    page.onlyMineLabel:SetPoint("TOPRIGHT", page.back, "BOTTOMRIGHT", -2, -8)
  else
    page.onlyMineLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, -12)
  end
  if dungeon then return ShowDetail(page, dungeon) end
  return ShowBrowse(page)
end

ns.JournalShowBrowse, ns.JournalShowDetail = ShowBrowse, ShowDetail

function ns.RegisterJournalScreen()
  return ns.RegisterScreen({
    key = "journal",
    name = "Dungeon journal",
    icon = "Interface\\LFGFrame\\LFGIcon-Dungeon",
    build = Build,
    refresh = Refresh,
  })
end

if SHIPPING then ns.RegisterJournalScreen() end

-- Is the journal the screen on show, and which dungeon is open in it?
function ns.IsJournalShown()
  local w = rawget(_G, "ForeverBuddyFrame")
  return (w and w:IsShown() and w.current == "journal") and true or false
end

function ns.JournalSelected()
  local w = rawget(_G, "ForeverBuddyFrame")
  local page = w and w.pages and w.pages.journal
  return page and page.selected or nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:SetScript("OnEvent", function()
  if ns.IsJournalShown() then ns.SelectScreen("journal", ns.JournalSelected()) end
end)
