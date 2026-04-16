import { getAllStreamSources } from './server/db.ts';

async function main() {
  const sources = await getAllStreamSources();
  for (const src of sources) {
    console.log(`ID: ${src.id} | Name: ${src.name} | Type: ${src.sourceType} | URL: ${src.url} | User: ${src.username} | Channels: ${src.channelsCount}`);
  }
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
