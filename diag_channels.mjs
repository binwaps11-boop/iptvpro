import { createConnection } from 'mysql2/promise';

const conn = await createConnection(process.env.DATABASE_URL);

// Count channels by type and source
const [rows] = await conn.execute(`
  SELECT s.name as source_name, c.content_type, COUNT(*) as cnt 
  FROM channels c 
  LEFT JOIN sources s ON c.source_id = s.id 
  GROUP BY s.name, c.content_type 
  ORDER BY s.name, c.content_type
`);
console.log('\n=== Channels by Source and Type ===');
rows.forEach(r => console.log(`  ${r.source_name || 'unknown'} | ${r.content_type} | ${r.cnt}`));

// Get sample channels from each source
const [samples] = await conn.execute(`
  SELECT c.id, c.name, c.content_type, c.stream_url, c.source_id, s.name as source_name,
    LEFT(c.raw_metadata, 200) as meta_preview
  FROM channels c 
  LEFT JOIN sources s ON c.source_id = s.id 
  GROUP BY c.source_id, c.content_type
  ORDER BY c.source_id, c.content_type
  LIMIT 20
`);
console.log('\n=== Sample Channels ===');
samples.forEach(r => {
  console.log(`\n  ID: ${r.id} | Source: ${r.source_name} | Type: ${r.content_type}`);
  console.log(`  Name: ${r.name}`);
  console.log(`  URL: ${(r.stream_url || '').substring(0, 100)}`);
  console.log(`  Meta: ${(r.meta_preview || 'none')}`);
});

// Test a live channel URL from each source
const [liveChannels] = await conn.execute(`
  SELECT c.id, c.name, c.stream_url, c.raw_metadata, s.name as source_name, s.type as source_type
  FROM channels c 
  LEFT JOIN sources s ON c.source_id = s.id 
  WHERE c.content_type = 'live'
  GROUP BY c.source_id
  LIMIT 5
`);

console.log('\n=== Testing Live Channel URLs ===');
for (const ch of liveChannels) {
  let testUrl = ch.stream_url;
  if (ch.raw_metadata) {
    try {
      const meta = JSON.parse(ch.raw_metadata);
      if (meta.sourceType === 'xtream' && meta.baseUrl && meta.username && meta.password) {
        const u = encodeURIComponent(meta.username);
        const p = encodeURIComponent(meta.password);
        if (meta.streamId) {
          testUrl = `${meta.baseUrl}/live/${u}/${p}/${meta.streamId}.m3u8`;
        }
      }
    } catch {}
  }
  console.log(`\n  Channel: ${ch.name} (Source: ${ch.source_name})`);
  console.log(`  Resolved URL: ${testUrl?.substring(0, 120)}`);
  
  // Test if URL is reachable
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    const resp = await fetch(testUrl, { 
      method: 'HEAD',
      signal: controller.signal,
      redirect: 'follow',
      headers: { 'User-Agent': 'Mozilla/5.0' }
    });
    clearTimeout(timeout);
    console.log(`  Status: ${resp.status} ${resp.statusText}`);
    console.log(`  Content-Type: ${resp.headers.get('content-type')}`);
  } catch (e) {
    console.log(`  Error: ${e.message}`);
    // Try GET instead
    try {
      const controller2 = new AbortController();
      const timeout2 = setTimeout(() => controller2.abort(), 8000);
      const resp2 = await fetch(testUrl, { 
        signal: controller2.signal,
        redirect: 'follow',
        headers: { 'User-Agent': 'Mozilla/5.0' }
      });
      clearTimeout(timeout2);
      console.log(`  GET Status: ${resp2.status} ${resp2.statusText}`);
      console.log(`  GET Content-Type: ${resp2.headers.get('content-type')}`);
      const body = await resp2.text();
      console.log(`  Body preview: ${body.substring(0, 200)}`);
    } catch (e2) {
      console.log(`  GET Error: ${e2.message}`);
    }
  }
}

// Test VOD channel
const [vodChannels] = await conn.execute(`
  SELECT c.id, c.name, c.stream_url, c.raw_metadata, s.name as source_name
  FROM channels c 
  LEFT JOIN sources s ON c.source_id = s.id 
  WHERE c.content_type = 'movie'
  GROUP BY c.source_id
  LIMIT 3
`);

console.log('\n=== Testing VOD Channel URLs ===');
for (const ch of vodChannels) {
  let testUrl = ch.stream_url;
  if (ch.raw_metadata) {
    try {
      const meta = JSON.parse(ch.raw_metadata);
      if (meta.sourceType === 'xtream' && meta.baseUrl && meta.username && meta.password) {
        const u = encodeURIComponent(meta.username);
        const p = encodeURIComponent(meta.password);
        if (meta.streamId) {
          const ext = meta.extension || 'mp4';
          testUrl = `${meta.baseUrl}/movie/${u}/${p}/${meta.streamId}.${ext}`;
        }
      }
    } catch {}
  }
  console.log(`\n  Movie: ${ch.name} (Source: ${ch.source_name})`);
  console.log(`  Resolved URL: ${testUrl?.substring(0, 120)}`);
  
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    const resp = await fetch(testUrl, { 
      method: 'HEAD',
      signal: controller.signal,
      redirect: 'follow',
      headers: { 'User-Agent': 'Mozilla/5.0' }
    });
    clearTimeout(timeout);
    console.log(`  Status: ${resp.status} ${resp.statusText}`);
    console.log(`  Content-Type: ${resp.headers.get('content-type')}`);
    console.log(`  Content-Length: ${resp.headers.get('content-length')}`);
  } catch (e) {
    console.log(`  Error: ${e.message}`);
  }
}

// Check HLS proxy endpoint
console.log('\n=== Testing HLS Proxy ===');
for (const ch of liveChannels.slice(0, 2)) {
  try {
    const resp = await fetch(`http://127.0.0.1:3000/api/stream/hls-proxy/${ch.id}/playlist.m3u8`, {
      headers: { 'User-Agent': 'Mozilla/5.0' }
    });
    console.log(`  Channel ${ch.id} (${ch.name}): ${resp.status}`);
    if (resp.ok) {
      const body = await resp.text();
      console.log(`  Playlist lines: ${body.split('\n').length}`);
      console.log(`  Preview: ${body.substring(0, 300)}`);
    } else {
      const body = await resp.text();
      console.log(`  Error body: ${body.substring(0, 200)}`);
    }
  } catch (e) {
    console.log(`  Proxy error: ${e.message}`);
  }
}

// Check VOD proxy endpoint
console.log('\n=== Testing VOD Proxy ===');
for (const ch of vodChannels.slice(0, 2)) {
  try {
    const resp = await fetch(`http://127.0.0.1:3000/api/stream/vod/${ch.id}`, {
      headers: { 'User-Agent': 'Mozilla/5.0' }
    });
    console.log(`  Movie ${ch.id} (${ch.name}): ${resp.status}`);
    const body = await resp.json();
    console.log(`  Response:`, JSON.stringify(body).substring(0, 300));
  } catch (e) {
    console.log(`  VOD error: ${e.message}`);
  }
}

await conn.end();
process.exit(0);
