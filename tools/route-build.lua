-- SnapGuide route builder. Runs inside the pfQuest DB state (pfdb.js).
-- Build(specText) turns a route script into SnapGuide Lua data plus a report of problems.
-- State (completed quests, quest log, level) carries over between routes built in order.
--
-- Route script, one step per line ("#" starts a comment):
--   ROUTE id | Title | minLevel | maxLevel        starts a route
--   ZONE Darkshore                               zone used for lookups until the next ZONE
--   DONE 123 456 ...                             quests already turned in (catch-up)
--   LOG 123 456 ...                              quests already in the log (catch-up)
--   A 4740 | note    C 4740 | note    T 4740 | note       accept / complete / turn in
--   R x,y | Place name | note                    go somewhere ("R | Place" without coords is fine)
--   F Place | note                               fly to Place
--   P Npc Name | Place | note                    get the flight path from Npc Name
--   S Npc Name | Place | note                    make Place your home at innkeeper Npc Name
--   H Place | note                               hearth to Place
--   B Npc Name | what to buy                     buy something
--   L 20 | note                                  keep going until level 20
--   G x,y | note                                 grind here
--   N note                                       anything else (manual tick)
-- Flags anywhere after the first field: @opt  @Paladin (class)  @Dwarf (race)  @xy=37.4,77.0
--   @zone=Ashenvale  @mobs=Name;Name  @nomobs  @lvl=19 (level the route expects here)
--   @together (on a C step: do it at the same time as the C step just before; the guide
--   shows them as one step and targets both quests' mobs)
--   @keep (on an A step: never skip this quest when you're ahead of the route)
--   @also=101;2880 (on a C step: other quests whose items or kills you'll get here too, like
--   "any skeleton" drops; the guide shows their progress under the step as well)

local CLASSBIT = { Warrior = 1, Paladin = 2, Hunter = 4, Rogue = 8, Priest = 16, Shaman = 64, Mage = 128, Warlock = 256, Druid = 1024 }
local RACEBIT = { Human = 1, Dwarf = 4, ["Night Elf"] = 8, NightElf = 8, Gnome = 64, ["High Elf"] = 512, HighElf = 512 }
local ZONEID = {}
for id, name in pairs(ZN) do
  name = string.gsub(name, "%s+$", "")
  if not ZONEID[name] or id < ZONEID[name] then ZONEID[name] = id end
end

STATE = STATE or { done = {}, log = {}, level = 1, xp = 0 }

-- titles more than one Alliance quest uses: the add-on tells those apart in your log by
-- their objective text, so every step of theirs carries it
local SHARED = {}
for id, q in pairs(Q) do
  local name = QN[id] and QN[id].T
  if name and Faction(q) ~= "H" then SHARED[name] = (SHARED[name] or 0) + 1 end
end

-- [[ XP model ]] --
-- XP to go from each level to the next (vanilla table)
local XP_NEEDED = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
  16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800,
  54100, 57700, 61000, 64900, 68700, 72800, 76500, 80900, 85400, 90000, 94900, 99700, 104800, 109800, 115100,
  120500, 126000, 131800, 137600, 143500, 149500, 155800, 162200, 168800, 175500, 182400, 189500, 196700 }

-- 1.25: what the estimate misses, mostly mobs killed on the way and discovery XP
local function AddXP(amount)
  STATE.xp = STATE.xp + amount * 1.25
  while STATE.level < 60 and STATE.xp >= XP_NEEDED[STATE.level] do
    STATE.xp = STATE.xp - XP_NEEDED[STATE.level]
    STATE.level = STATE.level + 1
  end
end

-- current level with the fraction through it, e.g. 20.4
local function Level()
  if STATE.level >= 60 then return 60 end
  return STATE.level + STATE.xp / XP_NEEDED[STATE.level]
end

-- rough quest reward: grows with quest level, cut once the quest is 6+ levels below you;
-- quests with nothing to do (deliver a letter, talk to someone) give about half
local function QuestXP(q)
  local ql = q.lvl or STATE.level
  local xp = 55 * ql + 1.2 * ql * ql
  local diff = STATE.level - ql
  if diff >= 10 then xp = xp * 0.1
  elseif diff >= 6 then xp = xp * (1 - 0.2 * (diff - 5)) end
  if not q.obj then xp = xp * 0.5 end
  return xp
end

-- kills while doing an objective: the counts in its text ("Kill 10 ...", "Collect 8 ..."),
-- items need about twice as many kills as items
local function KillXP(q)
  if not q.obj or not (q.obj.U or q.obj.I) then return 0 end
  local text = (QN[q.id or 0] and QN[q.id or 0].O) or ""
  local kills = 0
  for n in string.gmatch(text, "(%d+)") do kills = kills + math.min(tonumber(n), 20) end
  if q.obj.I and not q.obj.U then kills = kills * 2 end
  if kills == 0 then kills = 6 end
  kills = math.min(kills, 30)
  local ml = q.lvl or STATE.level
  local per = 45 + 5 * ml
  local diff = STATE.level - ml
  if diff > 4 then per = per * math.max(0.1, 1 - 0.15 * (diff - 4)) end
  return kills * per
end

-- OctoWoW's client redrew these zone maps with wider bounds (patch-4 WorldMapArea.dbc: left,
-- right, top, bottom) but the database has their coordinates for the old ones. The builder
-- works in database coordinates (route scripts too) and converts on the way out.
local REMAP = {
  [406] = { old = { 3245.83, -1637.5, 2916.67, -339.58 }, new = { 3949, -2069, 3441, -569 } }, -- Stonetalon
  [5023] = { old = { 719.47, -269.16, 2000.77, 607.6 }, new = { 1013, -435, 1823, 858 } }, -- Sunnyglade
}
local function Remap(z, x, y)
  local f = REMAP[z]
  if not f then return x, y end
  local o, n = f.old, f.new
  local wy = o[1] - x / 100 * (o[1] - o[2])
  local wx = o[3] - y / 100 * (o[3] - o[4])
  return (n[1] - wy) / (n[1] - n[2]) * 100, (n[3] - wx) / (n[3] - n[4]) * 100
