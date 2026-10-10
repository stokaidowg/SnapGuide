-- SnapGuide window: the current step, the next two, your level pace, an arrow to the step's
-- spot, and buttons to go back, tick/skip and target the step's NPC or mobs. Uses SnapUI's
-- look when SnapUI is loaded.

local G = SnapGuide
local f, arrow

local FONT = "Fonts\\FRIZQT__.TTF"
local TEX = "Interface\\Buttons\\WHITE8X8"

local ACTION = {
  A = { "!", 1, 0.82, 0, "Accept" },
  C = { "*", 1, 1, 1, "Do" },
  T = { "?", 1, 0.82, 0, "Turn in" },
  R = { ">", 0.31, 0.76, 0.97, "Go to" },
  F = { "F", 0.31, 0.76, 0.97, "Fly to" },
  H = { "H", 0.31, 0.76, 0.97, "Hearth to" },
  P = { "P", 0.4, 1, 0.4, "Get the flight path" },
  S = { "S", 0.4, 1, 0.4, "Make your home" },
  B = { "$", 1, 0.82, 0, "Buy" },
  L = { "L", 0.62, 0.25, 0.85, "Reach level" },
  G = { "G", 1, 0.5, 0.25, "Grind" },
  N = { "i", 0.8, 0.8, 0.8, "" },
  X = { "x", 1, 0.3, 0.3, "Abandon" },
}

