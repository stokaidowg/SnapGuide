local out = {}
for a, b in string.gmatch(RANGES, "(%d+)%-(%d+)") do
  for qid = tonumber(a), tonumber(b) do
    if Q[qid] and Faction(Q[qid]) ~= "H" then table.insert(out, Describe(qid)) end
  end
end
return Join(out)
