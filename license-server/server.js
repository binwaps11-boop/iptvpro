#!/usr/bin/env node
/**
 * خادم تراخيص «مدير الكروت» — قاعدة بيانات حقيقية تربط الحسابات وأرقام
 * الجوالات بالتراخيص، مع تحقق أونلاين دوري.
 *
 * بلا أي تبعيات: Node.js وحده (http + sqlite عبر node:sqlite أو ملف JSON ذرّي).
 * يعمل على أي VPS أوبونتو بأمر واحد:  node server.js
 *
 * الأمان:
 * - كل رد يُوقَّع بمفتاح ECDSA P-256 خاص يبقى على الخادم وحده.
 * - التطبيق يحمل المفتاح العام فقط ويتحقق من التوقيع — لا يستطيع تزوير ترخيص.
 * - nonce + طابع زمني يمنعان إعادة تشغيل الردود القديمة.
 * - تحديد معدل الطلبات لكل جهاز/عنوان.
 * - «حساب واحد = جهاز واحد» يُفرض على الخادم لا على العميل.
 */

'use strict'

const http = require('http')
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const PORT = Number(process.env.PORT || 8090)
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data')
const DB_FILE = path.join(DATA_DIR, 'licenses.json')
const KEY_FILE = path.join(DATA_DIR, 'signing-key.pem')
/** كلمة سر الأدمن — تُقرأ من البيئة، ولا تُكتب في الكود أبداً */
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || ''

if (!ADMIN_TOKEN) {
  console.error('✗ يجب ضبط ADMIN_TOKEN في البيئة قبل التشغيل. مثال:')
  console.error('  ADMIN_TOKEN="$(openssl rand -hex 24)" node server.js')
  process.exit(1)
}

fs.mkdirSync(DATA_DIR, { recursive: true })

// ==================== التخزين ====================
// ملف JSON بكتابة ذرّية (tmp + rename) — كافٍ لآلاف الحسابات وبلا تبعيات.

const emptyDb = () => ({ accounts: {}, devices: {}, events: [], nonces: {} })

function loadDb() {
  try {
    if (!fs.existsSync(DB_FILE)) return emptyDb()
    const parsed = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'))
    return { ...emptyDb(), ...parsed }
  } catch (e) {
    // ملف تالف: نحتفظ بنسخة ولا نمسح شيئاً
    try { fs.copyFileSync(DB_FILE, DB_FILE + '.bak') } catch (_) {}
    console.error('تعذّرت قراءة قاعدة البيانات — بدأنا بقاعدة جديدة والنسخة القديمة في .bak')
    return emptyDb()
  }
}

let db = loadDb()
let saveTimer = null

function saveDb() {
  // تجميع الكتابات: عدة تعديلات متتالية تُكتب مرة واحدة
  if (saveTimer) return
  saveTimer = setTimeout(() => {
    saveTimer = null
    const tmp = DB_FILE + '.tmp'
    try {
      fs.writeFileSync(tmp, JSON.stringify(db, null, 2))
      fs.renameSync(tmp, DB_FILE)
    } catch (e) {
      console.error('فشل الحفظ:', e.message)
    }
  }, 200)
}

// ==================== التوقيع ====================

function loadOrCreateKey() {
  if (fs.existsSync(KEY_FILE)) {
    return crypto.createPrivateKey(fs.readFileSync(KEY_FILE, 'utf8'))
  }
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' },
  })
  fs.writeFileSync(KEY_FILE, privateKey, { mode: 0o600 })
  const pubDer = crypto.createPublicKey(publicKey).export({ type: 'spki', format: 'der' })
  console.log('\n════════ المفتاح العام — ضعه في التطبيق ════════')
  console.log(pubDer.toString('base64'))
  console.log('════════════════════════════════════════════════\n')
  return crypto.createPrivateKey(privateKey)
}

const signingKey = loadOrCreateKey()

function publicKeyB64() {
  return crypto.createPublicKey(signingKey)
    .export({ type: 'spki', format: 'der' })
    .toString('base64')
}

