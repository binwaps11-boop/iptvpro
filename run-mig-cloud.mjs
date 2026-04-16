import mysql from 'mysql2/promise';
import fs from 'fs';

const conn = await mysql.createConnection(process.env.DATABASE_URL);
const sql = fs.readFileSync('./drizzle/0018_friendly_medusa.sql', 'utf8');
const statements = sql.split('--> statement-breakpoint').map(s => s.trim()).filter(Boolean);

for (const stmt of statements) {
  try {
    await conn.execute(stmt);
    console.log('OK:', stmt.slice(0, 60));
  } catch (e) {
    if (e.code === 'ER_DUP_FIELDNAME') {
      console.log('SKIP (exists):', stmt.slice(0, 60));
    } else {
      console.error('ERR:', e.message);
    }
  }
}
await conn.end();
console.log('Done!');
