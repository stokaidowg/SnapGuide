-- SnapGuide: a levelling guide for OctoWoW / Turtle WoW (1.12).
-- Routes (Routes\*.lua) are lists of steps generated from the OctoWoW quest database. This
-- file keeps your place in them: it reads the quest log, notices quests being accepted,
-- completed and turned in, ticks travel steps when you arrive, and works out the step to
-- show next. ui.lua draws it.
--
-- Step fields: a = action (A accept, C complete, T turn in, R go to, F fly, H hearth,
-- P flight path, S set hearth, B buy, L reach level, G grind, N note), q = quest id,
-- t = title/place, n = NPC, x/y/z = map spot, mobs = targetable names, o = objective text,
-- note, opt = optional, class/race = only for that class/race, lvl = level for L steps,
-- w = do this C step together with the C step before it (shown as one step),
-- el = the level the route expects you to be at this step, sk = (A steps) the quest can be
-- skipped when you're ahead of the route, worth sk levels; ql = that quest's level.

SnapGuide = { routes = {}, byId = {} }
local G = SnapGuide

local _, PLAYER_CLASS = UnitClass("player")
local PLAYER_RACE = UnitRace("player")
local CLASS_NAME = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

function G.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7SnapGuide|r " .. msg)
end

-- [[ routes ]] --
-- routes register themselves in play order (the .toc lists them that way)
function G:Route(def)
  def.index = table.getn(self.routes) + 1
  local turnIn = {}
  for i, s in ipairs(def.steps) do
    s.i = i
    s.key = def.id .. ":" .. i
    if s.a == "T" and s.q then turnIn[s.q] = i end
  end
  -- skippable pickups: where the route turns them in (ti), past the end if a later route does
  for _, s in ipairs(def.steps) do
    if s.a == "A" and s.sk then s.ti = turnIn[s.q] or 100000 end
  end
  table.insert(self.routes, def)
  self.byId[def.id] = def
end

-- [[ saved state ]] --
-- SnapGuideDB (per character): route = id, ticked[key] = true for travel/manual steps done,
-- skipped[key] = true, done[questId] = true for quests turned in,
-- overskip[questId] = true for quests passed over because you were ahead, keep[questId] =
-- true for ones you brought back with /sg back (never passed over again),
-- overlevel = false turns that off, ahead = how many levels ahead to stay (default 0.5)
local db

local function InitDB()
  SnapGuideDB = SnapGuideDB or {}
  db = SnapGuideDB
  db.ticked = db.ticked or {}
  db.skipped = db.skipped or {}
  db.done = db.done or {}
  db.overskip = db.overskip or {}
  db.keep = db.keep or {}
  db.xp = db.xp or {}
  G.db = db
end

-- turned in? ours, plus pfQuest's history when it's installed (it records every turn-in).
-- A quest we can see in your log isn't, whatever pfQuest says: it guesses ids from titles
-- and can mark the wrong part of a chain done (The Absent Minded Prospector).
function G:IsDone(qid)
  if self.inLog[qid] then return false end
  if db.done[qid] then return true end
  if pfQuest_history and pfQuest_history[qid] then return true end
end

-- [[ quest log ]] --
-- log[title] = { complete = bool, level = n, qid = id when we could tell which quest of a
-- shared title it is } for every quest in the log; inLog[qid] = true for those ids
G.log = {}
G.inLog = {}
G.collapsed = false

-- titles[title] = quest ids with that title, in route order across every route;
-- objs[qid] = objective text, which routes carry for quests sharing a title
function G:Titles()
  if not self.titles then
    self.titles, self.objs = {}, {}
    for _, r in ipairs(self.routes) do
      for _, s in ipairs(r.steps) do
        if s.q and s.t then
          local list = self.titles[s.t] or {}
          self.titles[s.t] = list
          local seen = false
          for _, q in ipairs(list) do if q == s.q then seen = true end end
          if not seen then table.insert(list, s.q) end
          if s.o and not self.objs[s.q] then self.objs[s.q] = s.o end
        end
      end
    end
  end
  return self.titles
end

-- lower case letters and digits only, without the database's $N/$B placeholders
local function Plain(text)
  text = string.gsub(text or "", "%$%a", "")
  return string.gsub(string.lower(text), "[^%w]", "")
end

