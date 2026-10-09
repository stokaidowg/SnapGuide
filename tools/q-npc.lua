-- find NPCs by name fragment in a zone, with coords
local out = {}
for id, name in pairs(UN) do
  for frag in string.gmatch(FRAGS, "[^;]+") do
    if string.find(name, frag, 1, true) then
      for _, c in ipairs((U[id] and U[id].coords) or {}) do
        if not ZONEF or ZN[c[3]] == ZONEF then
          table.insert(out, string.format("%-32s %6d @%.1f,%.1f %s", name, id, c[1], c[2], tostring(ZN[c[3]])))
          break
        end
      end
    end
  end
end
table.sort(out)
return Join(out)