end

-- quests another Alliance quest needs first: skipping one would cut a chain the route (or a
-- later zone) uses, so these never get the "skip when ahead" mark
local CHAIN = {}
for _, q in pairs(Q) do
  if type(q) == "table" and q.pre and Faction(q) ~= "H" then
    for _, p in ipairs(q.pre) do CHAIN[p] = true end
  end
end

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end

local function lstr(s)
  return string.format("%q", s)
end

-- unit/object id by name, preferring one with spawns in zone z
local nameIndex
local function FindByName(name, z)
  if not nameIndex then
    nameIndex = {}
    for id, n in pairs(UN) do
      nameIndex[n] = nameIndex[n] or {}
      table.insert(nameIndex[n], { "U", id })
    end
    for id, n in pairs(ON) do
      local key = type(n) == "table" and n.T or n
      if type(key) == "string" then
        nameIndex[key] = nameIndex[key] or {}
        table.insert(nameIndex[key], { "O", id })
      end
    end
  end
  local best, bestc
  for _, e in ipairs(nameIndex[name] or {}) do
    local db = e[1] == "U" and U or O
    for _, c in ipairs((db[e[2]] and db[e[2]].coords) or {}) do
      if not best or (c[3] == z and bestc[3] ~= z) then
        best, bestc = e, c
      end
    end
  end
  return best, bestc
end

-- spawn points of units/objects, as { x, y, zone, name } (name only for units)
local function Spawns(kind, id, into)
  local db = kind == "U" and U or kind == "O" and O or pfDB.areatrigger.data
  for _, c in ipairs((db[id] and db[id].coords) or {}) do
    table.insert(into, { c[1], c[2], c[3], kind == "U" and UN[id] or nil })
  end
end