/**
 * يوقّع الحمولة ويعيدها مع التوقيع — التطبيق يتحقق قبل الوثوق.
 *
 * تُرسل الحمولة كنص base64 لا ككائن JSON: إعادة تسلسل الكائن على العميل
 * قد تغيّر ترتيب المفاتيح أو المسافات فيفشل التحقق من التوقيع. بهذه الصيغة
 * يتحقق العميل من نفس البايتات تماماً ثم يحللها.
 */
function signed(payload) {
  const raw = Buffer.from(JSON.stringify(payload), 'utf8')
  const sig = crypto.sign('sha256', raw, {
    key: signingKey,
    dsaEncoding: 'ieee-p1363', // 64 بايت خام — يحوّلها العميل إلى DER
  })
  return { data: raw.toString('base64'), signature: sig.toString('base64') }
}

// ==================== أدوات ====================

const now = () => Date.now()
const DAY = 86400000

function accountId(email, deviceCode) {
  const base = String(email || '').trim().toLowerCase() || `device_${deviceCode}`
  return base.replace(/[^a-z0-9._@-]/g, '_').slice(0, 120)
}

function logEvent(kind, detail) {
  db.events.push({ at: now(), kind, detail })
  if (db.events.length > 5000) db.events = db.events.slice(-5000)
}

/** تحديد المعدل: 60 طلباً في الدقيقة لكل مفتاح */
const rate = new Map()
function rateLimited(key) {
  const t = now()
  const win = rate.get(key) || { start: t, count: 0 }
  if (t - win.start > 60000) { win.start = t; win.count = 0 }
  win.count++
  rate.set(key, win)
  // تنظيف دوري: بلا هذا تنمو الخريطة بعدد العناوين للأبد
  if (rate.size > 5000) {
    for (const [k, v] of rate) if (t - v.start > 120000) rate.delete(k)
  }
  return win.count > 60
}

/**
 * عنوان العميل الحقيقي. خلف Nginx يكون remoteAddress دائماً 127.0.0.1،
 * فيتشارك كل المشتركين دلواً واحداً ويُقفلون جميعاً بعد ٦٠ طلباً. لا نثق
 * برأس X-Forwarded-For إلا إن أعلن المشغّل أن الخادم خلف بروكسي.
 */
const TRUST_PROXY = process.env.TRUST_PROXY === '1'
function clientIp(req) {
  if (TRUST_PROXY) {
    const fwd = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim()
    if (fwd) return fwd
  }
  return req.socket.remoteAddress || 'unknown'
}

/** يمنع إعادة تشغيل الطلبات: نفس الـnonce لا يُقبل مرتين */
function nonceUsed(nonce) {
  if (!nonce) return false
  const t = now()
  for (const [n, at] of Object.entries(db.nonces)) {
    if (t - at > 10 * 60000) delete db.nonces[n]
  }
  if (db.nonces[nonce]) return true
  db.nonces[nonce] = t
  return false
}

function planDays(plan) {
  return { trial: 7, month: 30, quarter: 90, year: 365, lifetime: 36500 }[plan] ?? 30
}

// ==================== منطق الترخيص ====================

/**
 * حالة الحساب كما يراها التطبيق. تُبنى على الخادم دائماً — العميل لا يقرر شيئاً.
 */
function accountState(acc) {
  if (!acc) return { status: 'unknown', valid: false, reason: 'الحساب غير مسجّل' }
  if (acc.blocked) return { status: 'blocked', valid: false, reason: 'الحساب موقوف من مزوّد الخدمة' }
  const remaining = acc.expiresAt - now()
  if (remaining <= 0) {
    return {
      status: acc.plan === 'trial' ? 'trial_ended' : 'expired',
      valid: false,
      reason: acc.plan === 'trial' ? 'انتهت التجربة' : 'انتهى الاشتراك',
      expiresAt: acc.expiresAt,
    }
  }
  return {
    status: acc.plan === 'trial' ? 'trial' : 'active',
    valid: true,
    plan: acc.plan,
    expiresAt: acc.expiresAt,
    daysLeft: Math.ceil(remaining / DAY),
  }
}

