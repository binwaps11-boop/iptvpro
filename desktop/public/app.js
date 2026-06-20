// ===== الحالة =====
let STATE = { live: [], movies: [], series: [], sources: [], settings: {} };
let view = 'live'; // live | movies | series
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

function currentList() {
  return STATE[view] || [];
}

// ===== تحميل الحالة =====
async function loadState() {
  STATE = await fetch('/api/state').then((r) => r.json());
  renderTabs();
  renderCats();
  renderGrid();
  renderSources();
  fillSettings();
}

async function loadNetInfo() {
  try {
    const n = await fetch('/api/netinfo').then((r) => r.json());
    if (n.addresses && n.addresses.length) {
      $('#netbanner').textContent = `🌐 من أجهزة الشبكة: http://${n.addresses[0]}:${n.port}`;
      $('#netbanner').title = 'افتح هذا العنوان على التلفزيون/الجوال على نفس الشبكة (مثل Jellyfin)';
    }
  } catch {}
}

// ===== التبويبات (مباشر/أفلام/مسلسلات) =====
function renderTabs() {
  $$('.ctab').forEach((b) => {
    const count = (STATE[b.dataset.view] || []).length;
    b.classList.toggle('active', b.dataset.view === view);
    const base = { live: '📡 المباشر', movies: '🎬 الأفلام', series: '📺 المسلسلات' }[b.dataset.view];
    b.textContent = `${base} (${count})`;
  });
}

// ===== الفئات =====
function categories() {
  const set = new Map();
  for (const ch of currentList()) set.set(ch.category, (set.get(ch.category) || 0) + 1);
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
  mk('__all__', `الكل (${currentList().length})`);
  for (const [name, n] of cats) mk(name, `${name} (${n})`);
}

// ===== الشبكة =====
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
    card.innerHTML = `
      <div class="thumb">${
        item.logo ? `<img src="${item.logo}" loading="lazy" onerror="this.replaceWith(ph())">` : '<span class="ph">📺</span>'
      }</div>
      <div class="name">${escapeHtml(item.name)}</div>
      <div class="cat">${escapeHtml(item.category)}</div>`;
    card.onclick = () => (item.type === 'series' ? openSeries(item) : play(item));
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
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

// ===== المسلسلات: المواسم والحلقات =====
async function openSeries(item) {
  $('#seriesTitle').textContent = item.name;
  $('#seriesBody').innerHTML = 'جارٍ تحميل الحلقات…';
  $('#seriesModal').classList.remove('hidden');
  try {
    const data = await fetch(
      `/api/series-info?sourceId=${item.sourceId}&seriesId=${item.seriesId}`
    ).then((r) => r.json());
    if (data.error) throw new Error(data.error);
    const box = $('#seriesBody');
    box.innerHTML = '';
    if (!data.seasons.length) {
      box.innerHTML = 'لا توجد حلقات.';
      return;
    }
    data.seasons.forEach((s) => {
      const h = document.createElement('div');
      h.className = 'season-h';
      h.textContent = `الموسم ${s.season}`;
      box.appendChild(h);
      s.episodes.forEach((ep) => {
        const row = document.createElement('div');
        row.className = 'ep';
        row.innerHTML = `<span>${escapeHtml(ep.title)}</span><span class="play">▶ تشغيل</span>`;
        row.onclick = () => {
          $('#seriesModal').classList.add('hidden');
          play({ name: `${item.name} — ${ep.title}`, url: ep.url, type: 'movie' });
        };
        box.appendChild(row);
      });
    });
  } catch (e) {
    $('#seriesBody').innerHTML = 'تعذّر تحميل الحلقات: ' + escapeHtml(e.message);
  }
}

// ===== التشغيل =====
function streamUrl(item) {
  return STATE.settings.useProxy ? '/proxy?u=' + encodeURIComponent(item.url) : item.url;
}

function play(item) {
  const video = $('#video');
  const url = streamUrl(item);
  const live = item.type === 'live' || /\.m3u8(\?|$)/i.test(item.url) || /\/live\//.test(item.url);
  $('#nowPlaying').textContent = item.name;
  $('#playerStatus').textContent = 'جارٍ الاتصال…';
  $('#player').classList.remove('hidden');

  if (hls) { hls.destroy(); hls = null; }

  if (live && window.Hls && Hls.isSupported()) {
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
          $('#playerStatus').textContent =
            'تعذّر التشغيل (قد تكون محظورة جغرافياً — جرّب تفعيل البروكسي/VPN من الإعدادات).';
        }
      }
    });
  } else {
    // أفلام/حلقات أو HLS أصلي (Safari) — تشغيل مباشر للملف مع دعم التقديم
    video.src = url;
    video.play().catch(() => {});
    $('#playerStatus').textContent = item.type === 'live' ? '🔴 بث مباشر' : '▶ تشغيل';
    video.onerror = () => {
      $('#playerStatus').textContent =
        'تعذّر تشغيل الملف (قد تكون الصيغة mkv غير مدعومة في المتصفح، أو يلزم VPN).';
    };
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
    el.innerHTML = `<span>${escapeHtml(s.name)}
      <small style="color:var(--muted)">(${s.type} · ${s.live} مباشر · ${s.movies} فيلم · ${s.series} مسلسل)</small></span>
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
  toast('جارٍ الاستيراد… (قد يستغرق دقيقة للاشتراكات الكبيرة)', 120000);
  try {
    const r = await fetch('/api/sources', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, ...data }),
    }).then((x) => x.json());
    if (r.error) throw new Error(r.error);
    toast(`تم الاستيراد ✓  ${r.live || 0} مباشر · ${r.movies || 0} فيلم · ${r.series || 0} مسلسل`, 4000);
    $('#sourcesModal').classList.add('hidden');
    await loadState();
  } catch (e) {
    toast('فشل الاستيراد: ' + e.message, 6000);
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
  $('#btnFullscreen').onclick = () => {
    const v = $('#video');
    if (document.fullscreenElement) document.exitFullscreen();
    else (v.requestFullscreen || v.webkitRequestFullscreen || (() => {})).call(v);
  };
  $('#btnSources').onclick = () => $('#sourcesModal').classList.remove('hidden');
  $('#btnSettings').onclick = () => $('#settingsModal').classList.remove('hidden');
  $$('[data-close]').forEach((b) => (b.onclick = () => b.closest('.modal').classList.add('hidden')));
  $$('.modal').forEach((m) => (m.onclick = (e) => { if (e.target === m) m.classList.add('hidden'); }));

  // تبويبات المحتوى
  $$('.ctab').forEach((t) => {
    t.onclick = () => {
      view = t.dataset.view;
      activeCat = '__all__';
      renderTabs();
      renderCats();
      renderGrid();
    };
  });

  // تبويبات نافذة المصادر
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
    await $('#formSettings').requestSubmit();
    $('#testResult').textContent = 'جارٍ الاختبار…';
    const r = await fetch('/api/test-upstream').then((x) => x.json());
    $('#testResult').textContent = r.ok ? `✓ يعمل — عنوان IP الخارج: ${r.ip}` : '✗ فشل: ' + r.error;
  };
}

bind();
loadState();
loadNetInfo();
