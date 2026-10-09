// node paths.js [--png leg] : walking paths for every route leg where a straight line is
// blocked (cliffs, mountains, deep gorges), found on the client's own terrain (terrain.js),
// written to ../Paths.lua. The arrow follows a step's path points before the step itself.
//
// A leg runs from the last step with coordinates to the next one. Flights and hearths start
// a new leg; legs between continents (boats) are skipped. Paths are keyed by step and carry
// the step's spot, so a rebuilt route never follows a path meant for another step: rerun
// this after build.js.
const fs = require("fs");
const path = require("path");
const T = require("./terrain");

const ROOT = path.join(__dirname, "..");
const MIN_LEG = 80; // yards: shorter legs are walked by eye
const NEAR_ENOUGH = 250; // yards: a spot the search can't reach (a cave) gets a path this close
// cities are mostly indoors (the ground there means nothing), and these R steps are rides
const CITIES = new Set(["Stormwind City", "Ironforge", "Darnassus", "Undercity", "Orgrimmar", "Thunder Bluff"]);
const RIDE = /tram|boat|ship|zeppelin|portal|teleport/i;
const SNAP = 8; // grid points searched around a spot that sits on a slope or in a building

// [[ zones ]] -- name -> { continent, left, right, top, bottom } (zones.lua)
const ZONES = {};
for (const m of fs.readFileSync(path.join(ROOT, "zones.lua"), "utf8").matchAll(/\["([^"]+)"\]\s*=\s*\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}/g)) {
  ZONES[m[1]] = [m[2], m[3], m[4], m[5], m[6]].map(Number);
}
function World(z, x, y) {
  const b = ZONES[z];
  if (!b) return null;
  return { c: b[0], z, x: b[3] - y / 100 * (b[3] - b[4]), y: b[1] - x / 100 * (b[1] - b[2]) };
}