/**
 * الرد الموحّد: حالة موقّعة + مهلة سماح + موعد الفحص التالي.
 *
 * الـnonce يعود داخل الحمولة الموقّعة لا خارجها: بدونه يكفي أن يحتفظ أحدهم
 * برد قديم صالح ويعيد بثّه للتطبيق بعد انتهاء اشتراكه، فيُقبل لأن توقيعه سليم.
 * التطبيق يولّد nonce لكل نداء ويرفض أي رد لا يحمله.
 */
function stateResponse(acc, deviceCode, nonce) {
  const st = accountState(acc)
  return signed({
    ...st,
    account: acc ? acc.id : null,
    device: deviceCode || null,
    nonce: nonce || null,
    // مهلة سماح بلا إنترنت — بعدها يجب التحقق أونلاين
    graceHours: 72,
    issuedAt: now(),
    nextCheckAt: now() + 6 * 3600000,
  })
}

// ==================== المسارات ====================

const routes = {
  /** تسجيل حساب جديد وبدء التجربة — التجربة تُمنح مرة واحدة لكل بريد وجهاز */
  'POST /api/register': (body, ip) => {
    const email = String(body.email || '').trim().toLowerCase()
    const phone = String(body.phone || '').trim()
    const name = String(body.name || '').trim()
    const device = String(body.device || '').trim().toUpperCase()

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return { code: 400, json: { error: 'أدخل بريداً صحيحاً' } }
    }
    if (!/^\d{7,15}$/.test(phone.replace(/\D/g, ''))) {
      return { code: 400, json: { error: 'أدخل رقم جوال صحيح' } }
    }
    if (!device) return { code: 400, json: { error: 'رمز الجهاز مفقود' } }
    const nonce = String(body.nonce || '')
    if (!nonce) return { code: 400, json: { error: 'الطلب ناقص' } }
    if (nonceUsed(nonce)) return { code: 400, json: { error: 'طلب مكرر' } }

    const id = accountId(email, device)
    let acc = db.accounts[id]

    // القاعدة في الاتجاهين: حساب واحد = جهاز واحد، وجهاز واحد = حساب واحد.
    // بدون هذا الشق يفتح الجهاز نفسه حسابات بلا حد ببريد جديد كل مرة.
    const owner = db.devices[device] && db.devices[device].account
    if (owner && owner !== id) {
      return {
        code: 409,
        json: {
          error: 'هذا الجهاز مسجّل بحساب آخر — استخدم بريده أو اطلب نقل الجهاز من مزوّد الخدمة',
          boundAccount: owner,
        },
      }
    }

    if (acc) {
      // حساب موجود: قاعدة «حساب واحد = جهاز واحد» تُفرض هنا على الخادم
      if (acc.device && acc.device !== device) {
        return {
          code: 409,
          json: {
            error: 'هذا الحساب مسجّل على جهاز آخر — اطلب من مزوّد الخدمة نقل الجهاز',
            boundDevice: acc.device,
          },
        }
      }
      acc.name = name || acc.name
      acc.phone = phone || acc.phone
      acc.lastSeen = now()
    } else {
      // التجربة مرة واحدة لكل جهاز — لا تتجدد بمسح بيانات التطبيق
      const deviceRecord = db.devices[device]
      const trialUsed = deviceRecord && deviceRecord.trialUsed
      acc = {
        id, email, phone, name, device,
        plan: 'trial',
        blocked: false,
        createdAt: now(),
        expiresAt: now() + (trialUsed ? 0 : planDays('trial') * DAY),
        lastSeen: now(),
      }
      db.accounts[id] = acc
      db.devices[device] = { ...(deviceRecord || {}), trialUsed: true, account: id, at: now() }
      acc.trialUsedBefore = !!trialUsed
      logEvent('register', { id, phone, device, trialUsed: !!trialUsed })
    }
    saveDb()
    return { code: 200, json: stateResponse(acc, device, nonce) }
  },

  /** التحقق الدوري — التطبيق يسأل، الخادم يقرر */
  'POST /api/check': (body) => {
    const device = String(body.device || '').trim().toUpperCase()
    const email = String(body.email || '').trim().toLowerCase()
    const nonce = String(body.nonce || '')
    if (!nonce) return { code: 400, json: { error: 'الطلب ناقص' } }
    if (nonceUsed(nonce)) {
      return { code: 400, json: { error: 'طلب مكرر' } }
    }
    const id = accountId(email, device)
    const acc = db.accounts[id]
    if (acc) {
      // الجهاز يجب أن يطابق المربوط — نسخ الحساب لجهاز آخر يُرفض
      if (acc.device && device && acc.device !== device) {
        return {
          code: 200,
          json: signed({
            status: 'wrong_device', valid: false,
            reason: 'هذا الحساب مربوط بجهاز آخر',
            device, nonce,
            issuedAt: now(), graceHours: 0, nextCheckAt: now() + 3600000,
          }),
        }
      }
      acc.lastSeen = now()
      saveDb()
    }
    return { code: 200, json: stateResponse(acc, device, nonce) }
  },

  /** طلب ترخيص/تجديد — يصل الأدمن */
  'POST /api/request': (body) => {
    const device = String(body.device || '').trim().toUpperCase()
    const email = String(body.email || '').trim().toLowerCase()
    const id = accountId(email, device)
    const acc = db.accounts[id]
    if (!acc) return { code: 404, json: { error: 'الحساب غير مسجّل' } }
    acc.pending = {
      at: now(),
      renewal: !!body.renewal,
      note: String(body.note || '').slice(0, 300),
    }
    logEvent('request', { id, renewal: !!body.renewal })
    saveDb()
    return { code: 200, json: { ok: true, message: 'وصل طلبك — بانتظار موافقة مزوّد الخدمة' } }
  },

  /**
   * المشترك يرفع **ملخّص** راوتراته (اسم + عنوان فقط، بلا كلمات مرور) فيراها
   * الأدمن ضمن الحساب. لا نخزّن كلمات مرور الراوتر إطلاقاً على الخادم.
   */
  'POST /api/routers': (body) => {
    const device = String(body.device || '').trim().toUpperCase()
    const email = String(body.email || '').trim().toLowerCase()
    const id = accountId(email, device)
    const acc = db.accounts[id]
    if (!acc) return { code: 404, json: { error: 'الحساب غير مسجّل' } }
    const routers = Array.isArray(body.routers) ? body.routers.slice(0, 20).map((r) => ({
      name: String(r.name || '').slice(0, 60),
      host: String(r.host || '').slice(0, 80),
    })) : []
    acc.routers = routers
    acc.lastSeen = now()
    saveDb()
    return { code: 200, json: { ok: true } }
  },

  // ===== مسارات الأدمن (تتطلب رمز الأدمن) =====

  'GET /api/admin/accounts': () => ({
    code: 200,
    json: {
      accounts: Object.values(db.accounts).map((a) => ({
        ...a, state: accountState(a),
      })).sort((x, y) => (y.pending?.at || y.createdAt) - (x.pending?.at || x.createdAt)),
    },
  }),

  /** الموافقة: يمنح خطة ومدة */
  'POST /api/admin/approve': (body) => {
    const acc = db.accounts[String(body.id || '')]
    if (!acc) return { code: 404, json: { error: 'الحساب غير موجود' } }
    const plan = String(body.plan || 'month')
    const days = planDays(plan)
    const base = Math.max(acc.expiresAt, now()) // التجديد يضيف للمتبقي لا يلغيه
    acc.plan = plan
    acc.expiresAt = base + days * DAY
    acc.blocked = false
    delete acc.pending
    logEvent('approve', { id: acc.id, plan, until: acc.expiresAt })
    saveDb()
    return { code: 200, json: { ok: true, account: acc, state: accountState(acc) } }
  },

  'POST /api/admin/block': (body) => {
    const acc = db.accounts[String(body.id || '')]
    if (!acc) return { code: 404, json: { error: 'الحساب غير موجود' } }
    acc.blocked = !!body.blocked
    logEvent(acc.blocked ? 'block' : 'unblock', { id: acc.id })
    saveDb()
    return { code: 200, json: { ok: true, state: accountState(acc) } }
  },

  /** نقل الحساب لجهاز جديد بموافقة الأدمن */
  'POST /api/admin/rebind': (body) => {
    const acc = db.accounts[String(body.id || '')]
    if (!acc) return { code: 404, json: { error: 'الحساب غير موجود' } }
    const device = String(body.device || '').trim().toUpperCase()
    if (!device) return { code: 400, json: { error: 'رمز الجهاز مفقود' } }
    logEvent('rebind', { id: acc.id, from: acc.device, to: device })
    // نحرّر الجهاز القديم ونربط الجديد، وإلا بقي القديم يحجب أي تسجيل عليه
    if (acc.device && db.devices[acc.device]) delete db.devices[acc.device].account
    acc.device = device
    db.devices[device] = { ...(db.devices[device] || {}), trialUsed: true, account: acc.id, at: now() }
    saveDb()
    return { code: 200, json: { ok: true, account: acc } }
  },

  'GET /api/admin/events': () => ({ code: 200, json: { events: db.events.slice(-300).reverse() } }),

  /** المفتاح العام — يُنسخ إلى التطبيق مرة واحدة */
  'GET /api/pubkey': () => ({ code: 200, json: { publicKey: publicKeyB64() } }),

  'GET /api/health': () => ({
    code: 200,
    json: { ok: true, accounts: Object.keys(db.accounts).length, uptime: process.uptime() },
  }),
}