-- which of the quests sharing this title has this objective text (nil when none is clear)
function G:MatchObjective(title, text)
  text = Plain(text)
  if text == "" then return nil end
  local best, bestLen, tie = nil, 0, false
  for _, q in ipairs(self:Titles()[title] or {}) do
    local o = self.objs[q] and Plain(self.objs[q])
    if o and o ~= "" then
      local n, max = 0, math.min(string.len(o), string.len(text))
      while n < max and string.byte(o, n + 1) == string.byte(text, n + 1) do n = n + 1 end
      if n > bestLen then best, bestLen, tie = q, n, false
      elseif n == bestLen and n > 0 then tie = true end
    end
  end
  if best and not tie and bestLen >= 12 then return best end
end

function G:ReadLog()
  local log, inLog = {}, {}
  local collapsed = false
  local titles = self:Titles()
  local selected = GetQuestLogSelection and GetQuestLogSelection()
  local moved = false
  local n = GetNumQuestLogEntries()
  for i = 1, n do
    local title, level, _, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
    if isHeader then
      if isCollapsed then collapsed = true end
    elseif title then
      local entry = { complete = isComplete == 1, level = level, index = i }
      local list = titles[title]
      if list and table.getn(list) > 1 and GetQuestLogQuestText and SelectQuestLogEntry then
        -- a title several quests share: tell them apart by the objective text
        SelectQuestLogEntry(i)
        moved = true
        local _, objective = GetQuestLogQuestText()
        entry.qid = self:MatchObjective(title, objective)
      elseif list and table.getn(list) == 1 then
        entry.qid = list[1]
      end
      if entry.qid then inLog[entry.qid] = true end
      log[title] = entry
    end
  end
  if moved then SelectQuestLogEntry(selected or 0) end
  self.log = log
  self.inLog = inLog
  self.collapsed = collapsed
  self.logRead = true
end

-- several quests in a chain can share a title ("A Lost Master" parts 1 and 2). The one in
-- your log is the one its objective text matches, or else the earliest one, in route order
-- across every route, not turned in yet.
function G:Owner(route, title)
  local entry = self.log[title]
  if entry and entry.qid then return entry.qid end
  for _, q in ipairs(self:Titles()[title] or {}) do
    if not self:IsDone(q) then return q end
  end
end

-- [[ step state ]] --
function G:Applies(s)
  if s.class and s.class ~= CLASS_NAME[PLAYER_CLASS] then return false end
  if s.race and s.race ~= PLAYER_RACE and not (s.race == "NightElf" and PLAYER_RACE == "Night Elf") then return false end
  return true
end

-- where you are, as zone name and map x/y in percent (nil when the map shows elsewhere)
function G:Position()
  if WorldMapFrame and WorldMapFrame:IsShown() then
    return self.lastZone, self.lastX, self.lastY
  end
  SetMapToCurrentZone()
  local x, y = GetPlayerMapPosition("player")
  local zone = GetRealZoneText()
  if x and (x > 0 or y > 0) then
    self.lastZone, self.lastX, self.lastY = zone, x * 100, y * 100
    return zone, x * 100, y * 100
  end
  return zone
end

local function Near(s, zone, x, y, range)
  if not s.x or not x or zone ~= s.z then return false end
  return math.abs(s.x - x) <= range and math.abs(s.y - y) <= range * 1.5
end

local function Here(name)
  if not name then return false end
  return GetSubZoneText() == name or GetRealZoneText() == name or GetMinimapZoneText() == name
end

-- [[ ahead of the route ]] --
-- your level with the fraction through it, e.g. 24.6
function G:PlayerLevel()
  local max = UnitXPMax("player")
  local frac = (max and max > 0) and UnitXP("player") / max or 0
  return UnitLevel("player") + frac
end

