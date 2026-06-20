#!/usr/bin/env node
/*
 * IPTV Pro Desktop — مشغّل IPTV لسطح المكتب (شبيه Jellyfin)
 * -----------------------------------------------------------
 * خادم محلي مكتفٍ ذاتياً (بدون أي حزم npm) يقوم بـ:
 *   1. تقديم واجهة ويب لتشغيل القنوات (HLS).
 *   2. استيراد القوائم: M3U / M3U URL / Xtream Codes.
 *   3. Stream Proxy لحل مشكلة CORS وإعادة كتابة روابط m3u8.
 *   4. توجيه كل الطلبات عبر بروكسي/VPN يملكه المستخدم
 *      (HTTP CONNECT أو SOCKS5) — لتجاوز الحظر الجغرافي بشكل شرعي.
 *
 * التشغيل:  node server.js   ثم افتح  http://localhost:8787
 */

import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, 'public');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const PORT = process.env.PORT || 8787;

const DEFAULT_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

// ---------------------------------------------------------------------------
// إدارة الإعدادات (تُحفظ في config.json)
// ---------------------------------------------------------------------------
function defaultConfig() {
  return {
    sources: [], // {id, type, name, server, username, password, channels:[]}
    settings: {
      useProxy: true, // تمرير البث عبر الخادم المحلي (يحل CORS)
      userAgent: DEFAULT_UA,
      referer: '',
      // بروكسي/VPN خاص بالمستخدم (يُطبّق على كل الطلبات الصادرة)
      upstream: { enabled: false, type: 'http', host: '', port: 0, username: '', password: '' },
    },
  };
}

function loadConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
    const cfg = JSON.parse(raw);
    return { ...defaultConfig(), ...cfg, settings: { ...defaultConfig().settings, ...(cfg.settings || {}) } };
  } catch {
    return defaultConfig();
  }
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}

let config = loadConfig();

// ---------------------------------------------------------------------------
// الاتصال عبر البروكسي/VPN (HTTP CONNECT أو SOCKS5)
// ---------------------------------------------------------------------------
function dialDirect(host, port) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(port, host);
    sock.once('connect', () => resolve(sock));
    sock.once('error', reject);
  });
}

function dialHttpProxy(proxy, host, port) {
  return new Promise((resolve, reject) => {
    const conn = net.connect(proxy.port, proxy.host);
    conn.once('error', reject);
    conn.once('connect', () => {
      let head = `CONNECT ${host}:${port} HTTP/1.1\r\nHost: ${host}:${port}\r\n`;
      if (proxy.username) {
        const auth = Buffer.from(`${proxy.username}:${proxy.password || ''}`).toString('base64');
        head += `Proxy-Authorization: Basic ${auth}\r\n`;
      }
      head += 'Connection: keep-alive\r\n\r\n';
      conn.write(head);
    });
    let buf = '';
    const onData = (d) => {
      buf += d.toString('binary');
      if (buf.includes('\r\n\r\n')) {
        conn.removeListener('data', onData);
        const statusLine = buf.split('\r\n')[0] || '';
        if (/\s2\d\d\s/.test(statusLine) || statusLine.includes(' 200 ')) resolve(conn);
        else {
          conn.destroy();
          reject(new Error('HTTP proxy CONNECT رفض: ' + statusLine));
        }
      }
    };
    conn.on('data', onData);
  });
}

function dialSocks5(proxy, host, port) {
  return new Promise((resolve, reject) => {
    const conn = net.connect(proxy.port, proxy.host);
    conn.once('error', reject);
    const useAuth = !!proxy.username;
    conn.once('connect', () => {
      // greeting: VER=5, methods
      conn.write(Buffer.from(useAuth ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]));
    });
    let stage = 'greeting';
    const onData = (data) => {
      if (stage === 'greeting') {
        if (data[0] !== 0x05) return fail('SOCKS5: رد غير صالح');
        const method = data[1];
        if (method === 0x00) return sendConnect();
        if (method === 0x02) {
          stage = 'auth';
          const u = Buffer.from(proxy.username, 'utf8');
          const p = Buffer.from(proxy.password || '', 'utf8');
          conn.write(Buffer.concat([Buffer.from([0x01, u.length]), u, Buffer.from([p.length]), p]));
          return;
        }
        return fail('SOCKS5: طريقة مصادقة غير مدعومة');
      }
      if (stage === 'auth') {
        if (data[1] !== 0x00) return fail('SOCKS5: فشل اسم المستخدم/كلمة المرور');
        return sendConnect();
      }
      if (stage === 'connect') {
        if (data[1] !== 0x00) return fail('SOCKS5: رفض الاتصال (code ' + data[1] + ')');
        conn.removeListener('data', onData);
        resolve(conn);
      }
    };
    function sendConnect() {
      stage = 'connect';
      const hostBuf = Buffer.from(host, 'utf8');
      const head = Buffer.from([0x05, 0x01, 0x00, 0x03, hostBuf.length]);
      const portBuf = Buffer.from([(port >> 8) & 0xff, port & 0xff]);
      conn.write(Buffer.concat([head, hostBuf, portBuf]));
    }
    function fail(msg) {
      conn.destroy();
      reject(new Error(msg));
    }
    conn.on('data', onData);
  });
}

