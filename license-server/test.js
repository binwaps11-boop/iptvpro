const crypto = require('crypto')
const { spawn } = require('child_process')
const fs = require('fs')
const path = require('path')

// الاختبار يشغّل الخادم بنفسه على منفذ ودليل بيانات مؤقتين ثم يوقفه،
// فلا يحتاج خطوتين ولا يصطدم بخادم يعمل أصلاً ولا يلوّث بيانات حقيقية.
const PORT = Number(process.env.TEST_PORT || 8123)
const BASE = `http://127.0.0.1:${PORT}`
const ADMIN = 'testtoken123'
const DATA = path.join(require('os').tmpdir(), 'lic-test-' + process.pid)

let child = null
function startServer() {
  fs.rmSync(DATA, { recursive: true, force: true })
  child = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
    env: { ...process.env, PORT: String(PORT), DATA_DIR: DATA, ADMIN_TOKEN: ADMIN },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  child.stderr.on('data', (d) => process.stderr.write(d))
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 15000
    const poll = () => {
      fetch(BASE + '/api/health').then(resolve).catch(() => {
        if (Date.now() > deadline) reject(new Error('لم يبدأ الخادم خلال ١٥ ثانية'))
        else setTimeout(poll, 200)
      })
    }
    poll()
  })
}
function stopServer() {
  if (child) child.kill('SIGKILL')
  fs.rmSync(DATA, { recursive: true, force: true })
}

let pub = null
async function post(path, body, headers = {}) {
  const r = await fetch(BASE + path, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  })
  return { code: r.status, json: await r.json() }
}
async function get(path, headers = {}) {
  const r = await fetch(BASE + path, { headers })
  return { code: r.status, json: await r.json() }
}
function rawToDer(raw) {
  const trim = (b) => { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; let v = b.slice(i)
    return (v[0] & 0x80) ? Buffer.concat([Buffer.from([0]), v]) : v }
  const r = trim(raw.slice(0, 32)), s = trim(raw.slice(32, 64))
  const body = Buffer.concat([Buffer.from([2, r.length]), r, Buffer.from([2, s.length]), s])
  return Buffer.concat([Buffer.from([0x30, body.length]), body])
}
/** يحاكي تماماً ما يفعله التطبيق: تحقق DER + مطابقة الـnonce */
function verifyLikeAndroid(res, nonce) {
  const raw = Buffer.from(res.data, 'base64')
  const sig = Buffer.from(res.signature, 'base64')
  if (sig.length !== 64) return { ok: false, why: 'طول التوقيع ليس ٦٤' }
  const key = crypto.createPublicKey({ key: Buffer.from(pub, 'base64'), format: 'der', type: 'spki' })
  const v = crypto.createVerify('SHA256')
  v.update(raw)
  if (!v.verify(key, rawToDer(sig))) return { ok: false, why: 'توقيع غير صالح' }
  const payload = JSON.parse(raw.toString('utf8'))
  if (payload.nonce !== nonce) return { ok: false, why: `nonce غير مطابق (${payload.nonce})` }
  return { ok: true, payload }
}

let pass = 0, fail = 0
function check(name, cond, extra = '') {
  if (cond) { pass++; console.log(`  ✓ ${name}`) }
  else { fail++; console.log(`  ✗ ${name} ${extra}`) }
}

