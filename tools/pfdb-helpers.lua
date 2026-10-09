table.getn = table.getn or function(t) return #t end
string.gfind = string.gfind or string.gmatch
-- Applies the Octo patches the way pfQuest-octo's patchtable.lua does, and defines helpers.
local function patch(base, diff)
  for k, v in pairs(diff) do
    if v == "_" then base[k] = nil else base[k] = v end
  end
end
for _, db in ipairs({ "quests", "units", "objects", "items", "areatrigger" }) do
  if rawget(pfDB[db], "data-turtle") then patch(pfDB[db].data, pfDB[db]["data-turtle"]) end
  if rawget(pfDB[db], "enUS-turtle") then patch(pfDB[db].enUS, pfDB[db]["enUS-turtle"]) end
end
patch(pfDB.zones.enUS, pfDB.zones["enUS-turtle"])

Q, U, O, I = pfDB.quests.data, pfDB.units.data, pfDB.objects.data, pfDB.items.data
QN, UN, ON, IN, ZN = pfDB.quests.enUS, pfDB.units.enUS, pfDB.objects.enUS, pfDB.items.enUS, pfDB.zones.enUS

local function has(r, bits)
  for _, b in ipairs(bits) do
    if math.floor(r / b) % 2 == 1 then return true end
  end
end
ALLYBITS, HORDEBITS = { 1, 4, 8, 64, 512 }, { 2, 16, 32, 128, 256 }

-- "A", "H" or "both" for a quest's race mask
function Faction(q)
  if not q.race or q.race == 0 then return "both" end
  local a, h = has(q.race, ALLYBITS), has(q.race, HORDEBITS)
  return (a and h) and "both" or a and "A" or h and "H" or "?"
end

function QName(id)
  return QN[id] and QN[id].T or ("quest " .. id)
end

-- first coords { x, y, zone } of a unit/object id
function Coords(kind, id)
  local e = (kind == "U" and U or O)[id]
  if e and e.coords and e.coords[1] then
    return e.coords[1]
  end
end

-- zone of a quest's start NPC/object
function StartZone(q)
  if not q or not q.start then return nil end
  for _, kind in ipairs({ "U", "O" }) do
    for _, id in ipairs(q.start[kind] or {}) do
      local c = Coords(kind, id)
      if c then return c[3], c end
    end
  end
end

function Join(t, sep)
  return table.concat(t, sep or "\n")
end
