// ===== الحالة =====
let STATE = { sources: [], channels: [], settings: {} };
let activeCat = '__all__';
let hls = null;

const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];

function toast(msg, ms = 2500) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.remove('hidden');
  clearTimeout(t._t);
  t._t = setTimeout(() => t.classList.add('hidden'), ms);
}

// ===== تحميل الحالة =====
async function loadState() {
  STATE = await fetch('/api/state').then((r) => r.json());
  renderCats();
  renderGrid();
  renderSources();
  fillSettings();
}

// ===== الفئات =====
function categories() {
  const set = new Map();
  for (const ch of STATE.channels) set.set(ch.category, (set.get(ch.category) || 0) + 1);
  return [...set.entries()].sort((a, b) => b[1] - a[1]);
}

function renderCats() {
  const cats = categories();
  const nav = $('#cats');
  nav.innerHTML = '';
  const mk = (key, label) => {
    const el = document.createElement('button');
    el.className = 'chip' + (activeCat === key ? ' active' : '');
    el.textContent = label;
    el.onclick = () => {
      activeCat = key;
      renderCats();
      renderGrid();
    };
    nav.appendChild(el);
  };
  mk('__all__', `الكل (${STATE.channels.length})`);
  for (const [name, n] of cats) mk(name, `${name} (${n})`);
}

// ===== الشبكة =====
function renderGrid() {
  const q = $('#search').value.trim().toLowerCase();
  let list = STATE.channels;
  if (activeCat !== '__all__') list = list.filter((c) => c.category === activeCat);
  if (q) list = list.filter((c) => (c.name || '').toLowerCase().includes(q));

  const grid = $('#grid');
  $('#empty').classList.toggle('hidden', STATE.channels.length > 0);
  grid.innerHTML = '';
  list.slice(0, 600).forEach((ch) => {
    const card = document.createElement('div');
    card.className = 'card';
    card.innerHTML = `
      <div class="thumb">${
        ch.logo ? `<img src="${ch.logo}" loading="lazy" onerror="this.replaceWith(ph())">` : '<span class="ph">📺</span>'
      }</div>
      <div class="name">${escapeHtml(ch.name)}</div>
      <div class="cat">${escapeHtml(ch.category)}</div>`;
    card.onclick = () => play(ch);
    grid.appendChild(card);
  });
}
window.ph = () => {
  const s = document.createElement('span');
  s.className = 'ph';
  s.textContent = '📺';
  return s;
};
function escapeHtml(s = '') {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

// ===== التشغيل =====
function streamUrl(ch) {
  return STATE.settings.useProxy ? '/proxy?u=' + encodeURIComponent(ch.url) : ch.url;
}

function play(ch) {
  const video = $('#video');
  const url = streamUrl(ch);
  $('#nowPlaying').textContent = ch.name;
  $('#playerStatus').textContent = 'جارٍ الاتصال…';
  $('#player').classList.remove('hidden');

  if (hls) { hls.destroy(); hls = null; }

  if (window.Hls && Hls.isSupported()) {
    hls = new Hls({
      lowLatencyMode: false,
      backBufferLength: 30,
      maxBufferLength: 30,
      manifestLoadingTimeOut: 20000,
      fragLoadingTimeOut: 30000,
    });
    hls.loadSource(url);
    hls.attachMedia(video);
    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      $('#playerStatus').textContent = '🔴 بث مباشر';
      video.play().catch(() => {});
    });
    hls.on(Hls.Events.ERROR, (e, data) => {
      if (data.fatal) {
        if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
          $('#playerStatus').textContent = 'خطأ شبكة — إعادة المحاولة…';
          hls.startLoad();
        } else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
          hls.recoverMediaError();
        } else {
          $('#playerStatus').textContent = 'تعذّر تشغيل القناة (قد تكون محظورة جغرافياً — جرّب تفعيل البروكسي/VPN).';
        }
      }
    });
  } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
    video.src = url;
    video.play().catch(() => {});
    $('#playerStatus').textContent = '🔴 بث مباشر';
  } else {
    $('#playerStatus').textContent = 'المتصفح لا يدعم HLS.';
  }
}

function closePlayer() {
  $('#player').classList.add('hidden');
  const video = $('#video');
  video.pause();
  video.removeAttribute('src');
  video.load();
  if (hls) { hls.destroy(); hls = null; }
}