-- quests at or below this level are grey for you (the client's grey-level formula)
local function GreyLevel(level)
  if level <= 5 then return 0 end
  if level <= 39 then return level - math.floor(level / 10) - 5 end
  return level - math.floor(level / 5) - 1
end

-- this step's quest is in your log
function G:Started(route, s)
  return self.log[s.t] and self:Owner(route, s.t) == s.q
end

-- pass over a pickup when you're ahead of the route? Only quests the route marked skippable
-- (no later quest needs them, not class quests), only ones you haven't picked up or done,
-- and only while the XP you'd give up still leaves you `ahead` levels in front of the route.
-- deficit: XP (in levels) of quests already passed over whose turn-in the route hasn't
-- reached yet, so its expected level doesn't count them yet. Grey quests always go.
function G:CanOverskip(route, s, deficit)
  if db.overlevel == false or s.a ~= "A" or not s.sk or db.keep[s.q] then return false end
  if not self.logRead or self.collapsed then return false end -- can't see the whole log yet
  if not self:Applies(s) or self:IsDone(s.q) or self:Started(route, s) then return false end
  if s.ql and s.ql <= GreyLevel(UnitLevel("player")) then return "grey" end
  deficit = deficit or self.deficit or 0
  if self:PlayerLevel() - (s.el or 0) - deficit - s.sk >= (db.ahead or 0.5) then return "ahead" end
  return false
end

-- is the step finished? (travel steps tick once and stay ticked)
function G:StepDone(route, s)
  if not self:Applies(s) then return true end
  if db.skipped[s.key] or db.ticked[s.key] then return true end
  local a = s.a
  -- a quest passed over for being ahead: its steps are done, unless you picked it up anyway
  if s.q and db.overskip[s.q] and (a == "A" or a == "C" or a == "T") and not self:Started(route, s) then
    return true
  end
  if a == "A" or a == "C" then
    if self:IsDone(s.q) then return true end
    local entry = self.log[s.t]
    if not entry or self:Owner(route, s.t) ~= s.q then
      -- an optional quest you never took (or abandoned) doesn't hold the route up
      if s.opt and a == "C" then return true end
      return false
    end
    if a == "A" then return true end
    return entry.complete
  elseif a == "T" then
    if self:IsDone(s.q) then return true end
    if s.opt and not self.log[s.t] then return true end
    return false
  elseif a == "X" then
    -- abandon: done once it's out of your log (or you turned it in after all)
    return not self.log[s.t] or self:IsDone(s.q)
  elseif a == "L" then
    return UnitLevel("player") >= (s.lvl or 0)
  elseif a == "S" then
    return GetBindLocation() == s.t
  end
  return false
end

-- travel/manual steps that complete themselves when you get there
function G:CheckArrival(route, s)
  if db.ticked[s.key] then return end
  local a = s.a
  if a == "R" or a == "F" or a == "H" then
    local zone, x, y = self:Position()
    if Near(s, zone, x, y, 1.2) or (not s.x and Here(s.t)) or (a ~= "R" and Here(s.t)) then
      db.ticked[s.key] = true
      return true
    end
  end
end

-- [[ current step ]] --
function G:CurrentRoute()
  local r = db.route and self.byId[db.route]
  if r then return r end
  -- first time: the first route that suits your level
  local level = UnitLevel("player")
  for _, route in ipairs(self.routes) do
    if level < route.max then return route end
  end
  return self.routes[1]
end

function G:SetRoute(id)
  db.route = id
  self:Refresh()
end

local function ReportOverskip(list)
  if not list then return end
  if table.getn(list.ahead) > 0 then
    G.Print(string.format("you're %.1f levels ahead of the guide, skipping: |cffffffff%s|r",
      G:PlayerLevel() - (list.el or 0), table.concat(list.ahead, ", ")))
  end
  if table.getn(list.grey) > 0 then
    G.Print("grey for you now, skipping: |cffffffff" .. table.concat(list.grey, ", ") .. "|r")
  end
  if not G.hinted then
    G.hinted = true
    G.Print("|cffffffff/sg back|r brings a skipped quest back, |cffffffff/sg ahead off|r stops skipping.")
  end
end

-- first unfinished step; when a route is finished, moves on to the next one.
-- Pickups you're too far ahead for are passed over on the way (and remembered).
function G:Current()
  local route = self:CurrentRoute()
  if not route then return nil end
  local passed
  local open = {} -- passed-over pickups so far, to work out the deficit at each step
  local function Deficit(i)
    local d = 0
    for _, a in ipairs(open) do
      if a.ti > i then d = d + a.sk end
    end
    return d
  end
  for _, s in ipairs(route.steps) do
    if not self:StepDone(route, s) then
      local deficit = Deficit(s.i)
      local why = self:CanOverskip(route, s, deficit)
      if why then
        db.overskip[s.q] = true
        table.insert(open, s)
        passed = passed or { el = s.el, ahead = {}, grey = {} }
        table.insert(passed[why], s.t)
      else
        self.deficit = deficit
        ReportOverskip(passed)
        return route, s
      end
    elseif s.ti and db.overskip[s.q] and not self:Started(route, s) then
      table.insert(open, s)
    end
  end
  self.deficit = 0
  ReportOverskip(passed)
  local nextRoute = self.routes[route.index + 1]
  if nextRoute and db.route ~= nextRoute.id then
    db.route = nextRoute.id
    G.Print("|cff60ff60" .. route.title .. " done.|r On to " .. nextRoute.title .. " (" .. nextRoute.min .. "-" .. nextRoute.max .. ").")
    return self:Current()
  end
  return route, nil
end

-- a step still to do, for looking ahead: not done and not one you'll pass over
function G:Pending(route, s)
  return not self:StepDone(route, s) and not self:CanOverskip(route, s)
end

-- the current step plus the unfinished C steps marked to be done along with it
function G:Group(route, s)
  local group = { s }
  if s.a ~= "C" then return group end
  for i = s.i + 1, table.getn(route.steps) do
    local n = route.steps[i]
    if not n.w then break end
    if not self:StepDone(route, n) then table.insert(group, n) end
  end
  return group
end

-- the next few unfinished steps after the current one (and anything grouped with it), for
-- the preview lines
function G:Upcoming(route, from, count)
  local list = {}
  local group = self:Group(route, from)
  for i = group[table.getn(group)].i + 1, table.getn(route.steps) do
    local s = route.steps[i]
    if self:Pending(route, s) then
      table.insert(list, s)
      if table.getn(list) >= count then break end
    end
  end
  return list
end

-- tick or skip the current step by hand
function G:Tick(s)
  if not s then return end
  if s.a == "A" or s.a == "C" or s.a == "T" or s.a == "L" or s.a == "S" then
    db.skipped[s.key] = true
  else
    db.ticked[s.key] = true
  end
  self:Refresh()
end

-- undo: un-tick the last ticked/skipped step before the current one. A quest passed over
-- for being ahead comes back for good (it won't be passed over again).
function G:Back()
  local route, cur = self:Current()
  if not route then return end
  local last = cur and cur.i - 1 or table.getn(route.steps)
  for i = last, 1, -1 do
    local s = route.steps[i]
    if db.ticked[s.key] or db.skipped[s.key] then
      db.ticked[s.key], db.skipped[s.key] = nil, nil
      break
    elseif s.a == "A" and db.overskip[s.q] and not self:IsDone(s.q) then
      db.overskip[s.q] = nil
      db.keep[s.q] = true
      G.Print("bringing back " .. s.t .. ".")
      break
    end
  end
  self:Refresh()
end

-- [[ turn-ins ]] --
-- The quest window's title when you click Complete Quest; once that quest leaves the log
-- it was turned in (rather than abandoned).
local pendingTurnIn, pendingAt

function G:NoteTurnIns(oldLog)
  if not pendingTurnIn then return end
  if GetTime() - pendingAt > 60 then
    pendingTurnIn = nil -- closed the window without completing
    return
  end
  local old = oldLog[pendingTurnIn]
  if old and not self.log[pendingTurnIn] then
    local qid = old.qid or self:Owner(nil, pendingTurnIn)
    if qid then
      db.done[qid] = true
    end
    pendingTurnIn = nil
  end
end

-- [[ level tracking ]] --
-- XP gained this session and per hour; time to level at that pace
G.session = { start = GetTime(), xp = 0 }
local lastXP, lastMax

local function TrackXP()
  local xp, max = UnitXP("player"), UnitXPMax("player")
  if lastXP then
    if xp >= lastXP then
      G.session.xp = G.session.xp + (xp - lastXP)
    else
      -- levelled up: the rest of the old level plus what's in the new one
      G.session.xp = G.session.xp + (lastMax - lastXP) + xp
    end
  end
  lastXP, lastMax = xp, max
end

function G:XPRate()
  local hours = (GetTime() - self.session.start) / 3600
  if hours < 0.02 or self.session.xp <= 0 then return nil end
  return self.session.xp / hours
end

-- [[ refresh ]] --
function G:Refresh()
  if not db then return end
  local route, s = self:Current()
  self.route, self.step = route, s
  if self.OnRefresh then self:OnRefresh(route, s) end
end

-- [[ events ]] --
local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_COMPLETE", "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "UI_INFO_MESSAGE",
  "TAXIMAP_OPENED", "PLAYER_ENTERING_WORLD" }) do
  events:RegisterEvent(e)
