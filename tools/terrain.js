// Walkable ground for a continent, read from the client's own map tiles (ADT files in the
// MPQs, OctoWoW's patched ones first). Used by paths.js to route around cliffs and water.
//
// The world is a grid of 64 x 64 tiles of 533.33 yards; every tile has 16 x 16 chunks with
// 9 x 9 height points each, so the grid here has a point every 4.17 yards. World coordinates
// are the client's: X grows north, Y grows west (the same as zones.lua).
//
// Per point: height, and flags
//   WATER  deep enough to swim       DEADLY lava or slime
//   FREE   a gap in the ground (a cave or tunnel mouth) or inside a building / bridge box:
//          the ground there says nothing, so it's treated as passable
//   SMOOTH part of a small steep patch (a rock, a mound) that you just walk round
//   STEEP  (on the square whose top-left corner this point is) STEEP_TRIS or more of the
//          square's four ground triangles (corners + the centre height) are too steep to walk
const { Archives } = require("./mpq");

const TILE = 1600 / 3; // 533.333 yards
const UNIT = TILE / 128; // 4.1667 yards between height points
const ORIGIN = 32 * TILE;
const N = 64 * 128; // grid points along each side of the map
const WATER = 1, DEADLY = 2, FREE = 4, SMOOTH = 8, STEEP = 16;
// ground steeper than ANGLE can't be walked up; a square is blocked when STEEP_TRIS of its four
// triangles are (2 walled off ramps up Raptor Ridge and the like; 55 degrees changed nothing)
const ANGLE = 50, STEEP_TRIS = 3;
const MIN_UP = Math.cos(ANGLE * Math.PI / 180);
const SPECK = 40; // steep patches up to this many points (about 700 square yards) count as flat
const MAX_SLOPE = Math.tan(ANGLE * Math.PI / 180);

// grid column (east-west, growing east) and row (growing south) of a world spot
function ToGrid(x, y) {
  return [(ORIGIN - y) / UNIT, (ORIGIN - x) / UNIT];
}
function ToWorld(gx, gy) {
  return [ORIGIN - gy * UNIT, ORIGIN - gx * UNIT];
}

// the walkable (flat enough) triangles of a building model, in its own coordinates
const floorCache = new Map();
function Floors(mpq, name) {
  if (floorCache.has(name)) return floorCache.get(name);
  const tris = [];
  const root = name && mpq.get(name);
  let groups = 0;
  if (root) chunks(root, 0, root.length, (m, p) => { if (m === "MOHD") groups = root.readUInt32LE(p + 4); });
  for (let g = 0; g < groups; g++) {
    const gf = mpq.get(name.replace(/.wmo$/i, "_" + String(g).padStart(3, "0") + ".wmo"));
    if (!gf) continue;
    chunks(gf, 0, gf.length, (m, p, size) => {
      if (m !== "MOGP") return;
      let vt = null, ix = null;
      chunks(gf, p + 0x44, p + size, (m2, p2, s2) => {
        if (m2 === "MOVT") vt = [p2, s2];
        if (m2 === "MOVI") ix = [p2, s2];
      });
      if (!vt || !ix) return;
      const V = (i) => { const o = vt[0] + i * 12; return [gf.readFloatLE(o), gf.readFloatLE(o + 4), gf.readFloatLE(o + 8)]; };
      for (let o = ix[0]; o + 6 <= ix[0] + ix[1]; o += 6) {
        const a = V(gf.readUInt16LE(o)), b = V(gf.readUInt16LE(o + 2)), c = V(gf.readUInt16LE(o + 4));
        const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2], vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
        const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        const len = Math.hypot(nx, ny, nz);
        if (len > 0 && Math.abs(nz) / len >= 0.7) tris.push([a, b, c]);
      }
    });
  }
  floorCache.set(name, tris);
  return tris;
}

function chunks(buf, start, end, fn) {
  end = Math.min(end, buf.length);
  let p = start;
  while (p + 8 <= end) {
    const magic = buf.toString("latin1", p, p + 4).split("").reverse().join("");
    const size = buf.readUInt32LE(p + 4);
    fn(magic, p + 8, size);
    p += 8 + size;
  }
}

