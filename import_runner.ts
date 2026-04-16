
import * as db from './server/db';
import fs from 'fs';

async function main() {
  const data = JSON.parse(fs.readFileSync('/tmp/import_data.json', 'utf8'));
  
  // 1. Create Xtream source
  console.log('Creating Xtream source...');
  const xtreamSourceId = await db.createStreamSource({
    name: data.xtream.name,
    sourceType: 'xtream',
    url: data.xtream.url,
    username: data.xtream.username,
    password: data.xtream.password,
  });
  console.log('Xtream source ID:', xtreamSourceId);
  
  // 2. Import Xtream channels in batches
  const BATCH_SIZE = 1000;
  const xtreamChannels = data.xtream.channels;
  let totalXtream = 0;
  
  for (let i = 0; i < xtreamChannels.length; i += BATCH_SIZE) {
    const batch = xtreamChannels.slice(i, i + BATCH_SIZE);
    
    // Create categories first
    const groups = [...new Set(batch.map((ch: any) => ch.group).filter(Boolean))];
    const categoryMap = new Map<string, number>();
    for (const group of groups) {
      const catId = await db.findOrCreateCategory(group as string);
      categoryMap.set(group as string, catId);
    }
    
    const channelData = batch.map((ch: any) => ({
      name: ch.name,
      streamUrl: ch.streamUrl,
      logoUrl: ch.logoUrl || null,
      categoryId: ch.group ? (categoryMap.get(ch.group) ?? null) : null,
      sourceId: xtreamSourceId,
      isActive: 1,
      tvgId: ch.tvgId || null,
      tvgName: ch.tvgName || null,
      groupTitle: ch.group || null,
      contentType: (ch.contentType || 'live') as 'live' | 'movie' | 'series',
      rawMetadata: ch.rawMetadata || null,
    }));
    
    const count = await db.createManyChannels(channelData);
    totalXtream += count;
    console.log(`Batch ${Math.floor(i/BATCH_SIZE) + 1}: ${count} imported (total: ${totalXtream})`);
  }
  
  await db.updateStreamSource(xtreamSourceId, { channelsCount: totalXtream, lastSync: new Date() });
  console.log(`✅ Xtream: ${totalXtream} channels imported`);
  
  // 3. Create M3U8 source
  console.log('\nCreating M3U8 source...');
  const m3uSourceId = await db.createStreamSource({
    name: data.m3u8.name,
    sourceType: 'm3u_file',
    fileName: 'IPTV442WEB-VIP-28-3-2026.m3u8',
  });
  console.log('M3U8 source ID:', m3uSourceId);
  
  // 4. Import M3U8 channels
  const m3uChannels = data.m3u8.channels;
  const m3uGroups = [...new Set(m3uChannels.map((ch: any) => ch.group).filter(Boolean))];
  const m3uCategoryMap = new Map<string, number>();
  for (const group of m3uGroups) {
    const catId = await db.findOrCreateCategory(group as string);
    m3uCategoryMap.set(group as string, catId);
  }
  
  const m3uData = m3uChannels.map((ch: any) => ({
    name: ch.name,
    streamUrl: ch.streamUrl,
    logoUrl: ch.logoUrl || null,
    categoryId: ch.group ? (m3uCategoryMap.get(ch.group) ?? null) : null,
    sourceId: m3uSourceId,
    isActive: 1,
    tvgId: ch.tvgId || null,
    tvgName: ch.tvgName || null,
    groupTitle: ch.group || null,
    contentType: 'live' as const,
    rawMetadata: null,
  }));
  
  const m3uCount = await db.createManyChannels(m3uData);
  await db.updateStreamSource(m3uSourceId, { channelsCount: m3uCount, lastSync: new Date() });
  console.log(`✅ M3U8: ${m3uCount} channels imported`);
  
  console.log(`\n✅ Total: ${totalXtream + m3uCount} channels imported from 2 sources`);
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
