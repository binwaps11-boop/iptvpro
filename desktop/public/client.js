// ===== بوابة العميل — مشاهدة فقط =====
let STATE = { live: [], movies: [], series: [] };
let view = 'live';
let activeCat = '__all__';
let hls = null;
let currentChannel = null;

const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];

const CID = (() => {
  let c = localStorage.getItem('cid');
  if (!c) { c = 'd-' + Math.random().toString(36).slice(2) + Date.now().toString(36); localStorage.setItem('cid', c); }
  return c;
})();

function toast(msg, ms = 2500) {
  const t = $('#toast');
  t.textContent = msg; t.classList.remove('hidden');
  clearTimeout(t._t); t._t = setTimeout(() => t.classList.add('hidden'), ms);
}
function escapeHtml(s = '') {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}
window.ph = () => { const s = document.createElement('span'); s.className = 'ph'; s.textContent = '📺'; return s; };
const currentList = () => STATE[view] || [];

// ===== التهيئة =====
async function init() {
  const me = await fetch('/api/me').then((r) => r.json());
  if (!me.authenticated) { location.href = '/login'; return; }
  if (me.role === 'admin') $('#adminLink').classList.remove('hidden');
  const info = me.role === 'client'
    ? `👤 ${escapeHtml(me.name || me.username)}${me.daysLeft ? ' · ' + me.daysLeft + ' يوم' : ''}`
    : '👑 مدير';
  $('#userinfo').textContent = info;
  await loadState();
  bind();
  setInterval(() => { if (currentChannel) sendPing(); }, 12000);
}

async function loadState() {
  STATE = await fetch('/api/state').then((r) => r.json());
  renderTabs(); renderCats(); renderGrid();
}

function renderTabs() {
  $$('.ctab').forEach((b) => {
    const count = (STATE[b.dataset.view] || []).length;
    b.classList.toggle('active', b.dataset.view === view);
    const base = { live: '📡 المباشر', movies: '🎬 الأفلام', series: '📺 المسلسلات' }[b.dataset.view];
    b.textContent = `${base} (${count})`;
  });
}

function categories() {
  const m = new Map();
  for (const c of currentList()) m.set(c.category, (m.get(c.category) || 0) + 1);
  return [...m.entries()].sort((a, b) => b[1] - a[1]);
}
function renderCats() {
  const nav = $('#cats'); nav.innerHTML = '';
  const mk = (key, label) => {
    const el = document.createElement('button');
    el.className = 'chip' + (activeCat === key ? ' active' : '');
    el.textContent = label;
    el.onclick = () => { activeCat = key; renderCats(); renderGrid(); };
    nav.appendChild(el);
  };
  mk('__all__', `الكل (${currentList().length})`);
  for (const [name, n] of categories()) mk(name, `${name} (${n})`);
}

function renderGrid() {
  const q = $('#search').value.trim().toLowerCase();
  let list = currentList();
  if (activeCat !== '__all__') list = list.filter((c) => c.category === activeCat);
  if (q) list = list.filter((c) => (c.name || '').toLowerCase().includes(q));
  const grid = $('#grid');
  $('#empty').classList.toggle('hidden', currentList().length > 0);
  grid.innerHTML = '';
  list.slice(0, 600).forEach((item) => {
    const card = document.createElement('div');
    card.className = 'card';
    card.innerHTML = `<div class="thumb">${
      item.logo ? `<img src="${item.logo}" loading="lazy" onerror="this.replaceWith(ph())">` : '<span class="ph">📺</span>'
    }</div><div class="name">${escapeHtml(item.name)}</div><div class="cat">${escapeHtml(item.category)}</div>`;
    card.onclick = () => (item.type === 'series' ? openSeries(item) : play(item));
    grid.appendChild(card);
  });
}

// ===== المسلسلات =====
async function openSeries(item) {
  $('#seriesTitle').textContent = item.name;
  $('#seriesBody').innerHTML = 'جارٍ تحميل الحلقات…';
  $('#seriesModal').classList.remove('hidden');
  try {
    const data = await fetch(`/api/series-info?sourceId=${item.sourceId}&seriesId=${item.seriesId}`).then((r) => r.json());
    if (data.error) throw new Error(data.error);
    const box = $('#seriesBody'); box.innerHTML = '';
    if (!data.seasons.length) { box.innerHTML = 'لا توجد حلقات.'; return; }
    data.seasons.forEach((s) => {
      const h = document.createElement('div'); h.className = 'season-h'; h.textContent = `الموسم ${s.season}`;
      box.appendChild(h);
      s.episodes.forEach((ep) => {
        const row = document.createElement('div'); row.className = 'ep';
        row.innerHTML = `<span>${escapeHtml(ep.title)}</span><span class="play">▶ تشغيل</span>`;
        row.onclick = () => { $('#seriesModal').classList.add('hidden'); play({ name: `${item.name} — ${ep.title}`, url: ep.url, type: 'movie' }); };
        box.appendChild(row);
      });
    });
  } catch (e) { $('#seriesBody').innerHTML = 'تعذّر تحميل الحلقات: ' + escapeHtml(e.message); }
}

