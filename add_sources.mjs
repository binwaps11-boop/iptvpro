/**
 * Script to add new Xtream source and M3U8 file directly via database
 * Bypasses tRPC auth by calling db functions directly
 */
import fs from 'fs';

const XTREAM_URL = 'http://jwnyc.w-4k.pro:80';
const XTREAM_USER = 'ham7745152';
const XTREAM_PASS = '951423652';

async function safeFetch(url, timeoutMs = 60000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const text = await res.text();
    try { return JSON.parse(text); } catch { return []; }
  } catch (e) {
    if (e.name === 'AbortError') return [];
    throw e;
  } finally { clearTimeout(timer); }
}

async function main() {
  // ============= 1. Fetch Xtream Data =============
  console.log('=== Fetching Xtream Data from jwnyc.w-4k.pro ===');
  const apiUrl = (action) => `${XTREAM_URL}/player_api.php?username=${encodeURIComponent(XTREAM_USER)}&password=${encodeURIComponent(XTREAM_PASS)}&action=${action}`;
  
  // Auth check
  const authData = await safeFetch(`${XTREAM_URL}/player_api.php?username=${encodeURIComponent(XTREAM_USER)}&password=${encodeURIComponent(XTREAM_PASS)}`, 15000);
  console.log('Auth:', authData?.user_info?.auth === 1 ? 'OK' : 'FAILED');
  
  // Fetch all content types in parallel
  const [liveCats, liveStreams, vodCats, vodStreams, seriesCats, seriesStreams] = await Promise.all([
    safeFetch(apiUrl('get_live_categories')),
    safeFetch(apiUrl('get_live_streams')),
    safeFetch(apiUrl('get_vod_categories')),
    safeFetch(apiUrl('get_vod_streams')),
    safeFetch(apiUrl('get_series_categories')),
    safeFetch(apiUrl('get_series')),
  ]);
  
  console.log(`Live: ${liveStreams.length} channels in ${liveCats.length} categories`);
  console.log(`VOD: ${vodStreams.length} movies in ${vodCats.length} categories`);
  console.log(`Series: ${seriesStreams.length} series in ${seriesCats.length} categories`);
  
  // Build channels array
  const catMap = (cats) => { const m = new Map(); if (Array.isArray(cats)) for (const c of cats) m.set(String(c.category_id), c.category_name); return m; };
  const liveCatMap = catMap(liveCats);
  const vodCatMap = catMap(vodCats);
  const seriesCatMap = catMap(seriesCats);
  
  const liveChannels = (Array.isArray(liveStreams) ? liveStreams : []).map(s => ({
    name: s.name || 'Unknown',
    streamUrl: `${XTREAM_URL}/live/${encodeURIComponent(XTREAM_USER)}/${encodeURIComponent(XTREAM_PASS)}/${s.stream_id}.m3u8`,
    logoUrl: s.stream_icon || null,
    group: liveCatMap.get(String(s.category_id)) || 'Uncategorized',
    tvgId: String(s.stream_id || ''),
    tvgName: s.name || '',
    contentType: 'live',
    rawMetadata: JSON.stringify({ sourceType: 'xtream', baseUrl: XTREAM_URL, username: XTREAM_USER, password: XTREAM_PASS, streamId: s.stream_id, streamType: 'live' }),
  }));
  
  const vodChannels = (Array.isArray(vodStreams) ? vodStreams : []).map(s => ({
    name: s.name || 'Unknown Movie',
    streamUrl: `${XTREAM_URL}/movie/${encodeURIComponent(XTREAM_USER)}/${encodeURIComponent(XTREAM_PASS)}/${s.stream_id}.${s.container_extension || 'mp4'}`,
    logoUrl: s.stream_icon || null,
    group: vodCatMap.get(String(s.category_id)) || 'Movies',
    tvgId: String(s.stream_id || ''),
    tvgName: s.name || '',
    contentType: 'movie',
    rawMetadata: JSON.stringify({ sourceType: 'xtream', baseUrl: XTREAM_URL, username: XTREAM_USER, password: XTREAM_PASS, streamId: s.stream_id, streamType: 'vod', extension: s.container_extension || 'mp4' }),
  }));
  
  const seriesChannels = (Array.isArray(seriesStreams) ? seriesStreams : []).map(s => ({
    name: s.name || 'Unknown Series',
    streamUrl: `${XTREAM_URL}/series/${encodeURIComponent(XTREAM_USER)}/${encodeURIComponent(XTREAM_PASS)}/${s.series_id}`,
    logoUrl: s.cover || null,
    group: seriesCatMap.get(String(s.category_id)) || 'Series',
    tvgId: String(s.series_id || ''),
    tvgName: s.name || '',
    contentType: 'series',
    rawMetadata: JSON.stringify({ sourceType: 'xtream', baseUrl: XTREAM_URL, username: XTREAM_USER, password: XTREAM_PASS, seriesId: s.series_id, streamType: 'series' }),
  }));
  
  const allChannels = [...liveChannels, ...vodChannels, ...seriesChannels];
  console.log(`\nTotal channels to import: ${allChannels.length}`);
  
  // ============= 2. Parse M3U8 File =============
  console.log('\n=== Parsing M3U8 File ===');
  const m3uContent = fs.readFileSync('/home/ubuntu/upload/IPTV442WEB-VIP-28-3-2026(3).m3u8', 'utf8');
  const lines = m3uContent.split('\n');
  const m3uChannels = [];
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.startsWith('#EXTINF')) {
      const nameMatch = line.match(/,\s*(.+)$/);
      const logoMatch = line.match(/tvg-logo="([^"]+)"/);
      const groupMatch = line.match(/group-title="([^"]+)"/);
      const tvgIdMatch = line.match(/tvg-id="([^"]+)"/);
      const tvgNameMatch = line.match(/tvg-name="([^"]+)"/);
      
      let streamUrl = '';
      for (let j = i + 1; j < lines.length; j++) {
        const nextLine = lines[j].trim();
        if (nextLine && !nextLine.startsWith('#')) { streamUrl = nextLine; break; }
      }
      
      const name = nameMatch ? nameMatch[1].trim() : 'Unknown';
      if (name.includes('IPTV442WEB') || name.includes('تحديث') || name.includes('للتحديث') || name.includes('ابحث في جوجل')) continue;
      
      if (streamUrl) {
        m3uChannels.push({
          name,
          streamUrl,
          logoUrl: logoMatch ? logoMatch[1] : null,
          group: groupMatch ? groupMatch[1] : 'General',
          tvgId: tvgIdMatch ? tvgIdMatch[1] : null,
          tvgName: tvgNameMatch ? tvgNameMatch[1] : null,
          contentType: 'live',
          rawMetadata: null,
        });
      }
    }
  }
  console.log(`Parsed ${m3uChannels.length} channels from M3U8`);
  
  // ============= 3. Output JSON for import =============
  const output = {
    xtream: {
      name: 'W-4K Pro (Xtream)',
      url: XTREAM_URL,
      username: XTREAM_USER,
      password: XTREAM_PASS,
      liveCount: liveChannels.length,
      vodCount: vodChannels.length,
      seriesCount: seriesChannels.length,
      channels: allChannels,
    },
    m3u8: {
      name: 'IPTV442WEB VIP',
      channels: m3uChannels,
    },
  };
  
  fs.writeFileSync('/tmp/import_data.json', JSON.stringify(output));
  console.log(`\nData saved to /tmp/import_data.json`);
  console.log(`Xtream: ${allChannels.length} channels`);
  console.log(`M3U8: ${m3uChannels.length} channels`);
  console.log(`Total: ${allChannels.length + m3uChannels.length} channels`);
}

main().catch(console.error);
