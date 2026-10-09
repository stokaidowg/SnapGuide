// node overlap.js [routesDir]: lists quests in each built route that can be done together
// (shared mobs or the same area), with how far apart the route has them.
const fs = require('fs');
const path = require('path');
const { lua } = require('./pfdb');
const dir = path.resolve(process.argv[2] || path.join(__dirname, '..', 'Routes'));
const order = fs.readFileSync(path.join(__dirname, 'route', 'order.txt'), 'utf8').split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith('#'));
const files = order.map(n => path.join(dir, n + '.lua').replace(/\\/g, '/'));
console.log(lua('ROUTEFILES = ' + JSON.stringify(files).replace('[', '{').replace(/\]$/, '}') + '\n' + fs.readFileSync(path.join(__dirname, 'overlap.lua'), 'utf8')));
