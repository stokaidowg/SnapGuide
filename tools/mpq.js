// MPQ reading (copied from SnapUI-dev/mpqget.js): Archives(dataDir).get(name) returns the file from
// the highest-priority archive that has it, like the client.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const T = new Uint32Array(0x500);
(function () {
  let seed = 0x00100001;
  for (let i = 0; i < 256; i++) {
    let idx = i;
    for (let j = 0; j < 5; j++) {
      seed = (seed * 125 + 3) % 0x2aaaab;
      const t1 = (seed & 0xffff) << 16;
      seed = (seed * 125 + 3) % 0x2aaaab;
      T[idx] = (t1 | (seed & 0xffff)) >>> 0;
      idx += 256;
    }
  }
})();
function hash(str, type) {
  let s1 = 0x7fed7fed, s2 = 0xeeeeeeee;
  for (const c of str.toUpperCase()) {
    const ch = c.charCodeAt(0);
    s1 = (T[type * 256 + ch] ^ ((s1 + s2) >>> 0)) >>> 0;
    s2 = (ch + s1 + s2 + ((s2 << 5) >>> 0) + 3) >>> 0;
  }
  return s1;
}
function decrypt(buf, key) {
  let seed = 0xeeeeeeee;
  const out = Buffer.from(buf);
  for (let i = 0; i + 4 <= out.length; i += 4) {
    seed = (seed + T[0x400 + (key & 0xff)]) >>> 0;
    const ch = (out.readUInt32LE(i) ^ ((key + seed) >>> 0)) >>> 0;
    out.writeUInt32LE(ch, i);
    key = ((((~key) << 0x15) >>> 0) + 0x11111111 | (key >>> 0x0b)) >>> 0;
    seed = (ch + seed + ((seed << 5) >>> 0) + 3) >>> 0;
  }
  return out;
}

// PKWARE DCL "explode" (used by older Blizzard MPQs)
function explode(src) {
  const LenBits = [3,2,3,3,4,4,4,5,5,5,5,6,6,6,7,7], LenCode = [5,3,1,6,10,2,12,20,4,24,8,48,16,32,64,0];
  const ExLenBits = [0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8], LenBase = [0,1,2,3,4,5,6,7,8,10,14,22,38,70,134,262];
  const DistBits = [2,4,4,5,5,5,5,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8];
  const DistCode = [0x03,0x0D,0x05,0x19,0x09,0x11,0x01,0x3E,0x1E,0x2E,0x0E,0x36,0x16,0x26,0x06,0x3A,0x1A,0x2A,0x0A,0x32,0x12,0x22,0x42,0x02,0x7C,0x3C,0x5C,0x1C,0x6C,0x2C,0x4C,0x0C,0x74,0x34,0x54,0x14,0x64,0x24,0x44,0x04,0x78,0x38,0x58,0x18,0x68,0x28,0x48,0x08,0xF0,0x70,0xB0,0x30,0xD0,0x50,0x90,0x10,0xE0,0x60,0xA0,0x20,0xC0,0x40,0x80,0x00];
  const ctype = src[0], dsize = src[1];
  if (ctype !== 0) throw new Error("binary-mode explode only");
  let pos = 2, bitbuf = 0, bitcnt = 0;
  const need = (n) => { while (bitcnt < n) { if (pos >= src.length) throw new Error("eof"); bitbuf |= src[pos++] << bitcnt; bitcnt += 8; } };
  const bits = (n) => { need(n); const v = bitbuf & ((1 << n) - 1); bitbuf >>>= n; bitcnt -= n; return v; };
  const rev = (v, n) => { let r = 0; for (let i = 0; i < n; i++) { r = (r << 1) | (v & 1); v >>= 1; } return r; };
  const decodeTable = (lens, codes) => { const m = new Map(); for (let i = 0; i < lens.length; i++) if (lens[i]) m.set(lens[i] + ":" + codes[i], i); return m; };
  const lenMap = decodeTable(LenBits, LenCode), distMap = decodeTable(DistBits, DistCode);
  const decode = (m, maxbits) => { let code = 0; for (let n = 1; n <= maxbits; n++) { code |= bits(1) << (n - 1); const k = m.get(n + ":" + code); if (k !== undefined) return k; } throw new Error("bad code"); };
  const out = [];
  for (;;) {
    if (bits(1)) {
      const li = decode(lenMap, 7);
      let len = LenBase[li] + (ExLenBits[li] ? bits(ExLenBits[li]) : 0) + 2;
      if (len === 519) break;
      const di = decode(distMap, 8);
      const dist = (len === 2 ? (di << 2) | bits(2) : (di << dsize) | bits(dsize)) + 1;
      for (let i = 0; i < len; i++) out.push(out[out.length - dist]);
    } else {
      out.push(bits(8));
    }
  }
  return Buffer.from(out);
}