;(async () => {
  await startServer()
  pub = (await get('/api/pubkey')).json.publicKey
  check('جلب المفتاح العام', !!pub && pub.length > 40)

  // 1) تسجيل جديد
  let n = crypto.randomUUID()
  let r = await post('/api/register', { email: 'ali@gmail.com', name: 'علي واقص', phone: '776831921', device: 'AB12-CD34', nonce: n })
  let v = verifyLikeAndroid(r.json, n)
  check('تسجيل جديد يوقّع رداً يقبله أندرويد', v.ok, v.why || '')
  check('التجربة تبدأ ٧ أيام', v.ok && v.payload.status === 'trial' && v.payload.daysLeft === 7, JSON.stringify(v.payload))

  // 2) إعادة استخدام نفس الـnonce مرفوضة
  r = await post('/api/register', { email: 'ali@gmail.com', name: 'علي', phone: '776831921', device: 'AB12-CD34', nonce: n })
  check('إعادة استخدام nonce مرفوضة', r.code === 400, JSON.stringify(r.json))

  // 3) إعادة بث رد قديم لا تنطلي: nonce جديد ≠ nonce الرد المحفوظ
  const oldResponse = (await post('/api/check', { email: 'ali@gmail.com', device: 'AB12-CD34', nonce: crypto.randomUUID() })).json
  const freshNonce = crypto.randomUUID()
  check('إعادة بث رد قديم تُرفض', !verifyLikeAndroid(oldResponse, freshNonce).ok)

  // 4) جهاز واحد لا يفتح حسابين
  n = crypto.randomUUID()
  r = await post('/api/register', { email: 'other@gmail.com', name: 'شخص آخر', phone: '777000111', device: 'AB12-CD34', nonce: n })
  check('الجهاز نفسه لا يفتح حساباً ثانياً', r.code === 409, JSON.stringify(r.json))

  // 5) حساب واحد لا ينتقل لجهاز آخر
  n = crypto.randomUUID()
  r = await post('/api/register', { email: 'ali@gmail.com', name: 'علي', phone: '776831921', device: 'ZZ99-YY88', nonce: n })
  check('الحساب لا ينتقل لجهاز آخر بلا إذن', r.code === 409, JSON.stringify(r.json))

  // 6) الفحص من جهاز خاطئ يعطي wrong_device
  n = crypto.randomUUID()
  r = await post('/api/check', { email: 'ali@gmail.com', device: 'QQ11-QQ11', nonce: n })
  v = verifyLikeAndroid(r.json, n)
  // حساب مختلف تماماً لأن accountId يعتمد البريد — نفس id، جهاز مختلف
  check('فحص من جهاز غير مربوط يُرفض', v.ok && v.payload.valid === false, JSON.stringify(v.payload))

  // 7) الإيقاف عن بعد
  r = await post('/api/admin/block', { id: 'ali@gmail.com', blocked: true }, { 'x-admin-token': ADMIN })
  check('الأدمن يوقف الحساب', r.code === 200)
  n = crypto.randomUUID()
  v = verifyLikeAndroid((await post('/api/check', { email: 'ali@gmail.com', device: 'AB12-CD34', nonce: n })).json, n)
  check('الإيقاف يصل التطبيق موقّعاً', v.ok && v.payload.status === 'blocked', JSON.stringify(v.payload))

  // 8) رمز أدمن خاطئ. الحالة الحرجة: رمز طوله النصي مساوٍ وبايتاته مختلفة
  //    (é حرف واحد لكنه بايتان في UTF-8) — كانت timingSafeEqual ترمي استثناءً
  r = await post('/api/admin/block', { id: 'ali@gmail.com', blocked: false }, { 'x-admin-token': 'testtoken12é' })
  check('رمز أدمن متعدد البايتات يُرفض بلا انهيار', r.code === 401, JSON.stringify(r.json))
  r = await post('/api/admin/block', { id: 'ali@gmail.com', blocked: false }, { 'x-admin-token': 'wrong' })
  check('رمز أدمن خاطئ يُرفض', r.code === 401, JSON.stringify(r.json))

  // 9) رفع الإيقاف + الموافقة على اشتراك شهر
  await post('/api/admin/block', { id: 'ali@gmail.com', blocked: false }, { 'x-admin-token': ADMIN })
  r = await post('/api/admin/approve', { id: 'ali@gmail.com', plan: 'month' }, { 'x-admin-token': ADMIN })
  check('الموافقة تمنح شهراً', r.code === 200 && r.json.state.plan === 'month')
  n = crypto.randomUUID()
  v = verifyLikeAndroid((await post('/api/check', { email: 'ali@gmail.com', device: 'AB12-CD34', nonce: n })).json, n)
  check('التطبيق يرى الاشتراك فعّالاً', v.ok && v.payload.status === 'active' && v.payload.daysLeft >= 30, JSON.stringify(v.payload))

  // 10) نقل الجهاز بموافقة الأدمن يحرّر القديم
  r = await post('/api/admin/rebind', { id: 'ali@gmail.com', device: 'NEW1-NEW1' }, { 'x-admin-token': ADMIN })
  check('النقل ينجح', r.code === 200)
  n = crypto.randomUUID()
  r = await post('/api/register', { email: 'someone@gmail.com', name: 'مستخدم جديد', phone: '777222333', device: 'AB12-CD34', nonce: n })
  check('الجهاز القديم صار حراً بعد النقل', r.code === 200, JSON.stringify(r.json))

  // 11) التجربة لا تتكرر على نفس الجهاز (بعد مسح بيانات التطبيق)
  v = verifyLikeAndroid(r.json, n)
  check('لا تجربة ثانية على جهاز استهلكها', v.ok && v.payload.valid === false, JSON.stringify(v.payload))

  // 12) بريد غير صالح
  r = await post('/api/register', { email: 'لا-بريد', name: 'اسم', phone: '777111222', device: 'XX00-XX00', nonce: crypto.randomUUID() })
  check('بريد غير صالح مرفوض', r.code === 400)

  // رفع الراوترات: المشترك يرفع ملخّص راوتراته فيراها الأدمن بلا كلمات مرور
  n = crypto.randomUUID()
  await post('/api/register', { email: 'router-user@gmail.com', name: 'صاحب راوتر', phone: '777333444', device: 'RT01-RT01', nonce: n })
  r = await post('/api/routers', { email: 'router-user@gmail.com', device: 'RT01-RT01', routers: [{ name: 'راوتري', host: '192.168.88.1', password: 'SECRET' }] })
  check('رفع الراوترات ينجح', r.code === 200 && r.json.ok === true)
  const accs = (await get('/api/admin/accounts', { 'x-admin-token': ADMIN })).json.accounts
  const ru = accs.find(a => a.id === 'router-user@gmail.com')
  check('الأدمن يرى راوتر المشترك', !!ru && Array.isArray(ru.routers) && ru.routers[0].name === 'راوتري')
  check('كلمة مرور الراوتر لا تُخزَّن على الخادم', !!ru && ru.routers[0].password === undefined)

  // 13) لوحة الأدمن تُخدَم من الخادم نفسه
  const page = await fetch(BASE + '/')
  const html = await page.text()
  check('لوحة الأدمن تُخدَم على /', page.status === 200 && html.includes('لوحة التراخيص'))
  check('نوع المحتوى HTML', (page.headers.get('content-type') || '').includes('text/html'))

  // 14) طلب بلا nonce مرفوض
  r = await post('/api/check', { email: 'ali@gmail.com', device: 'NEW1-NEW1' })
  check('طلب بلا nonce مرفوض', r.code === 400)

  console.log(`\nنجح ${pass} — فشل ${fail}`)
  stopServer()
  process.exit(fail ? 1 : 0)
})().catch((e) => { console.error(e); stopServer(); process.exit(1) })
