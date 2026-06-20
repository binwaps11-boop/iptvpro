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
 * التشغيل:  node server.js   ثم افتح  http://localhost:2222
 */

import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import fs from 'node:fs';
import os from 'node:os';
import crypto from 'node:crypto';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, 'public');
const CONFIG_PATH = process.env.CONFIG_DIR
  ? path.join(process.env.CONFIG_DIR, 'config.json')
  : path.join(__dirname, 'config.json');
// منفذان منفصلان: العملاء على USER_PORT (221) والإدارة على ADMIN_PORT (331)
const USER_PORT = process.env.USER_PORT || process.env.PORT || 221;
const ADMIN_PORT = process.env.ADMIN_PORT || 331;

// حدود الذاكرة المؤقتة المشتركة (Shared Relay)
const PLAYLIST_TTL = 1500; // ms — مدة صلاحية قائمة البث المشتركة
const MAX_CACHE_BYTES = 512 * 1024 * 1024; // سقف ذاكرة الأجزاء
const MAX_SEG_BYTES = 24 * 1024 * 1024; // أكبر جزء يُخزَّن
const VIEWER_TTL = 45000; // اعتبار الجهاز نشطاً خلال هذه المدة

// توجيه المكسيك (WireGuard) المُدار من اللوحة
const VPN_SCRIPT = path.join(__dirname, 'deploy', 'vpn-apply.sh');
const VPN_CONF = process.env.CONFIG_DIR
  ? path.join(process.env.CONFIG_DIR, 'mx.conf')
  : path.join(__dirname, 'mx.conf');

// يشغّل مساعد الـ VPN عبر sudo ويعيد JSON
function runVpn(action) {
  return new Promise((resolve) => {
    execFile('sudo', ['-n', VPN_SCRIPT, action], { timeout: 35000 }, (err, stdout) => {
      try {
        resolve(JSON.parse((stdout || '').trim() || '{}'));
      } catch {
        resolve({ ok: false, error: (stdout || (err && err.message) || 'فشل').toString().slice(0, 200) });
      }
    });
  });
}

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
    activation: null, // {serial, activatedAt}
    auth: null, // {admin:{username,salt,hash}, sessionSecret}
    clients: [], // حسابات العملاء (تُنشأ من لوحة الإدارة)
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
  fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}

let config = loadConfig();

// ---------------------------------------------------------------------------
// المصادقة والأدوار (Admin / عميل) — تهيئة أولية
// ---------------------------------------------------------------------------
function hashPassword(pw, salt = crypto.randomBytes(16).toString('hex')) {
  const hash = crypto.scryptSync(String(pw), salt, 64).toString('hex');
  return { salt, hash };
}
function checkPassword(pw, salt, hash) {
  try {
    const h = crypto.scryptSync(String(pw), salt, 64).toString('hex');
    return crypto.timingSafeEqual(Buffer.from(h), Buffer.from(hash));
  } catch {
    return false;
  }
}

// تهيئة حساب المدير ومفتاح الجلسات عند أول تشغيل
function ensureAuth() {
  if (!config.auth) config.auth = {};
  if (!config.auth.sessionSecret) config.auth.sessionSecret = crypto.randomBytes(32).toString('hex');
  if (!config.auth.admin) {
    const username = process.env.ADMIN_USER || 'admin';
    const password = process.env.ADMIN_PASSWORD || 'admin';
    config.auth.admin = { username, ...hashPassword(password) };
    config.auth.mustChangePassword = !process.env.ADMIN_PASSWORD;
    saveConfig(config);
    if (config.auth.mustChangePassword)
      console.log(
        `\n  ⚠️  حساب المدير الافتراضي:  المستخدم="${username}"  كلمة المرور="${password}"\n` +
          `      غيّرها فوراً من لوحة الإدارة، أو شغّل بمتغيّر ADMIN_PASSWORD.\n`
      );
    else console.log(`\n  ✅ حساب المدير "${username}" جاهز (كلمة المرور من ADMIN_PASSWORD).\n`);
  } else {
    saveConfig(config);
  }
}
ensureAuth();

