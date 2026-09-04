'use strict';

const fs = require('fs');
const path = require('path');

const dashboard = process.argv[2] || path.join(__dirname, '..', 'files', 'www', 'dashboard.js');
const source = fs.readFileSync(dashboard, 'utf8');
const start = source.indexOf('  function isRealMac(mac) {');
const end = source.indexOf('  async function scanLan()', start);
if (start < 0 || end < 0) throw new Error('LAN scan renderer block not found');

const block = source.slice(start, end);
const esc = (value) => String(value == null ? '' : value)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
const tr = (key) => key;
const tableCaption = label => `<caption class="sr-only">${esc(label)}</caption>`;
const tableHeaderCells = labels => labels.map(label => `<th scope="col">${esc(label)}</th>`).join('');
const factory = new Function('esc', 'tr', 'tableCaption', 'tableHeaderCells',
  `${block}\nreturn { isRealMac, renderLanScan };`);
const { renderLanScan } = factory(esc, tr, tableCaption, tableHeaderCells);

const devicesOnly = renderLanScan({
  ok: true,
  devices: [
    { host: 'edge-switch', ip: '192.168.1.20', mac: 'd4:35:38:d4:f3:c8', port: 'lan2', iface: 'br-lan' },
    { host: '<script>', ip: '224.0.0.1', mac: '01:00:5e:00:00:01', port: 'lan1', iface: 'br-lan' },
    { host: 'zero-noise', ip: '0.0.0.0', mac: '00:00:00:00:00:00', port: 'lan1', iface: 'br-lan' },
    { host: 'malformed-noise', ip: '192.168.1.30', mac: 'zz:zz:zz:zz:zz:zz', port: 'lan3', iface: 'br-lan' }
  ],
  lldp: []
});
if (!devicesOnly.includes('edge-switch') || !devicesOnly.includes('D4:35:38:D4:F3:C8') ||
    !devicesOnly.includes('lan2') || devicesOnly.includes('&lt;script&gt;') ||
    devicesOnly.includes('noLldpNeighbors') || devicesOnly.includes('zero-noise') ||
    devicesOnly.includes('malformed-noise') ||
    !devicesOnly.includes('data-ui-key="lan:d4:35:38:d4:f3:c8"') ||
    !devicesOnly.includes('<caption class="sr-only">lanNeighbors</caption>') ||
    (devicesOnly.match(/<th scope="col">/g) || []).length !== 5) {
  throw new Error(`devices-only LAN scan was not rendered correctly: ${devicesOnly}`);
}

const lldpOnly = renderLanScan({
  ok: true,
  devices: [],
  lldp: [{ name: '<core>', platform: 'switch', ip: '192.168.1.2', local_port: 'lan1', remote_port: '24' }]
});
if (!lldpOnly.includes('&lt;core&gt;') || !lldpOnly.includes('lldpNeighbors') ||
    !lldpOnly.includes('data-ui-key="lldp:lan1|24|&lt;core&gt;"') ||
    !lldpOnly.includes('<caption class="sr-only">lldpNeighbors</caption>') ||
    (lldpOnly.match(/<th scope="col">/g) || []).length !== 5)
  throw new Error(`LLDP-only LAN scan regression: ${lldpOnly}`);

const empty = renderLanScan({ ok: true, devices: [], lldp: [] });
if (!empty.includes('noLanDevices')) throw new Error(`empty scan state mismatch: ${empty}`);

console.log('lan_scan_render=pass');