function decompress(b) {
  let mask = b[0], body = b.subarray(1);
  if (mask === 0x02) return zlib.inflateSync(body);
  if (mask === 0x08) return explode(body);
  throw new Error("compression 0x" + mask.toString(16));
}

function openMpq(file) {
  const fd = fs.openSync(file, "r");
  const read = (p, n) => { const b = Buffer.alloc(n); fs.readSync(fd, b, 0, n, p); return b; };
  let base = 0, h = read(0, 64);
  if (h.toString("latin1", 0, 4) === "MPQ\x1b") { base = h.readUInt32LE(8); h = read(base, 64); }
  const sectorSize = 512 << h.readUInt16LE(14);
  const hc = h.readUInt32LE(24), bc = h.readUInt32LE(28);
  const ht = decrypt(read(base + h.readUInt32LE(16), hc * 16), hash("(hash table)", 3));
  const bt = decrypt(read(base + h.readUInt32LE(20), bc * 16), hash("(block table)", 3));
  return {
    get(name) {
      const n1 = hash(name, 1), n2 = hash(name, 2);
      let bi = -1;
      for (let i = hash(name, 0) % hc, k = 0; k < hc; i = (i + 1) % hc, k++) {
        const blk = ht.readUInt32LE(i * 16 + 12);
        if (blk === 0xffffffff) break;
        if (ht.readUInt32LE(i * 16) === n1 && ht.readUInt32LE(i * 16 + 4) === n2 && blk !== 0xfffffffe) { bi = blk; break; }
      }
      if (bi < 0) return null;
      const fp = bt.readUInt32LE(bi * 16), cs = bt.readUInt32LE(bi * 16 + 4), fsz = bt.readUInt32LE(bi * 16 + 8), fl = bt.readUInt32LE(bi * 16 + 12);
      if (!(fl & 0x80000000)) return null;
      const abs = base + fp;
      let key = hash(name.split("\\").pop(), 3);
      if (fl & 0x20000) key = ((key + fp) ^ fsz) >>> 0;
      const enc = fl & 0x10000, comp = fl & 0x200, imp = fl & 0x100;
      const dec = (b) => imp ? explode(b) : decompress(b);
      if (fl & 0x1000000) { let b = read(abs, cs); if (enc) b = decrypt(b, key); return (comp || imp) && cs < fsz ? dec(b) : b; }
      if (!comp && !imp) {
        const d = read(abs, fsz);
        if (!enc) return d;
        const parts = []; for (let s = 0; s * sectorSize < fsz; s++) parts.push(decrypt(d.subarray(s * sectorSize, (s + 1) * sectorSize), (key + s) >>> 0));
        return Buffer.concat(parts);
      }
      const ns = Math.ceil(fsz / sectorSize);
      let off = read(abs, (ns + 1) * 4);
      if (enc) off = decrypt(off, (key - 1) >>> 0);
      const parts = [];
      for (let s = 0; s < ns; s++) {
        const a = off.readUInt32LE(s * 4), e = off.readUInt32LE(s * 4 + 4);
        let b = read(abs + a, e - a);
        if (enc) b = decrypt(b, (key + s) >>> 0);
        const expect = Math.min(sectorSize, fsz - s * sectorSize);
        parts.push(b.length < expect ? (imp ? explode(b) : decompress(b)) : b);
      }
      return Buffer.concat(parts);
    },
  };
}

function Archives(dataDir) {
  // WoW loads base archives, then patch.MPQ, patch-1..9, patch-A..Z; later wins
  const order = fs.readdirSync(dataDir).filter(f => /\.mpq$/i.test(f));
  const rank = f => { const l = f.toLowerCase(); if (!l.startsWith("patch")) return 0; if (l === "patch.mpq") return 1; const c = l[6]; return /[0-9]/.test(c) ? 2 + Number(c) : 20 + c.charCodeAt(0); };
  order.sort((a, b) => rank(b) - rank(a));
  const archives = order.map(f => openMpq(path.join(dataDir, f)));
  return {
    get(name) {
      name = name.split("/").join("\\");
      for (const m of archives) {
        const d = m.get(name);
        if (d) return d;
      }
      return null;
    },
  };
}

module.exports = { Archives };