// جلسات موقّعة (cookie) بلا حالة على الخادم
function signSession(payload) {
  const p = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', config.auth.sessionSecret).update(p).digest('base64url');
  return p + '.' + sig;
}
function verifySession(token) {
  if (!token || !token.includes('.')) return null;
  const [p, sig] = token.split('.');
  const expect = crypto.createHmac('sha256', config.auth.sessionSecret).update(p).digest('base64url');
  try {
    if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expect))) return null;
    const data = JSON.parse(Buffer.from(p, 'base64url').toString('utf8'));
    if (data.exp && Date.now() > data.exp) return null;
    return data;
  } catch {
    return null;
  }
}
function parseCookies(req) {
  const out = {};
  const raw = req.headers.cookie || '';
  for (const part of raw.split(';')) {
    const i = part.indexOf('=');
    if (i > -1) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}
// يعيد {role, uid, username, client?} أو null
function getSession(req) {
  const s = verifySession(parseCookies(req).sid);
  if (!s) return null;
  if (s.role === 'admin') return s;
  const client = (config.clients || []).find((c) => c.id === s.uid);
  if (!client || client.disabled) return null;
  if (client.expiry && Date.now() > client.expiry) return null;
  return { ...s, client };
}

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

// يحدّد البروكسي المستخدم: صريح (opts.proxy) أو بلا (opts.noProxy) أو العام من الإعدادات
function resolveProxy(opts = {}) {
  if (opts.proxy) return opts.proxy;
  if (opts.noProxy) return null;
  const up = config.settings.upstream;
  return up && up.enabled && up.host && up.port ? up : null;
}

function dial(host, port, proxy) {
  if (proxy && proxy.host && proxy.port) {
    if (proxy.type === 'socks5') return dialSocks5(proxy, host, port);
    return dialHttpProxy(proxy, host, port);
  }
  return dialDirect(host, port);
}

// ---------------------------------------------------------------------------
// جلب الموارد البعيدة (يدعم البروكسي + HTTPS + التحويلات + Headers مخصّصة)
// ---------------------------------------------------------------------------
function upstreamFetch(targetUrl, opts = {}) {
  const { extraHeaders = {}, redirects = 5, method = 'GET', timeout = 25000 } = opts;
  const proxy = resolveProxy(opts);
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

    dial(u.hostname, port, proxy)
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
        req.setTimeout(timeout, () => req.destroy(new Error('انتهت مهلة الاتصال')));
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

function fetchBuffer(url, opts = {}) {
  return upstreamFetch(url, opts).then(
    (r) =>
      new Promise((resolve, reject) => {
        const chunks = [];
        r.stream.on('data', (c) => chunks.push(c));
        r.stream.on('end', () =>
          resolve({
            buf: Buffer.concat(chunks),
            ct: r.headers['content-type'] || 'application/octet-stream',
            status: r.status,
            finalUrl: r.finalUrl,
          })
        );
        r.stream.on('error', reject);
      })
  );
}

// ---------------------------------------------------------------------------
// محرّك Relay المشترك — يخدم آلاف الأجهزة على نفس القناة من سحبة واحدة
// (تخزين مؤقت للأجزاء + دمج الطلبات المتزامنة Coalescing) — مثل Jellyfin
// ---------------------------------------------------------------------------
const segCache = new Map(); // url -> {buf, ct, size, last}
const segInflight = new Map(); // url -> Promise (دمج الطلبات المتطابقة)
const plCache = new Map(); // url -> {text, finalUrl, ts}
const plInflight = new Map();
let cacheBytes = 0;

function evictIfNeeded() {
  if (cacheBytes <= MAX_CACHE_BYTES) return;
  const entries = [...segCache.entries()].sort((a, b) => a[1].last - b[1].last);
  for (const [k, v] of entries) {
    segCache.delete(k);
    cacheBytes -= v.size;
    if (cacheBytes <= MAX_CACHE_BYTES * 0.8) break;
  }
}

// جزء بثّ مشترك: يُسحب مرة واحدة مهما كثُر الطالبون له في نفس اللحظة
async function getSharedSegment(url) {
  const hit = segCache.get(url);
  if (hit) {
    hit.last = Date.now();
    return hit;
  }
  if (segInflight.has(url)) return segInflight.get(url);
  const promise = (async () => {
    const { buf, ct } = await fetchBuffer(url);
    const entry = { buf, ct, size: buf.length, last: Date.now() };
    if (buf.length <= MAX_SEG_BYTES) {
      segCache.set(url, entry);
      cacheBytes += buf.length;
      evictIfNeeded();
    }
    return entry;
  })();
  segInflight.set(url, promise);
  try {
    return await promise;
  } finally {
    segInflight.delete(url);
  }
}

// قائمة بث حيّة مشتركة بمهلة قصيرة: 2000 جهاز = طلب واحد للمزوّد كل ~1.5ث
async function getSharedPlaylist(url) {
  const hit = plCache.get(url);
  if (hit && Date.now() - hit.ts < PLAYLIST_TTL) return hit;
  if (plInflight.has(url)) return plInflight.get(url);
  const promise = (async () => {
    const { buf, finalUrl } = await fetchBuffer(url);
    const entry = { text: buf.toString('utf8'), finalUrl: finalUrl || url, ts: Date.now() };
    plCache.set(url, entry);
    return entry;
  })();
  plInflight.set(url, promise);
  try {
    return await promise;
  } finally {
    plInflight.delete(url);
  }
}

// ---------------------------------------------------------------------------
// تتبّع الأجهزة المشاهِدة (للحد الأقصى حسب الترخيص + عرض العدّاد)
// ---------------------------------------------------------------------------
const viewers = new Map(); // cid -> {uid, username, ip, last, channel}

function pruneViewers() {
  const now = Date.now();
  for (const [cid, v] of viewers) if (now - v.last > VIEWER_TTL) viewers.delete(cid);
}
function activeViewerCount() {
  pruneViewers();
  return viewers.size;
}
// عدد الأجهزة النشطة لعميل واحد (للتحقق من حدّه الخاص)
function activeForUser(uid) {
  pruneViewers();
  let n = 0;
  for (const v of viewers.values()) if (v.uid === uid) n++;
  return n;
}
function touchViewer(cid, info) {
  const prev = viewers.get(cid) || {};
  viewers.set(cid, { ...prev, ...info, last: Date.now() });
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

// ---------------------------------------------------------------------------
// بحث تلقائي عن بروكسي مكسيكي مجاني واختباره ضد المزوّد (بدون أي إعداد من المستخدم)
// المصدر: ProxyScrape (قوائم مجانية محدّثة، تصفية حسب الدولة)
// ---------------------------------------------------------------------------
async function fetchFreeMexicanProxies() {
  const urls = [
    'https://api.proxyscrape.com/v4/free-proxy-list/get?request=display_proxies&proxy_format=protocolipport&format=text&country=mx&protocol=socks5',
    'https://api.proxyscrape.com/v4/free-proxy-list/get?request=display_proxies&proxy_format=protocolipport&format=text&country=mx&protocol=http',
  ];
  const proxies = [];
  const seen = new Set();
  for (const url of urls) {
    try {
      const txt = await fetchText(url, { noProxy: true, timeout: 15000 });
      for (const raw of txt.split(/\s+/)) {
        const m = /^(socks5|http|https):\/\/([\d.]+):(\d+)$/i.exec(raw.trim());
        if (!m) continue;
        const proxy = { type: m[1].toLowerCase() === 'socks5' ? 'socks5' : 'http', host: m[2], port: Number(m[3]) };
        const k = proxy.type + proxy.host + proxy.port;
        if (!seen.has(k)) { seen.add(k); proxies.push(proxy); }
      }
    } catch {}
  }
  return proxies;
}

async function autoFindMexicanProxy() {
  const proxies = await fetchFreeMexicanProxies();
  if (!proxies.length) return { ok: false, error: 'تعذّر جلب قائمة البروكسيات المجانية', total: 0 };

  // هدف الاختبار: مزوّد المستخدم إن وُجد (الأدق)، وإلا فحص أن الخروج من المكسيك
  const src = config.sources.find((s) => s.type === 'xtream');
  const testUrl = src
    ? `${xtreamBase(src.server)}/player_api.php?username=${encodeURIComponent(src.username)}&password=${encodeURIComponent(src.password)}`
    : 'https://ifconfig.co/country';

  const isGood = async (proxy) => {
    try {
      const txt = await fetchText(testUrl, { proxy, timeout: 9000, redirects: 3 });
      return src ? /"user_info"|"auth"\s*:/.test(txt) : /mexico/i.test(txt);
    } catch {
      return false;
    }
  };

  // اختبار متوازٍ بميزانية وقت، يتوقّف عند أول بروكسي ناجح
  const start = Date.now();
  const budget = 48000;
  const concurrency = 14;
  let idx = 0;
  let found = null;
  const list = proxies.slice(0, 80);
  async function worker() {
    while (idx < list.length && !found && Date.now() - start < budget) {
      const proxy = list[idx++];
      if (await isGood(proxy)) found = proxy;
    }
  }
  await Promise.all(Array.from({ length: concurrency }, () => worker()));
  if (found) return { ok: true, proxy: found, total: proxies.length };
  return { ok: false, error: 'لم يُعثر على بروكسي مكسيكي مجاني يعمل حالياً', total: proxies.length };
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
// الخادم — يستمع على منفذين: العملاء (USER_PORT) والإدارة (ADMIN_PORT)
// ---------------------------------------------------------------------------
const requestHandler = async (req, res) => {
  const u = new URL(req.url, `http://${req.headers.host}`);
  const p = u.pathname;
  const session = getSession(req);
  const isAdmin = session && session.role === 'admin';
  const onAdminPort = req.socket.localPort === Number(ADMIN_PORT);

  try {
    // فصل المنافذ: لوحة الإدارة وأصولها متاحة فقط عبر منفذ الإدارة
    const adminOnly = /^\/admin(\.html|\.js)?$/.test(p);
    if (adminOnly && !onAdminPort) {
      res.writeHead(302, { Location: '/' });
      return res.end();
    }
    if (p === '/' && onAdminPort) {
      // منفذ الإدارة: الجذر يوجّه إلى اللوحة
      res.writeHead(302, { Location: '/admin' });
      return res.end();
    }
    // ----- البروكسي / Shared Relay (يتطلب جلسة مسجّلة) -----
    if (p === '/proxy') {
      if (!session) {
        res.writeHead(401);
        return res.end('unauthorized');
      }
      const target = u.searchParams.get('u');
      if (!target) {
        res.writeHead(400);
        return res.end('missing u');
      }
      res.setHeader('Access-Control-Allow-Origin', '*');
      const range = req.headers['range'];
      const isPlaylist = /\.m3u8(\?|$)/i.test(target);
      const clientIp = req.socket.remoteAddress;

      // قائمة بث حيّة: ذاكرة مشتركة + فرض حدّ أجهزة العميل عند بدء قناة جديدة
      if (isPlaylist && !range) {
        const cid = u.searchParams.get('cid');
        if (cid && session.role === 'client') {
          const cap = session.client.maxDevices || 0;
          const isNew = !viewers.has(cid);
          if (cap > 0 && isNew && activeForUser(session.uid) >= cap) {
            res.writeHead(429, { 'Content-Type': 'application/json; charset=utf-8' });
            return res.end(
              JSON.stringify({ error: `بلغت الحد الأقصى للأجهزة في اشتراكك (${cap}).` })
            );
          }
        }
        if (cid)
          touchViewer(cid, { uid: session.uid, username: session.username, ip: clientIp, channel: target });
        const pl = await getSharedPlaylist(target);
        res.writeHead(200, { 'Content-Type': 'application/vnd.apple.mpegurl; charset=utf-8' });
        return res.end(rewriteM3U8(pl.text, pl.finalUrl));
      }

      // أجزاء البث بدون Range: تُسحب مرة واحدة وتُوزَّع على كل الأجهزة (anti-stutter)
      if (!range) {
        try {
          const seg = await getSharedSegment(target);
          // قد يكون المحتوى قائمة فرعية (variant) — أعِد كتابته
          const ctl = (seg.ct || '').toLowerCase();
          if (ctl.includes('mpegurl') || ctl.includes('application/x-mpegurl')) {
            res.writeHead(200, { 'Content-Type': 'application/vnd.apple.mpegurl; charset=utf-8' });
            return res.end(rewriteM3U8(seg.buf.toString('utf8'), target));
          }
          res.writeHead(200, {
            'Content-Type': seg.ct,
            'Content-Length': seg.buf.length,
            'Cache-Control': 'public, max-age=30',
          });
          return res.end(seg.buf);
        } catch (e) {
          res.writeHead(502);
          return res.end('upstream error');
        }
      }

      // طلبات Range (أفلام/مسلسلات للتقديم) — تمرير مباشر دون تخزين
      const r = await upstreamFetch(target, { extraHeaders: { Range: range } });
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

    // ----- المصادقة -----
    if (p === '/api/login' && req.method === 'POST') {
      const body = await readBody(req);
      const username = (body.username || '').trim();
      const password = body.password || '';
      // مدير؟
      const a = config.auth.admin;
      if (a && a.username === username && checkPassword(password, a.salt, a.hash)) {
        const token = signSession({ role: 'admin', uid: 'admin', username, exp: Date.now() + 7 * 86400000 });
        res.setHeader('Set-Cookie', `sid=${token}; HttpOnly; Path=/; Max-Age=604800; SameSite=Lax`);
        return sendJSON(res, 200, { ok: true, role: 'admin', mustChangePassword: !!config.auth.mustChangePassword });
      }
      // عميل؟
      const c = (config.clients || []).find((x) => x.username === username);
      if (c && !c.disabled && checkPassword(password, c.salt, c.hash)) {
        if (c.expiry && Date.now() > c.expiry) return sendJSON(res, 403, { error: 'انتهى اشتراكك' });
        const token = signSession({ role: 'client', uid: c.id, username, exp: Date.now() + 7 * 86400000 });
        res.setHeader('Set-Cookie', `sid=${token}; HttpOnly; Path=/; Max-Age=604800; SameSite=Lax`);
        return sendJSON(res, 200, { ok: true, role: 'client' });
      }
      return sendJSON(res, 401, { error: 'بيانات الدخول غير صحيحة' });
    }

    if (p === '/api/logout' && req.method === 'POST') {
      res.setHeader('Set-Cookie', 'sid=; HttpOnly; Path=/; Max-Age=0');
      return sendJSON(res, 200, { ok: true });
    }

    if (p === '/api/me' && req.method === 'GET') {
      if (!session) return sendJSON(res, 200, { authenticated: false });
      const me = { authenticated: true, role: session.role, username: session.username };
      if (session.role === 'client') {
        me.name = session.client.name || session.username;
        me.maxDevices = session.client.maxDevices || 0;
        me.expiry = session.client.expiry || 0;
        me.daysLeft = session.client.expiry
          ? Math.max(0, Math.ceil((session.client.expiry - Date.now()) / 86400000))
          : 0;
      } else {
        me.mustChangePassword = !!config.auth.mustChangePassword;
      }
      return sendJSON(res, 200, me);
    }

    // ----- واجهة المحتوى (تتطلب جلسة) -----
    if (p === '/api/state' && req.method === 'GET') {
      if (!session) return sendJSON(res, 401, { error: 'يجب تسجيل الدخول' });
      const payload = {
        live: collect('live'),
        movies: collect('movies'),
        series: collect('series'),
      };
      if (isAdmin) {
        payload.sources = config.sources.map((s) => ({
          id: s.id,
          type: s.type,
          name: s.name,
          live: (s.live || []).length,
          movies: (s.movies || []).length,
          series: (s.series || []).length,
        }));
        payload.settings = config.settings;
      }
      return sendJSON(res, 200, payload);
    }

    if (p === '/api/sources' && req.method === 'POST') {
      if (!isAdmin) return sendJSON(res, 403, { error: 'للمدير فقط' });
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

    // مواسم/حلقات مسلسل (تُجلب عند الطلب) — لأي مستخدم مسجّل
    if (p === '/api/series-info' && req.method === 'GET') {
      if (!session) return sendJSON(res, 401, { error: 'يجب تسجيل الدخول' });
      const src = config.sources.find((s) => s.id === u.searchParams.get('sourceId'));
      if (!src) return sendJSON(res, 404, { error: 'المصدر غير موجود' });
      const info = await seriesInfo(src.server, src.username, src.password, u.searchParams.get('seriesId'));
      return sendJSON(res, 200, info);
    }

    // نبضة إبقاء الجهاز نشطاً (heartbeat) — لأي مستخدم مسجّل
    if (p === '/api/ping' && req.method === 'POST') {
      if (!session) return sendJSON(res, 401, { ok: false, error: 'يجب تسجيل الدخول' });
      const body = await readBody(req);
      if (body.cid) {
        if (session.role === 'client') {
          const cap = session.client.maxDevices || 0;
          if (cap > 0 && !viewers.has(body.cid) && activeForUser(session.uid) >= cap)
            return sendJSON(res, 429, { ok: false, error: 'بلغت الحد الأقصى للأجهزة', cap });
        }
        touchViewer(body.cid, {
          uid: session.uid,
          username: session.username,
          ip: req.socket.remoteAddress,
          channel: body.channel,
        });
      }
      const active =
        session.role === 'client' ? activeForUser(session.uid) : activeViewerCount();
      const cap = session.role === 'client' ? session.client.maxDevices || 0 : 0;
      return sendJSON(res, 200, { ok: true, active, cap });
    }

    // ========== نقاط للمدير فقط ==========
    if (p.startsWith('/api/admin/') || p === '/api/netinfo' || p === '/api/test-upstream' ||
        (p === '/api/sources' && req.method === 'DELETE') ||
        (p === '/api/settings' && req.method === 'POST') ||
        (p === '/api/clients')) {
      if (!isAdmin) return sendJSON(res, 403, { error: 'للمدير فقط' });
    }

    // معلومات الشبكة
    if (p === '/api/netinfo' && req.method === 'GET') {
      return sendJSON(res, 200, { addresses: lanAddresses(), port: USER_PORT, adminPort: ADMIN_PORT });
    }

    // ----- توجيه المكسيك (VPN) من اللوحة -----
    if (p === '/api/admin/vpn' && req.method === 'GET') {
      return sendJSON(res, 200, await runVpn('status'));
    }
    if (p === '/api/admin/vpn' && req.method === 'POST') {
      const body = await readBody(req);
      const cfg = (body.config || '').trim();
      if (!/\[Interface\]/i.test(cfg) || !/\[Peer\]/i.test(cfg))
        return sendJSON(res, 400, { ok: false, error: 'إعداد WireGuard غير صالح (يجب أن يحتوي [Interface] و[Peer]).' });
      try {
        fs.writeFileSync(VPN_CONF, cfg + '\n', { mode: 0o600 });
      } catch (e) {
        return sendJSON(res, 500, { ok: false, error: 'تعذّر حفظ الإعداد: ' + e.message });
      }
      return sendJSON(res, 200, await runVpn('up'));
    }
    if (p === '/api/admin/vpn/down' && req.method === 'POST') {
      return sendJSON(res, 200, await runVpn('down'));
    }

    // بحث تلقائي عن بروكسي مكسيكي مجاني وتفعيله (بدون أي إعداد من المستخدم)
    if (p === '/api/admin/autoproxy' && req.method === 'POST') {
      const r = await autoFindMexicanProxy();
      if (r.ok) {
        config.settings.upstream = {
          enabled: true,
          type: r.proxy.type,
          host: r.proxy.host,
          port: r.proxy.port,
          username: '',
          password: '',
        };
        saveConfig(config);
        return sendJSON(res, 200, { ok: true, proxy: r.proxy, total: r.total });
      }
      return sendJSON(res, 200, { ok: false, error: r.error, total: r.total });
    }

    // إحصائيات المشاهدين (للمدير)
    if (p === '/api/admin/viewers' && req.method === 'GET') {
      pruneViewers();
      const list = [...viewers.values()].map((v) => ({ username: v.username, ip: v.ip, channel: v.channel }));
      return sendJSON(res, 200, { active: list.length, viewers: list });
    }

    // إدارة العملاء (Admin)
    if (p === '/api/clients' && req.method === 'GET') {
      const now = Date.now();
      return sendJSON(res, 200, {
        clients: (config.clients || []).map((c) => ({
          id: c.id,
          username: c.username,
          name: c.name || '',
          maxDevices: c.maxDevices || 0,
          expiry: c.expiry || 0,
          daysLeft: c.expiry ? Math.max(0, Math.ceil((c.expiry - now) / 86400000)) : 0,
          disabled: !!c.disabled,
          active: activeForUser(c.id),
        })),
      });
    }

    if (p === '/api/clients' && req.method === 'POST') {
      const body = await readBody(req);
      const username = (body.username || '').trim();
      if (!username || !body.password) return sendJSON(res, 400, { error: 'اسم المستخدم وكلمة المرور مطلوبان' });
      if ((config.clients || []).some((c) => c.username === username))
        return sendJSON(res, 400, { error: 'اسم المستخدم موجود مسبقاً' });
      const days = Number(body.days || 0);
      const client = {
        id: 'c' + Date.now().toString(36),
        username,
        name: body.name || username,
        ...hashPassword(body.password),
        maxDevices: Number(body.maxDevices || 0),
        expiry: days > 0 ? Date.now() + days * 86400000 : 0,
        disabled: false,
        createdAt: Date.now(),
      };
      config.clients = config.clients || [];
      config.clients.push(client);
      saveConfig(config);
      return sendJSON(res, 200, { ok: true, id: client.id });
    }

    if (p === '/api/clients' && req.method === 'DELETE') {
      const id = u.searchParams.get('id');
      config.clients = (config.clients || []).filter((c) => c.id !== id);
      saveConfig(config);
      return sendJSON(res, 200, { ok: true });
    }

    // تعديل عميل (تعطيل/تفعيل، تجديد، حد الأجهزة، كلمة المرور)
    if (p === '/api/clients/update' && req.method === 'POST') {
      if (!isAdmin) return sendJSON(res, 403, { error: 'للمدير فقط' });
      const body = await readBody(req);
      const c = (config.clients || []).find((x) => x.id === body.id);
      if (!c) return sendJSON(res, 404, { error: 'العميل غير موجود' });
      if (body.disabled !== undefined) c.disabled = !!body.disabled;
      if (body.maxDevices !== undefined) c.maxDevices = Number(body.maxDevices);
      if (body.addDays) c.expiry = (c.expiry && c.expiry > Date.now() ? c.expiry : Date.now()) + Number(body.addDays) * 86400000;
      if (body.password) Object.assign(c, hashPassword(body.password));
      saveConfig(config);
      return sendJSON(res, 200, { ok: true });
    }

    // تغيير كلمة مرور المدير
    if (p === '/api/admin/password' && req.method === 'POST') {
      const body = await readBody(req);
      if (!body.password || String(body.password).length < 4)
        return sendJSON(res, 400, { error: 'كلمة المرور قصيرة' });
      config.auth.admin = { username: config.auth.admin.username, ...hashPassword(body.password) };
      config.auth.mustChangePassword = false;
      saveConfig(config);
      return sendJSON(res, 200, { ok: true });
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

    if (p === '/api/test-upstream' && req.method === 'GET') {
      try {
        const txt = await fetchText('https://api.ipify.org?format=json');
        return sendJSON(res, 200, { ok: true, ip: JSON.parse(txt).ip });
      } catch (e) {
        return sendJSON(res, 200, { ok: false, error: e.message });
      }
    }

    // ----- صفحات وملفات ثابتة -----
    if (p === '/login') return serveStatic(res, '/login.html');
    // حماية صفحة الإدارة: تتطلب جلسة مدير
    if (p === '/admin' || p === '/admin.html') {
      if (!isAdmin) {
        res.writeHead(302, { Location: '/login?next=/admin' });
        return res.end();
      }
      return serveStatic(res, '/admin.html');
    }
    return serveStatic(res, p);
  } catch (err) {
    sendJSON(res, 500, { error: err.message });
  }
};

function startServer(port, label) {
  const srv = http.createServer(requestHandler);
  srv.keepAliveTimeout = 60_000;
  srv.requestTimeout = 0;
  srv.on('error', (e) => {
    if (e.code === 'EACCES')
      console.error(`\n  ✗ المنفذ ${port} محجوز (<1024) ويتطلب صلاحية root أو CAP_NET_BIND_SERVICE — راجع deploy/install.sh\n`);
    else console.error(`\n  ✗ تعذّر الاستماع على المنفذ ${port}: ${e.message}\n`);
    process.exit(1);
  });
  srv.listen(port, '0.0.0.0', () => {
    const ips = lanAddresses();
    const host = ips[0] ? `http://${ips[0]}:${port}` : `http://localhost:${port}`;
    console.log(`  ▶  ${label}:  ${host}`);
  });
  return srv;
}

console.log(`\n  IPTV Pro Server يعمل الآن`);
startServer(USER_PORT, 'بوابة العملاء  ');
if (Number(ADMIN_PORT) !== Number(USER_PORT)) startServer(ADMIN_PORT, 'لوحة الإدارة /admin');
console.log(`  Shared Relay مفعّل: نفس القناة تُسحب مرة واحدة وتُوزَّع على كل الأجهزة\n`);
