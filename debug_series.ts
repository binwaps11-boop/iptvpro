import * as db from './server/db';

async function main() {
  // Get a series channel from new source
  const channel = await db.getChannelById(394083);
  if (!channel) { console.log('Channel not found'); process.exit(1); }
  
  console.log('Channel:', channel.id, channel.name);
  console.log('ContentType:', channel.contentType);
  console.log('rawMetadata:', channel.rawMetadata?.substring(0, 200));
  
  if (!channel.rawMetadata) {
    console.log('ERROR: No rawMetadata!');
    process.exit(1);
  }
  
  const meta = JSON.parse(channel.rawMetadata);
  console.log('Meta:', JSON.stringify(meta, null, 2));
  
  // Check if it has seriesId
  if (meta.sourceType !== 'xtream' || !meta.seriesId) {
    console.log('ERROR: Not xtream or no seriesId!');
    console.log('sourceType:', meta.sourceType);
    console.log('seriesId:', meta.seriesId);
    process.exit(1);
  }
  
  // Try fetching series info
  const apiUrl = `${meta.baseUrl}/player_api.php?username=${encodeURIComponent(meta.username)}&password=${encodeURIComponent(meta.password)}&action=get_series_info&series_id=${meta.seriesId}`;
  console.log('\nFetching:', apiUrl.substring(0, 100) + '...');
  
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const res = await fetch(apiUrl, { signal: controller.signal });
    console.log('Response status:', res.status);
    if (!res.ok) { console.log('HTTP error'); process.exit(1); }
    const data = await res.json();
    clearTimeout(timer);
    
    if (!data?.episodes) {
      console.log('No episodes in response!');
      console.log('Keys:', Object.keys(data));
      process.exit(1);
    }
    
    let total = 0;
    for (const [season, eps] of Object.entries(data.episodes)) {
      const arr = eps as any[];
      total += arr.length;
      console.log(`Season ${season}: ${arr.length} episodes`);
      if (arr.length > 0) {
        const ep = arr[0];
        console.log(`  First: id=${ep.id}, title=${ep.title?.substring(0,40)}, ext=${ep.container_extension}`);
      }
    }
    console.log(`\nTotal episodes: ${total}`);
  } catch (e: any) {
    clearTimeout(timer);
    console.log('Fetch error:', e.message);
  }
  
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