function Continent(map, dataDir) {
  const mpq = Archives(dataDir || "H:/Games/OctoWoW/Data");
  const tiles = new Map(); // ty * 64 + tx -> { h: Float32Array, f: Uint8Array }
  const wmos = [];

  function Tile(tx, ty, make) {
    const k = ty * 64 + tx;
    let t = tiles.get(k);
    if (!t && make) {
      t = { h: new Float32Array(128 * 128).fill(NaN), f: new Uint8Array(128 * 128) };
      tiles.set(k, t);
    }
    return t;
  }
  function Index(gx, gy, make) {
    if (gx < 0 || gy < 0 || gx >= N || gy >= N) return null;
    const t = Tile(gx >> 7, gy >> 7, make);
    return t ? [t, (gy & 127) * 128 + (gx & 127)] : null;
  }

  // which tiles exist (WDT MAIN: 64 x 64 entries, flag 1 = has an ADT)
  const wdt = mpq.get(`World/Maps/${map}/${map}.wdt`);
  if (!wdt) throw new Error("no WDT for " + map);
  const present = [];
  chunks(wdt, 0, wdt.length, (magic, p) => {
    if (magic !== "MAIN") return;
    for (let i = 0; i < 4096; i++) if (wdt.readUInt32LE(p + i * 8) & 1) present.push(i);
  });

  for (const i of present) {
    // WDT index is y * 64 + x; the ADT file is named map_x_y
    const tx = i % 64, ty = Math.floor(i / 64);
    const adt = mpq.get(`World/Maps/${map}/${map}_${tx}_${ty}.adt`);
    if (!adt) continue;
    let mwmo = null;
    const mwid = [];
    chunks(adt, 0, adt.length, (magic, p, size) => {
      if (magic === "MWMO") {
        mwmo = adt.subarray(p, p + size);
      } else if (magic === "MWID") {
        for (let o = p; o < p + size; o += 4) mwid.push(adt.readUInt32LE(o));
      } else if (magic === "MODF") {
        for (let o = p; o + 64 <= p + size; o += 64) {
          const off = mwid[adt.readUInt32LE(o)];
          let e = off;
          while (mwmo && mwmo[e]) e++;
          wmos.push({
            id: adt.readUInt32LE(o + 4), name: mwmo ? mwmo.toString("latin1", off, e) : "",
            pos: [adt.readFloatLE(o + 8), adt.readFloatLE(o + 12), adt.readFloatLE(o + 16)], yaw: adt.readFloatLE(o + 24),
          });
        }
      } else if (magic === "MCNK") {
        const c = p - 8; // offsets in the header count from the chunk's magic
        const flags = adt.readUInt32LE(p);
        const ofsHeight = adt.readUInt32LE(p + 20);
        const holes = adt.readUInt16LE(p + 60);
        const ofsLiquid = adt.readUInt32LE(p + 96), sizeLiquid = adt.readUInt32LE(p + 100);
        const px = adt.readFloatLE(p + 104), py = adt.readFloatLE(p + 108), pz = adt.readFloatLE(p + 112);
        const [gx0, gy0] = ToGrid(px, py).map(Math.round);
        const hb = c + ofsHeight + 8;
        const H = (r, col) => pz + adt.readFloatLE(hb + (r * 17 + col) * 4);
        for (let r = 0; r < 9; r++) {
          for (let col = 0; col < 9; col++) {
            const at = Index(gx0 + col, gy0 + r, true);
            if (at) at[0].h[at[1]] = H(r, col);
          }
        }
        // each square: four triangles from its corners to its centre point
        const U = UNIT, M = UNIT / 2;
        const up = (ax, ay, az, bx, by, bz, cx, cy, cz) => {
          const ux = bx - ax, uy = by - ay, uz = bz - az, vx = cx - ax, vy = cy - ay, vz = cz - az;
          const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
          return Math.abs(nz) / Math.hypot(nx, ny, nz);
        };
        for (let r = 0; r < 8; r++) {
          for (let col = 0; col < 8; col++) {
            const a = H(r, col), b = H(r, col + 1), d = H(r + 1, col), e = H(r + 1, col + 1);
            const m = pz + adt.readFloatLE(hb + (r * 17 + 9 + col) * 4);
            let steep = 0;
            if (up(0, 0, a, U, 0, b, M, M, m) < MIN_UP) steep++;
            if (up(U, 0, b, U, U, e, M, M, m) < MIN_UP) steep++;
            if (up(U, U, e, 0, U, d, M, M, m) < MIN_UP) steep++;
            if (up(0, U, d, 0, 0, a, M, M, m) < MIN_UP) steep++;
            if (steep >= STEEP_TRIS) {
              const at = Index(gx0 + col, gy0 + r, true);
              if (at) at[0].f[at[1]] |= STEEP;
            }
          }
        }
        // a gap: 4 x 4 holes, each 2 x 2 cells
        if (holes) {
          for (let b = 0; b < 16; b++) {
            if (!(holes & (1 << b))) continue;
            const hr = (b >> 2) * 2, hc = (b & 3) * 2;
            for (let r = hr; r <= hr + 2; r++) for (let col = hc; col <= hc + 2; col++) {
              const at = Index(gx0 + col, gy0 + r, true);
              if (at) at[0].f[at[1]] |= FREE;
            }
          }
        }
        // liquid (vanilla MCLQ): min, max, 9 x 9 points of { data, height }, 8 x 8 tile flags
        const kind = flags & 0x3c; // 4 river, 8 ocean, 16 magma, 32 slime
        if (kind && ofsLiquid && sizeLiquid > 8) {
          const lb = c + ofsLiquid + 8;
          const deadly = kind & 0x30;
          for (let r = 0; r < 8; r++) for (let col = 0; col < 8; col++) {
            if ((adt[lb + 8 + 81 * 8 + r * 8 + col] & 0x0f) === 0x0f) continue;
            for (const [dr, dc] of [[0, 0], [0, 1], [1, 0], [1, 1]]) {
              const lh = adt.readFloatLE(lb + 8 + ((r + dr) * 9 + col + dc) * 8 + 4);
              const depth = lh - H(r + dr, col + dc);
              const at = Index(gx0 + col + dc, gy0 + r + dr, true);
              if (!at) continue;
              if (deadly && depth > 0) at[0].f[at[1]] |= DEADLY;
              else if (!deadly && depth > 1.5) at[0].f[at[1]] |= WATER;
            }
          }
        }
      }
    });
  }

  // Buildings, bridges and tunnels: their floors are walkable whatever the ground under them
  // does. A floor counts where it's at or above the ground (bridge decks, building floors);
  // floors buried in the ground (caves, mines) would link places that aren't linked, so they
  // don't, except in tunnels, which are there to link two places.
  const seen = new Set();
  let floors = 0;
  for (const w of wmos) {
    if (seen.has(w.id)) continue;
    seen.add(w.id);
    const tris = Floors(mpq, w.name);
    if (!tris.length) continue;
    const tunnel = /tunnel/i.test(w.name);
    // placement: local (x, y, z up) -> (y, z, x), turned by yaw about the up axis, plus pos;
    // placement x = ORIGIN - worldY (grid x * UNIT), y = height, z = ORIGIN - worldX
    const a = w.yaw * Math.PI / 180, c = Math.cos(a), sn = Math.sin(a);
    const P = (v) => [w.pos[0] + c * v[1] + sn * v[0], w.pos[1] + v[2], w.pos[2] - sn * v[1] + c * v[0]];
    for (const t of tris) {
      const p = t.map(P);
      const gx = p.map(q => q[0] / UNIT), gy = p.map(q => q[2] / UNIT);
      const det = (gy[1] - gy[2]) * (gx[0] - gx[2]) + (gx[2] - gx[1]) * (gy[0] - gy[2]);
      if (Math.abs(det) < 1e-9) continue;
      for (let y = Math.ceil(Math.min(...gy)); y <= Math.floor(Math.max(...gy)); y++) {
        for (let x = Math.ceil(Math.min(...gx)); x <= Math.floor(Math.max(...gx)); x++) {
          const l1 = ((gy[1] - gy[2]) * (x - gx[2]) + (gx[2] - gx[1]) * (y - gy[2])) / det;
          const l2 = ((gy[2] - gy[0]) * (x - gx[2]) + (gx[0] - gx[2]) * (y - gy[2])) / det;
          const l3 = 1 - l1 - l2;
          if (l1 < -0.01 || l2 < -0.01 || l3 < -0.01) continue;
          const at = Index(x, y, false);
          if (!at) continue;
          const ground = at[0].h[at[1]];
          const floor = l1 * p[0][1] + l2 * p[1][1] + l3 * p[2][1];
          if (tunnel || !(ground === ground) || floor >= ground - 4) {
            if (!(at[0].f[at[1]] & FREE)) floors++;
            at[0].f[at[1]] |= FREE;
          }
        }
      }
    }
  }

  const land = {
    map, tiles: tiles.size, wmos: seen.size, floors,
    Height(gx, gy) { const at = Index(gx, gy); return at ? at[0].h[at[1]] : NaN; },
    Flags(gx, gy) { const at = Index(gx, gy); return at ? at[0].f[at[1]] : 0; },
  };

  // Small steep patches (a rock, a mound, a bank a few yards long) are walked round without
  // thinking; left in, they make the search zig-zag. Steep points in patches smaller than
  // SPECK points are marked SMOOTH and treated as flat.
  const steep = (gx, gy) => {
    for (const [dx, dy] of [[1, 0], [0, 1], [-1, 0], [0, -1]]) if (!Step(land, gx, gy, gx + dx, gy + dy, true)) return true;
    return false;
  };
  const visited = new Map(); // tile key -> Uint8Array
  const Visited = (gx, gy) => {
    const k = (gy >> 7) * 64 + (gx >> 7);
    let v = visited.get(k);
    if (!v) { v = new Uint8Array(128 * 128); visited.set(k, v); }
    return [v, (gy & 127) * 128 + (gx & 127)];
  };
  let smoothed = 0;
  for (const [k, t] of tiles) {
    const tx = k % 64, ty = Math.floor(k / 64);
    for (let i = 0; i < 128 * 128; i++) {
      const gx = tx * 128 + (i & 127), gy = ty * 128 + (i >> 7);
      const [v, vi] = Visited(gx, gy);
      if (v[vi] || !(t.h[i] === t.h[i]) || (t.f[i] & (WATER | DEADLY | FREE)) || !steep(gx, gy)) continue;
      // flood the patch, stopping once it's clearly not small
      const patch = [[gx, gy]];
      v[vi] = 1;
      for (let q = 0; q < patch.length && patch.length <= SPECK; q++) {
        const [px, py] = patch[q];
        for (const [dx, dy] of [[1, 0], [0, 1], [-1, 0], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]) {
          const nx = px + dx, ny = py + dy;
          if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue;
          const [nv, ni] = Visited(nx, ny);
          if (nv[ni]) continue;
          const h = land.Height(nx, ny);
          if (!(h === h) || (land.Flags(nx, ny) & (WATER | DEADLY | FREE)) || !steep(nx, ny)) continue;
          nv[ni] = 1;
          patch.push([nx, ny]);
        }
      }
      if (patch.length <= SPECK) {
        for (const [px, py] of patch) { const at = Index(px, py); at[0].f[at[1]] |= SMOOTH; }
        smoothed += patch.length;
      }
    }
  }
  land.smoothed = smoothed;
  return land;
}

