// node travel.js [routesDir]: walking estimate per built route, its longest legs, and spots it
// comes back to after leaving.
const fs = require('fs');
const path = require('path');
const { lua } = require('./pfdb');
const dir = path.resolve(process.argv[2] || path.join(__dirname, '..', 'Routes'));
const order = fs.readFileSync(path.join(__dirname, 'route', 'order.txt'), 'utf8').split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith('#'));
const files = order.map(n => path.join(dir, n + '.lua').replace(/\\/g, '/'));
// zone sizes come from the add-on's zones.lua (every zone the client knows)
const zoneSrc = fs.readFileSync(path.join(__dirname, '..', 'zones.lua'), 'utf8');
console.log(lua('ZONESRC = ' + JSON.stringify(zoneSrc) + '\nROUTEFILES = {' + files.map(f => JSON.stringify(f)).join(',') + '}\n' + fs.readFileSync(path.join(__dirname, 'travel.lua'), 'utf8')));
