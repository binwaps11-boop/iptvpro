// ===== لوحة الإدارة =====
const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];
let STATE = {};

function toast(msg, ms = 3000) {
  const t = $('#toast'); t.textContent = msg; t.classList.remove('hidden');
  clearTimeout(t._t); t._t = setTimeout(() => t.classList.add('hidden'), ms);
}
function esc(s = '') { return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
const jpost = (url, body) => fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then((r) => r.json());

async function init() {
  const me = await fetch('/api/me').then((r) => r.json());
  if (!me.authenticated || me.role !== 'admin') { location.href = '/login?next=/admin'; return; }
  if (me.mustChangePassword) $('#pwBanner').classList.remove('hidden');
  await refresh();
  bind();
  setInterval(refreshStats, 10000);
}

async function refresh() {
  STATE = await fetch('/api/state').then((r) => r.json());
  fillSettings();
  renderSources();
  await renderClients();
  await refreshStats();
}

async function refreshStats() {
  const v = await fetch('/api/admin/viewers').then((r) => r.json()).catch(() => ({ active: 0, viewers: [] }));
  const s = STATE;
  const card = (label, val) => `<div class="stat"><div class="stat-v">${val}</div><div class="stat-l">${label}</div></div>`;
  $('#stats').innerHTML =
    card('المصادر', (s.sources || []).length) +
    card('قنوات مباشرة', (s.live || []).length) +
    card('أفلام', (s.movies || []).length) +
    card('مسلسلات', (s.series || []).length) +
    card('أجهزة تشاهد الآن', v.active);
}

// ===== المصادر =====
function renderSources() {
  const box = $('#sourcesList'); box.innerHTML = '';
  if (!(STATE.sources || []).length) { box.innerHTML = '<div class="li muted">لا توجد مصادر</div>'; return; }
  STATE.sources.forEach((s) => {
    const el = document.createElement('div'); el.className = 'li';
    el.innerHTML = `<span>${esc(s.name)} <small class="muted">(${s.type} · ${s.live}📡 ${s.movies}🎬 ${s.series}📺)</small></span><button class="del">حذف</button>`;
    el.querySelector('.del').onclick = async () => { if (!confirm('حذف المصدر؟')) return; await fetch('/api/sources?id=' + s.id, { method: 'DELETE' }); toast('تم الحذف'); refresh(); };
    box.appendChild(el);
  });
}
async function submitSource(type, data) {
  toast('جارٍ الاستيراد… قد يستغرق دقيقة للاشتراكات الكبيرة', 120000);
  const r = await jpost('/api/sources', { type, ...data });
  if (r.error) return toast('فشل: ' + r.error, 6000);
  toast(`تم ✓ ${r.live || 0}📡 ${r.movies || 0}🎬 ${r.series || 0}📺`, 4000);
  refresh();
}

// ===== العملاء =====
async function renderClients() {
  const { clients } = await fetch('/api/clients').then((r) => r.json());
  const box = $('#clientsList'); box.innerHTML = '';
  if (!clients.length) { box.innerHTML = '<div class="li muted">لا يوجد عملاء</div>'; return; }
  clients.forEach((c) => {
    const el = document.createElement('div'); el.className = 'li client' + (c.disabled ? ' off' : '');
    el.innerHTML =
      `<div><b>${esc(c.username)}</b> <small class="muted">${esc(c.name)}</small><br>
        <small class="muted">أجهزة: ${c.active}/${c.maxDevices || '∞'} · ${c.expiry ? c.daysLeft + ' يوم' : 'دائم'}${c.disabled ? ' · موقوف' : ''}</small></div>
       <div class="cli-actions">
        <button class="mini" data-act="renew">+30ي</button>
        <button class="mini" data-act="toggle">${c.disabled ? 'تفعيل' : 'إيقاف'}</button>
        <button class="mini danger" data-act="del">حذف</button>
       </div>`;
    el.querySelector('[data-act="renew"]').onclick = async () => { await jpost('/api/clients/update', { id: c.id, addDays: 30 }); toast('تم التجديد +30 يوم'); renderClients(); };
    el.querySelector('[data-act="toggle"]').onclick = async () => { await jpost('/api/clients/update', { id: c.id, disabled: !c.disabled }); renderClients(); };
    el.querySelector('[data-act="del"]').onclick = async () => { if (!confirm('حذف العميل؟')) return; await fetch('/api/clients?id=' + c.id, { method: 'DELETE' }); toast('تم الحذف'); renderClients(); };
    box.appendChild(el);
  });
}

// ===== الإعدادات =====
function fillSettings() {
  const s = STATE.settings || {}; const f = $('#formSettings');
  f.useProxy.checked = !!s.useProxy; f.userAgent.value = s.userAgent || ''; f.referer.value = s.referer || '';
  const up = s.upstream || {};
  f.up_enabled.checked = !!up.enabled; f.up_type.value = up.type || 'http';
  f.up_host.value = up.host || ''; f.up_port.value = up.port || '';
  f.up_username.value = up.username || ''; f.up_password.value = up.password || '';
}

function bind() {
  $('#btnLogout').onclick = async () => { await fetch('/api/logout', { method: 'POST' }); location.href = '/login'; };
  $('#pwBannerBtn').onclick = () => $('#formPw').scrollIntoView({ behavior: 'smooth' });

  $$('.tab').forEach((t) => { t.onclick = () => {
    $$('.tab').forEach((x) => x.classList.remove('active')); t.classList.add('active');
    $$('.tabpane').forEach((p) => p.classList.toggle('hidden', p.dataset.pane !== t.dataset.tab));
  }; });

  $('#formXtream').onsubmit = (e) => { e.preventDefault(); const f = e.target; submitSource('xtream', { name: f.name.value, server: f.server.value, username: f.username.value, password: f.password.value }); };
  $('#formUrl').onsubmit = (e) => { e.preventDefault(); submitSource('m3u_url', { name: e.target.name.value, url: e.target.url.value }); };
  $('#formContent').onsubmit = (e) => { e.preventDefault(); submitSource('m3u_content', { name: e.target.name.value, content: e.target.content.value }); };

  $('#formClient').onsubmit = async (e) => {
    e.preventDefault(); const f = e.target;
    const r = await jpost('/api/clients', { username: f.username.value, password: f.password.value, name: f.name.value, days: +f.days.value, maxDevices: +f.maxDevices.value });
    if (r.error) return toast('فشل: ' + r.error, 5000);
    toast('تمت إضافة العميل ✓'); f.reset(); f.days.value = 30; f.maxDevices.value = 2; renderClients();
  };

  $('#formSettings').onsubmit = async (e) => {
    e.preventDefault(); const f = e.target;
    await jpost('/api/settings', {
      useProxy: f.useProxy.checked, userAgent: f.userAgent.value, referer: f.referer.value,
      upstream: { enabled: f.up_enabled.checked, type: f.up_type.value, host: f.up_host.value.trim(), port: +f.up_port.value || 0, username: f.up_username.value, password: f.up_password.value },
    });
    toast('تم حفظ الإعدادات ✓'); refresh();
  };
  $('#btnTest').onclick = async () => {
    await $('#formSettings').requestSubmit();
    $('#testResult').textContent = 'جارٍ الاختبار…';
    const r = await fetch('/api/test-upstream').then((x) => x.json());
    $('#testResult').textContent = r.ok ? `✓ يعمل — IP الخارج: ${r.ip}` : '✗ فشل: ' + r.error;
  };

  $('#formPw').onsubmit = async (e) => {
    e.preventDefault();
    const r = await jpost('/api/admin/password', { password: e.target.password.value });
    if (r.error) return toast('فشل: ' + r.error, 4000);
    toast('تم تغيير كلمة المرور ✓'); $('#pwBanner').classList.add('hidden'); e.target.reset();
  };
}

init();
