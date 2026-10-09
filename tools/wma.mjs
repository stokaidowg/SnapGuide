import { FS, MPQ } from '@wowserhq/stormjs';
import fs from 'node:fs';
FS.mkdir('/data');
FS.mount(FS.filesystems.NODEFS, { root: 'H:/Games/OctoWoW/Data' }, '/data');
const archives = ['dbc.MPQ', 'patch.MPQ', 'patch-1.mpq', 'patch-2.mpq', 'patch-3.mpq', 'patch-4.mpq', 'patch-5.mpq', 'patch-O.mpq', 'backup.MPQ'];
const name = 'DBFilesClient' + String.fromCharCode(92) + 'WorldMapArea.dbc';
fs.mkdirSync('mpqout/wma', { recursive: true });
for (const a of archives) {
  let mpq;
  try { mpq = await MPQ.open('/data/' + a, 'r'); } catch (e) { console.log('cannot open', a); continue; }
  try {
    if (mpq.hasFile(name)) {
      const f = mpq.openFile(name); const d = f.read(); f.close();
      fs.writeFileSync('mpqout/wma/' + a + '.dbc', Buffer.from(d));
      console.log('found in', a, d.length);
    }
  } catch (e) { console.log('err', a, e.message); }
  mpq.close();
}