-- a map spot (zone, x/y in percent) in world yards: north, west, continent. Zone edges come
-- from zones.lua (the client's own map table); nil for zones it doesn't have
local function World(zone, x, y)
  local b = zone and x and G.ZONES and G.ZONES[zone]
  if not b then return nil end
  return b[4] - y / 100 * (b[4] - b[5]), b[2] - x / 100 * (b[2] - b[3]), b[1]
end

local function Look(frame, alpha)
  if SnapUI and SnapUI.Backdrop then
    SnapUI.Backdrop(frame, alpha)
  else
    frame:SetBackdrop({ bgFile = TEX, edgeFile = TEX, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    frame:SetBackdropColor(0.05, 0.05, 0.05, alpha or 0.85)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
  end
end

local function Text(parent, size, justify)
  local t = parent:CreateFontString(nil, "OVERLAY")
  t:SetFont((SnapUI and SnapUI.FONT) or FONT, size, "OUTLINE")
  t:SetJustifyH(justify or "LEFT")
  return t
end

local function Button(parent, label, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(18)
  b:SetHeight(18)
  Look(b, 1)
  b.text = Text(b, 12, "CENTER")
  b.text:SetPoint("CENTER", 0, 0)
  b.text:SetText(label)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function()
    this:SetBackdropBorderColor(0.31, 0.76, 0.97, 1)
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(tip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    this:SetBackdropBorderColor(0, 0, 0, 1)
    GameTooltip:Hide()
  end)
  return b
end

-- dragged positions, saved per character. A frame kept on screen can come out of a drag
-- with no anchor on this client (it vanishes, and an empty position got saved): pin it by
-- its top-left corner. A broken saved position falls back to the default.
local function SavePos(frame, key)
  local p, _, rp, x, y = frame:GetPoint()
  if p and rp and x and y then
    G.db[key] = { p, rp, x, y }
    return
  end
  local left, top = frame:GetLeft(), frame:GetTop()
  if left and top then
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, top * scale)
    G.db[key] = { "TOPLEFT", "BOTTOMLEFT", left * scale, top * scale }
  end
end

local function Place(frame, key, p, rp, x, y)
  local pos = G.db[key]
  frame:ClearAllPoints()
  if pos and type(pos[1]) == "string" and type(pos[2]) == "string" and tonumber(pos[3]) and tonumber(pos[4]) then
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    G.db[key] = nil
    frame:SetPoint(p, UIParent, rp, x, y)
  end
end

local function Coords(s)
  if s.x then return string.format(" |cff888888(%.1f, %.1f)|r", s.x, s.y) end
  return ""
end

-- one line describing a step
local function Describe(s)
  local a = ACTION[s.a] or ACTION.N
  local text
  if s.a == "A" or s.a == "T" or s.a == "X" then
    text = a[5] .. " |cffffffff" .. (s.t or "?") .. "|r" .. (s.n and (" |cffaaaaaa- " .. s.n .. "|r") or "")
  elseif s.a == "C" then
    text = "|cffffffff" .. (s.t or "?") .. "|r"
  elseif s.a == "L" then
    text = a[5] .. " |cffffffff" .. (s.lvl or "?") .. "|r"
  elseif s.a == "P" or s.a == "S" then
    text = a[5] .. " |cffffffff" .. (s.t or "") .. "|r" .. (s.n and (" |cffaaaaaa- " .. s.n .. "|r") or "")
  elseif s.a == "B" then
    text = a[5] .. " |cffffffff" .. (s.t or "") .. "|r" .. (s.n and (" |cffaaaaaa- " .. s.n .. "|r") or "")
  elseif s.a == "N" then
    text = "|cffffffff" .. (s.t or "") .. "|r"
  else
    text = (a[5] ~= "" and (a[5] .. " ") or "") .. "|cffffffff" .. (s.t or "") .. "|r"
  end
  if s.opt then text = text .. " |cff888888(optional)|r" end
  return text
end
G.Describe = Describe

-- [[ arrow ]] --
local minimapArrow
local function Facing()
  if GetPlayerFacing then return GetPlayerFacing() end
  if not minimapArrow then
    for _, v in ipairs({ Minimap:GetChildren() }) do
      if v:IsObjectType("Model") and not v:GetName() and v:GetModel()
        and string.find(string.lower(v:GetModel()), "interface\\minimap\\minimaparrow") then
        minimapArrow = v
        break
      end
    end
  end
  return minimapArrow and minimapArrow:GetFacing() or 0
end

-- rotate a texture by `a` radians (anticlockwise as you look at it) using its corners
local function Rotate(tex, a)
  local c, s = math.cos(a), math.sin(a)
  local function P(u, v)
    return 0.5 + u * c - v * s, 0.5 + u * s + v * c
  end
  local ulx, uly = P(-0.5, -0.5)
  local llx, lly = P(-0.5, 0.5)
  local urx, ury = P(0.5, -0.5)
  local lrx, lry = P(0.5, 0.5)
  tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

-- pfQuest ships TomTom's 108-frame arrow sheet (9 x 12 frames of 56 x 42 in a 512 x 512
-- texture), which is known to work on 1.12; without pfQuest, rotate Blizzard's minimap arrow
local SPRITE = "Interface\\AddOns\\pfQuest\\img\\arrow"
local useSprite

local function PointArrow(rel)
  if useSprite then
    local cell = math.mod(math.floor(rel / (math.pi * 2) * 108 + 0.5), 108)
    if cell < 0 then cell = cell + 108 end
    local col, row = math.mod(cell, 9), math.floor(cell / 9)
    arrow.icon:SetTexCoord(col * 56 / 512, (col + 1) * 56 / 512, row * 42 / 512, (row + 1) * 42 / 512)
  else
    Rotate(arrow.icon, rel)
  end
  -- green when you're heading the right way, red when it's behind you
  local r = rel - math.floor(rel / (math.pi * 2)) * math.pi * 2 -- 0..2pi
  local off = math.min(r, math.pi * 2 - r) / math.pi -- 0 ahead, 1 behind
  arrow.icon:SetVertexColor(math.min(1, off * 2), math.min(1, (1 - off) * 2), 0.2)
end

-- [[ corpse ]] --
-- Where you died, saved on PLAYER_DEAD (the client's own corpse position replaces it once
-- you're a ghost on the same map). Kept until you're alive again.
local corpse, corpseAt = nil, 0

local function CorpseSpot()
  if not UnitIsGhost("player") then return nil end
  -- the map lookup only twice a second (the arrow asks 25 times)
  if GetTime() - corpseAt < 0.5 then return corpse end
  corpseAt = GetTime()
  if GetCorpseMapPosition and not (WorldMapFrame and WorldMapFrame:IsShown()) then
    SetMapToCurrentZone()
    local x, y = GetCorpseMapPosition()
    if x and (x > 0 or y > 0) then
      corpse = { t = "Your corpse", x = x * 100, y = y * 100, z = GetRealZoneText(), corpse = true }
    end
  end
  return corpse
end

local corpseEvents = CreateFrame("Frame")
corpseEvents:RegisterEvent("PLAYER_DEAD")
corpseEvents:RegisterEvent("PLAYER_UNGHOST")
corpseEvents:RegisterEvent("PLAYER_ALIVE")
corpseEvents:SetScript("OnEvent", function()
  if event == "PLAYER_DEAD" then
    local zone, x, y = G:Position()
    corpse = x and { t = "Your corpse", x = x, y = y, z = zone, corpse = true } or nil
  elseif not UnitIsDeadOrGhost("player") then
    -- resurrected (PLAYER_ALIVE also fires on release, while you're still a ghost)
    corpse = nil
  end
end)

-- where to walk: your corpse while you're a ghost; otherwise the current step's spot, or the
-- next step that has one (the current step may be "use the item in your bags" or a note)
function G:ArrowTarget()
  local c = CorpseSpot()
  if c then return c end
  local s = self.step
  if not s then return nil end
  if s.x then return s end
  if self.route then
    local count = 0
    for i = s.i + 1, table.getn(self.route.steps) do
      local n = self.route.steps[i]
      if self:Pending(self.route, n) then
        if n.x then return n, true end
        count = count + 1
        if count >= 5 then break end
      end
    end
  end
end

-- [[ paths ]] --
-- Paths.lua (tools/paths.js, from the client's terrain) gives some steps a few points to walk
-- through first, round cliffs and mountains. The arrow aims at the next point; it moves on
-- when you're within REACHED yards of it, or when you're clearly further along the path, and
-- never goes back. A path made for other coordinates (the route was rebuilt) is ignored.
local REACHED, ALONG = 25, 40
local pathKey, pathNext

local function StepPath(s)
  local p = G.paths and s.key and G.paths[s.key]
  if not p or G.db.paths == false then return nil end
  if p.to ~= string.format("%s:%.2f,%.2f", s.z or "", s.x or 0, s.y or 0) then return nil end
  return p
end

-- yards from (n, w) to the segment a-b
local function ToSegment(n, w, an, aw, bn, bw)
  local dn, dw = bn - an, bw - aw
  local l2 = dn * dn + dw * dw
  local t = l2 > 0 and math.max(0, math.min(1, ((n - an) * dn + (w - aw) * dw) / l2)) or 0
  local en, ew = an + t * dn - n, aw + t * dw - w
  return math.sqrt(en * en + ew * ew)
end

-- where the arrow should aim for step s (target at tN, tW) from (pN, pW): the next path
-- point, the yards left along the path, which point it is and how many there are
function G:PathAim(s, pN, pW, tN, tW)
  local p = StepPath(s)
  if not p then return nil end
  local count = table.getn(p) / 2
  if count < 1 then return nil end
  local function Point(j)
    if j > count then return tN, tW end
    return p[j * 2 - 1], p[j * 2]
  end
  -- segment j runs from point j-1 to point j (point count+1 is the step itself; segment 1 is
  -- just point 1)
  local function Dist(j)
    local bn, bw = Point(j)
    local an, aw = bn, bw
    if j > 1 then an, aw = Point(j - 1) end
    return ToSegment(pN, pW, an, aw, bn, bw)
  end
  if pathKey ~= s.key then
    -- a new step: start at the segment you're nearest to
    pathKey, pathNext = s.key, 1
    local best
    for j = 1, count + 1 do
      local d = Dist(j)
      if not best or d < best then best, pathNext = d, j end
    end
  else
    -- further along: a later segment you're right next to
    for j = count + 1, pathNext + 1, -1 do
      if Dist(j) < ALONG then pathNext = j break end
    end
  end
  -- at the point: on to the next
  while pathNext <= count do
    local n, w = Point(pathNext)
    if math.sqrt((n - pN) ^ 2 + (w - pW) ^ 2) > REACHED then break end
    pathNext = pathNext + 1
  end
  if pathNext > count then return nil end
  local an, aw = Point(pathNext)
  local left = math.sqrt((an - pN) ^ 2 + (aw - pW) ^ 2)
  for j = pathNext + 1, count + 1 do
    local n1, w1 = Point(j - 1)
    local n2, w2 = Point(j)
    left = left + math.sqrt((n2 - n1) ^ 2 + (w2 - w1) ^ 2)
  end
  return an, aw, left, pathNext, count
end

local lastPos, posZone, posX, posY = 0
local function UpdateArrow()
  if not arrow then return end
  local s, ahead = G:ArrowTarget()
  -- the corpse arrow shows even with the guide window hidden
  if not s or G.db.arrow == false or (G.db.hidden and not s.corpse) then
    arrow:Hide()
    return
  end
  -- where you are (map lookups are slower, so only five times a second)
  if GetTime() - lastPos > 0.2 then
    lastPos = GetTime()
    posZone, posX, posY = G:Position()
  end
  local label = (ahead and "|cff888888next:|r " or "") .. (s.t or s.n or "")
  if s.corpse then label = "|cffff6060" .. s.t .. "|r" end
  arrow.label:SetText(label)
  arrow:Show()
  -- both ends in world yards: works across zone borders on the same continent
  local pN, pW, pC = World(posZone, posX, posY)
  local tN, tW, tC = World(s.z, s.x, s.y)
  if pN and tN and pC == tC then
    local dN, dW = tN - pN, tW - pW
    local d = math.sqrt(dN * dN + dW * dW)
    -- round an obstacle: aim at the path's next point, count the yards along the path
    local aN, aW, left = nil
    if not s.corpse then aN, aW, left = G:PathAim(s, pN, pW, tN, tW) end
    if aN then
      dN, dW = aN - pN, aW - pW
      d = left
    end
    PointArrow(math.atan2(dW, dN) - Facing()) -- anticlockwise from north, like facing
    arrow.icon:Show()
    local text = d < 20 and "|cff60ff60You're here|r" or (math.floor(d / 5 + 0.5) * 5 .. " yd")
    if aN then text = text .. " |cff4fc3f7path|r" end
    if posZone ~= s.z then text = text .. " |cff888888in|r |cffffffff" .. s.z .. "|r" end
    arrow.dist:SetText(text)
    return
  end
  if posX and posZone == s.z then
    -- a zone missing from the table: map percent, no distance
    local dx, dy = s.x - posX, s.y - posY
    PointArrow(math.atan2(-dx * 1.5, -dy) - Facing())
    arrow.icon:Show()
    arrow.dist:SetText(math.sqrt((dx * 1.5) ^ 2 + dy ^ 2) < 1 and "|cff60ff60You're here|r" or "")
    return
  end
  -- another continent (or somewhere the map can't place you): say where to go
  arrow.icon:Hide()
  arrow.dist:SetText("Go to |cffffffff" .. (s.z or "?") .. "|r")
end

-- [[ arrow settings ]] --
-- size, transparency, and the two text lines under it; saved per character
local ARROW_DEFAULTS = { arrowScale = 0.8, arrowAlpha = 1, arrowDist = true, arrowLabel = true, paths = true }

local function ArrowSetting(key)
  local v = G.db[key]
  if v == nil then return ARROW_DEFAULTS[key] end
  return v
end

local function ApplyArrowStyle()
  if not arrow then return end
  arrow:SetScale(ArrowSetting("arrowScale"))
  arrow:SetAlpha(ArrowSetting("arrowAlpha") * (arrow.fade or 1))
  if ArrowSetting("arrowDist") then arrow.dist:Show() else arrow.dist:Hide() end
  if ArrowSetting("arrowLabel") then arrow.label:Show() else arrow.label:Hide() end
end

local config
local function ToggleArrowConfig()
  if config then
    if config:IsShown() then config:Hide() else config:Show() end
    return
  end
  config = CreateFrame("Frame", "SnapGuideArrowConfig", UIParent)
  config:SetWidth(200)
  config:SetHeight(152)
  config:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  config:SetFrameStrata("DIALOG")
  config:EnableMouse(true)
  config:SetMovable(true)
  config:RegisterForDrag("LeftButton")
  config:SetScript("OnDragStart", function() this:StartMoving() end)
  config:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  Look(config, 0.95)
  table.insert(UISpecialFrames, "SnapGuideArrowConfig") -- Escape closes it

  local title = Text(config, 13, "LEFT")
  title:SetPoint("TOPLEFT", 8, -7)
  title:SetText("|cff4fc3f7SnapGuide|r arrow")
  local close = Button(config, "x", "Close", function() config:Hide() end)
  close:SetPoint("TOPRIGHT", -4, -4)

  local rows = {}
  local function Row(i, label)
    local r = CreateFrame("Frame", nil, config)
    r:SetWidth(184)
    r:SetHeight(20)
    r:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 24)
    r.label = Text(r, 12, "LEFT")
    r.label:SetPoint("LEFT", 0, 0)
    r.label:SetText(label)
    rows[i] = r
    return r
  end

  -- a value stepped with - and +
  local function Stepper(i, label, key, step, min, max, fmt)
    local r = Row(i, label)
    r.value = Text(r, 12, "CENTER")
    r.value:SetWidth(44)
    r.value:SetPoint("RIGHT", r, "RIGHT", -20, 0)
    local function Refresh() r.value:SetText(string.format(fmt, ArrowSetting(key) * 100)) end
    local function Bump(d)
      local v = math.floor((ArrowSetting(key) + d) * 100 + 0.5) / 100
      G.db[key] = math.max(min, math.min(max, v))
      Refresh()
      ApplyArrowStyle()
    end
    local minus = Button(r, "-", label .. " down", function() Bump(-step) end)
    minus:SetPoint("RIGHT", r.value, "LEFT", 0, 0)
    local plus = Button(r, "+", label .. " up", function() Bump(step) end)
    plus:SetPoint("LEFT", r.value, "RIGHT", 0, 0)
    Refresh()
  end

  -- an on/off switch
  local function Switch(i, label, key)
    local r = Row(i, label)
    local b = Button(r, "", label, nil)
    b:SetWidth(44)
    b:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    local function Refresh() b.text:SetText(ArrowSetting(key) and "|cff60ff60On|r" or "|cffff6060Off|r") end
    b:SetScript("OnClick", function()
      G.db[key] = not ArrowSetting(key)
      Refresh()
      ApplyArrowStyle()
    end)
    Refresh()
  end

  Stepper(1, "Size", "arrowScale", 0.1, 0.4, 2, "%d%%")
  Stepper(2, "Opacity", "arrowAlpha", 0.1, 0.2, 1, "%d%%")
  Switch(3, "Distance text", "arrowDist")
  Switch(4, "Step name", "arrowLabel")
  Switch(5, "Paths round cliffs", "paths")
end
G.ToggleArrowConfig = ToggleArrowConfig

local function CreateArrow()
  arrow = CreateFrame("Button", "SnapGuideArrow", UIParent)
  arrow:SetWidth(120)
  arrow:SetHeight(96)
  arrow:SetMovable(true)
  arrow:EnableMouse(true)
  arrow:RegisterForDrag("LeftButton")
  arrow:SetScript("OnDragStart", function() this:StartMoving() end)
  arrow:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    SavePos(this, "arrowPos")
  end)
  Place(arrow, "arrowPos", "TOP", "TOP", 0, -120)
  arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
  useSprite = IsAddOnLoaded and IsAddOnLoaded("pfQuest")
  if useSprite then
    arrow.icon:SetTexture(SPRITE)
    arrow.icon:SetWidth(84)
    arrow.icon:SetHeight(63)
  else
    arrow.icon:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow.icon:SetWidth(64)
    arrow.icon:SetHeight(64)
  end
  arrow.icon:SetPoint("TOP", 0, 0)
  arrow.dist = Text(arrow, 14, "CENTER")
  arrow.dist:SetPoint("TOP", arrow, "TOP", 0, -66)
  arrow.label = Text(arrow, 11, "CENTER")
  arrow.label:SetPoint("TOP", arrow.dist, "BOTTOM", 0, -2)
  arrow.label:SetWidth(220)
  arrow.label:SetTextColor(0.85, 0.85, 0.85)
  arrow:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
    local s = G:ArrowTarget()
    if s then
      GameTooltip:SetText(Describe(s))
      if s.x then GameTooltip:AddLine(string.format("%s %.1f, %.1f", s.z or "", s.x, s.y), 0.8, 0.8, 0.8) end
      local p = not s.corpse and StepPath(s)
      if p and pathKey == s.key and pathNext <= table.getn(p) / 2 then
        GameTooltip:AddLine(string.format("Walking round an obstacle: point %d of %d", pathNext, table.getn(p) / 2), 0.31, 0.76, 0.97)
      end
    end
    GameTooltip:AddLine("Drag to move. Right-click for size and text options", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
  arrow:RegisterForClicks("RightButtonUp")
  arrow:SetScript("OnClick", function() ToggleArrowConfig() end)
  arrow:Hide()
  ApplyArrowStyle()

  -- driven from a frame that's always shown: a hidden frame gets no OnUpdate
  local t = 0
  local driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", function()
    t = t + arg1
    if t > 0.04 then
      t = 0
      UpdateArrow()
    end
  end)
end

-- [[ targeting ]] --
-- The step's NPC (accept / turn in), or its mobs one after another. Targets get a raid
-- icon, so they stand out (works when the server allows icons outside a group).
local ICONS = { 8, 7, 2, 3, 4, 6, 5, 1 } -- skull, cross, circle, diamond, triangle, square, moon, star
local nextIcon, cycle = 1, 0

-- mobs to target for a step and the steps done along with it, without repeats
function G:GroupMobs(route, s)
  local names, seen = {}, {}
  for _, g in ipairs(self:Group(route, s)) do
    for _, m in ipairs(g.mobs or {}) do
      if not seen[m] then
        seen[m] = true
        table.insert(names, m)
      end
    end
  end
  return names
end

-- objective progress lines ("Crawler Meat: 3/8") for a quest in your log
-- sep: between objectives (", " by default, a line break for one per line)
local function Progress(title, sep)
  local entry = G.log[title]
  if not entry then return nil end
  local parts = {}
  for j = 1, GetNumQuestLeaderBoards(entry.index) or 0 do
    local text, _, finished = GetQuestLogLeaderBoard(j, entry.index)
    if text then table.insert(parts, (finished and "|cff60ff60" or "|cffffd100") .. text .. "|r") end
  end
  if table.getn(parts) == 0 then return nil end
  return table.concat(parts, sep or ", ")
end

-- quiet: no error messages (the automatic tries below); returns true when something was targeted
function G:Target(quiet)
  local s = self.step
  if not s then return end
  local names = {}
  if s.n and (s.a == "A" or s.a == "T" or s.a == "P" or s.a == "S" or s.a == "B") then table.insert(names, s.n) end
  for _, m in ipairs(self:GroupMobs(self.route, s)) do table.insert(names, m) end
  if table.getn(names) == 0 then
    if not quiet then UIErrorsFrame:AddMessage("Nothing to target for this step", 1, 0.3, 0.3, 1, 2) end
    return
  end
  for k = 1, table.getn(names) do
    cycle = math.mod(cycle, table.getn(names)) + 1
    local name = names[cycle]
    TargetByName(name, true)
    if UnitExists("target") and UnitName("target") == name and not UnitIsDead("target") then
      if not GetRaidTargetIndex("target") then
        pcall(SetRaidTarget, "target", ICONS[nextIcon])
        nextIcon = math.mod(nextIcon, 8) + 1
      end
      return true
    end
  end
  if not quiet then UIErrorsFrame:AddMessage("No " .. table.concat(names, " / ") .. " nearby", 1, 0.3, 0.3, 1, 2) end
end

-- [[ auto target ]] --
-- When the guide moves on to a step with an NPC or mobs, target (and mark) them by itself.
-- One try per step, found or not (the user asked: no repeated tries). It waits until you're
-- out of combat with no living target, so it never takes over a fight or something you
-- picked. db.autoTarget = false turns it off (/sg autotarget).
local autoKey, autoNext, shownKey = nil, 0, nil

local function Targetable(s)
  if not s then return false end
  if s.n and not s.obj and (s.a == "A" or s.a == "T" or s.a == "P" or s.a == "S" or s.a == "B") then return true end
  return table.getn(G:GroupMobs(G.route, s)) > 0
end

function G:AutoTarget(now)
  if self.db.autoTarget == false or not autoKey or not self.step or self.step.key ~= autoKey then return end
  if now < autoNext then return end
  if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then return end
  if UnitExists("target") and not UnitIsDead("target") then return end
  autoKey = nil
  self:Target(true)
end

function G:AutoTargetCommand(arg)
  if arg == "on" then self.db.autoTarget = nil
  elseif arg == "off" then self.db.autoTarget = false
  else self.db.autoTarget = self.db.autoTarget == false and nil or false end
  G.Print("targeting the next step's NPC or mobs by itself: " .. (self.db.autoTarget == false and "|cffff8080off|r" or "|cff60ff60on|r"))
end

-- [[ route menu ]] --
local menu
local function ToggleMenu(anchor)
  if not menu then
    menu = CreateFrame("Frame", "SnapGuideRouteMenu", f)
    menu:SetFrameStrata("DIALOG")
    Look(menu, 0.97)
    menu.items = {}
  end
  if menu:IsShown() then menu:Hide() return end
  for _, b in ipairs(menu.items) do b:Hide() end
  for i, r in ipairs(G.routes) do
    local route = r
    local b = menu.items[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(16)
      b.text = Text(b, 11, "LEFT")
      b.text:SetPoint("LEFT", 6, 0)
      b:SetScript("OnEnter", function() this.text:SetTextColor(0.31, 0.76, 0.97) end)
      b:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1) end)
      menu.items[i] = b
    end
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * 16)
    b:SetPoint("RIGHT", menu, "RIGHT", -2, 0)
    b.text:SetText((route == G.route and "|cff4fc3f7> |r" or "") .. route.title .. " |cff888888" .. route.min .. "-" .. route.max .. "|r")
    b:SetScript("OnClick", function()
      menu:Hide()
      G:SetRoute(route.id)
    end)
    b:Show()
  end
  menu:SetWidth(200)
  menu:SetHeight(4 + table.getn(G.routes) * 16)
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  menu:Show()
end

-- [[ main window ]] --
local function Create()
  f = CreateFrame("Frame", "SnapGuideFrame", UIParent)
  f:SetWidth(300)
  f:SetHeight(120)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    SavePos(this, "pos")
  end)
  Place(f, "pos", "RIGHT", "RIGHT", -20, 80)
  Look(f, 0.85)

  f.title = Text(f, 12, "LEFT")
  f.title:SetPoint("TOPLEFT", 6, -6)
  f.count = Text(f, 11, "RIGHT")
  f.count:SetPoint("TOPRIGHT", -84, -7)

  f.menuBtn = Button(f, "=", "Routes", function() ToggleMenu(this) end)
  f.menuBtn:SetPoint("TOPRIGHT", -4, -3)
  f.targetBtn = Button(f, "o", "Target the step's NPC or mobs (also: key binding, /sg target)", function() G:Target() end)
  f.targetBtn:SetPoint("RIGHT", f.menuBtn, "LEFT", -2, 0)
  f.skipBtn = Button(f, "+", "Done / skip this step", function() G:Tick(G.step) end)
  f.skipBtn:SetPoint("RIGHT", f.targetBtn, "LEFT", -2, 0)
  f.backBtn = Button(f, "<", "Undo the last tick or skip", function() G:Back() end)
  f.backBtn:SetPoint("RIGHT", f.skipBtn, "LEFT", -2, 0)

  -- current step: an action badge, the step, its note
  f.badge = CreateFrame("Frame", nil, f)
  f.badge:SetWidth(22)
  f.badge:SetHeight(22)
  f.badge:SetPoint("TOPLEFT", 6, -26)
  Look(f.badge, 1)
  f.badge.text = Text(f.badge, 15, "CENTER")
  f.badge.text:SetPoint("CENTER", 1, 0)

  f.step = CreateFrame("Button", nil, f)
  f.step:SetPoint("TOPLEFT", f.badge, "TOPRIGHT", 6, 0)
  f.step:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.step:SetHeight(22)
  f.step.text = Text(f.step, 13, "LEFT")
  f.step.text:SetPoint("TOPLEFT", 0, -1)
  f.step.text:SetPoint("RIGHT", f.step, "RIGHT", 0, 0)
  f.step:SetScript("OnEnter", function()
    local s = G.step
    if not s then return end
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    local group = G:Group(G.route, s)
    for i, g in ipairs(group) do
      if i == 1 then GameTooltip:SetText(Describe(g)) else GameTooltip:AddLine(Describe(g)) end
      if g.o then GameTooltip:AddLine(g.o, 1, 1, 1, 1) end
      if g.note then GameTooltip:AddLine(g.note, 0.8, 0.8, 0.8, 1) end
    end
    local mobs = G:GroupMobs(G.route, s)
    if table.getn(mobs) > 0 then GameTooltip:AddLine("Target: " .. table.concat(mobs, ", "), 1, 0.5, 0.25, 1) end
    if s.x then GameTooltip:AddLine(string.format("%s %.1f, %.1f", s.z or "", s.x, s.y), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  f.step:SetScript("OnLeave", function() GameTooltip:Hide() end)

  f.note = Text(f, 11, "LEFT")
  f.note:SetPoint("TOPLEFT", f.badge, "BOTTOMLEFT", 0, -5)
  f.note:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.note:SetTextColor(0.8, 0.8, 0.8)

  -- shown when the step's NPC can't be found: your choice, nothing is skipped by itself
  f.skipQuest = Button(f, "Skip quest", "Skip this quest: its later steps, and quests that need it, go too. < brings it back.", function() G:Tick(G.step) end)
  f.skipQuest:SetWidth(80)
  f.keepQuest = Button(f, "Keep it", "Hide this warning: the NPC may just be dead or out of sight", function() G:KeepNPC(G.step) end)
  f.keepQuest:SetWidth(60)
  f.keepQuest:SetPoint("LEFT", f.skipQuest, "RIGHT", 4, 0)
  f.skipQuest:Hide()
  f.keepQuest:Hide()

  f.next = {}
  for i = 1, 2 do
    local t = Text(f, 11, "LEFT")
    t:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    t:SetAlpha(0.55)
    f.next[i] = t
  end

  f.xp = Text(f, 11, "LEFT")
  f.xp:SetPoint("BOTTOMLEFT", 6, 5)
  f.xp:SetPoint("RIGHT", f, "RIGHT", -6, 0)

  CreateArrow()
end

local function Short(n)
  if n >= 10000 then return string.format("%.0fk", n / 1000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end

local function UpdateXP(route)
  local level, xp, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  local text = "Level " .. level .. " |cff888888" .. math.floor(xp / math.max(max, 1) * 100) .. "%|r"
  local rate = G:XPRate()
  if rate then
    local mins = (max - xp) / rate * 60
    text = text .. "  " .. Short(rate) .. "/h  |cff888888level in|r " .. (mins >= 60 and string.format("%dh%02dm", mins / 60, math.mod(mins, 60)) or (math.floor(mins) .. "m"))
  end
  if route then
    local pace
    if level < route.min then
      pace = "|cffff8080behind (route is " .. route.min .. "-" .. route.max .. ")|r"
    elseif level > route.max then
      pace = "|cff60ff60ahead of this route|r"
    end
    if pace then text = text .. "  " .. pace end
  end
  f.xp:SetText(text)
end

function G:OnRefresh(route, s)
  if not f then return end
  -- a new step: target its NPC or mobs once they're about
  if s and s.key ~= shownKey then
    shownKey = s.key
    if Targetable(s) then autoKey, autoNext = s.key, 0 else autoKey = nil end
  end
  if not route then
    f.title:SetText("SnapGuide")
    f.step.text:SetText("No routes loaded")
    return
  end
  f.title:SetText("|cff4fc3f7" .. route.title .. "|r |cff888888" .. route.min .. "-" .. route.max .. "|r")
  if not s then
    f.count:SetText("")
    f.badge.text:SetText("")
    f.step.text:SetText("|cff60ff60All routes done!|r")
    f.note:SetText("")
    for i = 1, 2 do f.next[i]:SetText("") end
    f.skipQuest:Hide()
    f.keepQuest:Hide()
    UpdateXP(route)
    return
  end
  f.count:SetText(s.i .. "/" .. table.getn(route.steps))
  local a = ACTION[s.a] or ACTION.N
  f.badge.text:SetText(a[1])
  f.badge.text:SetTextColor(a[2], a[3], a[4])
  local group = self:Group(route, s)
  local note
  if table.getn(group) > 1 then
    -- quests done at the same time: one line, then each quest's note and progress
    local titles, lines = {}, {}
    for _, g in ipairs(group) do
      table.insert(titles, "|cffffffff" .. (g.t or "?") .. "|r")
      local line = "|cffffffff" .. (g.t or "?") .. ":|r " .. (g.note or g.o or "")
      local progress = Progress(g.t)
      if progress then line = line .. " " .. progress end
      table.insert(lines, line)
    end
    f.step.text:SetText(table.concat(titles, " |cff888888+|r ") .. Coords(s))
    note = "|cff4fc3f7Do these together.|r\n" .. table.concat(lines, "\n")
  else
    f.step.text:SetText(Describe(s) .. Coords(s))
    note = s.note or ""
    if s.a == "C" and s.o and note == "" then note = s.o end
    -- the quest's objectives from your log, one per line: "Ghoul Fang: 3/10"
    if s.a == "C" then
      local progress = Progress(s.t, "\n")
      if progress then note = (note ~= "" and (note .. "\n") or "") .. progress end
    end
  end
  local missing = self.missing[s.key]
  if missing then
    note = "|cffff8080" .. s.n .. " isn't here. The server may have moved or removed them.|r " .. note
  end
  if self.collapsed and (s.a == "C" or s.a == "A") then
    note = "|cffff8080Expand all quest log headers so SnapGuide can see your quests.|r " .. note
  end
  f.note:SetText(note)

  -- skip or keep, under the note, when the NPC is missing
  local last = f.note
  if missing then
    f.skipQuest:ClearAllPoints()
    f.skipQuest:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", 0, -5)
    f.skipQuest:Show()
    f.keepQuest:Show()
    last = f.skipQuest
  else
    f.skipQuest:Hide()
    f.keepQuest:Hide()
  end

  -- the next two steps under the note
  local list = self:Upcoming(route, s, 2)
  for i = 1, 2 do
    local t = f.next[i]
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -6 or -2)
    t:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    if list[i] then
      local na = ACTION[list[i].a] or ACTION.N
      t:SetText(na[1] .. "  " .. Describe(list[i]))
    else
      t:SetText("")
    end
    last = t
  end

  if (s.n and (s.a == "A" or s.a == "T" or s.a == "P" or s.a == "S" or s.a == "B")) or table.getn(self:GroupMobs(route, s)) > 0 then
    f.targetBtn:Enable()
    f.targetBtn:SetAlpha(1)
  else
    f.targetBtn:Disable()
    f.targetBtn:SetAlpha(0.35)
  end

  -- size to fit the note
  local h = 26 + 22 + 5 + (note ~= "" and f.note:GetHeight() or 0) + (missing and 23 or 0) + 6 + 14 * 2 + 20
  f:SetHeight(math.max(96, h))
  UpdateXP(route)
end

function G:ToggleFrame(cmd)
  if not f then return end
  if cmd == "hide" or (cmd == "" and f:IsShown()) then
    f:Hide()
    arrow:Hide()
    self.db.hidden = true
  else
    f:Show()
    self.db.hidden = nil
    self:Refresh()
  end
end

-- [[ dungeons and raids ]] --
-- Inside an instance the window and the arrow fade out and only show while the mouse is
-- over them (or the route menu is open), to keep the screen clear. /sg fade turns it off.
local FADE_SPEED = 4 -- alpha per second

function G:InstanceFade()
  return self.db.instanceFade ~= false and IsInInstance and IsInInstance() and true or false
end

local function FadeTo(frame, goal, dt)
  local a = frame.fade or 1
  if a == goal then return false end
  if a < goal then a = math.min(goal, a + FADE_SPEED * dt) else a = math.max(goal, a - FADE_SPEED * dt) end
  frame.fade = a
  return true
end

local fader = CreateFrame("Frame")
fader:SetScript("OnUpdate", function()
  if not f or not arrow then return end
  local dt = arg1
  local fade = G:InstanceFade()
  local goal = (not fade or MouseIsOver(f) or (menu and menu:IsShown())) and 1 or 0
  if FadeTo(f, goal, dt) then f:SetAlpha(f.fade) end
  -- the corpse arrow stays visible
  goal = (not fade or UnitIsGhost("player") or (arrow:IsShown() and MouseIsOver(arrow))) and 1 or 0
  if FadeTo(arrow, goal, dt) then ApplyArrowStyle() end
end)

function G:FadeCommand()
  self.db.instanceFade = self.db.instanceFade == false
  G.Print("in dungeons and raids the guide " .. (self.db.instanceFade and "only shows on mouse-over" or "stays visible") .. ".")
end

-- keep the XP line ticking
local tick = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
  tick = tick + arg1
  if tick > 5 and f and f:IsShown() then
    tick = 0
    UpdateXP(G.route)
  end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  Create()
  if G.db.hidden then f:Hide() end
  G:Refresh()
  local route = G.route
  G.Print("loaded " .. table.getn(G.routes) .. " route" .. (table.getn(G.routes) == 1 and "" or "s") ..
    (route and (". Now: " .. route.title .. " (" .. route.min .. "-" .. route.max .. ")") or "") .. ". |cffffffff/sg help|r for commands.")
end)

BINDING_HEADER_SNAPGUIDE = "SnapGuide"
BINDING_NAME_SNAPGUIDE_TARGET = "Target the step's NPC or mob"
BINDING_NAME_SNAPGUIDE_SKIP = "Tick / skip the current step"
