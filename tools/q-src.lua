local out = {}
for qid in string.gmatch(QIDS, "%d+") do
  local q = Q[tonumber(qid)]
  table.insert(out, "quest " .. qid .. " " .. QName(tonumber(qid)))
  for _, item in ipairs((q.obj and q.obj.I) or {}) do
    local src = I[item] or {}
    table.insert(out, "  item " .. tostring(IN[item]) .. " (" .. item .. ")")
    for uid, ch in pairs(src.U or {}) do
      local cells = {}
      for _, c in ipairs((U[uid] and U[uid].coords) or {}) do
        local k = ZN[c[3]] .. " " .. math.floor(c[1] / 10) * 10 .. "," .. math.floor(c[2] / 10) * 10
        cells[k] = (cells[k] or 0) + 1
      end
      local cs = {}
      for k, n in pairs(cells) do table.insert(cs, k .. "x" .. n) end
      table.sort(cs)
      table.insert(out, string.format("    %5.1f%% %s: %s", ch, tostring(UN[uid]), table.concat(cs, "  ")))
    end
    for oid, ch in pairs(src.O or {}) do table.insert(out, "    obj " .. tostring(Name and ON[oid]) .. " " .. ch) end
  end
end
return Join(out)