end
events:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 ~= "SnapGuide" then return end
    InitDB()
    return
  end
  if not db then return end
  if event == "PLAYER_LOGIN" then
    G:ReadLog()
    TrackXP()
  elseif event == "QUEST_LOG_UPDATE" then
    local old = G.log
    G:ReadLog()
    G:NoteTurnIns(old)
  elseif event == "QUEST_COMPLETE" then
    pendingTurnIn, pendingAt = GetTitleText(), GetTime()
  elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
    TrackXP()
  elseif event == "UI_INFO_MESSAGE" then
    -- "New flight path discovered!"
    if arg1 == ERR_NEWTAXIPATH and G.step and G.step.a == "P" then
      db.ticked[G.step.key] = true
    end
  elseif event == "TAXIMAP_OPENED" then
    -- talking to the flight master you were sent to: you have the path now
    if G.step and G.step.a == "P" then
      db.ticked[G.step.key] = true
    end
  end
  G:Refresh()
end)

-- arrival checks run a few times a second
local elapsed = 0
events:SetScript("OnUpdate", function()
  elapsed = elapsed + arg1
  if elapsed < 0.5 or not db then return end
  elapsed = 0
  if G.route and G.step and G:CheckArrival(G.route, G.step) then
    G:Refresh()
  end
end)