// ===== التشغيل =====
function streamUrl(item) {
  const live = item.type === 'live' || /\.m3u8(\?|$)/i.test(item.url) || /\/live\//.test(item.url);
  return '/proxy?u=' + encodeURIComponent(item.url) + (live ? '&cid=' + encodeURIComponent(CID) : '');
}
function buildQualityMenu() {
  const sel = $('#quality'); sel.innerHTML = '<option value="-1">جودة: تلقائي</option>';
  if (!hls || !hls.levels) return;
  hls.levels.forEach((lvl, i) => {
    const h = lvl.height ? lvl.height + 'p' : Math.round((lvl.bitrate || 0) / 1000) + 'k';
    const o = document.createElement('option'); o.value = i; o.textContent = 'جودة: ' + h; sel.appendChild(o);
  });
  sel.onchange = () => { if (hls) hls.currentLevel = Number(sel.value); };
}
function play(item) {
  const video = $('#video');
  currentChannel = item.name;
  const url = streamUrl(item);
  const live = item.type === 'live' || /\.m3u8(\?|$)/i.test(item.url) || /\/live\//.test(item.url);
  $('#nowPlaying').textContent = item.name;
  $('#playerStatus').textContent = 'جارٍ الاتصال…';
  $('#player').classList.remove('hidden');
  $('#quality').innerHTML = '<option value="-1">جودة: تلقائي</option>';
  sendPing(item.name);
  if (hls) { hls.destroy(); hls = null; }

  if (live && window.Hls && Hls.isSupported()) {
    hls = new Hls({ backBufferLength: 30, maxBufferLength: 30, manifestLoadingTimeOut: 20000, fragLoadingTimeOut: 30000 });
    hls.loadSource(url); hls.attachMedia(video);
    hls.on(Hls.Events.MANIFEST_PARSED, () => { $('#playerStatus').textContent = '🔴 بث مباشر'; buildQualityMenu(); video.play().catch(() => {}); });
    hls.on(Hls.Events.ERROR, (e, data) => {
      if (!data.fatal) return;
      if (data.response && data.response.code === 429) {
        $('#playerStatus').textContent = '🚫 بلغت الحد الأقصى للأجهزة في اشتراكك.';
        hls.destroy(); hls = null;
      } else if (data.type === Hls.ErrorTypes.NETWORK_ERROR) { $('#playerStatus').textContent = 'خطأ شبكة — إعادة المحاولة…'; hls.startLoad(); }
      else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) { hls.recoverMediaError(); }
      else { $('#playerStatus').textContent = 'تعذّر تشغيل القناة.'; }
    });
  } else {
    video.src = url; video.play().catch(() => {});
    $('#playerStatus').textContent = item.type === 'live' ? '🔴 بث مباشر' : '▶ تشغيل';
    video.onerror = () => { $('#playerStatus').textContent = 'تعذّر تشغيل الملف (قد تكون الصيغة غير مدعومة في المتصفح).'; };
  }
}
function closePlayer() {
  $('#player').classList.add('hidden'); currentChannel = null;
  const v = $('#video'); v.pause(); v.removeAttribute('src'); v.load();
  if (hls) { hls.destroy(); hls = null; }
}

async function sendPing(channel) {
  try {
    const r = await fetch('/api/ping', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ cid: CID, channel: channel || currentChannel }) });
    if (r.status === 429) { const d = await r.json(); $('#playerStatus').textContent = '🚫 ' + (d.error || 'تجاوزت حد الأجهزة'); closePlayer(); }
  } catch {}
}

function bind() {
  $('#search').addEventListener('input', renderGrid);
  $('#closePlayer').onclick = closePlayer;
  $('#btnFullscreen').onclick = () => { const v = $('#video'); if (document.fullscreenElement) document.exitFullscreen(); else (v.requestFullscreen || v.webkitRequestFullscreen || (() => {})).call(v); };
  $('#btnLogout').onclick = async () => { await fetch('/api/logout', { method: 'POST' }); location.href = '/login'; };
  $$('[data-close]').forEach((b) => (b.onclick = () => b.closest('.modal').classList.add('hidden')));
  $$('.modal').forEach((m) => (m.onclick = (e) => { if (e.target === m) m.classList.add('hidden'); }));
  $$('.ctab').forEach((t) => { t.onclick = () => { view = t.dataset.view; activeCat = '__all__'; renderTabs(); renderCats(); renderGrid(); }; });
}

init();
