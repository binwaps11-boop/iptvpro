import { createConnection } from 'mysql2/promise';
import { readFileSync } from 'fs';

const url = process.env.DATABASE_URL;
if (!url) { console.error('DATABASE_URL not set'); process.exit(1); }

const conn = await createConnection(url);

const sql = readFileSync('drizzle/0015_tiresome_betty_ross.sql', 'utf8');
const statements = sql.split('--> statement-breakpoint').map(s => s.trim()).filter(Boolean);

for (const stmt of statements) {
  try {
    await conn.execute(stmt);
    console.log('OK:', stmt.substring(0, 50) + '...');
  } catch (e) {
    if (e.code === 'ER_TABLE_EXISTS_ERROR') {
      console.log('SKIP (already exists):', stmt.substring(0, 50) + '...');
    } else {
      console.error('ERROR:', e.message);
    }
  }
}

await conn.end();
console.log('Migration complete!');