// [[ routes ]] -- the built files: one step per line, in order
function Steps(file) {
  const out = [];
  let inSteps = false;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (/^\s*steps\s*=\s*\{/.test(line)) { inSteps = true; continue; }
    if (!inSteps || !/^\s*\{a="/.test(line)) continue;
    const g = (k) => { const m = line.match(new RegExp("[{,]" + k + "=(\"[^\"]*\"|[-\\d.]+)")); return m ? (m[1][0] === '"' ? m[1].slice(1, -1) : Number(m[1])) : undefined; };
    out.push({ i: out.length + 1, a: g("a"), t: g("t"), x: g("x"), y: g("y"), z: g("z") });
  }
  return out;
}

// [[ search ]] --
const continents = {};
function Land(c) {
  if (!continents[c]) {
    const t0 = Date.now();
    continents[c] = T.Continent(c === 0 ? "Azeroth" : "Kalimdor");
    console.log(`  (terrain ${c === 0 ? "Eastern Kingdoms" : "Kalimdor"}: ${continents[c].tiles} tiles, ${Date.now() - t0} ms)`);
  }
  return continents[c];
}

const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

// a grid point near (gx, gy) you can actually stand on and leave
function Snap(L, gx, gy) {
  gx = Math.round(gx); gy = Math.round(gy);
  let best = null, bestD = Infinity;
  for (let dy = -SNAP; dy <= SNAP; dy++) for (let dx = -SNAP; dx <= SNAP; dx++) {
    const d = dx * dx + dy * dy;
    if (d >= bestD) continue;
    let ok = 0;
    for (const [ex, ey] of DIRS) if (T.Step(L, gx + dx, gy + dy, gx + dx + ex, gy + dy + ey)) ok++;
    if (ok >= 3) { best = [gx + dx, gy + dy]; bestD = d; }
  }
  return best;
}

// A* over the grid inside a box around both ends
function AStar(L, a, b, margin) {
  const m = Math.ceil(margin / T.UNIT);
  const x0 = Math.min(a[0], b[0]) - m, y0 = Math.min(a[1], b[1]) - m;
  const w = Math.abs(a[0] - b[0]) + 2 * m + 1, h = Math.abs(a[1] - b[1]) + 2 * m + 1;
  const n = w * h;
  const g = new Float32Array(n).fill(Infinity), came = new Int32Array(n).fill(-1), closed = new Uint8Array(n);
  const id = (x, y) => (y - y0) * w + (x - x0);
  const H = (x, y) => { const dx = Math.abs(x - b[0]), dy = Math.abs(y - b[1]); return (dx + dy) + (Math.SQRT2 - 2) * Math.min(dx, dy); };
  // binary heap of [f, index]
  const hf = [], hi = [];
  const push = (f, i) => {
    let k = hf.length; hf.push(f); hi.push(i);
    while (k > 0) { const p = (k - 1) >> 1; if (hf[p] <= hf[k]) break; [hf[p], hf[k]] = [hf[k], hf[p]]; [hi[p], hi[k]] = [hi[k], hi[p]]; k = p; }
  };
  const pop = () => {
    const top = hi[0], lf = hf.pop(), li = hi.pop();
    if (hf.length) {
      hf[0] = lf; hi[0] = li;
      let k = 0;
      for (;;) {
        const l = 2 * k + 1, r = l + 1; let s = k;
        if (l < hf.length && hf[l] < hf[s]) s = l;
        if (r < hf.length && hf[r] < hf[s]) s = r;
        if (s === k) break;
        [hf[s], hf[k]] = [hf[k], hf[s]]; [hi[s], hi[k]] = [hi[k], hi[s]]; k = s;
      }
    }
    return top;
  };
  // stay a few yards off cliff edges: a point next to a blocked one costs more
  const blocked = new Uint8Array(n), near = new Uint8Array(n); // 0 unknown, 1 no, 2 yes
  const Blocked = (x, y) => {
    if (x < x0 || y < y0 || x >= x0 + w || y >= y0 + h) return false;
    const k = id(x, y);
    if (!blocked[k]) {
      let b = false;
      for (const [dx, dy] of DIRS.slice(0, 4)) if (!T.Step(L, x, y, x + dx, y + dy)) { b = true; break; }
      blocked[k] = b ? 2 : 1;
    }
    return blocked[k] === 2;
  };
  const Near = (x, y, k) => {
    if (!near[k]) {
      let b = false;
      for (let dy = -2; dy <= 2 && !b; dy++) for (let dx = -2; dx <= 2; dx++) if (Blocked(x + dx, y + dy)) { b = true; break; }
      near[k] = b ? 2 : 1;
    }
    return near[k] === 2;
  };
  const start = id(a[0], a[1]), goal = id(b[0], b[1]);
  g[start] = 0;
  push(H(a[0], a[1]), start);
  while (hf.length) {
    const cur = pop();
    if (closed[cur]) continue;
    if (cur === goal) break;
    closed[cur] = 1;
    const cx = cur % w + x0, cy = Math.floor(cur / w) + y0;
    for (const [dx, dy] of DIRS) {
      const nx = cx + dx, ny = cy + dy;
      if (nx < x0 || ny < y0 || nx >= x0 + w || ny >= y0 + h) continue;
      const ni = id(nx, ny);
      if (closed[ni]) continue;
      const cost = T.Step(L, cx, cy, nx, ny);
      if (!cost) continue;
      const ng = g[cur] + cost * (dx && dy ? Math.SQRT2 : 1) * (Near(nx, ny, ni) ? 1.6 : 1);
      if (ng < g[ni]) { g[ni] = ng; came[ni] = cur; push(ng + H(nx, ny), ni); }
    }
  }
  if (came[goal] < 0 && goal !== start) return null;
  const out = [];
  for (let k = goal; k >= 0; k = came[k]) out.push([k % w + x0, Math.floor(k / w) + y0]);
  return out.reverse();
}

// the reachable point (from a) closest to b
function Closest(L, a, b, margin) {
  const m = Math.ceil(margin / T.UNIT);
  const x0 = Math.min(a[0], b[0]) - m, y0 = Math.min(a[1], b[1]) - m, x1 = Math.max(a[0], b[0]) + m, y1 = Math.max(a[1], b[1]) + m;
  const w = x1 - x0 + 1, seen = new Uint8Array(w * (y1 - y0 + 1)), q = [a];
  seen[(a[1] - y0) * w + a[0] - x0] = 1;
  let best = a, bestD = Infinity;
  while (q.length) {
    const [x, y] = q.pop();
    const d = (x - b[0]) ** 2 + (y - b[1]) ** 2;
    if (d < bestD) { bestD = d; best = [x, y]; }
    for (const [dx, dy] of DIRS) {
      const nx = x + dx, ny = y + dy;
      if (nx < x0 || ny < y0 || nx > x1 || ny > y1 || seen[(ny - y0) * w + nx - x0]) continue;
      if (!T.Step(L, x, y, nx, ny)) continue;
      seen[(ny - y0) * w + nx - x0] = 1;
      q.push([nx, ny]);
    }
  }
  return best;
}

// can you walk straight from p to q? (every grid point along the line, step by step)
function Clear(L, p, q) {
  const steps = Math.ceil(Math.max(Math.abs(q[0] - p[0]), Math.abs(q[1] - p[1])) * 2);
  let px = Math.round(p[0]), py = Math.round(p[1]);
  for (let s = 1; s <= steps; s++) {
    const x = Math.round(p[0] + (q[0] - p[0]) * s / steps), y = Math.round(p[1] + (q[1] - p[1]) * s / steps);
    if (x === px && y === py) continue;
    // a diagonal move also needs one of its two straight neighbours, so lines don't slip
    // through the corner between two blocked points
    if (!T.Step(L, px, py, x, y)) return false;
    if (x !== px && y !== py && !T.Step(L, px, py, x, py) && !T.Step(L, px, py, px, y)) return false;
    px = x; py = y;
  }
  return true;
}

// the A* path cut down to the corners you have to turn at
function Corners(L, raw) {
  const out = [raw[0]];
  let i = 0;
  while (i < raw.length - 1) {
    let j = i + 1;
    while (j + 1 < raw.length && Clear(L, raw[i], raw[j + 1])) j++;
    out.push(raw[j]);
    i = j;
  }
  return out;
}

const dist = (p, q) => Math.hypot(p[0] - q[0], p[1] - q[1]) * T.UNIT;

// drop corners that are within TOLERANCE yards of the line between their neighbours
// (Douglas-Peucker): the arrow only needs the real turns
const TOLERANCE = 15;
function Thin(pts) {
  if (pts.length <= 2) return pts;
  let worst = 0, at = 0;
  for (let k = 1; k < pts.length - 1; k++) {
    const d = Deviation([pts[k]], pts[0], pts[pts.length - 1]);
    if (d > worst) { worst = d; at = k; }
  }
  if (worst < TOLERANCE) return [pts[0], pts[pts.length - 1]];
  return Thin(pts.slice(0, at + 1)).slice(0, -1).concat(Thin(pts.slice(at)));
}
function Length(pts) { let s = 0; for (let k = 1; k < pts.length; k++) s += dist(pts[k - 1], pts[k]); return s; }
function Deviation(pts, a, b) {
  let worst = 0;
  const L2 = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2;
  for (const p of pts) {
    const t = L2 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * (b[0] - a[0]) + (p[1] - a[1]) * (b[1] - a[1])) / L2)) : 0;
    worst = Math.max(worst, dist(p, [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]));
  }
  return worst;
}

