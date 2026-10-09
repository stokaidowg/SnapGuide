-- Finds quests in a route that can be done at the same time: their objectives share mobs,
-- or their spawn points sit in the same area. Run through overlap.js (needs the pfQuest DB).
-- ROUTEFILES = { "path/a18_darkshore.lua", ... } is set before this runs.

local ZONEID = {}
for id, name in pairs(ZN) do
  name = string.gsub(name, "%s+$", "")
  if not ZONEID[name] or id < ZONEID[name] then ZONEID[name] = id end
end

-- objective spawn points { x, y } in zone z, and the unit ids you kill for them
local function Points(qid, z)
  local q = Q[qid]
  local pts, units = {}, {}
  if not q or not q.obj then return pts, units end
  local function add(kind, id)
    local db = kind == "U" and U or O
    if kind == "U" then units[id] = true end
    for _, c in ipairs((db[id] and db[id].coords) or {}) do
      if c[3] == z then table.insert(pts, { c[1], c[2] }) end
    end
  end
  for _, id in ipairs(q.obj.U or {}) do add("U", id) end
  for _, id in ipairs(q.obj.O or {}) do add("O", id) end
  for _, id in ipairs(q.obj.I or {}) do
    local src = I[id]
    if src then
      local list = {}
      for uid, chance in pairs(src.U or {}) do table.insert(list, { uid, chance }) end
      table.sort(list, function(a, b) return a[2] > b[2] end)
      for i, e in ipairs(list) do
        if e[2] >= 5 or i <= 3 then add("U", e[1]) end
      end
      for oid in pairs(src.O or {}) do add("O", oid) end
    end
  end
  return pts, units
end

-- share of a's points with one of b's within r (map percent)
local function Covered(a, b, r)
  if table.getn(a) == 0 then return 0 end
  local n = 0
  for _, p in ipairs(a) do
    for _, q in ipairs(b) do
      if math.abs(p[1] - q[1]) <= r and math.abs(p[2] - q[2]) <= r then n = n + 1 break end
    end
  end
  return n / table.getn(a)
end

local out = {}
SnapGuide = {}
function SnapGuide:Route(def) CUR = def end

for _, file in ipairs(ROUTEFILES) do
  CUR = nil
  dofile(file)
  local r = CUR
  -- C steps, with where the quest is accepted and turned in
  local cs, pos = {}, {}
  for i, s in ipairs(r.steps) do
    if s.q then
      pos[s.q] = pos[s.q] or {}
      pos[s.q][s.a] = pos[s.q][s.a] or i
    end
    if s.a == "C" and s.z then
      local z = ZONEID[s.z]
      local pts, units = Points(s.q, z)
      table.insert(cs, { i = i, s = s, pts = pts, units = units })
    end
  end
  local lines = {}
  for ai = 1, table.getn(cs) do
    for bi = ai + 1, table.getn(cs) do
      local a, b = cs[ai], cs[bi]
      if a.s.z == b.s.z and a.s.q ~= b.s.q then
        local shared = {}
        for u in pairs(a.units) do
          if b.units[u] then table.insert(shared, UN[u] or tostring(u)) end
        end
        local ca, cb = Covered(a.pts, b.pts, 3), Covered(b.pts, a.pts, 3)
        local near = a.s.x and b.s.x and math.abs(a.s.x - b.s.x) <= 4 and math.abs(a.s.y - b.s.y) <= 4
        if table.getn(shared) > 0 or math.max(ca, cb) >= 0.35 or near then
          table.sort(shared)
          table.insert(lines, string.format(
            "  %s[%d] C %d %s (A@%s T@%s)  +  [%d] C %d %s (A@%s T@%s)\n      gap %d steps | share mobs: %s | area overlap %d%%/%d%% | hotspots %.1f,%.1f / %.1f,%.1f",
            (b.s.w and b.i == a.i + 1) and "(together) " or "", a.i, a.s.q, a.s.t, tostring(pos[a.s.q].A), tostring(pos[a.s.q].T),
            b.i, b.s.q, b.s.t, tostring(pos[b.s.q].A), tostring(pos[b.s.q].T),
            b.i - a.i, table.getn(shared) > 0 and table.concat(shared, ", ") or "-",
            math.floor(ca * 100), math.floor(cb * 100), a.s.x or 0, a.s.y or 0, b.s.x or 0, b.s.y or 0))
        end
      end
    end
  end
  table.insert(out, "== " .. r.id .. " (" .. table.getn(cs) .. " C steps)")
  for _, l in ipairs(lines) do table.insert(out, l) end
end
return table.concat(out, "\n")
