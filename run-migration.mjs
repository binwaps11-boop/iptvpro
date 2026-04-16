import mysql from 'mysql2/promise';
import fs from 'fs';

async function run() {
  const conn = await mysql.createConnection(process.env.DATABASE_URL);
  const stmts = fs.readFileSync('/tmp/migration.sql', 'utf8')
    .split('--> statement-breakpoint')
    .map(s => s.trim())
    .filter(Boolean);
  for (const s of stmts) {
    try {
      await conn.execute(s);
      console.log('OK:', s.substring(0, 60));
    } catch (e) {
      console.log('SKIP:', e.message.substring(0, 80));
    }
  }
  await conn.end();
}
run();