function dial(host, port) {
  const up = config.settings.upstream;
  if (up && up.enabled && up.host && up.port) {
    if (up.type === 'socks5') return dialSocks5(up, host, port);
    return dialHttpProxy(up, host, port);
  }
  return dialDirect(host, port);
}

// ---------------------------------------------------------------------------
// جلب الموارد البعيدة (يدعم البروكسي + HTTPS + التحويلات + Headers مخصّصة)
// ---------------------------------------------------------------------------
function upstreamFetch(targetUrl, opts = {}) {
  const { extraHeaders = {}, redirects = 5, method = 'GET' } = opts;
  return new Promise((resolve, reject) => {
    let u;
    try {
      u = new URL(targetUrl);
    } catch {
      return reject(new Error('رابط غير صالح: ' + targetUrl));
    }
    const isHttps = u.protocol === 'https:';
    const port = Number(u.port) || (isHttps ? 443 : 80);
    const s = config.settings;
    const headers = {
      'User-Agent': s.userAgent || DEFAULT_UA,
      Accept: '*/*',
      ...(s.referer ? { Referer: s.referer } : {}),
      ...extraHeaders,
      Host: u.host,
    };

    dial(u.hostname, port)
      .then((tunnel) => {
        const transport = isHttps ? https : http;
        const reqOptions = {
          method,
          path: (u.pathname || '/') + (u.search || ''),
          headers,
          createConnection: () => {
            if (!isHttps) return tunnel;
            return tls.connect({ socket: tunnel, servername: u.hostname, rejectUnauthorized: false });
          },
        };
        const req = transport.request(reqOptions, (res) => {
          if (
            [301, 302, 303, 307, 308].includes(res.statusCode) &&
            res.headers.location &&
            redirects > 0
          ) {
            res.resume();
            const next = new URL(res.headers.location, targetUrl).toString();
            return resolve(upstreamFetch(next, { ...opts, redirects: redirects - 1 }));
          }
          resolve({ status: res.statusCode, headers: res.headers, stream: res, finalUrl: targetUrl });
        });
        req.on('error', reject);
        req.setTimeout(25000, () => req.destroy(new Error('انتهت مهلة الاتصال')));
        req.end();
      })
      .catch(reject);
  });
}

function fetchText(url, opts = {}) {
  return upstreamFetch(url, opts).then(
    (r) =>
      new Promise((resolve, reject) => {
        if (r.status >= 400) return reject(new Error('HTTP ' + r.status));
        const chunks = [];
        r.stream.on('data', (c) => chunks.push(c));
        r.stream.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
        r.stream.on('error', reject);
      })
  );
}

// ---------------------------------------------------------------------------
// محلّلات القوائم
// ---------------------------------------------------------------------------
function parseM3U(text) {
  const lines = text.split('\n');
  const out = [];
  let cur = null;
  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      const attr = (k) => (line.match(new RegExp(k + '="([^"]*)"', 'i')) || [])[1] || '';
      const name = line.split(',').slice(1).join(',').trim();
      cur = {
        name: name || attr('tvg-name') || 'بدون اسم',
        logo: attr('tvg-logo'),
        category: attr('group-title') || 'غير مصنّف',
      };
    } else if (line && !line.startsWith('#')) {
      if (cur) {
        cur.url = line;
        out.push(cur);
        cur = null;
      }
    }
  }
  return out;
}

function xtreamBase(server) {
  return server.replace(/\/+$/, '');
}

async function xtreamApi(base, username, password, action, extra = '') {
  const url =
    `${base}/player_api.php?username=${encodeURIComponent(username)}` +
    `&password=${encodeURIComponent(password)}&action=${action}${extra}`;
  return JSON.parse(await fetchText(url));
}

