-- Walking estimate for each built route: yards between consecutive steps with a map spot
-- (hearths and flights reset your position), the longest legs, and places the route comes
-- back to after going somewhere else. Run through travel.js. ROUTEFILES is set before this.

-- zone sizes in yards (same table as ui.lua)
local YARDS = {
  ["Darkshore"] = { 6550, 4367 }, ["Loch Modan"] = { 2758, 1840 }, ["Westfall"] = { 3500, 2333 },
  ["Redridge Mountains"] = { 2171, 1448 }, ["Duskwood"] = { 2700, 1800 }, ["Ashenvale"] = { 5767, 3844 },
  ["Stonetalon Mountains"] = { 4883, 3256 }, ["Wetlands"] = { 4135, 2756 }, ["Hillsbrad Foothills"] = { 3200, 2133 },
  ["Alterac Mountains"] = { 2800, 1867 }, ["Arathi Highlands"] = { 3600, 2400 }, ["Stranglethorn Vale"] = { 6381, 4254 },
  ["Desolace"] = { 4496, 2998 }, ["Dustwallow Marsh"] = { 5250, 3500 }, ["Badlands"] = { 2488, 1658 },
  ["Swamp of Sorrows"] = { 2294, 1529 }, ["Stormwind City"] = { 1738, 1158 }, ["Ironforge"] = { 791, 528 },
}

-- any zone missing above: its size from zones.lua's world bounds { continent, left, right, top, bottom }
if ZONESRC then
  local env = { SnapGuide = {} }
  local chunk = load(ZONESRC, "zones.lua", "t", env)
  if chunk then
    chunk()
    for name, z in pairs(env.SnapGuide.ZONES or {}) do
      if not YARDS[name] then YARDS[name] = { math.abs(z[2] - z[3]), math.abs(z[4] - z[5]) } end
    end
  end
end

local function Dist(a, b)
  if a.z ~= b.z then return nil end
  local y = YARDS[a.z]
  if not y then return nil end
  return math.sqrt(((a.x - b.x) / 100 * y[1]) ^ 2 + ((a.y - b.y) / 100 * y[2]) ^ 2)
end

local function Label(s)
  return string.format("[%d] %s %s", s.i, s.a, tostring(s.t or s.n or s.note or ""))
end

local out = {}
SnapGuide = {}
function SnapGuide:Route(def) CUR = def end
local grand = 0

for _, file in ipairs(ROUTEFILES) do
  CUR = nil
  dofile(file)
  local r = CUR
  for i, s in ipairs(r.steps) do s.i = i end
  local total, legs, here = 0, {}, nil
  local visits = {}
  local legNo = 0
  for _, s in ipairs(r.steps) do
    if s.a == "H" or s.a == "F" then
      here = nil
      legNo = legNo + 1
    elseif s.x and s.z then
      if here then
        local d = Dist(here, s)
        if d then
          total = total + d
          table.insert(legs, { d = d, from = here, to = s })
        end
      end
      here = s
      s.leg = legNo
      table.insert(visits, s)
    end
  end
  grand = grand + total
  table.sort(legs, function(a, b) return a.d > b.d end)
  table.insert(out, string.format("== %s: %.0f yards walked (%.1f min at 7 yd/s)", r.id, total, total / 7 / 60))
  for k = 1, math.min(5, table.getn(legs)) do
    local l = legs[k]
    table.insert(out, string.format("   %5.0f yd  %s (%.1f,%.1f) -> %s (%.1f,%.1f)", l.d, Label(l.from), l.from.x, l.from.y, Label(l.to), l.to.x, l.to.y))
  end
  -- out and back: walking (no hearth/flight) from a spot and returning to it within a few
  -- stops, after going 500+ yards away
  local a = 1
  while a <= table.getn(visits) do
    local found
    for b = a + 2, math.min(a + 8, table.getn(visits)) do
      local va, vb = visits[a], visits[b]
      if vb.leg ~= va.leg then break end
      local d = Dist(va, vb)
      if d and d < 150 then
        local far, farv = 0
        for c = a + 1, b - 1 do
          local dc = Dist(va, visits[c])
          if dc and dc > far then far, farv = dc, visits[c] end
        end
        if far > 500 then
          table.insert(out, string.format("   out and back (%.0f yd each way): %s -> %s -> %s", far, Label(va), Label(farv), Label(vb)))
          found = b
          break
        end
      end
    end
    a = found or (a + 1)
  end
end
table.insert(out, string.format("TOTAL %.0f yards (%.0f min)", grand, grand / 7 / 60))
return table.concat(out, "\n")