-- [[ /sg ]] --
SLASH_SNAPGUIDE1 = "/sg"
SLASH_SNAPGUIDE2 = "/snapguide"
SlashCmdList["SNAPGUIDE"] = function(msg)
  local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "skip" or cmd == "next" then
    G:Tick(G.step)
  elseif cmd == "back" then
    G:Back()
  elseif cmd == "target" then
    if G.Target then G:Target() end
  elseif cmd == "routes" or cmd == "list" then
    for _, r in ipairs(G.routes) do
      G.Print((r == G.route and "|cff4fc3f7> |r" or "  ") .. r.index .. ". " .. r.title .. " (" .. r.min .. "-" .. r.max .. ")")
    end
  elseif cmd == "route" and tonumber(rest) and G.routes[tonumber(rest)] then
    G:SetRoute(G.routes[tonumber(rest)].id)
  elseif cmd == "arrow" and (rest == "config" or rest == "options") then
    if G.ToggleArrowConfig then G.ToggleArrowConfig() end
  elseif cmd == "arrow" then
    db.arrow = db.arrow == false
    G.Print("arrow " .. (db.arrow == false and "hidden" or "shown") .. ". |cffffffff/sg arrow config|r for size and text.")
  elseif cmd == "fade" then
    if G.FadeCommand then G:FadeCommand() end
  elseif cmd == "talents" or cmd == "talent" then
    if G.TalentCommand then G:TalentCommand(string.lower(rest or "")) end
  elseif cmd == "ahead" then
    rest = string.lower(rest or "")
    if tonumber(rest) then
      db.ahead = math.max(0, tonumber(rest))
      db.overlevel = nil
    elseif rest == "off" then
      db.overlevel = false
    elseif rest == "on" then
      db.overlevel = nil
    elseif rest == "" then
      if db.overlevel == false then db.overlevel = nil else db.overlevel = false end
    end
    if db.overlevel == false then
      G.Print("skipping quests when you're ahead: |cffff6060off|r.")
    else
      G.Print(string.format("skipping quests when you're ahead: |cff60ff60on|r, keeping you %.1f levels ahead of the guide (|cffffffff/sg ahead 1|r to change). You're %+.1f now.",
        db.ahead or 0.5, G.step and G.step.el and (G:PlayerLevel() - G.step.el) or 0))
    end
    G:Refresh()
  elseif cmd == "reset" then
    db.ticked, db.skipped, db.overskip, db.keep = {}, {}, {}, {}
    G:Refresh()
    G.Print("ticks and skips cleared for every route.")
  elseif cmd == "hide" or cmd == "show" or cmd == "" then
    if G.ToggleFrame then G:ToggleFrame(cmd) end
  else
    G.Print("|cffffffff/sg|r show/hide   |cffffffff/sg skip|r tick the current step   |cffffffff/sg back|r undo")
    G.Print("|cffffffff/sg target|r target the step's NPC or mob   |cffffffff/sg routes|r list   |cffffffff/sg route <n>|r jump to one")
    G.Print("|cffffffff/sg arrow|r hide or show the arrow   |cffffffff/sg reset|r clear all ticks and skips")
    G.Print("|cffffffff/sg ahead|r skip side quests when you're ahead of the guide (on/off, or |cffffffff/sg ahead 1|r = stay 1 level ahead)")
    G.Print("|cffffffff/sg fade|r in dungeons and raids, show the guide only on mouse-over (on by default)")
    G.Print("|cffffffff/sg talents|r the talent plan (|cffffffff/sg talents off|r to stop the advice)")
  end
end
