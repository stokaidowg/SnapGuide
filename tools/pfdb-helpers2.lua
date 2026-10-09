-- more helpers for route work (loaded by zone dumps)

-- "Name @ x,y Zone" for the first start/end unit or object of a quest end
function Who(t)
  if not t then return "?" end
  for _, kind in ipairs({ "U", "O", "I" }) do
    for _, id in ipairs(t[kind] or {}) do
      if kind == "I" then
        return "item " .. ((IN[id]) or id)
      end
      local name = kind == "U" and UN[id] or ON[id]
      local c = Coords(kind, id)
      if c then
        return string.format("%s @%.1f,%.1f %s", tostring(name), c[1], c[2], tostring(ZN[c[3]]))
      end
      return tostring(name) .. " (no coords)"
    end
  end
  return "?"
end

-- objective summary: units/objects/items with names
function Obj(q)
  if not q.obj then return "" end
  local parts = {}
  for _, id in ipairs(q.obj.U or {}) do table.insert(parts, "kill " .. tostring(UN[id])) end
  for _, id in ipairs(q.obj.O or {}) do table.insert(parts, "use " .. tostring(ON[id])) end
  for _, id in ipairs(q.obj.I or {}) do table.insert(parts, "item " .. tostring(IN[id])) end
  for _, id in ipairs(q.obj.A or {}) do table.insert(parts, "area " .. id) end
  return table.concat(parts, ", ")
end

-- quests whose start NPC/object is in zone z, for the Alliance
function ZoneQuests(z, minLvl, maxLvl)
  local list = {}
  for qid, q in pairs(Q) do
    if type(q) == "table" and Faction(q) ~= "H" then
      local sz = StartZone(q)
      if sz == z and (not minLvl or (q.lvl or 0) >= minLvl) and (not maxLvl or (q.lvl or 0) <= maxLvl) then
        table.insert(list, qid)
      end
    end
  end
  table.sort(list, function(a, b)
    if (Q[a].lvl or 0) ~= (Q[b].lvl or 0) then return (Q[a].lvl or 0) < (Q[b].lvl or 0) end
    return a < b
  end)
  return list
end

function Describe(qid)
  local q = Q[qid]
  local pre = q.pre and table.concat(q.pre, "/") or ""
  local cls = q.class and (" class=" .. q.class) or ""
  return string.format("%5d L%2d m%2d %-4s %-38s | start %s | end %s | pre %s | next %s | %s%s",
    qid, q.lvl or 0, q.min or 0, Faction(q), QName(qid), Who(q.start), Who(q["end"]), pre, tostring(q.next or ""), Obj(q), cls)
end