// a path for one leg: { via: [[gx, gy], ...] } (empty when walking straight is fine), or { fail }
function Leg(L, from, to) {
  const ga = T.ToGrid(from.x, from.y), gb = T.ToGrid(to.x, to.y);
  const a = Snap(L, ga[0], ga[1]), b = Snap(L, gb[0], gb[1]);
  if (!a || !b) return { fail: !a ? "start isn't on walkable ground" : "end isn't on walkable ground" };
  if (Clear(L, a, b)) return { via: [] };
  let raw = AStar(L, a, b, 400);
  if (!raw) raw = AStar(L, a, b, 1600);
  if (!raw) {
    // walled in (a cave, a ledge): get as close as the ground allows, then straight on
    const c = Closest(L, a, b, 1600);
    if (c && dist(c, b) <= NEAR_ENOUGH) raw = AStar(L, a, c, 400) || AStar(L, a, c, 1600);
    if (!raw) return { fail: "no walkable way found" };
    raw.push(b);
  }
  const corners = Thin(Corners(L, raw));
  const straight = dist(a, b), walked = Length(corners);
  // a small bump in the way: the straight arrow is good enough
  if (walked < straight * 1.06 && Deviation(corners, a, b) < 45) return { via: [], walked, straight };
  return { via: corners.slice(1, -1), walked, straight, raw, a, b };
}

