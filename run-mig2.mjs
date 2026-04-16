import mysql from 'mysql2/promise';

const url = process.env.DATABASE_URL;
const conn = await mysql.createConnection(url);

const stmts = [
  "ALTER TABLE `mikrotik_servers` ADD `mikrotikIdentity` varchar(255)",
  "ALTER TABLE `mikrotik_servers` ADD `allowedMacs` text",
  "ALTER TABLE `mikrotik_servers` ADD `allowedPorts` text",
  "ALTER TABLE `mikrotik_servers` ADD `macFilterMode` enum('whitelist','blacklist','disabled') DEFAULT 'disabled'",
  "ALTER TABLE `mikrotik_servers` ADD `portRestrictionMode` enum('allow_only','block','disabled') DEFAULT 'disabled'",
];

for (const s of stmts) {
  try {
    await conn.execute(s);
    console.log('OK:', s.slice(0, 60));
  } catch (e) {
    if (e.code === 'ER_DUP_FIELDNAME') console.log('SKIP (exists):', s.slice(0, 60));
    else console.error('ERR:', e.message);
  }
}
await conn.end();
console.log('Done');