// يستورد القنوات المباشرة + الأفلام + المسلسلات دفعة واحدة
async function importXtream(server, username, password) {
  const base = xtreamBase(server);
  const enc = encodeURIComponent;
  const liveUrl = (id) => `${base}/live/${enc(username)}/${enc(password)}/${id}.m3u8`;
  const movieUrl = (id, ext) => `${base}/movie/${enc(username)}/${enc(password)}/${id}.${ext || 'mp4'}`;

  const safe = (action) => xtreamApi(base, username, password, action).catch(() => []);
  const [liveCats, liveStreams, vodCats, vodStreams, serCats, series] = await Promise.all([
    safe('get_live_categories'),
    safe('get_live_streams'),
    safe('get_vod_categories'),
    safe('get_vod_streams'),
    safe('get_series_categories'),
    safe('get_series'),
  ]);

  const cmap = (arr) => Object.fromEntries((arr || []).map((c) => [c.category_id, c.category_name]));
  const lc = cmap(liveCats);
  const vc = cmap(vodCats);
  const sc = cmap(serCats);

  const live = (liveStreams || []).map((s) => ({
    type: 'live',
    name: s.name,
    logo: s.stream_icon || '',
    category: lc[s.category_id] || 'غير مصنّف',
    url: liveUrl(s.stream_id),
  }));
  const movies = (vodStreams || []).map((s) => ({
    type: 'movie',
    name: s.name,
    logo: s.stream_icon || '',
    category: vc[s.category_id] || 'غير مصنّف',
    url: movieUrl(s.stream_id, s.container_extension),
    rating: s.rating || '',
  }));
  const seriesList = (series || []).map((s) => ({
    type: 'series',
    name: s.name,
    logo: s.cover || '',
    category: sc[s.category_id] || 'غير مصنّف',
    seriesId: s.series_id,
    plot: s.plot || '',
  }));
  return { live, movies, series: seriesList };
}

// يجلب مواسم وحلقات مسلسل عند الطلب (lazy)
async function seriesInfo(server, username, password, seriesId) {
  const base = xtreamBase(server);
  const enc = encodeURIComponent;
  const data = await xtreamApi(base, username, password, 'get_series_info', '&series_id=' + seriesId);
  const eps = data.episodes || {};
  const seasons = Object.keys(eps)
    .sort((a, b) => Number(a) - Number(b))
    .map((season) => ({
      season,
      episodes: (eps[season] || []).map((e) => ({
        title: e.title || 'حلقة ' + e.episode_num,
        episode: e.episode_num,
        url: `${base}/series/${enc(username)}/${enc(password)}/${e.id}.${e.container_extension || 'mp4'}`,
      })),
    }));
  return { info: data.info || {}, seasons };
}

// ---------------------------------------------------------------------------
// إعادة كتابة m3u8 لتمرير الأجزاء عبر البروكسي المحلي
// ---------------------------------------------------------------------------
function proxify(absUrl) {
  return '/proxy?u=' + encodeURIComponent(absUrl);
}

function rewriteM3U8(text, baseUrl) {
  return text
    .split('\n')
    .map((raw) => {
      const line = raw.replace(/\r$/, '');
      if (line.startsWith('#')) {
        return line.replace(/URI="([^"]+)"/g, (m, uri) => {
          try {
            return `URI="${proxify(new URL(uri, baseUrl).toString())}"`;
          } catch {
            return m;
          }
        });
      }
      if (!line.trim()) return line;
      try {
        return proxify(new URL(line, baseUrl).toString());
      } catch {
        return line;
      }
    })
    .join('\n');
}

// ---------------------------------------------------------------------------
// مساعدات HTTP
// ---------------------------------------------------------------------------
function sendJSON(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
};

function serveStatic(res, urlPath) {
  let rel = urlPath === '/' ? '/index.html' : urlPath;
  const filePath = path.join(PUBLIC_DIR, path.normalize(rel).replace(/^(\.\.[/\\])+/, ''));
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    return res.end('forbidden');
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      return res.end('not found');
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath)] || 'application/octet-stream' });
    res.end(data);
  });
}

// يجمع محتوى نوع معيّن (live | movies | series) عبر كل المصادر
function collect(kind) {
  const out = [];
  for (const src of config.sources) {
    for (const item of src[kind] || []) out.push({ ...item, source: src.name, sourceId: src.id });
  }
  return out;
}