// [[ main ]] --
const args = process.argv.slice(2);
const pngLeg = args[0] === "--png" ? args[1] : null;
const order = fs.readFileSync(path.join(__dirname, "route", "order.txt"), "utf8").split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith("#"));
const lines = ["-- generated by tools/paths.js from the client's terrain: walking paths around cliffs,",
  "-- mountains and gorges. [\"route:step\"] = { to = \"zone:x,y\" (the step it was made for, to 2 decimals),",
  "-- then the points to walk through in order, as world yards north, west, north, west, ... }",
  "SnapGuide.paths = {"];
let legs = 0, routed = 0, failed = 0;
const t0 = Date.now();
for (const name of order) {
  const steps = Steps(path.join(ROOT, "Routes", name + ".lua"));
  let last = null, notes = [];
  for (const s of steps) {
    const here = s.x !== undefined && s.z ? World(s.z, s.x, s.y) : null;
    if (s.a === "F" || s.a === "H") { last = here; continue; }
    if (!here) continue;
    if (last && last.c === here.c && !CITIES.has(s.z) && !CITIES.has(last.z) && Math.hypot(last.x - here.x, last.y - here.y) >= MIN_LEG) {
      legs++;
      const L = Land(here.c);
      const r = Leg(L, last, here);
      const key = `${name}:${s.i}`;
      if (r.fail) {
        failed++;
        notes.push(`  ${key} ${s.t}: ${r.fail}`);
        if (pngLeg === key) Unreachable(L, last, here, key);
      } else if (r.via.length) {
        routed++;
        const pts = [];
        for (const p of r.via) { const [wx, wy] = T.ToWorld(p[0], p[1]); pts.push(Math.round(wx), Math.round(wy)); }
        lines.push(`  ["${key}"] = { to = "${s.z}:${s.x.toFixed(2)},${s.y.toFixed(2)}", ${pts.join(", ")} },`);
        notes.push(`  ${key} ${s.t}: ${r.via.length} points, ${Math.round(r.walked)} yd walked vs ${Math.round(r.straight)} straight`);
        if (pngLeg === key) Picture(L, r, key);
      }
    }
    // after a ride the next leg starts wherever it drops you
    last = s.a === "R" && RIDE.test(s.t || "") ? null : here;
  }
  console.log(name + (notes.length ? "\n" + notes.join("\n") : ": every leg is a straight walk"));
}
lines.push("}");
fs.writeFileSync(path.join(ROOT, "Paths.lua"), lines.join("\n") + "\n");
console.log(`${legs} legs, ${routed} need a path, ${failed} couldn't be routed (straight arrow there), ${Math.round((Date.now() - t0) / 1000)} s`);

