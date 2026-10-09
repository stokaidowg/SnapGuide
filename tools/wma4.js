const fs = require('fs');
function parse(file) {
  const b = fs.readFileSync(file);
  // find the string block: from the end, back over printable chars and NULs
  let s = b.length;
  while (s > 0 && (b[s - 1] === 0 || (b[s - 1] >= 32 && b[s - 1] < 127))) s--;
  // align to a record boundary from offset 20
  while ((s - 20) % 32 !== 0) s++;
  // the block starts with a NUL
  const n = (s - 20) / 32;
  const out = {};
  for (let i = 0; i < n; i++) {
    const o = 20 + i * 32;
    const so = b.readUInt32LE(o + 12);
    let e = s + so; while (e < b.length && b[e]) e++;
    out[b.toString('latin1', s + so, e)] = [16, 20, 24, 28].map(k => +b.readFloatLE(o + k).toFixed(2)).concat([b.readUInt32LE(o + 8)]);
  }
  return out;
}
const v = {};
for (const a of ['dbc.MPQ', 'patch.MPQ', 'patch-3.mpq', 'patch-4.mpq']) v[a] = parse('mpqout/wma/' + a + '.dbc');
console.log(Object.keys(v['patch-4.mpq']).length, 'zones in patch-4; sample', JSON.stringify(Object.entries(v['patch-4.mpq']).slice(0, 3)));
const base = v['patch-3.mpq'];
for (const [nm, r] of Object.entries(v['patch-4.mpq'])) {
  const old = base[nm] || v['patch.MPQ'][nm] || v['dbc.MPQ'][nm];
  if (!old) { console.log('NEW ', nm, r.join(',')); continue; }
  if (old.slice(0, 4).some((x, i) => Math.abs(x - r[i]) > 1)) console.log('MOVED', nm, 'old', old.join(','), 'new', r.join(','));
}
