// Loads pfQuest + pfQuest-octo databases (with the Octo patches applied) into a fengari Lua
// state. Usage: const { lua } = require('./pfdb'); lua(`return ...`) -> string result.
// Query files are plain Lua run after the DB loads; helpers below are defined as globals.
const fs = require('fs');
const { lua: L_, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(code, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name)) !== L_.LUA_OK ||
      L_.lua_pcall(L, 0, 1, 0) !== L_.LUA_OK) {
    throw new Error(name + ': ' + L_.lua_tojsstring(L, -1));
  }
  const s = L_.lua_type(L, -1) === L_.LUA_TSTRING ? L_.lua_tojsstring(L, -1) : null;
  L_.lua_pop(L, 1);
  return s;
}

const ADD = 'H:/Games/OctoWoW/Interface/AddOns/';
run(`pfDB = setmetatable({}, { __index = function(t, k) local v = {} rawset(t, k, v) return v end })`, 'init');
for (const f of [
  'pfQuest/db/quests.lua', 'pfQuest/db/units.lua', 'pfQuest/db/objects.lua', 'pfQuest/db/items.lua',
  'pfQuest/db/enUS/quests.lua', 'pfQuest/db/enUS/zones.lua', 'pfQuest/db/enUS/units.lua',
  'pfQuest/db/enUS/objects.lua', 'pfQuest/db/enUS/items.lua',
  'pfQuest-octo/db/quests-turtle.lua', 'pfQuest-octo/db/units-turtle.lua', 'pfQuest-octo/db/objects-turtle.lua',
  'pfQuest-octo/db/items-turtle.lua', 'pfQuest/db/areatrigger.lua', 'pfQuest-octo/db/areatrigger-turtle.lua',
  'pfQuest-octo/db/enUS/quests-turtle.lua', 'pfQuest-octo/db/enUS/zones-turtle.lua', 'pfQuest-octo/db/enUS/units-turtle.lua',
  'pfQuest-octo/db/enUS/objects-turtle.lua', 'pfQuest-octo/db/enUS/items-turtle.lua',
]) {
  run(fs.readFileSync(ADD + f, 'utf8'), f);
}
run(fs.readFileSync(__dirname + '/pfdb-helpers.lua', 'utf8'), 'helpers');
run(fs.readFileSync(__dirname + '/pfdb-helpers2.lua', 'utf8'), 'helpers2');
// quests the server has that the database doesn't yet (see the file)
run(fs.readFileSync(__dirname + '/extra-db.lua', 'utf8'), 'extra-db');

module.exports = { lua: (code) => run(code, 'query') };

if (require.main === module) {
  // node pfdb.js query.lua
  console.log(run(fs.readFileSync(process.argv[2], 'utf8'), process.argv[2]));
}
