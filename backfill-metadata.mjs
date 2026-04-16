import 'dotenv/config';
import mysql from 'mysql2/promise';

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL not set');
  process.exit(1);
}

async function main() {
  const conn = await mysql.createConnection(DATABASE_URL);
  
  // Get all Xtream sources
  const [sources] = await conn.execute('SELECT id, url, username, password FROM stream_sources WHERE sourceType = ?', ['xtream']);
  console.log(`Found ${sources.length} Xtream sources`);
  
  let totalUpdated = 0;
  
  for (const src of sources) {
    if (!src.url || !src.username || !src.password) continue;
    const baseUrl = src.url.replace(/\/+$/, '');
    console.log(`Processing source ${src.id}: ${baseUrl} (user: ${src.username})`);
    
    // Update live channels
    const [liveChannels] = await conn.execute(
      'SELECT id, tvgId FROM channels WHERE sourceId = ? AND contentType = ? AND rawMetadata IS NULL',
      [src.id, 'live']
    );
    console.log(`  Live channels to update: ${liveChannels.length}`);
    for (const ch of liveChannels) {
      const meta = JSON.stringify({
        sourceType: 'xtream', baseUrl,
        username: src.username, password: src.password,
        streamId: ch.tvgId ? parseInt(ch.tvgId) : 0,
        streamType: 'live'
      });
      await conn.execute('UPDATE channels SET rawMetadata = ? WHERE id = ?', [meta, ch.id]);
      totalUpdated++;
    }
    
    // Update movie channels
    const [movieChannels] = await conn.execute(
      'SELECT id, tvgId, streamUrl FROM channels WHERE sourceId = ? AND contentType = ? AND rawMetadata IS NULL',
      [src.id, 'movie']
    );
    console.log(`  Movie channels to update: ${movieChannels.length}`);
    for (const ch of movieChannels) {
      const ext = ch.streamUrl ? ch.streamUrl.split('.').pop() : 'mp4';
      const meta = JSON.stringify({
        sourceType: 'xtream', baseUrl,
        username: src.username, password: src.password,
        streamId: ch.tvgId ? parseInt(ch.tvgId) : 0,
        streamType: 'vod', extension: ext || 'mp4'
      });
      await conn.execute('UPDATE channels SET rawMetadata = ? WHERE id = ?', [meta, ch.id]);
      totalUpdated++;
    }
    
    // Update series channels
    const [seriesChannels] = await conn.execute(
      'SELECT id, tvgId FROM channels WHERE sourceId = ? AND contentType = ? AND rawMetadata IS NULL',
      [src.id, 'series']
    );
    console.log(`  Series channels to update: ${seriesChannels.length}`);
    for (const ch of seriesChannels) {
      const meta = JSON.stringify({
        sourceType: 'xtream', baseUrl,
        username: src.username, password: src.password,
        seriesId: ch.tvgId ? parseInt(ch.tvgId) : 0,
        streamType: 'series'
      });
      await conn.execute('UPDATE channels SET rawMetadata = ? WHERE id = ?', [meta, ch.id]);
      totalUpdated++;
    }
  }
  
  console.log(`\nTotal updated: ${totalUpdated}`);
  await conn.end();
}

main().catch(e => { console.error(e); process.exit(1); });