// can you go from one grid point to its neighbour? returns the cost multiplier, or 0.
// raw: ignore SMOOTH (used while finding the small patches)
function Step(T, ax, ay, bx, by, raw) {
  const ha = T.Height(ax, ay), hb = T.Height(bx, by);
  if (!(ha === ha) || !(hb === hb)) return 0; // NaN: off the map
  const fa = T.Flags(ax, ay), fb = T.Flags(bx, by);
  if ((fa | fb) & DEADLY) return 0;
  if (fa & fb & WATER) return 2.5; // swimming
  if ((fa | fb) & FREE) return 1.2;
  if (!raw && (fa & SMOOTH || fb & SMOOTH)) return 1.3;
  const run = (ax !== bx && ay !== by) ? Math.SQRT2 : 1;
  if (Math.abs(ha - hb) / (run * UNIT) > MAX_SLOPE) return 0;
  // the ground squares the step crosses: a diagonal step crosses one, a straight step runs
  // along the edge between two and needs one of them walkable
  const x = Math.min(ax, bx), y = Math.min(ay, by);
  const ok = (cx, cy) => !(T.Flags(cx, cy) & STEEP) && T.Height(cx, cy) === T.Height(cx, cy);
  if (ax !== bx && ay !== by) { if (!ok(x, y)) return 0; }
  else if (ay === by) { if (!ok(x, y) && !ok(x, y - 1)) return 0; }
  else if (!ok(x, y) && !ok(x - 1, y)) return 0;
  return (fa | fb) & WATER ? 1.8 : 1;
}

module.exports = { Continent, Step, ToGrid, ToWorld, UNIT, WATER, DEADLY, FREE, SMOOTH, STEEP };
