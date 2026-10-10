-- Makes extra-db.lua's body: run inside a Lua state that has pfQuest + the NEWER pfQuest-turtle
-- database loaded (github.com/shagu/pfQuest-turtle, db/*.lua) with pfdb-helpers.lua applied, and
-- save what it returns under extra-db.lua's header. Add quest ids to QUESTS (and any extra NPCs
-- to units) when the server has quests pfQuest-octo doesn't.
local QUESTS = { 41749, 41750, 41751, 41754, 41756, 41893, 41846, 41850, 41851, 41852, 41853, 41854, 41855, 41856, 41857, 41858, 41862, 41863, 41864, 41865, 41866, 41867, 41868, 41869, 41870, 41871, 41872, 41873, 41874, 41875, 41876, 41877, 41878, 41879, 41880, 41881, 41882, 41883, 41884, 41885, 41886, 41800, 41801, 41802, 41803 }
local out = {}
local function ser(v)
  if type(v) == "table" then
    local keys = {}
    for k in pairs(v) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      table.insert(parts, key .. "=" .. ser(v[k]))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then
    return string.format("%q", v)
  else
    return tostring(v)
  end
end
local units, items, objects = { [62415] = true }, {}, {} -- + Krangosh Thunderwind, Dun Kithas gryphon master
for _, id in ipairs(QUESTS) do
  local q = Q[id]
  table.insert(out, "Q[" .. id .. "] = " .. ser(q))
  table.insert(out, "QN[" .. id .. "] = " .. ser(QN[id]))
  for _, k in ipairs({ "start", "end", "obj" }) do
    for _, u in ipairs((q[k] and q[k].U) or {}) do units[u] = true end
    for _, o in ipairs((q[k] and q[k].O) or {}) do objects[o] = true end
    for _, i in ipairs((q[k] and q[k].I) or {}) do items[i] = true end
  end
end
for i in pairs(items) do
  local src = I[i] or {}
  for u in pairs(src.U or {}) do units[u] = true end
  for o in pairs(src.O or {}) do objects[o] = true end
end
local function sorted(t) local l = {} for k in pairs(t) do table.insert(l, k) end table.sort(l) return l end
for _, u in ipairs(sorted(units)) do table.insert(out, "U[" .. u .. "] = " .. ser(U[u])) table.insert(out, "UN[" .. u .. "] = " .. ser(UN[u])) end
for _, o in ipairs(sorted(objects)) do table.insert(out, "O[" .. o .. "] = " .. ser(O[o])) table.insert(out, "ON[" .. o .. "] = " .. ser(ON[o])) end
for _, i in ipairs(sorted(items)) do table.insert(out, "I[" .. i .. "] = " .. ser(I[i])) table.insert(out, "IN[" .. i .. "] = " .. ser(IN[i])) end
local triggers = {}
for _, id in ipairs(QUESTS) do for _, a in ipairs((Q[id].obj and Q[id].obj.A) or {}) do triggers[a] = true end end
for _, a in ipairs(sorted(triggers)) do table.insert(out, "pfDB.areatrigger.data[" .. a .. "] = " .. ser(pfDB.areatrigger.data[a])) end
table.insert(out, "ZN[5601] = " .. ser(ZN[5601]))
table.insert(out, "ZN[5602] = " .. ser(ZN[5602]))
return table.concat(out, "\n")
