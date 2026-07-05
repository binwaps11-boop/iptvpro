(function () {
  "use strict";

  var API = "/cgi-bin/dashapi2";
  var ACTION = "/cgi-bin/dashaction";
  var CTL = "/cgi-bin/dashctl";
  var AUTH = "/ubus";
  var ANON = "00000000000000000000000000000000";
  var LS = "smartap.";
  var UI_VERSION = "cr6608-smartap-live-sync-v7";
  if (localStorage.getItem(LS + "uiVersion") !== UI_VERSION) {
    localStorage.setItem(LS + "theme", "dark");
    localStorage.setItem(LS + "interval", "5");
    localStorage.removeItem(LS + "events");
    localStorage.removeItem(LS + "availability");
    localStorage.removeItem(LS + "histories");
    localStorage.removeItem(LS + "knownMacs");
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
    controlCache: {},
    lastScan: null,
    lanScan: null
  };

  var L = {
    ar: {
      loading: "جاري التحميل", unavailable: "غير متوفر", online: "متصل", offline: "غير متصل",
      lanOnly: "LAN فقط", refresh: "تحديث", theme: "الثيم", dark: "داكن", light: "فاتح",
      overview: "نظرة", insights: "الرؤى",
      signal: "الإشارة", network: "الترافيك", devices: "الأجهزة", wifi: "WiFi",
      system: "صحة النظام", actions: "إجراءات", isolation: "العزل والحماية",
      vendor: "الشركة", type: "النوع", link: "المنفذ", action: "إجراء", unknownVendor: "غير معروف", near: "قريب", mid: "متوسط", far: "بعيد",
      scanNeighbors: "فحص القنوات والشبكات المجاورة", scanning: "جاري الفحص…", bestChannel: "أفضل قناة",
      neighbors: "الشبكات المجاورة", noNeighbors: "لم يُعثر على شبكات مجاورة", applyBest: "طبّق أفضل قناة",
      scanLan: "اكتشاف الأجهزة على الشبكة", lanNeighbors: "أجهزة الشبكة (الجيران)",
      lanScanHint: "يفحص كل المنافذ ويكشف الأجهزة خلف أي سويتش — يعرض الاسم والـ IP والـ MAC والمنفذ.",
      noLanDevices: "لم يُعثر على أجهزة. تأكد من توصيل السويتش/الأجهزة ثم أعد الفحص.",
      port: "المنفذ", host: "الاسم", deviceName: "اسم الجهاز", scanAgain: "إعادة الفحص",
      lldpNeighbors: "أجهزة مُدارة (LLDP/CDP)", noLldpNeighbors: "لا توجد أجهزة LLDP/CDP مُدارة. تأكد أن السويتش/الراوتر يدعم LLDP ثم أعد الفحص.", platform: "النظام/الطراز", localPort: "منفذنا", remotePort: "منفذهم",
      portThroughput: "سحب المنافذ (لكل منفذ)", perPortRate: "معدل النقل لكل منفذ سلكي", totalRate: "السحب الإجمالي", download: "تحميل", upload: "رفع", yearly: "السنوي", total: "الإجمالي", rename: "تسمية الجهاز", renamePrompt: "اسم الجهاز:", limitPrompt: "حد السرعة (ميغابت/ث):", wifiRate: "سحب الواي فاي (لكل تردد)", portsRate: "سحب المنافذ السلكية", clientTraffic: "التحميل / الرفع",
      recommended: "المقترح", current: "الحالي", channel: "القناة", rogueAlert: "تحذير: توأم شرير", rogueDesc: "شبكة تبث نفس اسمك من جهاز غريب",
      healthScore: "درجة صحة الشبكة", airtime: "إشغال الهواء", latency: "زمن الاستجابة", noise: "أرضية الضوضاء",
      clientRadar: "رادار الأجهزة", linkRate: "سرعة الوصلة", constellation: "كوكبة العملاء (المدى=الإشارة)",
      newDevice: "جهاز جديد انضم", steer5g: "→ 5G", steerHint: "اطلب من الجهاز الانتقال إلى 5G",
      selftest: "الفحص الذاتي", selftestRun: "تشغيل الفحص الآن", selftestHint: "يعمل تلقائياً كل ليلة 4:00 صباحاً، وتقدر تشغّله يدوياً.",
      selftestNotes: "الملاحظات", lastReport: "آخر تقرير",
      distance: "المسافة التقديرية", secPosture: "حالة الحماية", efficiency: "كفاءة الوصلة",
      protected: "محمي", open: "مفتوح", encrypted: "مشفّر", thermal: "الحارس الحراري",
      thermalOk: "طبيعية", thermalWarm: "دافئة", thermalHot: "مرتفعة", meters: "م",
      secGood: "كل الشبكات آمنة", secOpenWarn: "شبكات مفتوحة", trend: "اتجاه الإشارة",
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
      overview: "Overview", insights: "Insights",
      signal: "Signal", network: "Traffic", devices: "Devices", wifi: "WiFi",
      system: "System Health", actions: "Actions", isolation: "Isolation",
      vendor: "Vendor", type: "Type", link: "Link", action: "Action", unknownVendor: "Unknown", near: "Near", mid: "Medium", far: "Far",
      scanNeighbors: "Scan channels & neighbors", scanning: "Scanning…", bestChannel: "Best channel",
      neighbors: "Neighboring networks", noNeighbors: "No neighboring networks found", applyBest: "Apply best channel",
      scanLan: "Discover devices on the network", lanNeighbors: "Network devices (Neighbors)",
      lanScanHint: "Scans every port and reveals devices behind any switch — shows name, IP, MAC and port.",
      noLanDevices: "No devices found. Check the switch/devices are connected, then scan again.",
      port: "Port", host: "Name", deviceName: "Device name", scanAgain: "Scan again",
      lldpNeighbors: "Managed devices (LLDP/CDP)", noLldpNeighbors: "No managed LLDP/CDP devices found. Make sure the switch/router advertises LLDP, then scan again.", platform: "Platform", localPort: "Our port", remotePort: "Their port",
      portThroughput: "Port throughput (per port)", perPortRate: "Rate per wired port", totalRate: "Total throughput", download: "Download", upload: "Upload", yearly: "Yearly", total: "Total", rename: "Rename device", renamePrompt: "Device name:", limitPrompt: "Speed limit (Mbps):", wifiRate: "WiFi throughput (per band)", portsRate: "Wired ports", clientTraffic: "Down / Up",
      recommended: "Recommended", current: "Current", channel: "Channel", rogueAlert: "Warning: evil twin", rogueDesc: "A foreign AP broadcasting your SSID",
      healthScore: "Network health score", airtime: "Airtime busy", latency: "Latency", noise: "Noise floor",
      clientRadar: "Client radar", linkRate: "Link rate", constellation: "Client constellation (radius = signal)",
      newDevice: "New device joined", steer5g: "→ 5G", steerHint: "Ask this client to move to 5G",
      selftest: "Self-test", selftestRun: "Run self-test now", selftestHint: "Runs automatically every night at 4:00 AM; you can also run it manually.",
      selftestNotes: "Notes", lastReport: "Last report",
      distance: "Est. distance", secPosture: "Security posture", efficiency: "Link efficiency",
      protected: "Protected", open: "Open", encrypted: "Encrypted", thermal: "Thermal guardian",
      thermalOk: "Normal", thermalWarm: "Warm", thermalHot: "Hot", meters: "m",
      secGood: "All networks secured", secOpenWarn: "Open networks", trend: "Signal trend",
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
  function trafficRxBytes(data) {
    if (data.traffic) return Number(data.traffic.rx_bytes) || 0;
    return (data.interfaces || []).reduce(function (a, i) { return a + (Number(i.rx_bytes) || 0); }, 0);
  }
  function trafficTxBytes(data) {
    if (data.traffic) return Number(data.traffic.tx_bytes) || 0;
    return (data.interfaces || []).reduce(function (a, i) { return a + (Number(i.tx_bytes) || 0); }, 0);
  }
  function dataUsage(data) {
    // track download (RX) and upload (TX) SEPARATELY so the daily/monthly usage can be
    // shown split instead of one combined number.
    var rx = trafficRxBytes(data), tx = trafficTxBytes(data);
    var dayKey = new Date().toISOString().slice(0,10), monthKey = dayKey.slice(0,7);
    function base(name, key, cur) {
      var b = JSON.parse(localStorage.getItem(LS + name) || "null");
      if (!b || b.key !== key || cur < b.bytes) { b = { key:key, bytes:cur }; localStorage.setItem(LS + name, JSON.stringify(b)); }
      return Math.max(0, cur - b.bytes);
    }
    var yearKey = dayKey.slice(0,4);
    var dayRx = base("dayBaseRx", dayKey, rx), dayTx = base("dayBaseTx", dayKey, tx);
    var monRx = base("monthBaseRx", monthKey, rx), monTx = base("monthBaseTx", monthKey, tx);
    var yrRx = base("yearBaseRx", yearKey, rx), yrTx = base("yearBaseTx", yearKey, tx);
    return { dayRx:dayRx, dayTx:dayTx, monRx:monRx, monTx:monTx, yrRx:yrRx, yrTx:yrTx,
             day:dayRx + dayTx, month:monRx + monTx, year:yrRx + yrTx, total:rx + tx };
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
  function stationTraffic(sta) {
    sta = sta || {};
    var up = num(sta.upload_bps), down = num(sta.download_bps);
    var upBytes = num(sta.upload_bytes), downBytes = num(sta.download_bytes);
    var hasCounters = finite(upBytes) || finite(downBytes);
    return {
      up: finite(up) ? up : 0,
      down: finite(down) ? down : 0,
      upBytes: finite(upBytes) ? upBytes : 0,
      downBytes: finite(downBytes) ? downBytes : 0,
      hasCounters: hasCounters
    };
  }
  function stationTrafficRows(data) {
    var rows = [];
    ((data && data.wifi) || []).forEach(function (w) {
      (w.stations || []).forEach(function (s) {
        var t = stationTraffic(s);
        if (!t.hasCounters) return;
        rows.push({
          label: s.ip || s.mac || "?",
          mac: s.mac || "",
          band: w.band || "",
          up: t.up,
          down: t.down,
          totalRate: t.up + t.down,
          upBytes: t.upBytes,
          downBytes: t.downBytes,
          totalBytes: t.upBytes + t.downBytes
        });
      });
    });
    return rows;
  }
  function stationTrafficHtml(sta) {
    var t = stationTraffic(sta);
    if (!t.hasCounters) return "";
    var downLabel = state.lang === "ar" ? "تنزيل" : "Download";
    var upLabel = state.lang === "ar" ? "رفع" : "Upload";
    return '<div class="grid two" style="margin-top:8px">' +
      '<div class="traffic-box"><span>' + downLabel + '</span><b class="latin">' + bps(t.down) + '</b><small class="muted">' + bytes(t.downBytes) + '</small></div>' +
      '<div class="traffic-box"><span>' + upLabel + '</span><b class="latin">' + bps(t.up) + '</b><small class="muted">' + bytes(t.upBytes) + '</small></div></div>';
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
  // Custom device names — user-assigned, keyed by MAC, stored locally on the phone/PC.
  function devNamesMap() { try { return JSON.parse(localStorage.getItem(LS + "devNames") || "{}") || {}; } catch (e) { return {}; } }
  function deviceName(mac) { if (!mac) return ""; return devNamesMap()[String(mac).toLowerCase()] || ""; }
  function setDeviceName(mac, name) {
    if (!mac) return; var m = devNamesMap(); var k = String(mac).toLowerCase();
    if (name) m[k] = String(name).slice(0, 32); else delete m[k];
    try { localStorage.setItem(LS + "devNames", JSON.stringify(m)); } catch (e) {}
  }
  function mergeDevices(data) {
    var map = {};
    (data.devices || []).forEach(function (d) { var k = String(d.mac || d.ip || Math.random()).toLowerCase(); map[k] = { ip:d.ip, mac:d.mac, iface:d.iface, type:d.type || "Ethernet", host:d.host }; });
    (data.wifi || []).forEach(function (w) { (w.stations || []).forEach(function (s) { var k = String(s.mac || Math.random()).toLowerCase(); var t = stationTraffic(s); map[k] = Object.assign(map[k] || {}, { mac:s.mac, ip:s.ip || (map[k]||{}).ip, iface:w.iface, type:"WiFi", signal:s.signal_dbm, rate:s.tx_rate, txRate:s.tx_rate, rxRate:s.rx_rate, down:t.down, up:t.up, downBytes:t.downBytes, upBytes:t.upBytes, hasTraffic:t.hasCounters }); }); });
    // Owner rule: the devices list shows Wi-Fi clients ONLY (2.4G + 5G). Wired/managed
    // gear on lan1..wan already appears in the LLDP/CDP neighbours section — no repeats.
    return Object.keys(map).map(function (k) { map[k].vendor = ouiVendor(map[k].mac); return map[k]; }).filter(function (e) { return e.type === "WiFi"; });
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
      // Self-contained local login — never depends on rpcd/ubus, so an empty or
      // sysupgrade-preserved root password can't block sign-in.
      var res = await fetch("/cgi-bin/dashlogin", {
        method: "POST", cache: "no-store",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "username=" + encodeURIComponent(user) + "&password=" + encodeURIComponent(pass)
      });
      var data = await res.json();
      if (!data.ok || !data.sid) throw new Error(data.message || "login failed");
      state.session = data.sid;
      sessionStorage.setItem(LS + "session", state.session);
      // best-effort: also prime the LuCI (OpenWrt settings) session so the
      // settings button doesn't prompt again. Failure here is non-fatal.
      primeLuciSession(user, pass);
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
      var res = await fetch(authUrl(API), { cache: "no-store" });
      if (res.status !== 200) throw new Error("invalid");
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
      ["quick","quick","gear"],
      ["netmgr","netmgr","net"],
      ["wifimgr","wifimgr","wifi"],
      ["sysmgr","sysmgr","cpu"],
      ["isolation","isolation","shield"],
      ["network","network","net"],
      ["devices","devices","device"],
      ["wifi","wifi","wifi"],
      ["insights","insights","signal"],
      ["system","system","cpu"],
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
    ["overview","network","devices","wifi","insights","system","quick","isolation","actions","netmgr","wifimgr","sysmgr"].forEach(function (s) { if ($(s)) $(s).hidden = s !== id; });
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
      [tr("deviceCount"), String(Math.max(mergeDevices(data).length, (w24?Number(w24.clients)||0:0)+(w5?Number(w5.clients)||0:0))), "devices", 1],
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
    // history is pushed once per refresh in render(); do NOT push again here
    // (double/triple push corrupts the traffic chart timescale)
    var samples = (state.histories.rx || []).map(function (rx, i) { return { rx:rx, tx:(state.histories.tx || [])[i] || 0 }; });
    var canvasId = prefix + "TrafficCanvas";
    var rxLabel = state.lang === "ar" ? "RX وارد" : "RX In";
    var txLabel = state.lang === "ar" ? "TX صادر" : "TX Out";
    var body = '<canvas id="' + canvasId + '"></canvas><div class="grid two" style="margin-top:12px">' +
      '<div class="traffic-box"><span>' + rxLabel + '</span><b class="latin">' + bps(rates.rx) + '</b><small class="muted">' + bytes(rates.totalRx) + '</small></div>' +
      '<div class="traffic-box"><span>' + txLabel + '</span><b class="latin">' + bps(rates.tx) + '</b><small class="muted">' + bytes(rates.totalTx) + '</small></div></div>';
    setTimeout(function () { drawChart($(canvasId), samples, { keys:["rx","tx"] }); }, 0);
    return card(tr("networkTitle"), body, "60s peaks", "net");
  }
  // download (RX) / upload (TX) split box for a period — three clean rows (label ... value)
  // so the numbers never wrap/overlap on a narrow phone screen.
  function usageRow(icon, label, val, color) {
    return '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin:3px 0;font-size:12px">' +
      '<span class="muted">' + icon + ' ' + esc(label) + '</span>' +
      '<b class="latin" style="color:' + color + ';white-space:nowrap">' + bytes(val) + '</b></div>';
  }
  function usageSplit(label, rx, tx) {
    return '<div class="traffic-box" style="text-align:start">' +
      '<span style="font-weight:700">' + esc(label) + '</span>' +
      usageRow("↓", tr("download"), rx, "var(--accent)") +
      usageRow("↑", tr("upload"), tx, "var(--primary)") +
      usageRow("Σ", tr("total") || "Σ", rx + tx, "var(--text)") +
      '</div>';
  }
  function renderData(data) {
    var u = dataUsage(data), dailyBudget = Number(localStorage.getItem(LS + "dailyBudgetGb") || 5), monthBudget = Number(localStorage.getItem(LS + "monthBudgetGb") || 100);
    var dayTotal = dailyBudget * 1024 * 1024 * 1024, monthTotal = monthBudget * 1024 * 1024 * 1024;
    var body = '<div class="gauge-grid">' +
      gauge(tr("daily"), bytes(u.day), dailyBudget + " GB", tr("budget"), pct(u.day, dayTotal), pct(u.day, dayTotal) > 85 ? "#EF4444" : "#06B6D4", "kpiRx") +
      gauge(tr("monthly"), bytes(u.month), monthBudget + " GB", tr("budget"), pct(u.month, monthTotal), pct(u.month, monthTotal) > 85 ? "#EF4444" : "#8B5CF6", "kpiTx") +
      '</div>' +
      // download / upload split for each period (daily, monthly, yearly — separate)
      '<div class="grid two" style="margin-top:8px">' + usageSplit(tr("daily"), u.dayRx, u.dayTx) + usageSplit(tr("monthly"), u.monRx, u.monTx) + '</div>' +
      '<div style="margin-top:8px">' + usageSplit(tr("yearly"), u.yrRx, u.yrTx) + '</div>' +
      '<p class="muted">' + tr("noQuota") + '</p>' +
      '<div class="grid two"><label class="kv"><div><span>' + tr("daily") + ' GB</span><input id="dailyBudget" type="number" min="1" value="' + dailyBudget + '"></div></label><label class="kv"><div><span>' + tr("monthly") + ' GB</span><input id="monthBudget" type="number" min="1" value="' + monthBudget + '"></div></label></div>';
    return card(tr("budget"), body, "local", "bolt");
  }
  function proximity(dbm) {
    var v = num(dbm);
    if (v === null || !finite(v)) return "";
    var lvl = v >= -60 ? "near" : v >= -75 ? "mid" : "far";
    var col = v >= -60 ? "var(--excellent)" : v >= -75 ? "var(--good)" : "var(--weak)";
    var ico = v >= -60 ? "●●●" : v >= -75 ? "●●" : "●";
    return '<span class="prox" style="color:' + col + '">' + ico + ' ' + tr(lvl) + '</span>';
  }
  // Estimate distance (m) from RSSI via the log-distance path-loss model:
  // d = 10^((RSSI@1m - RSSI)/(10·n)); RSSI@1m≈-40 dBm, n≈2.7 (typical indoor).
  function distanceM(dbm) {
    var v = num(dbm);
    if (v === null || !finite(v) || v >= 0) return null;
    var d = Math.pow(10, (-40 - v) / (10 * 2.7));
    return d;
  }
  function distanceLabel(dbm) {
    var d = distanceM(dbm);
    if (d === null) return "";
    var t = d < 10 ? d.toFixed(1) : Math.round(d);
    return '<span class="prox" style="color:var(--accent)">≈ ' + t + ' ' + tr("meters") + '</span>';
  }
  // Unified throughput view: grand total (RX/TX), each Wi-Fi band, and each wired port —
  // all from live /proc/net/dev deltas in dashapi2. One place answering "who pulls what".
  function throughputRow(label, rx, tx, up, chip) {
    var tot = (finite(rx) ? rx : 0) + (finite(tx) ? tx : 0);
    var col = up === false ? "var(--muted)" : tot > 50e6 ? "var(--excellent)" : tot > 1e6 ? "var(--good)" : "var(--mid)";
    return '<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><b class="latin">' + esc(label) +
      '</b><span class="latin">' + (chip ? '<span class="chip ' + (up === false ? "bad" : "ok") + '" style="font-size:10px">' + esc(chip) + '</span>' : "") + '</span></div>' +
      '<div style="display:flex;justify-content:space-between;font-size:11px;color:var(--muted)"><span>↓ ' + (finite(rx) ? bps(rx) : "—") + '</span><span>↑ ' + (finite(tx) ? bps(tx) : "—") + '</span></div>' +
      bar(Math.min(tot / 1e6, 100), 100, col) + '</div>';
  }
  function renderPortThroughput(data) {
    var ifsAll = data.interfaces || [];
    var ports = ifsAll.filter(function (i) { return /^(lan[0-9]+|wan[0-9.]*)$/.test(i.name); });
    // Wi-Fi radios: phy0-ap* = 2.4G, phy1-ap* = 5G. Sum per band.
    var wifiAgg = {};
    ifsAll.forEach(function (i) {
      var m = /^phy([0-9])-/.exec(i.name); if (!m) return;
      var band = m[1] === "0" ? "2.4G" : "5G";
      wifiAgg[band] = wifiAgg[band] || { rx: 0, tx: 0, up: false };
      if (finite(num(i.rx_bps))) wifiAgg[band].rx += num(i.rx_bps);
      if (finite(num(i.tx_bps))) wifiAgg[band].tx += num(i.tx_bps);
      if (i.connected) wifiAgg[band].up = true;
    });
    // grand total from the traffic counters (all client-facing ports summed in dashapi2)
    var t = data.traffic || {}, gRx = num(t.rx_bps), gTx = num(t.tx_bps);
    if (!ports.length && !Object.keys(wifiAgg).length && !finite(gRx)) return "";
    var body = '<p class="muted" style="margin:0 0 6px">' + esc(tr("perPortRate")) + '</p>';
    // total
    body += '<div style="text-align:center;margin-bottom:6px"><div class="latin" style="font-size:24px;font-weight:800;color:var(--accent)">' +
      bps((finite(gRx) ? gRx : 0) + (finite(gTx) ? gTx : 0)) + '</div><div style="font-size:11px;color:var(--muted)">' + esc(tr("totalRate")) +
      ' · ↓ ' + (finite(gRx) ? bps(gRx) : "—") + ' · ↑ ' + (finite(gTx) ? bps(gTx) : "—") + '</div></div>';
    // Wi-Fi per band — on an AP interface, TX = data sent to clients (download) and RX =
    // data from clients (upload), so pass tx as the ↓ (download) and rx as the ↑ (upload).
    var wifiRows = Object.keys(wifiAgg).map(function (b) { return throughputRow("WiFi " + b, wifiAgg[b].tx, wifiAgg[b].rx, wifiAgg[b].up, b); }).join("");
    if (wifiRows) body += '<h4 style="margin:8px 0 2px">' + esc(tr("wifiRate")) + '</h4>' + wifiRows;
    // wired ports
    var portRows = ports.map(function (i) { return throughputRow(i.name, num(i.rx_bps), num(i.tx_bps), i.connected, i.connected ? (i.speed_mbps ? i.speed_mbps + "M" : "up") : "down"); }).join("");
    if (portRows) body += '<h4 style="margin:8px 0 2px">' + esc(tr("portsRate")) + '</h4>' + portRows;
    return card(tr("portThroughput"), body, "live", "net");
  }
  // Link efficiency = actual PHY rate vs the band's 2×2 HE ceiling (2.4G HE20≈287, 5G HE80≈1201).
  function linkEfficiency(band, txRate) {
    var r = num(txRate); if (!finite(r) || r <= 0) return null;
    var ceil = band === "5G" ? 1201 : 287;
    return clamp(Math.round(r / ceil * 100), 0, 100);
  }
  // WPA3/PMF security posture from the per-SSID encryption string.
  function secLevel(enc) {
    var e = String(enc || "").toLowerCase();
    if (!e || /none|open/.test(e)) return { key: "open", col: "var(--mid)", txt: tr("open") };
    if (/wpa3|sae/.test(e)) return { key: "wpa3", col: "var(--excellent)", txt: "WPA3" };
    if (/wpa2|psk|ccmp/.test(e)) return { key: "wpa2", col: "var(--good)", txt: "WPA2" };
    return { key: "enc", col: "var(--good)", txt: tr("encrypted") };
  }
  function renderSecPosture(data) {
    var w = data.wifi || [];
    if (!w.length) return "";
    var open = 0;
    var rows = w.map(function (x) {
      var s = secLevel(x.encryption);
      if (s.key === "open") open++;
      return '<div class="kv"><div><span class="latin">' + esc(x.ssid || x.iface) + '</span>' +
        '<b><span class="prox" style="color:' + s.col + '">' + s.txt + '</span></b></div>' +
        bar(s.key === "wpa3" ? 100 : s.key === "wpa2" ? 72 : 30, 100, s.col) + '</div>';
    }).join("");
    var chip = open ? open + " " + tr("secOpenWarn") : tr("secGood");
    return card(tr("secPosture"), rows, chip, "shield");
  }
  function renderDevices(data) {
    var rows = mergeDevices(data);
    // Neighbor discovery (restored): LLDP managed devices (switches/routers, from the
    // source) shown first, then the ARP/FDB device list. On-demand; result persists.
    var scanCard = card(tr("lanNeighbors"),
      '<p class="muted" style="margin:0 0 8px">' + esc(tr("lanScanHint")) + '</p>' +
      '<div class="branch-actions"><button class="btn primary" id="lanScanBtn">' + esc(tr("scanLan")) + '</button></div>' +
      '<div id="lanScanResult">' + (state.lanScan ? renderLanScan(state.lanScan) : "") + '</div>', "LLDP / CDP", "net");
    var live = rows.length ? sectionHead(tr("devices"), "IP / MAC / " + tr("vendor") + " / RSSI", rows.length + "") +
      '<div class="table-wrap"><table><thead><tr><th>' + tr("type") + '</th><th>IP</th><th>MAC</th><th>' + tr("vendor") + '</th><th>' + tr("link") + '</th><th>RSSI</th><th>' + tr("clientTraffic") + '</th><th>' + tr("action") + '</th></tr></thead><tbody>' +
      rows.map(function (d) {
        var vn = d.vendor || tr("unknownVendor");
        var m = esc(d.mac || "");
        var cn = deviceName(d.mac);
        var rename = m ? ' <button class="btn dev-rename" data-dev-mac="' + m + '" title="' + esc(tr("rename")) + '">✎</button>' : "";
        var acts = (m ? '<button class="btn dev-action" data-dev-mac="' + m + '" data-dev-act="block_mac">' + tr("block") + '</button> <button class="btn dev-action" data-dev-mac="' + m + '" data-dev-act="unblock_mac">' + tr("allow") + '</button>' : "") + rename;
        // show the user-assigned name first (if any), then the DHCP host as a sub-line
        var nameLine = cn ? '<b>' + esc(cn) + '</b><br>' : "";
        var ipHost = nameLine + esc(d.ip || tr("unavailable")) + (d.host ? '<br><small class="muted latin">' + esc(d.host) + '</small>' : "");
        // live per-client download / upload (from the Wi-Fi driver station counters)
        var traf = d.hasTraffic
          ? '<span class="latin" style="color:var(--accent);white-space:nowrap">↓ ' + bps(d.down || 0) + '</span><br><span class="latin" style="color:var(--primary);white-space:nowrap">↑ ' + bps(d.up || 0) + '</span>'
          : '<span class="muted">—</span>';
        // link column: interface + negotiated PHY link rate RX/TX (Mbps) so both show
        // together during use — TX = AP→client (download), RX = client→AP (upload).
        var txr = num(d.txRate), rxr = num(d.rxRate);
        var linkCell = esc(d.iface || "");
        if (finite(txr) || finite(rxr)) {
          linkCell += '<br><small class="latin" style="white-space:nowrap"><span style="color:var(--accent)">↓ ' + (finite(txr) ? fmt(txr, 0) : "—") + '</span> <span style="color:var(--primary)">↑ ' + (finite(rxr) ? fmt(rxr, 0) : "—") + '</span> <span class="muted">Mbps</span></small>';
        }
        return '<tr><td>' + icon(d.type === "WiFi" ? "wifi" : "device") + " " + esc(d.type || "") + '</td><td class="latin">' + ipHost + '</td><td class="latin">' + esc((d.mac || tr("unavailable")).toUpperCase()) + '</td><td>' + esc(vn) + '</td><td>' + linkCell + '</td><td class="latin">' + (num(d.signal) !== null ? d.signal + ' dBm ' + proximity(d.signal) : tr('unavailable')) + '</td><td>' + traf + '</td><td>' + acts + '</td></tr>';
      }).join("") +
      '</tbody></table></div>' :
      sectionHead(tr("devices"), "IP / MAC / traffic", "") + '<div class="empty">' + tr("unavailable") + '</div>';
    return live + renderPortThroughput(data) + scanCard;
  }
  // Render the on-demand LAN neighbor-scan result: one row per discovered device with
  // its resolved name, IP, MAC and the bridge port (so devices behind a switch are visible).
  // drop multicast / broadcast / reserved L2 addresses — they are not real devices and
  // were the noise that made the old list look like "73 unknowns".
  function isRealMac(mac) {
    var m = String(mac || "").toLowerCase();
    if (m.length !== 17) return false;
    if (m === "ff:ff:ff:ff:ff:ff") return false;
    if (/^(01:00:5e|33:33|01:80:c2|ff:ff)/.test(m)) return false; // IPv4/IPv6 multicast, STP
    var b1 = parseInt(m.slice(0, 2), 16);
    if (b1 & 0x01) return false; // any group/multicast bit set
    return true;
  }
  function renderLanScan(d) {
    if (!d || !d.ok) return '<div class="ctl-status">' + esc(tr("noLanDevices")) + '</div>';
    // Show ONLY the LLDP/CDP managed devices (switches / routers / APs — the "source"
    // neighbors). The raw ARP/FDB list is intentionally not shown (owner request).
    var lldp = (d.lldp || []);
    if (!lldp.length) return '<div class="empty">' + tr("noLldpNeighbors") + '</div>';
    return '<h4 style="margin:10px 0 6px">' + tr("lldpNeighbors") + ' (' + lldp.length + ')</h4>' +
      '<div class="table-wrap"><table><thead><tr><th>' + tr("deviceName") + '</th><th>' + tr("platform") + '</th><th>IP</th><th>' + tr("localPort") + '</th><th>' + tr("remotePort") + '</th></tr></thead><tbody>' +
      lldp.map(function (n) {
        return '<tr><td>' + esc(n.name || "—") + '</td><td>' + esc(n.platform || "—") + '</td><td class="latin">' + esc(n.ip || "—") + '</td><td class="latin">' + esc(n.local_port || "—") + '</td><td class="latin">' + esc(n.remote_port || "—") + '</td></tr>';
      }).join("") + '</tbody></table></div>';
  }
  async function scanLan() {
    var btn = $("lanScanBtn"), box = $("lanScanResult");
    if (!btn || !box) return;
    btn.disabled = true; var old = btn.textContent; btn.textContent = tr("scanning");
    box.innerHTML = '<div class="ctl-status">' + esc(tr("scanning")) + '</div>';
    try {
      var r = await fetch(CTL, { method: "POST", cache: "no-store",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "section=devices&action=lan_neighbors&" + sidQuery() + "&_=" + Date.now() });
      if (r.status === 403) { requireLogin(tr("loginBad")); return; }
      var d = await r.json();
      state.lanScan = d; // persist so the 5s poll re-render keeps the result
      box.innerHTML = renderLanScan(d);
      bindDynamic();
    } catch (e) {
      box.innerHTML = '<div class="ctl-status">' + esc("scan: " + e.message) + '</div>';
    } finally { btn.disabled = false; btn.textContent = old; }
  }
  function healthCard(data) {
    var h = data.health; if (!h) return "";
    var score = num(h.score); if (!finite(score)) return "";
    var col = score >= 85 ? "var(--excellent)" : score >= 70 ? "var(--good)" : score >= 50 ? "var(--mid)" : "var(--weak)";
    var reasons = (h.reasons || []).map(function (r) {
      var rc = r.level === "ok" ? "var(--excellent)" : r.level === "mid" ? "var(--mid)" : "var(--weak)";
      var msg = state.lang === "ar" ? (r.ar || r.en) : (r.en || r.ar);
      return '<div class="hs-reason" style="border-inline-start:3px solid ' + rc + '">' + esc(msg) + '</div>';
    }).join("");
    var extra = '<div class="grid two" style="margin-top:10px">' +
      '<div class="traffic-box"><span>' + tr("airtime") + '</span><b class="latin">' + (finite(num(h.busy_pct)) ? h.busy_pct + "%" : tr("unavailable")) + '</b></div>' +
      '<div class="traffic-box"><span>' + tr("latency") + '</span><b class="latin">' + (finite(num(data.latency_ms)) ? fmt(num(data.latency_ms), 1) + " ms" : tr("unavailable")) + '</b></div></div>';
    var body = '<div class="hs-wrap"><div class="hs-score" style="color:' + col + ';border-color:' + col + '"><b>' + score + '</b><small>/100</small></div>' +
      '<div class="hs-reasons">' + (reasons || '<div class="hs-reason">' + esc(tr("ok")) + '</div>') + '</div></div>' + extra;
    return card(tr("healthScore"), body, tr(h.grade === "excellent" ? "ok" : h.grade === "weak" ? "warn" : "ok"), "shield");
  }
  function renderWifi(data) {
    var w = data.wifi || [];
    var body = w.length ? '<div class="grid two">' + w.map(function (x) {
      var sig = num(x.signal_dbm), q = quality("rssi", sig);
      var busy = x.survey ? num(x.survey.busy_pct) : null;
      var sta = (x.stations || []).map(function (s) {
        var ss = num(s.signal_dbm), qq = quality("rssi", ss);
        var rate = num(s.tx_rate), rrate = num(s.rx_rate), exp = num(s.expected_mbps);
        var meta = [];
        if (finite(rate)) meta.push("TX " + fmt(rate, 0));
        if (finite(rrate)) meta.push("RX " + fmt(rrate, 0));
        if (finite(exp)) meta.push("~" + fmt(exp, 0));
        var metaStr = meta.length ? '<small class="muted latin">' + esc(meta.join(" · ") + " Mbps") + '</small>' : "";
        // per-client signal trend (kept per MAC in localStorage histories)
        if (s.mac && finite(ss)) pushHistory("sig_" + s.mac, ss, 40);
        var eff = linkEfficiency(x.band, rate);
        var effStr = eff !== null ? '<span class="prox" style="color:' + (eff >= 70 ? "var(--excellent)" : eff >= 40 ? "var(--good)" : "var(--mid)") + '">' + tr("efficiency") + " " + eff + '%</span>' : "";
        var trendStr = (s.mac && (state.histories["sig_" + s.mac] || []).length > 2) ? spark(state.histories["sig_" + s.mac], qq.color) : "";
        var trafficStr = stationTrafficHtml(s);
        // 802.11v steer button — offered only for clients sitting on the 2.4G radio
        var steer = (x.band === "2.4G" && s.mac) ? ' <button class="btn dev-action" title="' + esc(tr("steerHint")) + '" data-steer-mac="' + esc(s.mac) + '" data-steer-iface="' + esc(x.iface || "") + '">' + esc(tr("steer5g")) + '</button>' : "";
        return '<div class="kv"><div><span class="latin">' + esc(s.ip || s.mac || tr("unavailable")) + steer + '</span><b class="latin">' + (finite(ss) ? ss + " dBm " : "") + proximity(ss) + '</b></div>' + bar(finite(ss) ? signalPct("rssi", ss) : 0, 100, qq.color) +
          '<div class="cli-tags">' + distanceLabel(ss) + effStr + '</div>' + metaStr + trafficStr + trendStr + '</div>';
      }).join("") || '<div class="empty">' + tr("unavailable") + '</div>';
      var busyRow = finite(busy) ? '<div><span>' + tr("airtime") + '</span><b class="latin" style="color:' + (busy >= 60 ? "var(--weak)" : busy >= 35 ? "var(--mid)" : "var(--excellent)") + '">' + busy + '%</b></div>' : "";
      // TX power: show the configured value (35) as the headline, like the user's build
      var txp = x.txpower || {}, txReq = num(txp.requested_dbm), txApplied = num(txp.applied_dbm);
      var txShown = finite(txReq) ? txReq : (finite(txApplied) ? txApplied : 35);
      var powerRow = '<div><span>Power</span><b class="latin" style="color:var(--excellent)">' + fmt(txShown, 0) + ' dBm</b></div>';
      return card(esc(x.ssid || x.iface), '<div class="kv"><div><span>Band</span><b>' + esc(x.band || "") + '</b></div><div><span>' + tr("channel") + '</span><b>' + esc(x.channel || "") + '</b></div><div><span>Mode</span><b class="latin">' + esc(x.htmode || "") + '</b></div><div><span>Clients</span><b>' + (x.clients || 0) + '</b></div><div><span>RSSI</span><b class="latin" style="color:' + q.color + '">' + (finite(sig) ? sig + " dBm" : tr("unavailable")) + '</b></div>' + powerRow + busyRow + '</div><h4>Clients · ' + tr("linkRate") + '</h4>' + sta, esc(x.hw_modes || ""), "wifi");
    }).join("") + '</div>' : '<div class="empty">' + tr("unavailable") + '</div>';
    // count total connected stations to decide whether to show the radar
    var totalSta = w.reduce(function (a, x) { return a + ((x.stations || []).length); }, 0);
    if (w.length) {
      setTimeout(function () { drawChannels($("channelCanvas"), w); }, 0);
      setTimeout(function () { drawChannels($("channelCanvas"), w); }, 450);
      setTimeout(function () { drawConstellation($("constellationCanvas"), w); }, 0);
      setTimeout(function () { drawConstellation($("constellationCanvas"), w); }, 450);
    }
    var chanCard = w.length ? card(state.lang === "ar" ? "إشغال القنوات" : "Channel occupancy",
      '<canvas id="channelCanvas" style="width:100%;height:150px"></canvas>', "2.4G / 5G", "signal") : "";
    var radarCard = totalSta ? card(tr("clientRadar"),
      '<canvas id="constellationCanvas" style="width:100%;height:230px"></canvas><p class="muted" style="text-align:center">' + esc(tr("constellation")) + '</p>', totalSta + "", "device") : "";
    // best-channel scan + neighboring networks (on-demand; scanning briefly dips throughput)
    var scanCard = card(tr("bestChannel") + " · " + tr("neighbors"),
      '<div class="branch-actions"><button class="btn primary" id="wifiScanBtn">' + esc(tr("scanNeighbors")) + '</button></div>' +
      '<div id="wifiScanResult">' + (state.lastScan ? renderScanResult(state.lastScan) : "") + '</div>', "iw scan", "signal");
    return sectionHead("WiFi AX / AC / N", "Clients, RSSI, " + tr("linkRate"), "offline") +
      healthCard(data) + '<div class="grid two">' + chanCard + renderSecPosture(data) + '</div>' + scanCard + radarCard + body;
  }
  // Client constellation radar: clients orbit the AP, radius = signal (strong→center),
  // colour = band, dot size = link rate. Pure offline canvas over live assoclist data.
  function drawConstellation(canvas, wifiList) {
    if (!canvas) return;
    var host = canvas.parentElement || canvas, dpr = window.devicePixelRatio || 1;
    var hostW = host.getBoundingClientRect().width;
    if (window.getComputedStyle) { var cs = getComputedStyle(host); hostW -= (parseFloat(cs.paddingLeft) || 0) + (parseFloat(cs.paddingRight) || 0); }
    var w = Math.max(260, Math.floor(hostW || 300)), h = 230;
    if (canvas.width !== w * dpr || canvas.height !== h * dpr) { canvas.width = w * dpr; canvas.height = h * dpr; }
    var ctx = canvas.getContext("2d"); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
    var cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2 - 18;
    var grid = cssVar("--border", "rgba(148,163,184,.16)"), muted = cssVar("--muted", "#94A3B8");
    var accent = cssVar("--accent", "#06B6D4"), primary = cssVar("--primary", "#3B82F6");
    // range rings labelled with both RSSI and the estimated distance (m)
    ctx.strokeStyle = grid; ctx.lineWidth = 1;
    [0.33, 0.66, 1].forEach(function (f) { ctx.beginPath(); ctx.arc(cx, cy, R * f, 0, Math.PI * 2); ctx.stroke(); });
    ctx.fillStyle = muted; ctx.font = "9px system-ui"; ctx.textAlign = "center";
    function ringLbl(dbm) { var d = distanceM(dbm); return dbm + (d !== null ? " · " + (d < 10 ? d.toFixed(1) : Math.round(d)) + tr("meters") : ""); }
    ctx.fillText(ringLbl(-45), cx, cy - R * 0.33 + 3); ctx.fillText(ringLbl(-75), cx, cy - R * 0.66 + 3); ctx.fillText(ringLbl(-90), cx, cy - R + 3);
    // centre AP
    ctx.fillStyle = primary; ctx.beginPath(); ctx.arc(cx, cy, 8, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = accent; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(cx, cy, 12, 0, Math.PI * 2); ctx.stroke();
    var pts = [];
    (wifiList || []).forEach(function (x) {
      var band5 = x.band === "5G";
      (x.stations || []).forEach(function (s) { pts.push({ sig: num(s.signal_dbm), rate: num(s.tx_rate), band5: band5, mac: s.mac }); });
    });
    var n = pts.length || 1, i = 0;
    pts.forEach(function (p) {
      var sig = finite(p.sig) ? clamp(p.sig, -95, -30) : -75;
      var frac = (-30 - sig) / (-30 - -95); // 0 (strong, near) .. 1 (weak, far)
      var rad = 16 + frac * (R - 20);
      var ang = (i / n) * Math.PI * 2 - Math.PI / 2; i++;
      var px = cx + rad * Math.cos(ang), py = cy + rad * Math.sin(ang);
      var col = p.band5 ? primary : accent;
      var sz = 4 + clamp((finite(p.rate) ? p.rate : 100) / 200, 0, 6);
      ctx.strokeStyle = hexA(col, 0.35); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(px, py); ctx.stroke();
      ctx.fillStyle = col; ctx.beginPath(); ctx.arc(px, py, sz, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = hexA(col, 0.18); ctx.beginPath(); ctx.arc(px, py, sz + 4, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = muted; ctx.font = "9px system-ui"; ctx.textAlign = "center";
      ctx.fillText(finite(p.sig) ? p.sig + "" : "?", px, py - sz - 4);
    });
  }
  async function scanWifi() {
    var btn = $("wifiScanBtn"), box = $("wifiScanResult");
    if (!btn || !box) return;
    btn.disabled = true; var old = btn.textContent; btn.textContent = tr("scanning");
    box.innerHTML = '<div class="ctl-status">' + esc(tr("scanning")) + '</div>';
    try {
      var r = await fetch(CTL, { method: "POST", cache: "no-store",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "section=wifiscan&action=secscan_run&" + sidQuery() + "&_=" + Date.now() });
      if (r.status === 403) { requireLogin(tr("loginBad")); return; }
      var d = await r.json();
      state.lastScan = d; // persist so the 5s poll re-render doesn't wipe results
      box.innerHTML = renderScanResult(d);
      bindDynamic();
    } catch (e) {
      box.innerHTML = '<div class="ctl-status">' + esc("scan: " + e.message) + '</div>';
    } finally { btn.disabled = false; btn.textContent = old; }
  }
  function renderScanResult(d) {
    if (!d || !d.ok) return '<div class="ctl-status">' + esc(tr("noNeighbors")) + '</div>';
    var neigh = (d.neighbors || []).slice().sort(function (a, b) { return (num(b.signal) || -999) - (num(a.signal) || -999); });
    var rogues = neigh.filter(function (x) { return x.rogue; });
    var best24 = num(d.best24), best5 = num(d.best5), cur24 = num(d.cur24), cur5 = num(d.cur5);
    var reco = '<div class="grid two" style="margin-bottom:10px">' +
      '<div class="ctl-card ok"><span>2.4G ' + tr("recommended") + '</span><b class="latin">' + (finite(best24) ? best24 : "-") + '</b><small>' + tr("current") + ": " + (finite(cur24) ? cur24 : "-") + '</small></div>' +
      '<div class="ctl-card ok"><span>5G ' + tr("recommended") + '</span><b class="latin">' + (finite(best5) ? best5 : "-") + '</b><small>' + tr("current") + ": " + (finite(cur5) ? cur5 : "-") + '</small></div></div>';
    var applyBtn = (finite(best24) || finite(best5)) ?
      '<div class="branch-actions"><button class="btn primary" id="wifiApplyChanBtn" data-ch24="' + (finite(best24) ? best24 : "") + '" data-ch5="' + (finite(best5) ? best5 : "") + '">' + esc(tr("applyBest")) + ' (2.4G ' + (finite(best24) ? best24 : "-") + ' · 5G ' + (finite(best5) ? best5 : "-") + ')</button></div>' : "";
    var rogueHtml = rogues.length ? '<div class="hs-reason" style="border-inline-start:3px solid var(--weak);margin-bottom:8px"><b>⚠ ' + esc(tr("rogueAlert")) + '</b> — ' + esc(tr("rogueDesc")) + ' (' + rogues.length + ')</div>' : "";
    var list = neigh.length ? '<div class="table-wrap"><table><thead><tr><th>SSID</th><th>' + tr("channel") + '</th><th>Signal</th><th>BSSID</th></tr></thead><tbody>' +
      neigh.slice(0, 30).map(function (x) {
        var sg = num(x.signal);
        return '<tr' + (x.rogue ? ' style="background:rgba(239,68,68,.12)"' : '') + '><td>' + esc(x.ssid || "—") + (x.rogue ? ' ⚠' : '') + '</td><td class="latin">' + esc(x.ch || "?") + '</td><td class="latin">' + (finite(sg) ? sg + " dBm " + proximity(sg) : "?") + '</td><td class="latin">' + esc((x.bssid || "").toUpperCase()) + '</td></tr>';
      }).join("") + '</tbody></table></div>' : '<div class="empty">' + tr("noNeighbors") + '</div>';
    return reco + applyBtn + '<h4>' + tr("neighbors") + ' (' + neigh.length + ')</h4>' + rogueHtml + list;
  }
  async function applyBestChannels(ch24, ch5) {
    try {
      var body = "section=wifiscan&action=apply_best_channels&confirm=1";
      if (ch24) body += "&ch24=" + encodeURIComponent(ch24);
      if (ch5) body += "&ch5=" + encodeURIComponent(ch5);
      var r = await fetch(CTL, { method: "POST", cache: "no-store",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body + "&" + sidQuery() + "&_=" + Date.now() });
      if (r.status === 403) { requireLogin(tr("loginBad")); return; }
      var j = await r.json();
      toast(j.summary || tr("ok"));
      event("Best channel applied: 2.4G=" + (ch24 || "-") + " 5G=" + (ch5 || "-"));
      setTimeout(loadData, 800);
    } catch (e) { toast(e.message); }
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
      ctx.fillStyle = color; ctx.font = "bold 11px system-ui";
      // 2.4G labels anchor to the right of the peak, 5G to the left, and the two bands
      // sit at different heights — so an adjacent 11|36 pair never glues into one string.
      ctx.textAlign = band5 ? "left" : "right";
      var lx = band5 ? cx + 3 : cx - 3, ly = base - bh - (band5 ? 6 : 20);
      ctx.fillText((band5 ? "5G " : "2.4G ") + ch + " (" + cl + ")", lx, ly);
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
    // nightly self-test card (runs 04:00 by cron; button runs it now). Result is kept in
    // state so the 5s poll re-render doesn't wipe it.
    var st = state.selftest;
    var stBody = '<p class="muted">' + esc(tr("selftestHint")) + '</p>' +
      '<div class="branch-actions"><button class="btn primary" id="selftestBtn">' + esc(tr("selftestRun")) + '</button></div>';
    if (st && st.ok) {
      var sc = num(st.score), scCol = sc >= 85 ? "var(--excellent)" : sc >= 70 ? "var(--good)" : sc >= 50 ? "var(--mid)" : "var(--weak)";
      stBody += '<div class="hs-wrap" style="margin-top:10px"><div class="hs-score" style="color:' + scCol + ';border-color:' + scCol + '"><b>' + esc(st.score) + '</b><small>/100</small></div>' +
        '<div class="hs-reasons">' +
        '<div class="hs-reason">' + esc(tr("lastReport")) + ': <b class="latin">' + esc(st.time || "") + '</b></div>' +
        '<div class="hs-reason latin">' + tr("temp") + ' ' + esc(st.temp_c == null ? "—" : st.temp_c + "°") + ' · RAM ' + esc(st.mem_pct) + '% · ' + tr("airtime") + ' ' + esc(st.busy_pct) + '% · Clients ' + esc(st.clients) + '</div>' +
        '<div class="hs-reason">' + esc(tr("selftestNotes")) + ': ' + esc(st.notes || "") + '</div>' +
        '</div></div>';
    }
    var selftestCard = card(tr("selftest"), stBody, "04:00", "shield");
    return sectionHead(tr("systemTitle"), "loadavg / free / overlay / thermal", "thresholds") + card("Health", body, "live", "cpu") + trendCard + selftestCard + card("Availability 24h", availabilityHtml(), "local", "bolt");
  }
  function renderNetwork(data, rates) {
    var interfaces = data.interfaces || [];
    var table = '<div class="table-wrap"><table><thead><tr><th>Interface</th><th>Status</th><th>Speed</th><th>RX Rate</th><th>TX Rate</th><th>RX Total</th><th>TX Total</th><th>Errors/Drops</th></tr></thead><tbody>' +
      interfaces.map(function (i) {
        var irx = num(i.rx_bps), itx = num(i.tx_bps);
        return '<tr><td class="latin">' + esc(i.name) + '</td><td><span class="chip ' + (i.connected ? "ok" : "bad") + '">' + (i.connected ? "up" : "down") + '</span></td><td class="latin">' + (i.speed_mbps ? i.speed_mbps + " Mbps" : tr("unavailable")) + '</td><td class="latin">' + bps(finite(irx) ? irx : (i.name === "br-lan" ? rates.rx : 0)) + '</td><td class="latin">' + bps(finite(itx) ? itx : (i.name === "br-lan" ? rates.tx : 0)) + '</td><td class="latin">' + bytes(i.rx_bytes) + '</td><td class="latin">' + bytes(i.tx_bytes) + '</td><td class="latin">' + (i.rx_errors||0) + "/" + (i.tx_errors||0) + " · " + (i.rx_dropped||0) + "/" + (i.tx_dropped||0) + '</td></tr>';
      }).join("") +
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
  // Strip anything that looks like code / commands / paths / config so the panels
  // never expose build or programming details — keep only plain human sentences.
  function cleanNote(text) {
    if (!text) return "";
    var techy = /[\/=$`{}<>]|\buci\b|\bnft\b|\bbr-lan\b|\bbr-vlan\b|\bbridge\b|\bpolicy\b|\bshow\b|\blink\b|guard|isolated|enabled=|flood|rogue|wan\.\d|lan[123]|0x|::|\.conf|\.sh\b|tmp|backup|Backup|dBm|txpower|vlan_filtering|bridge-vlan|iwinfo|ubus|dnsmasq|firewall reload|reload|commit|smartap|radio[01]|wifinet/i;
    var lines = String(text).split(/\r?\n/).map(function (s) { return s.trim(); })
      .filter(function (s) { return s && !techy.test(s); });
    return lines.join("\n");
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
    var note = cleanNote(data.text);
    if (note) html += '<div class="ctl-note">' + esc(note) + '</div>';
    return html || '<div class="ctl-status">' + (state.lang === "ar" ? "تم." : "Done.") + '</div>';
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
    if (type === "number" && f.options) {
      var mm = String(f.options).split(":");
      var at = (mm[0] !== undefined && mm[0] !== "" ? ' min="' + esc(mm[0]) + '"' : '') + (mm[1] ? ' max="' + esc(mm[1]) + '"' : '') + (mm[2] ? ' step="' + esc(mm[2]) + '"' : '');
      return wrap + '<input class="latin" data-ctl-field="' + esc(f.name) + '" type="number"' + at + ' value="' + esc(f.value) + '" autocomplete="off"' + ro + '>' + tail;
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
      '<p class="mode-hint">كل تطبيق يُحفظ فوراً (Apply & Keep) مع نسخة احتياطية وتأكيد قبل التنفيذ، طاقة البث من 1 إلى 38 (تختارها من التبويب المتقدم).</p>' +
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
      '<div class="kv"><span>TX Power</span><b class="latin">' + esc(fv("txpower") || "38") + ' dBm</b></div>';
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
  // New-device join alert: remembers every MAC ever seen (localStorage) and
  // raises a toast + event the first time an unknown device appears. Fully offline.
  function detectNewDevices(data) {
    var known;
    try { known = JSON.parse(localStorage.getItem(LS + "knownMacs") || "[]"); } catch (e) { known = []; }
    var set = {}, changed = false;
    known.forEach(function (m) { set[m] = 1; });
    var first = !known.length; // first run: learn silently, don't spam alerts
    mergeDevices(data).forEach(function (d) {
      var m = (d.mac || "").toLowerCase();
      if (!m || set[m]) return;
      set[m] = 1; changed = true;
      if (!first) {
        var label = m.toUpperCase() + (d.vendor ? " · " + d.vendor : "");
        toast(tr("newDevice") + ": " + label);
        event(tr("newDevice") + ": " + label, "warn");
      }
    });
    if (changed) localStorage.setItem(LS + "knownMacs", JSON.stringify(Object.keys(set).slice(-400)));
  }
  // Helper bundle passed to every Pro-Insights feature module (see PRO_FEATURES).
  // Each feature is a pure function(d, H) that returns a card HTML string.
  var H = {
    get lang() { return state.lang; },
    card: card, bar: bar, gauge: gauge, spark: spark, esc: esc, fmt: fmt,
    bytes: bytes, bps: bps, num: num, finite: finite, clamp: clamp, pct: pct,
    quality: quality, distanceM: distanceM, proximity: proximity, tr: tr,
    cssVar: cssVar, hexA: hexA, wifiBand: wifiBand, mergeDevices: mergeDevices,
    secLevel: secLevel, linkEfficiency: linkEfficiency, levelColor: levelColor,
    signalPct: signalPct, uptime: uptime, icon: icon,
    stationTraffic: stationTraffic, stationTrafficRows: stationTrafficRows
  };
  // Registry of professional feature cards (populated from the multi-agent design pass).
  // Each entry: { key, ar, en, cat, fn:function(d,H)->html }. Rendered with per-feature
  // isolation so one bad module can never break the section.
  var PRO_FEATURES = [
{key:"airtime_busy",ar:"انشغال الهواء",en:"Airtime Busy",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];if(!w.length)return H.card(H.lang==='ar'?'انشغال الهواء':'Airtime Busy','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا يوجد راديو':'No radios')+'</div>',null,'signal');var rows='';for(var i=0;i<w.length;i++){var r=w[i],sv=r.survey||{};var b=H.num(sv.busy_pct);b=H.finite(b)?H.clamp(b,0,100):null;var col=b==null?'var(--muted)':(b<30?'var(--excellent)':b<60?'var(--good)':b<80?'var(--mid)':'var(--weak)');var lab=b==null?'—':H.fmt(b,0)+'%';rows+='<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+'</span><span style="color:'+col+'">'+lab+'</span></div>'+H.bar(b||0,100,col)+'</div>';}return H.card(H.lang==='ar'?'انشغال الهواء':'Airtime Busy',rows,null,'signal');}},
  {key:"noise_floor",ar:"أرضية الضوضاء",en:"Noise Floor",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var rows='',n=0;for(var i=0;i<w.length;i++){var r=w[i];var nf=H.num(r.noise_dbm);if(nf==null&&r.survey)nf=H.num(r.survey.noise_dbm);if(!H.finite(nf))continue;n++;var pct=H.clamp((nf+100)/40*100,0,100);var col=nf<=-90?'var(--excellent)':nf<=-80?'var(--good)':nf<=-70?'var(--mid)':'var(--weak)';rows+='<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+'</span><span style="color:'+col+'">'+H.fmt(nf,0)+' dBm</span></div>'+H.bar(pct,100,col)+'</div>';}if(!n)rows='<div style="color:var(--muted)">'+(H.lang==='ar'?'لا بيانات ضوضاء':'No noise data')+'</div>';return H.card(H.lang==='ar'?'أرضية الضوضاء':'Noise Floor',rows,null,'signal');}},
  {key:"spectrum_load",ar:"حمل الطيف",en:"Spectrum Load",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var s=0,n=0;for(var i=0;i<w.length;i++){var b=H.num((w[i].survey||{}).busy_pct);if(H.finite(b)){s+=H.clamp(b,0,100);n++;}}if(!n)return H.card(H.lang==='ar'?'حمل الطيف':'Spectrum Load','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا بيانات':'No data')+'</div>',null,'signal');var busy=s/n;var col=busy<30?'var(--excellent)':busy<60?'var(--good)':busy<80?'var(--mid)':'var(--weak)';var C=2*Math.PI*52,off=C*(1-busy/100);var svg='<svg width="140" height="140" viewBox="0 0 140 140" style="display:block;margin:0 auto"><circle cx="70" cy="70" r="52" fill="none" stroke="var(--muted)" stroke-opacity=".2" stroke-width="14"/><circle cx="70" cy="70" r="52" fill="none" stroke="'+col+'" stroke-width="14" stroke-linecap="round" stroke-dasharray="'+C.toFixed(1)+'" stroke-dashoffset="'+off.toFixed(1)+'" transform="rotate(-90 70 70)"/><text x="70" y="66" text-anchor="middle" font-size="26" fill="var(--text)">'+H.fmt(busy,0)+'%</text><text x="70" y="88" text-anchor="middle" font-size="11" fill="var(--muted)">'+(H.lang==='ar'?'مشغول':'busy')+'</text></svg>';var sub='<div style="text-align:center;color:var(--muted);font-size:12px;margin-top:4px">'+n+' '+(H.lang==='ar'?'راديو · متوسط':'radios · avg')+'</div>';return H.card(H.lang==='ar'?'حمل الطيف':'Spectrum Load',svg+sub,H.fmt(busy,0)+'%','signal');}},
  {key:"interference_index",ar:"مؤشر التشويش",en:"Interference Index",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var arr=[];for(var i=0;i<w.length;i++){var r=w[i];var busy=H.num((r.survey||{}).busy_pct);var nf=H.num(r.noise_dbm);if(nf==null&&r.survey)nf=H.num(r.survey.noise_dbm);var bs=H.finite(busy)?H.clamp(busy,0,100):0;var ns=H.finite(nf)?H.clamp((nf+95)/30*100,0,100):0;arr.push({band:r.band||'?',ch:r.channel,idx:H.clamp(bs*.6+ns*.4,0,100)});}if(!arr.length)return H.card(H.lang==='ar'?'مؤشر التشويش':'Interference','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا بيانات':'No data')+'</div>',null,'shield');arr.sort(function(a,b){return b.idx-a.idx});var rows='';for(var j=0;j<arr.length;j++){var a=arr[j];var col=a.idx<30?'var(--excellent)':a.idx<55?'var(--good)':a.idx<75?'var(--mid)':'var(--weak)';var t=a.idx<30?(H.lang==='ar'?'نظيف':'clean'):a.idx<55?(H.lang==='ar'?'خفيف':'light'):a.idx<75?(H.lang==='ar'?'متوسط':'moderate'):(H.lang==='ar'?'مرتفع':'high');rows+='<div style="margin:6px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(a.band)+' · ch '+H.esc(String(a.ch||'?'))+'</span><span style="color:'+col+'">'+H.fmt(a.idx,0)+' · '+t+'</span></div>'+H.bar(a.idx,100,col)+'</div>';}return H.card(H.lang==='ar'?'مؤشر التشويش':'Interference Index',rows,null,'shield');}},
  {key:"band_balance",ar:"توازن الترددات",en:"Band Balance",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var c24=0,c5=0,found=false;for(var i=0;i<w.length;i++){var r=w[i];var cl=H.num(r.clients);cl=H.finite(cl)?cl:(Array.isArray(r.stations)?r.stations.length:0);if(r.band==='2.4G')c24+=cl;else if(r.band==='5G')c5+=cl;found=true;}if(!found)return H.card(H.lang==='ar'?'توازن الترددات':'Band Balance','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا راديو':'No radios')+'</div>',null,'wifi');var tot=c24+c5;var p24=tot?c24/tot*100:50,p5=tot?c5/tot*100:50;var bar='<div style="display:flex;height:26px;border-radius:6px;overflow:hidden;background:var(--muted)"><div style="width:'+p24.toFixed(1)+'%;background:var(--mid);display:flex;align-items:center;justify-content:center;font-size:11px;color:#000">'+(p24>12?'2.4G':'')+'</div><div style="width:'+p5.toFixed(1)+'%;background:var(--accent);display:flex;align-items:center;justify-content:center;font-size:11px;color:#000">'+(p5>12?'5G':'')+'</div></div>';var leg='<div style="display:flex;justify-content:space-between;margin-top:8px;font-size:12px"><span style="color:var(--mid)">2.4G · '+c24+' ('+H.fmt(p24,0)+'%)</span><span style="color:var(--accent)">5G · '+c5+' ('+H.fmt(p5,0)+'%)</span></div>';return H.card(H.lang==='ar'?'توازن الترددات':'Band Balance',bar+leg,tot+(H.lang==='ar'?' جهاز':' cl'),'wifi');}},
  {key:"channel_width",ar:"عرض القناة",en:"Channel Width",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];if(!w.length)return H.card(H.lang==='ar'?'عرض القناة':'Channel Width','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا راديو':'No radios')+'</div>',null,'net');var wm={HE20:20,HE40:40,HE80:80,HE160:160,VHT80:80,VHT40:40,VHT20:20,HT20:20,HT40:40};var cells='';for(var i=0;i<w.length;i++){var r=w[i];var ht=String(r.htmode||'').toUpperCase();var mhz=wm[ht]||H.num(r.width)||20;var pct=H.clamp(mhz/160*100,0,100);var col=mhz>=80?'var(--excellent)':mhz>=40?'var(--good)':'var(--mid)';cells+='<div style="flex:1;min-width:118px;padding:10px;border:1px solid var(--muted);border-radius:8px;margin:4px"><div style="font-size:12px;color:var(--muted)">'+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+'</div><div style="font-size:20px;color:'+col+';font-weight:600">'+mhz+' MHz</div><div style="font-size:11px;color:var(--muted);margin-bottom:4px">'+H.esc(ht||'—')+'</div>'+H.bar(pct,100,col)+'</div>';}return H.card(H.lang==='ar'?'عرض القناة':'Channel Width','<div style="display:flex;flex-wrap:wrap">'+cells+'</div>',null,'net');}},
  {key:"cochannel_pressure",ar:"ضغط القناة",en:"Co-Channel Pressure",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var arr=[];for(var i=0;i<w.length;i++){var r=w[i];var busy=H.num((r.survey||{}).busy_pct);busy=H.finite(busy)?H.clamp(busy,0,100):null;if(busy==null)continue;var cl=H.num(r.clients);cl=H.finite(cl)?cl:(Array.isArray(r.stations)?r.stations.length:0);var press=H.clamp(busy*(1+Math.min(cl,12)/12),0,100);arr.push({band:r.band||'?',ch:r.channel,press:press,cl:cl});}if(!arr.length)return H.card(H.lang==='ar'?'ضغط القناة':'Co-Channel','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا بيانات':'No data')+'</div>',null,'signal');arr.sort(function(a,b){return b.press-a.press});var rows='';for(var j=0;j<arr.length;j++){var a=arr[j];var col=a.press<35?'var(--excellent)':a.press<60?'var(--good)':a.press<80?'var(--mid)':'var(--weak)';rows+='<div style="display:flex;align-items:center;gap:8px;margin:7px 0"><span style="flex:0 0 20px;width:20px;height:20px;border-radius:50%;background:'+col+';color:#000;font-size:11px;display:flex;align-items:center;justify-content:center">'+(j+1)+'</span><div style="flex:1"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(a.band)+' ch '+H.esc(String(a.ch||'?'))+' · '+a.cl+' cl</span><span style="color:'+col+'">'+H.fmt(a.press,0)+'</span></div>'+H.bar(a.press,100,col)+'</div></div>';}return H.card(H.lang==='ar'?'ضغط القناة المشتركة':'Co-Channel Pressure',rows,null,'signal');}},
// ---------- Clients & Devices ----------
{key:"client_signal_rank",ar:"ترتيب إشارة العملاء",en:"Client Signal Ranking",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});if(!st.length)return H.card(H.lang==="ar"?"ترتيب إشارة العملاء":"Client Signal Ranking","<div class='empty'>"+(H.lang==="ar"?"لا عملاء":"No clients")+"</div>",null,"device");st.sort(function(a,b){return (H.num(b.signal_dbm)||-999)-(H.num(a.signal_dbm)||-999);});var r=st.slice(0,8).map(function(s){var v=H.num(s.signal_dbm),q=H.quality("rssi",v);return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(s.ip||s.mac||"?")+"</span><span style='color:"+q.color+"'>"+(H.finite(v)?v+" dBm":"?")+"</span></div>"+H.bar(H.finite(v)?H.signalPct("rssi",v):0,100,q.color)+"</div>";}).join("");return H.card(H.lang==="ar"?"ترتيب إشارة العملاء":"Client Signal Ranking",r,st.length+"","device");}},
{key:"sticky_clients",ar:"عملاء عالقون على 2.4G",en:"Sticky 2.4G Clients",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push({b:w.band,s:s});});});var bad=st.filter(function(x){return x.b==="2.4G"&&H.finite(H.num(x.s.signal_dbm))&&H.num(x.s.signal_dbm)>=-70;});var body=bad.length?bad.map(function(x){return "<div class='kv'><div><span class='latin'>"+H.esc(x.s.ip||x.s.mac)+"</span><b style='color:var(--mid)'>"+H.num(x.s.signal_dbm)+" dBm &rarr; 5G</b></div></div>";}).join(""):"<div style='color:var(--excellent)'>"+(H.lang==="ar"?"لا عملاء عالقون — التوزيع سليم":"No sticky clients — good distribution")+"</div>";return H.card(H.lang==="ar"?"عملاء عالقون على 2.4G":"Sticky 2.4G Clients",body,bad.length+"","wifi");}},
{key:"idle_clients",ar:"عملاء خاملون",en:"Idle Clients",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});if(!st.length)return H.card(H.lang==="ar"?"عملاء خاملون":"Idle Clients","<div class='empty'>—</div>",null,"device");var idle=st.filter(function(s){return H.finite(H.num(s.inactive_ms))&&H.num(s.inactive_ms)>60000;});idle.sort(function(a,b){return H.num(b.inactive_ms)-H.num(a.inactive_ms);});var body=idle.length?idle.map(function(s){return "<div class='kv'><div><span class='latin'>"+H.esc(s.ip||s.mac)+"</span><b class='latin'>"+Math.round(H.num(s.inactive_ms)/1000)+"s</b></div></div>";}).join(""):"<div style='color:var(--muted)'>"+(H.lang==="ar"?"كل العملاء نشطون":"All clients active")+"</div>";return H.card(H.lang==="ar"?"عملاء خاملون":"Idle Clients",body,idle.length+"/"+st.length,"device");}},
{key:"client_uptime",ar:"مدة اتصال العملاء",en:"Client Connected Time",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});var wt=st.filter(function(s){return H.finite(H.num(s.conn_s));});if(!wt.length)return H.card(H.lang==="ar"?"مدة الاتصال":"Connected Time","<div class='empty'>—</div>",null,"device");wt.sort(function(a,b){return H.num(b.conn_s)-H.num(a.conn_s);});var r=wt.slice(0,8).map(function(s){var t=H.num(s.conn_s),h=Math.floor(t/3600),m=Math.floor(t%3600/60);return "<div class='kv'><div><span class='latin'>"+H.esc(s.ip||s.mac)+"</span><b class='latin'>"+(h?h+"h "+m+"m":m+"m")+"</b></div></div>";}).join("");return H.card(H.lang==="ar"?"مدة اتصال العملاء":"Client Connected Time",r,wt.length+"","device");}},
{key:"device_type_split",ar:"توزيع أنواع الأجهزة",en:"Device Type Split",cat:"Clients & Devices",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"أنواع الأجهزة":"Device Types","<div class='empty'>—</div>",null,"device");var c={};dv.forEach(function(x){var t=x.type||"?";c[t]=(c[t]||0)+1;});var tot=dv.length,cols={WiFi:"var(--accent)",Ethernet:"var(--primary)",LAN:"var(--good)"};var r=Object.keys(c).map(function(k){var p=c[k]/tot*100;return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(k)+"</span><span>"+c[k]+" ("+H.fmt(p,0)+"%)</span></div>"+H.bar(p,100,cols[k]||"var(--muted)")+"</div>";}).join("");return H.card(H.lang==="ar"?"توزيع أنواع الأجهزة":"Device Type Split",r,tot+"","device");}},
{key:"fastest_client",ar:"أسرع وأبطأ عميل",en:"Fastest / Slowest",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});var wt=st.filter(function(s){return H.finite(H.num(s.tx_rate));});if(!wt.length)return H.card(H.lang==="ar"?"أسرع/أبطأ":"Fastest/Slowest","<div class='empty'>—</div>",null,"net");wt.sort(function(a,b){return H.num(b.tx_rate)-H.num(a.tx_rate);});var f=wt[0],s=wt[wt.length-1];function box(x,lbl,col){return "<div class='traffic-box'><span>"+lbl+"</span><b class='latin' style='color:"+col+"'>"+H.fmt(H.num(x.tx_rate),0)+" Mbps</b><small class='muted latin'>"+H.esc(x.ip||x.mac)+"</small></div>";}return H.card(H.lang==="ar"?"أسرع وأبطأ عميل":"Fastest / Slowest","<div class='grid two'>"+box(f,H.lang==="ar"?"الأسرع":"Fastest","var(--excellent)")+box(s,H.lang==="ar"?"الأبطأ":"Slowest","var(--mid)")+"</div>",wt.length+"","net");}},
// ---------- Security & Threats ----------
{key:"encryption_posture",ar:"حالة تشفير الشبكات",en:"Encryption Posture",cat:"Security & Threats",fn:function(d,H){var w=d.wifi||[];if(!w.length)return H.card(H.lang==="ar"?"الحماية":"Security","<div class='empty'>—</div>",null,"shield");var open=0;var r=w.map(function(x){var s=H.secLevel(x.encryption);if(s.key==="open")open++;return "<div class='kv'><div><span class='latin'>"+H.esc(x.ssid||x.iface)+"</span><b style='color:"+s.col+"'>"+H.esc(s.txt)+"</b></div>"+H.bar(s.key==="wpa3"?100:s.key==="wpa2"?72:30,100,s.col)+"</div>";}).join("");return H.card(H.lang==="ar"?"حالة تشفير الشبكات":"Encryption Posture",r,open?(open+" "+(H.lang==="ar"?"مفتوحة":"open")):(H.lang==="ar"?"آمنة":"secure"),"shield");}},
{key:"mac_random",ar:"العناوين العشوائية",en:"MAC Randomization",cat:"Security & Threats",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"العناوين العشوائية":"MAC Randomization","<div class='empty'>—</div>",null,"shield");var rnd=0;dv.forEach(function(x){var h=String(x.mac||"").replace(/[^0-9a-fA-F]/g,"");if(h.length>=2&&(parseInt(h.slice(0,2),16)&2))rnd++;});var p=rnd/dv.length*100,C=2*Math.PI*46,off=C*(1-p/100);var svg="<svg width='120' height='120' viewBox='0 0 120 120' style='display:block;margin:0 auto'><circle cx='60' cy='60' r='46' fill='none' stroke='var(--muted)' stroke-opacity='.2' stroke-width='12'/><circle cx='60' cy='60' r='46' fill='none' stroke='var(--primary)' stroke-width='12' stroke-linecap='round' stroke-dasharray='"+C.toFixed(1)+"' stroke-dashoffset='"+off.toFixed(1)+"' transform='rotate(-90 60 60)'/><text x='60' y='66' text-anchor='middle' font-size='22' fill='var(--text)'>"+H.fmt(p,0)+"%</text></svg><div style='text-align:center;color:var(--muted);font-size:12px'>"+rnd+"/"+dv.length+" "+(H.lang==="ar"?"خاص":"private")+"</div>";return H.card(H.lang==="ar"?"العناوين العشوائية":"MAC Randomization",svg,null,"shield");}},
{key:"vendor_breakdown",ar:"توزيع الشركات",en:"Vendor Breakdown",cat:"Security & Threats",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"الشركات":"Vendors","<div class='empty'>—</div>",null,"device");var c={};dv.forEach(function(x){var v=x.vendor||(H.lang==="ar"?"غير معروف":"Unknown");c[v]=(c[v]||0)+1;});var ks=Object.keys(c).sort(function(a,b){return c[b]-c[a];}),mx=c[ks[0]]||1;var r=ks.slice(0,7).map(function(k){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(k)+"</span><span>"+c[k]+"</span></div>"+H.bar(c[k],mx,"var(--accent)")+"</div>";}).join("");return H.card(H.lang==="ar"?"توزيع الشركات":"Vendor Breakdown",r,ks.length+"","device");}},
{key:"newest_devices",ar:"أحدث الأجهزة",en:"Newest Devices",cat:"Security & Threats",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"أحدث الأجهزة":"Newest Devices","<div class='empty'>—</div>",null,"shield");var r=dv.slice(-6).reverse().map(function(x){return "<div class='kv'><div><span class='latin'>"+H.esc((x.mac||"?").toUpperCase())+"</span><b class='latin'>"+H.esc(x.ip||x.host||x.type||"")+"</b></div><small class='muted'>"+H.esc(x.vendor||"")+"</small></div>";}).join("");return H.card(H.lang==="ar"?"أحدث الأجهزة المكتشفة":"Newest Devices",r,dv.length+"","shield");}},
{key:"open_net_warn",ar:"تنبيه الشبكات المفتوحة",en:"Open Network Warning",cat:"Security & Threats",fn:function(d,H){var w=d.wifi||[];var op=w.filter(function(x){var e=String(x.encryption||"").toLowerCase();return !e||/none|open/.test(e);});var body=op.length?("<div style='color:var(--mid)'>"+(H.lang==="ar"?"شبكات مفتوحة (بدون كلمة سر):":"Open networks (no password):")+"</div>"+op.map(function(x){return "<div class='kv'><div><span class='latin'>"+H.esc(x.ssid||x.iface)+"</span><b style='color:var(--mid)'>"+(H.lang==="ar"?"مفتوح":"OPEN")+"</b></div></div>";}).join("")):("<div style='color:var(--excellent)'>"+(H.lang==="ar"?"لا شبكات مفتوحة غير مقصودة":"No unintended open networks")+"</div>");return H.card(H.lang==="ar"?"تنبيه الشبكات المفتوحة":"Open Network Warning",body,op.length+"","shield");}},
{key:"threat_summary",ar:"ملخص المخاطر",en:"Threat Summary",cat:"Security & Threats",fn:function(d,H){var w=d.wifi||[],dv=(H.mergeDevices(d)||[]);var op=w.filter(function(x){var e=String(x.encryption||"").toLowerCase();return !e||/none|open/.test(e);}).length;var rnd=0;dv.forEach(function(x){var h=String(x.mac||"").replace(/[^0-9a-fA-F]/g,"");if(h.length>=2&&(parseInt(h.slice(0,2),16)&2))rnd++;});var items=[[H.lang==="ar"?"شبكات مفتوحة":"Open nets",op,op?"var(--mid)":"var(--excellent)"],[H.lang==="ar"?"أجهزة":"Devices",dv.length,"var(--primary)"],[H.lang==="ar"?"عناوين خاصة":"Private MACs",rnd,"var(--accent)"]];var r="<div class='grid two'>"+items.map(function(it){return "<div class='traffic-box'><span>"+it[0]+"</span><b style='color:"+it[2]+"'>"+it[1]+"</b></div>";}).join("")+"</div>";return H.card(H.lang==="ar"?"ملخص المخاطر":"Threat Summary",r,null,"shield");}},
// ---------- Traffic & Bandwidth ----------
{key:"live_throughput",ar:"التدفق الحي",en:"Live Throughput",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{},rx=H.num(t.rx_bps)||0,tx=H.num(t.tx_bps)||0;var body="<div class='grid two'><div class='traffic-box'><span>RX</span><b class='latin' style='color:var(--accent)'>"+H.bps(rx)+"</b></div><div class='traffic-box'><span>TX</span><b class='latin' style='color:var(--primary)'>"+H.bps(tx)+"</b></div></div><div style='margin-top:10px'>"+H.bar(rx+tx?rx/(rx+tx)*100:50,100,"var(--accent)")+"</div>";return H.card(H.lang==="ar"?"التدفق الحي":"Live Throughput",body,null,"net");}},
{key:"iface_data_rank",ar:"ترتيب المنافذ بالبيانات",en:"Interface Data Ranking",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=d.interfaces||[];if(!ifs.length)return H.card(H.lang==="ar"?"المنافذ":"Interfaces","<div class='empty'>—</div>",null,"net");var a=ifs.map(function(i){return {n:i.name,b:(H.num(i.rx_bytes)||0)+(H.num(i.tx_bytes)||0)};}).sort(function(x,y){return y.b-x.b;});var mx=a[0].b||1;var r=a.slice(0,7).map(function(i){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(i.n)+"</span><span class='latin'>"+H.bytes(i.b)+"</span></div>"+H.bar(i.b,mx,"var(--primary)")+"</div>";}).join("");return H.card(H.lang==="ar"?"ترتيب المنافذ بالبيانات":"Interface Data Ranking",r,ifs.length+"","net");}},
{key:"error_drop_watch",ar:"مراقب الأخطاء والفقد",en:"Errors & Drops",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=d.interfaces||[];if(!ifs.length)return H.card(H.lang==="ar"?"الأخطاء":"Errors","<div class='empty'>—</div>",null,"net");var bad=ifs.map(function(i){return {n:i.name,e:(H.num(i.rx_errors)||0)+(H.num(i.tx_errors)||0),dr:(H.num(i.rx_dropped)||0)+(H.num(i.tx_dropped)||0)};}).filter(function(i){return i.e||i.dr;}).sort(function(a,b){return (b.e+b.dr)-(a.e+a.dr);});var body=bad.length?bad.map(function(i){return "<div class='kv'><div><span class='latin'>"+H.esc(i.n)+"</span><b class='latin' style='color:var(--weak)'>"+i.e+" err · "+i.dr+" drop</b></div></div>";}).join(""):"<div style='color:var(--excellent)'>"+(H.lang==="ar"?"لا أخطاء ولا فقد":"No errors or drops")+"</div>";return H.card(H.lang==="ar"?"مراقب الأخطاء والفقد":"Errors & Drops",body,bad.length+"","shield");}},
{key:"total_data",ar:"إجمالي البيانات",en:"Total Data",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{},rx=H.num(t.rx_bytes)||0,tx=H.num(t.tx_bytes)||0;var body="<div class='grid two'><div class='traffic-box'><span>"+(H.lang==="ar"?"وارد":"Download")+"</span><b class='latin'>"+H.bytes(rx)+"</b></div><div class='traffic-box'><span>"+(H.lang==="ar"?"صادر":"Upload")+"</span><b class='latin'>"+H.bytes(tx)+"</b></div></div><p class='muted' style='margin-top:8px'>"+(H.lang==="ar"?"الإجمالي":"Total")+": "+H.bytes(rx+tx)+"</p>";return H.card(H.lang==="ar"?"إجمالي البيانات":"Total Data",body,null,"net");}},
{key:"updown_ratio",ar:"نسبة التنزيل/الرفع",en:"Down/Up Ratio",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{},rx=H.num(t.rx_bytes)||0,tx=H.num(t.tx_bytes)||0,tot=rx+tx;if(!tot)return H.card(H.lang==="ar"?"نسبة التنزيل/الرفع":"Down/Up","<div class='empty'>—</div>",null,"net");var pd=rx/tot*100,pu=tx/tot*100;var bar="<div style='display:flex;height:24px;border-radius:6px;overflow:hidden'><div style='width:"+pd.toFixed(1)+"%;background:var(--accent)'></div><div style='width:"+pu.toFixed(1)+"%;background:var(--primary)'></div></div><div style='display:flex;justify-content:space-between;margin-top:6px;font-size:12px'><span style='color:var(--accent)'>&darr; "+H.fmt(pd,0)+"%</span><span style='color:var(--primary)'>&uarr; "+H.fmt(pu,0)+"%</span></div>";return H.card(H.lang==="ar"?"نسبة التنزيل/الرفع":"Down/Up Ratio",bar,null,"net");}},
{key:"backhaul_status",ar:"حالة الوصلة العلوية",en:"Backhaul Status",cat:"Traffic & Bandwidth",fn:function(d,H){var b=d.backhaul||{},on=!!b.online,col=on?"var(--excellent)":"var(--mid)";var body="<div class='kv'><div><span>"+(H.lang==="ar"?"الحالة":"Status")+"</span><b style='color:"+col+"'>"+(on?(H.lang==="ar"?"متصل":"Online"):(H.lang==="ar"?"LAN فقط":"LAN only"))+"</b></div><div><span>"+(H.lang==="ar"?"البوابة":"Gateway")+"</span><b class='latin'>"+H.esc(b.gateway||"—")+"</b></div><div><span>"+(H.lang==="ar"?"المنفذ":"Device")+"</span><b class='latin'>"+H.esc(b.device||"—")+"</b></div></div>";return H.card(H.lang==="ar"?"حالة الوصلة العلوية":"Backhaul Status",body,on?"up":"lan","net");}},
// ---------- System & Health ----------
{key:"cpu_gauge",ar:"المعالج",en:"CPU",cat:"System & Health",fn:function(d,H){var c=d.cpu||{},p=H.clamp(H.num(c.percent)||0,0,100);return H.card(H.lang==="ar"?"المعالج":"CPU",H.gauge("CPU",p+"%","load",(c.cores||"?")+" cores",p,H.quality("system",p).color,"cpu"),null,"cpu");}},
{key:"ram_gauge",ar:"الذاكرة",en:"RAM",cat:"System & Health",fn:function(d,H){var m=d.mem||{},tot=H.num(m.total)||0,av=H.num(m.available)||0,used=tot-av,p=tot?H.clamp(used/tot*100,0,100):0;return H.card(H.lang==="ar"?"الذاكرة":"RAM",H.gauge("RAM",H.fmt(p,0)+"%",H.bytes(used),H.bytes(av)+" free",p,H.quality("system",p).color,"ram"),null,"cpu");}},
{key:"storage_gauge",ar:"التخزين",en:"Storage",cat:"System & Health",fn:function(d,H){var s=d.storage||{},tot=H.num(s.total)||0,us=H.num(s.used)||0,p=tot?H.clamp(us/tot*100,0,100):0;return H.card(H.lang==="ar"?"التخزين":"Storage",H.gauge("Storage",H.fmt(p,0)+"%",H.bytes(us),H.bytes(H.num(s.available)||0)+" free",p,H.quality("system",p).color,"storage"),null,"cpu");}},
{key:"thermal_zones",ar:"الحارس الحراري",en:"Thermal Guardian",cat:"System & Health",fn:function(d,H){var t=H.num(d.temperature_c);if(!H.finite(t))return H.card(H.lang==="ar"?"الحرارة":"Thermal","<div style='color:var(--muted)'>"+(H.lang==="ar"?"المستشعر غير متوفر":"Sensor unavailable")+"</div>",null,"cpu");var z=t<55?[H.lang==="ar"?"طبيعية":"Normal","var(--excellent)"]:t<70?[H.lang==="ar"?"دافئة":"Warm","var(--good)"]:t<82?[H.lang==="ar"?"مرتفعة":"High","var(--mid)"]:[H.lang==="ar"?"حرجة":"Critical","var(--weak)"];var body="<div style='text-align:center;font-size:34px;font-weight:800;color:"+z[1]+"'>"+H.fmt(t,1)+"&deg;</div><div style='text-align:center;color:"+z[1]+";margin-bottom:8px'>"+z[0]+"</div>"+H.bar(H.clamp(t,0,100),100,z[1]);return H.card(H.lang==="ar"?"الحارس الحراري":"Thermal Guardian",body,z[0],"cpu");}},
{key:"load_avg",ar:"متوسط الحمل",en:"Load Average",cat:"System & Health",fn:function(d,H){var l=d.load||[];if(!l.length)return H.card(H.lang==="ar"?"متوسط الحمل":"Load","<div class='empty'>—</div>",null,"cpu");var cores=(d.cpu&&d.cpu.cores)||1,labs=["1m","5m","15m"];var r=l.slice(0,3).map(function(v,i){var la=(H.num(v)||0)/65536,p=H.clamp(la/cores*100,0,100),col=p<60?"var(--excellent)":p<90?"var(--mid)":"var(--weak)";return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+labs[i]+"</span><span class='latin'>"+H.fmt(la,2)+"</span></div>"+H.bar(p,100,col)+"</div>";}).join("");return H.card(H.lang==="ar"?"متوسط الحمل":"Load Average",r,cores+" cores","cpu");}},
{key:"uptime_card",ar:"مدة التشغيل",en:"Uptime",cat:"System & Health",fn:function(d,H){var u=H.num(d.uptime)||0,dd=Math.floor(u/86400),h=Math.floor(u%86400/3600),m=Math.floor(u%3600/60);var big=dd?dd+"d "+h+"h":h+"h "+m+"m";return H.card(H.lang==="ar"?"مدة التشغيل":"Uptime","<div style='text-align:center;font-size:30px;font-weight:800;color:var(--accent)'>"+big+"</div><div style='text-align:center;color:var(--muted);font-size:12px'>"+H.esc(d.hostname||"")+" · "+H.esc(d.os||"")+"</div>",null,"bolt");}},
{key:"health_breakdown",ar:"تفصيل درجة الصحة",en:"Health Breakdown",cat:"System & Health",fn:function(d,H){var h=d.health||{},sc=H.num(h.score);if(!H.finite(sc))return H.card(H.lang==="ar"?"درجة الصحة":"Health","<div class='empty'>—</div>",null,"shield");var col=sc>=85?"var(--excellent)":sc>=70?"var(--good)":sc>=50?"var(--mid)":"var(--weak)";var rs=(h.reasons||[]).map(function(r){var rc=r.level==="ok"?"var(--excellent)":r.level==="mid"?"var(--mid)":"var(--weak)";return "<div style='font-size:12px;padding:5px 8px;border-radius:6px;background:rgba(148,185,255,.08);border-inline-start:3px solid "+rc+";margin:4px 0'>"+H.esc(H.lang==="ar"?(r.ar||r.en):(r.en||r.ar))+"</div>";}).join("");return H.card(H.lang==="ar"?"تفصيل درجة الصحة":"Health Breakdown","<div style='text-align:center;font-size:40px;font-weight:800;color:"+col+"'>"+sc+"</div>"+rs,h.grade||"","shield");}},
// ---------- Latency & Link Quality ----------
{key:"gateway_latency",ar:"زمن استجابة البوابة",en:"Gateway Latency",cat:"Latency & Link Quality",fn:function(d,H){var l=H.num(d.latency_ms);if(!H.finite(l))return H.card(H.lang==="ar"?"زمن الاستجابة":"Latency","<div style='color:var(--muted)'>"+(H.lang==="ar"?"غير متوفر":"N/A")+"</div>",null,"net");var col=l<10?"var(--excellent)":l<30?"var(--good)":l<60?"var(--mid)":"var(--weak)";return H.card(H.lang==="ar"?"زمن استجابة البوابة":"Gateway Latency","<div style='text-align:center;font-size:36px;font-weight:800;color:"+col+"'>"+H.fmt(l,1)+" ms</div>"+H.bar(H.clamp(100-l,0,100),100,col),null,"net");}},
{key:"link_eff_rank",ar:"ترتيب كفاءة الوصلة",en:"Link Efficiency Ranking",cat:"Latency & Link Quality",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push({b:w.band,s:s});});});var wt=st.map(function(x){return {n:x.s.ip||x.s.mac,e:H.linkEfficiency(x.b,H.num(x.s.tx_rate))};}).filter(function(x){return x.e!==null;});if(!wt.length)return H.card(H.lang==="ar"?"كفاءة الوصلة":"Link Efficiency","<div class='empty'>—</div>",null,"net");wt.sort(function(a,b){return b.e-a.e;});var r=wt.slice(0,8).map(function(x){var col=x.e>=70?"var(--excellent)":x.e>=40?"var(--good)":"var(--mid)";return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(x.n)+"</span><span style='color:"+col+"'>"+x.e+"%</span></div>"+H.bar(x.e,100,col)+"</div>";}).join("");return H.card(H.lang==="ar"?"ترتيب كفاءة الوصلة":"Link Efficiency Ranking",r,wt.length+"","net");}},
{key:"snr_board",ar:"لوحة جودة SNR",en:"SNR Quality Board",cat:"Latency & Link Quality",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});var wt=st.filter(function(s){return H.finite(H.num(s.snr));});if(!wt.length)return H.card(H.lang==="ar"?"جودة SNR":"SNR Board","<div class='empty'>—</div>",null,"signal");wt.sort(function(a,b){return H.num(b.snr)-H.num(a.snr);});var r=wt.slice(0,8).map(function(s){var v=H.num(s.snr),col=v>=40?"var(--excellent)":v>=25?"var(--good)":v>=15?"var(--mid)":"var(--weak)";return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(s.ip||s.mac)+"</span><span style='color:"+col+"'>"+v+" dB</span></div>"+H.bar(H.clamp(v/50*100,0,100),100,col)+"</div>";}).join("");return H.card(H.lang==="ar"?"لوحة جودة SNR":"SNR Quality Board",r,wt.length+"","signal");}},
{key:"expected_actual",ar:"المتوقع مقابل الفعلي",en:"Expected vs Actual",cat:"Latency & Link Quality",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});var wt=st.filter(function(s){return H.finite(H.num(s.expected_mbps))&&H.finite(H.num(s.tx_rate));});if(!wt.length)return H.card(H.lang==="ar"?"المتوقع/الفعلي":"Expected/Actual","<div class='empty'>—</div>",null,"net");var r=wt.slice(0,7).map(function(s){var e=H.num(s.expected_mbps),a=H.num(s.tx_rate),p=e?H.clamp(a/e*100,0,100):0,col=p>=80?"var(--excellent)":p>=50?"var(--good)":"var(--mid)";return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(s.ip||s.mac)+"</span><span class='latin'>"+H.fmt(a,0)+"/"+H.fmt(e,0)+"</span></div>"+H.bar(p,100,col)+"</div>";}).join("");return H.card(H.lang==="ar"?"المتوقع مقابل الفعلي":"Expected vs Actual",r,wt.length+"","net");}},
{key:"weakest_link",ar:"أضعف وصلة",en:"Weakest Link",cat:"Latency & Link Quality",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push({b:w.band,s:s});});});if(!st.length)return H.card(H.lang==="ar"?"أضعف وصلة":"Weakest Link","<div class='empty'>—</div>",null,"signal");st.sort(function(a,b){return (H.num(a.s.signal_dbm)||0)-(H.num(b.s.signal_dbm)||0);});var x=st[0],v=H.num(x.s.signal_dbm),q=H.quality("rssi",v),dist=H.distanceM(v);return H.card(H.lang==="ar"?"أضعف وصلة":"Weakest Link","<div style='text-align:center;font-size:26px;font-weight:800;color:"+q.color+"'>"+(H.finite(v)?v+" dBm":"?")+"</div><div style='text-align:center' class='latin'>"+H.esc(x.s.ip||x.s.mac)+"</div><div style='text-align:center;color:var(--muted);font-size:12px'>"+H.esc(x.b||"")+(dist!==null?" · ≈"+(dist<10?dist.toFixed(1):Math.round(dist))+"m":"")+"</div>",q.text,"signal");}},
// ---------- Topology & Discovery ----------
{key:"port_map",ar:"خريطة المنافذ",en:"Port Map",cat:"Topology & Discovery",fn:function(d,H){var ifs=d.interfaces||[];if(!ifs.length)return H.card(H.lang==="ar"?"خريطة المنافذ":"Port Map","<div class='empty'>—</div>",null,"net");var r="<div style='display:flex;flex-wrap:wrap;gap:8px'>"+ifs.map(function(i){var on=i.connected,col=on?"var(--excellent)":"var(--muted)";return "<div style='flex:1;min-width:96px;padding:8px;border:1px solid "+col+";border-radius:8px;text-align:center'><div class='latin' style='font-weight:700'>"+H.esc(i.name)+"</div><div style='font-size:11px;color:"+col+"'>"+(on?(i.speed_mbps?i.speed_mbps+"M":"up"):"down")+"</div></div>";}).join("")+"</div>";return H.card(H.lang==="ar"?"خريطة المنافذ":"Port Map",r,ifs.filter(function(i){return i.connected;}).length+"/"+ifs.length,"net");}},
{key:"dev_per_port",ar:"أجهزة لكل منفذ",en:"Devices per Port",cat:"Topology & Discovery",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"أجهزة لكل منفذ":"Devices per Port","<div class='empty'>—</div>",null,"device");var c={};dv.forEach(function(x){var k=x.iface||"?";c[k]=(c[k]||0)+1;});var ks=Object.keys(c).sort(function(a,b){return c[b]-c[a];}),mx=c[ks[0]]||1;var r=ks.map(function(k){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(k)+"</span><span>"+c[k]+"</span></div>"+H.bar(c[k],mx,"var(--primary)")+"</div>";}).join("");return H.card(H.lang==="ar"?"أجهزة لكل منفذ":"Devices per Port",r,dv.length+"","device");}},
{key:"lan_wifi_split",ar:"توزيع سلكي/لاسلكي",en:"LAN vs WiFi",cat:"Topology & Discovery",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"سلكي/لاسلكي":"LAN/WiFi","<div class='empty'>—</div>",null,"device");var wf=dv.filter(function(x){return x.type==="WiFi";}).length,ln=dv.length-wf,tot=dv.length,pw=wf/tot*100,pl=ln/tot*100;var bar="<div style='display:flex;height:24px;border-radius:6px;overflow:hidden'><div style='width:"+pw.toFixed(1)+"%;background:var(--accent)'></div><div style='width:"+pl.toFixed(1)+"%;background:var(--primary)'></div></div><div style='display:flex;justify-content:space-between;margin-top:6px;font-size:12px'><span style='color:var(--accent)'>WiFi "+wf+"</span><span style='color:var(--primary)'>LAN "+ln+"</span></div>";return H.card(H.lang==="ar"?"توزيع سلكي/لاسلكي":"LAN vs WiFi",bar,tot+"","device");}},
{key:"bridge_members",ar:"أعضاء الجسر",en:"Bridge Members",cat:"Topology & Discovery",fn:function(d,H){var ifs=(d.interfaces||[]).filter(function(i){return /^(lan|wan|phy)/.test(i.name||"");});if(!ifs.length)return H.card(H.lang==="ar"?"أعضاء الجسر":"Bridge Members","<div class='empty'>—</div>",null,"net");var r=ifs.map(function(i){var col=i.connected?"var(--excellent)":"var(--muted)";return "<div class='kv'><div><span class='latin'>"+H.esc(i.name)+"</span><b style='color:"+col+"'>"+(i.connected?"up":"down")+"</b></div></div>";}).join("");return H.card(H.lang==="ar"?"أعضاء الجسر":"Bridge Members",r,ifs.length+"","net");}},
{key:"gateway_path",ar:"مسار البوابة",en:"Gateway Path",cat:"Topology & Discovery",fn:function(d,H){var b=d.backhaul||{},steps=[[H.esc(d.hostname||"AP"),"var(--accent)"],[H.esc(b.device||"br-lan"),"var(--primary)"],[H.esc(b.gateway||(H.lang==="ar"?"البوابة":"gateway")),b.online?"var(--excellent)":"var(--mid)"]];var r="<div style='display:flex;align-items:center;gap:6px;flex-wrap:wrap'>"+steps.map(function(s,i){return "<span style='padding:6px 10px;border-radius:8px;background:rgba(148,185,255,.1);color:"+s[1]+";font-weight:700' class='latin'>"+s[0]+"</span>"+(i<steps.length-1?"<span style='color:var(--muted)'>&rarr;</span>":"");}).join("")+"</div>";return H.card(H.lang==="ar"?"مسار البوابة":"Gateway Path",r,b.online?"online":"lan","net");}},
// ---------- Automation & UX ----------
{key:"net_score_tile",ar:"النتيجة الكلية للشبكة",en:"Network Score",cat:"Automation & UX",fn:function(d,H){var h=d.health||{},sc=H.num(h.score);if(!H.finite(sc))return H.card(H.lang==="ar"?"النتيجة":"Score","<div class='empty'>—</div>",null,"shield");var col=sc>=85?"var(--excellent)":sc>=70?"var(--good)":sc>=50?"var(--mid)":"var(--weak)",C=2*Math.PI*50,off=C*(1-sc/100);var svg="<svg width='150' height='150' viewBox='0 0 150 150' style='display:block;margin:0 auto'><circle cx='75' cy='75' r='50' fill='none' stroke='var(--muted)' stroke-opacity='.2' stroke-width='14'/><circle cx='75' cy='75' r='50' fill='none' stroke='"+col+"' stroke-width='14' stroke-linecap='round' stroke-dasharray='"+C.toFixed(1)+"' stroke-dashoffset='"+off.toFixed(1)+"' transform='rotate(-90 75 75)'/><text x='75' y='78' text-anchor='middle' font-size='34' font-weight='800' fill='"+col+"'>"+sc+"</text><text x='75' y='98' text-anchor='middle' font-size='11' fill='var(--muted)'>/100</text></svg>";return H.card(H.lang==="ar"?"النتيجة الكلية للشبكة":"Network Score",svg,h.grade||"","shield");}},
{key:"recommendations",ar:"توصيات ذكية",en:"Smart Recommendations",cat:"Automation & UX",fn:function(d,H){var rs=(d.health&&d.health.reasons)||[];if(!rs.length)return H.card(H.lang==="ar"?"توصيات":"Recommendations","<div style='color:var(--excellent)'>"+(H.lang==="ar"?"لا توصيات — كل شيء سليم":"No recommendations — all good")+"</div>",null,"bolt");var body=rs.map(function(r){var rc=r.level==="ok"?"var(--excellent)":r.level==="mid"?"var(--mid)":"var(--weak)";return "<div style='font-size:13px;padding:7px 10px;border-radius:8px;background:rgba(148,185,255,.08);border-inline-start:3px solid "+rc+";margin:5px 0'>"+H.esc(H.lang==="ar"?(r.ar||r.en):(r.en||r.ar))+"</div>";}).join("");return H.card(H.lang==="ar"?"توصيات ذكية":"Smart Recommendations",body,rs.length+"","bolt");}},
{key:"kpi_strip",ar:"شريط المؤشرات",en:"KPI Strip",cat:"Automation & UX",fn:function(d,H){var w=d.wifi||[],dv=(H.mergeDevices(d)||[]),air=H.num((d.health||{}).busy_pct),lat=H.num(d.latency_ms),tmp=H.num(d.temperature_c);var items=[[H.lang==="ar"?"أجهزة":"Devices",dv.length,"var(--primary)"],[H.lang==="ar"?"شبكات":"SSIDs",w.length,"var(--accent)"],[H.lang==="ar"?"هواء":"Air",H.finite(air)?air+"%":"—","var(--mid)"],[H.lang==="ar"?"استجابة":"Lat",H.finite(lat)?H.fmt(lat,0)+"ms":"—","var(--good)"],[H.lang==="ar"?"حرارة":"Temp",H.finite(tmp)?H.fmt(tmp,0)+"°":"—","var(--weak)"]];var r="<div style='display:flex;flex-wrap:wrap;gap:8px'>"+items.map(function(it){return "<div style='flex:1;min-width:80px;text-align:center;padding:8px;border-radius:8px;background:rgba(148,185,255,.06)'><div style='font-size:22px;font-weight:800;color:"+it[2]+"'>"+it[1]+"</div><div style='font-size:11px;color:var(--muted)'>"+it[0]+"</div></div>";}).join("")+"</div>";return H.card(H.lang==="ar"?"شريط المؤشرات":"KPI Strip",r,null,"bolt");}},
{key:"capacity_headroom",ar:"سعة الاحتياطي",en:"Capacity Headroom",cat:"Automation & UX",fn:function(d,H){var air=H.num((d.health||{}).busy_pct),cpu=H.num((d.cpu||{}).percent),m=d.mem||{},mp=(H.num(m.total)&&H.num(m.available))?(1-H.num(m.available)/H.num(m.total))*100:null,mn=100;[air,cpu,mp].forEach(function(v){if(H.finite(v))mn=Math.min(mn,100-v);});var col=mn>=50?"var(--excellent)":mn>=25?"var(--good)":mn>=10?"var(--mid)":"var(--weak)";return H.card(H.lang==="ar"?"سعة الاحتياطي":"Capacity Headroom","<div style='text-align:center;font-size:36px;font-weight:800;color:"+col+"'>"+H.fmt(mn,0)+"%</div><div style='text-align:center;color:var(--muted);font-size:12px;margin-bottom:8px'>"+(H.lang==="ar"?"سعة متبقية (أقل مورد)":"headroom (tightest resource)")+"</div>"+H.bar(mn,100,col),null,"cpu");}},
{key:"air_quality_index",ar:"مؤشر جودة الهواء اللاسلكي",en:"Air Quality Index",cat:"Automation & UX",fn:function(d,H){var w=d.wifi||[],s=0,n=0;w.forEach(function(x){var b=H.num((x.survey||{}).busy_pct);if(H.finite(b)){s+=b;n++;}});if(!n)return H.card(H.lang==="ar"?"جودة الهواء":"Air Quality","<div class='empty'>—</div>",null,"signal");var aqi=H.clamp(100-s/n,0,100),col=aqi>=70?"var(--excellent)":aqi>=45?"var(--good)":aqi>=25?"var(--mid)":"var(--weak)",t=aqi>=70?(H.lang==="ar"?"ممتاز":"Excellent"):aqi>=45?(H.lang==="ar"?"جيد":"Good"):aqi>=25?(H.lang==="ar"?"متوسط":"Fair"):(H.lang==="ar"?"مزدحم":"Congested");return H.card(H.lang==="ar"?"مؤشر جودة الهواء اللاسلكي":"Air Quality Index","<div style='text-align:center;font-size:40px;font-weight:800;color:"+col+"'>"+H.fmt(aqi,0)+"</div><div style='text-align:center;color:"+col+";margin-bottom:8px'>"+t+"</div>"+H.bar(aqi,100,col),t,"signal");}},
{key:"quick_summary",ar:"الملخص السريع",en:"Quick Summary",cat:"Automation & UX",fn:function(d,H){var dv=(H.mergeDevices(d)||[]),w=d.wifi||[],parts=[];parts.push((H.lang==="ar"?"أجهزة: ":"Devices: ")+dv.length);parts.push((H.lang==="ar"?"شبكات: ":"Networks: ")+w.length);if(H.finite(H.num((d.health||{}).score)))parts.push((H.lang==="ar"?"الصحة: ":"Health: ")+H.num(d.health.score));if(H.finite(H.num(d.temperature_c)))parts.push((H.lang==="ar"?"الحرارة: ":"Temp: ")+H.fmt(H.num(d.temperature_c),0)+"°");var body="<div style='font-size:14px;line-height:2'>"+parts.map(function(p){return "<span style='display:inline-block;padding:4px 10px;margin:3px;border-radius:8px;background:rgba(148,185,255,.08)'>"+H.esc(p)+"</span>";}).join("")+"</div>";return H.card(H.lang==="ar"?"الملخص السريع":"Quick Summary",body,H.esc(d.hostname||""),"bolt");}},
   {key:"rf_dfs_channel_board",ar:"لوحة القنوات و DFS",en:"DFS & Channel Board",cat:"RF & Airtime",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[];if(!w.length)return H.card(A?'لوحة القنوات و DFS':'DFS & Channel Board','<div style="color:var(--muted);text-align:center;padding:14px">'+(A?'لا توجد بيانات واي فاي':'No WiFi data')+'</div>','--','shield');var h='',dn=0;for(var i=0;i<w.length;i++){var r=w[i]||{},cn=+(r.channel)||0,b=H.esc(String(r.band||'?')),m=String(r.htmode||'').match(/(\d+)/),wd=m?m[1]:'20',is5=String(r.band||'').indexOf('5')===0,dfs=is5&&cn>=52&&cn<=144;if(dfs)dn++;var c=dfs?'var(--mid)':'var(--excellent)';h+='<div style="display:flex;align-items:center;gap:6px;padding:7px 0 2px;flex-wrap:wrap"><b style="color:var(--primary);min-width:42px">'+b+'</b><span style="background:var(--border);border-radius:6px;padding:2px 8px;font-weight:600">CH '+(cn||'?')+'</span><span style="background:var(--border);border-radius:6px;padding:2px 8px">'+H.esc(wd)+'MHz</span><span style="margin-'+(A?'right':'left')+':auto;color:'+c+';font-weight:700">&#9679; '+(dfs?'DFS':(A?'آمن':'clear'))+'</span></div><div style="font-size:11px;color:var(--muted);padding:0 0 6px;border-bottom:1px solid var(--border)">'+H.esc(String(r.ssid||''))+' &middot; '+H.esc(String(r.htmode||''))+' &middot; '+(A?'إشارة ':'sig ')+H.num(r.signal_dbm)+' dBm</div>';}var chip=dn?(dn+' DFS'):(A?'بدون DFS':'non-DFS');return H.card(A?'لوحة القنوات و DFS':'DFS & Channel Board',h,chip,'shield');}},
   {key:"rf_airtime_efficiency",ar:"كفاءة زمن البث",en:"Airtime Efficiency",cat:"RF & Airtime",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[];if(!w.length)return H.card(A?'كفاءة زمن البث':'Airtime Efficiency','<div style="color:var(--muted);text-align:center;padding:14px">'+(A?'لا توجد بيانات':'No data')+'</div>','--','signal');var h='',worst=0;for(var i=0;i<w.length;i++){var r=w[i]||{},s=r.survey||{},busy=H.clamp(+(s.busy_pct)||0,0,100),cl=+(r.clients)||0,ratio=busy/Math.max(cl,1),c=ratio<=8?'var(--excellent)':ratio<=18?'var(--good)':ratio<=35?'var(--mid)':'var(--weak)',lb=ratio<=8?(A?'ممتاز':'excellent'):ratio<=18?(A?'جيد':'good'):ratio<=35?(A?'متوسط':'fair'):(cl===0&&busy>20?(A?'تشويش':'interference'):(A?'مزدحم':'congested'));if(ratio>worst)worst=ratio;h+='<div style="padding:6px 0"><div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:3px"><b>'+H.esc(String(r.band||'?'))+' &middot; '+cl+(A?' عميل':' clients')+'</b><span style="color:'+c+';font-weight:700">'+lb+'</span></div>'+H.bar(busy,100,c)+'<div style="display:flex;justify-content:space-between;font-size:11px;color:var(--muted);margin-top:3px"><span>'+(A?'انشغال ':'busy ')+H.fmt(busy,0)+'%</span><span>'+(A?'لكل عميل ':'per client ')+H.fmt(ratio,1)+'%</span></div></div>';}var chip=worst<=18?(A?'صحي':'healthy'):(A?'مراقبة':'watch');return H.card(A?'كفاءة زمن البث':'Airtime Efficiency',h,chip,'signal');}},
   {key:"roaming_candidates",ar:"مرشحو التجوال",en:"Roaming Candidates",cat:"Clients & Devices",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[],has5=w.some(function(r){return r&&r.band==='5G'});var dev={};((d&&d.devices)||[]).forEach(function(x){if(x&&x.mac)dev[String(x.mac).toUpperCase()]=x.host||x.ip||''});var L=[];w.forEach(function(r){if(!r||!r.stations)return;r.stations.forEach(function(s){if(!s)return;var sg=H.num(s.signal_dbm);if(!H.finite(sg))return;if(sg<=-67)L.push({m:String(s.mac||''),b:r.band||'',sg:sg})})});L.sort(function(a,b){return a.sg-b.sg});var n=L.length;L=L.slice(0,5);var h;if(!n){h='<div style="text-align:center;padding:12px;color:var(--good)">'+(A?'لا عملاء بإشارة ضعيفة — التغطية جيدة':'No weak clients — coverage healthy')+'</div>'}else{h=L.map(function(c){var nm=dev[c.m.toUpperCase()]||c.m.slice(-8);var col=c.sg<=-75?'var(--weak)':'var(--mid)';var tip=(c.b==='2.4G'&&has5)?(A?'مرشح للتوجيه إلى 5G':'Candidate: steer to 5G'):(A?'اقترب من نقطة الوصول':'Move closer to AP');return '<div style="margin:6px 0"><div style="display:flex;justify-content:space-between;font-size:11px"><b>'+H.esc(nm)+'</b><span style="color:'+col+'">'+H.fmt(c.sg,0)+' dBm · '+H.esc(c.b)+'</span></div>'+H.bar(H.clamp(c.sg+95,0,55),55,col)+'<div style="font-size:10px;color:var(--accent)">'+tip+'</div></div>'}).join('')}
return H.card(A?'مرشحو التجوال':'Roaming Candidates',h,String(n)+(A?' ضعيف':' weak'),'signal')}},
   {key:"distance_leaderboard",ar:"أبعد العملاء",en:"Distance Leaderboard",cat:"Clients & Devices",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[];var dev={};((d&&d.devices)||[]).forEach(function(x){if(x&&x.mac)dev[String(x.mac).toUpperCase()]=x.host||x.ip||''});var L=[];w.forEach(function(r){if(!r||!r.stations)return;r.stations.forEach(function(s){if(!s)return;var sg=H.num(s.signal_dbm);if(!H.finite(sg))return;var dm=H.num(H.distanceM(sg));if(!H.finite(dm)||dm<0)return;L.push({m:String(s.mac||''),b:r.band||'',dm:dm})})});L.sort(function(a,b){return b.dm-a.dm});var mx=L.length?L[0].dm:1,h;if(!L.length){h='<div style="text-align:center;padding:12px;color:var(--muted)">'+(A?'لا عملاء متصلين':'No connected clients')+'</div>'}else{h=L.slice(0,6).map(function(c,i){var nm=dev[c.m.toUpperCase()]||c.m.slice(-8);var col=c.dm>12?'var(--weak)':c.dm>7?'var(--mid)':c.dm>3?'var(--good)':'var(--excellent)';return '<div style="margin:6px 0"><div style="display:flex;justify-content:space-between;font-size:11px"><span>#'+(i+1)+' <b>'+H.esc(nm)+'</b> <span style="color:var(--muted)">'+H.esc(c.b)+'</span></span><b style="color:'+col+'">~'+H.fmt(c.dm,1)+(A?' م':' m')+'</b></div>'+H.bar(c.dm,mx||1,col)+'</div>'}).join('')+'<div style="font-size:10px;color:var(--muted);margin-top:4px">'+(A?'تقدير من قوة الإشارة':'Estimated from RSSI')+'</div>'}
return H.card(A?'أبعد العملاء':'Distance Leaderboard',h,String(L.length)+(A?' جهاز':' clients'),'device')}},
   {key:"client_bw_share",ar:"حصة العملاء من النطاق",en:"Client Bandwidth Share",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',t=a?'حصة العملاء':'Client Bandwidth Share',st=[],tot=0;(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){var e=H.num(s.expected_mbps);if(H.finite(e)&&e>0){st.push({k:s.ip||s.mac||'?',e:e});tot+=e}})});if(!st.length)return H.card(t,'<div class="empty">'+(a?'لا عملاء':'No data')+'</div>',null,'device');st.sort(function(x,y){return y.e-x.e});var top=st.slice(0,5),r=tot;top.forEach(function(x){r-=x.e});if(r>0)top.push({k:a?'أخرى':'Other',e:r});var cs='primary,accent,excellent,good,mid,muted'.split(','),acc=0,seg='',leg='';top.forEach(function(x,i){var f=x.e/tot,c='var(--'+cs[i%6]+')';seg+='<circle cx="60" cy="60" r="46" fill="none" stroke="'+c+'" stroke-width="14" stroke-dasharray="'+(f*289).toFixed(1)+' 289" stroke-dashoffset="'+(-acc*289).toFixed(1)+'" transform="rotate(-90 60 60)"/>';acc+=f;leg+='<div style="display:flex;justify-content:space-between;font-size:11px;margin:3px 0"><span class="latin" style="color:'+c+'">'+H.esc(x.k)+'</span><span class="latin">'+H.fmt(f*100,0)+'%·'+H.fmt(x.e,0)+'M</span></div>'});var svg='<svg width="120" height="120" viewBox="0 0 120 120" style="display:block;margin:0 auto">'+seg+'<text x="60" y="66" text-anchor="middle" font-size="17" fill="var(--text)">'+st.length+' '+(a?'عميل':'cl')+'</text></svg>';return H.card(t,svg+'<div style="margin-top:8px">'+leg+'</div>',H.fmt(tot,0)+'M','device');}},
   {key:"bridge_pps_tile",ar:"معدل الجسر الكلي",en:"Bridge Throughput",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',t=a?'معدل الجسر الكلي':'Bridge Throughput',tr=d.traffic||{},rx=H.num(tr.rx_bps)||0,tx=H.num(tr.tx_bps)||0,tot=rx+tx;if(!tot&&!(H.num(tr.rx_bytes)||0))return H.card(t,'<div class="empty">'+(a?'لا بيانات':'No data')+'</div>',null,'net');var pps=tot/6000,pl=pps>=1000?H.fmt(pps/1000,1)+'k':H.fmt(pps,0),cap=0;(d.interfaces||[]).forEach(function(i){i=i||{};var s=H.num(i.speed_mbps);if(i.connected&&H.finite(s)&&s>cap)cap=s});var use=cap?H.clamp(tot/(cap*1e6)*100,0,100):0,col=!cap?'var(--primary)':use<40?'var(--excellent)':use<70?'var(--good)':use<90?'var(--mid)':'var(--weak)';var body='<div style="text-align:center"><div class="latin" style="font-size:30px;font-weight:800;color:'+col+'">'+H.bps(tot)+'</div><div style="font-size:11px;color:var(--muted)">≈ '+pl+' pps @750B</div></div><div class="grid two"><div class="traffic-box"><span>↓ RX</span><b class="latin" style="color:var(--accent)">'+H.bps(rx)+'</b></div><div class="traffic-box"><span>↑ TX</span><b class="latin" style="color:var(--primary)">'+H.bps(tx)+'</b></div></div>'+(cap?'<div style="margin-top:10px"><div style="display:flex;justify-content:space-between;font-size:11px;color:var(--muted)"><span>'+(a?'استخدام الوصلة':'Link use')+'</span><span class="latin">'+H.fmt(use,1)+'%/'+cap+'M</span></div>'+H.bar(use,100,col)+'</div>':'');return H.card(t,body,null,'bolt');}},
   {key:"setup_checklist",ar:"قائمة فحص الإعداد",en:"Setup Checklist",cat:"Automation & UX",fn:function(d,H){var A=H.lang==='ar',t=A?'قائمة فحص الإعداد':'Setup Checklist';d=d||{};var hs=H.num((d.health||{}).score),tc=H.num(d.temperature_c),lt=H.num(d.latency_ms),cl=H.num(d.clients),bo=(d.backhaul||{}).online;var L=[[A?'الوصلة الرئيسية متصلة':'Upstream online',bo===true,bo!==true],[A?'يوجد أجهزة متصلة':'Clients connected',cl>0,!H.finite(cl)],[A?'الصحة أعلى من 70':'Health &gt; 70',hs>70,!H.finite(hs)],[A?'الحرارة أقل من 70°C':'Temp &lt; 70°C',tc<70,!H.finite(tc)],[A?'الاستجابة أقل من 20ms':'Latency &lt; 20ms',lt<20,!H.finite(lt)]];var ok=0,tot=0,r='';for(var i=0;i<5;i++){var u=L[i][2],p=L[i][1];if(!u){tot++;if(p)ok++}var c=u?'var(--muted)':p?'var(--excellent)':'var(--weak)';r+='<div style="display:flex;align-items:center;gap:9px;margin:7px 0;font-size:12px"><span style="flex:0 0 20px;height:20px;border-radius:50%;border:1.5px solid '+c+';color:'+c+';font-weight:700;display:flex;align-items:center;justify-content:center">'+(u?'—':p?'✓':'✕')+'</span><span style="flex:1">'+L[i][0]+'</span></div>'}var pc=tot?ok/tot*100:0,col=pc>=100?'var(--excellent)':pc>=60?'var(--good)':pc>=40?'var(--mid)':'var(--weak)';return H.card(t,'<div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px"><span>'+(A?'اكتمال الإعداد':'Setup complete')+'</span><b style="color:'+col+'">'+ok+'/'+tot+'</b></div>'+H.bar(pc,100,col)+'<div style="height:6px"></div>'+r,ok+'/'+tot,'gear')}},
   {key:"uptime_milestones",ar:"إنجازات التشغيل",en:"Uptime Milestones",cat:"Automation & UX",fn:function(d,H){var A=H.lang==='ar',t=A?'إنجازات التشغيل':'Uptime Milestones';var up=H.num((d||{}).uptime);if(!H.finite(up)||up<0)return H.card(t,"<div class='empty'>—</div>",null,'bolt');var M=[[3600,'1h'],[86400,'1d'],[604800,'1w'],[2592e3,'30d'],[864e4,'100d'],[31536e3,'1y']],g=0,nx=null,pl='';for(var i=0;i<6;i++){var a=up>=M[i][0];if(a)g++;else if(!nx)nx=M[i];var c=a?'var(--excellent)':'var(--muted)';pl+='<div style="flex:1;margin:3px;padding:6px 0;text-align:center;border-radius:8px;font-size:14px;border:1px solid '+(a?c:'var(--border)')+';color:'+c+'">'+(a?'★':'☆')+'<div style="font-size:10px">'+M[i][1]+'</div></div>'}var hd='<div style="text-align:center;margin-bottom:8px;font-size:22px;font-weight:700;color:var(--primary)">'+H.esc(H.uptime(up))+'<div style="font-size:11px;font-weight:400;color:var(--muted)">'+(A?'تشغيل متواصل':'uptime streak')+'</div></div>',ft;if(nx){var p=H.clamp(up/nx[0]*100,0,100);ft='<div style="font-size:11px;margin:8px 0 3px;color:var(--muted)">'+(A?'التالي: ':'Next: ')+nx[1]+' · <b style="color:var(--accent)">'+H.fmt(p,0)+'%</b> · '+H.esc(H.uptime(nx[0]-up))+(A?' متبقية':' left')+'</div>'+H.bar(p,100,'var(--accent)')}else ft='<div style="margin-top:8px;text-align:center;color:var(--excellent);font-size:12px">'+(A?'اكتمل الكل!':'All achieved!')+'</div>';return H.card(t,hd+'<div style="display:flex;flex-wrap:wrap">'+pl+'</div>'+ft,g+'/6','bolt')}},
];
  PRO_FEATURES.forEach(function (f) {
    if (f.key === "client_bw_share") {
      f.fn = function (d, H) {
        var a = H.lang === "ar";
        var title = a ? "استهلاك العملاء الفعلي" : "Real Client Traffic";
        var rows = H.stationTrafficRows(d);
        if (!rows.length) {
          return H.card(title, '<div class="empty">' + (a ? "لا توجد عدادات فعلية من الدرايفر" : "No driver counters") + '</div>', null, 'device');
        }
        var live = rows.filter(function (r) { return r.totalRate > 0; });
        if (!live.length) {
          rows.sort(function (x, y) { return y.totalBytes - x.totalBytes; });
          var totals = rows.slice(0, 6).map(function (r) {
            return '<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px;gap:8px"><span class="latin">' + H.esc(r.label) + '</span><span class="latin">' + H.bytes(r.totalBytes) + '</span></div>' +
              '<div class="grid two"><div class="traffic-box"><span>DL</span><b class="latin">' + H.bytes(r.downBytes) + '</b></div><div class="traffic-box"><span>UL</span><b class="latin">' + H.bytes(r.upBytes) + '</b></div></div></div>';
          }).join("");
          return H.card(title, totals || '<div class="empty">' + (a ? "لا توجد حركة حالية" : "No live traffic") + '</div>', a ? "عدادات فعلية" : "real counters", 'device');
        }
        live.sort(function (x, y) { return y.totalRate - x.totalRate; });
        var total = live.reduce(function (s, r) { return s + r.totalRate; }, 0);
        var top = live.slice(0, 5);
        var rest = live.slice(5).reduce(function (s, r) { return s + r.totalRate; }, 0);
        if (rest > 0) top.push({ label:a ? "أخرى" : "Other", totalRate:rest, down:0, up:0 });
        var colors = ["primary","accent","excellent","good","mid","muted"], acc = 0, seg = "", leg = "";
        top.forEach(function (r, i) {
          var frac = total ? r.totalRate / total : 0;
          var c = "var(--" + colors[i % colors.length] + ")";
          seg += '<circle cx="60" cy="60" r="46" fill="none" stroke="' + c + '" stroke-width="14" stroke-dasharray="' + (frac * 289).toFixed(1) + ' 289" stroke-dashoffset="' + (-acc * 289).toFixed(1) + '" transform="rotate(-90 60 60)"/>';
          acc += frac;
          leg += '<div style="margin:5px 0"><div style="display:flex;justify-content:space-between;font-size:11px;gap:8px"><span class="latin" style="color:' + c + '">' + H.esc(r.label) + '</span><b class="latin">' + H.fmt(frac * 100, 0) + '%</b></div>' +
            '<div style="display:flex;justify-content:space-between;font-size:10px;color:var(--muted)"><span>DL ' + H.bps(r.down || 0) + '</span><span>UL ' + H.bps(r.up || 0) + '</span></div></div>';
        });
        var svg = '<svg width="120" height="120" viewBox="0 0 120 120" style="display:block;margin:0 auto">' + seg + '<text x="60" y="62" text-anchor="middle" font-size="14" fill="var(--text)">' + live.length + '</text><text x="60" y="78" text-anchor="middle" font-size="10" fill="var(--muted)">clients</text></svg>';
        return H.card(title, svg + '<div style="margin-top:8px">' + leg + '</div>', H.bps(total), 'device');
      };
    } else if (f.key === "uptime_milestones") {
      f.fn = function (d, H) {
        var A = H.lang === "ar";
        var title = A ? "إنجازات التشغيل" : "Uptime Milestones";
        var up = H.num((d || {}).uptime);
        if (!H.finite(up) || up < 0) return H.card(title, "<div class='empty'>—</div>", null, 'bolt');
        var marks = [[3600,'1h'],[86400,'1d'],[604800,'1w'],[2592e3,'30d'],[864e4,'100d'],[31536e3,'1y']];
        var done = 0, next = null, pills = "";
        marks.forEach(function (m) {
          var ok = up >= m[0];
          if (ok) done++;
          else if (!next) next = m;
          var c = ok ? 'var(--excellent)' : 'var(--muted)';
          pills += '<div style="flex:1;margin:3px;padding:6px 0;text-align:center;border-radius:8px;font-size:14px;border:1px solid ' + (ok ? c : 'var(--border)') + ';color:' + c + '">' + (ok ? '&#9733;' : '&#9734;') + '<div style="font-size:10px">' + m[1] + '</div></div>';
        });
        var head = '<div style="text-align:center;margin-bottom:8px;font-size:22px;font-weight:700;color:var(--primary)">' + H.esc(H.uptime(up)) + '<div style="font-size:11px;font-weight:400;color:var(--muted)">' + (A ? 'تشغيل فعلي من /proc/uptime' : 'real /proc/uptime') + '</div></div>';
        var foot = next ? '<div style="font-size:11px;margin:8px 0 3px;color:var(--muted);text-align:center">' + (A ? 'التالي: ' : 'Next: ') + '<b style="color:var(--accent)">' + next[1] + '</b> · ' + H.esc(H.uptime(Math.max(0, next[0] - up))) + (A ? ' متبقية' : ' left') + '</div>' : '<div style="margin-top:8px;text-align:center;color:var(--excellent);font-size:12px">' + (A ? 'اكتمل الكل!' : 'All achieved!') + '</div>';
        return H.card(title, head + '<div style="display:flex;flex-wrap:wrap">' + pills + '</div>' + foot, done + '/6', 'bolt');
      };
    }
  });
  // #57 — real driver TX power: shows applied vs requested (35) and the regulatory max,
  // so the honest gap between "requested 35" and what the radio actually emits is visible.
  PRO_FEATURES.push({key:"tx_power_status",ar:"طاقة البث (مطلوب/مطبّق)",en:"TX Power (Req/Applied)",cat:"RF & Airtime",fn:function(d,H){var A=H.lang==="ar", rows="";((d&&d.wifi)||[]).forEach(function(w){var p=(w&&w.txpower)||{}, req=H.num(p.requested_dbm), app=H.num(p.applied_dbm);var reqTxt=H.finite(req)?H.fmt(req,0)+" dBm":"—";var appTxt=H.finite(app)?H.fmt(app,0)+" dBm":"—";var match=H.finite(req)&&H.finite(app)&&app>=req;var appCol=!H.finite(app)?"var(--muted)":match?"var(--excellent)":"var(--mid)";var head="<div style='display:flex;justify-content:space-between;font-size:12px'><b>"+H.esc((w.band||"?")+" ch "+(w.channel||"?"))+"</b><span class='latin' style='color:var(--muted)'>"+H.esc(w.iface||"")+"</span></div>";var line="<div style='display:flex;justify-content:space-between;font-size:12px;margin-top:3px'><span>"+(A?"مطلوب":"Requested")+"</span><span class='latin'>"+reqTxt+"</span></div>"+"<div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(A?"مطبّق (درايفر)":"Applied (driver)")+"</span><span class='latin' style='color:"+appCol+"'>"+appTxt+"</span></div>";rows+="<div style='margin:9px 0;padding-bottom:7px;border-bottom:1px solid var(--muted)'>"+head+line+H.bar(H.finite(app)?app:0,38,appCol)+"</div>";});if(!rows) rows="<div style='color:var(--muted)'>"+(A?"لا توجد بيانات طاقة":"No power data")+"</div>";var note="<div style='font-size:10px;color:var(--muted);margin-top:4px'>"+(A?"مطلوب = المحفوظ في UCI · مطبّق = ما أعلنه الدرايفر (iw) — وليس قياس RF حقيقي":"Requested = UCI saved · Applied = driver-declared (iw), not measured RF")+"</div>";return H.card(A?"طاقة البث (مطلوب/مطبّق)":"TX Power (Requested/Applied)",rows+note,null,"signal");}});
  PRO_FEATURES.push({key:"driver_banner",ar:"بصمة السائق (RF)",en:"Driver RF Banner",cat:"System & Health",fn:function(d,H){var A=H.lang==="ar";var b=(d&&d.perf&&d.perf.driver_banner)?String(d.perf.driver_banner):"";var is38=/38DBM/i.test(b),is35=/35DBM/i.test(b);var col=is38?"var(--excellent)":is35?"var(--mid)":"var(--muted)";var big=b?H.esc(b):(A?"غير معروف":"unknown");var sub=is38?(A?"سائق 38 مبني (طلب؛ الخرج محدود بالهاردوير)":"38 driver built (request; RF hardware-limited)"):is35?(A?"سائق 35 — النسخة ليست 38-build":"35 driver — not a 38 build"):(A?"لم يُقرأ من dmesg بعد":"not read from dmesg yet");var body="<div style=\"text-align:center;padding:6px 0\"><div style=\"font-size:16px;font-weight:800;color:"+col+";word-break:break-word\">"+big+"</div><div style=\"font-size:11px;color:var(--muted);margin-top:6px\">"+sub+"</div></div>";return H.card(A?"بصمة السائق (dmesg)":"Driver RF Banner (dmesg)",body,is38?"38":is35?"35":null,"cpu");}});
  // #58 — signal heatmap: every Wi-Fi client as a colour cell (green=strong .. red=weak).
  PRO_FEATURES.push({key:"signal_heatmap",ar:"خريطة حرارية للإشارة",en:"Signal Heatmap",cat:"Clients & Devices",fn:function(d,H){
    var A=H.lang==="ar", cells=[];
    ((d&&d.wifi)||[]).forEach(function(w){ ((w&&w.stations)||[]).forEach(function(s){ if(!s)return;
      var sg=H.num(s.signal_dbm); if(!H.finite(sg))return;
      cells.push({sg:sg,band:w.band||"",mac:String(s.mac||"")}); }); });
    if(!cells.length) return H.card(A?"خريطة حرارية للإشارة":"Signal Heatmap","<div class='empty'>"+(A?"لا عملاء متصلين":"No clients")+"</div>",null,"signal");
    cells.sort(function(a,b){return b.sg-a.sg;});
    function col(sg){ return sg>=-55?"#22C55E":sg>=-65?"#84CC16":sg>=-72?"#EAB308":sg>=-80?"#F97316":"#EF4444"; }
    var grid=cells.map(function(c){ var nm=c.mac.slice(-5);
      return "<div title='"+H.esc(c.mac)+"' style='background:"+col(c.sg)+";border-radius:7px;padding:8px 4px;text-align:center;color:#0b1220'>"+
        "<div style='font-weight:800;font-size:14px' class='latin'>"+H.fmt(c.sg,0)+"</div><div style='font-size:9px' class='latin'>"+H.esc(c.band)+"</div><div style='font-size:8px;opacity:.75' class='latin'>"+H.esc(nm)+"</div></div>"; }).join("");
    var legend="<div style='display:flex;gap:8px;margin-top:8px;font-size:10px;color:var(--muted);flex-wrap:wrap'>"+
      "<span style='color:#22C55E'>&#9632; "+(A?"ممتاز":"strong")+"</span><span style='color:#EAB308'>&#9632; "+(A?"متوسط":"fair")+"</span><span style='color:#EF4444'>&#9632; "+(A?"ضعيف":"weak")+"</span></div>";
    return H.card(A?"خريطة حرارية للإشارة":"Signal Heatmap","<div style='display:grid;grid-template-columns:repeat(auto-fill,minmax(52px,1fr));gap:6px'>"+grid+"</div>"+legend,String(cells.length),"signal");
  }});
  // #59 — weekly report: rolls a daily snapshot (usage, peak clients, max temp) in
  // localStorage and shows the last 7 days. Builds up over a week of uptime.
  PRO_FEATURES.push({key:"weekly_report",ar:"التقرير الأسبوعي",en:"Weekly Report",cat:"Automation & UX",fn:function(d,H){
    var A=H.lang==="ar";
    var day=new Date().toISOString().slice(0,10);
    var log; try{ log=JSON.parse(localStorage.getItem(LS+"weeklyLog")||"[]"); }catch(e){ log=[]; }
    if(!Array.isArray(log)) log=[];
    var u=dataUsage(d), cl=Math.max(Number(d.clients)||0, (H.mergeDevices(d)||[]).length), tc=H.num(d.temperature_c);
    var cur=log[log.length-1];
    if(!cur||cur.day!==day){ cur={day:day,rx:u.dayRx,tx:u.dayTx,peakCl:cl,maxTemp:H.finite(tc)?tc:0}; log.push(cur); }
    else{ cur.rx=u.dayRx; cur.tx=u.dayTx; if(cl>cur.peakCl)cur.peakCl=cl; if(H.finite(tc)&&tc>cur.maxTemp)cur.maxTemp=tc; }
    while(log.length>7) log.shift();
    try{ localStorage.setItem(LS+"weeklyLog",JSON.stringify(log)); }catch(e){}
    var mx=log.reduce(function(m,x){return Math.max(m,(x.rx||0)+(x.tx||0));},1);
    var rows=log.slice().reverse().map(function(x){ var tot=(x.rx||0)+(x.tx||0);
      return "<div style='margin:5px 0'><div style='display:flex;justify-content:space-between;font-size:11px'><b class='latin'>"+H.esc(x.day.slice(5))+"</b><span class='latin'>"+H.bytes(tot)+" · "+x.peakCl+(A?" جهاز":" cl")+(x.maxTemp?" · "+H.fmt(x.maxTemp,0)+"&deg;":"")+"</span></div>"+H.bar(tot,mx,"var(--accent)")+"</div>"; }).join("");
    var days=log.length, avg=days?log.reduce(function(a,x){return a+(x.rx||0)+(x.tx||0);},0)/days:0;
    var head="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:6px'><span>"+(A?"متوسط يومي":"daily avg")+"</span><b class='latin'>"+H.bytes(avg)+"</b></div>";
    var note=days<7?"<div style='font-size:10px;color:var(--muted);margin-top:6px'>"+(A?"يتراكم على مدى الأسبوع ("+days+"/7 يوم)":"builds up over a week ("+days+"/7 days)")+"</div>":"";
    return H.card(A?"التقرير الأسبوعي":"Weekly Report",head+rows+note,days+"/7","gear");
  }});
  // #60 — bandwidth hog: the client pulling the most right now + one-tap limit.
  PRO_FEATURES.push({key:"bandwidth_hog",ar:"ملتهم النطاق",en:"Bandwidth Hog",cat:"Traffic & Bandwidth",fn:function(d,H){
    var A=H.lang==="ar", rows=(H.stationTrafficRows&&H.stationTrafficRows(d))||[];
    if(!rows.length){ // fall back to expected_mbps if driver byte counters absent
      ((d&&d.wifi)||[]).forEach(function(w){((w&&w.stations)||[]).forEach(function(s){ if(!s)return; var e=H.num(s.expected_mbps); if(H.finite(e)&&e>0) rows.push({label:s.ip||s.mac||"?",mac:s.mac||"",totalRate:e*125000,up:0,down:e*125000}); }); }); }
    if(!rows.length) return H.card(A?"ملتهم النطاق":"Bandwidth Hog","<div class='empty'>"+(A?"لا حركة حالية":"No live traffic")+"</div>",null,"bolt");
    rows.sort(function(a,b){return (b.totalRate||0)-(a.totalRate||0);});
    var top=rows.slice(0,5), mx=top[0].totalRate||1;
    var body=top.map(function(r,i){ var nm=(typeof deviceName==="function"?deviceName(r.mac):"")||r.label;
      var lim=r.mac?"<button class='btn dev-action' data-dev-mac='"+H.esc(r.mac)+"' data-dev-act='__limit' style='font-size:10px;padding:2px 8px'>"+(A?"حدّ":"limit")+"</button>":"";
      return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px;gap:6px'><b>"+(i===0?"&#128293; ":"")+H.esc(nm)+"</b><span class='latin'>"+H.bps(r.totalRate||0)+" "+lim+"</span></div>"+
        H.bar(r.totalRate||0,mx,i===0?"var(--weak)":"var(--accent)")+"<div style='font-size:10px;color:var(--muted)'>&#8595; "+H.bps(r.down||0)+" &#183; &#8593; "+H.bps(r.up||0)+"</div></div>"; }).join("");
    return H.card(A?"ملتهم النطاق":"Bandwidth Hog",body,String(rows.length),"bolt");
  }});
  // #61 — internet outage log: records backhaul up/down transitions with duration.
  PRO_FEATURES.push({key:"outage_log",ar:"سجل انقطاع الإنترنت",en:"Internet Outage Log",cat:"Automation & UX",fn:function(d,H){
    var A=H.lang==="ar", online=!!((d&&d.backhaul)||{}).online;
    var st; try{ st=JSON.parse(localStorage.getItem(LS+"outageLog")||"{}"); }catch(e){ st={}; }
    if(typeof st.online==="undefined") st={online:online,since:Date.now(),events:[]};
    if(!Array.isArray(st.events)) st.events=[];
    if(online!==st.online){ var dur=Math.max(0,Date.now()-(st.since||Date.now()));
      if(!st.online) st.events.unshift({t:Date.now(),down:dur}); // came back up -> log the outage length
      st.online=online; st.since=Date.now(); st.events=st.events.slice(0,20);
      try{ localStorage.setItem(LS+"outageLog",JSON.stringify(st)); }catch(e){}
    } else { try{ localStorage.setItem(LS+"outageLog",JSON.stringify(st)); }catch(e){} }
    function dhm(ms){ var s=Math.round(ms/1000); if(s<60)return s+"s"; if(s<3600)return Math.floor(s/60)+"m "+(s%60)+"s"; return Math.floor(s/3600)+"h "+Math.floor((s%3600)/60)+"m"; }
    var cur="<div style='text-align:center;margin-bottom:8px'><span style='color:"+(online?"var(--excellent)":"var(--weak)")+";font-weight:700'>"+(online?(A?"متصل":"Online"):(A?"مقطوع":"Offline"))+"</span> <small class='muted'>"+(A?"منذ ":"for ")+dhm(Date.now()-(st.since||Date.now()))+"</small></div>";
    var list=st.events.length?st.events.map(function(e){ var dt=new Date(e.t); var hh=("0"+dt.getHours()).slice(-2)+":"+("0"+dt.getMinutes()).slice(-2);
      return "<div style='display:flex;justify-content:space-between;font-size:11px;margin:4px 0'><span class='latin'>"+hh+"</span><span style='color:var(--weak)'>"+(A?"انقطاع ":"down ")+dhm(e.down)+"</span></div>"; }).join(""):"<div style='font-size:11px;color:var(--excellent);text-align:center'>"+(A?"لا انقطاعات مسجّلة":"No outages recorded")+"</div>";
    return H.card(A?"سجل انقطاع الإنترنت":"Internet Outage Log",cur+list,String(st.events.length),"net");
  }});
  // #62 — latency monitor: gateway round-trip over time (sparkline + now/avg/max).
  PRO_FEATURES.push({key:"latency_monitor",ar:"مراقب زمن الاستجابة",en:"Latency Monitor",cat:"Traffic & Bandwidth",fn:function(d,H){
    var A=H.lang==="ar", lt=H.num(d&&d.latency_ms);
    var hist; try{ hist=JSON.parse(localStorage.getItem(LS+"latHist")||"[]"); }catch(e){ hist=[]; }
    if(!Array.isArray(hist)) hist=[];
    if(H.finite(lt)){ hist.push(lt); if(hist.length>60) hist.shift(); try{ localStorage.setItem(LS+"latHist",JSON.stringify(hist)); }catch(e){} }
    if(!hist.length) return H.card(A?"مراقب زمن الاستجابة":"Latency Monitor","<div class='empty'>"+(A?"لا بيانات":"No data")+"</div>",null,"net");
    var avg=hist.reduce(function(a,b){return a+b;},0)/hist.length, mx=Math.max.apply(null,hist), now=hist[hist.length-1];
    var col=now<20?"var(--excellent)":now<50?"var(--good)":now<100?"var(--mid)":"var(--weak)";
    var body="<div style='text-align:center'><div class='latin' style='font-size:28px;font-weight:800;color:"+col+"'>"+H.fmt(now,1)+" ms</div></div>"+
      H.spark(hist,col)+"<div class='grid two' style='margin-top:8px'><div class='traffic-box'><span>"+(A?"متوسط":"avg")+"</span><b class='latin'>"+H.fmt(avg,1)+" ms</b></div><div class='traffic-box'><span>"+(A?"أقصى":"max")+"</span><b class='latin'>"+H.fmt(mx,1)+" ms</b></div></div>";
    return H.card(A?"مراقب زمن الاستجابة":"Latency Monitor",body,H.fmt(now,0)+"ms","net");
  }});
  // #63 — Performance Pack: live checklist of every optimization actually active on the
  // device (read from d.perf which dashapi2 builds from uci/sysfs — real state, not claims).
  PRO_FEATURES.push({key:"perf_pack",ar:"حزمة الأداء الاحترافية",en:"Performance Pack",cat:"Automation & UX",fn:function(d,H){
    var A=H.lang==="ar", p=(d&&d.perf)||null, t=A?"حزمة الأداء الاحترافية":"Performance Pack";
    if(!p) return H.card(t,"<div class='empty'>"+(A?"لا بيانات":"No data")+"</div>",null,"bolt");
    function row(ok,ar,en,hint){ var c=ok?"var(--excellent)":"var(--muted)";
      return "<div style='display:flex;align-items:center;gap:8px;margin:5px 0;font-size:12px'>"+
        "<span style='flex:0 0 18px;height:18px;border-radius:50%;border:1.5px solid "+c+";color:"+c+";font-weight:700;display:flex;align-items:center;justify-content:center;font-size:11px'>"+(ok?"✓":"—")+"</span>"+
        "<span style='flex:1'>"+(A?ar:en)+(hint?" <small class='muted'>"+hint+"</small>":"")+"</span></div>"; }
    function grp(title,rows){ return "<div style='margin:8px 0 2px;font-weight:700;font-size:12px;color:var(--accent)'>"+title+"</div>"+rows; }
    var items=[
      [!!p.mu_bf_he,1],[!!p.mu_bf_vht,1],[!!p.su_bf,1],[!!p.spatial_reuse,1],[!!p.bss_color,1],
      [!!p.dynack,1],[!!p.ldpc,1],[!!p.stbc,1],[!!p.keep_weak,1],
      [!!p.airtime,1],[!!p.m2u,1],[!!p.kv,1],[H.num(p.maxassoc)>=200,1],
      [!!p.hw_offload,1],[!!p.sw_offload,1],[!!p.rps,1],[!!p.fastopen,1],[H.num(p.dns_cache)>=4000,1],[!!p.sgi,1]];
    var on=items.filter(function(x){return x[0];}).length, tot=items.length;
    var head="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px'><span>"+(A?"المُفعّل":"Active")+"</span><b class='latin' style='color:var(--excellent)'>"+on+"/"+tot+"</b></div>"+H.bar(on,tot,"var(--excellent)")+
      "<div style='display:flex;justify-content:space-between;font-size:11px;color:var(--muted);margin:6px 0'><span>"+(A?"قوة البث":"TX power")+"</span><b class='latin' style='color:var(--excellent)'>"+(H.finite(H.num(p.txpower))?p.txpower:35)+" dBm</b></div>";
    var body=head+
      grp(A?"MIMO / AX":"MIMO / AX",
        row(p.mu_bf_he,"MU-MIMO (AX)","MU-MIMO (AX)",A?"إرسال لعدة أجهزة معاً":"serve many at once")+
        row(p.mu_bf_vht,"MU-MIMO (AC)","MU-MIMO (AC)",A?"نفس الميزة لأجهزة AC":"same for AC clients")+
        row(p.su_bf,"Beamforming",  "Beamforming",A?"تركيز الشعاع نحو كل جهاز":"focus beam per client")+
        row(p.spatial_reuse,A?"إعادة استخدام مكاني":"Spatial Reuse",A?"إعادة استخدام مكاني":"Spatial Reuse",A?"أداء أعلى في الزحام":"better in congestion")+
        row(p.bss_color,"BSS Color","BSS Color",""))+
      grp(A?"تقوية العميل البعيد":"Far-client boost",
        row(p.dynack,A?"مهلة ACK ديناميكية":"Dynamic ACK",A?"مهلة ACK ديناميكية":"Dynamic ACK",A?"نقل كامل للبعيد بلا ضرر للقريب":"full speed at distance")+
        row(p.ldpc,"LDPC","LDPC",A?"فكّ الإشارة الضعيفة بنجاح":"decode weak signals")+
        row(p.stbc,"STBC","STBC",A?"تنوّع هوائيات للموثوقية":"antenna diversity")+
        row(p.keep_weak,A?"عدم فصل الضعيف أبداً":"Never drop weak",A?"عدم فصل الضعيف أبداً":"Never drop weak",""))+
      grp(A?"السعة":"Capacity",
        row(p.airtime,A?"عدالة وقت الهواء":"Airtime fairness",A?"عدالة وقت الهواء":"Airtime fairness",A?"جهاز واحد لا يخنق الباقي":"no client starves others")+
        row(H.num(p.maxassoc)>=200,A?"سعة 200 جهاز/تردد":"200 clients/band",A?"سعة 200 جهاز/تردد":"200 clients/band","")+
        row(p.m2u,"Multicast→Unicast","Multicast→Unicast",A?"بث فيديو أسرع":"faster video")+
        row(p.kv,"802.11k/v roaming","802.11k/v roaming",""))+
      grp(A?"مسار الحزم السريع":"Fast packet path",
        row(p.hw_offload,A?"تفريغ عتادي":"HW offload",A?"تفريغ عتادي":"HW offload",A?"توجيه بالعتاد لا بالمعالج":"forwarding in hardware")+
        row(p.sw_offload,A?"تفريغ برمجي":"SW offload",A?"تفريغ برمجي":"SW offload","")+
        row(p.rps,A?"توزيع على النواتين":"RPS steering",A?"توزيع على النواتين":"RPS steering","")+
        row(p.fastopen,"TCP FastOpen","TCP FastOpen","")+
        row(H.num(p.dns_cache)>=4000,A?"كاش DNS كبير":"Big DNS cache",A?"كاش DNS كبير":"Big DNS cache","4000"));
    return H.card(t,body,on+"/"+tot,"bolt");
  }});
  // #64 — MIMO/AX/AC/N matrix: which acceleration each Wi-Fi generation gets, as a grid.
  PRO_FEATURES.push({key:"mimo_matrix",ar:"مصفوفة AX/AC/N",en:"AX/AC/N Matrix",cat:"Automation & UX",fn:function(d,H){
    var A=H.lang==="ar", p=(d&&d.perf)||{}, t=A?"مصفوفة AX/AC/N":"AX/AC/N Matrix";
    var cols=[["WiFi 6 (AX)"],["WiFi 5 (AC)"],["WiFi 4 (N)"]];
    var rows=[
      [A?"سرعة قصوى":"Top rate","HE80 1024-QAM","VHT80 256-QAM","HT40 MCS15"],
      ["MU-MIMO",p.mu_bf_he?"✓":"—",p.mu_bf_vht?"✓":"—","—"],
      ["Beamforming",p.su_bf?"✓":"—",p.mu_bf_vht||p.su_bf?"✓":"—","—"],
      ["LDPC",p.ldpc?"✓":"—",p.ldpc?"✓":"—",p.ldpc?"✓":"—"],
      ["STBC",p.stbc?"✓":"—",p.stbc?"✓":"—",p.stbc?"✓":"—"],
      ["OFDMA","✓ fw","—","—"],
      [A?"مدى بعيد":"Long range",p.dynack?"✓":"—",p.dynack?"✓":"—",p.dynack?"✓":"—"]];
    var h="<div class='table-wrap'><table style='font-size:11px'><thead><tr><th></th><th>"+cols[0][0]+"</th><th>"+cols[1][0]+"</th><th>"+cols[2][0]+"</th></tr></thead><tbody>";
    rows.forEach(function(r){ h+="<tr><td style='font-weight:700'>"+r[0]+"</td>"; for(var i=1;i<4;i++){ var v=r[i], ok=v.indexOf("✓")===0; h+="<td class='latin' style='color:"+(ok?"var(--excellent)":v==="—"?"var(--muted)":"var(--text)")+"'>"+v+"</td>"; } h+="</tr>"; });
    h+="</tbody></table></div><p class='muted' style='margin-top:6px;font-size:11px'>"+(A?"كل جيل واي فاي يحصل على أقصى تسريع يدعمه — والقديم لا يبطّئ الحديث (عدالة وقت الهواء)":"Each Wi-Fi generation gets its maximum acceleration — old clients never slow new ones (airtime fairness)")+"</p>";
    return H.card(t,h,"2×2","signal");
  }});
  // ---- v88 RX/TX + AX/AC/N live cards (from existing dashapi2 fields) ----
  PRO_FEATURES.push({key:"band_rate_summary",ar:"سرعة الوصلة لكل باند",en:"Per-Band Link Rate",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var ceil={"2.4G":574,"5G":1201};var agg={};w.forEach(function(r){var b=r.band||"?";(r.stations||[]).forEach(function(s){var tx=H.num(s.tx_rate),rx=H.num(s.rx_rate);if(!agg[b])agg[b]={tx:[],rx:[],n:0,top:0};if(H.finite(tx)){agg[b].tx.push(tx);if(tx>=0.9*(ceil[b]||1201))agg[b].top++;}if(H.finite(rx))agg[b].rx.push(rx);agg[b].n++;});});var ks=Object.keys(agg);if(!ks.length)return H.card(H.lang==="ar"?"سرعة الوصلة":"Link Rate","<div class='empty'>—</div>",null,"net");function avg(a){return a.length?a.reduce(function(x,y){return x+y;},0)/a.length:0;}function mx(a){return a.length?Math.max.apply(null,a):0;}var body=ks.map(function(b){var g=agg[b],c=ceil[b]||1201,mxtx=mx(g.tx);return "<div style='margin:8px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span><b>"+H.esc(b)+"</b> · "+g.n+" "+(H.lang==="ar"?"عميل":"cli")+"</span><span class='latin'>"+H.fmt(mxtx,0)+"/"+c+" Mbps</span></div>"+H.bar(mxtx,c,mxtx>=0.9*c?"var(--excellent)":mxtx>=0.5*c?"var(--good)":"var(--mid)")+"<small class='muted latin'>"+(H.lang==="ar"?"متوسط TX ":"avg TX ")+H.fmt(avg(g.tx),0)+" · RX "+H.fmt(avg(g.rx),0)+" · "+(H.lang==="ar"?"عند السقف ":"at-ceiling ")+g.top+"</small></div>";}).join("");return H.card(H.lang==="ar"?"سرعة الوصلة لكل باند (حتى 1200)":"Per-Band Link Rate (up to 1200)",body,ks.length+"","net");}});
  PRO_FEATURES.push({key:"band_rxtx_ratio",ar:"تدفق RX/TX لكل باند",en:"Per-Band RX/TX Flow",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var b={"2.4G":{dl:0,ul:0},"5G":{dl:0,ul:0}};ifs.forEach(function(x){var n=x.name||"";var band=/^phy0-ap/.test(n)?"2.4G":/^phy1-ap/.test(n)?"5G":null;if(!band)return;b[band].dl+=H.num(x.tx_bps)||0;b[band].ul+=H.num(x.rx_bps)||0;});var body=["2.4G","5G"].map(function(k){var dl=b[k].dl,ul=b[k].ul,t=dl+ul||1;var pdl=dl/t*100;return "<div style='margin:8px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span><b>"+k+"</b></span><span class='latin'>↓"+H.bps(dl)+" ↑"+H.bps(ul)+"</span></div><div style='display:flex;height:16px;border-radius:5px;overflow:hidden'><div style='width:"+pdl.toFixed(1)+"%;background:var(--accent)'></div><div style='width:"+(100-pdl).toFixed(1)+"%;background:var(--primary)'></div></div></div>";}).join("");return H.card(H.lang==="ar"?"تدفق RX/TX لكل باند":"Per-Band RX/TX Flow","<div style='font-size:11px;color:var(--muted);margin-bottom:6px'>↓ "+(H.lang==="ar"?"تنزيل":"download")+" · ↑ "+(H.lang==="ar"?"رفع":"upload")+"</div>"+body,null,"net");}});
  PRO_FEATURES.push({key:"phy_std_badge",ar:"معيار كل راديو AX/AC/N",en:"Per-Radio Standard",cat:"Automation & UX",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];if(!w.length)return H.card(H.lang==="ar"?"المعيار":"Standard","<div class='empty'>—</div>",null,"signal");var body=w.map(function(r){var h=String(r.htmode||"");var std=/HE/.test(h)?["Wi-Fi 6 (AX)","var(--excellent)"]:/VHT/.test(h)?["Wi-Fi 5 (AC)","var(--good)"]:/HT/.test(h)?["Wi-Fi 4 (N)","var(--mid)"]:["Legacy","var(--weak)"];return "<div style='display:flex;justify-content:space-between;align-items:center;margin:7px 0'><span>"+H.esc(r.band||"?")+" · ch "+H.esc(String(r.channel||"?"))+" · "+H.esc(h)+"</span><span style='padding:2px 10px;border-radius:10px;font-size:12px;font-weight:700;color:#fff;background:"+std[1]+"'>"+std[0]+"</span></div>";}).join("");return H.card(H.lang==="ar"?"معيار كل راديو (AX/AC/N)":"Per-Radio Standard (AX/AC/N)",body,w.length+"","signal");}});
  PRO_FEATURES.push({key:"phy_rate_hist",ar:"توزيع سرعات العملاء",en:"Client Rate Histogram",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var edges=[[0,100],[100,300],[300,600],[600,900],[900,1300]],lab=["<100","100-300","300-600","600-900","900-1200"],buck=[0,0,0,0,0],tot=0;w.forEach(function(r){(r.stations||[]).forEach(function(s){var t=H.num(s.tx_rate);if(!H.finite(t))return;tot++;for(var i=0;i<edges.length;i++){if(t>=edges[i][0]&&t<edges[i][1]){buck[i]++;break;}}});});if(!tot)return H.card(H.lang==="ar"?"توزيع السرعات":"Rate Histogram","<div class='empty'>—</div>",null,"device");var mx=Math.max.apply(null,buck)||1;var body=lab.map(function(l,i){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+l+" Mbps</span><span>"+buck[i]+"</span></div>"+H.bar(buck[i],mx,i>=3?"var(--excellent)":i>=1?"var(--good)":"var(--mid)")+"</div>";}).join("");return H.card(H.lang==="ar"?"توزيع سرعات العملاء (TX)":"Client Link-Rate Histogram (TX)",body,tot+"","device");}});
  // ---- v91 feature pack: 72 agent-generated insight cards (validated: syntax + runtime smoke ar/en x full/empty/partial) ----
  PRO_FEATURES.push({key:"x_rf_channel_score",ar:"جودة القناة",en:"Channel Score",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'جودة القناة':'Channel Score';if(!w.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');var rows='';for(var i=0;i<w.length;i++){var r=w[i],sv=r.survey||{};var busy=H.num(sv.busy_pct);busy=H.finite(busy)?H.clamp(busy,0,100):null;var noise=H.num(r.noise_dbm);if(!H.finite(noise)){noise=H.num(sv.noise_dbm);}var score=100;if(busy!=null){score-=busy*0.6;}if(H.finite(noise)){score-=H.clamp((noise+95),0,35);}score=H.clamp(score,0,100);var col=score>75?'var(--excellent)':score>55?'var(--good)':score>35?'var(--mid)':'var(--weak)';var sub=(busy==null?'—':H.fmt(busy,0)+'% busy')+' · '+(H.finite(noise)?H.fmt(noise,0)+' dBm':'—');rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+"</span><span style='color:"+col+"'>"+H.fmt(score,0)+"</span></div>"+H.bar(score,100,col)+"<div style='font-size:11px;color:var(--muted)'>"+sub+"</div></div>";}return H.card(t,rows,null,'signal');}});
  PRO_FEATURES.push({key:"x_rf_bss_color",ar:"إعادة الاستخدام المكاني",en:"Spatial Reuse (BSS Color)",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'إعادة الاستخدام المكاني':'Spatial Reuse (BSS Color)';if(!w.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'wifi');var rows='';var he=0;for(var i=0;i<w.length;i++){var r=w[i];var hm=String(r.htmode||'').toUpperCase();var isEHT=hm.indexOf('EHT')>-1;var isHE=hm.indexOf('HE')>-1;var ok=isHE||isEHT;if(ok){he++;}var cap=isEHT?'Wi-Fi 7':isHE?'Wi-Fi 6':(H.lang==='ar'?'قديم':'Legacy');var col=ok?'var(--excellent)':'var(--mid)';var txt=ok?(H.lang==='ar'?'BSS Color مدعوم':'BSS color capable'):(H.lang==='ar'?'لا إعادة استخدام':'no spatial reuse');rows+="<div style='display:flex;justify-content:space-between;margin:6px 0;font-size:12px'><span>"+H.esc(r.band||'?')+' · '+H.esc(hm||'?')+"</span><span style='color:"+col+"'>"+H.esc(cap)+' · '+txt+"</span></div>";}return H.card(t,rows,he+'/'+w.length+' HE','wifi');}});
  PRO_FEATURES.push({key:"x_rf_nss_estimate",ar:"تيارات NSS المكانية",en:"NSS Spatial Streams",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'تيارات NSS المكانية':'NSS Spatial Streams';function pbase(hm){if(hm.indexOf('160')>-1)return 1200;if(hm.indexOf('80')>-1)return 600;if(hm.indexOf('40')>-1)return 286;return 143;}var counts={1:0,2:0,3:0,4:0};var total=0;for(var i=0;i<w.length;i++){var r=w[i];var hm=String(r.htmode||'').toUpperCase();var b=pbase(hm);var ss=Array.isArray(r.stations)?r.stations:[];for(var j=0;j<ss.length;j++){var rate=H.num(ss[j].tx_rate);if(!H.finite(rate)||b<=0)continue;var nss=H.clamp(Math.round(rate/b),1,4);counts[nss]++;total++;}}if(!total)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='';for(var k=1;k<=4;k++){var c=counts[k];var pct=total>0?(c/total)*100:0;var col=k>=2?'var(--excellent)':'var(--mid)';rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(H.lang==='ar'?k+'×NSS':k+' stream')+"</span><span>"+c+"</span></div>"+H.bar(pct,100,col)+"</div>";}return H.card(t,rows,String(total),'net');}});
  PRO_FEATURES.push({key:"x_rf_snr_mcs",ar:"أعلى MCS حسب SNR",en:"Max MCS by SNR",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'أعلى MCS حسب SNR':'Max MCS by SNR';function mcs(snr){if(snr>=37)return 11;if(snr>=35)return 10;if(snr>=32)return 9;if(snr>=29)return 8;if(snr>=25)return 7;if(snr>=22)return 6;if(snr>=19)return 5;if(snr>=17)return 4;if(snr>=13)return 3;if(snr>=11)return 2;if(snr>=8)return 1;if(snr>=5)return 0;return -1;}var arr=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var s=ss[j];var snr=H.num(s.snr);if(!H.finite(snr)){var sig=H.num(s.signal_dbm);var nz=H.num(w[i].noise_dbm);if(H.finite(sig)&&H.finite(nz)){snr=sig-nz;}}if(!H.finite(snr))continue;arr.push({mac:s.mac,ip:s.ip,snr:snr,m:mcs(snr)});}}if(!arr.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');arr.sort(function(a,b){return b.m-a.m;});var rows='';var n=Math.min(arr.length,6);for(var k=0;k<n;k++){var x=arr[k];var col=x.m>=9?'var(--excellent)':x.m>=6?'var(--good)':x.m>=3?'var(--mid)':'var(--weak)';var lab=x.m<0?'—':'MCS '+x.m;rows+="<div style='display:flex;justify-content:space-between;margin:5px 0;font-size:12px'><span>"+H.esc(x.ip||x.mac||'?')+"</span><span style='color:"+col+"'>"+lab+' · '+H.fmt(x.snr,0)+" dB</span></div>";}return H.card(t,rows,String(arr.length),'signal');}});
  PRO_FEATURES.push({key:"x_rf_spectral_eff",ar:"الكفاءة الطيفية",en:"Spectral Efficiency",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'الكفاءة الطيفية':'Spectral Efficiency';function width(hm){hm=String(hm).toUpperCase();if(hm.indexOf('160')>-1)return 160;if(hm.indexOf('80')>-1)return 80;if(hm.indexOf('40')>-1)return 40;return 20;}var rows='';var any=false;for(var i=0;i<w.length;i++){var r=w[i];var mhz=width(r.htmode);var ss=Array.isArray(r.stations)?r.stations:[];var sum=0,c=0;for(var j=0;j<ss.length;j++){var rt=H.num(ss[j].tx_rate);if(H.finite(rt)){sum+=rt;c++;}}if(!c)continue;any=true;var avg=sum/c;var eff=mhz>0?avg/mhz:0;var col=eff>8?'var(--excellent)':eff>5?'var(--good)':eff>2.5?'var(--mid)':'var(--weak)';rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(r.band||'?')+' · '+mhz+"MHz</span><span style='color:"+col+"'>"+H.fmt(eff,1)+" b/Hz</span></div>"+H.bar(H.clamp(eff,0,12),12,col)+"<div style='font-size:11px;color:var(--muted)'>"+H.fmt(avg,0)+' Mbps avg · '+c+(H.lang==='ar'?' عميل':' clients')+"</div></div>";}if(!any)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');return H.card(t,rows,null,'signal');}});
  PRO_FEATURES.push({key:"x_rf_airtime_est",ar:"مستهلكو وقت البث",en:"Airtime Consumers",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'مستهلكو وقت البث':'Airtime Consumers';var arr=[];var tot=0;for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var s=ss[j];var rt=H.num(s.tx_rate);if(!H.finite(rt)||rt<=0)continue;var wgt=1/rt;arr.push({mac:s.mac,ip:s.ip,rt:rt,w:wgt});tot+=wgt;}}if(!arr.length||tot<=0)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');arr.sort(function(a,b){return b.w-a.w;});var rows='';var n=Math.min(arr.length,6);for(var k=0;k<n;k++){var x=arr[k];var pct=(x.w/tot)*100;var col=pct>40?'var(--weak)':pct>25?'var(--mid)':'var(--good)';rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(x.ip||x.mac||'?')+"</span><span style='color:"+col+"'>"+H.fmt(pct,0)+'% · '+H.fmt(x.rt,0)+" Mbps</span></div>"+H.bar(pct,100,col)+"</div>";}return H.card(t,rows,String(arr.length),'signal');}});
  PRO_FEATURES.push({key:"x_rf_spectrum_congestion",ar:"ازدحام الطيف",en:"Spectrum Congestion",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'ازدحام الطيف':'Spectrum Congestion';var vals=[];for(var i=0;i<w.length;i++){var sv=w[i].survey||{};var b=H.num(sv.busy_pct);if(H.finite(b)){vals.push(H.clamp(b,0,100));}}if(!vals.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');var sum=0;for(var j=0;j<vals.length;j++){sum+=vals[j];}var avg=sum/vals.length;var col=avg<30?'var(--excellent)':avg<55?'var(--good)':avg<75?'var(--mid)':'var(--weak)';var txt=avg<30?(H.lang==='ar'?'نظيف':'clear'):avg<55?(H.lang==='ar'?'معتدل':'moderate'):avg<75?(H.lang==='ar'?'مزدحم':'busy'):(H.lang==='ar'?'مكتظ':'congested');var body=H.gauge(H.lang==='ar'?'متوسط الانشغال':'avg busy',H.fmt(avg,0)+'%',txt,vals.length+(H.lang==='ar'?' راديو':' radios'),avg,col,'signal');return H.card(t,body,txt,'signal');}});
  PRO_FEATURES.push({key:"x_rf_phy_ceiling",ar:"سقف PHY المحقق",en:"PHY Ceiling Reached",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'سقف PHY المحقق':'PHY Ceiling Reached';function cap(hm){hm=String(hm).toUpperCase();var per=hm.indexOf('160')>-1?1200:hm.indexOf('80')>-1?600:hm.indexOf('40')>-1?286:143;return per*2;}var rows='';var any=false;for(var i=0;i<w.length;i++){var r=w[i];var mx=cap(r.htmode);var ss=Array.isArray(r.stations)?r.stations:[];var best=0;for(var j=0;j<ss.length;j++){var rt=H.num(ss[j].tx_rate);if(H.finite(rt)&&rt>best){best=rt;}}if(mx<=0)continue;any=true;var pct=H.clamp((best/mx)*100,0,100);var col=pct>75?'var(--excellent)':pct>50?'var(--good)':pct>25?'var(--mid)':'var(--weak)';rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(r.band||'?')+' · '+H.esc(String(r.htmode||'?'))+"</span><span style='color:"+col+"'>"+H.fmt(pct,0)+"%</span></div>"+H.bar(pct,100,col)+"<div style='font-size:11px;color:var(--muted)'>"+H.fmt(best,0)+' / '+mx+" Mbps</div></div>";}if(!any)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');return H.card(t,rows,null,'net');}});
  PRO_FEATURES.push({key:"x_cl_rssi_hist",ar:"توزيع الإشارة RSSI",en:"RSSI Distribution",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var sig=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(H.finite(v))sig.push(v);}}var T=H.lang==='ar'?'توزيع الإشارة RSSI':'RSSI Distribution';if(!sig.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');var b=[{l:H.lang==='ar'?'ممتاز ≥-50':'Excellent ≥-50',c:'var(--excellent)',n:0},{l:H.lang==='ar'?'جيد -50..-60':'Good -50..-60',c:'var(--good)',n:0},{l:H.lang==='ar'?'متوسط -60..-70':'Fair -60..-70',c:'var(--mid)',n:0},{l:H.lang==='ar'?'ضعيف -70..-80':'Weak -70..-80',c:'var(--weak)',n:0},{l:H.lang==='ar'?'حرج <-80':'Edge <-80',c:'var(--weak)',n:0}];for(var k=0;k<sig.length;k++){var s=sig[k];if(s>=-50)b[0].n++;else if(s>=-60)b[1].n++;else if(s>=-70)b[2].n++;else if(s>=-80)b[3].n++;else b[4].n++;}var rows='';for(var m=0;m<b.length;m++){rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+b[m].l+"</span><span style='color:"+b[m].c+"'>"+b[m].n+"</span></div>"+H.bar(b[m].n,sig.length,b[m].c)+"</div>";}return H.card(T,rows,String(sig.length),'signal');}});
  PRO_FEATURES.push({key:"x_cl_link_eff_watch",ar:"كفاءة الوصلة",en:"Link Efficiency",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var arr=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var s=ss[j];var tx=H.num(s.tx_rate);var ex=H.num(s.expected_mbps);if(H.finite(tx)&&H.finite(ex)&&ex>0){arr.push({s:s,eff:H.clamp(tx/ex*100,0,100)});}}}var T=H.lang==='ar'?'كفاءة الوصلة':'Link Efficiency';if(!arr.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'net');var sum=0;for(var k=0;k<arr.length;k++)sum+=arr[k].eff;var avg=sum/arr.length;arr.sort(function(a,b){return a.eff-b.eff;});var rows="<div style='font-size:12px;color:var(--muted);margin-bottom:6px'>"+(H.lang==='ar'?'المتوسط':'Avg')+" "+H.fmt(avg,0)+"%"+(H.lang==='ar'?' — الأضعف أولاً':' — worst first')+"</div>";var lim=Math.min(4,arr.length);for(var m=0;m<lim;m++){var e=arr[m];var col=e.eff>=70?'var(--excellent)':e.eff>=45?'var(--mid)':'var(--weak)';rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(e.s.ip||e.s.mac||'?')+"</span><span style='color:"+col+"'>"+H.fmt(e.eff,0)+"%</span></div>"+H.bar(e.eff,100,col)+"</div>";}return H.card(T,rows,H.fmt(avg,0)+'%','net');}});
  PRO_FEATURES.push({key:"x_cl_phy_class",ar:"فئة PHY",en:"PHY Class Split",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var ax=0,ac=0,nn=0,un=0;for(var i=0;i<w.length;i++){var r=w[i];var c=H.num(r.clients);var cn=H.finite(c)?c:(Array.isArray(r.stations)?r.stations.length:0);var hm=String(r.htmode||'').toUpperCase();if(hm.indexOf('EHT')>=0||hm.indexOf('HE')>=0)ax+=cn;else if(hm.indexOf('VHT')>=0)ac+=cn;else if(hm.indexOf('HT')>=0)nn+=cn;else un+=cn;}var tot=ax+ac+nn+un;var T=H.lang==='ar'?'فئة PHY':'PHY Class Split';if(!tot)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'wifi');var b=[{l:'Wi-Fi 6 (ax)',c:'var(--excellent)',n:ax},{l:'Wi-Fi 5 (ac)',c:'var(--good)',n:ac},{l:'Wi-Fi 4 (n)',c:'var(--mid)',n:nn},{l:H.lang==='ar'?'غير معروف':'Unknown',c:'var(--muted)',n:un}];var rows='';for(var m=0;m<b.length;m++){if(!b[m].n)continue;rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+b[m].l+"</span><span style='color:"+b[m].c+"'>"+b[m].n+"</span></div>"+H.bar(b[m].n,tot,b[m].c)+"</div>";}rows+="<div style='font-size:11px;color:var(--muted);margin-top:4px'>"+(H.lang==='ar'?'مستنتج من نمط الراديو':'inferred from radio htmode')+"</div>";return H.card(T,rows,String(tot),'wifi');}});
  PRO_FEATURES.push({key:"x_cl_nss_estimate",ar:"تقدير التدفقات NSS",en:"NSS Estimate",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var one=0,two=0;for(var i=0;i<w.length;i++){var r=w[i];var hm=String(r.htmode||'').toUpperCase();var per=143;if(hm.indexOf('160')>=0)per=1200;else if(hm.indexOf('80')>=0)per=600;else if(hm.indexOf('40')>=0)per=286;else per=143;var ss=Array.isArray(r.stations)?r.stations:[];for(var j=0;j<ss.length;j++){var tx=H.num(ss[j].tx_rate);if(!H.finite(tx))continue;if(tx>per*1.25)two++;else one++;}}var tot=one+two;var T=H.lang==='ar'?'تقدير التدفقات NSS':'NSS Estimate';if(!tot)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'wifi');var rows="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(H.lang==='ar'?'تياران 2×2':'2 streams (2×2)')+"</span><span style='color:var(--excellent)'>"+two+"</span></div>"+H.bar(two,tot,'var(--excellent)')+"</div>";rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(H.lang==='ar'?'تيار واحد 1×1':'1 stream (1×1)')+"</span><span style='color:var(--mid)'>"+one+"</span></div>"+H.bar(one,tot,'var(--mid)')+"</div>";rows+="<div style='font-size:11px;color:var(--muted);margin-top:4px'>"+(H.lang==='ar'?'تقديري من معدل الربط':'estimated from link rate')+"</div>";return H.card(T,rows,String(tot),'wifi');}});
  PRO_FEATURES.push({key:"x_cl_roam_ready",ar:"جاهزية التجوال",en:"Roaming Readiness",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var cand=[];var tot=0;for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(!H.finite(v))continue;tot++;if(v<=-67&&v>=-82)cand.push({s:ss[j],v:v});}}var T=H.lang==='ar'?'جاهزية التجوال':'Roaming Readiness';if(!tot)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');cand.sort(function(a,b){return a.v-b.v;});var rows="<div style='font-size:12px;color:var(--muted);margin-bottom:6px'>"+cand.length+" / "+tot+" "+(H.lang==='ar'?'مرشح للتجوال':'roam candidates')+"</div>";if(!cand.length){rows+="<div style='color:var(--excellent);font-size:12px'>"+(H.lang==='ar'?'كل العملاء بإشارة قوية':'all clients strong')+"</div>";}var lim=Math.min(4,cand.length);for(var m=0;m<lim;m++){var q=H.quality('rssi',cand[m].v);rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:4px 0'><span>"+H.esc(cand[m].s.ip||cand[m].s.mac||'?')+"</span><span style='color:"+q.color+"'>"+H.fmt(cand[m].v,0)+" dBm</span></div>";}rows+="<div style='font-size:11px;color:var(--muted);margin-top:6px'>"+(H.lang==='ar'?'تبقى متصلة — لا تُفصل أبداً':'kept connected — never dropped')+"</div>";return H.card(T,rows,String(cand.length),'signal');}});
  PRO_FEATURES.push({key:"x_cl_edge_clients",ar:"العملاء الطرفيون",en:"Edge Clients",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var arr=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(H.finite(v))arr.push({s:ss[j],v:v});}}var T=H.lang==='ar'?'العملاء الطرفيون':'Edge Clients';if(!arr.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'device');arr.sort(function(a,b){return a.v-b.v;});var lim=Math.min(4,arr.length);var rows='';for(var m=0;m<lim;m++){var e=arr[m];var q=H.quality('rssi',e.v);var dm=H.num(H.distanceM(e.v));var ds=H.finite(dm)?'~'+H.fmt(dm,0)+' m':'';rows+="<div style='margin:5px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(e.s.ip||e.s.mac||'?')+"</span><span style='color:"+q.color+"'>"+H.fmt(e.v,0)+" dBm</span></div><div style='font-size:11px;color:var(--muted)'>"+ds+"</div></div>";}rows+="<div style='font-size:11px;color:var(--excellent);margin-top:6px'>"+(H.lang==='ar'?'محمية — لا تُفصل أبداً':'protected — never dropped')+"</div>";return H.card(T,rows,String(arr.length),'device');}});
  PRO_FEATURES.push({key:"x_cl_signal_spread",ar:"تشتت الإشارة",en:"Signal Spread",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var sig=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(H.finite(v))sig.push(v);}}var T=H.lang==='ar'?'تشتت الإشارة':'Signal Spread';if(!sig.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');var mn=sig[0],mx=sig[0],sum=0;for(var k=0;k<sig.length;k++){var s=sig[k];if(s<mn)mn=s;if(s>mx)mx=s;sum+=s;}var avg=sum/sig.length;var rng=mx-mn;function box(lbl,val,col){return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+val+"</b></div>";}var body="<div class='grid two'>"+box(H.lang==='ar'?'الأقوى':'Best',H.fmt(mx,0)+' dBm','var(--excellent)')+box(H.lang==='ar'?'الأضعف':'Worst',H.fmt(mn,0)+' dBm','var(--weak)')+box(H.lang==='ar'?'المتوسط':'Avg',H.fmt(avg,0)+' dBm','var(--good)')+box(H.lang==='ar'?'المدى':'Range',H.fmt(rng,0)+' dB','var(--mid)')+"</div>";return H.card(T,body,String(sig.length),'signal');}});
  PRO_FEATURES.push({key:"x_cl_snr_headroom",ar:"هامش SNR للعملاء",en:"Client SNR Headroom",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var arr=[];for(var i=0;i<w.length;i++){var r=w[i];var nf=H.num(r.noise_dbm);if(!H.finite(nf)&&r.survey)nf=H.num(r.survey.noise_dbm);var ss=Array.isArray(r.stations)?r.stations:[];for(var j=0;j<ss.length;j++){var s=ss[j];var snr=H.num(s.snr);if(!H.finite(snr)){var sg=H.num(s.signal_dbm);if(H.finite(sg)&&H.finite(nf))snr=sg-nf;}if(H.finite(snr))arr.push({s:s,snr:snr});}}var T=H.lang==='ar'?'هامش SNR للعملاء':'Client SNR Headroom';if(!arr.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');arr.sort(function(a,b){return a.snr-b.snr;});var lim=Math.min(5,arr.length);var rows='';for(var m=0;m<lim;m++){var e=arr[m];var col=e.snr>=30?'var(--excellent)':e.snr>=20?'var(--good)':e.snr>=12?'var(--mid)':'var(--weak)';rows+="<div style='margin:5px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(e.s.ip||e.s.mac||'?')+"</span><span style='color:"+col+"'>"+H.fmt(e.snr,0)+" dB</span></div>"+H.bar(H.clamp(e.snr,0,40),40,col)+"</div>";}return H.card(T,rows,String(arr.length),'signal');}});
  PRO_FEATURES.push({key:"x_tr_iface_throughput",ar:"إنتاجية كل واجهة",en:"Per-Interface Throughput",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var title=H.lang==='ar'?'إنتاجية كل واجهة':'Per-Interface Throughput';if(!ifs.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var max=1;for(var i=0;i<ifs.length;i++){var rx=H.num(ifs[i].rx_bps),tx=H.num(ifs[i].tx_bps);rx=H.finite(rx)?rx:0;tx=H.finite(tx)?tx:0;if(rx>max)max=rx;if(tx>max)max=tx;}var rows='';for(var j=0;j<ifs.length;j++){var f=ifs[j];var r=H.num(f.rx_bps);r=H.finite(r)?r:0;var t=H.num(f.tx_bps);t=H.finite(t)?t:0;rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(f.name||'?')+"</span><span style='color:var(--muted)'>↓"+H.bps(r)+" ↑"+H.bps(t)+"</span></div>"+H.bar(r,max,'var(--good)')+H.bar(t,max,'var(--accent)')+"</div>";}return H.card(title,rows,String(ifs.length),'net');}});
  PRO_FEATURES.push({key:"x_tr_top_talkers",ar:"أكثر العملاء استهلاكاً",en:"Top Talkers",cat:"Traffic & Bandwidth",fn:function(d,H){var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var title=H.lang==='ar'?'أكثر العملاء استهلاكاً':'Top Talkers';var rows=st.filter(function(s){return H.finite(H.num(s.tx_rate))||H.finite(H.num(s.rx_rate));});if(!rows.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'device');function tot(s){return (H.finite(H.num(s.tx_rate))?H.num(s.tx_rate):0)+(H.finite(H.num(s.rx_rate))?H.num(s.rx_rate):0);}rows.sort(function(a,b){return tot(b)-tot(a);});var max=1;for(var k=0;k<rows.length;k++){if(tot(rows[k])>max)max=tot(rows[k]);}var out='';var n=Math.min(rows.length,5);for(var i=0;i<n;i++){var s=rows[i];var v=tot(s);out+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(s.ip||s.mac||'?')+"</span><span style='color:var(--accent)'>"+H.fmt(v,0)+" Mbps</span></div>"+H.bar(v,max,'var(--accent)')+"</div>";}return H.card(title,out,String(rows.length),'device');}});
  PRO_FEATURES.push({key:"x_tr_burst_watch",ar:"كشف الاندفاعات",en:"Burst Detection",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var up=H.num(d.uptime);up=H.finite(up)&&up>0?up:0;var title=H.lang==='ar'?'كشف الاندفاعات':'Burst Detection';if(!ifs.length||!up)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');var rows='';var cnt=0;for(var i=0;i<ifs.length;i++){var f=ifs[i];var cur=(H.finite(H.num(f.rx_bps))?H.num(f.rx_bps):0)+(H.finite(H.num(f.tx_bps))?H.num(f.tx_bps):0);var totb=(H.finite(H.num(f.rx_bytes))?H.num(f.rx_bytes):0)+(H.finite(H.num(f.tx_bytes))?H.num(f.tx_bytes):0);var avg=up>0?totb*8/up:0;var ratio=avg>0?cur/avg:0;var col=ratio<1.5?'var(--excellent)':ratio<3?'var(--good)':ratio<6?'var(--mid)':'var(--weak)';var lab=avg>0?H.fmt(ratio,1)+'x':'—';if(ratio>=3)cnt++;rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(f.name||'?')+"</span><span style='color:"+col+"'>"+lab+"</span></div><div style='font-size:11px;color:var(--muted)'>"+(H.lang==='ar'?'الآن ':'now ')+H.bps(cur)+' · '+(H.lang==='ar'?'متوسط ':'avg ')+H.bps(avg)+"</div></div>";}return H.card(title,rows,cnt?String(cnt):null,'signal');}});
  PRO_FEATURES.push({key:"x_tr_symmetry",ar:"تناظر التحميل/الرفع",en:"RX / TX Symmetry",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{};var rx=H.num(t.rx_bps),tx=H.num(t.tx_bps);var title=H.lang==='ar'?'تناظر التحميل/الرفع':'RX / TX Symmetry';if(!H.finite(rx)&&!H.finite(tx))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');rx=H.finite(rx)?rx:0;tx=H.finite(tx)?tx:0;var tot=rx+tx;var rxp=tot>0?rx/tot*100:0;var txp=tot>0?tx/tot*100:0;var ratio=tx>0?rx/tx:0;var body="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px'><span style='color:var(--good)'>↓ "+H.bps(rx)+"</span><span style='color:var(--accent)'>↑ "+H.bps(tx)+"</span></div>";body+=H.bar(rxp,100,'var(--good)');body+="<div style='display:flex;justify-content:space-between;font-size:11px;color:var(--muted);margin-top:4px'><span>"+H.fmt(rxp,0)+"% RX</span><span>"+H.fmt(txp,0)+"% TX</span></div>";var chip=tx>0?H.fmt(ratio,1)+':1':null;return H.card(title,body,chip,'net');}});
  PRO_FEATURES.push({key:"x_tr_pps_estimate",ar:"الحزم في الثانية (تقديري)",en:"Packets/sec (est.)",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{};var rx=H.num(t.rx_bps),tx=H.num(t.tx_bps);var title=H.lang==='ar'?'الحزم في الثانية (تقديري)':'Packets/sec (est.)';if(!H.finite(rx)&&!H.finite(tx))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');rx=H.finite(rx)?rx:0;tx=H.finite(tx)?tx:0;var AVG=1000;var rpps=rx/8/AVG;var tpps=tx/8/AVG;var tot=rpps+tpps;function fmtp(n){if(n>=1000000)return H.fmt(n/1000000,2)+'M';if(n>=1000)return H.fmt(n/1000,1)+'k';return H.fmt(n,0);}var body="<div style='font-size:22px;font-weight:600;color:var(--accent)'>"+fmtp(tot)+" <small style='font-size:12px;color:var(--muted)'>pps</small></div>";body+="<div style='display:flex;justify-content:space-between;font-size:12px;margin-top:6px'><span style='color:var(--good)'>↓ "+fmtp(rpps)+"</span><span style='color:var(--accent)'>↑ "+fmtp(tpps)+"</span></div>";body+="<div style='font-size:10px;color:var(--muted);margin-top:4px'>"+(H.lang==='ar'?'مقدّر عند 1000 بايت/إطار':'est. @ 1000 B/frame')+"</div>";return H.card(title,body,null,'cpu');}});
  PRO_FEATURES.push({key:"x_tr_iface_share",ar:"حصة النطاق لكل واجهة",en:"Bandwidth Share",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var title=H.lang==='ar'?'حصة النطاق لكل واجهة':'Bandwidth Share';if(!ifs.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var arr=[];var tot=0;for(var i=0;i<ifs.length;i++){var f=ifs[i];var v=(H.finite(H.num(f.rx_bps))?H.num(f.rx_bps):0)+(H.finite(H.num(f.tx_bps))?H.num(f.tx_bps):0);arr.push({name:f.name||'?',v:v});tot+=v;}if(tot<=0)return H.card(title,"<div style='color:var(--muted)'>"+(H.lang==='ar'?'لا حركة':'no traffic')+"</div>",null,'net');arr.sort(function(a,b){return b.v-a.v;});var cols=['var(--accent)','var(--good)','var(--mid)','var(--primary)','var(--weak)'];var rows='';for(var j=0;j<arr.length;j++){var p=arr[j].v/tot*100;var col=cols[j%cols.length];rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(arr[j].name)+"</span><span style='color:"+col+"'>"+H.fmt(p,0)+"%</span></div>"+H.bar(p,100,col)+"</div>";}return H.card(title,rows,null,'net');}});
  PRO_FEATURES.push({key:"x_tr_data_volume",ar:"حجم البيانات التراكمي",en:"Cumulative Data",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var title=H.lang==='ar'?'حجم البيانات التراكمي':'Cumulative Data';if(!ifs.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'storage');var arr=[];var grand=0;for(var i=0;i<ifs.length;i++){var f=ifs[i];var rb=H.finite(H.num(f.rx_bytes))?H.num(f.rx_bytes):0;var tb=H.finite(H.num(f.tx_bytes))?H.num(f.tx_bytes):0;arr.push({name:f.name||'?',rb:rb,tb:tb,tot:rb+tb});grand+=rb+tb;}arr.sort(function(a,b){return b.tot-a.tot;});var max=1;for(var k=0;k<arr.length;k++){if(arr[k].tot>max)max=arr[k].tot;}var rows='';for(var j=0;j<arr.length;j++){rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(arr[j].name)+"</span><span style='color:var(--muted)'>↓"+H.bytes(arr[j].rb)+" ↑"+H.bytes(arr[j].tb)+"</span></div>"+H.bar(arr[j].tot,max,'var(--primary)')+"</div>";}return H.card(title,rows,H.bytes(grand),'storage');}});
  PRO_FEATURES.push({key:"x_tr_link_saturation",ar:"إشباع الوصلة",en:"Link Saturation",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{};var rx=H.num(t.rx_bps),tx=H.num(t.tx_bps);var title=H.lang==='ar'?'إشباع الوصلة':'Link Saturation';if(!H.finite(rx)&&!H.finite(tx))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');rx=H.finite(rx)?rx:0;tx=H.finite(tx)?tx:0;var tot=rx+tx;var CAP=1000000000;var pct=H.clamp(tot/CAP*100,0,100);var col=pct<40?'var(--excellent)':pct<70?'var(--good)':pct<90?'var(--mid)':'var(--weak)';var big=H.bps(tot);var sub1='↓ '+H.bps(rx);var sub2='↑ '+H.bps(tx);var body=H.gauge(H.lang==='ar'?'من 1 جيجابت':'of 1 Gbps',big,sub1,sub2,pct,col,'net');return H.card(title,body,H.fmt(pct,0)+'%','net');}});
  PRO_FEATURES.push({key:"x_lq_latency_grade",ar:"تقييم زمن الوصول",en:"Gateway RTT Grade",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'تقييم زمن الوصول':'Gateway RTT Grade';var L=H.num(d.latency_ms);if(!H.finite(L))return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');L=H.clamp(L,0,10000);var col=L<10?'var(--excellent)':L<30?'var(--good)':L<60?'var(--mid)':'var(--weak)';var txt=L<10?(H.lang==='ar'?'ممتاز':'Excellent'):L<30?(H.lang==='ar'?'جيد':'Good'):L<60?(H.lang==='ar'?'متوسط':'Fair'):(H.lang==='ar'?'ضعيف':'Poor');var pct=H.clamp(100-L,0,100);var gw=(d.backhaul&&d.backhaul.gateway)?d.backhaul.gateway:(H.lang==='ar'?'البوابة':'gateway');var body=H.gauge('RTT',H.fmt(L,1)+' ms',txt,H.esc(String(gw)),pct,col,'net');return H.card(t,body,txt,'net');}});
  PRO_FEATURES.push({key:"x_lq_jitter_est",ar:"تقدير التذبذب",en:"Jitter Estimate",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'تقدير التذبذب':'Jitter Estimate';var L=H.num(d.latency_ms);var w=Array.isArray(d.wifi)?d.wifi:[];var bs=0,bn=0;for(var i=0;i<w.length;i++){var sv=w[i].survey||{};var b=H.num(sv.busy_pct);if(H.finite(b)){bs+=H.clamp(b,0,100);bn++;}}var busy=bn?bs/bn:null;if(!H.finite(L)&&busy==null)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var base=H.finite(L)?H.clamp(L,0,10000):20;var jit=H.clamp(base*0.12+(busy!=null?busy*0.05:0),0,base||1);var col=jit<2?'var(--excellent)':jit<8?'var(--good)':jit<20?'var(--mid)':'var(--weak)';var txt=jit<2?(H.lang==='ar'?'مستقر':'Stable'):jit<8?(H.lang==='ar'?'جيد':'Good'):jit<20?(H.lang==='ar'?'متغير':'Variable'):(H.lang==='ar'?'غير مستقر':'Unstable');var pct=H.clamp(100-jit*3,0,100);var sub=(H.lang==='ar'?'تقديري':'estimated')+(busy!=null?' · '+(H.lang==='ar'?'انشغال ':'busy ')+H.fmt(busy,0)+'%':'');var body=H.gauge(H.lang==='ar'?'التذبذب':'Jitter','≈ '+H.fmt(jit,1)+' ms',txt,sub,pct,col,'signal');return H.card(t,body,txt,'signal');}});
  PRO_FEATURES.push({key:"x_lq_link_eff",ar:"كفاءة الوصلة",en:"Link Efficiency",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'كفاءة الوصلة':'Link Efficiency';var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var sum=0,n=0;for(var i=0;i<st.length;i++){var tx=H.num(st[i].tx_rate),ex=H.num(st[i].expected_mbps);if(H.finite(tx)&&H.finite(ex)&&ex>0){sum+=H.clamp(tx/ex*100,0,100);n++;}}if(!n)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var avg=sum/n;var col=avg>=85?'var(--excellent)':avg>=65?'var(--good)':avg>=45?'var(--mid)':'var(--weak)';var txt=avg>=85?(H.lang==='ar'?'مثالي':'Optimal'):avg>=65?(H.lang==='ar'?'جيد':'Good'):avg>=45?(H.lang==='ar'?'مقبول':'OK'):(H.lang==='ar'?'ضعيف':'Poor');var sub=(H.lang==='ar'?'فعلي مقابل متوقع':'actual vs expected PHY');var body=H.gauge(H.lang==='ar'?'الكفاءة':'Efficiency',H.fmt(avg,0)+'%',txt,sub,H.clamp(avg,0,100),col,'net');return H.card(t,body,String(n),'net');}});
  PRO_FEATURES.push({key:"x_lq_airtime_fair",ar:"عدالة زمن الهواء",en:"Airtime Fairness",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'عدالة زمن الهواء':'Airtime Fairness';var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var r=[];for(var i=0;i<st.length;i++){var tx=H.num(st[i].tx_rate);if(H.finite(tx)&&tx>0)r.push(tx);}if(r.length<2)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');var sum=0,sq=0;for(var j=0;j<r.length;j++){sum+=r[j];sq+=r[j]*r[j];}if(sq<=0)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');var fair=(sum*sum)/(r.length*sq);var pct=H.clamp(fair*100,0,100);var col=pct>=80?'var(--excellent)':pct>=60?'var(--good)':pct>=40?'var(--mid)':'var(--weak)';var txt=pct>=80?(H.lang==='ar'?'متوازن':'Balanced'):pct>=60?(H.lang==='ar'?'جيد':'Good'):pct>=40?(H.lang==='ar'?'متفاوت':'Skewed'):(H.lang==='ar'?'غير عادل':'Unfair');var sub=(H.lang==='ar'?'مؤشر جين · ':'Jain index · ')+r.length+(H.lang==='ar'?' عميل':' clients');var body=H.gauge(H.lang==='ar'?'العدالة':'Fairness',H.fmt(pct,0)+'%',txt,sub,pct,col,'signal');return H.card(t,body,txt,'signal');}});
  PRO_FEATURES.push({key:"x_lq_ceiling_1200",ar:"قرب سقف 1200",en:"1200 Mbps Ceiling",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'قرب سقف 1200':'1200 Mbps Ceiling';var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var best=null,bs=null;for(var i=0;i<st.length;i++){var tx=H.num(st[i].tx_rate);if(H.finite(tx)&&(best==null||tx>best)){best=tx;bs=st[i];}}if(best==null)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var CEIL=1200;var pct=H.clamp(best/CEIL*100,0,100);var col=pct>=85?'var(--excellent)':pct>=60?'var(--good)':pct>=35?'var(--mid)':'var(--weak)';var txt=H.fmt(pct,0)+'% '+(H.lang==='ar'?'من السقف':'of cap');var who=bs?H.esc(bs.ip||bs.mac||'?'):'?';var sub=(H.lang==='ar'?'أفضل وصلة · ':'best link · ')+who;var body=H.gauge(H.lang==='ar'?'الذروة':'Peak PHY',H.fmt(best,0)+' Mbps',txt,sub,pct,col,'net');return H.card(t,body,'HE80·2SS','net');}});
  PRO_FEATURES.push({key:"x_lq_phy_eff_rank",ar:"ترتيب كفاءة العملاء",en:"Per-Client PHY Efficiency",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'ترتيب كفاءة العملاء':'Per-Client PHY Efficiency';var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var arr=[];for(var i=0;i<st.length;i++){var tx=H.num(st[i].tx_rate),ex=H.num(st[i].expected_mbps);if(H.finite(tx)&&H.finite(ex)&&ex>0){arr.push({s:st[i],e:H.clamp(tx/ex*100,0,150),tx:tx});}}if(!arr.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');arr.sort(function(a,b){return b.e-a.e;});var rows='';var lim=Math.min(arr.length,6);for(var k=0;k<lim;k++){var it=arr[k];var col=it.e>=85?'var(--excellent)':it.e>=65?'var(--good)':it.e>=45?'var(--mid)':'var(--weak)';var who=H.esc(it.s.ip||it.s.mac||'?');rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+who+"</span><span style='color:"+col+"'>"+H.fmt(it.e,0)+'% · '+H.fmt(it.tx,0)+"M</span></div>"+H.bar(H.clamp(it.e,0,100),100,col)+'</div>';}return H.card(t,rows,String(arr.length),'net');}});
  PRO_FEATURES.push({key:"x_lq_rtt_budget",ar:"ميزانية زمن الوصول",en:"RTT Budget",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'ميزانية زمن الوصول':'RTT Budget';var L=H.num(d.latency_ms);var bh=d.backhaul||{};var online=bh.online===true;if(!H.finite(L))return H.card(t,"<div style='color:var(--muted)'>—</div>",online?(H.lang==='ar'?'متصل':'up'):null,'net');var BUD=100;L=H.clamp(L,0,BUD*3);var used=H.clamp(L/BUD*100,0,100);var col=L<30?'var(--excellent)':L<60?'var(--good)':L<BUD?'var(--mid)':'var(--weak)';var left=H.clamp(BUD-L,0,BUD);var body="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px'><span>"+(H.lang==='ar'?'المستخدم':'used')+"</span><span style='color:"+col+"'>"+H.fmt(L,1)+' / '+BUD+" ms</span></div>"+H.bar(used,100,col)+"<div style='display:flex;justify-content:space-between;font-size:11px;margin-top:6px;color:var(--muted)'><span>"+(H.lang==='ar'?'المتبقي':'headroom')+' '+H.fmt(left,0)+"ms</span><span>"+(online?(H.lang==='ar'?'الرابط نشط':'backhaul up'):(H.lang==='ar'?'الرابط منقطع':'backhaul down'))+"</span></div>";return H.card(t,body,online?(H.lang==='ar'?'متصل':'up'):(H.lang==='ar'?'منقطع':'down'),'net');}});
  PRO_FEATURES.push({key:"x_lq_stability_score",ar:"مؤشر استقرار الوصلة",en:"Link Stability Score",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'مؤشر استقرار الوصلة':'Link Stability Score';var parts=[];var L=H.num(d.latency_ms);if(H.finite(L)){parts.push(H.clamp(100-H.clamp(L,0,100),0,100));}var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var ss=0,sn=0;for(var i=0;i<st.length;i++){var sn2=H.num(st[i].snr);if(!H.finite(sn2)){var sig=H.num(st[i].signal_dbm);if(H.finite(sig))sn2=sig+95;}if(H.finite(sn2)){ss+=H.clamp(H.signalPct('snr',sn2),0,100);sn++;}}if(sn)parts.push(ss/sn);var es=0,en=0;for(var j=0;j<st.length;j++){var tx=H.num(st[j].tx_rate),ex=H.num(st[j].expected_mbps);if(H.finite(tx)&&H.finite(ex)&&ex>0){es+=H.clamp(tx/ex*100,0,100);en++;}}if(en)parts.push(es/en);if(!parts.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');var sum=0;for(var k=0;k<parts.length;k++)sum+=parts[k];var score=sum/parts.length;var col=score>=80?'var(--excellent)':score>=60?'var(--good)':score>=40?'var(--mid)':'var(--weak)';var txt=score>=80?(H.lang==='ar'?'ممتاز':'Excellent'):score>=60?(H.lang==='ar'?'جيد':'Good'):score>=40?(H.lang==='ar'?'متوسط':'Fair'):(H.lang==='ar'?'ضعيف':'Poor');var sub=(H.lang==='ar'?'من ':'from ')+parts.length+(H.lang==='ar'?' مقاييس':' metrics');var body=H.gauge(H.lang==='ar'?'الاستقرار':'Stability',H.fmt(score,0)+'/100',txt,sub,H.clamp(score,0,100),col,'signal');return H.card(t,body,txt,'signal');}});
  PRO_FEATURES.push({key:"x_se_open_ssid_audit",ar:"تدقيق الشبكات المفتوحة",en:"Open SSID Audit",cat:"Security & Threats",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var T=H.lang==='ar'?'تدقيق الشبكات المفتوحة':'Open SSID Audit';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var rows='';var open=0;for(var i=0;i<w.length;i++){var r=w[i];var enc=(r.encryption||'').toString().toLowerCase();var isOpen=enc===''||enc==='none';if(isOpen)open++;var col=isOpen?'var(--weak)':'var(--excellent)';var lab=isOpen?(H.lang==='ar'?'مفتوحة':'OPEN'):(H.lang==='ar'?'مشفّرة':'secured');rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(r.ssid||r.band||'?')+"</span><span style='color:"+col+"'>"+lab+"</span></div>";}var chip=open>0?String(open)+(H.lang==='ar'?' مفتوحة':' open'):(H.lang==='ar'?'آمن':'ok');return H.card(T,rows,chip,'shield');}});
  PRO_FEATURES.push({key:"x_se_wpa_posture",ar:"وضع WPA و PMF",en:"WPA / PMF Posture",cat:"Security & Threats",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var T=H.lang==='ar'?'وضع WPA و PMF':'WPA / PMF Posture';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var rows='';for(var i=0;i<w.length;i++){var r=w[i];var sl=H.secLevel(r.encryption||'');var col=(sl&&sl.col)?sl.col:'var(--muted)';var txt=(sl&&sl.txt)?sl.txt:'—';rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(r.band||'?')+"</span><span style='color:"+col+"'>"+H.esc(txt)+"</span></div><div style='font-size:11px;color:var(--muted)'>"+H.esc(String(r.encryption||'none'))+"</div></div>";}return H.card(T,rows,null,'shield');}});
  PRO_FEATURES.push({key:"x_se_rogue_neighbors",ar:"مراقبة الجيران",en:"Rogue Neighbor Watch",cat:"Security & Threats",fn:function(d,H){var n=Array.isArray(d.neighbors)?d.neighbors:(Array.isArray(d.lldp)?d.lldp:[]);var T=H.lang==='ar'?'مراقبة الجيران':'Rogue Neighbor Watch';if(!n.length)return H.card(T,"<div style='color:var(--muted)'>"+(H.lang==='ar'?'لا جيران':'no neighbors')+"</div>",'0','wifi');var cnt=n.length;var col=cnt<3?'var(--excellent)':cnt<8?'var(--mid)':'var(--weak)';var big=String(cnt);var sub=H.lang==='ar'?'أجهزة مجاورة':'nearby devices';var sub2=cnt>=8?(H.lang==='ar'?'ازدحام مرتفع':'crowded'):(H.lang==='ar'?'ضمن الحدود':'within limits');var body=H.gauge(H.lang==='ar'?'الجيران':'neighbors',big,sub,sub2,H.clamp(cnt*10,0,100),col,'wifi');return H.card(T,body,String(cnt),'wifi');}});
  PRO_FEATURES.push({key:"x_se_new_device_watch",ar:"مراقبة أجهزة جديدة",en:"New Device Watch",cat:"Security & Threats",fn:function(d,H){var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var T=H.lang==='ar'?'مراقبة أجهزة جديدة':'New Device Watch';if(!st.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'device');var recent=[];for(var i=0;i<st.length;i++){var c=H.num(st[i].conn_s);if(H.finite(c)&&c<600){recent.push(st[i]);}}if(!recent.length)return H.card(T,"<div style='color:var(--excellent)'>"+(H.lang==='ar'?'لا أجهزة جديدة':'no new joins')+"</div>",'0','device');recent.sort(function(a,b){return H.num(a.conn_s)-H.num(b.conn_s);});var rows='';for(var j=0;j<recent.length&&j<5;j++){var s=recent[j];rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:5px 0'><span>"+H.esc(s.ip||s.mac||'?')+"</span><span style='color:var(--mid)'>"+H.uptime(H.finite(H.num(s.conn_s))?H.num(s.conn_s):0)+"</span></div>";}return H.card(T,rows,String(recent.length),'device');}});
  PRO_FEATURES.push({key:"x_se_client_isolation",ar:"عزل العملاء",en:"Client Isolation",cat:"Security & Threats",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var T=H.lang==='ar'?'عزل العملاء':'Client Isolation';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var rows='';var totalPairs=0;for(var i=0;i<w.length;i++){var r=w[i];var n=(Array.isArray(r.stations)?r.stations:[]).length;var pairs=n>1?(n*(n-1)/2):0;totalPairs+=pairs;var col=pairs===0?'var(--excellent)':pairs<10?'var(--mid)':'var(--weak)';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(r.band||'?')+' · '+n+(H.lang==='ar'?' عميل':' cli')+"</span><span style='color:"+col+"'>"+pairs+(H.lang==='ar'?' مسار':' paths')+"</span></div>";}var note="<div style='font-size:11px;color:var(--muted);margin-top:4px'>"+(H.lang==='ar'?'مسارات رؤية محتملة بين العملاء':'potential peer-visibility paths')+"</div>";return H.card(T,rows+note,String(totalPairs),'shield');}});
  PRO_FEATURES.push({key:"x_se_mgmt_exposure",ar:"تعرّض الإدارة",en:"Management Exposure",cat:"Security & Threats",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var T=H.lang==='ar'?'تعرّض الإدارة':'Management Exposure';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'net');var openClients=0;var openR=0;for(var i=0;i<w.length;i++){var r=w[i];var enc=(r.encryption||'').toString().toLowerCase();if(enc===''||enc==='none'){openR++;var c=H.num(r.clients);if(!H.finite(c)){c=(Array.isArray(r.stations)?r.stations:[]).length;}openClients+=c;}}var score=H.clamp(openR*30+openClients*5,0,100);var col=score<20?'var(--excellent)':score<50?'var(--mid)':'var(--weak)';var big=openR>0?(H.lang==='ar'?'مكشوف':'EXPOSED'):(H.lang==='ar'?'محمي':'GUARDED');var sub=(H.lang==='ar'?'شبكات مفتوحة: ':'open nets: ')+openR;var sub2=(H.lang==='ar'?'عملاء مكشوفون: ':'exposed clients: ')+openClients;return H.card(T,H.gauge(H.lang==='ar'?'سطح الإدارة':'mgmt surface',big,sub,sub2,score,col,'net'),null,'net');}});
  PRO_FEATURES.push({key:"x_se_enc_coverage",ar:"تغطية التشفير",en:"Encryption Coverage",cat:"Security & Threats",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var T=H.lang==='ar'?'تغطية التشفير':'Encryption Coverage';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var tot=0,sec=0;for(var i=0;i<w.length;i++){var r=w[i];var c=H.num(r.clients);if(!H.finite(c)){c=(Array.isArray(r.stations)?r.stations:[]).length;}tot+=c;var enc=(r.encryption||'').toString().toLowerCase();if(!(enc===''||enc==='none')){sec+=c;}}if(tot<=0)return H.card(T,"<div style='color:var(--muted)'>"+(H.lang==='ar'?'لا عملاء':'no clients')+"</div>",null,'shield');var pct=H.clamp(sec/tot*100,0,100);var col=pct>=99?'var(--excellent)':pct>=60?'var(--mid)':'var(--weak)';var body="<div style='font-size:20px;font-weight:700;color:"+col+"'>"+H.fmt(pct,0)+"%</div>"+H.bar(pct,100,col)+"<div style='font-size:11px;color:var(--muted);margin-top:4px'>"+sec+" / "+tot+(H.lang==='ar'?' عميل مشفّر':' clients encrypted')+"</div>";return H.card(T,body,H.fmt(pct,0)+'%','shield');}});
  PRO_FEATURES.push({key:"x_se_posture_score",ar:"درجة الأمان",en:"Security Posture",cat:"Security & Threats",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var T=H.lang==='ar'?'درجة الأمان':'Security Posture';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var score=100;var openR=0;for(var i=0;i<w.length;i++){var r=w[i];var enc=(r.encryption||'').toString().toLowerCase();if(enc===''||enc==='none'){openR++;score-=35;}}var nb=Array.isArray(d.neighbors)?d.neighbors.length:(Array.isArray(d.lldp)?d.lldp.length:0);if(nb>8)score-=10;score=H.clamp(score,0,100);var col=score>=80?'var(--excellent)':score>=50?'var(--mid)':'var(--weak)';var grade=score>=80?(H.lang==='ar'?'قوي':'STRONG'):score>=50?(H.lang==='ar'?'متوسط':'FAIR'):(H.lang==='ar'?'ضعيف':'WEAK');var sub=(H.lang==='ar'?'شبكات مفتوحة: ':'open SSIDs: ')+openR;return H.card(T,H.gauge(H.lang==='ar'?'التقييم':'rating',grade,sub,H.fmt(score,0)+'/100',score,col,'shield'),H.fmt(score,0),'shield');}});
  PRO_FEATURES.push({key:"x_sy_resource_triad",ar:"موارد النظام",en:"System Resources",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'موارد النظام':'System Resources';var cpu=d.cpu||{};var mem=d.mem||{};var stg=d.storage||{};var cp=H.num(cpu.percent);var mt=H.num(mem.total);var ma=H.num(mem.available);var stt=H.num(stg.total);var stu=H.num(stg.used);var cpct=H.finite(cp)?H.clamp(cp,0,100):null;var mpct=(H.finite(mt)&&mt>0&&H.finite(ma))?H.clamp((mt-ma)/mt*100,0,100):null;var spct=(H.finite(stt)&&stt>0&&H.finite(stu))?H.clamp(stu/stt*100,0,100):null;if(cpct==null&&mpct==null&&spct==null)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');function c(p){return p==null?'var(--muted)':(p<50?'var(--excellent)':p<75?'var(--good)':p<90?'var(--mid)':'var(--weak)');}function row(lab,pct){var col=c(pct);return "<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+lab+"</span><span style='color:"+col+"'>"+(pct==null?'—':H.fmt(pct,0)+'%')+"</span></div>"+H.bar(pct||0,100,col)+"</div>";}var body=row(ar?'المعالج':'CPU',cpct)+row(ar?'الذاكرة':'RAM',mpct)+row(ar?'التخزين':'Flash',spct);return H.card(title,body,null,'cpu');}});
  PRO_FEATURES.push({key:"x_sy_thermal_headroom",ar:"هامش الحرارة",en:"Thermal Headroom",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'هامش الحرارة':'Thermal Headroom';var t=H.num(d.temperature_c);if(!H.finite(t))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');var ceil=105;var head=ceil-t;var pct=H.clamp(t/ceil*100,0,100);var col=t<55?'var(--excellent)':t<70?'var(--good)':t<85?'var(--mid)':'var(--weak)';var body=H.gauge(ar?'المعالج':'SoC',H.fmt(t,0)+'°C',(ar?'هامش ':'headroom ')+H.fmt(head,0)+'°C',(ar?'الحد ':'ceiling ')+ceil+'°C',pct,col,'cpu');return H.card(title,body,H.fmt(head,0)+'°C','cpu');}});
  PRO_FEATURES.push({key:"x_sy_uptime_milestone",ar:"إنجاز التشغيل",en:"Uptime Milestone",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'إنجاز التشغيل':'Uptime Milestone';var u=H.num(d.uptime);if(!H.finite(u)||u<0)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var days=u/86400;var ms=[1,7,30,90,180,365];var next=null,prev=0;for(var i=0;i<ms.length;i++){if(days<ms[i]){next=ms[i];break;}prev=ms[i];}var body="<div style='font-size:22px;font-weight:700'>"+H.esc(H.uptime(u))+"</div>";if(next==null){body+="<div style='color:var(--excellent);font-size:12px;margin-top:6px'>"+(ar?'تجاوز سنة كاملة':'Over a full year')+"</div>";return H.card(title,body,'365d+','net');}var span=next-prev;var into=days-prev;var pct=span>0?H.clamp(into/span*100,0,100):0;var col=pct<50?'var(--good)':pct<85?'var(--mid)':'var(--excellent)';body+="<div style='font-size:12px;color:var(--muted);margin:6px 0'>"+(ar?'التالي':'Next')+': '+next+(ar?' يوم':'d')+"</div>"+H.bar(pct,100,col);return H.card(title,body,H.fmt(days,0)+'d','net');}});
  PRO_FEATURES.push({key:"x_sy_load_verdict",ar:"حكم متوسط الحِمل",en:"Load Verdict",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'حكم متوسط الحِمل':'Load Verdict';var l=Array.isArray(d.load)?d.load:[];var cores=H.num((d.cpu||{}).cores);if(!H.finite(cores)||cores<=0)cores=1;var l1=H.num(l[0]),l5=H.num(l[1]),l15=H.num(l[2]);if(!H.finite(l1)&&!H.finite(l5)&&!H.finite(l15))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');function seg(lab,v){if(!H.finite(v))return "<div class='traffic-box'><span>"+lab+"</span><b style='color:var(--muted)'>—</b></div>";var per=v/cores;var col=per<0.7?'var(--excellent)':per<1?'var(--good)':per<1.5?'var(--mid)':'var(--weak)';return "<div class='traffic-box'><span>"+lab+"</span><b style='color:"+col+"'>"+H.fmt(v,2)+"</b><small class='muted'>"+H.fmt(per*100,0)+"%/core</small></div>";}var body="<div class='grid three'>"+seg('1m',l1)+seg('5m',l5)+seg('15m',l15)+"</div>";var v1=H.finite(l1)?l1/cores:null;var chip=v1==null?null:(v1<0.7?(ar?'خفيف':'Light'):v1<1?(ar?'طبيعي':'Normal'):v1<1.5?(ar?'مرتفع':'Busy'):(ar?'مُحمّل':'Overloaded'));return H.card(title,body,chip,'cpu');}});
  PRO_FEATURES.push({key:"x_sy_mem_pressure",ar:"ضغط الذاكرة",en:"Memory Pressure",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'ضغط الذاكرة':'Memory Pressure';var m=d.mem||{};var mt=H.num(m.total),ma=H.num(m.available);if(!H.finite(mt)||mt<=0||!H.finite(ma))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'ram');var used=mt-ma;if(used<0)used=0;var pct=H.clamp(used/mt*100,0,100);var col=pct<60?'var(--excellent)':pct<80?'var(--good)':pct<92?'var(--mid)':'var(--weak)';var lvl=pct<60?(ar?'مريح':'Comfortable'):pct<80?(ar?'معتدل':'Moderate'):pct<92?(ar?'مرتفع':'Elevated'):(ar?'حرج':'Critical');var body=H.gauge(ar?'مستخدم':'Used',H.fmt(pct,0)+'%',H.bytes(used)+' / '+H.bytes(mt),(ar?'متاح ':'free ')+H.bytes(ma),pct,col,'ram');return H.card(title,body,lvl,'ram');}});
  PRO_FEATURES.push({key:"x_sy_flash_capacity",ar:"سعة التخزين",en:"Flash Storage",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'سعة التخزين':'Flash Storage';var s=d.storage||{};var tt=H.num(s.total),us=H.num(s.used),av=H.num(s.available);if(!H.finite(tt)||tt<=0)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'storage');if(!H.finite(us)&&H.finite(av))us=tt-av;if(!H.finite(us))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'storage');if(us<0)us=0;var pct=H.clamp(us/tt*100,0,100);var free=H.finite(av)?av:tt-us;var col=pct<70?'var(--excellent)':pct<85?'var(--good)':pct<95?'var(--mid)':'var(--weak)';var chip=(H.finite(free)&&free<(tt*0.1))?(ar?'شبه ممتلئ':'Nearly full'):null;var body=H.gauge(ar?'مستخدم':'Used',H.fmt(pct,0)+'%',H.bytes(us)+' / '+H.bytes(tt),(ar?'حر ':'free ')+H.bytes(free),pct,col,'storage');return H.card(title,body,chip,'storage');}});
  PRO_FEATURES.push({key:"x_sy_service_rollup",ar:"حالة الخدمات",en:"Service Health",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'حالة الخدمات':'Service Health';var h=d.health;if(!h||typeof h!=='object')return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'shield');var keys=[];for(var k in h){if(Object.prototype.hasOwnProperty.call(h,k))keys.push(k);}if(!keys.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'shield');function ok(v){if(v===true)return true;if(v===false)return false;if(typeof v==='number')return H.finite(v)&&v>0;if(typeof v==='string'){var s=v.toLowerCase();return s==='ok'||s==='up'||s==='running'||s==='online'||s==='good'||s==='active'||s==='healthy';}return !!v;}var good=0,rows='';for(var i=0;i<keys.length;i++){var isok=ok(h[keys[i]]);if(isok)good++;var col=isok?'var(--excellent)':'var(--weak)';var txt=isok?(ar?'يعمل':'up'):(ar?'متوقف':'down');rows+="<div style='display:flex;justify-content:space-between;align-items:center;font-size:12px;margin:5px 0'><span>"+H.esc(keys[i])+"</span><span style='color:"+col+"'>●&nbsp;"+txt+"</span></div>";}return H.card(title,rows,good+'/'+keys.length,'shield');}});
  PRO_FEATURES.push({key:"x_sy_stability_score",ar:"مؤشر الاستقرار",en:"Stability Score",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'مؤشر الاستقرار':'Stability Score';var cp=H.num((d.cpu||{}).percent);var m=d.mem||{};var mt=H.num(m.total),ma=H.num(m.available);var t=H.num(d.temperature_c);var l=Array.isArray(d.load)?d.load:[];var l1=H.num(l[0]);var cores=H.num((d.cpu||{}).cores);if(!H.finite(cores)||cores<=0)cores=1;var scores=[];if(H.finite(cp))scores.push(H.clamp(100-cp,0,100));if(H.finite(mt)&&mt>0&&H.finite(ma))scores.push(H.clamp(ma/mt*100,0,100));if(H.finite(t))scores.push(H.clamp((105-t)/105*100,0,100));if(H.finite(l1))scores.push(H.clamp(100-(l1/cores*100),0,100));if(!scores.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'shield');var sum=0;for(var i=0;i<scores.length;i++){sum+=scores[i];}var avg=sum/scores.length;var col=avg>=80?'var(--excellent)':avg>=60?'var(--good)':avg>=40?'var(--mid)':'var(--weak)';var q=avg>=80?(ar?'ممتاز':'Excellent'):avg>=60?(ar?'جيد':'Good'):avg>=40?(ar?'متوسط':'Fair'):(ar?'ضعيف':'Poor');var body=H.gauge(ar?'النتيجة':'Score',H.fmt(avg,0),q,(ar?'من ':'of ')+scores.length+(ar?' مقاييس':' metrics'),avg,col,'shield');return H.card(title,body,q,'shield');}});
  PRO_FEATURES.push({key:"x_tp_lldp_map",ar:"خريطة الجيران LLDP",en:"LLDP Neighbors",cat:"Topology & Discovery",fn:function(d,H){var n=Array.isArray(d.lldp)?d.lldp:(Array.isArray(d.neighbors)?d.neighbors:[]);var t=H.lang==='ar'?'خريطة الجيران LLDP':'LLDP Neighbors';if(!n.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='';for(var i=0;i<n.length&&i<8;i++){var x=n[i]||{};var nm=x.name||x.host||x.chassis||x.system||x.mac||'?';var pt=x.port||x.iface||x.port_id||'';var ip=x.ip||x.mgmt_ip||'';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(String(nm))+(pt?" <small class='muted'>· "+H.esc(String(pt))+"</small>":"")+"</span><span style='color:var(--muted)'>"+H.esc(String(ip))+"</span></div>";}return H.card(t,rows,String(n.length),'net');}});
  PRO_FEATURES.push({key:"x_tp_radio_ports",ar:"عملاء كل راديو",en:"Clients per Radio",cat:"Topology & Discovery",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'عملاء كل راديو':'Clients per Radio';if(!w.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'wifi');var mx=1,cnts=[];for(var i=0;i<w.length;i++){var r=w[i]||{};var c=H.num(r.clients);if(!H.finite(c)){var st=Array.isArray(r.stations)?r.stations:[];c=st.length;}c=H.finite(c)?c:0;cnts.push(c);if(c>mx)mx=c;}var rows='',tot=0;for(var j=0;j<w.length;j++){var rr=w[j]||{};var cc=cnts[j];tot+=cc;var lab=(rr.iface||rr.band||'?');rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(String(lab))+"</span><span>"+cc+"</span></div>"+H.bar(cc,mx,'var(--accent)')+"</div>";}return H.card(t,rows,String(tot),'wifi');}});
  PRO_FEATURES.push({key:"x_tp_wired_wifi",ar:"سلكي مقابل لاسلكي",en:"Wired vs Wi-Fi",cat:"Topology & Discovery",fn:function(d,H){var dv=H.mergeDevices(d);dv=Array.isArray(dv)?dv:[];var t=H.lang==='ar'?'سلكي مقابل لاسلكي':'Wired vs Wi-Fi';if(!dv.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var wired=0,wifi=0;for(var i=0;i<dv.length;i++){var s=dv[i]||{};var ty=String(s.type||'').toLowerCase();if(ty.indexOf('wire')>=0||ty==='eth'||ty==='lan'){wired++;}else if(ty.indexOf('wif')>=0||ty.indexOf('wl')>=0||ty.indexOf('wireless')>=0){wifi++;}else if(H.finite(H.num(s.signal_dbm))||s.band){wifi++;}else{wired++;}}var tot=wired+wifi;function box(v,lbl,col){var p=tot>0?(v/tot*100):0;return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+v+"</b><small class='muted'>"+H.fmt(p,0)+"%</small></div>";}var body="<div class='grid two'>"+box(wired,H.lang==='ar'?'سلكي':'Wired','var(--good)')+box(wifi,H.lang==='ar'?'لاسلكي':'Wi-Fi','var(--accent)')+"</div>"+H.bar(wifi,tot,'var(--accent)');return H.card(t,body,String(tot),'net');}});
  PRO_FEATURES.push({key:"x_tp_uplink_quality",ar:"جودة الوصلة الصاعدة",en:"Uplink Quality",cat:"Topology & Discovery",fn:function(d,H){var b=d.backhaul||{};var t=H.lang==='ar'?'جودة الوصلة الصاعدة':'Uplink Quality';var on=b.online;var lat=H.num(d.latency_ms);var gw=b.gateway||'';var dev=b.device||'';if(on==null&&!H.finite(lat)&&!gw)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var col=on===false?'var(--weak)':(H.finite(lat)?(lat<20?'var(--excellent)':lat<60?'var(--good)':lat<120?'var(--mid)':'var(--weak)'):'var(--good)');var stTxt=on===false?(H.lang==='ar'?'غير متصل':'Offline'):(H.lang==='ar'?'متصل':'Online');var latTxt=H.finite(lat)?H.fmt(lat,0)+' ms':'—';var body="<div style='display:flex;justify-content:space-between;align-items:center;margin:6px 0'><b style='color:"+col+"'>"+stTxt+"</b><span style='color:"+col+"'>"+latTxt+"</span></div>";body+="<div style='font-size:12px;color:var(--muted)'>"+(H.lang==='ar'?'البوابة':'Gateway')+": "+H.esc(String(gw||'—'))+"</div>";body+="<div style='font-size:12px;color:var(--muted)'>"+(H.lang==='ar'?'المنفذ':'Device')+": "+H.esc(String(dev||'—'))+"</div>";return H.card(t,body,on===false?null:stTxt,'net');}});
  PRO_FEATURES.push({key:"x_tp_ap_role",ar:"دور الجهاز",en:"Device Role",cat:"Topology & Discovery",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var b=d.backhaul||{};var t=H.lang==='ar'?'دور الجهاز':'Device Role';if(!w.length&&b.online==null)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'wifi');var role=(b.online?(H.lang==='ar'?'نقطة وصول (موصولة)':'Access Point (uplinked)'):(H.lang==='ar'?'نقطة وصول':'Access Point'));var ssids='';for(var i=0;i<w.length;i++){var r=w[i]||{};var ss=r.ssid||'?';ssids+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:5px 0'><span>"+H.esc(String(ss))+"</span><small class='muted'>"+H.esc(String(r.band||''))+"</small></div>";}var body="<div style='font-size:15px;font-weight:600;color:var(--accent);margin-bottom:6px'>"+role+"</div>"+(ssids||"<div style='color:var(--muted)'>—</div>");return H.card(t,body,'AP','wifi');}});
  PRO_FEATURES.push({key:"x_tp_bridge_health",ar:"صحة أعضاء الجسر",en:"Bridge Member Health",cat:"Topology & Discovery",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var t=H.lang==='ar'?'صحة أعضاء الجسر':'Bridge Member Health';if(!ifs.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='',bad=0;for(var i=0;i<ifs.length&&i<8;i++){var f=ifs[i]||{};var e=(H.num(f.rx_errors)||0)+(H.num(f.tx_errors)||0);var dr=(H.num(f.rx_dropped)||0)+(H.num(f.tx_dropped)||0);e=H.finite(e)?e:0;dr=H.finite(dr)?dr:0;var tot=e+dr;var col=tot===0?'var(--excellent)':tot<10?'var(--mid)':'var(--weak)';if(tot>0)bad++;var txt=tot===0?(H.lang==='ar'?'سليم':'OK'):(H.lang==='ar'?(e+' أخطاء '+dr+' مفقود'):(e+' err '+dr+' drop'));rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(String(f.name||'?'))+"</span><span style='color:"+col+"'>"+txt+"</span></div>";}return H.card(t,rows,bad>0?String(bad):null,'net');}});
  PRO_FEATURES.push({key:"x_tp_discovery_count",ar:"ملخص الاكتشاف",en:"Discovery Summary",cat:"Topology & Discovery",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var cl=0;for(var i=0;i<w.length;i++){var r=w[i]||{};var c=H.num(r.clients);if(!H.finite(c)){var st=Array.isArray(r.stations)?r.stations:[];c=st.length;}cl+=H.finite(c)?c:0;}var dv=H.mergeDevices(d);dv=Array.isArray(dv)?dv:[];var nb=Array.isArray(d.lldp)?d.lldp.length:(Array.isArray(d.neighbors)?d.neighbors.length:0);var t=H.lang==='ar'?'ملخص الاكتشاف':'Discovery Summary';if(!cl&&!dv.length&&!nb)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'device');function box(v,lbl,col){return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+v+"</b></div>";}var body="<div class='grid two'>"+box(cl,H.lang==='ar'?'عملاء واي فاي':'Wi-Fi Clients','var(--accent)')+box(dv.length,H.lang==='ar'?'أجهزة':'Devices','var(--good)')+box(nb,H.lang==='ar'?'جيران LLDP':'LLDP','var(--primary)')+"</div>";return H.card(t,body,String(dv.length+nb),'device');}});
  PRO_FEATURES.push({key:"x_tp_link_activity",ar:"نشاط الوصلات",en:"Link Activity",cat:"Topology & Discovery",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var t=H.lang==='ar'?'نشاط الوصلات':'Link Activity';if(!ifs.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='',act=0,shown=0;for(var i=0;i<ifs.length&&i<8;i++){var f=ifs[i]||{};var rb=H.num(f.rx_bps);var tb=H.num(f.tx_bps);rb=H.finite(rb)?rb:0;tb=H.finite(tb)?tb:0;var tot=rb+tb;var up=tot>0;if(up)act++;shown++;var col=up?'var(--excellent)':'var(--muted)';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span style='color:"+col+"'>● "+H.esc(String(f.name||'?'))+"</span><span class='muted'>"+H.bps(tot)+"</span></div>";}return H.card(t,rows,String(act)+'/'+String(shown),'net');}});
  PRO_FEATURES.push({key:"x_ux_setup_score",ar:"اكتمال الإعداد",en:"Setup Completeness",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'اكتمال الإعداد':'Setup Completeness';var w=Array.isArray(d.wifi)?d.wifi:[];var checks=[];checks.push(w.length>0);var bands={};for(var i=0;i<w.length;i++){bands[w[i].band]=1;}checks.push(!!bands['2.4G']&&!!bands['5G']);var bh=d.backhaul||{};checks.push(!!bh.online);var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);checks.push(H.finite(mt)&&H.finite(ma)&&mt>0&&(ma/mt)>0.1);var cpu=H.num((d.cpu||{}).percent);checks.push(H.finite(cpu)&&cpu<90);var sa=H.num((d.storage||{}).available);checks.push(H.finite(sa)&&sa>0);var clients=0;for(var j=0;j<w.length;j++){clients+=(H.num(w[j].clients)||0);}checks.push(clients>0);var pass=0;for(var k=0;k<checks.length;k++){if(checks[k])pass++;}var tot=checks.length;if(!tot)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'shield');var pct=H.clamp(pass/tot*100,0,100);var col=pct>=80?'var(--excellent)':pct>=50?'var(--good)':pct>=30?'var(--mid)':'var(--weak)';return H.card(title,H.gauge(ar?'مكتمل':'Complete',H.fmt(pct,0)+'%',pass+'/'+tot,ar?'فحوصات':'checks',pct,col,'shield'),pass+'/'+tot,'shield');}});
  PRO_FEATURES.push({key:"x_ux_verdict",ar:"الحكم السريع",en:"One-Glance Verdict",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'الحكم السريع':'One-Glance Verdict';var score=100;var cpu=H.num((d.cpu||{}).percent);if(H.finite(cpu)&&cpu>85){score-=25;}var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);if(H.finite(mt)&&H.finite(ma)&&mt>0&&(ma/mt)<0.1){score-=20;}var bh=d.backhaul||{};if(!bh.online){score-=30;}var lat=H.num(d.latency_ms);if(H.finite(lat)&&lat>100){score-=15;}var temp=H.num(d.temperature_c);if(H.finite(temp)&&temp>80){score-=15;}score=H.clamp(score,0,100);var verdict,col;if(score>=85){verdict=ar?'ممتاز':'ALL GOOD';col='var(--excellent)';}else if(score>=60){verdict=ar?'جيد':'OK';col='var(--good)';}else if(score>=40){verdict=ar?'انتباه':'WATCH';col='var(--mid)';}else{verdict=ar?'تحقق':'CHECK';col='var(--weak)';}var body="<div style='text-align:center;padding:8px 0'><div style='font-size:26px;font-weight:700;color:"+col+"'>"+verdict+"</div><div style='color:var(--muted);font-size:12px;margin-top:4px'>"+(ar?'مؤشر الصحة':'health index')+' '+H.fmt(score,0)+"</div></div>"+H.bar(score,100,col);return H.card(title,body,H.fmt(score,0),'shield');}});
  PRO_FEATURES.push({key:"x_ux_tips",ar:"نصائح التحسين",en:"Optimization Tips",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'نصائح التحسين':'Optimization Tips';var tips=[];var w=Array.isArray(d.wifi)?d.wifi:[];for(var i=0;i<w.length;i++){var b=H.num((w[i].survey||{}).busy_pct);if(H.finite(b)&&b>70){tips.push((ar?'ازدحام الهواء على ':'High airtime on ')+H.esc(w[i].band||'?')+(ar?' — غيّر القناة':' — change channel'));break;}}var cpu=H.num((d.cpu||{}).percent);if(H.finite(cpu)&&cpu>85){tips.push(ar?'المعالج مرتفع — راجع العمليات':'CPU high — check processes');}var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);if(H.finite(mt)&&H.finite(ma)&&mt>0&&(ma/mt)<0.12){tips.push(ar?'الذاكرة منخفضة':'Low free memory');}var weak=0;for(var j=0;j<w.length;j++){var sts=Array.isArray(w[j].stations)?w[j].stations:[];for(var k=0;k<sts.length;k++){var s=H.num(sts[k].signal_dbm);if(H.finite(s)&&s<-75)weak++;}}if(weak>0){tips.push(weak+(ar?' عميل بإشارة ضعيفة — أعد التموضع':' weak-signal clients — reposition'));}var lat=H.num(d.latency_ms);if(H.finite(lat)&&lat>120){tips.push(ar?'زمن وصول مرتفع للبوابة':'High gateway latency');}if(!tips.length)return H.card(title,"<div style='color:var(--excellent)'>"+(ar?'لا توصيات — كل شيء مضبوط':'No tips — all tuned')+"</div>",null,'shield');var rows='';for(var t=0;t<tips.length&&t<5;t++){rows+="<div style='display:flex;gap:6px;margin:5px 0;font-size:12px'><span style='color:var(--accent)'>•</span><span>"+tips[t]+"</span></div>";}return H.card(title,rows,String(tips.length),'cpu');}});
  PRO_FEATURES.push({key:"x_ux_all_ok",ar:"ملخص الحالة",en:"Everything OK?",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'ملخص الحالة':'Everything OK?';var items=[];var w=Array.isArray(d.wifi)?d.wifi:[];items.push({l:ar?'الواي فاي':'WiFi',ok:w.length>0});var bh=d.backhaul||{};items.push({l:ar?'الاتصال':'Uplink',ok:!!bh.online});var cpu=H.num((d.cpu||{}).percent);items.push({l:ar?'المعالج':'CPU',ok:H.finite(cpu)?cpu<85:true});var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);items.push({l:ar?'الذاكرة':'RAM',ok:(H.finite(mt)&&H.finite(ma)&&mt>0)?(ma/mt)>0.1:true});var sa=H.num((d.storage||{}).available);items.push({l:ar?'التخزين':'Disk',ok:H.finite(sa)?sa>0:true});var temp=H.num(d.temperature_c);items.push({l:ar?'الحرارة':'Temp',ok:H.finite(temp)?temp<80:true});var okc=0;for(var i=0;i<items.length;i++){if(items[i].ok)okc++;}var rows='';for(var j=0;j<items.length;j++){var it=items[j];var c=it.ok?'var(--excellent)':'var(--weak)';var mark=it.ok?'✓':'!';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:4px 0'><span>"+it.l+"</span><span style='color:"+c+";font-weight:700'>"+mark+"</span></div>";}var allok=okc===items.length;var chip=allok?(ar?'الكل سليم':'ALL OK'):okc+'/'+items.length;return H.card(title,rows,chip,'shield');}});
  PRO_FEATURES.push({key:"x_ux_weekly_digest",ar:"الملخص الأسبوعي",en:"Weekly Digest",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'الملخص الأسبوعي':'Weekly Digest';var tr=d.traffic||{};var rxb=H.num(tr.rx_bytes),txb=H.num(tr.tx_bytes);var tot=(H.finite(rxb)?rxb:0)+(H.finite(txb)?txb:0);var up=H.num(d.uptime);var w=Array.isArray(d.wifi)?d.wifi:[];var clients=0;for(var i=0;i<w.length;i++){clients+=(H.num(w[i].clients)||0);}var now=(H.num(tr.rx_bps)||0)+(H.num(tr.tx_bps)||0);function row(lbl,val,col){return "<div style='display:flex;justify-content:space-between;font-size:12px;margin:5px 0'><span style='color:var(--muted)'>"+lbl+"</span><b style='color:"+(col||'var(--text)')+"'>"+val+"</b></div>";}if(tot<=0&&!H.finite(up)&&!clients&&now<=0)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='';rows+=row(ar?'إجمالي البيانات':'Total data',tot>0?H.bytes(tot):'—','var(--accent)');rows+=row(ar?'مدة التشغيل':'Uptime',H.finite(up)?H.uptime(up):'—');rows+=row(ar?'العملاء':'Clients',String(clients));rows+=row(ar?'التدفق الآن':'Now',now>0?H.bps(now):'—','var(--good)');return H.card(title,rows,null,'net');}});
  PRO_FEATURES.push({key:"x_ux_readiness_meters",ar:"قائمة الجاهزية",en:"Readiness Meters",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'قائمة الجاهزية':'Readiness Meters';var rows='';var any=false;function line(lbl,pct,col){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+lbl+"</span><span style='color:"+col+"'>"+H.fmt(pct,0)+"%</span></div>"+H.bar(pct,100,col)+"</div>";}var cpu=H.num((d.cpu||{}).percent);if(H.finite(cpu)){any=true;var ch=H.clamp(100-cpu,0,100);rows+=line(ar?'فراغ المعالج':'CPU free',ch,ch>40?'var(--excellent)':ch>15?'var(--mid)':'var(--weak)');}var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);if(H.finite(mt)&&H.finite(ma)&&mt>0){any=true;var mf=H.clamp(ma/mt*100,0,100);rows+=line(ar?'فراغ الذاكرة':'RAM free',mf,mf>30?'var(--excellent)':mf>12?'var(--mid)':'var(--weak)');}var st=d.storage||{};var stt=H.num(st.total),su=H.num(st.used);if(H.finite(stt)&&H.finite(su)&&stt>0){any=true;var sf=H.clamp((1-su/stt)*100,0,100);rows+=line(ar?'فراغ التخزين':'Disk free',sf,sf>25?'var(--excellent)':sf>10?'var(--mid)':'var(--weak)');}var w=Array.isArray(d.wifi)?d.wifi:[];var bs=0,bn=0;for(var i=0;i<w.length;i++){var b=H.num((w[i].survey||{}).busy_pct);if(H.finite(b)){bs+=b;bn++;}}if(bn>0){any=true;var af=H.clamp(100-bs/bn,0,100);rows+=line(ar?'فراغ الهواء':'Airtime free',af,af>50?'var(--excellent)':af>25?'var(--mid)':'var(--weak)');}if(!any)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');return H.card(title,rows,null,'cpu');}});
  PRO_FEATURES.push({key:"x_ux_action_items",ar:"مهام مطلوبة",en:"Action Items",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'مهام مطلوبة':'Action Items';var crit=0,warn=0;var bh=d.backhaul||{};if(!bh.online)crit++;var cpu=H.num((d.cpu||{}).percent);if(H.finite(cpu)){if(cpu>92)crit++;else if(cpu>80)warn++;}var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);if(H.finite(mt)&&H.finite(ma)&&mt>0){var fr=ma/mt;if(fr<0.06)crit++;else if(fr<0.15)warn++;}var temp=H.num(d.temperature_c);if(H.finite(temp)){if(temp>85)crit++;else if(temp>75)warn++;}var lat=H.num(d.latency_ms);if(H.finite(lat)){if(lat>200)crit++;else if(lat>100)warn++;}var ifs=Array.isArray(d.interfaces)?d.interfaces:[];for(var i=0;i<ifs.length;i++){var e=(H.num(ifs[i].rx_errors)||0)+(H.num(ifs[i].tx_errors)||0);if(e>1000){warn++;break;}}var total=crit+warn;var col=crit>0?'var(--weak)':warn>0?'var(--mid)':'var(--excellent)';var sub=ar?(crit+' حرج · '+warn+' تحذير'):(crit+' critical · '+warn+' warn');var body="<div style='text-align:center;padding:6px 0'><div style='font-size:28px;font-weight:700;color:"+col+"'>"+String(total)+"</div><div style='font-size:12px;color:var(--muted);margin-top:2px'>"+(total?sub:(ar?'لا مهام':'no action items'))+"</div></div>";return H.card(title,body,total?String(total):null,'shield');}});
  PRO_FEATURES.push({key:"x_ux_verdict_tiles",ar:"لوحة المؤشرات",en:"Verdict Tiles",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'لوحة المؤشرات':'Verdict Tiles';var w=Array.isArray(d.wifi)?d.wifi:[];var clients=0;for(var i=0;i<w.length;i++){clients+=(H.num(w[i].clients)||0);}var bh=d.backhaul||{};var tr=d.traffic||{};var thr=(H.num(tr.rx_bps)||0)+(H.num(tr.tx_bps)||0);var ssum=0,scnt=0;for(var j=0;j<w.length;j++){var sts=Array.isArray(w[j].stations)?w[j].stations:[];for(var k=0;k<sts.length;k++){var sg=H.num(sts[k].signal_dbm);if(H.finite(sg)){ssum+=sg;scnt++;}}}var avg=scnt?ssum/scnt:null;function tile(lbl,val,col){return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+val+"</b></div>";}var upCol=bh.online?'var(--excellent)':'var(--weak)';var upTxt=bh.online?(ar?'متصل':'Up'):(ar?'مقطوع':'Down');var sigCol=avg==null?'var(--muted)':(avg>-60?'var(--excellent)':avg>-72?'var(--good)':'var(--mid)');var body="<div class='grid two'>"+tile(ar?'الاتصال':'Uplink',upTxt,upCol)+tile(ar?'العملاء':'Clients',String(clients),clients>0?'var(--good)':'var(--muted)')+tile(ar?'التدفق':'Throughput',thr>0?H.bps(thr):'—',thr>0?'var(--accent)':'var(--muted)')+tile(ar?'الإشارة':'Avg Signal',avg==null?'—':H.fmt(avg,0)+' dBm',sigCol)+"</div>";return H.card(title,body,null,'net');}});
  PRO_FEATURES.push({key:"x_cap_link_capacity",ar:"سعة الوصلة القصوى",en:"Peak Link Capacity",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var MAX=1201;var peak=0,found=false;for(var i=0;i<w.length;i++){var st=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<st.length;j++){var r=H.num(st[j].tx_rate);if(H.finite(r)){found=true;if(r>peak)peak=r;}}}var title=H.lang==='ar'?'سعة الوصلة القصوى':'Peak Link Capacity';if(!found)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var pct=H.clamp(peak/MAX*100,0,100);var col=pct>=80?'var(--excellent)':pct>=55?'var(--good)':pct>=30?'var(--mid)':'var(--weak)';var body=H.gauge(H.lang==='ar'?'ذروة الوصلة':'Peak link',H.fmt(peak,0)+' Mbps',H.lang==='ar'?'السقف 1201':'Ceiling 1201',H.fmt(pct,0)+'%',pct,col,'net');return H.card(title,body,H.fmt(pct,0)+'%','net');}});
  PRO_FEATURES.push({key:"x_cap_stream_util",ar:"استغلال التدفقات المكانية",en:"Spatial-Stream Use",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var one=0,two=0,found=false;for(var i=0;i<w.length;i++){var st=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<st.length;j++){var r=H.num(st[j].tx_rate);if(H.finite(r)&&r>0){found=true;if(r>=700)two++;else one++;}}}var title=H.lang==='ar'?'استغلال التدفقات المكانية':'Spatial-Stream Use';if(!found)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'wifi');var tot=one+two;var body="";body+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(H.lang==='ar'?'تدفقان (MIMO)':'2SS (MIMO)')+"</span><span style='color:var(--excellent)'>"+two+"</span></div>"+H.bar(two,tot||1,'var(--excellent)')+"</div>";body+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(H.lang==='ar'?'تدفق واحد (SISO)':'1SS (SISO)')+"</span><span style='color:var(--mid)'>"+one+"</span></div>"+H.bar(one,tot||1,'var(--mid)')+"</div>";var chip=H.fmt(tot?two/tot*100:0,0)+'% 2SS';return H.card(title,body,chip,'wifi');}});
  PRO_FEATURES.push({key:"x_cap_mode_badges",ar:"أوضاع HE و VHT",en:"HE / VHT Modes",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var title=H.lang==='ar'?'أوضاع HE و VHT':'HE / VHT Modes';if(!w.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');var rows='';for(var i=0;i<w.length;i++){var r=w[i];var m=String(r.htmode||'').toUpperCase();var gen=m.indexOf('HE')===0?'Wi-Fi 6':m.indexOf('VHT')===0?'Wi-Fi 5':m.indexOf('HT')===0?'Wi-Fi 4':(H.lang==='ar'?'قديم':'legacy');var col=m.indexOf('HE')===0?'var(--excellent)':m.indexOf('VHT')===0?'var(--good)':m.indexOf('HT')===0?'var(--mid)':'var(--muted)';rows+="<div style='display:flex;justify-content:space-between;align-items:center;margin:7px 0;font-size:12px'><span>"+H.esc(r.band||'?')+"</span><span style='background:"+col+";color:#000;padding:2px 8px;border-radius:6px;font-weight:600'>"+H.esc(m||'—')+"</span><span style='color:var(--muted)'>"+gen+"</span></div>";}return H.card(title,rows,null,'signal');}});
  PRO_FEATURES.push({key:"x_cap_band_phy",ar:"إجمالي معدل PHY لكل نطاق",en:"Aggregate PHY / Band",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var title=H.lang==='ar'?'إجمالي معدل PHY لكل نطاق':'Aggregate PHY / Band';if(!w.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var data=[],maxAgg=0;for(var i=0;i<w.length;i++){var st=Array.isArray(w[i].stations)?w[i].stations:[];var sum=0;for(var j=0;j<st.length;j++){var r=H.num(st[j].tx_rate);if(H.finite(r))sum+=r;}data.push({band:w[i].band||'?',sum:sum});if(sum>maxAgg)maxAgg=sum;}var rows='';for(var k=0;k<data.length;k++){var col=data[k].sum>=1000?'var(--excellent)':data[k].sum>=400?'var(--good)':data[k].sum>0?'var(--mid)':'var(--muted)';rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(data[k].band)+"</span><span style='color:"+col+"'>"+H.bps(data[k].sum*1e6)+"</span></div>"+H.bar(data[k].sum,maxAgg||1,col)+"</div>";}return H.card(title,rows,null,'net');}});
  PRO_FEATURES.push({key:"x_cap_headroom",ar:"الهامش حتى السقف",en:"Headroom to Max",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var MAX=1201;var peak=0,found=false;for(var i=0;i<w.length;i++){var st=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<st.length;j++){var r=H.num(st[j].tx_rate);if(H.finite(r)){found=true;if(r>peak)peak=r;}}}var title=H.lang==='ar'?'الهامش حتى السقف':'Headroom to Max';if(!found)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');var head=H.clamp(MAX-peak,0,MAX);var hpct=H.clamp(head/MAX*100,0,100);var col=hpct<=20?'var(--excellent)':hpct<=45?'var(--good)':hpct<=70?'var(--mid)':'var(--weak)';var body="<div style='font-size:26px;font-weight:700;color:"+col+"'>"+H.fmt(head,0)+" Mbps</div><div style='color:var(--muted);font-size:12px;margin-bottom:6px'>"+(H.lang==='ar'?'متبقٍ حتى 1201':'remaining to 1201')+"</div>"+H.bar(peak,MAX,col);return H.card(title,body,H.fmt(100-hpct,0)+'% '+(H.lang==='ar'?'مُستغل':'used'),'signal');}});
  PRO_FEATURES.push({key:"x_cap_phy_eff",ar:"كفاءة الطبقة الفيزيائية",en:"PHY Efficiency",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var accP=0,cnt=0;for(var i=0;i<w.length;i++){var st=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<st.length;j++){var a=H.num(st[j].tx_rate);var e=H.num(st[j].expected_mbps);if(H.finite(a)&&H.finite(e)&&e>0){accP+=H.clamp(a/e*100,0,100);cnt++;}}}var title=H.lang==='ar'?'كفاءة الطبقة الفيزيائية':'PHY Efficiency';if(!cnt)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'wifi');var eff=accP/cnt;var col=eff>=80?'var(--excellent)':eff>=60?'var(--good)':eff>=40?'var(--mid)':'var(--weak)';var body=H.gauge(H.lang==='ar'?'فعلي مقابل متوقع':'actual vs expected',H.fmt(eff,0)+'%',H.esc(String(cnt))+(H.lang==='ar'?' عميل':' clients'),H.lang==='ar'?'المتوسط':'mean',eff,col,'wifi');return H.card(title,body,H.fmt(eff,0)+'%','wifi');}});
  PRO_FEATURES.push({key:"x_cap_width_capacity",ar:"سعة عرض القناة",en:"Channel-Width Capacity",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var title=H.lang==='ar'?'سعة عرض القناة':'Channel-Width Capacity';if(!w.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');function capFor(r){var m=String(r.htmode||'').toUpperCase();var wd=H.num(r.width);var n=H.finite(wd)?wd:(m.indexOf('160')>=0?160:m.indexOf('80')>=0?80:m.indexOf('40')>=0?40:m.indexOf('20')>=0?20:0);if(n>=160)return 2402;if(n>=80)return 1201;if(n>=40)return 573;if(n>=20)return 286;return 0;}var rows='';for(var i=0;i<w.length;i++){var cap=capFor(w[i]);var col=cap>=1201?'var(--excellent)':cap>=573?'var(--good)':cap>0?'var(--mid)':'var(--muted)';rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(w[i].band||'?')+' · '+H.esc(String(w[i].htmode||'?'))+"</span><span style='color:"+col+"'>"+(cap?H.fmt(cap,0)+' Mbps':'—')+"</span></div>"+H.bar(cap,2402,col)+"</div>";}return H.card(title,rows,null,'signal');}});
  PRO_FEATURES.push({key:"x_cap_ceiling_rank",ar:"الأقرب إلى السقف",en:"Closest to Ceiling",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var MAX=1201;var st=[];for(var i=0;i<w.length;i++){var s=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<s.length;j++){if(H.finite(H.num(s[j].tx_rate)))st.push(s[j]);}}var title=H.lang==='ar'?'الأقرب إلى السقف':'Closest to Ceiling';if(!st.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');st.sort(function(a,b){return H.num(b.tx_rate)-H.num(a.tx_rate);});var rows='';var lim=st.length<4?st.length:4;for(var k=0;k<lim;k++){var r=H.num(st[k].tx_rate);var pct=H.clamp(r/MAX*100,0,100);var col=pct>=80?'var(--excellent)':pct>=55?'var(--good)':pct>=30?'var(--mid)':'var(--weak)';var who=st[k].ip||st[k].mac||'?';rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(String(who))+"</span><span style='color:"+col+"'>"+H.fmt(r,0)+' ('+H.fmt(pct,0)+"%)</span></div>"+H.bar(pct,100,col)+"</div>";}return H.card(title,rows,String(st.length),'net');}});
  // Defensive: strip null/non-object elements from the live arrays so a stray null in
  // d.wifi / d.devices / d.interfaces / stations can never throw inside a card.
  function sanitizeData(data) {
    var d = data || {};
    var okArr = function (a) { return Array.isArray(a) ? a.filter(function (x) { return x && typeof x === "object"; }) : []; };
    var out = {}; for (var k in d) if (Object.prototype.hasOwnProperty.call(d, k)) out[k] = d[k];
    out.wifi = okArr(d.wifi).map(function (w) { var c = {}; for (var k in w) c[k] = w[k]; c.stations = okArr(w.stations); return c; });
    out.devices = okArr(d.devices);
    out.interfaces = okArr(d.interfaces);
    return out;
  }
  // Fixed, sensible category order so the Insights section is organized (not insertion-random).
  var PRO_CAT_ORDER = ["System & Health","RF & Airtime","Clients & Devices","Traffic & Bandwidth","Latency & Link Quality","Security & Threats","Topology & Discovery","Automation & UX"];
  var PRO_CAT_AR = {"System & Health":"النظام والصحة","RF & Airtime":"الراديو والهواء","Clients & Devices":"العملاء والأجهزة","Traffic & Bandwidth":"الحركة والتدفق","Latency & Link Quality":"الكمون وجودة الوصلة","Security & Threats":"الحماية والمخاطر","Topology & Discovery":"الطوبولوجيا والاكتشاف","Automation & UX":"الأتمتة والتجربة"};
  function renderProInsights(data) {
    if (!PRO_FEATURES.length) return sectionHead(tr("insights"), "Pro", "") + '<div class="empty">' + tr("loading") + '</div>';
    data = sanitizeData(data);
    var cats = {};
    PRO_FEATURES.forEach(function (f) { (cats[f.cat] = cats[f.cat] || []).push(f); });
    var out = sectionHead(tr("insights"), state.lang === "ar" ? "لوحات احترافية — تحليلات حية" : "Professional live analytics", PRO_FEATURES.length + "");
    // render known categories in fixed order first, then any stragglers
    var ordered = PRO_CAT_ORDER.filter(function (c) { return cats[c]; });
    Object.keys(cats).forEach(function (c) { if (ordered.indexOf(c) < 0) ordered.push(c); });
    var seen = {};
    ordered.forEach(function (c) {
      var label = state.lang === "ar" ? (PRO_CAT_AR[c] || c) : c;
      out += '<h3 class="pro-cat">' + esc(label) + '</h3><div class="grid pro-grid">';
      cats[c].forEach(function (f) {
        if (seen[f.key]) return; seen[f.key] = 1;   // guard against any duplicate key
        var html = "";
        try { html = f.fn(data, H); } catch (e) { html = ""; }
        if (html) out += html;
      });
      out += '</div>';
    });
    return out;
  }
  function render(data) {
    state.latest = data;
    window.__lastApi = data;
    detectNewDevices(data);
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
    if ($("insights")) $("insights").innerHTML = renderProInsights(data);
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
        if (act === "__limit") { // bandwidth-hog "limit" -> ask Mbps, set per-client QoS
          var mb = window.prompt(tr("limitPrompt"), "10"); if (mb === null) return;
          mb = String(mb).replace(/[^0-9]/g, ""); if (!mb) return;
          try {
            var rl = await fetch(CTL, { method:"POST", cache:"no-store", headers:{ "Content-Type":"application/x-www-form-urlencoded" },
              body:"section=devices&action=set_client_limit&mac=" + encodeURIComponent(mac) + "&limit_down=" + mb + "&limit_up=" + mb + "&" + sidQuery() + "&_=" + Date.now() });
            if (rl.status === 403) return requireLogin(tr("loginBad"));
            var jl = await rl.json(); toast(jl.summary || tr("ok")); event("Limit " + mac + " " + mb + "Mbps");
          } catch (e) { toast(e.message); }
          return;
        }
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
    // device rename (custom names stored locally)
    Array.prototype.forEach.call(document.querySelectorAll(".dev-rename"), function (b) {
      b.onclick = function () {
        var mac = b.dataset.devMac; if (!mac) return;
        var cur = deviceName(mac);
        var nm = window.prompt(tr("renamePrompt"), cur || "");
        if (nm === null) return;
        setDeviceName(mac, nm.trim());
        if (state.latest) render(state.latest);
      };
    });
    var scanBtn = $("wifiScanBtn");
    if (scanBtn) scanBtn.onclick = scanWifi;
    var lanBtn = $("lanScanBtn");
    if (lanBtn) lanBtn.onclick = scanLan;
    var applyChan = $("wifiApplyChanBtn");
    if (applyChan) applyChan.onclick = function () { applyBestChannels(applyChan.dataset.ch24, applyChan.dataset.ch5); };
    var stBtn = $("selftestBtn");
    if (stBtn) stBtn.onclick = async function () {
      stBtn.disabled = true; var old = stBtn.textContent; stBtn.textContent = tr("loading") + "...";
      try {
        var r = await fetch(CTL, { method:"POST", cache:"no-store",
          headers:{ "Content-Type":"application/x-www-form-urlencoded" },
          body:"section=selftest&action=run_selftest&" + sidQuery() + "&_=" + Date.now() });
        if (r.status === 403) return requireLogin(tr("loginBad"));
        state.selftest = await r.json();
        if (state.latest) render(state.latest);
        showSection("system");
      } catch (e) { toast("selftest: " + e.message); stBtn.disabled = false; stBtn.textContent = old; }
    };
    Array.prototype.forEach.call(document.querySelectorAll("[data-steer-mac]"), function (b) {
      b.onclick = async function () {
        b.disabled = true;
        try {
          var r = await fetch(CTL, { method:"POST", cache:"no-store",
            headers:{ "Content-Type":"application/x-www-form-urlencoded" },
            body:"section=wifi&action=steer_client&mac=" + encodeURIComponent(b.dataset.steerMac) + "&iface=" + encodeURIComponent(b.dataset.steerIface || "") + "&" + sidQuery() + "&_=" + Date.now() });
          if (r.status === 403) return requireLogin(tr("loginBad"));
          var j = await r.json();
          toast(j.summary || tr("ok"));
          event("Steer 5G: " + b.dataset.steerMac);
        } catch (e) { toast(e.message); } finally { b.disabled = false; }
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
  // ===== v44 UX pack: auto day/night theme, quick search, draggable cards, speed gauge =====
  // (7) local speed test with an animated needle gauge — replaces the plain toast
  var _speedPlain = speedTest;
  speedTest = async function () {
    var ov = document.createElement("div");
    ov.style.cssText = "position:fixed;inset:0;background:rgba(2,6,23,.72);display:flex;align-items:center;justify-content:center;z-index:9999";
    ov.innerHTML = '<div style="background:var(--card,#0B1220);border:1px solid var(--border);border-radius:16px;padding:22px;text-align:center;min-width:260px">' +
      '<svg width="220" height="130" viewBox="0 0 220 130">' +
      '<path d="M20 120 A 90 90 0 0 1 200 120" fill="none" stroke="var(--border)" stroke-width="14" stroke-linecap="round"/>' +
      '<path id="sgArc" d="M20 120 A 90 90 0 0 1 200 120" fill="none" stroke="var(--accent)" stroke-width="14" stroke-linecap="round" stroke-dasharray="0 999"/>' +
      '<line id="sgNeedle" x1="110" y1="120" x2="30" y2="118" stroke="var(--primary)" stroke-width="4" stroke-linecap="round"/>' +
      '<circle cx="110" cy="120" r="7" fill="var(--primary)"/></svg>' +
      '<div id="sgVal" class="latin" style="font-size:26px;font-weight:800;margin-top:4px">0 Mbps</div>' +
      '<div id="sgSub" style="color:var(--muted);font-size:12px;margin-top:2px">&nbsp;</div>' +
      '<button id="sgClose" class="btn" style="margin-top:12px">OK</button></div>';
    document.body.appendChild(ov);
    ov.querySelector("#sgClose").onclick = function () { ov.parentNode && ov.parentNode.removeChild(ov); };
    function setG(mbps) {
      var f = Math.min(mbps / 1000, 1), ang = (-180 + f * 180) * Math.PI / 180;
      var n = ov.querySelector("#sgNeedle");
      n.setAttribute("x2", 110 + 85 * Math.cos(ang)); n.setAttribute("y2", 120 + 85 * Math.sin(ang));
      ov.querySelector("#sgArc").setAttribute("stroke-dasharray", (f * 283).toFixed(1) + " 999");
      ov.querySelector("#sgVal").textContent = fmt(mbps, mbps < 100 ? 1 : 0) + " Mbps";
    }
    var total = 0, t0 = performance.now();
    try {
      for (var i = 0; i < 6; i++) {
        var r = await fetch("dashboard.js?sp=" + Math.random(), { cache: "no-store" });
        var b = await r.arrayBuffer(); total += b.byteLength;
        setG(total * 8 / ((performance.now() - t0) / 1000) / 1e6);
      }
      ov.querySelector("#sgSub").textContent = state.lang === "ar" ? "سرعة القراءة من الجهاز عبر الشبكة المحلية" : "LAN read speed from the router";
    } catch (e) { ov.querySelector("#sgSub").textContent = "test: " + e.message; }
  };
  document.addEventListener("DOMContentLoaded", function () {
    try {
      // (15) auto day/night theme: the theme button cycles dark -> light -> auto
      var themePref = localStorage.getItem(LS + "themePref") || state.theme;
      function resolveTheme(p) { if (p !== "auto") return p; var h = new Date().getHours(); return (h >= 18 || h < 6) ? "dark" : "light"; }
      function applyPref(p) {
        themePref = p; localStorage.setItem(LS + "themePref", p);
        state.theme = resolveTheme(p); localStorage.setItem(LS + "theme", state.theme);
        renderChrome(); if (state.latest) render(state.latest);
        var b = $("themeBtn"); if (b && p === "auto") b.textContent = state.lang === "ar" ? "تلقائي" : "Auto";
      }
      var tb = $("themeBtn");
      if (tb) tb.onclick = function () { applyPref(themePref === "dark" ? "light" : themePref === "light" ? "auto" : "dark"); };
      if (themePref === "auto") applyPref("auto");
      setInterval(function () { if (themePref === "auto" && resolveTheme("auto") !== state.theme) applyPref("auto"); }, 60000);
      // (18) quick search: filters the section menu as you type
      var navEl = document.querySelector(".nav");
      if (navEl && navEl.parentElement && !$("navSearch")) {
        var si = document.createElement("input");
        si.id = "navSearch"; si.type = "search";
        si.placeholder = state.lang === "ar" ? "بحث سريع…" : "Quick search…";
        si.style.cssText = "width:100%;margin:0 0 8px;padding:8px 10px;border-radius:10px;border:1px solid var(--border);background:transparent;color:var(--text);font:inherit";
        navEl.parentElement.insertBefore(si, navEl);
        si.oninput = function () {
          var q = si.value.trim().toLowerCase();
          Array.prototype.forEach.call(navEl.querySelectorAll("button"), function (b) {
            b.style.display = (!q || b.textContent.toLowerCase().indexOf(q) > -1) ? "" : "none";
          });
        };
      }
      // (14) draggable insight cards — order persists per card title (grid `order`)
      var ORDER_KEY = LS + "cardOrder", dragSrc = null;
      function cardTitle(el) { var h = el.querySelector("h3,h4,header,b"); return ((h ? h.textContent : el.textContent) || "").slice(0, 60); }
      function bindDrag(box) {
        var map = JSON.parse(localStorage.getItem(ORDER_KEY) || "{}");
        Array.prototype.forEach.call(box.querySelectorAll(".card"), function (c, i) {
          var t = cardTitle(c);
          c.style.order = map[t] != null ? map[t] : i;
          c.setAttribute("draggable", "true");
          c.ondragstart = function () { dragSrc = c; };
          c.ondragover = function (e) { e.preventDefault(); };
          c.ondrop = function (e) {
            e.preventDefault(); if (!dragSrc || dragSrc === c) return;
            var a = Number(dragSrc.style.order || 0), b2 = Number(c.style.order || 0);
            dragSrc.style.order = b2; c.style.order = a;
            var m = JSON.parse(localStorage.getItem(ORDER_KEY) || "{}");
            m[cardTitle(dragSrc)] = b2; m[t] = a;
            localStorage.setItem(ORDER_KEY, JSON.stringify(m)); dragSrc = null;
          };
        });
      }
      var insBox = $("insights");
      if (insBox && window.MutationObserver) new MutationObserver(function () { try { bindDrag(insBox); } catch (e) {} }).observe(insBox, { childList: true });
    } catch (e) { /* UX pack must never break the dashboard */ }
  });
}());
