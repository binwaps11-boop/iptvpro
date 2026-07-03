(function () {
  "use strict";

  var API = "/cgi-bin/dashapi2";
  var ACTION = "/cgi-bin/dashaction";
  var CTL = "/cgi-bin/dashctl";
  var AUTH = "/ubus";
  var ANON = "00000000000000000000000000000000";
  var LS = "smartap.";
  var UI_VERSION = "cr6608-smartap-clean-dashboard-v4";
  if (localStorage.getItem(LS + "uiVersion") !== UI_VERSION) {
    localStorage.setItem(LS + "theme", "dark");
    localStorage.setItem(LS + "interval", "5");
    localStorage.removeItem(LS + "events");
    localStorage.removeItem(LS + "availability");
    localStorage.removeItem(LS + "histories");
    localStorage.setItem(LS + "uiVersion", UI_VERSION);
  }
  var state = {
    lang: localStorage.getItem(LS + "lang") || "ar",
    theme: localStorage.getItem(LS + "theme") || "dark",
    interval: Number(localStorage.getItem(LS + "interval") || 5),
    timer: 0,
    latest: null,
    previousTraffic: null,
    previousAt: 0,
    histories: JSON.parse(localStorage.getItem(LS + "histories") || "{}"),
    availability: JSON.parse(localStorage.getItem(LS + "availability") || "[]"),
    events: JSON.parse(localStorage.getItem(LS + "events") || "[]"),
    toastTimer: 0,
    session: "",
    pendingAction: null,
    adminSelection: {},
    controlCache: {}
  };

  var L = {
    ar: {
      loading: "جاري التحميل", unavailable: "غير متوفر", online: "متصل", offline: "غير متصل",
      lanOnly: "LAN فقط", refresh: "تحديث", theme: "الثيم", dark: "داكن", light: "فاتح",
      overview: "نظرة",
      signal: "الإشارة", network: "الترافيك", devices: "الأجهزة", wifi: "WiFi",
      system: "صحة النظام", actions: "إجراءات", isolation: "العزل والحماية",
      vendor: "الشركة", type: "النوع", link: "المنفذ", action: "إجراء", unknownVendor: "غير معروف",
      netmgr: "الشبكة", wifimgr: "لاسلكي", sysmgr: "النظام",
      quick: "الإعدادات السريعة", quickHint: "برمجة الجهاز بخطوات: الوضع، الشبكة، الحماية، المتقدم — تطبيق واحد.",
      quickTitle: "برمجة سريعة (AP / VLAN / Mesh / WDS / PPPoE)",
      quickNote: "اختر الوضع وعبّئ الحقول ثم اضغط حفظ وتطبيق. التطبيق يحفظ فوراً وبشكل نهائي (Apply & Keep) مع نسخة احتياطية وزر إرجاع يدوي. تُطبَّق كل الحقول من التبويبات الثلاثة معاً.",
      isolationHint: "حمايات وتحكم بالمنافذ — كل خيار مشروح تحته.",
      isolationTitle: "الحماية والمنافذ — دليل مبسّط",
      isolationNote: "٣ أقسام: (١) الحمايات العامة — دروع تشتغل تلقائياً، خلّها مفعّلة. (٢) عزل الواي فاي — تخلي أجهزة الشبكة ما تشوف بعض (أأمن). (٣) منافذ الكيبل — تشغّل/تطفّي كل منفذ وتعزله أو تحط له VLAN. تحت كل خيار جملة تشرح وش يصير لو غيّرته. أي تعديل يُطبَّق ويُحفظ فوراً (Apply & Keep)، مع نسخة احتياطية وزر إرجاع يدوي.",
      subtitle: "لوحة OpenWrt محلية: بيانات حية، أصول داخلية، بدون CDN.",
      uptime: "مدة التشغيل", model: "الموديل", firmware: "النظام", internet: "الإنترنت",
      deviceCount: "الأجهزة", updated: "آخر تحديث", traffic: "الترافيك", cpu: "المعالج",
      ram: "الذاكرة", storage: "التخزين", temp: "الحرارة", daily: "اليومي", monthly: "الشهري",
      noQuota: "استهلاك محسوب من عدادات الجهاز، الميزانية محلية قابلة للتعديل.",
      safeAction: "إجراء محمي", cancel: "تم الإلغاء", ok: "سليم", warn: "تنبيه",
      block: "حظر", allow: "سماح", simulated: "لم يتم تطبيق قاعدة جدار ناري. هذا زر واجهة آمن حالياً.",
      networkTitle: "Network · Traffic & Errors", systemTitle: "System · CPU / RAM / Storage",
      emptyEvents: "لا توجد أحداث جديدة.", speedTest: "اختبار سرعة", localTest: "اختبار محلي",
      interval: "فاصل التحديث", budget: "الميزانية", save: "حفظ",
      readApiNow: "قراءة البيانات الآن", reconnect: "إعادة الاتصال", toggleWifi: "تبديل WiFi",
      reboot: "إعادة التشغيل", protected: "محمي", confirmRequired: "يتطلب تأكيد",
      actionsHint: "التأكيدات تحمي الوصول ولا يتم لمس إعداد الطاقة.",
      confirmAgain: "اضغط الزر مرة أخرى خلال 6 ثوانٍ للتأكيد",
      loginSubtitle: "تسجيل الدخول إلى لوحة الراوتر", username: "اسم المستخدم", password: "كلمة السر",
      passwordHint: "كلمة المرور الافتراضية: admin (غيّرها من إدارة النظام)", login: "دخول", logout: "خروج",
      loginWait: "جاري التحقق من بيانات الدخول...", loginBad: "فشل تسجيل الدخول. تحقق من اسم المستخدم أو كلمة السر.",
      loginOk: "تم تسجيل الدخول", loggedOut: "تم تسجيل الخروج",
      rootPassWarn: "كلمة مرور الدخول الافتراضية admin — يُنصح بتغييرها من النظام ← الإدارة.",
      protectedPage: "صفحة حساسة", opensOriginal: "قسم داخل تصميم Smart AP الحالي", newDashboard: "هذه اللوحة الحالية",
      branchHint: "لوحة Smart AP السوداء مخصصة للنظرة العامة والترافيك فقط.",
      comingSoon: "تمت إضافته كواجهة داخلية جديدة.",
      sensitiveNote: "محمي: هذا القسم لا يغيّر الطاقة أو الإعدادات الحساسة من هذه اللوحة."
    },
    en: {
      loading: "Loading", unavailable: "Not available", online: "Online", offline: "Offline",
      lanOnly: "LAN only", refresh: "Refresh", theme: "Theme", dark: "Dark", light: "Light",
      overview: "Overview",
      signal: "Signal", network: "Traffic", devices: "Devices", wifi: "WiFi",
      system: "System Health", actions: "Actions", isolation: "Isolation",
      vendor: "Vendor", type: "Type", link: "Link", action: "Action", unknownVendor: "Unknown",
      netmgr: "Network", wifimgr: "Wireless", sysmgr: "System",
      quick: "Quick Setup", quickHint: "Program the device step by step: mode, network, protection, advanced — one apply.",
      quickTitle: "Quick programming (AP / VLAN / Mesh / WDS / PPPoE)",
      quickNote: "Pick a mode, fill the fields, then Save & Apply. Each apply saves immediately and permanently (Apply & Keep) with a backup and a manual rollback button. All fields from the three tabs are applied together.",
      isolationHint: "Protections & port control — each option explained below it.",
      isolationTitle: "Protection & Ports — simple guide",
      isolationNote: "3 parts: (1) General protections — shields that run automatically, keep them on. (2) Wi-Fi isolation — makes devices unable to see each other (safer). (3) LAN ports — turn each port on/off, isolate it, or assign a VLAN. Each option has a line explaining what happens if you change it. Every change applies and saves immediately (Apply & Keep), with a backup and manual rollback.",
      subtitle: "Local OpenWrt dashboard: live data, offline assets, no CDN.",
      uptime: "Uptime", model: "Model", firmware: "Firmware", internet: "Internet",
      deviceCount: "Devices", updated: "Updated", traffic: "Traffic", cpu: "CPU",
      ram: "RAM", storage: "Storage", temp: "Temperature", daily: "Daily", monthly: "Monthly",
      noQuota: "Usage is calculated from device counters; budgets are stored locally.",
      safeAction: "Protected action", cancel: "Cancelled", ok: "OK", warn: "Warning",
      block: "Block", allow: "Allow", simulated: "No firewall rule was applied. This is a safe UI action for now.",
      networkTitle: "Network · Traffic & Errors", systemTitle: "System · CPU / RAM / Storage",
      emptyEvents: "No new events.", speedTest: "Speed test", localTest: "Local test",
      interval: "Update interval", budget: "Budget", save: "Save",
      readApiNow: "Read API now", reconnect: "Reconnect", toggleWifi: "Toggle WiFi",
      reboot: "Reboot", protected: "Protected", confirmRequired: "Confirm required",
      actionsHint: "Confirmations protect access; power settings are not touched.",
      confirmAgain: "Press the button again within 6 seconds to confirm",
      loginSubtitle: "Sign in to the router dashboard", username: "Username", password: "Password",
      passwordHint: "Default password: admin (change it in System)", login: "Sign in", logout: "Logout",
      loginWait: "Checking credentials...", loginBad: "Login failed. Check the username or password.",
      loginOk: "Signed in", loggedOut: "Signed out",
      rootPassWarn: "Default login password is admin — change it in System → Administration.",
      protectedPage: "Protected page", opensOriginal: "Section inside the current Smart AP design", newDashboard: "This current dashboard",
      branchHint: "The black Smart AP panel is for overview and traffic only.",
      comingSoon: "Smart AP control is loaded here.",
      sensitiveNote: "Protected: this section does not change power or sensitive settings from this dashboard."
    }
  };

  function $(id) { return document.getElementById(id); }
  function tr(key) { return (L[state.lang] && L[state.lang][key]) || L.en[key] || key; }
  function esc(v) { return String(v == null ? "" : v).replace(/[&<>"']/g, function (c) { return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]; }); }
  function sid(v) { return String(v || "").replace(/[^a-zA-Z0-9_-]/g, "_"); }
  function num(v) { if (v === null || v === undefined || v === "") return null; var n = Number(v); return isFinite(n) ? n : null; }
  function finite(v) { return typeof v === "number" && isFinite(v); }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function text(id, v) { var el = $(id); if (el) el.textContent = v == null || v === "" ? tr("unavailable") : String(v); }
  function sidQuery() { return "sid=" + encodeURIComponent(state.session || ""); }
  function authUrl(url) { return url + (url.indexOf("?") >= 0 ? "&" : "?") + sidQuery() + "&_=" + Date.now(); }
  function requireLogin(message) {
    state.session = "";
    sessionStorage.removeItem(LS + "session");
    clearInterval(state.timer);
    showLogin(message || tr("loginBad"), true);
  }
  function fmt(v, d) { return finite(v) ? v.toLocaleString("en-US", { maximumFractionDigits: d == null ? 1 : d }) : tr("unavailable"); }
  function bytes(v) {
    v = Number(v);
    if (!isFinite(v) || v < 0) return tr("unavailable");
    var u = ["B","KB","MB","GB","TB"], i = 0;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return fmt(v, i === 0 ? 0 : v >= 100 ? 0 : v >= 10 ? 1 : 2) + " " + u[i];
  }
  function bps(v) {
    var bits = Number(v) * 8;
    if (!isFinite(bits) || bits < 0) bits = 0;
    var u = ["bps","Kbps","Mbps","Gbps"], i = 0;
    while (bits >= 1000 && i < u.length - 1) { bits /= 1000; i++; }
    return fmt(bits, i === 0 ? 0 : bits >= 100 ? 0 : bits >= 10 ? 1 : 2) + " " + u[i];
  }
  function pct(v, total) { return total > 0 ? clamp(Math.round(v / total * 100), 0, 100) : 0; }
  function uptime(s) {
    s = Number(s) || 0;
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return state.lang === "ar" ? (d ? d + " يوم " + h + " س" : h + " س " + m + " د") : (d ? d + "d " + h + "h" : h + "h " + m + "m");
  }
  function nowTime() { return new Date().toLocaleTimeString(state.lang === "ar" ? "ar" : "en-US", { hour:"2-digit", minute:"2-digit", second:"2-digit" }); }
  function levelColor(level) { return { excellent:"#10B981", good:"#84CC16", mid:"#F59E0B", weak:"#EF4444", critical:"#DC2626", neutral:"#3B82F6" }[level || "neutral"] || "#3B82F6"; }
  function quality(kind, value) {
    if (!finite(value)) return { text:tr("unavailable"), level:"neutral", color:"#64748B" };
    var level = "weak";
    if (kind === "rsrp") level = value >= -80 ? "excellent" : value >= -90 ? "good" : value >= -100 ? "mid" : "weak";
    else if (kind === "rsrq") level = value >= -10 ? "excellent" : value >= -15 ? "good" : value >= -20 ? "mid" : "weak";
    else if (kind === "sinr") level = value >= 20 ? "excellent" : value >= 13 ? "good" : value >= 0 ? "mid" : "weak";
    else if (kind === "rssi") level = value >= -65 ? "excellent" : value >= -75 ? "good" : value >= -85 ? "mid" : "weak";
    else level = value < 55 ? "excellent" : value < 72 ? "good" : value < 88 ? "mid" : "weak";
    return { text: state.lang === "ar" ? ({excellent:"ممتاز", good:"جيد", mid:"متوسط", weak:"ضعيف"}[level]) : ({excellent:"Excellent", good:"Good", mid:"Fair", weak:"Weak"}[level]), level:level, color:levelColor(level) };
  }
  function signalPct(kind, value) {
    if (!finite(value)) return 0;
    if (kind === "rsrp") return clamp((value + 120) / 50 * 100, 0, 100);
    if (kind === "rsrq") return clamp((value + 25) / 20 * 100, 0, 100);
    if (kind === "sinr") return clamp((value + 10) / 40 * 100, 0, 100);
    if (kind === "rssi") return clamp((value + 100) / 50 * 100, 0, 100);
    return clamp(value, 0, 100);
  }
  function icon(name) {
    var p = {
      wifi:"M3.5 9a13 13 0 0 1 17 0M7 12.5a7.5 7.5 0 0 1 10 0M10.5 16a2.2 2.2 0 0 1 3 0M12 20h.01",
      signal:"M4 19h3M10 19h3V9h-3v10ZM16 19h3V4h-3v15Z",
      cpu:"M8 3v3m8-3v3M8 18v3m8-3v3M3 8h3m-3 8h3m12-8h3m-3 8h3M7 7h10v10H7z",
      net:"M12 5v5m0 0H6v5m6-5h6v5M6 19h.01M12 19h.01M18 19h.01",
      device:"M7 7h10v7H7zM9 18h6M12 14v4M5 21h14",
      bolt:"M13 2 4 14h7l-1 8 9-12h-7l1-8Z",
      refresh:"M20 12a8 8 0 0 1-13.7 5.7M4 12A8 8 0 0 1 17.7 6.3M17 3v4h-4M7 21v-4h4",
      sms:"M4 5h16v11H8l-4 4V5Z",
      gear:"M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z",
      shield:"M12 3 5 6v6c0 4 3 6.5 7 9 4-2.5 7-5 7-9V6l-7-3ZM9.5 12l1.8 1.8L15 10"
    }[name] || "M5 12h14M12 5v14";
    return '<svg class="ico" viewBox="0 0 24 24" fill="none"><path d="' + p + '" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  }
  function spark(values, color) {
    values = (values || []).filter(finite).slice(-24);
    if (values.length < 2) return '<svg class="spark" viewBox="0 0 120 24"><path d="M4 18H116" stroke="rgba(148,163,184,.35)" stroke-width="2" stroke-linecap="round"/></svg>';
    var min = Math.min.apply(null, values), max = Math.max.apply(null, values);
    if (max === min) max = min + 1;
    var d = values.map(function (v, i) {
      var x = 4 + i * (112 / (values.length - 1));
      var y = 20 - ((v - min) / (max - min)) * 16;
      return (i ? "L" : "M") + x.toFixed(1) + " " + y.toFixed(1);
    }).join(" ");
    return '<svg class="spark" viewBox="0 0 120 24"><path d="' + d + '" fill="none" stroke="' + color + '" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  }
  function pushHistory(key, value, max) {
    if (!state.histories[key]) state.histories[key] = [];
    if (finite(value)) state.histories[key].push(value);
    if (state.histories[key].length > (max || 120)) state.histories[key] = state.histories[key].slice(-(max || 120));
  }
  function saveHistories() { localStorage.setItem(LS + "histories", JSON.stringify(state.histories)); }
  function gauge(title, value, unit, sub, percent, color, histKey) {
    var dash = 314, off = dash - dash * clamp(percent || 0, 0, 100) / 100;
    return '<div class="gauge-card" style="box-shadow:0 0 34px ' + color + '18">' +
      '<div class="gauge"><svg viewBox="0 0 132 132" role="img">' +
      '<circle cx="66" cy="66" r="50" fill="none" stroke="rgba(148,163,184,.18)" stroke-width="12"/>' +
      '<circle cx="66" cy="66" r="50" fill="none" stroke="' + color + '" stroke-width="12" stroke-linecap="round" stroke-dasharray="' + dash + '" stroke-dashoffset="' + off + '" transform="rotate(-90 66 66)"/>' +
      '<text x="66" y="55" text-anchor="middle" fill="#94A3B8" font-size="11">' + esc(title) + '</text>' +
      '<text x="66" y="78" text-anchor="middle" fill="currentColor" font-size="17" font-weight="800">' + esc(value) + '</text>' +
      '<text x="66" y="96" text-anchor="middle" fill="#94A3B8" font-size="10">' + esc(unit || "") + '</text>' +
      '</svg></div><div class="muted" style="text-align:center">' + esc(sub || "") + '</div>' +
      spark(state.histories[histKey] || [], color) + '</div>';
  }
  function bar(v, total, color) { return '<div class="bar"><i style="width:' + pct(v, total) + '%;background:' + (color || "var(--grad)") + '"></i></div>'; }
  function card(title, body, chip, iconName) {
    return '<article class="card"><div class="card-head"><div class="title">' + icon(iconName || "bolt") + '<span>' + title + '</span></div>' + (chip ? '<span class="chip">' + chip + '</span>' : "") + '</div>' + body + '</article>';
  }
  function sectionHead(title, desc, chip) {
    return '<div class="section-head"><div><h3>' + title + '</h3><p>' + desc + '</p></div>' + (chip ? '<span class="chip">' + chip + '</span>' : "") + '</div>';
  }
  // Read a CSS custom property (theme-aware) with a fallback, so canvas drawings
  // follow the light/dark theme automatically.
  function cssVar(name, fallback) {
    try {
      var v = getComputedStyle(document.documentElement).getPropertyValue(name);
      v = (v || "").trim();
      return v || fallback;
    } catch (e) { return fallback; }
  }
  function drawChart(canvas, samples, opts) {
    if (!canvas) return;
    opts = opts || {};
    var rect = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    var w = Math.max(260, Math.floor(rect.width)), h = Math.max(160, Math.floor(rect.height));
    if (canvas.width !== w * dpr || canvas.height !== h * dpr) { canvas.width = w * dpr; canvas.height = h * dpr; }
    var ctx = canvas.getContext("2d"); ctx.setTransform(dpr,0,0,dpr,0,0); ctx.clearRect(0,0,w,h);
    var muted = cssVar("--muted", "#94A3B8"), grid = cssVar("--border", "rgba(148,163,184,.16)");
    var palette = opts.colors || [cssVar("--accent", "#06B6D4"), cssVar("--primary", "#3B82F6"), cssVar("--good", "#84CC16")];
    var pad = 26, iw = w - pad * 2, ih = h - pad * 2;
    ctx.strokeStyle = grid; ctx.lineWidth = 1;
    for (var g = 0; g < 4; g++) { var y = pad + ih * g / 3; ctx.beginPath(); ctx.moveTo(pad,y); ctx.lineTo(w-pad,y); ctx.stroke(); }
    if (!samples || samples.length < 2) { ctx.fillStyle=muted; ctx.textAlign="center"; ctx.fillText(tr("loading"), w/2, h/2); return; }
    var keys = opts.keys || ["rx","tx"], labels = opts.labels || keys, isPct = opts.fmt === "pct";
    var max = isPct ? 100 : 1;
    if (!isPct) samples.forEach(function (s) { keys.forEach(function (k) { max = Math.max(max, Number(s[k]) || 0); }); });
    function fmtVal(v) { return isPct ? Math.round(v) + "%" : bps(v); }
    function line(key, color) {
      var peak = {v:0,x:0,y:0};
      ctx.beginPath();
      samples.forEach(function (s, i) {
        var v = Number(s[key]) || 0, x = pad + iw * i / Math.max(1, samples.length - 1), y = pad + ih - ih * (v / max);
        if (v > peak.v) peak = {v:v,x:x,y:y};
        if (i) ctx.lineTo(x,y); else ctx.moveTo(x,y);
      });
      ctx.strokeStyle = color; ctx.lineWidth = 2.6; ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.stroke();
      ctx.fillStyle = color; ctx.beginPath(); ctx.arc(peak.x, peak.y, 4, 0, Math.PI * 2); ctx.fill();
    }
    keys.forEach(function (k, i) { line(k, palette[i % palette.length]); });
    // theme-aware legend
    ctx.font = "11px system-ui"; ctx.textAlign = "left";
    var lx = pad;
    keys.forEach(function (k, i) {
      var c = palette[i % palette.length], lab = labels[i] || k;
      ctx.fillStyle = c; ctx.fillRect(lx, 8, 10, 10);
      ctx.fillStyle = muted; ctx.fillText(lab, lx + 14, 17);
      lx += 14 + ctx.measureText(lab).width + 18;
    });
  }
  function totalTraffic(data) {
    if (data.traffic) return (Number(data.traffic.rx_bytes) || 0) + (Number(data.traffic.tx_bytes) || 0);
    return (data.interfaces || []).reduce(function (a, i) { return a + (Number(i.rx_bytes) || 0) + (Number(i.tx_bytes) || 0); }, 0);
  }
  function dataUsage(data) {
    var total = totalTraffic(data), dayKey = new Date().toISOString().slice(0,10), monthKey = dayKey.slice(0,7);
    function base(name, key) {
      var b = JSON.parse(localStorage.getItem(LS + name) || "null");
      if (!b || b.key !== key || total < b.bytes) { b = { key:key, bytes:total }; localStorage.setItem(LS + name, JSON.stringify(b)); }
      return Math.max(0, total - b.bytes);
    }
    return { day:base("dayBase", dayKey), month:base("monthBase", monthKey), total:total };
  }
  function trafficRates(data) {
    var now = Date.now(), rx = data.traffic ? Number(data.traffic.rx_bytes) || 0 : 0, tx = data.traffic ? Number(data.traffic.tx_bytes) || 0 : 0;
    if (!data.traffic) (data.interfaces || []).forEach(function (i) { if (/^(lan|wan|phy)/.test(i.name)) { rx += Number(i.rx_bytes) || 0; tx += Number(i.tx_bytes) || 0; } });
    var rxBps = data.traffic ? Number(data.traffic.rx_bps) || 0 : 0, txBps = data.traffic ? Number(data.traffic.tx_bps) || 0 : 0;
    if ((!rxBps && !txBps) && state.previousTraffic && state.previousAt) {
      var dt = Math.max(1, (now - state.previousAt) / 1000);
      rxBps = Math.max(0, (rx - state.previousTraffic.rx) / dt);
      txBps = Math.max(0, (tx - state.previousTraffic.tx) / dt);
    }
    state.previousTraffic = { rx:rx, tx:tx }; state.previousAt = now;
    return { rx:rxBps, tx:txBps, totalRx:rx, totalTx:tx };
  }
  // Offline MAC vendor (OUI) table — first 3 octets -> manufacturer. Covers the most
  // common consumer/IoT vendors; fully local, no lookups. "LAA" = locally-administered
  // (randomized private) MAC used by modern phones for privacy.
  var OUI = {
    "3C5AB4":"Google","1A11A0":"Google","F0EF86":"Google","D8EB46":"Google",
    "F4F5D8":"Google","001A11":"Google","AC63BE":"Amazon","44650D":"Amazon","F0272D":"Amazon",
    "68370E":"Apple","F0DBF8":"Apple","A85C2C":"Apple","3C0754":"Apple","F80377":"Apple",
    "9C207B":"Apple","D0817A":"Apple","A4B197":"Apple","BCD074":"Apple","78CA39":"Apple",
    "F0989D":"Apple","881FA1":"Apple","AC1F74":"Apple","64B0A6":"Apple","24F094":"Apple",
    "C82A14":"Apple","DC2B2A":"Apple","E0B52D":"Apple","F0B479":"Apple","98460A":"Apple",
    "E4CE8F":"Apple","6C4008":"Apple","B8C111":"Apple","8866A5":"Apple","D49A20":"Apple",
    "003EE1":"Apple","040CCE":"Apple","28E02C":"Apple","70CD60":"Apple","A0999B":"Apple",
    "F4F15A":"Apple","B827EB":"Raspberry Pi","DCA632":"Raspberry Pi","E45F01":"Raspberry Pi","2CCF67":"Raspberry Pi",
    "D83ADD":"Raspberry Pi","28CDC1":"Raspberry Pi","5CF370":"Xiaomi","64B473":"Xiaomi","286C07":"Xiaomi",
    "7C1DD9":"Xiaomi","F8A45F":"Xiaomi","98FAE3":"Xiaomi","742344":"Xiaomi","A091A2":"Xiaomi",
    "50EC50":"Xiaomi","C46AB7":"Xiaomi","78:11:DC":"Xiaomi","009EC8":"Xiaomi","2CFDA1":"Xiaomi",
    "AC64DD":"Xiaomi","04CF8C":"Xiaomi","FC64BA":"Xiaomi","8CBEBE":"Xiaomi","3C47AE":"Xiaomi",
    "F48B32":"Xiaomi","2CF0A2":"Xiaomi","D024F7":"Xiaomi","001874":"Huawei","00259E":"Huawei",
    "080088":"Huawei","2008ED":"Huawei","283152":"Huawei","48435A":"Huawei","5C7D5E":"Huawei",
    "781DBA":"Huawei","AC4E91":"Huawei","D0D04B":"Huawei","E8088B":"Huawei","F83DFF":"Huawei",
    "00E0FC":"Huawei","047503":"Huawei","10C61F":"Huawei","4C8BEF":"Huawei","702E22":"Huawei",
    "0C1420":"Samsung","1899E8":"Samsung","28395E":"Samsung","345B22":"Samsung","4844F7":"Samsung",
    "5001BB":"Samsung","6C2F2C":"Samsung","78BDBC":"Samsung","8425DB":"Samsung","9401C2":"Samsung",
    "A00798":"Samsung","B0DF3A":"Samsung","C0BDD1":"Samsung","D0176A":"Samsung","E8508B":"Samsung",
    "F409D8":"Samsung","001632":"Samsung","0021D1":"Samsung","5CE8EB":"Samsung","EC1F72":"Samsung",
    "001A2B":"Intel","001B21":"Intel","0024D7":"Intel","3C970E":"Intel","7CB27D":"Intel",
    "A0A8CD":"Intel","B4B676":"Intel","E4A471":"Intel","F8633F":"Intel","8CC841":"Intel",
    "00155D":"Microsoft","0017FA":"Microsoft","281878":"Microsoft","7CED8D":"Microsoft","C0335E":"Microsoft",
    "00E04C":"Realtek","525400":"QEMU/KVM","000C29":"VMware","005056":"VMware","080027":"VirtualBox",
    "001DD8":"Microsoft","D8FE8F":"Sony","FCF152":"Sony","AC9B0A":"Sony","000D93":"Sony",
    "001966":"LG","0021FB":"LG","10683F":"LG","3CBDD8":"LG","6CD68A":"LG","A816B2":"LG",
    "C4438F":"LG","001E75":"LG","001AEF":"OPPO","10A5D0":"OPPO","3CA582":"OPPO","5C0947":"OPPO",
    "84D6D0":"OnePlus","C0EEFB":"OnePlus","64A2F9":"OnePlus","94652D":"OnePlus","2CF01A":"OnePlus",
    "0016A4":"Vivo","2C598A":"Vivo","30766F":"Vivo","BCAEE3":"Vivo","D856BD":"Vivo",
    "F0761C":"TP-Link","5091E3":"TP-Link","A42BB0":"TP-Link","EC086B":"TP-Link","6466B3":"TP-Link",
    "5C628B":"MikroTik","4C5E0C":"MikroTik","6C3B6B":"MikroTik","D4CA6D":"MikroTik","E48D8C":"MikroTik",
    "742401":"MikroTik","2CC81B":"MikroTik","B869F4":"MikroTik","08551A":"MikroTik","CC2DE0":"MikroTik",
    "F81A67":"TP-Link","D8150D":"TP-Link","1CBFCE":"Shenzhen","001788":"Philips Hue","ECB5FA":"Philips Hue",
    "18B430":"Nest","642944":"Nest","00D02D":"Ubiquiti","44D9E7":"Ubiquiti","788A20":"Ubiquiti",
    "687251":"Ubiquiti","FCECDA":"Ubiquiti","74ACB9":"Ubiquiti","E063DA":"Ubiquiti","B4FBE4":"Ubiquiti"
  };
  function ouiVendor(mac) {
    if (!mac) return "";
    var hex = String(mac).replace(/[^0-9a-fA-F]/g, "").toUpperCase();
    if (hex.length < 6) return "";
    // second-least-significant bit of first octet set => locally-administered (random) MAC
    var b1 = parseInt(hex.slice(0, 2), 16);
    if (b1 & 0x02) return state.lang === "ar" ? "خاص (عشوائي)" : "Private (random)";
    return OUI[hex.slice(0, 6)] || "";
  }
  function mergeDevices(data) {
    var map = {};
    (data.devices || []).forEach(function (d) { var k = (d.mac || d.ip || Math.random()).toLowerCase(); map[k] = { ip:d.ip, mac:d.mac, iface:d.iface, type:d.type || "Ethernet" }; });
    (data.wifi || []).forEach(function (w) { (w.stations || []).forEach(function (s) { var k = (s.mac || Math.random()).toLowerCase(); map[k] = Object.assign(map[k] || {}, { mac:s.mac, ip:s.ip, iface:w.iface, type:"WiFi", signal:s.signal_dbm, rate:s.rate }); }); });
    return Object.keys(map).map(function (k) { map[k].vendor = ouiVendor(map[k].mac); return map[k]; });
  }
  function wifiBand(data, band) { return (data.wifi || []).filter(function (w) { return w.band === band; })[0] || null; }
  function updateAvailability(ok) {
    var t = Date.now();
    state.availability.push({ t:t, ok:!!ok });
    var cutoff = t - 24 * 3600 * 1000;
    state.availability = state.availability.filter(function (x) { return x.t >= cutoff; }).slice(-288);
    localStorage.setItem(LS + "availability", JSON.stringify(state.availability));
  }
  function availabilityHtml() {
    if (!state.availability.length) return '<div class="empty">' + tr("loading") + '</div>';
    return '<div style="display:grid;grid-template-columns:repeat(' + state.availability.length + ',1fr);gap:2px;height:34px">' +
      state.availability.map(function (x) { return '<i title="' + new Date(x.t).toLocaleTimeString() + '" style="border-radius:4px;background:' + (x.ok ? "var(--excellent)" : "var(--weak)") + '"></i>'; }).join("") + '</div>';
  }
  function toast(msg) { var el = $("toast"); if (!el) return; el.textContent = msg; el.classList.add("show"); clearTimeout(state.toastTimer); state.toastTimer = setTimeout(function () { el.classList.remove("show"); }, 3500); }
  function event(msg, type) {
    state.events.unshift({ t:Date.now(), msg:msg, type:type || "info" });
    state.events = state.events.slice(0, 80);
    localStorage.setItem(LS + "events", JSON.stringify(state.events));
  }
  function loginMessage(msg, bad) {
    var el = $("loginMsg");
    if (!el) return;
    el.textContent = msg || "";
    el.className = "login-msg" + (bad ? " bad" : "");
  }
  function setLoginText() {
    if ($("loginMark")) $("loginMark").innerHTML = icon("wifi");
    text("loginSubtitle", tr("loginSubtitle"));
    text("loginUserLabel", tr("username"));
    text("loginPassLabel", tr("password"));
    text("loginBtn", tr("login"));
    text("loginWarning", tr("rootPassWarn"));
    var pass = $("loginPass");
    if (pass) pass.placeholder = tr("passwordHint");
  }
  function showLogin(msg, bad) {
    clearInterval(state.timer);
    if ($("appShell")) $("appShell").hidden = true;
    if ($("loginScreen")) $("loginScreen").hidden = false;
    setLoginText();
    loginMessage(msg || "", bad);
    setTimeout(function () { var u = $("loginUser"); if (u) u.focus(); }, 60);
  }
  function showDashboard() {
    if ($("loginScreen")) $("loginScreen").hidden = true;
    if ($("appShell")) $("appShell").hidden = false;
    loginMessage("", false);
    showSection("overview");
    startPolling();
  }
  async function ubusCall(sid, object, method, params) {
    var res = await fetch(AUTH, {
      method:"POST",
      cache:"no-store",
      headers:{ "Content-Type":"application/json" },
      body:JSON.stringify({ jsonrpc:"2.0", id:Date.now(), method:"call", params:[sid || ANON, object, method, params || {}] })
    });
    var json = await res.json();
    if (!json.result || json.result[0] !== 0) throw new Error("ubus " + (json.result ? json.result[0] : "error"));
    return json.result[1] || {};
  }
  async function primeLuciSession(username, password) {
    try {
      var body = new URLSearchParams();
      body.set("luci_username", username || "root");
      body.set("luci_password", password || "");
      await fetch("/cgi-bin/luci/", {
        method: "POST",
        credentials: "same-origin",
        cache: "no-store",
        body: body
      });
    } catch (e) {}
  }
  async function login(username, password) {
    loginMessage(tr("loginWait"), false);
    try {
      var user = username || "root";
      var pass = password || "";
      var data = await ubusCall(ANON, "session", "login", { username:user, password:pass, timeout:3600 });
      if (!data.ubus_rpc_session) throw new Error("missing session");
      state.session = data.ubus_rpc_session;
      sessionStorage.setItem(LS + "session", state.session);
      await primeLuciSession(user, pass);
      toast(tr("loginOk"));
      showDashboard();
    } catch (e) {
      state.session = "";
      sessionStorage.removeItem(LS + "session");
      showLogin(tr("loginBad"), true);
    }
  }
  async function validateSession() {
    if (!state.session) return false;
    try {
      await ubusCall(state.session, "system", "board", {});
      return true;
    } catch (e) {
      state.session = "";
      sessionStorage.removeItem(LS + "session");
      return false;
    }
  }
  async function logout() {
    var sid = state.session;
    state.session = "";
    sessionStorage.removeItem(LS + "session");
    clearInterval(state.timer);
    if (sid) {
      try { await ubusCall(sid, "session", "destroy", { ubus_rpc_session:sid }); } catch (e) {}
    }
    showLogin(tr("loggedOut"), false);
  }

  function renderChrome() {
    document.documentElement.lang = state.lang;
    document.documentElement.dir = state.lang === "ar" ? "rtl" : "ltr";
    document.documentElement.dataset.theme = state.theme;
    $("heroSubtitle").textContent = tr("subtitle");
    $("refreshBtn").textContent = tr("refresh");
    $("themeBtn").textContent = state.theme === "dark" ? tr("dark") : tr("light");
    $("themeBtn").classList.toggle("active", state.theme === "dark");
    $("themeBtn").setAttribute("aria-pressed", state.theme === "dark" ? "true" : "false");
    if ($("logoutBtn")) $("logoutBtn").textContent = tr("logout");
    if ($("openWrtBtn")) $("openWrtBtn").textContent = state.lang === "ar" ? "ضبط OpenWrt" : "OpenWrt Settings";
    $("intervalSelect").value = String(state.interval);
    $("langAr").className = state.lang === "ar" ? "active" : "";
    $("langEn").className = state.lang === "en" ? "active" : "";
    $("brandMark").innerHTML = icon("wifi");
    var nav = [
      ["overview","overview","bolt"],
      ["network","network","net"],
      ["devices","devices","device"],
      ["wifi","wifi","wifi"],
      ["system","system","cpu"],
      ["quick","quick","gear"],
      ["isolation","isolation","shield"],
      ["netmgr","netmgr","net"],
      ["wifimgr","wifimgr","wifi"],
      ["sysmgr","sysmgr","cpu"],
      ["actions","actions","gear"]
    ];
    $("nav").innerHTML = nav.map(function (n, i) { return '<button data-section="' + n[0] + '" class="' + (i ? "" : "active") + '">' + icon(n[2]) + '<span>' + tr(n[1]) + '</span></button>'; }).join("");
    Array.prototype.forEach.call(document.querySelectorAll("[data-section]"), function (b) {
      b.onclick = function () { showSection(b.dataset.section); };
    });
    setLoginText();
  }
  function showSection(id) {
    document.body.dataset.activeSection = id;
    ["overview","network","devices","wifi","system","quick","isolation","netmgr","wifimgr","sysmgr","actions"].forEach(function (s) { if ($(s)) $(s).hidden = s !== id; });
    Array.prototype.forEach.call(document.querySelectorAll("[data-section]"), function (b) { b.classList.toggle("active", b.dataset.section === id); });
    if (adminGroups()[id] && $(id) && (!$(id).innerHTML || $(id).dataset.uiVersion !== UI_VERSION)) {
      $(id).innerHTML = renderAdminBranch(id);
      $(id).dataset.uiVersion = UI_VERSION;
      bindDynamic();
    }
    if (id === "isolation" && $("isolation") && $("isolation").dataset.uiVersion !== UI_VERSION) {
      $("isolation").innerHTML = renderIsolation();
      $("isolation").dataset.uiVersion = UI_VERSION;
      bindDynamic();
      loadControl("isolation");
    }
    if (id === "quick" && $("quick") && $("quick").dataset.uiVersion !== UI_VERSION) {
      $("quick").innerHTML = renderQuick();
      $("quick").dataset.uiVersion = UI_VERSION;
      bindDynamic();
      loadControl("wizard");
    }
    window.scrollTo({ top:0, behavior:"smooth" });
    setTimeout(loadActiveControl, 0);
  }
  function openSmartSettings() {
    showSection("overview");
  }
  function renderKpis(data, rates) {
    var w24 = wifiBand(data, "2.4G"), w5 = wifiBand(data, "5G");
    var back = data.backhaul || {}, internet = back.online ? (back.device || tr("online")) : tr("lanOnly");
    var list = [
      [tr("uptime"), uptime(data.uptime), "uptime", 1],
      [tr("model"), data.model || tr("unavailable"), "model", 1],
      [tr("firmware"), "OpenWrt " + (data.os || ""), "firmware", 1],
      [tr("internet"), internet, "internet", back.online ? 1 : 0],
      [tr("deviceCount"), String(Math.max(Number(data.clients)||0, mergeDevices(data).length, (w24?Number(w24.clients)||0:0)+(w5?Number(w5.clients)||0:0))), "devices", 1],
      ["2.4G", w24 ? ((w24.ssid || "2.4G") + " · " + (w24.clients || 0)) : tr("unavailable"), "w24", w24 ? 1 : 0],
      ["5G", w5 ? ((w5.ssid || "5G") + " · " + (w5.clients || 0)) : tr("unavailable"), "w5", w5 ? 1 : 0],
      [tr("updated"), nowTime(), "updated", 1]
    ];
    pushHistory("kpiRx", rates.rx, 60); pushHistory("kpiTx", rates.tx, 60);
    $("kpiBar").innerHTML = list.map(function (x, i) {
      var h = i === 3 ? state.availability.map(function (a) { return a.ok ? 1 : 0; }) : (i === 0 ? state.histories.kpiRx : state.histories.kpiTx);
      return '<div class="kpi"><span>' + esc(x[0]) + '</span><b>' + esc(x[1]) + '</b>' + spark(h || [], x[3] ? "#06B6D4" : "#EF4444") + '</div>';
    }).join("");
  }
  function renderTraffic(data, rates, prefix) {
    prefix = prefix || "main";
    pushHistory("rx", rates.rx, 60); pushHistory("tx", rates.tx, 60);
    var samples = (state.histories.rx || []).map(function (rx, i) { return { rx:rx, tx:(state.histories.tx || [])[i] || 0 }; });
    var canvasId = prefix + "TrafficCanvas";
    var body = '<canvas id="' + canvasId + '"></canvas><div class="grid two" style="margin-top:12px">' +
      '<div class="traffic-box"><span>RX</span><b class="latin">' + bps(rates.rx) + '</b><small class="muted">' + bytes(rates.totalRx) + '</small></div>' +
      '<div class="traffic-box"><span>TX</span><b class="latin">' + bps(rates.tx) + '</b><small class="muted">' + bytes(rates.totalTx) + '</small></div></div>';
    setTimeout(function () { drawChart($(canvasId), samples, { keys:["rx","tx"] }); }, 0);
    return card(tr("networkTitle"), body, "60s peaks", "net");
  }
  function renderData(data) {
    var u = dataUsage(data), dailyBudget = Number(localStorage.getItem(LS + "dailyBudgetGb") || 5), monthBudget = Number(localStorage.getItem(LS + "monthBudgetGb") || 100);
    var dayTotal = dailyBudget * 1024 * 1024 * 1024, monthTotal = monthBudget * 1024 * 1024 * 1024;
    var body = '<div class="gauge-grid">' +
      gauge(tr("daily"), bytes(u.day), dailyBudget + " GB", tr("budget"), pct(u.day, dayTotal), pct(u.day, dayTotal) > 85 ? "#EF4444" : "#06B6D4", "kpiRx") +
      gauge(tr("monthly"), bytes(u.month), monthBudget + " GB", tr("budget"), pct(u.month, monthTotal), pct(u.month, monthTotal) > 85 ? "#EF4444" : "#8B5CF6", "kpiTx") +
      '</div><p class="muted">' + tr("noQuota") + '</p>' +
      '<div class="grid two"><label class="kv"><div><span>' + tr("daily") + ' GB</span><input id="dailyBudget" type="number" min="1" value="' + dailyBudget + '"></div></label><label class="kv"><div><span>' + tr("monthly") + ' GB</span><input id="monthBudget" type="number" min="1" value="' + monthBudget + '"></div></label></div>';
    return card(tr("budget"), body, "local", "bolt");
  }
  function renderDevices(data) {
    var rows = mergeDevices(data);
    if (!rows.length) return sectionHead(tr("devices"), "IP / MAC / traffic", "") + '<div class="empty">' + tr("unavailable") + '</div>';
    return sectionHead(tr("devices"), "IP / MAC / " + tr("vendor") + " / RSSI", rows.length + "") +
      '<div class="table-wrap"><table><thead><tr><th>' + tr("type") + '</th><th>IP</th><th>MAC</th><th>' + tr("vendor") + '</th><th>' + tr("link") + '</th><th>RSSI</th><th>' + tr("action") + '</th></tr></thead><tbody>' +
      rows.map(function (d) {
        var vn = d.vendor || tr("unknownVendor");
        var m = esc(d.mac || "");
        var acts = m ? '<button class="btn dev-action" data-dev-mac="' + m + '" data-dev-act="block_mac">' + tr("block") + '</button> <button class="btn dev-action" data-dev-mac="' + m + '" data-dev-act="unblock_mac">' + tr("allow") + '</button>' : "";
        return '<tr><td>' + icon(d.type === "WiFi" ? "wifi" : "device") + " " + esc(d.type || "") + '</td><td class="latin">' + esc(d.ip || tr("unavailable")) + '</td><td class="latin">' + esc((d.mac || tr("unavailable")).toUpperCase()) + '</td><td>' + esc(vn) + '</td><td>' + esc(d.iface || "") + '</td><td class="latin">' + (num(d.signal) !== null ? d.signal + " dBm" : tr("unavailable")) + '</td><td>' + acts + '</td></tr>';
      }).join("") +
      '</tbody></table></div>';
  }
  function renderWifi(data) {
    var w = data.wifi || [];
    var body = w.length ? '<div class="grid two">' + w.map(function (x) {
      var sig = num(x.signal_dbm), q = quality("rssi", sig);
      var sta = (x.stations || []).map(function (s) {
        var ss = num(s.signal_dbm), qq = quality("rssi", ss);
        return '<div class="kv"><div><span class="latin">' + esc(s.ip || s.mac || tr("unavailable")) + '</span><b class="latin">' + (finite(ss) ? ss + " dBm" : tr("unavailable")) + '</b></div>' + bar(finite(ss) ? signalPct("rssi", ss) : 0, 100, qq.color) + '</div>';
      }).join("") || '<div class="empty">' + tr("unavailable") + '</div>';
      return card(esc(x.ssid || x.iface), '<div class="kv"><div><span>Band</span><b>' + esc(x.band || "") + '</b></div><div><span>Channel</span><b>' + esc(x.channel || "") + '</b></div><div><span>Mode</span><b class="latin">' + esc(x.htmode || "") + '</b></div><div><span>Clients</span><b>' + (x.clients || 0) + '</b></div><div><span>RSSI</span><b class="latin" style="color:' + q.color + '">' + (finite(sig) ? sig + " dBm" : tr("unavailable")) + '</b></div></div><h4>Clients</h4>' + sta, x.hw_modes || "", "wifi");
    }).join("") + '</div>' : '<div class="empty">' + tr("unavailable") + '</div>';
    if (w.length) {
      // draw now, then once more after the section finishes expanding (canvas measured
      // too early renders scaled-up, overlapping labels)
      setTimeout(function () { drawChannels($("channelCanvas"), w); }, 0);
      setTimeout(function () { drawChannels($("channelCanvas"), w); }, 450);
    }
    var chanCard = w.length ? card(state.lang === "ar" ? "إشغال القنوات" : "Channel occupancy",
      '<canvas id="channelCanvas" style="width:100%;height:150px"></canvas>', "2.4G / 5G", "signal") : "";
    return sectionHead("WiFi AX / AC / N", "Clients, RSSI, link rate", "offline") + chanCard + body;
  }
  // theme-aware Wi-Fi channel occupancy (net-new, offline canvas)
  function drawChannels(canvas, wifiList) {
    if (!canvas) return;
    // measure the PARENT box, not the canvas: the canvas rect can be read before its
    // 100%-width style settles, baking a small bitmap that CSS then stretches into
    // giant blurry overlapping labels
    var host = canvas.parentElement || canvas;
    var rect = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    var hostW = host.getBoundingClientRect().width;
    if (window.getComputedStyle) {
      var cs = getComputedStyle(host);
      hostW -= (parseFloat(cs.paddingLeft) || 0) + (parseFloat(cs.paddingRight) || 0);
    }
    var w = Math.max(260, Math.floor(hostW || rect.width)), h = Math.max(130, Math.floor(rect.height) || 150);
    if (canvas.width !== w * dpr || canvas.height !== h * dpr) { canvas.width = w * dpr; canvas.height = h * dpr; }
    var ctx = canvas.getContext("2d"); ctx.setTransform(dpr,0,0,dpr,0,0); ctx.clearRect(0,0,w,h);
    var axis = cssVar("--muted", "#94A3B8"), grid = cssVar("--border", "rgba(148,163,184,.16)");
    var chans = [1,2,3,4,5,6,7,8,9,10,11,36,40,44,48,149,153,157,161,165];
    var pad = 20, base = h - 20, slot = (w - pad * 2) / (chans.length - 1);
    function xOf(i) { return pad + slot * i; }
    ctx.strokeStyle = grid; ctx.beginPath(); ctx.moveTo(pad, base); ctx.lineTo(w - pad, base); ctx.stroke();
    ctx.fillStyle = axis; ctx.font = "9px system-ui"; ctx.textAlign = "center";
    chans.forEach(function (c, i) {
      // 2.4G: odd channels; 5G: every other one starting at 40 so the 11|36 band
      // boundary never renders as one glued number
      var show = c < 14 ? (c % 2 === 1) : ((i - 12) % 2 === 0);
      if (show) ctx.fillText(c, xOf(i), h - 5);
    });
    var maxCl = 1; (wifiList || []).forEach(function (x) { maxCl = Math.max(maxCl, Number(x.clients) || 0); });
    (wifiList || []).forEach(function (x) {
      var ch = Number(x.channel) || 0, idx = chans.indexOf(ch); if (idx < 0) return;
      var band5 = x.band === "5G";
      var color = band5 ? cssVar("--primary", "#3B82F6") : cssVar("--accent", "#06B6D4");
      var mhz = /80/.test(x.htmode) ? 80 : /40/.test(x.htmode) ? 40 : 20;
      var span = slot * (mhz / 20) * 0.9 + slot * 0.4;
      var cl = Math.max(0, Number(x.clients) || 0), bh = (base - pad) * (0.3 + 0.7 * (cl / maxCl));
      bh = Math.min(bh, base - 34); // keep the bubble label inside the canvas
      var cx = xOf(idx);
      ctx.beginPath(); ctx.moveTo(cx - span, base); ctx.quadraticCurveTo(cx, base - bh - 14, cx + span, base); ctx.closePath();
      ctx.fillStyle = hexA(color, 0.28); ctx.fill();
      ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.beginPath();
      ctx.moveTo(cx - span, base); ctx.quadraticCurveTo(cx, base - bh - 14, cx + span, base); ctx.stroke();
      ctx.fillStyle = color; ctx.font = "bold 11px system-ui"; ctx.textAlign = "center";
      ctx.fillText((band5 ? "5G·" : "2.4G·") + ch + " (" + cl + ")", cx, base - bh - 18);
    });
  }
  // rgba() from a hex/color var with alpha
  function hexA(c, a) {
    c = (c || "").trim();
    if (c.charAt(0) === "#") {
      var n = c.length === 4 ? c.replace(/#(.)(.)(.)/, "#$1$1$2$2$3$3") : c;
      var r = parseInt(n.substr(1,2),16), g = parseInt(n.substr(3,2),16), b = parseInt(n.substr(5,2),16);
      if (isFinite(r) && isFinite(g) && isFinite(b)) return "rgba(" + r + "," + g + "," + b + "," + a + ")";
    }
    return c || "rgba(6,182,212," + a + ")";
  }
  function renderSystem(data) {
    var mem = data.mem || {}, st = data.storage || {}, cpu = data.cpu || {};
    var usedMem = (Number(mem.total)||0) - (Number(mem.available)||0), memPct = pct(usedMem, Number(mem.total)||0);
    var stPct = pct(Number(st.used)||0, Number(st.total)||0), cpuPct = clamp(Number(cpu.percent)||0,0,100), temp = num(data.temperature_c);
    pushHistory("cpu", cpuPct, 60); pushHistory("ram", memPct, 60); pushHistory("storage", stPct, 60);
    var body = '<div class="gauge-grid">' +
      gauge("CPU", cpuPct + "%", "load", quality("system", cpuPct).text, cpuPct, quality("system", cpuPct).color, "cpu") +
      gauge("RAM", memPct + "%", bytes(usedMem), bytes(mem.available) + " free", memPct, quality("system", memPct).color, "ram") +
      gauge("Storage", stPct + "%", bytes(st.used), bytes(st.available) + " free", stPct, quality("system", stPct).color, "storage") +
      gauge("Temp", finite(temp) ? fmt(temp,1) : tr("unavailable"), finite(temp) ? "C" : "", finite(temp) ? tr("ok") : tr("unavailable"), finite(temp) ? clamp(temp,0,100) : 0, finite(temp) ? quality("system", temp).color : "#64748B", "temp") +
      '</div>';
    if (finite(temp)) pushHistory("temp", clamp(temp,0,100), 60);
    // theme-aware CPU/RAM/temp trend (net-new chart)
    var trend = (state.histories.cpu || []).map(function (c, i) {
      return { cpu:c, ram:(state.histories.ram||[])[i]||0, temp:(state.histories.temp||[])[i]||0 };
    });
    setTimeout(function () {
      drawChart($("sysTrendCanvas"), trend, {
        keys:["cpu","ram","temp"], labels:[tr("cpu"),tr("ram"),tr("temp")], fmt:"pct",
        colors:[cssVar("--accent","#06B6D4"), cssVar("--good","#84CC16"), cssVar("--mid","#F59E0B")]
      });
    }, 0);
    var trendCard = card(state.lang === "ar" ? "مسار الموارد" : "Resource trend",
      '<canvas id="sysTrendCanvas" style="width:100%;height:180px"></canvas>', "CPU / RAM / " + tr("temp"), "cpu");
    return sectionHead(tr("systemTitle"), "loadavg / free / overlay / thermal", "thresholds") + card("Health", body, "live", "cpu") + trendCard + card("Availability 24h", availabilityHtml(), "local", "bolt");
  }
  function renderNetwork(data, rates) {
    var interfaces = data.interfaces || [];
    var table = '<div class="table-wrap"><table><thead><tr><th>Interface</th><th>Status</th><th>Speed</th><th>RX/TX</th><th>Total</th><th>Errors/Drops</th></tr></thead><tbody>' +
      interfaces.map(function (i) { return '<tr><td class="latin">' + esc(i.name) + '</td><td><span class="chip ' + (i.connected ? "ok" : "bad") + '">' + (i.connected ? "up" : "down") + '</span></td><td class="latin">' + (i.speed_mbps ? i.speed_mbps + " Mbps" : tr("unavailable")) + '</td><td class="latin">' + bps(i.name === "br-lan" ? rates.rx : 0) + " / " + bps(i.name === "br-lan" ? rates.tx : 0) + '</td><td class="latin">' + bytes(i.rx_bytes) + " / " + bytes(i.tx_bytes) + '</td><td class="latin">' + (i.rx_errors||0) + "/" + (i.tx_errors||0) + " · " + (i.rx_dropped||0) + "/" + (i.tx_dropped||0) + '</td></tr>'; }).join("") +
      '</tbody></table></div>';
    var ping = card("Latency / Jitter", '<canvas id="latencyCanvas"></canvas><p class="muted" id="latencyText"></p>', "fetch", "net");
    setTimeout(function () { drawChart($("latencyCanvas"), (state.histories.latency || []).map(function (v) { return { rx:v }; }), { keys:["rx"] }); }, 0);
    return sectionHead(tr("networkTitle"), "RX/TX, drops, latency, speed test", data.backhaul && data.backhaul.online ? tr("online") : tr("lanOnly")) + '<div class="grid two">' + renderTraffic(data, rates, "network") + ping + '</div>' + table;
  }
  function adminGroups() {
    var ar = state.lang === "ar";
    // Only sections whose backend is fully supported on this build are listed.
    // (SQM and igmpproxy-IPTV are intentionally omitted: SQM caps throughput and
    //  igmpproxy/udpxy are not installed.)
    return {
      netmgr: {
        title: ar ? "الشبكة المحلية" : "Network",
        desc: ar ? "DHCP، السويتش والمنافذ، حماية الحلقات، الضيوف والجدولة، الجيران" : "DHCP, switch/ports, loop guard, guest & schedule, neighbors",
        items: [
          ["dhcp", ar ? "الشبكة / DHCP" : "LAN / DHCP", ""],
          ["switchmgr", ar ? "السويتش والمنافذ" : "Switch / Ports", ""],
          ["loopguard", ar ? "حماية الحلقات (STP)" : "Loop Guard", ""],
          ["netcfg", ar ? "شبكة الضيوف والجدولة" : "Guest & Reboot", ""],
          ["neighbors", ar ? "جيران الجسر" : "Bridge Neighbors", ""]
        ]
      },
      wifimgr: {
        title: ar ? "لاسلكي AX1800" : "Wireless AX1800",
        desc: ar ? "الشبكات، محلل القنوات، تحسين الأداء، الأجهزة المتصلة، طاقة البث" : "Networks, analyzer, optimizer, clients, TX power",
        items: [
          ["wireless", ar ? "شبكات الواي فاي" : "Wi-Fi Networks", ""],
          ["analyzer", ar ? "محلل القنوات" : "Analyzer", ""],
          ["optimizer", ar ? "تحسين الأداء" : "Optimizer", ""],
          ["clients", ar ? "أجهزة الواي فاي" : "Wi-Fi Clients", ""],
          ["power", ar ? "طاقة البث" : "TX Power", "protected"]
        ]
      },
      sysmgr: {
        title: ar ? "النظام والأدوات" : "System & Tools",
        desc: ar ? "معلومات الجهاز، أدوات الشبكة، اختبار السرعة" : "Device info, network tools, speed test",
        items: [
          ["specs", ar ? "معلومات الجهاز" : "Device Info", ""],
          ["nettools", ar ? "أدوات الشبكة" : "Network Tools", ""],
          ["speed", ar ? "اختبار السرعة" : "Speed Test", ""]
        ]
      }
    };
  }
  function renderControlData(section, data) {
    if (!data || data.ok === false) {
      return '<div class="ctl-status">' + esc((data && (data.summary || data.text)) || "Control data unavailable") + '</div>';
    }
    if (section === "wizard") return renderWizardControl(section, data);
    var html = "";
    if (data.cards && data.cards.length) {
      html += '<div class="ctl-cards">' + data.cards.map(function (c) {
        return '<div class="ctl-card ' + esc(c.level || "neutral") + '"><span>' + esc(c.label) + '</span><b>' + esc(c.value) + '</b><small>' + esc(c.hint || "") + '</small></div>';
      }).join("") + '</div>';
    }
    if (data.form && data.form.length) {
      html += formWithGroups(data.form);
    }
    if (data.actions && data.actions.length) {
      html += '<div class="branch-actions">' + data.actions.filter(function (a) { return !a.url; }).map(function (a) {
        if (a.id === "logout") return '<button class="btn primary" data-smart-logout="1">' + esc(a.label || tr("logout")) + '</button>';
        var cls = a.confirm ? "btn" : "btn primary";
        return '<button class="' + cls + '" data-ctl-section="' + esc(section) + '" data-ctl-action="' + esc(a.id) + '" data-ctl-input="' + esc(a.input || "") + '" data-ctl-confirm="' + (a.confirm ? "1" : "") + '">' + esc(a.label || a.id) + '</button>';
      }).join("") + '</div>';
    }
    if (data.actions && data.actions.some(function (a) { return a.input === "host"; })) {
      html += '<div class="ctl-line"><input class="ctl-input latin" id="ctlHost_' + sid(section) + '" value="192.168.1.1" autocomplete="off" inputmode="url"></div>';
    }
    if (data.text) html += '<pre class="ctl-pre">' + esc(data.text) + '</pre>';
    return html || '<div class="ctl-status">No details returned.</div>';
  }
  function groupTitle(g) {
    var m = {
      guard: state.lang === "ar" ? "🛡️ الحمايات العامة (تشغيل/إيقاف)" : "🛡️ General protections",
      wifi: state.lang === "ar" ? "📶 عزل شبكات الواي فاي" : "📶 Wi-Fi isolation",
      ports: state.lang === "ar" ? "🔌 منافذ الكيبل (LAN)" : "🔌 LAN cable ports",
      device: state.lang === "ar" ? "الجهاز" : "Device",
      security: state.lang === "ar" ? "الحماية" : "Security",
      advanced: state.lang === "ar" ? "متقدم" : "Advanced"
    };
    return m[g] || "";
  }
  // Render a form, inserting a subheading whenever the field group changes (only if the
  // form actually uses more than one group). Keeps single-group sections unchanged.
  function formWithGroups(form) {
    var groups = {};
    form.forEach(function (f) { groups[f.group || ""] = 1; });
    var multi = Object.keys(groups).filter(function (g) { return g; }).length > 1;
    if (!multi) return '<div class="ctl-form">' + form.map(fieldHtml).join("") + '</div>';
    var out = "", last = null, open = false;
    form.forEach(function (f) {
      var g = f.group || "";
      if (g !== last) {
        if (open) out += '</div>';
        var t = groupTitle(g);
        if (t) out += '<div class="ctl-subhead">' + esc(t) + '</div>';
        out += '<div class="ctl-form">';
        open = true; last = g;
      }
      out += fieldHtml(f);
    });
    if (open) out += '</div>';
    return out;
  }
  function optionHtml(options, current) {
    return String(options || "").split(",").filter(Boolean).map(function (part) {
      var bits = part.split(":"), value = bits.shift(), label = bits.join(":") || value;
      return '<option value="' + esc(value) + '"' + (String(current) === value ? " selected" : "") + '>' + esc(label) + '</option>';
    }).join("");
  }
  function fieldHtml(f) {
    var type = f.type || "text", ro = f.readonly ? " readonly disabled" : "";
    var wrap = '<label class="royal-field" data-royal-group="' + esc(f.group || "") + '" data-modes="' + esc(f.modes || "") + '"><span>' + esc(f.label) + '</span>';
    var tail = '<small>' + esc(f.hint || "") + '</small></label>';
    if (type === "select") {
      return wrap + '<select class="latin" data-ctl-field="' + esc(f.name) + '"' + ro + '>' + optionHtml(f.options, f.value) + '</select>' + tail;
    }
    return wrap + '<input class="latin" data-ctl-field="' + esc(f.name) + '" type="' + esc(type) + '" value="' + esc(f.value) + '" autocomplete="off"' + ro + '>' + tail;
  }
  function renderWizardControl(section, data) {
    var fields = data.form || [];
    function group(name) { return fields.filter(function (f) { return (f.group || "device") === name; }).map(fieldHtml).join(""); }
    var cards = data.cards && data.cards.length ? '<div class="ctl-cards">' + data.cards.map(function (c) {
      return '<div class="ctl-card ' + esc(c.level || "neutral") + '"><span>' + esc(c.label) + '</span><b>' + esc(c.value) + '</b><small>' + esc(c.hint || "") + '</small></div>';
    }).join("") + '</div>' : "";
    var actions = '<div class="branch-actions">' + (data.actions || []).filter(function (a) { return !a.url; }).map(function (a) {
      return '<button class="' + (a.confirm ? "btn" : "btn primary") + '" data-ctl-section="' + esc(section) + '" data-ctl-action="' + esc(a.id) + '" data-ctl-confirm="' + (a.confirm ? "1" : "") + '">' + esc(a.label || a.id) + '</button>';
    }).join("") + '</div>';
    return cards +
      '<div class="wizard-tabs">' +
      '<button class="wizard-tab active" data-wizard-tab="device">1. إعدادات الجهاز</button>' +
      '<button class="wizard-tab" data-wizard-tab="security">2. إعدادات الحماية</button>' +
      '<button class="wizard-tab" data-wizard-tab="advanced">3. إعدادات متقدمة</button>' +
      '</div>' +
      '<p class="mode-hint">كل تطبيق يُحفظ فوراً (Apply & Keep) مع نسخة احتياطية وتأكيد قبل التنفيذ، ولا يخفض قيمة TX Power أبداً.</p>' +
      '<section class="royal-pane" data-wizard-pane="device"><div class="royal-grid wizard-fields">' + group("device") + '</div></section>' +
      '<section class="royal-pane" data-wizard-pane="security" hidden><div class="royal-grid wizard-fields">' + group("security") + '</div></section>' +
      '<section class="royal-pane" data-wizard-pane="advanced" hidden><div class="royal-grid wizard-fields">' + group("advanced") + '</div></section>' +
      '<div class="wizard-preview"><b>Preview</b><div id="wizardPreview"></div></div>' + actions + (data.text ? '<pre class="ctl-pre">' + esc(data.text) + '</pre>' : "");
  }
  function updateWizardPreview() {
    var box = $("wizardPreview"); if (!box) return;
    function fv(n) { var el = document.querySelector('[data-control-section="wizard"] [data-ctl-field="' + n + '"]'); return el ? el.value : ""; }
    var modeEl = document.querySelector('[data-control-section="wizard"] [data-ctl-field="program_mode"]');
    var modeLabel = modeEl && modeEl.options ? modeEl.options[modeEl.selectedIndex].text : fv("program_mode");
    box.innerHTML = '<div class="kv"><span>Mode</span><b class="latin">' + esc(modeLabel || "-") + '</b></div>' +
      '<div class="kv"><span>IP (WiFi + Cable)</span><b class="latin">' + esc(fv("device_ip") || "-") + '</b></div>' +
      '<div class="kv"><span>VLAN</span><b class="latin">' + esc(fv("vlan_id") || "-") + '</b></div>' +
      '<div class="kv"><span>SSID</span><b class="latin">' + esc(fv("ssid") || "-") + '</b></div>' +
      '<div class="kv"><span>Security</span><b class="latin">' + esc(fv("security") || "-") + '</b></div>' +
      '<div class="kv"><span>NAT / DHCP / FW</span><b class="latin">' + esc((fv("nat_enabled") || "0") + " / " + (fv("dhcp_server") || "0") + " / " + (fv("firewall_enabled") || "1")) + '</b></div>' +
      '<div class="kv"><span>TX Power</span><b class="latin">30 locked</b></div>';
  }
  function syncWizardMode() {
    var panel = document.querySelector('[data-control-section="wizard"]');
    if (!panel) return;
    var modeEl = panel.querySelector('[data-ctl-field="program_mode"]');
    var mode = modeEl ? modeEl.value : "ap";
    Array.prototype.forEach.call(panel.querySelectorAll(".royal-field[data-modes]"), function (wrap) {
      var modes = (wrap.dataset.modes || "").split(",").filter(Boolean);
      wrap.hidden = modes.length && modes.indexOf("all") < 0 && modes.indexOf(mode) < 0;
    });
    updateWizardPreview();
  }
  function renderBranchDetail(groupId, item) {
    var kind = item[2] || "", section = item[0], ctlId = "ctl_" + sid(section);
    var note = kind === "protected" || kind === "danger" ? tr("sensitiveNote") : item[0] === "dashboard" ? tr("newDashboard") : "Live controls and status are loaded from the Xiaomi CR6608 router.";
    return '<div class="branch-detail" data-control-section="' + esc(section) + '">' +
      '<div class="chip ' + (kind === "danger" ? "bad" : kind === "protected" ? "warn" : "ok") + '">' + esc(kind === "danger" || kind === "protected" ? tr("protectedPage") : "Live CR6608 control") + '</div>' +
      '<h3>' + esc(item[1]) + '</h3>' +
      '<p>' + esc(note) + '</p>' +
      '<div class="branch-actions">' +
      (item[0] === "logout" ? '<button class="btn primary" data-smart-logout="1">' + esc(tr("logout")) + '</button>' : '<button class="btn primary" data-ctl-refresh="' + esc(section) + '">' + esc(tr("refresh")) + '</button>') +
      '</div>' +
      '<div id="' + ctlId + '" class="ctl-status">Loading router controls...</div>' +
      '</div>';
  }
  function renderAdminBranch(groupId) {
    var group = adminGroups()[groupId];
    if (!group) return "";
    var idx = state.adminSelection[groupId] || 0;
    var first = group.items[idx] || group.items[0];
    return sectionHead(group.title, group.desc, "Xiaomi CR6608") +
      '<div class="branch-layout">' +
      '<aside class="branch-menu">' + group.items.map(function (item, i) {
        var kind = item[2] || "";
        return '<button class="' + (i === idx ? "active" : "") + (kind === "protected" ? " protected" : "") + (kind === "danger" ? " danger" : "") + '" data-admin-group="' + groupId + '" data-admin-index="' + i + '">' + esc(item[1]) + '</button>';
      }).join("") + '</aside>' +
      '<div id="' + groupId + 'Detail">' + renderBranchDetail(groupId, first) + '</div>' +
      '</div>';
  }
  function renderEvents(data) {
    var apiEvents = data.events || [];
    var all = apiEvents.concat(state.events.map(function (e) { return new Date(e.t).toLocaleTimeString() + " " + e.msg; })).slice(0, 60);
    return card("Events / Alerts", '<div class="events">' + (all.length ? all.map(function (e) { return '<div class="event">' + esc(e) + '</div>'; }).join("") : '<div class="empty">' + tr("emptyEvents") + '</div>') + '</div>', "filter", "bolt");
  }
  function renderActions() {
    var actions = [["refresh",tr("refresh"),tr("readApiNow")],["speedtest",tr("speedTest"),tr("localTest")],["reconnect",tr("reconnect"),tr("protected")],["wifi_toggle",tr("toggleWifi"),tr("protected")],["reboot",tr("reboot"),tr("confirmRequired")]];
    return sectionHead(tr("actions"), tr("actionsHint"), tr("safeAction")) +
      '<div class="actions">' + actions.map(function (a) { return '<button class="action" data-action="' + a[0] + '"><strong>' + esc(a[1]) + '</strong><span>' + esc(a[2]) + '</span></button>'; }).join("") + '</div>' + renderEvents(state.latest || {});
  }
  function renderIsolation() {
    return sectionHead(tr("isolation"), tr("isolationHint"), "Xiaomi CR6608") +
      '<div class="branch-detail" data-control-section="isolation">' +
      '<div class="chip warn"><span>' + esc(tr("protected")) + '</span></div>' +
      '<h3>' + esc(tr("isolationTitle")) + '</h3>' +
      '<p>' + esc(tr("isolationNote")) + '</p>' +
      '<div class="branch-actions"><button class="btn primary" data-ctl-refresh="isolation">' + esc(tr("refresh")) + '</button></div>' +
      '<div id="ctl_isolation" class="ctl-status">' + esc(tr("loading")) + '</div>' +
      '</div>';
  }
  function renderQuick() {
    return sectionHead(tr("quick"), tr("quickHint"), "Xiaomi CR6608") +
      '<div class="branch-detail" data-control-section="wizard">' +
      '<div class="chip warn"><span>' + esc(tr("protected")) + '</span></div>' +
      '<h3>' + esc(tr("quickTitle")) + '</h3>' +
      '<p>' + esc(tr("quickNote")) + '</p>' +
      '<div class="branch-actions"><button class="btn primary" data-ctl-refresh="wizard">' + esc(tr("refresh")) + '</button></div>' +
      '<div id="ctl_wizard" class="ctl-status">' + esc(tr("loading")) + '</div>' +
      '</div>';
  }
  function render(data) {
    state.latest = data;
    window.__lastApi = data;
    var rates = trafficRates(data);
    updateAvailability(!!data.ok);
    pushHistory("latency", state.lastLatency || 0, 60);
    pushHistory("rx", rates.rx, 60); pushHistory("tx", rates.tx, 60);
    renderKpis(data, rates);
    $("connectionState").textContent = data.ok ? tr("online") : tr("offline");
    $("statusPulse").classList.toggle("bad", !data.ok);
    $("sideTitle").textContent = "Smart AP";
    $("sideStatus").textContent = (data.hostname || "OpenWrt") + " · " + nowTime();
    $("overview").innerHTML = sectionHead(tr("overview"), tr("subtitle"), nowTime()) + '<div class="grid two">' + renderTraffic(data, rates, "overview") + renderData(data) + '</div>' + renderEvents(data);
    $("network").innerHTML = renderNetwork(data, rates);
    $("devices").innerHTML = renderDevices(data);
    $("wifi").innerHTML = renderWifi(data);
    $("system").innerHTML = renderSystem(data);
    $("actions").innerHTML = renderActions();
    bindDynamic();
    setTimeout(loadActiveControl, 0);
    saveHistories();
  }
  async function loadData() {
    if (!state.session) return;
    var start = performance.now();
    try {
      var res = await fetch(authUrl(API), { cache:"no-store" });
      var text = await res.text();
      state.lastLatency = Math.max(1, performance.now() - start);
      if (res.status === 403) return requireLogin("انتهت الجلسة أو يلزم تسجيل دخول Xiaomi CR6608.");
      if (!res.ok) throw new Error("HTTP " + res.status);
      var data = JSON.parse(text);
      render(data);
    } catch (e) {
      updateAvailability(false);
      toast("API: " + e.message);
      event("API error: " + e.message, "error");
    }
  }
  async function speedTest() {
    var bytesRead = 0, start = performance.now(), pings = [];
    for (var i = 0; i < 5; i++) {
      var t0 = performance.now();
      var r = await fetch(authUrl(API + "?speed=" + i), { cache:"no-store" });
      if (r.status === 403) { requireLogin("انتهت الجلسة أو يلزم تسجيل دخول Xiaomi CR6608."); return; }
      var tx = await r.text();
      pings.push(performance.now() - t0);
      bytesRead += tx.length;
    }
    var ms = performance.now() - start, avg = pings.reduce(function (a,b) { return a+b; },0) / pings.length;
    var jitter = Math.sqrt(pings.map(function (x) { return Math.pow(x - avg, 2); }).reduce(function (a,b) { return a+b; },0) / pings.length);
    toast(tr("localTest") + ": " + fmt(avg,0) + "ms, jitter " + fmt(jitter,0) + "ms, " + bps(bytesRead / (ms / 1000)));
  }
  async function action(name) {
    if (name === "refresh") return loadData();
    if (name === "speedtest") return speedTest();
    if (name === "reboot" || name === "reconnect" || name === "wifi_toggle") {
      var now = Date.now();
      if (!state.pendingAction || state.pendingAction.name !== name || state.pendingAction.until < now) {
        state.pendingAction = { name:name, until:now + 6000 };
        return toast(tr("confirmAgain"));
      }
      state.pendingAction = null;
    }
    try {
      var r = await fetch(authUrl(ACTION + "?action=" + encodeURIComponent(name) + "&confirm=1"), { cache:"no-store" });
      if (r.status === 403) return requireLogin("انتهت الجلسة أو يلزم تسجيل دخول Xiaomi CR6608.");
      var j = await r.json();
      toast(j.message || tr("ok"));
      event(name + ": " + (j.message || ""));
    } catch (e) { toast(e.message); }
  }
  function activeControlSection() {
    var active = document.body.dataset.activeSection;
    var groups = adminGroups(), group = groups[active];
    if (!group) return "";
    var idx = state.adminSelection[active] || 0;
    return (group.items[idx] || group.items[0] || [])[0] || "";
  }
  function controlParams(section, actionName, button) {
    var params = "";
    if (button && button.dataset.ctlInput === "host") {
      var h = $("ctlHost_" + sid(section));
      params += "&host=" + encodeURIComponent((h && h.value) || "192.168.1.1");
    }
    var panel = document.querySelector('[data-control-section="' + section + '"]');
    Array.prototype.forEach.call(panel ? panel.querySelectorAll("[data-ctl-field]") : [], function (i) {
      // Submit every field the user actually filled — including fields in inactive
      // wizard tabs (.royal-pane[hidden]). Only skip disabled fields and fields hidden
      // by mode filtering (their own .royal-field wrapper is [hidden]).
      if (i.disabled) return;
      var wrap = i.closest(".royal-field");
      if (wrap && wrap.hidden) return;
      params += "&" + encodeURIComponent(i.dataset.ctlField) + "=" + encodeURIComponent(i.value);
    });
    return params;
  }
  async function loadControl(section, actionName, params, button) {
    var box = $("ctl_" + sid(section));
    if (!box) return;
    if (actionName && button && button.dataset.ctlConfirm === "1") {
      var key = "ctl:" + section + ":" + actionName, now = Date.now();
      if (!state.pendingAction || state.pendingAction.name !== key || state.pendingAction.until < now) {
        state.pendingAction = { name:key, until:now + 6000 };
        return toast(tr("confirmAgain"));
      }
      state.pendingAction = null;
      params = (params || "") + "&confirm=1";
    }
    box.className = "ctl-status";
    box.textContent = actionName ? "Running control..." : "Loading router controls...";
    try {
      var url = authUrl(CTL + "?section=" + encodeURIComponent(section));
      var fetchOptions = { cache:"no-store" };
      if (actionName) {
        url = CTL;
        fetchOptions = {
          method:"POST",
          cache:"no-store",
          headers:{ "Content-Type":"application/x-www-form-urlencoded" },
          body:"section=" + encodeURIComponent(section) + "&action=" + encodeURIComponent(actionName) + (params || "") + "&" + sidQuery() + "&_=" + Date.now()
        };
      }
      var res = await fetch(url, fetchOptions);
      if (res.status === 403) return requireLogin("انتهت الجلسة أو يلزم تسجيل دخول Xiaomi CR6608.");
      var data = await res.json();
      state.controlCache[section] = data;
      box.className = "";
      box.innerHTML = renderControlData(section, data);
      if (section === "wizard") syncWizardMode();
      if (data.summary) toast(data.summary);
      bindDynamic();
    } catch (e) {
      box.className = "ctl-status";
      box.textContent = "Control API error: " + e.message;
    }
  }
  function loadActiveControl() {
    var section = activeControlSection();
    if (!section) return;
    var box = $("ctl_" + sid(section));
    if (box && !box.dataset.loaded) {
      box.dataset.loaded = "1";
      loadControl(section);
    }
  }
  function bindDynamic() {
    Array.prototype.forEach.call(document.querySelectorAll("[data-action]"), function (b) { b.onclick = function () { action(b.dataset.action); }; });
    Array.prototype.forEach.call(document.querySelectorAll("[data-admin-group]"), function (b) {
      b.onclick = function () {
        var groupId = b.dataset.adminGroup, group = adminGroups()[groupId], idx = Number(b.dataset.adminIndex) || 0;
        if (!group) return;
        state.adminSelection[groupId] = idx;
        Array.prototype.forEach.call(document.querySelectorAll('[data-admin-group="' + groupId + '"]'), function (x) { x.classList.toggle("active", x === b); });
        var panel = $(groupId + "Detail");
        if (panel) panel.innerHTML = renderBranchDetail(groupId, group.items[idx]);
        bindDynamic();
        loadControl(group.items[idx][0]);
      };
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-ctl-refresh]"), function (b) {
      b.onclick = function () { loadControl(b.dataset.ctlRefresh); };
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-ctl-action]"), function (b) {
      b.onclick = function () {
        var section = b.dataset.ctlSection, actionName = b.dataset.ctlAction;
        if (actionName === "logout") return logout();
        loadControl(section, actionName, controlParams(section, actionName, b), b);
      };
    });
    Array.prototype.forEach.call(document.querySelectorAll('[data-control-section="wizard"] [data-ctl-field]'), function (i) {
      i.oninput = syncWizardMode;
      i.onchange = syncWizardMode;
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-wizard-tab]"), function (b) {
      b.onclick = function () {
        var key = b.dataset.wizardTab;
        Array.prototype.forEach.call(document.querySelectorAll("[data-wizard-tab]"), function (x) { x.classList.toggle("active", x === b); });
        Array.prototype.forEach.call(document.querySelectorAll("[data-wizard-pane]"), function (p) { p.hidden = p.dataset.wizardPane !== key; });
        syncWizardMode();
      };
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-smart-section]"), function (b) { b.onclick = function (ev) { ev.preventDefault(); showSection(b.dataset.smartSection); }; });
    Array.prototype.forEach.call(document.querySelectorAll("[data-smart-logout]"), function (b) { b.onclick = function (ev) { ev.preventDefault(); logout(); }; });
    Array.prototype.forEach.call(document.querySelectorAll(".dev-action"), function (b) {
      b.onclick = async function () {
        var mac = b.dataset.devMac, act = b.dataset.devAct;
        if (!mac || !act) return toast(tr("simulated"));
        try {
          var r = await fetch(CTL, { method:"POST", cache:"no-store",
            headers:{ "Content-Type":"application/x-www-form-urlencoded" },
            body:"section=devices&action=" + encodeURIComponent(act) + "&mac=" + encodeURIComponent(mac) + "&confirm=1&" + sidQuery() + "&_=" + Date.now() });
          if (r.status === 403) return requireLogin(tr("loginBad"));
          var j = await r.json();
          toast(j.summary || j.text || tr("ok"));
          event((act === "block_mac" ? "Block " : "Allow ") + mac);
          setTimeout(loadData, 400);
        } catch (e) { toast(e.message); }
      };
    });
    var d = $("dailyBudget"), m = $("monthBudget");
    if (d) d.onchange = function () { localStorage.setItem(LS + "dailyBudgetGb", Math.max(1, Number(d.value)||5)); loadData(); };
    if (m) m.onchange = function () { localStorage.setItem(LS + "monthBudgetGb", Math.max(1, Number(m.value)||100)); loadData(); };
  }
  function startPolling() {
    if (!state.session) return showLogin();
    clearInterval(state.timer);
    loadData();
    state.timer = setInterval(loadData, Math.max(5, state.interval) * 1000);
  }
  function init() {
    state.session = "";
    sessionStorage.removeItem(LS + "session");
    renderChrome();
    setLoginText();
    if ($("loginForm")) {
      $("loginForm").onsubmit = function (ev) {
        ev.preventDefault();
        login(($("loginUser") && $("loginUser").value) || "root", ($("loginPass") && $("loginPass").value) || "");
      };
    }
    $("langAr").onclick = function () { state.lang = "ar"; localStorage.setItem(LS + "lang", state.lang); renderChrome(); if (state.latest) render(state.latest); };
    $("langEn").onclick = function () { state.lang = "en"; localStorage.setItem(LS + "lang", state.lang); renderChrome(); if (state.latest) render(state.latest); };
    $("themeBtn").onclick = function () {
      state.theme = state.theme === "dark" ? "light" : "dark";
      localStorage.setItem(LS + "theme", state.theme);
      renderChrome();
      // Repaint everything so canvas charts/gauges pick up the new theme colors,
      // and re-open the active control section so its chart (if any) redraws too.
      if (state.latest) render(state.latest);
      var act = document.body.dataset.activeSection;
      if (act) { var el = $(act); if (el && el.dataset) { el.dataset.uiVersion = ""; } showSection(act); }
    };
    $("intervalSelect").onchange = function () { state.interval = Number(this.value) || 5; localStorage.setItem(LS + "interval", state.interval); startPolling(); };
    $("logoutBtn").onclick = logout;
    if ($("openWrtBtn")) $("openWrtBtn").onclick = function () { window.location.href = "/cgi-bin/luci/"; };
    $("refreshBtn").onclick = loadData;
    document.addEventListener("visibilitychange", function () { if (document.hidden) clearInterval(state.timer); else startPolling(); });
    showLogin();
  }
  document.addEventListener("DOMContentLoaded", init);
}());
