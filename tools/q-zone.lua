local z = tonumber(ZONE)
local out = {}
for _, qid in ipairs(ZoneQuests(z)) do table.insert(out, Describe(qid)) end
return Join(out)