// عناوين الشبكة المحلية (للوصول من أجهزة أخرى — مثل Jellyfin)
function lanAddresses() {
  const out = [];
  const ifs = os.networkInterfaces();
  for (const name of Object.keys(ifs)) {
    for (const i of ifs[name] || []) {
      if (i.family === 'IPv4' && !i.internal) out.push(i.address);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// الخادم
// ---------------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, `http://${req.headers.host}`);
  const p = u.pathname;

  try {
    // ----- البروكسي / Stream relay -----
    if (p === '/proxy') {
      const target = u.searchParams.get('u');
      if (!target) {
        res.writeHead(400);
        return res.end('missing u');
      }
      // مرّر طلب النطاق (Range) للسماح بالتقديم/الترجيع في الأفلام والمسلسلات
      const range = req.headers['range'];
      const r = await upstreamFetch(target, { extraHeaders: range ? { Range: range } : {} });
      const ct = (r.headers['content-type'] || '').toLowerCase();
      const isPlaylist =
        ct.includes('mpegurl') || /\.m3u8(\?|$)/i.test(target) || ct.includes('application/x-mpegurl');

      res.setHeader('Access-Control-Allow-Origin', '*');

      if (isPlaylist) {
        const chunks = [];
        r.stream.on('data', (c) => chunks.push(c));
        r.stream.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          const rewritten = rewriteM3U8(text, r.finalUrl);
          res.writeHead(200, { 'Content-Type': 'application/vnd.apple.mpegurl; charset=utf-8' });
          res.end(rewritten);
        });
        r.stream.on('error', () => res.end());
        return;
      }

      // أجزاء البث والملفات (ts/m4s/mp4/مفاتيح...) — تمرير مباشر مع دعم Range
      const headers = {
        'Content-Type': r.headers['content-type'] || 'application/octet-stream',
        'Accept-Ranges': 'bytes',
      };
      if (r.headers['content-length']) headers['Content-Length'] = r.headers['content-length'];
      if (r.headers['content-range']) headers['Content-Range'] = r.headers['content-range'];
      res.writeHead(r.status || 200, headers);
      r.stream.pipe(res);
      return;
    }

    // ----- واجهة API -----
    if (p === '/api/state' && req.method === 'GET') {
      return sendJSON(res, 200, {
        sources: config.sources.map((s) => ({
          id: s.id,
          type: s.type,
          name: s.name,
          live: (s.live || []).length,
          movies: (s.movies || []).length,
          series: (s.series || []).length,
        })),
        live: collect('live'),
        movies: collect('movies'),
        series: collect('series'),
        settings: config.settings,
      });
    }

    if (p === '/api/sources' && req.method === 'POST') {
      const body = await readBody(req);
      const id = 's' + Date.now().toString(36);
      const name = (body.name || '').trim() || 'مصدر';
      let live = [];
      let movies = [];
      let series = [];
      if (body.type === 'm3u_url') live = parseM3U(await fetchText(body.url));
      else if (body.type === 'm3u_content') live = parseM3U(body.content || '');
      else if (body.type === 'xtream') {
        const r = await importXtream(body.server, body.username, body.password);
        ({ live, movies, series } = r);
      } else return sendJSON(res, 400, { error: 'نوع مصدر غير معروف' });

      config.sources.push({ id, type: body.type, name, ...body, live, movies, series });
      saveConfig(config);
      return sendJSON(res, 200, { id, live: live.length, movies: movies.length, series: series.length });
    }

    // مواسم/حلقات مسلسل (تُجلب عند الطلب)
    if (p === '/api/series-info' && req.method === 'GET') {
      const src = config.sources.find((s) => s.id === u.searchParams.get('sourceId'));
      if (!src) return sendJSON(res, 404, { error: 'المصدر غير موجود' });
      const info = await seriesInfo(src.server, src.username, src.password, u.searchParams.get('seriesId'));
      return sendJSON(res, 200, info);
    }

    // معلومات الشبكة (للوصول من أجهزة أخرى مثل Jellyfin)
    if (p === '/api/netinfo' && req.method === 'GET') {
      return sendJSON(res, 200, { addresses: lanAddresses(), port: PORT });
    }

    if (p === '/api/sources' && req.method === 'DELETE') {
      const id = u.searchParams.get('id');
      config.sources = config.sources.filter((s) => s.id !== id);
      saveConfig(config);
      return sendJSON(res, 200, { ok: true });
    }

    if (p === '/api/settings' && req.method === 'POST') {
      const body = await readBody(req);
      config.settings = {
        ...config.settings,
        ...body,
        upstream: { ...config.settings.upstream, ...(body.upstream || {}) },
      };
      saveConfig(config);
      return sendJSON(res, 200, { ok: true, settings: config.settings });
    }

    // اختبار اتصال البروكسي/VPN
    if (p === '/api/test-upstream' && req.method === 'GET') {
      try {
        const txt = await fetchText('https://api.ipify.org?format=json');
        return sendJSON(res, 200, { ok: true, ip: JSON.parse(txt).ip });
      } catch (e) {
        return sendJSON(res, 200, { ok: false, error: e.message });
      }
    }

    // ----- ملفات ثابتة -----
    return serveStatic(res, p);
  } catch (err) {
    sendJSON(res, 500, { error: err.message });
  }
});

server.keepAliveTimeout = 60_000;
server.requestTimeout = 0;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n  ▶  IPTV Pro Desktop يعمل الآن`);
  console.log(`     على هذا الجهاز:      http://localhost:${PORT}`);
  for (const ip of lanAddresses()) {
    console.log(`     من أجهزة الشبكة:     http://${ip}:${PORT}   ← افتحه على التلفزيون/الجوال (مثل Jellyfin)`);
  }
  console.log('');
});