// ===== المصادر =====
function renderSources() {
  const box = $('#sourcesList');
  box.innerHTML = '<h4 style="margin:6px 0">المصادر المضافة</h4>';
  if (!STATE.sources.length) {
    box.innerHTML += '<div class="src-item">لا توجد مصادر</div>';
    return;
  }
  STATE.sources.forEach((s) => {
    const el = document.createElement('div');
    el.className = 'src-item';
    el.innerHTML = `<span>${escapeHtml(s.name)} <small style="color:var(--muted)">(${s.type} · ${s.count} قناة)</small></span>
      <button class="del" data-id="${s.id}">حذف</button>`;
    el.querySelector('.del').onclick = async () => {
      await fetch('/api/sources?id=' + s.id, { method: 'DELETE' });
      toast('تم حذف المصدر');
      await loadState();
    };
    box.appendChild(el);
  });
}

async function submitSource(type, data) {
  toast('جارٍ الاستيراد…', 60000);
  try {
    const r = await fetch('/api/sources', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, ...data }),
    }).then((x) => x.json());
    if (r.error) throw new Error(r.error);
    toast(`تم استيراد ${r.count} قناة ✓`);
    await loadState();
  } catch (e) {
    toast('فشل الاستيراد: ' + e.message, 5000);
  }
}

// ===== الإعدادات =====
function fillSettings() {
  const s = STATE.settings;
  const f = $('#formSettings');
  f.useProxy.checked = !!s.useProxy;
  f.userAgent.value = s.userAgent || '';
  f.referer.value = s.referer || '';
  const up = s.upstream || {};
  f.up_enabled.checked = !!up.enabled;
  f.up_type.value = up.type || 'http';
  f.up_host.value = up.host || '';
  f.up_port.value = up.port || '';
  f.up_username.value = up.username || '';
  f.up_password.value = up.password || '';
}

// ===== ربط الأحداث =====
function bind() {
  $('#search').addEventListener('input', renderGrid);
  $('#closePlayer').onclick = closePlayer;
  $('#btnSources').onclick = () => $('#sourcesModal').classList.remove('hidden');
  $('#btnSettings').onclick = () => $('#settingsModal').classList.remove('hidden');
  $$('[data-close]').forEach((b) => (b.onclick = () => b.closest('.modal').classList.add('hidden')));
  $$('.modal').forEach((m) => (m.onclick = (e) => { if (e.target === m) m.classList.add('hidden'); }));

  // تبويبات المصادر
  $$('.tab').forEach((t) => {
    t.onclick = () => {
      $$('.tab').forEach((x) => x.classList.remove('active'));
      t.classList.add('active');
      $$('.tabpane').forEach((p) => p.classList.toggle('hidden', p.dataset.pane !== t.dataset.tab));
    };
  });

  $('#formXtream').onsubmit = (e) => {
    e.preventDefault();
    const f = e.target;
    submitSource('xtream', {
      name: f.name.value,
      server: f.server.value,
      username: f.username.value,
      password: f.password.value,
    });
  };
  $('#formUrl').onsubmit = (e) => {
    e.preventDefault();
    submitSource('m3u_url', { name: e.target.name.value, url: e.target.url.value });
  };
  $('#formContent').onsubmit = (e) => {
    e.preventDefault();
    submitSource('m3u_content', { name: e.target.name.value, content: e.target.content.value });
  };

  $('#formSettings').onsubmit = async (e) => {
    e.preventDefault();
    const f = e.target;
    const payload = {
      useProxy: f.useProxy.checked,
      userAgent: f.userAgent.value,
      referer: f.referer.value,
      upstream: {
        enabled: f.up_enabled.checked,
        type: f.up_type.value,
        host: f.up_host.value.trim(),
        port: Number(f.up_port.value) || 0,
        username: f.up_username.value,
        password: f.up_password.value,
      },
    };
    const r = await fetch('/api/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    }).then((x) => x.json());
    STATE.settings = r.settings;
    toast('تم حفظ الإعدادات ✓');
  };

  $('#btnTest').onclick = async () => {
    // احفظ أولاً ثم اختبر
    await $('#formSettings').requestSubmit();
    $('#testResult').textContent = 'جارٍ الاختبار…';
    const r = await fetch('/api/test-upstream').then((x) => x.json());
    $('#testResult').textContent = r.ok
      ? `✓ يعمل — عنوان IP الخارج: ${r.ip}`
      : '✗ فشل: ' + r.error;
  };
}

bind();
loadState();