// ==================== الخادم ====================

const server = http.createServer((req, res) => {
  const ip = clientIp(req)
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
  const key = `${req.method} ${url.pathname}`

  const send = (code, json) => {
    const body = JSON.stringify(json)
    res.writeHead(code, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': Buffer.byteLength(body),
      'Cache-Control': 'no-store',
    })
    res.end(body)
  }

  if (rateLimited(ip)) return send(429, { error: 'طلبات كثيرة — انتظر قليلاً' })

  // لوحة الأدمن: صفحة واحدة تُخدَم من الخادم نفسه. الصفحة عامة لأنها لا تحوي
  // بيانات — الرمز يُدخَل فيها ويُرسل في ترويسة كل نداء، وهو ما تفحصه المسارات.
  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/admin')) {
    try {
      const html = fs.readFileSync(path.join(__dirname, 'admin.html'))
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Length': html.length,
        'Cache-Control': 'no-store',
      })
      return res.end(html)
    } catch (_) {
      return send(404, { error: 'صفحة اللوحة غير موجودة' })
    }
  }

  const handler = routes[key]
  if (!handler) return send(404, { error: 'مسار غير معروف' })

  // مسارات الأدمن تتطلب الرمز
  if (url.pathname.startsWith('/api/admin/')) {
    const token = req.headers['x-admin-token']
    // مقارنة ثابتة الزمن تمنع تخمين الرمز بقياس الوقت.
    // المقارنة على البايتات لا على طول النص: رمز بأحرف غير لاتينية يعطي
    // طولاً نصياً متساوياً وبايتات مختلفة، وكانت timingSafeEqual ترمي استثناءً.
    const given = typeof token === 'string' ? Buffer.from(token, 'utf8') : Buffer.alloc(0)
    const expect = Buffer.from(ADMIN_TOKEN, 'utf8')
    const ok = given.length === expect.length && crypto.timingSafeEqual(given, expect)
    if (!ok) return send(401, { error: 'غير مصرّح' })
  }

  if (req.method === 'GET') {
    try {
      const out = handler({}, ip)
      return send(out.code, out.json)
    } catch (e) {
      return send(500, { error: 'خطأ داخلي' })
    }
  }

  let raw = ''
  let tooBig = false
  req.on('data', (chunk) => {
    raw += chunk
    if (raw.length > 64 * 1024) { tooBig = true; req.destroy() }
  })
  req.on('end', () => {
    if (tooBig) return
    let body = {}
    try { body = raw ? JSON.parse(raw) : {} } catch (_) {
      return send(400, { error: 'صيغة غير صالحة' })
    }
    try {
      const out = handler(body, ip)
      send(out.code, out.json)
    } catch (e) {
      console.error(e)
      send(500, { error: 'خطأ داخلي' })
    }
  })
})

server.listen(PORT, () => {
  console.log(`✓ خادم التراخيص يعمل على المنفذ ${PORT}`)
  console.log(`  الحسابات المسجّلة: ${Object.keys(db.accounts).length}`)
  console.log(`  المفتاح العام: ${publicKeyB64().slice(0, 40)}…`)
})
