import { createStreamSource, getAllStreamSources } from './server/db.ts';

async function main() {
  // Check existing sources
  const existing = await getAllStreamSources();
  console.log('Existing sources:', existing.length);
  
  // Check if source already exists
  const exists = existing.find(s => s.url === 'http://jwnyc.w-4k.pro:80');
  if (exists) {
    console.log('Source already exists with id:', exists.id);
    process.exit(0);
  }
  
  // Create new source
  const id = await createStreamSource({
    name: 'W-4K Pro',
    sourceType: 'xtream',
    url: 'http://jwnyc.w-4k.pro:80',
    username: 'ham7745152',
    password: '951423652',
  });
  
  console.log('Created source with id:', id);
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