// --png route:step : the leg drawn over the terrain (dark = too steep, blue = water,
// yellow = building/bridge/gap, red = the search path, white = the corners kept)
function Picture(L, r, key) {
  const { PNG } = require("./png");
  const pts = r.raw;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const p of pts) { x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]); }
  x0 -= 60; y0 -= 60; x1 += 60; y1 += 60;
  const w = x1 - x0 + 1, h = y1 - y0 + 1, rgb = new Uint8Array(w * h * 3);
  const set = (x, y, c) => { if (x < x0 || y < y0 || x > x1 || y > y1) return; const i = ((y - y0) * w + (x - x0)) * 3; rgb[i] = c[0]; rgb[i + 1] = c[1]; rgb[i + 2] = c[2]; };
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const f = L.Flags(x, y), ht = L.Height(x, y);
    let ok = 0; for (const [dx, dy] of DIRS.slice(0, 4)) if (T.Step(L, x, y, x + dx, y + dy)) ok++;
    const sh = Math.max(60, Math.min(230, 100 + ht / 2));
    set(x, y, !(ht === ht) ? [0, 0, 0] : f & T.DEADLY ? [255, 60, 0] : f & T.WATER ? [40, 90, 200] : f & T.FREE ? [230, 200, 60] : ok < 4 ? [25, 25, 25] : [sh * 0.55, sh, sh * 0.5]);
  }
  for (const p of pts) set(p[0], p[1], [255, 40, 40]);
  for (const p of [r.a, ...r.via, r.b]) for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(p[0] + dx, p[1] + dy, [255, 255, 255]);
  const out = path.join(__dirname, "path-" + key.replace(/[^A-Za-z0-9]/g, "_") + ".png");
  fs.writeFileSync(out, PNG(w, h, rgb));
  console.log("  picture: " + out);
}

// --png on a leg that failed: what can be reached from each end (green from the start,
// purple from the end) over the terrain, to see what walls one of them in
function Unreachable(L, from, to, key) {
  const { PNG } = require("./png");
  const a = Snap(L, ...T.ToGrid(from.x, from.y)), b = Snap(L, ...T.ToGrid(to.x, to.y));
  if (!a || !b) { console.log("  (an end has no walkable ground nearby)"); return; }
  const m = 150;
  const x0 = Math.min(a[0], b[0]) - m, y0 = Math.min(a[1], b[1]) - m, x1 = Math.max(a[0], b[0]) + m, y1 = Math.max(a[1], b[1]) + m;
  const w = x1 - x0 + 1, h = y1 - y0 + 1;
  const flood = (p) => {
    const seen = new Uint8Array(w * h), q = [p];
    seen[(p[1] - y0) * w + p[0] - x0] = 1;
    while (q.length) {
      const [x, y] = q.pop();
      for (const [dx, dy] of DIRS) {
        const nx = x + dx, ny = y + dy;
        if (nx < x0 || ny < y0 || nx > x1 || ny > y1 || seen[(ny - y0) * w + nx - x0]) continue;
        if (!T.Step(L, x, y, nx, ny)) continue;
        seen[(ny - y0) * w + nx - x0] = 1; q.push([nx, ny]);
      }
    }
    return seen;
  };
  const fa = flood(a), fb = flood(b), rgb = new Uint8Array(w * h * 3);
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const i = (y - y0) * w + x - x0, f = L.Flags(x, y);
    let c = f & T.WATER ? [40, 90, 200] : f & T.FREE ? [230, 200, 60] : [30, 30, 30];
    if (fa[i]) c = [70, 190, 70];
    if (fb[i]) c = fa[i] ? [255, 255, 255] : [170, 80, 200];
    rgb.set(c, i * 3);
  }
  for (const p of [a, b]) for (let dy = -3; dy <= 3; dy++) for (let dx = -3; dx <= 3; dx++) {
    const x = p[0] + dx, y = p[1] + dy; if (x >= x0 && y >= y0 && x <= x1 && y <= y1) rgb.set([255, 0, 0], ((y - y0) * w + x - x0) * 3);
  }
  const out = path.join(__dirname, "path-" + key.replace(/[^A-Za-z0-9]/g, "_") + ".png");
  fs.writeFileSync(out, PNG(w, h, rgb));
  console.log("  picture: " + out);
}
