#!/usr/bin/env node
/*
 * إعداد مفاتيح نظام التراخيص (تُشغَّل مرة واحدة عند تجهيز منتجك).
 * - ينشئ زوج مفاتيح Ed25519.
 * - يحفظ المفتاح الخاص في  license/private.pem   (احتفظ به سرّياً — لا تشاركه!)
 * - يحفظ المفتاح العام في   license_pub.pem        (يُشحن مع التطبيق لتفعيل الحماية)
 *
 * بعد تشغيله يصبح التطبيق «مقفولاً» ويتطلب سيريالاً صالحاً للأجهزة الزائدة.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PRIV_PATH = path.join(__dirname, 'private.pem');
const PUB_PATH = path.join(__dirname, '..', 'license_pub.pem');

if (fs.existsSync(PRIV_PATH) && process.argv[2] !== '--force') {
  console.error('✗ المفاتيح موجودة مسبقاً. لإعادة الإنشاء (سيُبطل كل السيريالات القديمة):');
  console.error('   node license/setup-keys.mjs --force');
  process.exit(1);
}

const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
fs.writeFileSync(PRIV_PATH, privateKey.export({ type: 'pkcs8', format: 'pem' }));
fs.writeFileSync(PUB_PATH, publicKey.export({ type: 'spki', format: 'pem' }));

console.log('\n  ✅ تم إنشاء مفاتيح التراخيص:');
console.log('     • المفتاح الخاص (سرّي):  license/private.pem');
console.log('     • المفتاح العام (يُشحن): license_pub.pem');
console.log('\n  الآن نظام التراخيص مُفعّل. ولّد سيريالات عبر:');
console.log('     node license/keygen.mjs --customer "اسم" --days 30 --devices 1000\n');
