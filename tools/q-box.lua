-- NPCs standing in a box of a zone (quest givers, vendors, flight masters, innkeepers)
local out = {}
local zid
for id, n in pairs(ZN) do if string.gsub(n, "%s+$", "") == BOXZONE then zid = id end end
for id, u in pairs(U) do
  if type(u) == "table" and u.coords then
    for _, c in ipairs(u.coords) do
      if c[3] == zid and c[1] >= X1 and c[1] <= X2 and c[2] >= Y1 and c[2] <= Y2 and not (u.lvl and string.find(tostring(u.lvl), "^1%d%-") ) then
        table.insert(out, string.format("%-30s %6d @%.1f,%.1f lvl %s", tostring(UN[id]), id, c[1], c[2], tostring(u.lvl)))
        break
      end
    end
  end
end
table.sort(out)
return Join(out)