-- the best spot to do an objective: lots of spawns close together, not far from `ref`
-- (where the route has you just before). Each spawn scores how many others are within 6%;
-- that's divided down by distance from ref, so a decent cluster nearby beats a big one
-- across the zone.
local function Hotspot(points, z, ref)
  local inz, count = {}, {}
  for _, c in ipairs(points) do
    count[c[3]] = (count[c[3]] or 0) + 1
    if c[3] == z then table.insert(inz, c) end
  end
  if table.getn(inz) == 0 then
    -- not in this zone: use the zone with the most points
    local bz, bn = nil, 0
    for zz, n in pairs(count) do
      if n > bn then bz, bn = zz, n end
    end
    if not bz then return nil end
    z, ref = bz, nil
    for _, c in ipairs(points) do
      if c[3] == z then table.insert(inz, c) end
    end
  end
  local best, bestScore
  for _, c in ipairs(inz) do
    local near = 0
    for _, d in ipairs(inz) do
      if math.abs(c[1] - d[1]) <= 6 and math.abs(c[2] - d[2]) <= 6 then near = near + 1 end
    end
    local score = near
    if ref then
      local dist = math.sqrt((c[1] - ref[1]) ^ 2 + (c[2] - ref[2]) ^ 2)
      score = near / (1 + dist / 12)
    end
    if not bestScore or score > bestScore then best, bestScore = c, score end
  end
  local sx, sy, n = 0, 0, 0
  local names, order = {}, {}
  for _, c in ipairs(inz) do
    if math.abs(c[1] - best[1]) <= 6 and math.abs(c[2] - best[2]) <= 6 then
      sx, sy, n = sx + c[1], sy + c[2], n + 1
    end
    -- mobs worth targeting: ones that spawn around the spot
    if c[4] and math.abs(c[1] - best[1]) <= 10 and math.abs(c[2] - best[2]) <= 10 then
      if not names[c[4]] then table.insert(order, c[4]) end
      names[c[4]] = (names[c[4]] or 0) + 1
    end
  end
  table.sort(order, function(a, b) return names[a] > names[b] end)
  local mobs = {}
  for i = 1, math.min(6, table.getn(order)) do mobs[i] = order[i] end
  return math.floor(sx / n * 10 + 0.5) / 10, math.floor(sy / n * 10 + 0.5) / 10, z, mobs
end

local function Place(kind, id, z)
  local db = kind == "U" and U or O
  local e = db[id]
  local best
  for _, c in ipairs((e and e.coords) or {}) do
    if not best or (c[3] == z and best[3] ~= z) then best = c end
  end
  return best
end

local function Name(kind, id)
  if kind == "U" then return UN[id] end
  if kind == "O" then local n = ON[id] return type(n) == "table" and n.T or n end
  if kind == "I" then local n = IN[id] return type(n) == "table" and n.T or n end
end

-- who starts / ends a quest: name, coords, kind
local function Giver(t, z)
  if not t then return nil end
  for _, kind in ipairs({ "U", "O" }) do
    for _, id in ipairs(t[kind] or {}) do
      local c = Place(kind, id, z)
      return Name(kind, id), c, kind
    end
  end
  for _, id in ipairs(t.I or {}) do
    return Name("I", id), nil, "I"
  end
end

-- objectives: a hotspot near ref and the mobs to target there
local function Objectives(q, z, ref)
  local points, items = {}, {}
  local mob = function() end
  if not q.obj then return nil end
  for _, id in ipairs(q.obj.U or {}) do Spawns("U", id, points) end
  for _, id in ipairs(q.obj.O or {}) do Spawns("O", id, points) end
  for _, id in ipairs(q.obj.A or {}) do Spawns("A", id, points) end
  for _, id in ipairs(q.obj.I or {}) do
    table.insert(items, Name("I", id))
    local src = I[id]
    if src then
      -- best droppers first
      local list = {}
      for uid, chance in pairs(src.U or {}) do table.insert(list, { uid, chance }) end
      table.sort(list, function(a, b) return a[2] > b[2] end)
      -- droppers worth killing (5%+), or the best few if all are rare
      for i, e in ipairs(list) do
        if e[2] >= 5 or i <= 3 then Spawns("U", e[1], points) end
      end
      for oid in pairs(src.O or {}) do Spawns("O", oid, points) end
    end
  end
  local x, y, zz, mobs = Hotspot(points, z, ref)
  return x, y, zz, mobs, items
end

