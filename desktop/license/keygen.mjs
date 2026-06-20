#!/usr/bin/env node
/*
 * مولّد سيريالات الاشتراك (يُستخدم من صاحب الخدمة فقط).
 * يوقّع كل سيريال رقمياً بمفتاح Ed25519 الخاص، ويتحقق منه التطبيق بالمفتاح العام.
 *
 * الاستخدام:
 *   node license/keygen.mjs --customer "أحمد" --days 30 --devices 1000 --plan gold
 *
 * يتطلب وجود المفتاح الخاص: license/private.pem  (أنشئه عبر setup-keys.mjs)
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PRIV_PATH = path.join(__dirname, 'private.pem');

export function generateSerial(data, privatePem) {
  const payload = Buffer.from(JSON.stringify(data), 'utf8');
  const sig = crypto.sign(null, payload, privatePem);
  return payload.toString('base64url') + '.' + sig.toString('base64url');
}

function parseArgs(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) a[argv[i].slice(2)] = argv[i + 1];
  }
  return a;
}

// تشغيل مباشر من سطر الأوامر
if (import.meta.url === `file://${process.argv[1]}`) {
  if (!fs.existsSync(PRIV_PATH)) {
    console.error('✗ المفتاح الخاص غير موجود. شغّل أولاً:  node license/setup-keys.mjs');
    process.exit(1);
  }
  const a = parseArgs(process.argv.slice(2));
  const days = Number(a.days || 30);
  const data = {
    id: crypto.randomUUID().slice(0, 8),
    customer: a.customer || 'عميل',
    plan: a.plan || 'standard',
    maxDevices: Number(a.devices || 0), // 0 = بلا حد
    iat: Date.now(),
    exp: days > 0 ? Date.now() + days * 86400000 : 0,
  };
  const serial = generateSerial(data, fs.readFileSync(PRIV_PATH, 'utf8'));
  console.log('\n  ✅ تم توليد السيريال:\n');
  console.log('  ' + serial + '\n');
  console.log('  العميل:    ' + data.customer);
  console.log('  الباقة:    ' + data.plan);
  console.log('  الأجهزة:   ' + (data.maxDevices || 'بلا حد'));
  console.log('  المدة:     ' + (days > 0 ? days + ' يوم' : 'دائم'));
  console.log('  ينتهي:     ' + (data.exp ? new Date(data.exp).toLocaleString('ar') : '—') + '\n');
}
