import * as db from './server/db';

async function main() {
  const channels = await db.getAllChannels({});
  const types: Record<string,number> = {};
  for (const ch of channels) { const t = ch.contentType || 'unknown'; types[t] = (types[t]||0)+1; }
  console.log('Total:', channels.length);
  for (const [t,c] of Object.entries(types).sort()) console.log(' ', t, ':', c);
  
  // Find a series from new source
  const series = channels.filter(c => c.contentType === 'series' && c.sourceId === 360003);
  console.log('Series from new source:', series.length);
  if (series.length > 0) {
    const s = series[0];
    console.log('First series:', s.id, s.name?.substring(0,40));
    if (s.rawMetadata) {
      const meta = JSON.parse(s.rawMetadata);
      console.log('  meta:', JSON.stringify(meta).substring(0,100));
    }
  }
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
