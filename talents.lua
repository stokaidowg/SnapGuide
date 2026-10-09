-- SnapGuide talents: a levelling build per class, one pick after another. When you have a
-- point to spend it says which talent is next, and in the talent window it opens that tree
-- and makes the talent glow.
--
-- A plan is a list of { talent name, rank to reach }, in the order you take them. The same
-- talent can come back with a higher rank later (2H Spec 1 before Seal of Command, then 3).

local G = SnapGuide

-- Retribution (Turtle WoW build from forum.turtlecraft.gg t=21206: 0/0/21 at 30, 5/0/36 at 50;
-- order between 30 and 50 puts damage first). 51+ is the obvious leftovers, then your choice.
G.talentPlans = {
  PALADIN = {
    { "Benediction", 5 },                       -- 10-14
    { "Improved Blessings", 5 },                -- 15-19
    { "Improved Retribution Aura", 2 },         -- 20-21
    { "Conviction", 5 },                        -- 22-26
    { "Pursuit of Justice", 2 },                -- 27-28
    { "Two-Handed Weapon Specialization", 1 },  -- 29
    { "Seal of Command", 1 },                   -- 30
    { "Two-Handed Weapon Specialization", 3 },  -- 31-32
    { "Vengeance", 5 },                         -- 33-37
    { "Vengeful Strikes", 5 },                  -- 38-42
    { "Vindication", 3 },                       -- 43-45
    { "Divine Strength", 5 },                   -- 46-50
    { "Repentance", 1 },                        -- 51
    { "Improved Judgement", 2 },                -- 52-53
  },
}

local _, PLAYER_CLASS = UnitClass("player")

-- where a talent sits: tab, index, current rank, max rank
local function FindTalent(name)
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local tname, _, _, _, rank, maxRank = GetTalentInfo(tab, i)
      if tname == name then return tab, i, rank, maxRank end
    end
  end
end

-- the next pick of the plan: { name, tab, index, rank, target }, or nil when the plan is done
-- (talents the client doesn't have are skipped, so a renamed talent can't block the rest)
function G:NextTalent()
  local plan = self.talentPlans[PLAYER_CLASS]
  if not plan then return end
  for _, p in ipairs(plan) do
    local tab, index, rank = FindTalent(p[1])
    if tab and rank < p[2] then
      return { name = p[1], tab = tab, index = index, rank = rank, target = p[2] }
    end
  end
end

local function Enabled()
  return G.db and G.db.talents ~= false and G.talentPlans[PLAYER_CLASS]
end

-- [[ glow in the talent window ]] --
local glow, tabGlow

local function Pulse()
  this:SetAlpha(0.55 + 0.45 * math.sin(GetTime() * 5))
end

local function MakeGlow(texture)
  local f = CreateFrame("Frame")
  local t = f:CreateTexture(nil, "OVERLAY")
  t:SetTexture(texture)
  t:SetBlendMode("ADD")
  t:SetVertexColor(0.31, 0.76, 0.97)
  t:SetAllPoints(f)
  f:SetScript("OnUpdate", Pulse)
  f:Hide()
  return f
end

local function Place(f, parent, scale)
  f:SetParent(parent)
  f:ClearAllPoints()
  f:SetPoint("CENTER", parent, "CENTER", 0, 0)
  f:SetWidth(parent:GetWidth() * scale)
  f:SetHeight(parent:GetHeight() * scale)
  f:SetFrameLevel(parent:GetFrameLevel() + 2)
  f:Show()
end

function G:TalentGlow()
  if not glow then
    glow = MakeGlow("Interface\\Buttons\\UI-ActionButton-Border")
    tabGlow = MakeGlow("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
  end
  glow:Hide()
  tabGlow:Hide()
  if not Enabled() or not TalentFrame or not TalentFrame:IsVisible() then return end
  if UnitCharacterPoints("player") <= 0 then return end
  local n = self:NextTalent()
  if not n then return end
  if PanelTemplates_GetSelectedTab(TalentFrame) == n.tab then
    local button = getglobal("TalentFrameTalent" .. n.index)
    if button and button:IsShown() then Place(glow, button, 1.8) end
  else
    -- you're looking at another tree: point at the right tab
    local tab = getglobal("TalentFrameTab" .. n.tab)
    if tab then Place(tabGlow, tab, 1) end
  end
end

-- Blizzard_TalentUI loads on demand: wrap its update (runs on show, tab clicks and every
-- point spent) and its OnShow (open on the tree the next pick is in)
local hooked
local function Hook()
  if hooked or not TalentFrame_Update then return end
  hooked = true
  local update = TalentFrame_Update
  TalentFrame_Update = function()
    update()
    G:TalentGlow()
  end
  local onShow = TalentFrame_OnShow
  TalentFrame_OnShow = function()
    if Enabled() and UnitCharacterPoints("player") > 0 then
      local n = G:NextTalent()
      if n and PanelTemplates_GetSelectedTab(TalentFrame) ~= n.tab then
        PanelTemplates_SetTab(TalentFrame, n.tab)
      end
    end
    onShow()
  end
end

-- [[ chat reminder ]] --
-- once per pick: "Talent point: Conviction (2/5)"
local lastSaid
local function Remind()
  if not Enabled() then return end
  local points = UnitCharacterPoints("player")
  if points <= 0 then lastSaid = nil return end
  local n = G:NextTalent()
  if not n then return end
  local key = n.name .. ":" .. n.rank .. ":" .. points
  if key == lastSaid then return end
  lastSaid = key
  G.Print("talent point: |cffffffff" .. n.name .. "|r (" .. (n.rank + 1) .. "/" .. n.target .. ")"
    .. (points > 1 and ", " .. points .. " points to spend" or "") .. ". Open talents (N): it's glowing.")
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 == "Blizzard_TalentUI" or (arg1 == "SnapGuide" and IsAddOnLoaded("Blizzard_TalentUI")) then Hook() end
    return
  end
  Remind()
end)

-- /sg talents [on|off]
function G:TalentCommand(rest)
  if rest == "off" or rest == "on" then
    self.db.talents = rest == "on"
    self.Print("talent advice " .. (rest == "on" and "on" or "off") .. ".")
    self:TalentGlow()
    return
  end
  local plan = self.talentPlans[PLAYER_CLASS]
  if not plan then
    self.Print("no talent plan for your class yet.")
    return
  end
  local n = self:NextTalent()
  self.Print("talent plan" .. (self.db.talents == false and " (|cffff6060off|r: /sg talents on)" or "") .. ":")
  for _, p in ipairs(plan) do
    local _, _, rank = FindTalent(p[1])
    local mark
    if not rank then mark = "|cff808080?|r"
    elseif rank >= p[2] then mark = "|cff60ff60done|r"
    elseif n and n.name == p[1] and n.target == p[2] then mark = "|cff4fc3f7next|r"
    else mark = "  " end
    self.Print("  " .. mark .. " " .. p[1] .. " " .. p[2])
  end
  if not n then self.Print("plan finished: the rest are up to you.") end
end
