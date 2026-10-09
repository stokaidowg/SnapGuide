const { lua } = require('./pfdb');
const fs = require('fs');
for (const z of process.argv.slice(2)) {
  console.log('=== zone ' + z);
  console.log(lua('ZONE = ' + z + '\n' + fs.readFileSync(__dirname + '/q-zone.lua', 'utf8')));
}
