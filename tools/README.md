# SnapGuide route tools

Not loaded by the game (they're not in the .toc). These build `Routes\*.lua` from the route
scripts in `route\`, checked against the pfQuest + pfQuest-octo database.

Setup (once): `npm install fengari@0.1.4` in this folder (a Lua VM for Node).

- `node build.js ..\Routes` - build every route in `route\order.txt` into the add-on and rewrite
  `SnapGuide.toc`. Prints each route's step count, quest log size, simulated level at the end,
  and warnings (missing pre-quests, quests too high for you, quest log over 20, no coordinates).
- `node zone.js <zoneId>` - every Alliance quest in a zone with givers, chains and objectives.
- `route-build.lua` documents the route script format at the top.

The level simulation starts from `START <level> <xp>` in the first route and estimates XP from
quests and kills (scaled 1.25x for kills on the way and discovery XP).
Every step gets `el` (the level you'd be there). Pickups also get `sk` (the quest's worth in
levels) and `ql` when the add-on may skip them for players ahead of the route: not when another
Alliance quest anywhere in the DB needs the quest first (chains used later), not class quests,
and not ones flagged `@keep` in the route script.
- `node overlap.js` - quests in each built route that could be done at the same time (shared mobs
  or spawns in the same area). Pairs already marked `@together` show as "(together)"; the rest
  are either chains (the second needs the first turned in) or worth a look.
- `node paths.js` - walking paths round cliffs, mountains and gorges for every route leg where a
  straight line is blocked, written to `..\Paths.lua` (loaded via `toc-head.txt`). Reads the
  client's own terrain from the MPQs (`terrain.js`, through `mpq.js`): ground heights, water,
  lava, and the floors of buildings, bridges and tunnels. Searches it with A* and keeps only
  the corners you have to turn at. Run it after `build.js`: in game, a path made for a step
  whose coordinates changed is ignored. `--png route:step` draws one leg over the terrain
  (dark = too steep, blue = water, yellow = floors; for a leg it couldn't route, what each end
  can reach). Legs in cities and after trams/boats are skipped (indoors / rides). No npm
  packages needed.
- `node travel.js` - straight-line walking estimate per built route (hearths and flights reset
  your position), its five longest legs, and "out and back" trips that walk somewhere and return
  to the same spot. Use it before/after reordering a route to see whether it helped.
