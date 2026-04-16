# Key Fixes Needed

## 1. Live Edge Problem (البث يبدو مسجل)
- generateManifest يعرض آخر 30 segment = ~3 دقائق من البث القديم
- HLS.js يبدأ من أول segment في المانيفست بدلاً من Live Edge
- الحل: تقليل segments في المانيفست لـ 6 فقط (مثل Jellyfin) + liveSyncDurationCount=3

## 2. Multi-Device Problem
- hlsEngine.ts يعمل بشكل صحيح (shared session)
- المشكلة: إذا فشل HLS Engine، يقع في fallback لـ proxy mode
- Proxy mode يفتح اتصال جديد لكل جهاز = المصدر يرفض الثاني
- الحل: إزالة fallback لـ proxy، Jellyfin فقط

## 3. MIN_SEGMENTS_BEFORE_SERVE = 3 (18 ثانية انتظار)
- طويل جداً، يجعل المستخدم ينتظر
- الحل: تقليل لـ 2 segments (12 ثانية)

## Changes to make:
### hlsEngine.ts:
- MAX_SEGMENTS: 200 → 30 (less memory, faster)
- Manifest: show only last 6 segments (not 30)
- MIN_SEGMENTS_BEFORE_SERVE: 3 → 2
- SEGMENT_DURATION_MS: 6000 → 4000 (from Jellyfin doc: hls_time=4)

### SubscriptionView.tsx HLS.js config:
- liveSyncDurationCount: 6 → 3 (from stream-fixes.test.ts)
- liveMaxLatencyDurationCount: 20 → 6 (much tighter)
- backBufferLength: Infinity → 300 (from test)
- liveBackBufferLength: Infinity → 300
- Remove Direct Play and Proxy options
- Force Jellyfin mode always

### streamProxy.ts:
- /channel/:id route: redirect to HLS Engine instead of direct proxy