local function Flags(rest)
  local f = {}
  rest = string.gsub(rest, "@(%S+)", function(tok)
    local k, v = string.match(tok, "^([%w]+)=(.+)$")
    if k then
      f[k] = (string.gsub(v, "_", " "))
    elseif CLASSBIT[tok] then
      f.class = tok
    elseif RACEBIT[tok] then
      f.race = tok
    else
      f[tok] = true
    end
    return ""
  end)
  return f, rest
end

local function Fields(line)
  local parts = {}
  for p in string.gmatch(line .. "|", "([^|]*)|") do
    table.insert(parts, trim(p))
  end
  return parts
end

local function ClassesOf(mask)
  local t = {}
  for n, b in pairs(CLASSBIT) do
    if math.floor(mask / b) % 2 == 1 then table.insert(t, n) end
  end
  table.sort(t)
  return t
end

function Build(spec)
  local out, report = {}, {}
  local route = {}
  local steps = {}
  local zone, zid = nil, nil
  local warn = function(n, msg) table.insert(report, string.format("  line %d: %s", n, msg)) end
  local lineNo = 0

  for raw in string.gmatch(spec .. "\n", "([^\n]*)\n") do
    lineNo = lineNo + 1
    local line = trim(string.gsub(raw, "%s#.*$", ""))
    if string.sub(line, 1, 1) == "#" then line = "" end
    if line ~= "" then
      local flags
      flags, line = Flags(line)
      local op, rest = string.match(line, "^(%S+)%s*(.*)$")
      local f = Fields(rest)
      local step

      if op == "ROUTE" then
        route = { id = f[1], title = f[2], min = tonumber(f[3]), max = tonumber(f[4]), start = Level() }

      elseif op == "ZONE" then
        zone = f[1]
        zid = ZONEID[zone]
        if not zid then warn(lineNo, "unknown zone " .. zone) end
      elseif op == "START" then
        -- START 18 7919: your level and XP into it when this route begins (catch-up)
        local lv, xp = string.match(rest, "(%d+)%s+(%d+)")
        STATE.level, STATE.xp = tonumber(lv), tonumber(xp)
      elseif op == "DONE" then
        for id in string.gmatch(rest, "%d+") do STATE.done[tonumber(id)] = true end
      elseif op == "LOG" then
        for id in string.gmatch(rest, "%d+") do STATE.log[tonumber(id)] = true end
      elseif op == "A" or op == "C" or op == "T" then
        local qid = tonumber(f[1])
        local q = qid and Q[qid]
        if not q then
          warn(lineNo, "no quest " .. tostring(f[1]))
        else
          step = { a = op, q = qid, t = QName(qid), note = f[2] }
          if (SHARED[step.t] or 0) > 1 then step.o = QN[qid] and QN[qid].O end
          if op == "A" then
            local n, c, kind = Giver(q.start, zid)
            step.n = n
            if kind == "O" then step.obj = true end
            if kind == "I" then step.note = step.note or ("Starts from the item " .. tostring(n)) end
            if c then step.x, step.y, step.z = c[1], c[2], c[3] end
            if STATE.done[qid] then warn(lineNo, "accepting " .. qid .. " which is already done") end
            if STATE.log[qid] then warn(lineNo, "accepting " .. qid .. " which is already in the log") end
            if q.pre then
              local ok = false
              for _, p in ipairs(q.pre) do if STATE.done[p] then ok = true end end
              if not ok then warn(lineNo, "pre-quest not done for " .. qid .. " " .. QName(qid) .. ": needs " .. table.concat(q.pre, "/") .. " " .. QName(q.pre[1])) end
            end
            if q.min and q.min > STATE.level then
              warn(lineNo, string.format("%s needs level %d, you'd be %.1f here", QName(qid), q.min, Level()))
            end
            if q.race and q.race > 0 and Faction(q) == "H" then warn(lineNo, "Horde quest " .. qid) end
            -- skippable when you're ahead: sk = what the quest is worth, in levels at this point
            if not CHAIN[qid] and not q.class and not flags.class and not flags.keep then
              q.id = qid
              local worth = (QuestXP(q) + KillXP(q)) * 1.25 / XP_NEEDED[math.min(STATE.level, 59)]
              step.sk = math.max(0.01, math.floor(worth * 100 + 0.5) / 100)
              step.ql = q.lvl
            end
            if q.pre then step.pre = q.pre end
            STATE.log[qid] = true
          elseif op == "C" then
            -- near where the route has you: the last step with coordinates in this zone
            local ref
            for i = table.getn(steps), 1, -1 do
              if steps[i].x and steps[i].z == zid then ref = { steps[i].x, steps[i].y } break end
            end
            local x, y, z2, mobs, items = Objectives(q, zid, ref)
            step.x, step.y, step.z = x, y, z2
            if mobs and table.getn(mobs) > 0 and not flags.nomobs then step.mobs = mobs end
            step.o = QN[qid] and QN[qid].O
            if not STATE.log[qid] then warn(lineNo, "completing " .. qid .. " " .. QName(qid) .. " which isn't in the log") end
            q.id = qid
            -- doing a quest 4+ levels above you is hard going (5+ is red)
            if q.lvl and q.lvl - STATE.level >= 4 and not flags.opt then
              warn(lineNo, string.format("%s is level %d, you'd be %.1f doing it", QName(qid), q.lvl, Level()))
            end
            if not flags.opt then AddXP(KillXP(q)) end
          else
            local n, c, kind = Giver(q["end"], zid)
            step.n = n
            if kind == "O" then step.obj = true end
            if c then step.x, step.y, step.z = c[1], c[2], c[3] end
            if not STATE.log[qid] then warn(lineNo, "turning in " .. qid .. " " .. QName(qid) .. " which isn't in the log") end
            STATE.log[qid] = nil
            STATE.done[qid] = true
            if not flags.opt then AddXP(QuestXP(q)) end
          end
          if q.class and not flags.class then
            local cl = ClassesOf(q.class)
            if table.getn(cl) == 1 then flags.class = cl[1] else warn(lineNo, "class quest " .. qid .. " for " .. table.concat(cl, ",")) end
          end
        end
      elseif op == "R" or op == "G" then
        step = { a = op }
        local x, y = string.match(f[1] or "", "^([%d%.]+)%s*,%s*([%d%.]+)$")
        if x then
          step.x, step.y, step.z = tonumber(x), tonumber(y), (flags.zone and ZONEID[flags.zone]) or zid
          step.t, step.note = f[2], f[3]
        else
          step.t, step.note = f[2] ~= "" and f[2] or f[1], f[3]
        end
        if op == "G" then step.t, step.note = f[2], nil end
      elseif op == "F" or op == "H" then
        step = { a = op, t = f[1], note = f[2] }
      elseif op == "P" or op == "S" or op == "B" then
        local e, c = FindByName(f[1], zid)
        step = { a = op, n = f[1], t = f[2], note = f[3] }
        if c then step.x, step.y, step.z = c[1], c[2], c[3] else warn(lineNo, "no NPC called " .. f[1]) end
      elseif op == "X" then
        -- abandon a quest that isn't worth finishing (frees a log slot)
        local qid = tonumber(f[1])
        step = { a = "X", q = qid, t = qid and QName(qid), note = f[2] }
        if qid and not STATE.log[qid] then warn(lineNo, "abandoning " .. qid .. " which isn't in the log") end
        if qid then STATE.log[qid] = nil end
      elseif op == "L" then
        step = { a = "L", lvl = tonumber(f[1]), note = f[2] }
        local target = tonumber(f[1]) or 0
        if STATE.level < target then
          warn(lineNo, string.format("grind: you'd be %.1f, the route wants %d", Level(), target))
          STATE.level, STATE.xp = target, 0
        end
      elseif op == "N" then
        step = { a = "N", t = f[1], note = f[2] }
      else
        warn(lineNo, "unknown step " .. op)
      end

      if step then
        if flags.xy then
          local x, y = string.match(flags.xy, "([%d%.]+),([%d%.]+)")
          step.x, step.y = tonumber(x), tonumber(y)
          step.z = flags.zone and ZONEID[flags.zone] or zid
        end
        if flags.mobs then
          step.mobs = {}
          for m in string.gmatch(flags.mobs, "[^;]+") do table.insert(step.mobs, (string.gsub(m, "_", " "))) end
        end
        step.opt = flags.opt and true or nil
        if flags.also then
          step.also = {}
          for id in string.gmatch(flags.also, "%d+") do
            id = tonumber(id)
            if not Q[id] then warn(lineNo, "@also: no quest " .. id) else table.insert(step.also, id) end
          end
        end
        if flags.together then
          local prev = steps[table.getn(steps)]
          if step.a ~= "C" or not prev or prev.a ~= "C" then
            warn(lineNo, "@together needs a C step right after another C step")
          else
            step.w = true
          end
        end
        step.class, step.race = flags.class, flags.race
        step.el = math.floor(Level() * 10) / 10
        if (step.a == "C" or step.a == "T" or step.a == "A") and not step.x then
          warn(lineNo, step.a .. " " .. tostring(step.q) .. " " .. tostring(step.t) .. " has no coordinates")
        end
        step.line = lineNo
        table.insert(steps, step)
      end

      -- quest log check
      local n = 0
      for _ in pairs(STATE.log) do n = n + 1 end
      if n > 25 then warn(lineNo, "quest log has " .. n .. " quests (max 25 on OctoWoW)") end
    end
  end

  -- the level range shown in game comes from the simulation, not the header
  if route.start and route.start > 1 then
    route.min = math.floor(route.start)
    route.max = math.max(route.min + 1, math.floor(Level() + 0.5))
  end
  -- emit
  table.insert(out, "SnapGuide:Route({")
  table.insert(out, string.format("  id = %s, title = %s, min = %d, max = %d,", lstr(route.id), lstr(route.title), route.min, route.max))
  table.insert(out, "  steps = {")
  for _, s in ipairs(steps) do
    local p = { "a=" .. lstr(s.a) }
    if s.q then table.insert(p, "q=" .. s.q) end
    if s.t then table.insert(p, "t=" .. lstr(s.t)) end
    if s.n then table.insert(p, "n=" .. lstr(s.n)) end
    if s.x then table.insert(p, string.format("x=%.1f,y=%.1f", Remap(s.z, s.x, s.y))) end
    if s.z and ZN[s.z] then table.insert(p, "z=" .. lstr((string.gsub(ZN[s.z], "%s+$", "")))) end
    if s.lvl then table.insert(p, "lvl=" .. s.lvl) end
    if s.el then table.insert(p, "el=" .. s.el) end
    if s.sk then table.insert(p, "sk=" .. s.sk) end
    if s.ql then table.insert(p, "ql=" .. s.ql) end
    if s.pre then table.insert(p, "pre={" .. table.concat(s.pre, ",") .. "}") end
    if s.mobs then
      local m = {}
      for _, v in ipairs(s.mobs) do table.insert(m, lstr(v)) end
      table.insert(p, "mobs={" .. table.concat(m, ",") .. "}")
    end
    if s.o and s.o ~= "" then
      local o = string.gsub(s.o, "%$B", " ")
      table.insert(p, "o=" .. lstr(o))
    end
    if s.note and s.note ~= "" then table.insert(p, "note=" .. lstr(s.note)) end
    if s.opt then table.insert(p, "opt=true") end
    if s.also and table.getn(s.also) > 0 then table.insert(p, "also={" .. table.concat(s.also, ",") .. "}") end
    if s.obj then table.insert(p, "obj=true") end
    if s.w then table.insert(p, "w=true") end
    if s.class then table.insert(p, "class=" .. lstr(s.class)) end
    if s.race then table.insert(p, "race=" .. lstr(s.race)) end
    table.insert(out, "    {" .. table.concat(p, ",") .. "},")
  end
  table.insert(out, "  },")
  table.insert(out, "})")

  local logn = 0
  for _ in pairs(STATE.log) do logn = logn + 1 end
  table.insert(report, 1, string.format("%s: %d steps, quest log at end %d, level at end %.1f", tostring(route.id), table.getn(steps), logn, Level()))
  return table.concat(out, "\n") .. "\n", table.concat(report, "\n")
end
