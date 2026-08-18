(function () {
  "use strict";

  var API = "/cgi-bin/dashapi2";
  var ACTION = "/cgi-bin/dashaction";
  var CTL = "/cgi-bin/dashctl";
  var LS = "smartap.";
  var startupSessionCleanup = Promise.resolve();
  var UI_VERSION = "cr6608-smartap-v66-ui-authfix2-chartfix1-25.12.5";
  var AUTH_TIMEOUT_MS = 12000;
  var API_TIMEOUT_MS = 15000;
  var CONTROL_TIMEOUT_MS = 130000;
  var NETWORK_CONTROL_TIMEOUT_MS = 190000;
  // uhttpd permits a guarded CGI to run for 750 seconds.  This covers one
  // 660-second DFS/ACS verification, but not the absolute worst case of a
  // failed DFS apply followed by another DFS restore (the backend worker is
  // independently bounded and Safe Apply recovery remains authoritative).
  // Keep the request just below uhttpd, then recover state instead of claiming
  // that a lost HTTP response proves success or failure.
  var WIFI_CONTROL_TIMEOUT_MS = 740000;
  // The worker's default outer guard is 1700 seconds so it can verify a failed
  // DFS apply and a DFS rollback.  Recovery must outlive that worker even when
  // uhttpd has already closed the original 750-second CGI response.
  var WIFI_RECOVERY_WINDOW_MS = 1740000;
  var RECOVERY_PROBE_TIMEOUT_MS = 8000;
  var RECOVERY_WINDOW_MS = 180000;
  var RECOVERY_GRACE_MS = 20000;
  var SCAN_TIMEOUT_MS = 45000;
  var POLL_INTERVALS = [3, 10, 30, 60, 120];
  function validPollInterval(value) {
    var interval = Number(value);
    return POLL_INTERVALS.indexOf(interval) >= 0 ? interval : 3;
  }
  if (localStorage.getItem(LS + "uiVersion") !== UI_VERSION) {
    if (!localStorage.getItem(LS + "theme")) localStorage.setItem(LS + "theme", "dark");
    if (!(Number(localStorage.getItem(LS + "interval")) >= 3)) localStorage.setItem(LS + "interval", "3");
    localStorage.removeItem(LS + "events");
    localStorage.removeItem(LS + "availability");
    localStorage.removeItem(LS + "histories");
    localStorage.removeItem(LS + "knownMacs");
    localStorage.removeItem(LS + "cardOrder");
    localStorage.setItem(LS + "uiVersion", UI_VERSION);
  }
  var initialPollInterval = validPollInterval(localStorage.getItem(LS + "interval"));
  try { localStorage.setItem(LS + "interval", String(initialPollInterval)); } catch (_) {}
  function storedJson(key, fallback) {
    try {
      var value = JSON.parse(localStorage.getItem(LS + key) || "null");
      return value == null ? fallback : value;
    } catch (e) {
      try { localStorage.removeItem(LS + key); } catch (_) {}
      return fallback;
    }
  }
  var storedHistories = storedJson("histories", {});
  if (!storedHistories || typeof storedHistories !== "object" || Array.isArray(storedHistories)) storedHistories = {};
  var storedAvailability = storedJson("availability", []);
  if (!Array.isArray(storedAvailability)) storedAvailability = [];
  storedAvailability = storedAvailability.filter(function (x) {
    return x && typeof x === "object" && Number.isFinite(Number(x.t)) && typeof x.ok === "boolean";
  });
  var storedEvents = storedJson("events", []);
  if (!Array.isArray(storedEvents)) storedEvents = [];
  storedEvents = storedEvents.filter(function (x) { return x && typeof x === "object"; });
  var state = {
    lang: localStorage.getItem(LS + "lang") || "ar",
    theme: localStorage.getItem(LS + "theme") || "dark",
    interval: initialPollInterval,
    timer: 0,
    latest: null,
    previousTraffic: null,
    previousAt: 0,
    histories: storedHistories,
    availability: storedAvailability,
    events: storedEvents,
    toastTimer: 0,
    session: "",
    loginPending: false,
    pendingAction: null,
    adminSelection: {},
    controlCache: {},
    controlTokens: {},
    controlRecoveryTargets: {},
    dataGeneration: 0,
    dataController: null,
    controlGeneration: 0,
    controlReadController: null,
    controlReadBox: null,
    postLock: null,
    lastFullAt: 0,
    fullRefreshRequested: false,
    staleRetryTimer: 0,
    suspendHistory: false,
    historyDirty: false,
    historySaveTimer: 0,
    lastHistorySaveAt: 0,
    lastScan: null,
    lanScan: null,
    insightCategory: localStorage.getItem(LS + "insightCategory") || "System & Health"
  };

  var L = {
    ar: {
      loading: "جاري التحميل", unavailable: "غير متوفر", online: "متصل", offline: "غير متصل",
      lanOnly: "LAN فقط", refresh: "تحديث", theme: "الثيم", dark: "داكن", light: "فاتح",
      overview: "نظرة", insights: "الرؤى",
      signal: "الإشارة", network: "الترافيك", devices: "الأجهزة", wifi: "WiFi",
      system: "صحة النظام", actions: "إجراءات", isolation: "العزل والحماية",
      vendor: "الشركة", type: "النوع", link: "المنفذ", action: "إجراء", unknownVendor: "غير معروف", near: "قريب / قوي", mid: "متوسط", far: "بعيد / ضعيف",
      scanNeighbors: "فحص القنوات والشبكات المجاورة", scanning: "جاري الفحص…", bestChannel: "أفضل قناة",
      neighbors: "الشبكات المجاورة", noNeighbors: "لم يُعثر على شبكات مجاورة", applyBest: "طبّق أفضل قناة",
      scanLan: "اكتشاف الأجهزة على الشبكة", lanNeighbors: "أجهزة الشبكة (الجيران)",
      lanScanHint: "يفحص كل المنافذ ويكشف الأجهزة خلف أي سويتش — يعرض الاسم والـ IP والـ MAC والمنفذ.",
      noLanDevices: "لم يُعثر على أجهزة. تأكد من توصيل السويتش/الأجهزة ثم أعد الفحص.",
      port: "المنفذ", host: "الاسم", deviceName: "اسم الجهاز", scanAgain: "إعادة الفحص",
      lldpNeighbors: "أجهزة مُدارة (LLDP/CDP)", noLldpNeighbors: "لا توجد أجهزة LLDP/CDP مُدارة. تأكد أن السويتش/الراوتر يدعم LLDP ثم أعد الفحص.", platform: "النظام/الطراز", localPort: "منفذنا", remotePort: "منفذهم",
      portThroughput: "سحب المنافذ (لكل منفذ)", perPortRate: "معدل النقل لكل منفذ سلكي", totalRate: "السحب الإجمالي", download: "تحميل", upload: "رفع", yearly: "السنوي", total: "الإجمالي", rename: "تسمية الجهاز", renamePrompt: "اسم الجهاز:", limitPrompt: "حد السرعة (ميغابت/ث):", wifiRate: "سحب الواي فاي (لكل تردد)", portsRate: "سحب المنافذ السلكية", clientTraffic: "التحميل / الرفع",
      recommended: "المقترح", current: "الحالي", channel: "القناة", rogueAlert: "BSSID غير معروف يستخدم اسم الشبكة", rogueDesc: "تحقق يدوياً؛ قد يكون نقطة Mesh أو موسعاً شرعياً",
      healthScore: "درجة موارد النظام", airtime: "إشغال الهواء (سياق)", latency: "زمن جلب اللوحة (سياق)", noise: "أرضية الضوضاء",
      clientRadar: "رادار الأجهزة", linkRate: "آخر معدل PHY TX/RX — ليس سرعة نقل البيانات", constellation: "كوكبة العملاء (المدى=الإشارة)",
      newDevice: "جهاز جديد انضم", steer5g: "→ 5G", steerHint: "اطلب من الجهاز الانتقال إلى 5G",
      selftest: "الفحص الذاتي", selftestRun: "تشغيل الفحص الآن", selftestHint: "يعمل تلقائياً كل ليلة 4:00 صباحاً، وتقدر تشغّله يدوياً.",
      selftestNotes: "الملاحظات", lastReport: "آخر تقرير",
      distance: "المسافة التقديرية", secPosture: "لقطة تشفير الشبكات", efficiency: "كفاءة الوصلة",
      protected: "محمي", open: "مفتوح", encrypted: "مشفّر", thermal: "الحارس الحراري",
      thermalOk: "طبيعية", thermalWarm: "دافئة", thermalHot: "مرتفعة", meters: "م",
      secGood: "لم تُرصد شبكة مفتوحة", secOpenWarn: "شبكات مفتوحة", trend: "اتجاه الإشارة",
      netmgr: "الشبكة", wifimgr: "لاسلكي", sysmgr: "النظام",
      quick: "الإعدادات السريعة", quickHint: "برمجة الجهاز بخطوات: الوضع، الشبكة، الحماية، المتقدم — تطبيق واحد.",
      quickTitle: "برمجة سريعة — أوضاع الشبكة",
      quickNote: "اختر الوضع وعبّئ الحقول ثم اضغط حفظ وتطبيق. اختبر الاتصال وثبّت التغييرات خلال مهلة الحماية الظاهرة، وإلا يرجع الجهاز تلقائياً للإعداد السابق.",
      isolationHint: "حمايات وتحكم بالمنافذ — كل خيار مشروح تحته.",
      isolationTitle: "الحماية والمنافذ — دليل مبسّط",
      isolationNote: "٣ أقسام: الحمايات العامة، عزل الواي فاي، ومنافذ الكيبل. بعد التطبيق اختبر الاتصال ثم ثبّت العملية خلال مهلة الحماية الظاهرة، وإلا يتم الرجوع تلقائياً.",
      wizardDevice: "١. إعدادات الجهاز", wizardSecurity: "٢. إعدادات الحماية", wizardAdvanced: "٣. إعدادات متقدمة",
      wizardApplyNote: "بعد التطبيق اختبر الاتصال ثم ثبّت التغييرات خلال مهلة الحماية الظاهرة. طاقة البث قابلة للاختيار من 1 إلى 38 dBm، وتظهر القيمة المقبولة منفصلة.",
      preview: "معاينة", previewMode: "الوضع", previewManagement: "IP الإدارة (Wi-Fi + الكيبل)", previewVlan: "VLAN",
      previewSsid: "اسم الشبكة", previewSecurity: "الحماية", previewServices: "NAT / DHCP / الجدار الناري", previewTxPower: "طاقة البث 2.4G / 5G",
      subtitle: "لوحة Smart AP محلية: بيانات حية، أصول داخلية، بدون CDN.",
      uptime: "مدة التشغيل", model: "الموديل", firmware: "النظام", internet: "الإنترنت",
      deviceCount: "الأجهزة", updated: "آخر تحديث", traffic: "الترافيك", cpu: "المعالج",
      ram: "الذاكرة", storage: "التخزين", temp: "الحرارة", daily: "اليومي", monthly: "الشهري",
      noQuota: "هذه عدادات حقيقية على حافة العملاء منذ بدء الواجهات. ليست محاسبة يومية أو شهرية أو سنوية، وتعود للصفر بعد إعادة التشغيل أو إعادة تحميل الواجهة.",
      counterWindow: "منذ بدء العدادات", routerCounter: "عداد الراوتر", topologyPartial: "تعذر تحديد منفذ الرفع؛ حُجبت عدادات منافذ DSA وتغطي القيم حواف عملاء Wi-Fi المعروفة فقط.",
      safeAction: "إجراء محمي", cancel: "تم الإلغاء", ok: "سليم", warn: "تنبيه",
      block: "حظر", allow: "سماح", simulated: "لم يتم تطبيق قاعدة جدار ناري. هذا زر واجهة آمن حالياً.",
      networkTitle: "الشبكة · الترافيك والأخطاء", systemTitle: "النظام · المعالج والذاكرة والتخزين",
      emptyEvents: "لا توجد أحداث جديدة.", speedTest: "اختبار سرعة", localTest: "اختبار محلي",
      interval: "فاصل التحديث", budget: "الميزانية", save: "حفظ",
      readApiNow: "قراءة البيانات الآن", reconnect: "إعادة الاتصال", toggleWifi: "تبديل WiFi",
      wifi24: "Wi-Fi 2.4G", wifi5: "Wi-Fi 5G", radioOn: "يعمل", radioOff: "متوقف",
      reboot: "إعادة التشغيل", protected: "محمي", confirmRequired: "يتطلب تأكيد",
      actionsHint: "التأكيدات تحمي الوصول ولا يتم لمس إعداد الطاقة.",
      confirmAgain: "اضغط الزر مرة أخرى خلال 6 ثوانٍ للتأكيد",
      loginSubtitle: "تسجيل الدخول إلى لوحة الراوتر", username: "اسم المستخدم", password: "كلمة السر",
      passwordHint: "كلمة مرور حساب root للراوتر", login: "دخول", logout: "خروج",
      loginWait: "جاري التحقق من بيانات الدخول...", loginBad: "فشل تسجيل الدخول. استخدم root أو admin وكلمة مرور حساب root للراوتر.",
      sessionExpired: "انتهت جلسة الإدارة. أدخل كلمة مرور الراوتر مجدداً.",
      loginRateLimited: "محاولات كثيرة. انتظر دقيقة ثم استخدم كلمة مرور حساب root للراوتر.",
      loginUnavailable: "تعذر الوصول إلى خدمة تسجيل الدخول. تحقق من اتصالك بالراوتر ثم حاول مرة أخرى.",
      localOnly: "محلي · بدون سحابة",
      openWrtSettings: "ضبط OpenWrt", openWrtOpening: "جارٍ فتح إعدادات OpenWrt…",
      openWrtAuthFailed: "تعذر إنشاء جلسة OpenWrt الآمنة. بقيت داخل Smart AP؛ أعد المحاولة.",
      loginOk: "تم تسجيل الدخول", loggedOut: "تم تسجيل الخروج",
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
      vendor: "Vendor", type: "Type", link: "Link", action: "Action", unknownVendor: "Unknown", near: "Near / Strong", mid: "Medium", far: "Far / Weak",
      scanNeighbors: "Scan channels & neighbors", scanning: "Scanning…", bestChannel: "Best channel",
      neighbors: "Neighboring networks", noNeighbors: "No neighboring networks found", applyBest: "Apply best channel",
      scanLan: "Discover devices on the network", lanNeighbors: "Network devices (Neighbors)",
      lanScanHint: "Scans every port and reveals devices behind any switch — shows name, IP, MAC and port.",
      noLanDevices: "No devices found. Check the switch/devices are connected, then scan again.",
      port: "Port", host: "Name", deviceName: "Device name", scanAgain: "Scan again",
      lldpNeighbors: "Managed devices (LLDP/CDP)", noLldpNeighbors: "No managed LLDP/CDP devices found. Make sure the switch/router advertises LLDP, then scan again.", platform: "Platform", localPort: "Our port", remotePort: "Their port",
      portThroughput: "Port throughput (per port)", perPortRate: "Rate per wired port", totalRate: "Total throughput", download: "Download", upload: "Upload", yearly: "Yearly", total: "Total", rename: "Rename device", renamePrompt: "Device name:", limitPrompt: "Speed limit (Mbps):", wifiRate: "WiFi throughput (per band)", portsRate: "Wired ports", clientTraffic: "Down / Up",
      recommended: "Recommended", current: "Current", channel: "Channel", rogueAlert: "Unrecognized BSSID using this SSID", rogueDesc: "Investigate manually; a legitimate mesh node or extender can match",
      healthScore: "System resource score", airtime: "Airtime busy (context)", latency: "Dashboard fetch (context)", noise: "Noise floor",
      clientRadar: "Client radar", linkRate: "Last PHY TX/RX rate — not throughput", constellation: "Client constellation (radius = signal)",
      newDevice: "New device joined", steer5g: "→ 5G", steerHint: "Ask this client to move to 5G",
      selftest: "Self-test", selftestRun: "Run self-test now", selftestHint: "Runs automatically every night at 4:00 AM; you can also run it manually.",
      selftestNotes: "Notes", lastReport: "Last report",
      distance: "Est. distance", secPosture: "SSID encryption snapshot", efficiency: "Link efficiency",
      protected: "Protected", open: "Open", encrypted: "Encrypted", thermal: "Thermal guardian",
      thermalOk: "Normal", thermalWarm: "Warm", thermalHot: "Hot", meters: "m",
      secGood: "No open SSID observed", secOpenWarn: "Open networks", trend: "Signal trend",
      netmgr: "Network", wifimgr: "Wireless", sysmgr: "System",
      quick: "Quick Setup", quickHint: "Program the device step by step: mode, network, protection, advanced — one apply.",
      quickTitle: "Quick programming — AP, VLAN, Mesh, WDS and PPPoE modes",
      quickNote: "Pick a mode, then Save & Apply. Test connectivity and keep the matching transaction within the displayed safety window, otherwise it rolls back automatically.",
      isolationHint: "Protections & port control — each option explained below it.",
      isolationTitle: "Protection & Ports — simple guide",
      isolationNote: "General protection, Wi-Fi isolation and wired-port policy. After Apply, test connectivity and keep the transaction within the displayed safety window or it rolls back automatically.",
      wizardDevice: "1. Device settings", wizardSecurity: "2. Security settings", wizardAdvanced: "3. Advanced settings",
      wizardApplyNote: "After applying, test connectivity and keep the changes within the displayed safety window. TX power can be selected from 1 to 38 dBm; the accepted value is shown separately.",
      preview: "Preview", previewMode: "Mode", previewManagement: "Management IP (Wi-Fi + cable)", previewVlan: "VLAN",
      previewSsid: "SSID", previewSecurity: "Security", previewServices: "NAT / DHCP / firewall", previewTxPower: "TX power 2.4G / 5G",
      subtitle: "Local Smart AP dashboard: live data, offline assets, no CDN.",
      uptime: "Uptime", model: "Model", firmware: "Firmware", internet: "Internet",
      deviceCount: "Devices", updated: "Updated", traffic: "Traffic", cpu: "CPU",
      ram: "RAM", storage: "Storage", temp: "Temperature", daily: "Daily", monthly: "Monthly",
      noQuota: "These are real client-edge counters since the interfaces started. They are not daily, monthly, or yearly billing and reset after a reboot or interface reload.",
      counterWindow: "Since counters started", routerCounter: "Router counter", topologyPartial: "The uplink port could not be identified; DSA-port counters are withheld and the values cover known Wi-Fi client edges only.",
      safeAction: "Protected action", cancel: "Cancelled", ok: "OK", warn: "Warning",
      block: "Block", allow: "Allow", simulated: "No firewall rule was applied. This is a safe UI action for now.",
      networkTitle: "Network · Traffic & Errors", systemTitle: "System · CPU / RAM / Storage",
      emptyEvents: "No new events.", speedTest: "Speed test", localTest: "Local test",
      interval: "Update interval", budget: "Budget", save: "Save",
      readApiNow: "Read API now", reconnect: "Reconnect", toggleWifi: "Toggle WiFi",
      wifi24: "Wi-Fi 2.4G", wifi5: "Wi-Fi 5G", radioOn: "On", radioOff: "Off",
      reboot: "Reboot", protected: "Protected", confirmRequired: "Confirm required",
      actionsHint: "Confirmations protect access; power settings are not touched.",
      confirmAgain: "Press the button again within 6 seconds to confirm",
      loginSubtitle: "Sign in to the router dashboard", username: "Username", password: "Password",
      passwordHint: "Router root account password", login: "Sign in", logout: "Logout",
      loginWait: "Checking credentials...", loginBad: "Sign-in failed. Use root or admin with the router root-account password.",
      sessionExpired: "The management session expired. Enter the router password again.",
      loginRateLimited: "Too many attempts. Wait one minute, then use the router root account password.",
      loginUnavailable: "The sign-in service did not respond. Check the router connection and try again.",
      localOnly: "Local · No cloud",
      openWrtSettings: "OpenWrt Settings", openWrtOpening: "Opening OpenWrt settings…",
      openWrtAuthFailed: "Could not create the secure OpenWrt session. You remain in Smart AP; retry.",
      loginOk: "Signed in", loggedOut: "Signed out",
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
  function sidQuery() { return "session_cookie=1"; }
  function authUrl(url) { return url + (url.indexOf("?") >= 0 ? "&" : "?") + "_=" + Date.now(); }
  function authHeaders(extra) {
    return Object.assign({}, extra || {});
  }
  function markBrowserSession() {
    sessionStorage.setItem(LS + "session", "cookie");
  }
  function fetchWithTimeout(url, options, timeoutMs) {
    var controller = typeof AbortController !== "undefined" ? new AbortController() : null;
    var timer;
    var timerActive = true;
    var requestCleaned = false;
    var requestOptions = Object.assign({}, options || {});
    var upstreamSignal = requestOptions.signal;
    var upstreamAbort = null;
    if (controller) {
      upstreamAbort = function () { try { controller.abort(); } catch (_) {} };
      if (upstreamSignal) {
        if (upstreamSignal.aborted) upstreamAbort();
        else upstreamSignal.addEventListener("abort", upstreamAbort, { once:true });
      }
      requestOptions.signal = controller.signal;
    }
    function clearRequestTimer() {
      if (requestCleaned) return;
      requestCleaned = true;
      if (timerActive) {
        timerActive = false;
        clearTimeout(timer);
      }
      if (upstreamSignal && upstreamAbort)
        upstreamSignal.removeEventListener("abort", upstreamAbort);
    }
    var timeout = new Promise(function (_, reject) {
      timer = setTimeout(function () {
        timerActive = false;
        if (controller) controller.abort();
        var error = new Error("request-timeout");
        error.code = "SMARTAP_TIMEOUT";
        reject(error);
      }, timeoutMs || AUTH_TIMEOUT_MS);
    });
    return Promise.race([fetch(url, requestOptions), timeout]).then(function (response) {
      // Fetch resolves after response headers. Keep the deadline active while
      // JSON/text is read too, so a CGI cannot emit headers and then hang the UI.
      var bodyReaders = ["arrayBuffer", "blob", "formData", "json", "text"];
      bodyReaders.forEach(function (reader) {
        if (!response || typeof response[reader] !== "function") return;
        var original = response[reader].bind(response);
        response[reader] = function () {
          var bodyPromise;
          try {
            bodyPromise = original.apply(null, arguments);
          } catch (error) {
            clearRequestTimer();
            throw error;
          }
          return Promise.race([bodyPromise, timeout]).then(function (value) {
            clearRequestTimer();
            return value;
          }, function (error) {
            clearRequestTimer();
            throw error;
          });
        };
      });
      if (!response || requestOptions.method === "HEAD" ||
          response.status === 204 || response.status === 205 || response.status === 304)
        clearRequestTimer();
      return response;
    }, function (error) {
      clearRequestTimer();
      throw error;
    });
  }
  function isAbortError(error) {
    return !!error && (error.name === "AbortError" || error.code === "ABORT_ERR");
  }
  function postBusyError() {
    var error = new Error(state.lang === "ar"
      ? "يوجد تعديل آخر قيد التنفيذ. انتظر اكتماله ثم أعد المحاولة."
      : "Another router change is still running. Wait for it to finish and retry.");
    error.code = "SMARTAP_POST_BUSY";
    return error;
  }
  async function postJsonLocked(url, options, timeoutMs, button) {
    if (state.postLock) throw postBusyError();
    var token = {}, wasDisabled = !!(button && button.disabled);
    state.postLock = token;
    if (button) button.disabled = true;
    try {
      var requestOptions = Object.assign({}, options || {});
      requestOptions.method = "POST";
      var response = await fetchWithTimeout(url, requestOptions, timeoutMs);
      var data = await response.json();
      return { response:response, data:data };
    } catch (error) {
      // Anything thrown after the mutation lock was acquired is a lost POST
      // result (transport, timeout, aborted body, or truncated JSON).  The
      // caller must recover authoritative server state instead of guessing.
      if (error && typeof error === "object") error.smartapPostFailure = true;
      throw error;
    } finally {
      if (state.postLock === token) state.postLock = null;
      if (button && !wasDisabled && button.isConnected !== false) button.disabled = false;
    }
  }
  function cancelDataRead() {
    state.dataGeneration++;
    if (state.dataController) {
      try { state.dataController.abort(); } catch (_) {}
    }
  }
  function cancelControlRead() {
    state.controlGeneration++;
    if (state.controlReadController) {
      try { state.controlReadController.abort(); } catch (_) {}
    }
    if (state.controlReadBox && state.controlReadBox.dataset)
      delete state.controlReadBox.dataset.loaded;
    state.controlReadController = null;
    state.controlReadBox = null;
  }
  function isDataRequestCurrent(generation, sessionAtStart) {
    return generation === state.dataGeneration && !!state.session && state.session === sessionAtStart;
  }
  function isControlRequestCurrent(generation, section, box) {
    var connected = !!box && (box.isConnected === undefined || box.isConnected);
    return generation === state.controlGeneration && connected && activeControlSection() === section;
  }
  function requireLogin(message) {
    cancelDataRead();
    cancelControlRead();
    state.session = "";
    sessionStorage.removeItem(LS + "session");
    clearInterval(state.timer);
    clearStaleRetry();
    if ($("loginPass")) $("loginPass").value = "";
    showLogin(message || tr("sessionExpired"), true);
  }
  function clearStaleRetry() {
    if (state.staleRetryTimer) clearTimeout(state.staleRetryTimer);
    state.staleRetryTimer = 0;
  }
  function scheduleStaleRetry(delay) {
    clearStaleRetry();
    state.staleRetryTimer = setTimeout(function () {
      state.staleRetryTimer = 0;
      if (state.session) loadData(true);
    }, Math.max(250, Number(delay) || 0));
  }
  function queueFullRefresh(delay) {
    state.lastFullAt = 0;
    state.nextStaleRetryAt = 0;
    setTimeout(function () { if (state.session) loadData(true); }, Math.max(0, Number(delay) || 0));
  }
  function dashboardActionTimeoutMs(name) {
    if (/^wifi_radio[01]$/.test(name || "")) return WIFI_CONTROL_TIMEOUT_MS;
    if (name === "reconnect") return 45000;
    return 30000;
  }
  function controlActionTimeoutMs(section, actionName) {
    var wifiActions = /^(apply_royal|reset_royal|apply_isolation|apply_best_channels|auto_optimize|run_autochannel_now|save_wifi|delete_wifi|save_wifi_radio|set_txpower|wifi_reload|save_guest)$/;
    var networkActions = /^(add_interface|save_interface|delete_interface|add_route|save_dhcp|enable_stp|save_iptv|firewall_reload|restart_dnsmasq|save_firewall_defaults|save_dnsmasq)$/;
    if (wifiActions.test(actionName || "") || /^raw_uci_/.test(actionName || "") || actionName === "resume_pending_apply" || (section === "wizard" && actionName === "apply_royal")) return WIFI_CONTROL_TIMEOUT_MS;
    if (networkActions.test(actionName || "")) return NETWORK_CONTROL_TIMEOUT_MS;
    return CONTROL_TIMEOUT_MS;
  }
  function controlRecoveryWindowMs(section, actionName) {
    var actionTimeout = controlActionTimeoutMs(section, actionName);
    if (actionTimeout >= WIFI_CONTROL_TIMEOUT_MS) return WIFI_RECOVERY_WINDOW_MS;
    return Math.max(RECOVERY_WINDOW_MS, actionTimeout + RECOVERY_GRACE_MS);
  }
  function dashboardRecoveryWindowMs(name) {
    var actionTimeout = dashboardActionTimeoutMs(name);
    if (actionTimeout >= WIFI_CONTROL_TIMEOUT_MS) return WIFI_RECOVERY_WINDOW_MS;
    return Math.max(RECOVERY_WINDOW_MS, actionTimeout + RECOVERY_GRACE_MS);
  }
  function controlPostNeedsRecovery(error) {
    return !!error && error.smartapPostFailure === true && error.code !== "SMARTAP_POST_BUSY";
  }
  function validRecoveryIpv4(value) {
    var parts = String(value || "").split(".");
    if (parts.length !== 4) return "";
    for (var i = 0; i < parts.length; i++) {
      if (!/^[0-9]{1,3}$/.test(parts[i]) || Number(parts[i]) > 255) return "";
      parts[i] = String(Number(parts[i]));
    }
    return parts.join(".");
  }
  function controlRecoveryContext(section, actionName, params) {
    var context = { targetUrl:"" };
    if (!/^[a-z0-9_-]{1,64}$/.test(section || "") || typeof window === "undefined") return context;
    try {
      var query = new URLSearchParams(String(params || "").replace(/^&/, ""));
      var targetHost = "", targetPort = "";
      if (actionName === "save_admin_access") {
        var requestedPort = query.get("http_port") || "";
        if (/^[0-9]{1,5}$/.test(requestedPort) && Number(requestedPort) >= 1 && Number(requestedPort) <= 65535)
          targetPort = String(Number(requestedPort));
      }
      if (actionName === "save_dhcp") targetHost = validRecoveryIpv4(query.get("lan_ipaddr"));
      if (actionName === "apply_royal") targetHost = validRecoveryIpv4(query.get("device_ip"));
      if (!targetHost && !targetPort) return context;
      var target = new URL(window.location.href);
      if (targetHost) target.hostname = targetHost;
      if (targetPort) {
        // http_port changes uhttpd.listen_http even if this page happened to be
        // opened through HTTPS, so point to the listener that was just staged.
        target.protocol = "http:";
        target.port = targetPort;
      }
      target.username = "";
      target.password = "";
      target.pathname = "/";
      target.search = "";
      target.hash = "";
      if (target.origin !== window.location.origin) context.targetUrl = target.href;
    } catch (_) {}
    return context;
  }
  function paintControlRecovery(box, message, context, warning) {
    if (!box) return;
    box.className = "ctl-status" + (warning ? " warn" : "");
    var targetUrl = context && context.targetUrl || "";
    if (!targetUrl) {
      box.textContent = message;
      return;
    }
    var label = state.lang === "ar" ? "فتح عنوان الإدارة الجديد المحتمل" : "Open the possible new management address";
    box.innerHTML = esc(message) + '<br><a class="btn primary" href="' + esc(targetUrl) + '" target="_blank" rel="noopener noreferrer">' + esc(label) + '</a>';
  }
  function applyStatusHasPendingConfirmation(status) {
    return !!status && status.busy === false && status.safe_state === "armed" && status.pending === true &&
      status.confirmation_ready === true && Number(status.remaining_s) > 0 && /^[0-9a-f]{32}$/.test(status.rollback_token || "");
  }
  function applyStatusIsSettled(status) {
    return !!status && status.busy === false && status.safe_state === "clean" && status.pending === false;
  }
  function dashboardActionMayReconnect(name) {
    return name === "reconnect" || /^wifi_radio[01]$/.test(name || "");
  }
  function sleepMs(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
  function recoveryPollDelayMs(attempt) {
    attempt = Math.max(0, Number(attempt) || 0);
    if (attempt < 5) return 2000;
    if (attempt < 15) return 5000;
    return 10000;
  }
  function startControlProgress(box, actionName) {
    var started = Date.now(), stopped = false, timer = 0;
    function paint() {
      if (stopped || !box || (box.isConnected === false)) return;
      var elapsed = Math.max(0, Math.floor((Date.now() - started) / 1000));
      box.className = "ctl-status";
      box.setAttribute("aria-busy", "true");
      box.textContent = (state.lang === "ar"
        ? "جارٍ التطبيق والتحقق (" + elapsed + " ث). أبقِ الصفحة مفتوحة؛ قد يعيد الراوتر الاتصال تلقائياً."
        : "Applying and verifying (" + elapsed + "s). Keep this page open; the router may reconnect automatically.");
    }
    paint();
    timer = setInterval(paint, 1000);
    return function () {
      if (stopped) return;
      stopped = true;
      clearInterval(timer);
      if (box) box.removeAttribute("aria-busy");
    };
  }
  async function readApplyStatus() {
    var res = await fetchWithTimeout(authUrl(CTL + "?section=apply_status"), {
      credentials:"same-origin", cache:"no-store", headers:authHeaders()
    }, RECOVERY_PROBE_TIMEOUT_MS);
    if (res.status === 403) {
      requireLogin(tr("sessionExpired"));
      var authError = new Error("session-expired"); authError.code = "SMARTAP_AUTH"; throw authError;
    }
    if (!res.ok) throw new Error("HTTP " + res.status);
    var data = await res.json();
    if (!data || data.ok !== true) throw new Error("invalid apply status");
    return data;
  }
  function presentPendingApply(section, box, data) {
    var token = data && data.rollback_token || "";
    if (!data || data.ok !== true || data.confirmation_ready !== true || !/^[0-9a-f]{32}$/.test(token) || !box) return false;
    state.controlTokens[section] = token;
    box.dataset.loaded = "1";
    box.className = "";
    var remaining = finite(num(data.remaining_s)) ? " · " + Math.max(0, num(data.remaining_s)) + "s" : "";
    box.innerHTML = '<div class="ctl-card warn"><span>Safe Apply</span><b>' + esc(data.summary || "Confirmation pending") + '</b><small class="latin">' + esc(remaining) + '</small></div>' +
      '<div class="branch-actions"><button class="btn primary" data-ctl-section="' + esc(section) + '" data-ctl-action="keep_changes">' + esc(state.lang === "ar" ? "تثبيت التغييرات" : "Keep changes") + '</button>' +
      '<button class="btn" data-ctl-section="' + esc(section) + '" data-ctl-action="rollback_last" data-ctl-confirm="1">' + esc(state.lang === "ar" ? "رجوع الآن" : "Rollback now") + '</button></div>' +
      '<div class="ctl-note">' + esc(data.text || "Test connectivity before keeping the matching transaction.") + '</div>';
    bindDynamic(box);
    return true;
  }
  async function recoverSessionSafeApply() {
    try {
      var status = await readApplyStatus();
      if (applyStatusHasPendingConfirmation(status)) {
        var pendingBox = quickSafeApplyBox();
        if (presentPendingApply("wizard", pendingBox, status)) {
          toast(state.lang === "ar" ? "توجد تغييرات تنتظر التثبيت أو الرجوع" : "Changes are waiting to be kept or rolled back");
          return true;
        }
      }
      if (status && (status.busy === true || status.pending === true || status.safe_state === "invalid")) {
        var recoveryBox = quickSafeApplyBox();
        if (recoveryBox) {
          paintControlRecovery(recoveryBox, status.text || (state.lang === "ar"
            ? "حالة Safe Apply غير محسومة؛ جارٍ انتظار النتيجة الآمنة."
            : "Safe Apply is unresolved; waiting for the authoritative result."), { targetUrl:"" }, true);
          recoverControlAction("wizard", "resume_pending_apply", recoveryBox).catch(function (error) {
            toast(error && error.message ? error.message : "Safe Apply recovery failed");
          });
        }
        return true;
      }
    } catch (error) {
      if (error && error.code === "SMARTAP_AUTH") return true;
    }
    return false;
  }
  async function recoverControlAction(section, actionName, box, recoveryContext) {
    if (!actionName || !box) return false;
    recoveryContext = recoveryContext || { targetUrl:"" };
    // A failed DFS/ACS apply plus verified restore can occupy the backend's
    // 1700-second worker guard. Recovery follows that worker, not the shorter
    // HTTP request or ordinary three-minute reconnect window.
    var deadline = Date.now() + controlRecoveryWindowMs(section, actionName), attempt = 0;
    box.dataset.loaded = "1";
    while (Date.now() < deadline) {
      if (activeControlSection() !== section || box.isConnected === false) return true;
      box.className = "ctl-status";
      box.textContent = state.lang === "ar"
        ? "تغيّر الاتصال أثناء التطبيق. جارٍ الوصول إلى الراوتر واستعادة حالة الحماية…"
        : "Connection changed during apply. Reaching the router and recovering Safe Apply status…";
      if (recoveryContext.targetUrl) paintControlRecovery(box, box.textContent, recoveryContext, false);
      try {
        var status = await readApplyStatus();
        if (applyStatusHasPendingConfirmation(status) && presentPendingApply(section, box, status)) {
          toast(state.lang === "ar" ? "عاد الاتصال؛ اختر تثبيت التغييرات أو الرجوع" : "Router reconnected; keep or roll back the changes");
          return true;
        }
        if (applyStatusIsSettled(status)) {
          toast(state.lang === "ar" ? "عاد الاتصال بالراوتر؛ جارٍ تحديث الإعدادات" : "Router reconnected; refreshing settings");
          delete state.controlRecoveryTargets[section];
          delete box.dataset.loaded;
          await loadControl(section);
          return true;
        }
        if (status.busy === false) {
          var safeLabel = /^[a-z]+$/.test(status.safe_state || "") ? status.safe_state : "unknown";
          var safetyMessage = state.lang === "ar"
            ? "وصل الراوتر، لكن حالة Safe Apply غير محسومة أو ينقصها رمز تأكيد صالح (" + safeLabel + "). سيستمر الفحص ولن يُفترض النجاح."
            : "The router is reachable, but Safe Apply is unresolved or lacks a valid confirmation token (" + safeLabel + "). Polling continues and success is not assumed.";
          paintControlRecovery(box, safetyMessage, recoveryContext, true);
        }
      } catch (probeError) {
        if (probeError && probeError.code === "SMARTAP_AUTH") return true;
      }
      await sleepMs(recoveryPollDelayMs(attempt++));
    }
    box.className = "ctl-status";
    box.textContent = state.lang === "ar"
      ? "لم يعد الاتصال بعد. اتصل بالشبكة الجديدة أو بمنفذ LAN ثم حدّث الصفحة؛ حماية الرجوع ما زالت هي المرجع ولا تُعرض العملية كفشل مؤكد."
      : "The router is not reachable yet. Join the new network or a LAN port, then refresh; Safe Apply remains authoritative and the operation is not reported as a confirmed failure.";
    paintControlRecovery(box, box.textContent, recoveryContext, true);
    return true;
  }
  async function waitForRouterReachable(name, button) {
    var deadline = Date.now() + dashboardRecoveryWindowMs(name), oldHtml = button && button.innerHTML, attempt = 0;
    function restoreButton() {
      if (!button) return;
      button.disabled = false;
      button.removeAttribute("aria-busy");
      if (oldHtml != null) button.innerHTML = oldHtml;
    }
    if (button) { button.disabled = true; button.setAttribute("aria-busy", "true"); }
    while (Date.now() < deadline) {
      if (button) button.textContent = state.lang === "ar" ? "جارٍ إعادة الاتصال…" : "Reconnecting…";
      try {
        var res = await fetchWithTimeout(authUrl(API + "?lite=1"), { credentials:"same-origin", cache:"no-store", headers:authHeaders() }, RECOVERY_PROBE_TIMEOUT_MS);
        if (res.status === 403) { restoreButton(); requireLogin(tr("sessionExpired")); return true; }
        if (res.ok) {
          await res.text();
          toast(state.lang === "ar" ? "عاد الاتصال بالراوتر" : "Router reconnected");
          queueFullRefresh(0);
          restoreButton();
          return true;
        }
      } catch (_) {}
      await sleepMs(recoveryPollDelayMs(attempt++));
    }
    toast(state.lang === "ar" ? "اتصل بالشبكة الأخرى أو بمنفذ LAN ثم حدّث الصفحة" : "Join the other band or a LAN port, then refresh");
    restoreButton();
    return true;
  }
  function fmt(v, d) { return finite(v) ? v.toLocaleString("en-US", { maximumFractionDigits: d == null ? 1 : d }) : tr("unavailable"); }
  function bytes(v) {
    v = Number(v);
    if (!isFinite(v) || v < 0) return tr("unavailable");
    var u = ["B","KB","MB","GB","TB"], i = 0;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return fmt(v, i === 0 ? 0 : v >= 100 ? 0 : v >= 10 ? 1 : 2) + " " + u[i];
  }
  // Decimal (SI) bytes for TRAFFIC contexts so cumulative totals are consistent
  // with the decimal bps()/Mbps figures on the same page. bytes() stays binary
  // for RAM/storage gauges.
  function bytesNet(v) {
    v = Number(v);
    if (!isFinite(v) || v < 0) return tr("unavailable");
    var u = ["B","KB","MB","GB","TB"], i = 0;
    while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
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
  function localDateKey(value) {
    var d = value instanceof Date ? value : new Date(value == null ? Date.now() : value);
    return [d.getFullYear(), String(d.getMonth() + 1).padStart(2, "0"), String(d.getDate()).padStart(2, "0")].join("-");
  }
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
  function pushHistory(key, value, max, allowWhenSuspended) {
    if (state.suspendHistory && allowWhenSuspended !== true) return;
    if (!state.histories[key]) state.histories[key] = [];
    if (finite(value)) {
      state.histories[key].push(value);
      state.historyDirty = true;
    }
    if (state.histories[key].length > (max || 120)) {
      state.histories[key] = state.histories[key].slice(-(max || 120));
      state.historyDirty = true;
    }
  }
  function saveHistories(force) {
    if (!state.historyDirty) return;
    var wait = force ? 0 : Math.max(0, 15000 - (Date.now() - state.lastHistorySaveAt));
    if (wait > 0) {
      if (!state.historySaveTimer) state.historySaveTimer = setTimeout(function () {
        state.historySaveTimer = 0;
        saveHistories(true);
      }, wait);
      return;
    }
    try {
      localStorage.setItem(LS + "histories", JSON.stringify(state.histories));
      state.historyDirty = false;
      state.lastHistorySaveAt = Date.now();
    } catch (e) {}
  }
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
  // title/chip are always plain text; body is the only trusted-HTML argument.
  function card(title, body, chip, iconName) {
    return '<article class="card"><div class="card-head"><div class="title">' + icon(iconName || "bolt") + '<span>' + esc(title) + '</span></div>' + (chip ? '<span class="chip">' + esc(chip) + '</span>' : "") + '</div>' + body + '</article>';
  }
  function sectionHead(title, desc, chip) {
    return '<div class="section-head"><div><h3>' + esc(title) + '</h3><p>' + esc(desc) + '</p></div>' + (chip ? '<span class="chip">' + esc(chip) + '</span>' : "") + '</div>';
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
    if (!canvas || !canvas.isConnected || canvas.offsetParent === null) return false;
    opts = opts || {};
    var rect = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    if (rect.width < 2 || rect.height < 2) return false;
    var w = Math.max(260, Math.floor(rect.width)), h = Math.max(160, Math.floor(rect.height));
    if (canvas.width !== w * dpr || canvas.height !== h * dpr) { canvas.width = w * dpr; canvas.height = h * dpr; }
    var ctx = canvas.getContext("2d"); ctx.setTransform(dpr,0,0,dpr,0,0); ctx.clearRect(0,0,w,h);
    var muted = cssVar("--muted", "#94A3B8"), grid = cssVar("--border", "rgba(148,163,184,.16)");
    var palette = opts.colors || [cssVar("--accent", "#06B6D4"), cssVar("--primary", "#3B82F6"), cssVar("--good", "#84CC16")];
    var pad = 26, iw = w - pad * 2, ih = h - pad * 2;
    ctx.strokeStyle = grid; ctx.lineWidth = 1;
    for (var g = 0; g < 4; g++) { var y = pad + ih * g / 3; ctx.beginPath(); ctx.moveTo(pad,y); ctx.lineTo(w-pad,y); ctx.stroke(); }
    if (!samples || samples.length < 2) { ctx.fillStyle=muted; ctx.textAlign="center"; ctx.fillText(tr("loading"), w/2, h/2); return true; }
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
    return true;
  }
  // Canvas nodes are replaced whenever live data re-renders a section. Each job
  // owns one generation and must paint the current connected node at a stable
  // size on two consecutive frames. Older jobs can never paint a replacement.
  var chartDrawJobs = Object.create(null);
  function scheduleChartDraw(canvasId, draw) {
    var job = { generation:(chartDrawJobs[canvasId] ? chartDrawJobs[canvasId].generation : 0) + 1, attempts:0, node:null, size:"", stable:0, queued:false, paint:null };
    chartDrawJobs[canvasId] = job;
    function queue() {
      if (job.queued) return;
      job.queued = true;
      function run() {
        job.queued = false;
        paint();
      }
      if (typeof requestAnimationFrame === "function") requestAnimationFrame(run);
      else setTimeout(run, 16);
    }
    function paint() {
      if (chartDrawJobs[canvasId] !== job) return;
      job.attempts++;
      var canvas = $(canvasId);
      if (!canvas || !canvas.isConnected || canvas.offsetParent === null) {
        if (job.attempts < 20) queue();
        return;
      }
      var rect = canvas.getBoundingClientRect();
      var size = Math.round(rect.width * 10) + "x" + Math.round(rect.height * 10);
      if (canvas !== job.node) { job.node = canvas; job.size = ""; job.stable = 0; }
      canvas.dataset.chartGeneration = String(job.generation);
      canvas.dataset.chartStable = "0";
      var painted = !!draw(canvas);
      if (painted && canvas === $(canvasId) && canvas.isConnected) {
        job.stable = size === job.size ? job.stable + 1 : 1;
        job.size = size;
      } else {
        job.stable = 0;
      }
      if (job.stable >= 2) {
        canvas.dataset.chartStable = "1";
        return;
      }
      if (job.attempts < 20) queue();
    }
    job.paint = paint;
    queue();
  }
  // render helpers register chart jobs before their HTML string is inserted.
  // Paint each newly-connected canvas synchronously once, while retaining the
  // queued frame for the second stable-size pass and background-tab recovery.
  function flushScheduledCharts(root) {
    if (!root || !root.querySelectorAll) return;
    Array.prototype.forEach.call(root.querySelectorAll("canvas[id]"), function (canvas) {
      var job = chartDrawJobs[canvas.id];
      if (!job || typeof job.paint !== "function") return;
      try { job.paint(); } catch (e) { /* The already queued frame remains the fallback. */ }
    });
  }
  function totalTraffic(data) {
    return data && data.traffic ? (Number(data.traffic.rx_bytes) || 0) + (Number(data.traffic.tx_bytes) || 0) : 0;
  }
  function trafficRxBytes(data) {
    return data && data.traffic ? Number(data.traffic.rx_bytes) || 0 : 0;
  }
  function trafficTxBytes(data) {
    return data && data.traffic ? Number(data.traffic.tx_bytes) || 0 : 0;
  }
  function verifiedUplinkCapacity(data) {
    var traffic = (data && data.traffic) || {};
    if (traffic.topology_complete !== true) return null;
    var device = String(traffic.uplink_device || "");
    if (!device) return null;
    var interfaces = (data && data.interfaces) || [];
    for (var i = 0; i < interfaces.length; i++) {
      var row = interfaces[i] || {}, speed = num(row.speed_mbps);
      if (String(row.name || "") === device && row.connected === true && finite(speed) && speed > 0)
        return { device:device, speedMbps:speed, bytesPerSecond:speed * 1000000 / 8 };
    }
    return null;
  }
  function trafficCoverageNote(data) {
    return data && data.traffic && data.traffic.topology_complete === true ? "" : tr("topologyPartial");
  }
  function dataUsage(data) {
    // Calendar totals cannot be reconstructed accurately from volatile kernel
    // counters: interface reloads and power loss reset them, and browser-local
    // baselines differed between phones and used UTC boundaries.  Expose the
    // honest router counter window instead of manufacturing Daily/Monthly/Yearly.
    var rx = trafficRxBytes(data), tx = trafficTxBytes(data);
    return {
      rx:rx,
      tx:tx,
      total:rx + tx,
      scope:(data.traffic && data.traffic.counter_window) || "since-interface-reset",
      topologyComplete:!!(data.traffic && data.traffic.topology_complete === true)
    };
  }
  function trafficRates(data, updateBaseline) {
    var now = Date.now(), rx = data.traffic ? Number(data.traffic.rx_bytes) || 0 : 0, tx = data.traffic ? Number(data.traffic.tx_bytes) || 0 : 0;
    var rxBps = data.traffic ? Number(data.traffic.rx_bps) || 0 : 0, txBps = data.traffic ? Number(data.traffic.tx_bps) || 0 : 0;
    var signature = data.traffic ? String(data.traffic.counter_signature || "") : "missing-client-edge";
    // Use the client byte-delta as the single consistent rate source whenever a
    // matching-signature baseline exists (server rx_bps/tx_bps is only the
    // first-sample fallback). Mixing the server's ~10-60s average with the
    // client's ~poll-interval delta made the headline/sparkline jump periodically.
    if (updateBaseline && signature && state.previousTraffic &&
        state.previousTraffic.signature === signature && state.previousAt &&
        now > state.previousAt) {
      var dt = Math.max(1, (now - state.previousAt) / 1000);
      rxBps = Math.max(0, (rx - state.previousTraffic.rx) / dt);
      txBps = Math.max(0, (tx - state.previousTraffic.tx) / dt);
    }
    if (updateBaseline) {
      state.previousTraffic = { rx:rx, tx:tx, signature:signature }; state.previousAt = now;
    }
    return { rx:rxBps, tx:txBps, totalRx:rx, totalTx:tx };
  }
  function stationTraffic(sta) {
    sta = sta || {};
    var up = num(sta.upload_bps), down = num(sta.download_bps);
    var upBytes = num(sta.upload_bytes), downBytes = num(sta.download_bytes);
    var hasCounters = finite(upBytes) || finite(downBytes);
    var hasRate = finite(up) || finite(down);
    return {
      up: finite(up) ? up : 0,
      down: finite(down) ? down : 0,
      upBytes: finite(upBytes) ? upBytes : 0,
      downBytes: finite(downBytes) ? downBytes : 0,
      hasCounters: hasCounters,
      hasRate: hasRate,
      rateSource: hasRate ? "byte-counter-delta" : ""
    };
  }
  function stationTrafficRows(data) {
    var rows = [];
    ((data && data.wifi) || []).forEach(function (w) {
      (w.stations || []).forEach(function (s) {
        var t = stationTraffic(s);
        // Per-client consumption must come from byte-counter deltas.  A PHY
        // link rate (or the driver's expected throughput estimate) is not
        // traffic and must never be used as a fallback here.
        if (!t.hasRate) return;
        rows.push({
          label: s.ip || s.mac || "?",
          mac: s.mac || "",
          band: w.band || "",
          up: t.up,
          down: t.down,
          totalRate: t.up + t.down,
          upBytes: t.upBytes,
          downBytes: t.downBytes,
          totalBytes: t.upBytes + t.downBytes,
          rateSource: t.rateSource
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
      '<div class="traffic-box"><span>' + downLabel + '</span><b class="latin">' + bps(t.down) + '</b><small class="muted">' + bytesNet(t.downBytes) + '</small></div>' +
      '<div class="traffic-box"><span>' + upLabel + '</span><b class="latin">' + bps(t.up) + '</b><small class="muted">' + bytesNet(t.upBytes) + '</small></div></div>';
  }
  function parseStationRateDetail(sta, direction) {
    sta = sta || {};
    direction = direction === "rx" ? "rx" : "tx";
    var detail = sta[direction + "_rate_detail"];
    if (detail === null || detail === undefined || detail === "")
      detail = sta[direction === "tx" ? "txRateDetail" : "rxRateDetail"];
    detail = detail === null || detail === undefined ? "" : String(detail).replace(/^\s+|\s+$/g, "");
    var rate = num(sta[direction + "_rate"]);
    if (!finite(rate)) rate = num(sta[direction === "tx" ? "txRate" : "rxRate"]);
    var rateMatch = detail.match(/([0-9]+(?:\.[0-9]+)?)\s*([KMG])?Bit\/s\b/i);
    if (rateMatch) {
      rate = Number(rateMatch[1]);
      var unit = String(rateMatch[2] || "M").toUpperCase();
      if (unit === "K") rate /= 1000;
      else if (unit === "G") rate *= 1000;
    }

    var width = null, widthMatch = detail.match(/(?:^|[\s,])(20|40|80|160|320)\s*MHz\b/i);
    if (widthMatch) width = Number(widthMatch[1]);

    var family = "", mcs = null, nss = null, nssSource = "";
    var mcsMatch = detail.match(/\b(EHT|HE|VHT)-MCS\s*([0-9]+)\b/i);
    if (mcsMatch) {
      family = String(mcsMatch[1]).toUpperCase();
      mcs = Number(mcsMatch[2]);
    } else {
      mcsMatch = detail.match(/(?:^|[\s,])MCS\s*([0-9]+)\b/i);
      if (mcsMatch) {
        family = "HT";
        mcs = Number(mcsMatch[1]);
      }
    }

    // HE/VHT/EHT NSS is used only when the driver explicitly reports it.
    // HT MCS 0..31 encodes the stream count in the standard MCS index, so
    // deriving it from that index is exact and does not guess from Mbps.
    var nssMatch = detail.match(/\b(?:EHT|HE|VHT)-NSS\s*([1-8])\b/i);
    if (nssMatch) {
      nss = Number(nssMatch[1]);
      nssSource = "reported";
    } else if (family === "HT" && mcs !== null && mcs >= 0 && mcs <= 31) {
      nss = Math.floor(mcs / 8) + 1;
      nssSource = "ht-mcs";
    }

    var gi = null, shortGi = /\bshort[\s_-]+GI\b/i.test(detail);
    var giMatch = detail.match(/\b(?:EHT|HE)-GI\s*([0-9]+(?:\.[0-9]+)?)\b/i);
    if (giMatch) gi = Number(giMatch[1]);
    else if (shortGi) gi = "short";

    return {
      raw: detail,
      rate: finite(rate) ? rate : null,
      family: family,
      mcs: mcs,
      nss: nss,
      nssSource: nssSource,
      gi: gi,
      shortGi: shortGi,
      width: width
    };
  }
  function stationRateDetail(sta, direction) {
    var info = parseStationRateDetail(sta, direction);
    if (info.raw) return info.raw;
    return finite(info.rate) ? fmt(info.rate, info.rate < 100 ? 1 : 0) + " MBit/s" : "";
  }
  function stationReportedNss(sta, direction) {
    var info = parseStationRateDetail(sta, direction || "tx");
    return finite(info.nss) ? info.nss : null;
  }
  function stationInactiveAge(ms) {
    ms = num(ms);
    if (!finite(ms)) return "";
    return ms < 1000 ? fmt(ms, 0) + " ms" : ms < 60000 ? fmt(ms / 1000, ms < 10000 ? 1 : 0) + " s" : ms < 3600000 ? fmt(ms / 60000, 1) + " min" : fmt(ms / 3600000, 1) + " h";
  }
  function radioWidthMHz(radio) {
    radio = radio || {};
    var width = num(radio.width);
    if (finite(width) && /^(20|40|80|160|320)$/.test(String(Math.round(width)))) return Math.round(width);
    var match = String(radio.htmode || "").toUpperCase().match(/(20|40|80|160|320)\b/);
    return match ? Number(match[1]) : null;
  }
  function configuredPhyCeiling2x2(radio) {
    radio = radio || {};
    var mode = String(radio.htmode || "").toUpperCase(), width = radioWidthMHz(radio);
    var family = /^EHT/.test(mode) ? "EHT" : /^HE/.test(mode) ? "HE" : /^VHT/.test(mode) ? "VHT" : /^HT/.test(mode) ? "HT" : "";
    var tables = {
      HE: { 20:286.8, 40:573.5, 80:1201.0, 160:2402.0 },
      VHT: { 20:173.3, 40:400.0, 80:866.7, 160:1733.3 },
      HT: { 20:144.4, 40:300.0 }
    };
    var mbps = tables[family] && width !== null ? tables[family][width] : null;
    return finite(mbps) ? { family:family, width:width, nss:2, mbps:mbps, mode:mode } : null;
  }
  function stationRateSnapshots(data, direction) {
    var rows = [];
    ((data && data.wifi) || []).forEach(function (radio) {
      (radio.stations || []).forEach(function (sta) {
        var info = parseStationRateDetail(sta, direction || "tx");
        if (!info.raw && !finite(info.rate)) return;
        rows.push({ radio:radio, station:sta, info:info, capacity:configuredPhyCeiling2x2(radio) });
      });
    });
    return rows;
  }
  function stationPhyHtml(sta, compact) {
    sta = sta || {};
    var tx = stationRateDetail(sta, "tx"), rx = stationRateDetail(sta, "rx");
    var retries = num(sta.tx_retries), failed = num(sta.tx_failed), inactive = num(sta.inactive_ms);
    var rows = '<small class="muted" style="display:block"><b>' + esc(state.lang === "ar" ? "آخر لقطة PHY" : "Last PHY snapshot") + '</b></small>', stats = [];
    var txLabel = state.lang === "ar" ? "آخر معدل PHY TX:" : "Last PHY TX:";
    var rxLabel = state.lang === "ar" ? "آخر معدل PHY RX:" : "Last PHY RX:";
    if (tx) rows += '<small style="display:block"><b>' + esc(txLabel) + '</b> <span class="latin" dir="ltr">' + esc(tx) + '</span></small>';
    if (rx) rows += '<small style="display:block"><b>' + esc(rxLabel) + '</b> <span class="latin" dir="ltr">' + esc(rx) + '</span></small>';
    if (finite(retries)) stats.push((state.lang === "ar" ? "إعادات الإرسال " : "Retries ") + fmt(retries, 0));
    if (finite(failed)) stats.push((state.lang === "ar" ? "فشل الإرسال " : "Failed ") + fmt(failed, 0));
    if (finite(inactive)) {
      var inactiveText = stationInactiveAge(inactive);
      stats.push((state.lang === "ar" ? "الخمول " : "Inactive ") + inactiveText);
    }
    if (stats.length) rows += '<small class="muted" style="display:block">' + esc(stats.join(" · ")) + '</small>';
    if (!rows) return "";
    var sleeping = finite(inactive) && inactive >= 60000;
    var note = sleeping
      ? (state.lang === "ar" ? "العميل خامل/نائم؛ انخفاض آخر معدل PHY حتى 1 Mbps طبيعي أثناء السكون ولا يقيس سرعة النقل." : "Client is idle/asleep; a last PHY rate as low as 1 Mbps is normal during sleep and does not measure throughput.")
      : (state.lang === "ar" ? "آخر معدل PHY لحظي كما تراه نقطة الوصول؛ ليس سرعة نقل البيانات." : "Last instantaneous PHY rate reported by the AP; not traffic throughput.");
    return '<div class="station-phy" style="margin-top:' + (compact ? "3" : "6") + 'px;white-space:normal;word-break:break-word">' + rows +
      '<small class="muted" style="display:block">' + esc(note) + '</small></div>';
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
    (data.wifi || []).forEach(function (w) { (w.stations || []).forEach(function (s) { var k = String(s.mac || Math.random()).toLowerCase(); var t = stationTraffic(s); map[k] = Object.assign(map[k] || {}, { mac:s.mac, ip:s.ip || (map[k]||{}).ip, iface:w.iface, type:"WiFi", signal:s.signal_dbm, rate:s.tx_rate, txRate:s.tx_rate, rxRate:s.rx_rate, tx_rate:s.tx_rate, rx_rate:s.rx_rate, tx_rate_detail:s.tx_rate_detail, rx_rate_detail:s.rx_rate_detail, tx_retries:s.tx_retries, tx_failed:s.tx_failed, inactive_ms:s.inactive_ms, down:t.down, up:t.up, downBytes:t.downBytes, upBytes:t.upBytes, hasTraffic:t.hasCounters }); }); });
    // Owner rule: the devices list shows Wi-Fi clients ONLY (2.4G + 5G). Wired/managed
    // gear on lan1..wan already appears in the LLDP/CDP neighbours section — no repeats.
    return Object.keys(map).map(function (k) { map[k].vendor = ouiVendor(map[k].mac); return map[k]; }).filter(function (e) { return e.type === "WiFi"; });
  }
  function wifiBand(data, band) { return (data.wifi || []).filter(function (w) { return w.band === band; })[0] || null; }
  function updateAvailability(ok) {
    var t = Date.now();
    var bucketMs = 5 * 60 * 1000;
    var bucket = Math.floor(t / bucketMs) * bucketMs;
    var last = state.availability[state.availability.length - 1];
    var changed = false;
    if (last && last.t === bucket) {
      // Preserve any failure observed inside the five-minute bucket.
      var bucketOk = last.ok && !!ok;
      if (bucketOk !== last.ok) { last.ok = bucketOk; changed = true; }
    } else {
      state.availability.push({ t:bucket, ok:!!ok });
      changed = true;
    }
    var cutoff = t - 24 * 3600 * 1000;
    var retained = state.availability.filter(function (x) { return x.t >= cutoff; }).slice(-288);
    if (retained.length !== state.availability.length) changed = true;
    state.availability = retained;
    if (changed) try { localStorage.setItem(LS + "availability", JSON.stringify(state.availability)); } catch (e) {}
  }
  function availabilityHtml() {
    if (!state.availability.length) return '<div class="empty">' + tr("loading") + '</div>';
    var bucketMs = 5 * 60 * 1000, end = Math.floor(Date.now() / bucketMs) * bucketMs, byTime = Object.create(null);
    state.availability.forEach(function (x) { byTime[x.t] = x; });
    var cells = [];
    for (var i = 287; i >= 0; i--) {
      var at = end - i * bucketMs, sample = byTime[at], color = sample ? (sample.ok ? "var(--excellent)" : "var(--weak)") : "var(--muted)";
      var status = sample ? (sample.ok ? (state.lang === "ar" ? "مرصود متاح" : "observed available") : (state.lang === "ar" ? "مرصود غير متاح" : "observed unavailable")) : (state.lang === "ar" ? "غير مرصود" : "not observed");
      cells.push('<i title="' + esc(new Date(at).toLocaleString() + " · " + status) + '" style="border-radius:4px;background:' + color + ';opacity:' + (sample ? '1' : '.25') + '"></i>');
    }
    return '<div style="display:grid;grid-template-columns:repeat(288,1fr);gap:1px;height:34px">' + cells.join("") + '</div>' +
      '<small class="muted">' + esc(state.lang === "ar" ? "مراقبة هذا المتصفح خلال آخر 24 ساعة؛ الفجوات رمادية وليست نجاحاً." : "Observed by this browser over the last 24h; grey gaps are unknown, not successful checks.") + '</small>';
  }
  function hideToast() {
    var el = $("toast");
    if (el) el.classList.remove("show");
    document.body.classList.remove("toast-visible");
  }
  function toast(msg) {
    var el = $("toast"); if (!el) return;
    el.textContent = msg;
    el.classList.add("show");
    document.body.classList.add("toast-visible");
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(hideToast, 3500);
  }
  function event(msg, type) {
    state.events.unshift({ t:Date.now(), msg:msg, type:type || "info" });
    state.events = state.events.slice(0, 80);
    // Persist only meaningful events; never store transient "error" alerts so they
    // don't replay as stale "Failed to fetch" after the panel recovers or reloads.
    if ((type || "info") !== "error")
      try { localStorage.setItem(LS + "events", JSON.stringify(state.events.filter(function (e) { return e.type !== "error"; }))); } catch (e) {}
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
    text("loginBtn", state.loginPending ? tr("loginWait") : tr("login"));
    var pass = $("loginPass");
    if (pass) pass.placeholder = tr("passwordHint");
    var user = $("loginUser");
    if (user && !user.value) user.value = "root";
    text("loginLocalMeta", tr("localOnly"));
  }
  function setLoginBusy(busy) {
    state.loginPending = !!busy;
    var button = $("loginBtn");
    if (button) {
      button.disabled = state.loginPending;
      button.setAttribute("aria-busy", state.loginPending ? "true" : "false");
      button.textContent = state.loginPending ? tr("loginWait") : tr("login");
    }
    var user = $("loginUser"), pass = $("loginPass");
    if (user) user.disabled = state.loginPending;
    if (pass) pass.disabled = state.loginPending;
  }
  function showLogin(msg, bad) {
    clearInterval(state.timer);
    clearStaleRetry();
    if ($("appShell")) $("appShell").hidden = true;
    if ($("loginScreen")) $("loginScreen").hidden = false;
    setLoginText();
    loginMessage(msg || "", bad);
    setTimeout(function () {
      var pass = $("loginPass"), user = $("loginUser");
      if (pass && !pass.value) pass.focus();
      else if (user) user.focus();
    }, 60);
  }
  function showDashboard() {
    if ($("loginScreen")) $("loginScreen").hidden = true;
    if ($("appShell")) $("appShell").hidden = false;
    loginMessage("", false);
    showSection("overview");
    startPolling();
  }
  async function syncBrowserTime() {
    if (!state.session) return;
    try {
      await postJsonLocked(CTL, {
        credentials:"same-origin",
        cache:"no-store",
        headers:authHeaders({ "Content-Type":"application/x-www-form-urlencoded" }),
        body:"section=system&action=sync_time&epoch=" + Math.floor(Date.now() / 1000) + "&" + sidQuery()
      }, 5000);
    } catch (e) {
      // Time sync is best effort; normal dashboard operation must remain available.
    }
  }
  async function revokeServerSessions() {
    var res = await fetchWithTimeout("/cgi-bin/dashlogout", {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: "session_cookie=1"
    }, 8000);
    var data = await res.json().catch(function () { return {}; });
    if (!res.ok || !data.ok) throw new Error(data.error || "session revocation failed");
    return true;
  }
  async function ensureLuciSession() {
    if (!state.session) throw new Error("Smart AP session is missing");
    var res = await fetchWithTimeout("/cgi-bin/dashluci", {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: authHeaders({ "Content-Type": "application/x-www-form-urlencoded" }),
      body: "session_cookie=1"
    }, AUTH_TIMEOUT_MS);
    var data = await res.json().catch(function () { return {}; });
    if (!res.ok || !data.ok) {
      var error = new Error(data.error || "LuCI session failed");
      error.status = res.status;
      throw error;
    }
    return true;
  }
  async function login(username, password) {
    if (state.loginPending) return;
    setLoginBusy(true);
    loginMessage(tr("loginWait"), false);
    try {
      await startupSessionCleanup;
      // The device still has one privileged account.  `admin` is only a UI alias
      // for that root account and the CGI remains the authoritative allowlist.
      // Normalize case/whitespace here so typed and password-manager values use
      // the same contract on mobile and desktop without copying any credential.
      var user = String(username || "root").replace(/^\s+|\s+$/g, "").toLowerCase() || "root";
      if ($("loginUser")) $("loginUser").value = user;
      var pass = password || "";
      var res = await fetchWithTimeout("/cgi-bin/dashlogin", {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username:user, password:pass })
      }, AUTH_TIMEOUT_MS);
      var data = await res.json().catch(function () { return {}; });
      if (!res.ok || !data.ok) {
        var loginError = new Error(res.status === 429
          ? tr("loginRateLimited")
          : res.status === 401
            ? tr("loginBad")
            : tr("loginUnavailable"));
        loginError.status = res.status;
        throw loginError;
      }
      state.session = "cookie";
      markBrowserSession();
      toast(tr("loginOk"));
      showDashboard();
      recoverSessionSafeApply().then(function (pending) { if (!pending) syncBrowserTime(); });
    } catch (e) {
      if (state.session) {
        try { await revokeServerSessions(); } catch (cleanupError) {}
      }
      state.session = "";
      sessionStorage.removeItem(LS + "session");
      var unavailable = e && (e.code === "SMARTAP_TIMEOUT" || e.name === "AbortError" || e instanceof TypeError);
      showLogin(unavailable ? tr("loginUnavailable") : (e.message || tr("loginBad")), true);
    } finally {
      setLoginBusy(false);
    }
  }
  async function validateSession() {
    if (!state.session) return false;
    try {
      // Session validation must never wait for the full hardware collector. The
      // lite route performs the same cookie check before its bounded procfs read.
      var res = await fetchWithTimeout(authUrl(API + "?lite=1&probe=1"), { credentials:"same-origin", cache:"no-store", headers:authHeaders() }, 8000);
      if (res.status === 401 || res.status === 403) {
        state.session = "";
        sessionStorage.removeItem(LS + "session");
        return false;
      }
      if (res.status !== 200) return null;
      var data = await res.json();
      if (data && data.ok === true) return true;
      if (data && (data.authenticated === false || data.error === "forbidden")) {
        state.session = "";
        sessionStorage.removeItem(LS + "session");
        return false;
      }
      return null;
    } catch (e) {
      // A timeout/503 is not evidence that the HttpOnly session is invalid.
      // Keep it and retry instead of asking for the password again.
      return null;
    }
  }
  async function logout() {
    clearInterval(state.timer);
    clearStaleRetry();
    cancelDataRead();
    cancelControlRead();
    try {
      await revokeServerSessions();
      state.session = "";
      sessionStorage.removeItem(LS + "session");
      if ($("loginPass")) $("loginPass").value = "";
      showLogin(tr("loggedOut"), false);
    } catch (e) {
      startPolling();
      toast(e.message || tr("loginBad"));
    }
  }

  function renderChrome() {
    var activeSection = document.body.dataset.activeSection || "overview";
    document.documentElement.lang = state.lang;
    document.documentElement.dir = state.lang === "ar" ? "rtl" : "ltr";
    document.documentElement.dataset.theme = state.theme;
    $("heroSubtitle").textContent = tr("subtitle");
    $("refreshBtn").textContent = tr("refresh");
    $("themeBtn").textContent = state.theme === "dark" ? tr("dark") : tr("light");
    $("themeBtn").classList.toggle("active", state.theme === "dark");
    $("themeBtn").setAttribute("aria-pressed", state.theme === "dark" ? "true" : "false");
    if ($("logoutBtn")) $("logoutBtn").textContent = tr("logout");
    if ($("openWrtBtn")) $("openWrtBtn").textContent = tr("openWrtSettings");
    $("intervalSelect").value = String(state.interval);
    ["langAr", "loginLangAr"].forEach(function (id) {
      if ($(id)) { $(id).className = state.lang === "ar" ? "active" : ""; $(id).setAttribute("aria-pressed", state.lang === "ar" ? "true" : "false"); }
    });
    ["langEn", "loginLangEn"].forEach(function (id) {
      if ($(id)) { $(id).className = state.lang === "en" ? "active" : ""; $(id).setAttribute("aria-pressed", state.lang === "en" ? "true" : "false"); }
    });
    $("brandMark").innerHTML = icon("wifi");
    var nav = [
      ["overview","overview","bolt"],
      ["quick","quick","gear"],
      ["isolation","isolation","shield"],
      ["devices","devices","device"],
      ["wifi","wifi","wifi"],
      ["insights","insights","signal"],
      ["network","network","net"],
      ["system","system","cpu"],
      ["actions","actions","gear"]
    ];
    $("nav").innerHTML = nav.map(function (n) {
      var active = n[0] === activeSection;
      return '<button data-section="' + n[0] + '" class="' + (active ? "active" : "") + '"' + (active ? ' aria-current="page"' : "") + '>' + icon(n[2]) + '<span>' + tr(n[1]) + '</span></button>';
    }).join("");
    Array.prototype.forEach.call(document.querySelectorAll("[data-section]"), function (b) {
      b.onclick = function () { showSection(b.dataset.section); };
    });
    setLoginText();
  }
  function showSection(id) {
    cancelControlRead();
    document.body.dataset.activeSection = id;
    ["overview","network","devices","wifi","insights","system","quick","isolation","actions"].forEach(function (s) { if ($(s)) $(s).hidden = s !== id; });
    Array.prototype.forEach.call(document.querySelectorAll("[data-section]"), function (b) {
      var active = b.dataset.section === id;
      b.classList.toggle("active", active);
      if (active) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current");
    });
    if (adminGroups()[id] && $(id) && (!$(id).innerHTML || $(id).dataset.uiVersion !== UI_VERSION)) {
      $(id).innerHTML = renderAdminBranch(id);
      $(id).dataset.uiVersion = UI_VERSION;
      bindDynamic($(id));
    }
    if (id === "isolation" && $("isolation") && $("isolation").dataset.uiVersion !== UI_VERSION) {
      $("isolation").innerHTML = renderIsolation();
      $("isolation").dataset.uiVersion = UI_VERSION;
      bindDynamic($("isolation"));
      loadControl("isolation");
    }
    if (id === "quick" && $("quick") && $("quick").dataset.uiVersion !== UI_VERSION) {
      $("quick").innerHTML = renderQuick();
      $("quick").dataset.uiVersion = UI_VERSION;
      bindDynamic($("quick"));
      loadControl("wizard");
    }
    if (state.latest && /^(overview|network|devices|wifi|insights|system|actions)$/.test(id)) {
      var priorSuspendHistory = state.suspendHistory;
      state.suspendHistory = snapshotIsStale(state.latest);
      try {
        renderLiveSection(id, state.latest, trafficRates(state.latest, false));
      } finally {
        state.suspendHistory = priorSuspendHistory;
      }
    }
    var main = document.querySelector(".main");
    if (main) main.scrollTo({ top:0, behavior:"auto" });
    window.scrollTo({ top:0, behavior:"auto" });
    setTimeout(loadActiveControl, 0);
    if (state.latest && /^(network|devices|wifi|insights)$/.test(id) && Date.now() - state.lastFullAt > 5000) {
      setTimeout(function () { loadData(true); }, 0);
    }
  }
  function openSmartSettings() {
    showSection("overview");
  }
  function snapshotIsStale(data) {
    return !!data && (data.snapshot_stale === true || data.snapshot_invalidated === true);
  }
  function cachedStatusLabel() {
    return state.lang === "ar" ? "\u0628\u064a\u0627\u0646\u0627\u062a \u0645\u062e\u0632\u0646\u0629" : "Cached data";
  }
  function detailStatusLabel(data, entries) {
    if (snapshotIsStale(data)) return cachedStatusLabel();
    if (!Array.isArray(entries)) return tr("unavailable");
    if (entries.some(function (entry) { return entry && entry.up === true && entry.disabled !== true; })) return tr("online");
    if (entries.length && entries.every(function (entry) { return entry && (entry.disabled === true || entry.up === false); })) return tr("offline");
    return entries.length ? tr("loading") : tr("unavailable");
  }
  function emptyDevicesLabel(data) {
    var inventoryAvailable = Array.isArray(data && data.devices) || Array.isArray(data && data.wifi);
    if (!inventoryAvailable) return tr("unavailable");
    if (snapshotIsStale(data))
      return state.lang === "ar"
        ? "\u0644\u0627 \u062a\u0648\u062c\u062f \u0623\u062c\u0647\u0632\u0629 \u0641\u064a \u0622\u062e\u0631 \u0644\u0642\u0637\u0629 \u0645\u062e\u0632\u0646\u0629"
        : "No devices in the latest cached snapshot";
    return state.lang === "ar" ? "\u0644\u0627 \u062a\u0648\u062c\u062f \u0623\u062c\u0647\u0632\u0629 \u0645\u062a\u0635\u0644\u0629" : "No connected devices";
  }
  function renderKpis(data, rates, liveCounters) {
    var w24 = wifiBand(data, "2.4G"), w5 = wifiBand(data, "5G");
    var back = data.backhaul || {}, internet = back.online ? (back.device || tr("online")) : tr("lanOnly");
    var snapshotAge = Math.max(0, num(data.snapshot_age_s) || 0);
    var updatedValue = snapshotIsStale(data)
      ? (state.lang === "ar" ? "لقطة مخزنة منذ " : "Cached ") + uptime(snapshotAge)
      : nowTime();
    var osValue = String(data.os || "").trim();
    var osMatch = osValue.match(/OpenWrt\s+([0-9]+(?:\.[0-9]+)+)/i);
    var firmwareSummary = osMatch ? "OpenWrt " + osMatch[1] : (osValue || "OpenWrt");
    var list = [
      [tr("uptime"), uptime(data.uptime), "uptime", 1],
      [tr("model"), data.model || tr("unavailable"), "model", 1],
      [tr("firmware"), firmwareSummary, "firmware", 1],
      [tr("internet"), internet, "internet", back.online ? 1 : 0],
      [tr("deviceCount"), String(Math.max(mergeDevices(data).length, (w24?Number(w24.clients)||0:0)+(w5?Number(w5.clients)||0:0))), "devices", 1],
      ["2.4G", w24 ? ((w24.ssid || "2.4G") + " · " + (w24.clients || 0)) : tr("unavailable"), "w24", w24 ? 1 : 0],
      ["5G", w5 ? ((w5.ssid || "5G") + " · " + (w5.clients || 0)) : tr("unavailable"), "w5", w5 ? 1 : 0],
      [tr("updated"), updatedValue, "updated", snapshotIsStale(data) ? 0 : 1]
    ];
    pushHistory("kpiRx", rates.rx, 60, liveCounters); pushHistory("kpiTx", rates.tx, 60, liveCounters);
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
    var rxLabel = "↓ " + tr("download");
    var txLabel = "↑ " + tr("upload");
    var complete = !!(data.traffic && data.traffic.topology_complete === true);
    var body = '<canvas id="' + canvasId + '"></canvas><div class="grid two" style="margin-top:12px">' +
      '<div class="traffic-box"><span>' + rxLabel + '</span><b class="latin">' + bps(rates.rx) + '</b><small class="muted">' + bytesNet(rates.totalRx) + '</small></div>' +
      '<div class="traffic-box"><span>' + txLabel + '</span><b class="latin">' + bps(rates.tx) + '</b><small class="muted">' + bytesNet(rates.totalTx) + '</small></div></div>' +
      (complete ? "" : '<p class="ctl-note">' + esc(trafficCoverageNote(data)) + '</p>');
    scheduleChartDraw(canvasId, function (canvas) {
      return drawChart(canvas, samples, { keys:["rx","tx"], labels:[tr("download"),tr("upload")] });
    });
    return card(tr("networkTitle"), body, snapshotIsStale(data) ? cachedStatusLabel() : (complete ? "60s peaks" : (state.lang === "ar" ? "حواف Wi-Fi فقط" : "Wi-Fi edges only")), "net");
  }
  // Client-edge download / upload split for a counter window — three clean rows.
  // so the numbers never wrap/overlap on a narrow phone screen.
  function usageRow(icon, label, val, color) {
    return '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin:3px 0;font-size:12px">' +
      '<span class="muted">' + icon + ' ' + esc(label) + '</span>' +
      '<b class="latin" style="color:' + color + ';white-space:nowrap">' + bytesNet(val) + '</b></div>';
  }
  function usageSplit(label, download, upload) {
    return '<div class="traffic-box" style="text-align:start">' +
      '<span style="font-weight:700">' + esc(label) + '</span>' +
      usageRow("↓", tr("download"), download, "var(--accent)") +
      usageRow("↑", tr("upload"), upload, "var(--primary)") +
      usageRow("Σ", tr("total") || "Σ", download + upload, "var(--text)") +
      '</div>';
  }
  function renderData(data) {
    var u = dataUsage(data);
    var totalLabel = u.topologyComplete ? tr("total") : (state.lang === "ar" ? "الإجمالي المرصود" : "Observed subtotal");
    var body = '<div class="grid two">' +
      usageSplit(tr("counterWindow"), u.rx, u.tx) +
      '<div class="traffic-box" style="text-align:start"><span style="font-weight:700">' + esc(totalLabel) + '</span><b class="latin" style="display:block;font-size:22px;margin-top:8px;color:var(--accent)">' + bytesNet(u.total) + '</b><small class="muted">' + esc(tr("routerCounter")) + '</small></div>' +
      '</div><p class="muted">' + esc(tr("noQuota")) + '</p>' +
      (u.topologyComplete ? "" : '<p class="ctl-note">' + esc(tr("topologyPartial")) + '</p>');
    return card(tr("traffic"), body, tr("routerCounter"), "bolt");
  }
  function proximity(dbm) {
    var v = num(dbm);
    if (v === null || !finite(v)) return "";
    var lvl = v >= -67 ? "near" : v >= -77 ? "mid" : "far";
    var col = v >= -67 ? "var(--excellent)" : v >= -77 ? "var(--good)" : "var(--weak)";
    var ico = v >= -67 ? "●●●" : v >= -77 ? "●●" : "●";
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
  // Client-edge view: callers convert AP/DSA interface TX to client download and
  // interface RX to client upload before reaching this renderer.
  function throughputRow(label, download, upload, up, chip) {
    var tot = (finite(download) ? download : 0) + (finite(upload) ? upload : 0);
    var downPct = tot > 0 ? (finite(download) ? download : 0) / tot * 100 : 0;
    return '<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><b class="latin">' + esc(label) +
      '</b><span class="latin">' + (chip ? '<span class="chip ' + (up === false ? "bad" : "ok") + '" style="font-size:10px">' + esc(chip) + '</span>' : "") + '</span></div>' +
      '<div style="display:flex;justify-content:space-between;font-size:11px;color:var(--muted)"><span>↓ ' + esc(tr("download")) + ' ' + (finite(download) ? bps(download) : "—") + '</span><span>↑ ' + esc(tr("upload")) + ' ' + (finite(upload) ? bps(upload) : "—") + '</span></div>' +
      '<div style="display:flex;height:5px;border-radius:4px;overflow:hidden;margin-top:4px"><div style="width:' + downPct.toFixed(1) + '%;background:var(--accent)"></div><div style="width:' + (100-downPct).toFixed(1) + '%;background:var(--primary)"></div></div></div>';
  }
  function renderPortThroughput(data) {
    var ifsAll = data.interfaces || [];
    var topologyComplete = !!(data.traffic && data.traffic.topology_complete === true);
    var uplinkDevice = String((data.traffic || {}).uplink_device || "");
    var ports = topologyComplete ? ifsAll.filter(function (i) { return /^(lan[0-9]+|wan[0-9.]*)$/.test(i.name) && (!uplinkDevice || i.name !== uplinkDevice); }) : [];
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
    // Client-edge aggregate from dashapi2. rx_* is already client download and
    // tx_* is already client upload; these are not raw interface RX/TX fields.
    var t = data.traffic || {}, gRx = num(t.rx_bps), gTx = num(t.tx_bps);
    if (!ports.length && !Object.keys(wifiAgg).length && !finite(gRx)) return "";
    var body = '<p class="muted" style="margin:0 0 6px">' + esc(tr("perPortRate")) + '</p>';
    // total
    body += '<div style="text-align:center;margin-bottom:6px"><div class="latin" style="font-size:24px;font-weight:800;color:var(--accent)">' +
      bps((finite(gRx) ? gRx : 0) + (finite(gTx) ? gTx : 0)) + '</div><div style="font-size:11px;color:var(--muted)">' + esc(tr("totalRate")) +
      ' · ↓ ' + esc(tr("download")) + ' ' + (finite(gRx) ? bps(gRx) : "—") + ' · ↑ ' + esc(tr("upload")) + ' ' + (finite(gTx) ? bps(gTx) : "—") + '</div></div>';
    // Wi-Fi per band — on an AP interface, TX = data sent to clients (download) and RX =
    // data from clients (upload), so pass tx as the ↓ (download) and rx as the ↑ (upload).
    var wifiRows = Object.keys(wifiAgg).map(function (b) { return throughputRow("WiFi " + b, wifiAgg[b].tx, wifiAgg[b].rx, wifiAgg[b].up, b); }).join("");
    if (wifiRows) body += '<h4 style="margin:8px 0 2px">' + esc(tr("wifiRate")) + '</h4>' + wifiRows;
    if (!topologyComplete) body += '<small class="muted">' + esc(trafficCoverageNote(data)) + '</small>';
    // DSA wired client edges have the same direction as AP interfaces: TX is
    // download to the client and RX is upload from the client.
    var portRows = ports.map(function (i) { return throughputRow(i.name, num(i.tx_bps), num(i.rx_bps), i.connected, i.connected ? (i.speed_mbps ? i.speed_mbps + "M" : "up") : "down"); }).join("");
    if (portRows) body += '<h4 style="margin:8px 0 2px">' + esc(tr("portsRate")) + '</h4>' + portRows +
      '<small class="muted">' + esc(state.lang === "ar" ? "صفوف حواف العملاء السلكية؛ يُستبعد منفذ uplink المعلن. عند طوبولوجيا جزئية قد لا يمكن تصنيف كل منفذ." : "Wired client-edge rows; the reported uplink is excluded. With partial topology, every port may not be classifiable.") + '</small>';
    return card(tr("portThroughput"), body, "live", "net");
  }
  // Advertised SSID encryption family from the per-SSID encryption string.
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
    rows += '<small class="muted">' + esc(state.lang === "ar" ? "يعرض تشفير SSID المعلن فقط؛ لا يثبت عزل العملاء أو الجدار الناري أو تعرّض الإدارة." : "Advertised SSID encryption only; this does not prove client isolation, firewall policy, or management exposure.") + '</small>';
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
        // iw reports the AP-side last PHY TX/RX rate. It is deliberately kept
        // separate from the live byte-counter throughput in the next column.
        var linkCell = esc(d.iface || "") + stationPhyHtml(d, true);
        return '<tr><td>' + icon(d.type === "WiFi" ? "wifi" : "device") + " " + esc(d.type || "") + '</td><td class="latin">' + ipHost + '</td><td class="latin">' + esc((d.mac || tr("unavailable")).toUpperCase()) + '</td><td>' + esc(vn) + '</td><td>' + linkCell + '</td><td class="latin">' + (num(d.signal) !== null ? d.signal + ' dBm ' + proximity(d.signal) : tr('unavailable')) + '</td><td>' + traf + '</td><td>' + acts + '</td></tr>';
      }).join("") +
      '</tbody></table></div>' :
      sectionHead(tr("devices"), "IP / MAC / traffic", snapshotIsStale(data) ? cachedStatusLabel() : "0") +
        '<div class="empty">' + esc(emptyDevicesLabel(data)) + '</div>';
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
      var result = await postJsonLocked(CTL, { credentials:"same-origin", cache: "no-store",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "section=devices&action=lan_neighbors&" + sidQuery() + "&_=" + Date.now() }, 20000, btn);
      var r = result.response;
      if (r.status === 403) { requireLogin(tr("sessionExpired")); return; }
      var d = result.data;
      state.lanScan = d; // persist so the 5s poll re-render keeps the result
      box.innerHTML = renderLanScan(d);
      bindDynamic(box);
    } catch (e) {
      box.innerHTML = '<div class="ctl-status">' + esc("scan: " + e.message) + '</div>';
    } finally { btn.disabled = false; btn.textContent = old; }
  }
  function healthCard(data) {
    var h = data.health; if (!h) return "";
    var score = num(h.score); if (!finite(score)) return "";
    var stale = snapshotIsStale(data);
    var col = score >= 85 ? "var(--excellent)" : score >= 70 ? "var(--good)" : score >= 50 ? "var(--mid)" : "var(--weak)";
    var reasons = (h.reasons || []).map(function (r) {
      var rc = r.level === "ok" ? "var(--excellent)" : r.level === "mid" ? "var(--mid)" : "var(--weak)";
      var msg = state.lang === "ar" ? (r.ar || r.en) : (r.en || r.ar);
      return '<div class="hs-reason" style="border-inline-start:3px solid ' + rc + '">' + esc(msg) + '</div>';
    }).join("");
    var extra = '<div class="grid two" style="margin-top:10px">' +
      '<div class="traffic-box"><span>' + tr("airtime") + '</span><b class="latin">' + (finite(num(h.busy_pct)) ? h.busy_pct + "%" : tr("unavailable")) + '</b></div>' +
      '<div class="traffic-box"><span>' + tr("latency") + '</span><b class="latin">' + (finite(num(data.latency_ms)) ? fmt(num(data.latency_ms), 1) + " ms" : tr("unavailable")) + '</b></div></div>';
    var fallbackReason = stale
      ? (state.lang === "ar"
        ? "\u0627\u0644\u062f\u0631\u062c\u0629 \u0645\u0646 \u0644\u0642\u0637\u0629 \u0645\u062e\u0632\u0646\u0629 \u0648\u062a\u0646\u062a\u0638\u0631 \u0627\u0644\u062a\u062d\u062f\u064a\u062b \u0627\u0644\u062a\u0641\u0635\u064a\u0644\u064a"
        : "Score is from a cached snapshot pending a detailed refresh")
      : (state.lang === "ar" ? "لا تحذيرات موارد في المدخلات المتاحة" : "No resource warnings in available inputs");
    var reasonHtml = stale
      ? '<div class="hs-reason" style="border-inline-start:3px solid var(--mid)">' + esc(fallbackReason) + '</div>'
      : (reasons || '<div class="hs-reason">' + esc(fallbackReason) + '</div>');
    var body = '<div class="hs-wrap"><div class="hs-score" style="color:' + col + ';border-color:' + col + '"><b>' + score + '</b><small>/100</small></div>' +
      '<div class="hs-reasons">' + reasonHtml + '</div></div>' + extra;
    var healthChip = stale ? cachedStatusLabel() : (state.lang === "ar" ? "عينة موارد" : "resource sample");
    return card(tr("healthScore"), body, healthChip, "shield");
  }
  function renderWifi(data) {
    var w = data.wifi || [];
    var body = w.length ? '<div class="grid two">' + w.map(function (x) {
      var stationSignals = (x.stations || []).map(function (s) { return num(s.signal_dbm); }).filter(finite);
      var sig = stationSignals.length ? stationSignals.reduce(function (a, b) { return a + b; }, 0) / stationSignals.length : null;
      var q = quality("rssi", sig);
      var busy = x.survey ? num(x.survey.busy_pct) : null;
      var sta = (x.stations || []).map(function (s) {
        var ss = num(s.signal_dbm), noise = num(s.noise_dbm), snr = num(s.snr), qq = quality("rssi", ss);
        var phyStr = stationPhyHtml(s, false);
        var rfParts = [];
        if (finite(ss)) rfParts.push("Signal " + fmt(ss, 0) + " dBm");
        if (finite(noise)) rfParts.push("Noise " + fmt(noise, 0) + " dBm");
        if (finite(snr)) rfParts.push("SNR " + fmt(snr, 0) + " dB");
        var rfStr = rfParts.length ? '<small class="muted latin">' + esc(rfParts.join(" · ")) + '</small>' : "";
        // per-client signal trend (kept per MAC in localStorage histories)
        if (s.mac && finite(ss)) pushHistory("sig_" + s.mac, ss, 40);
        var trendStr = (s.mac && (state.histories["sig_" + s.mac] || []).length > 2) ? spark(state.histories["sig_" + s.mac], qq.color) : "";
        var trafficStr = stationTrafficHtml(s);
        // per-client throughput trend (download+upload byte-rate, per MAC)
        var stRate = stationTraffic(s);
        if (s.mac && stRate.hasRate) pushHistory("rate_" + s.mac, (stRate.down || 0) + (stRate.up || 0), 40);
        var rateTrend = (s.mac && (state.histories["rate_" + s.mac] || []).length > 2) ? spark(state.histories["rate_" + s.mac], "var(--accent)") : "";
        var retries = num(s.tx_retries), packets = num(s.tx_packets), failed = num(s.tx_failed);
        var retryPct = finite(retries) && finite(packets) && retries + packets > 0 ? retries * 100 / (retries + packets) : null;
        var retryStr = finite(retryPct) ? '<span class="prox" style="color:' + (retryPct < 8 ? "var(--excellent)" : retryPct < 20 ? "var(--mid)" : "var(--weak)") + '">' + (state.lang === "ar" ? "إعادة إرسال " : "Retries ") + fmt(retryPct, 0) + '%</span>' : "";
        var failStr = finite(failed) && failed > 0 ? '<span class="prox" style="color:var(--weak)">' + (state.lang === "ar" ? "فشل " : "Failed ") + fmt(failed, 0) + '</span>' : "";
        // 802.11v steer button — offered only for clients sitting on the 2.4G radio
        var steer = (x.band === "2.4G" && s.mac) ? ' <button class="btn dev-action" title="' + esc(tr("steerHint")) + '" data-steer-mac="' + esc(s.mac) + '" data-steer-iface="' + esc(x.iface || "") + '">' + esc(tr("steer5g")) + '</button>' : "";
        return '<div class="kv"><div><span class="latin">' + esc(s.ip || s.mac || tr("unavailable")) + steer + '</span><b class="latin">' + (finite(ss) ? ss + " dBm " : "") + proximity(ss) + '</b></div>' + bar(finite(ss) ? signalPct("rssi", ss) : 0, 100, qq.color) +
          '<div class="cli-tags">' + retryStr + failStr + '</div>' + rfStr + phyStr + trafficStr + trendStr + rateTrend + '</div>';
      }).join("") || '<div class="empty">' + tr("unavailable") + '</div>';
      var busyRow = finite(busy) ? '<div><span>' + tr("airtime") + '</span><b class="latin" style="color:' + (busy >= 60 ? "var(--weak)" : busy >= 35 ? "var(--mid)" : "var(--excellent)") + '">' + busy + '%</b></div>' : "";
      var txp = x.txpower || {},
        txReq = num(x.requested_dbm != null ? x.requested_dbm : txp.requested_dbm),
        txApplied = num(x.applied_dbm != null ? x.applied_dbm : txp.applied_dbm),
        txMax = num(x.max_dbm != null ? x.max_dbm : txp.max_dbm),
        radioState = String(x.state || txp.status || (x.up === true ? "up" : "unknown")),
        radioReason = String(x.reason || txp.reason || "");
      var txAppliedText = finite(txApplied) ? fmt(txApplied, 0) + " dBm" : tr("unavailable");
      var txAppliedColor = finite(txApplied) ? (txp.status === "limited" ? "var(--mid)" : "var(--excellent)") : "var(--muted)";
      var powerRow = '<div><span>' + (state.lang === "ar" ? "TX المطبق" : "Applied TX") + '</span><b class="latin" style="color:' + txAppliedColor + '">' + txAppliedText + '</b></div>' +
        '<div><span>' + (state.lang === "ar" ? "TX المطلوب" : "Requested TX") + '</span><b class="latin">' + (finite(txReq) ? fmt(txReq, 0) + " dBm" : tr("unavailable")) + '</b></div>' +
        '<div><span>' + (state.lang === "ar" ? "حد القناة" : "Channel maximum") + '</span><b class="latin">' + (finite(txMax) ? fmt(txMax, 0) + " dBm" : tr("unavailable")) + '</b></div>' +
        '<div><span>Status</span><b class="latin">' + esc(radioState) + '</b></div>' +
        (radioReason ? '<small class="muted">' + esc(radioReason) + '</small>' : '');
      var rssiLabel = state.lang === "ar" ? "متوسط RSSI للعملاء" : "Average client RSSI";
      return card(x.ssid || x.iface, '<div class="kv"><div><span>Band</span><b>' + esc(x.band || "") + '</b></div><div><span>' + tr("channel") + '</span><b>' + esc(x.channel || "") + '</b></div><div><span>Mode</span><b class="latin">' + esc(x.htmode || "") + '</b></div><div><span>Clients</span><b>' + (x.clients || 0) + '</b></div><div><span>' + rssiLabel + '</span><b class="latin" style="color:' + q.color + '">' + (finite(sig) ? fmt(sig, 0) + " dBm " + proximity(sig) : tr("unavailable")) + '</b></div>' + powerRow + busyRow + '</div><h4>Clients · ' + tr("linkRate") + '</h4>' + sta, x.hw_modes || "", "wifi");
    }).join("") + '</div>' : '<div class="empty">' + tr("unavailable") + '</div>';
    // count total connected stations to decide whether to show the radar
    var totalSta = w.reduce(function (a, x) { return a + ((x.stations || []).length); }, 0);
    if (w.length) {
      scheduleChartDraw("channelCanvas", function (canvas) { return drawChannels(canvas, w); });
      scheduleChartDraw("constellationCanvas", function (canvas) { return drawConstellation(canvas, w); });
    }
    var chanCard = w.length ? card(state.lang === "ar" ? "إشغال القنوات" : "Channel occupancy",
      '<canvas id="channelCanvas" style="width:100%;height:150px"></canvas>', "2.4G / 5G", "signal") : "";
    var radarCard = totalSta ? card(tr("clientRadar"),
      '<canvas id="constellationCanvas" style="width:100%;height:230px"></canvas><p class="muted" style="text-align:center">' + esc(tr("constellation")) + '</p>', totalSta + "", "device") : "";
    // best-channel scan + neighboring networks (on-demand; scanning briefly dips throughput)
    var scanCard = card(tr("bestChannel") + " · " + tr("neighbors"),
      '<div class="branch-actions"><button class="btn primary" id="wifiScanBtn">' + esc(tr("scanNeighbors")) + '</button></div>' +
      '<div id="wifiScanResult">' + (state.lastScan ? renderScanResult(state.lastScan) : "") + '</div>', "iw scan", "signal");
    return sectionHead("WiFi AX / AC / N", state.lang === "ar" ? "TX Power منفصل عن RSSI العملاء ومعدل الربط" : "TX power, client RSSI and link rate are separate measurements", detailStatusLabel(data, data.wifi)) +
      healthCard(data) + '<div class="grid two">' + chanCard + renderSecPosture(data) + '</div>' + scanCard + radarCard + body;
  }
  // Client constellation radar: clients orbit the AP, radius = signal (strong→center),
  // colour = band, dot size = link rate. Pure offline canvas over live assoclist data.
  function drawConstellation(canvas, wifiList) {
    if (!canvas) return false;
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
      (x.stations || []).forEach(function (s) { pts.push({ sig: num(s.signal_dbm), band5: band5, mac: s.mac }); });
    });
    var n = pts.length || 1, i = 0;
    pts.forEach(function (p) {
      var sig = finite(p.sig) ? clamp(p.sig, -95, -30) : -75;
      var frac = (-30 - sig) / (-30 - -95); // 0 (strong, near) .. 1 (weak, far)
      var rad = 16 + frac * (R - 20);
      var ang = (i / n) * Math.PI * 2 - Math.PI / 2; i++;
      var px = cx + rad * Math.cos(ang), py = cy + rad * Math.sin(ang);
      var col = p.band5 ? primary : accent;
      // Marker size is deliberately constant: a last PHY snapshot is not traffic volume.
      var sz = 6;
      ctx.strokeStyle = hexA(col, 0.35); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(px, py); ctx.stroke();
      ctx.fillStyle = col; ctx.beginPath(); ctx.arc(px, py, sz, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = hexA(col, 0.18); ctx.beginPath(); ctx.arc(px, py, sz + 4, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = muted; ctx.font = "9px system-ui"; ctx.textAlign = "center";
      ctx.fillText(finite(p.sig) ? p.sig + "" : "?", px, py - sz - 4);
    });
    return true;
  }
  async function scanWifi() {
    var btn = $("wifiScanBtn"), box = $("wifiScanResult");
    if (!btn || !box) return;
    btn.disabled = true; var old = btn.textContent; btn.textContent = tr("scanning");
    box.innerHTML = '<div class="ctl-status">' + esc(tr("scanning")) + '</div>';
    try {
      var result = await postJsonLocked(CTL, { credentials:"same-origin", cache: "no-store",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "section=wifiscan&action=secscan_run&" + sidQuery() + "&_=" + Date.now() }, SCAN_TIMEOUT_MS, btn);
      var r = result.response;
      if (r.status === 403) { requireLogin(tr("sessionExpired")); return; }
      var d = result.data;
      state.lastScan = d; // persist so the 5s poll re-render doesn't wipe results
      box.innerHTML = renderScanResult(d);
      bindDynamic(box);
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
  async function applyBestChannels(ch24, ch5, button) {
    var scanBox = $("wifiScanResult"), stopProgress = function () {};
    try {
      var body = "section=wifiscan&action=apply_best_channels&confirm=1";
      if (ch24) body += "&ch24=" + encodeURIComponent(ch24);
      if (ch5) body += "&ch5=" + encodeURIComponent(ch5);
      if (scanBox) stopProgress = startControlProgress(scanBox, "apply_best_channels");
      var result = await postJsonLocked(CTL, { credentials:"same-origin", cache: "no-store",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body + "&" + sidQuery() + "&_=" + Date.now() }, controlActionTimeoutMs("wifiscan", "apply_best_channels"), button);
      var r = result.response;
      if (r.status === 403) { requireLogin(tr("sessionExpired")); return; }
      var j = result.data;
      stopProgress();
      if (!j || j.ok !== true) {
        toast((j && (j.summary || j.text)) || (state.lang === "ar" ? "فشل تطبيق القناة" : "Channel apply failed"));
        return;
      }
      var readyToken = j.confirmation_ready === true && /^[0-9a-f]{32}$/.test(j.rollback_token || "");
      if (readyToken) {
        showSection("quick");
        var quickBox = $("ctl_wizard");
        if (!quickBox || !presentPendingApply("wizard", quickBox, j)) {
          toast(state.lang === "ar" ? "تعذر عرض تأكيد Safe Apply؛ سيبقى الرجوع التلقائي هو المرجع" : "Safe Apply confirmation is unavailable; automatic rollback remains authoritative");
          return;
        }
      } else {
        toast(state.lang === "ar" ? "لم يثبت الخادم جاهزية التغيير؛ سيبقى الرجوع التلقائي هو المرجع" : "The server did not prove the change ready; automatic rollback remains authoritative");
        return;
      }
      toast(j.summary || tr("ok"));
      event("Best channel applied: 2.4G=" + (ch24 || "-") + " 5G=" + (ch5 || "-"));
      queueFullRefresh(800);
    } catch (e) {
      stopProgress();
      showSection("quick");
      var recoveryBox = $("ctl_wizard");
      if (controlPostNeedsRecovery(e) && await recoverControlAction("wizard", "apply_best_channels", recoveryBox)) return;
      toast(e.message);
    } finally { stopProgress(); }
  }
  // theme-aware Wi-Fi channel occupancy (net-new, offline canvas)
  function drawChannels(canvas, wifiList) {
    if (!canvas) return false;
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
    return true;
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
    var liveCounters = !snapshotIsStale(data) || data._liveLite === true;
    var usedMem = (Number(mem.total)||0) - (Number(mem.available)||0), memPct = pct(usedMem, Number(mem.total)||0);
    var stPct = pct(Number(st.used)||0, Number(st.total)||0), cpuPct = clamp(Number(cpu.percent)||0,0,100), temp = num(data.temperature_c);
    pushHistory("cpu", cpuPct, 60, liveCounters); pushHistory("ram", memPct, 60, liveCounters); pushHistory("storage", stPct, 60, liveCounters);
    var body = '<div class="gauge-grid">' +
      gauge("CPU", cpuPct + "%", "load", quality("system", cpuPct).text, cpuPct, quality("system", cpuPct).color, "cpu") +
      gauge("RAM", memPct + "%", bytes(usedMem), bytes(mem.available) + " free", memPct, quality("system", memPct).color, "ram") +
      gauge("Storage", stPct + "%", bytes(st.used), bytes(st.available) + " free", stPct, quality("system", stPct).color, "storage") +
      gauge("Temp", finite(temp) ? fmt(temp,1) : tr("unavailable"), finite(temp) ? "C" : "", finite(temp) ? tr("ok") : tr("unavailable"), finite(temp) ? clamp(temp,0,100) : 0, finite(temp) ? quality("system", temp).color : "#64748B", "temp") +
      '</div>';
    if (finite(temp)) pushHistory("temp", clamp(temp,0,100), 60, !snapshotIsStale(data));
    // theme-aware CPU/RAM/temp trend (net-new chart)
    var trend = (state.histories.cpu || []).map(function (c, i) {
      return { cpu:c, ram:(state.histories.ram||[])[i]||0, temp:(state.histories.temp||[])[i]||0 };
    });
    scheduleChartDraw("sysTrendCanvas", function (canvas) {
      return drawChart(canvas, trend, {
        keys:["cpu","ram","temp"], labels:[tr("cpu"),tr("ram"),tr("temp")], fmt:"pct",
        colors:[cssVar("--accent","#06B6D4"), cssVar("--good","#84CC16"), cssVar("--mid","#F59E0B")]
      });
    });
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
    return sectionHead(tr("systemTitle"), "loadavg / free / overlay / thermal", "thresholds") + card(state.lang === "ar" ? "لقطة الموارد" : "Resource snapshot", body, "live", "cpu") + trendCard + selftestCard + card(state.lang === "ar" ? "التوفر المرصود بالمتصفح · آخر 24 ساعة" : "Browser-observed availability · last 24h", availabilityHtml(), "browser local", "bolt");
  }
  function renderNetwork(data, rates) {
    var ar = state.lang === "ar";
    var interfaces = (data.interfaces || []).slice().sort(function (a, b) {
      // Array.prototype.sort is stable (ES2019): keeps the server's
      // br-lan/eth0/wan/lanN order inside each group, connected rows first.
      return (b.connected === true) - (a.connected === true);
    });
    var labels = ar
      ? ["الواجهة","الحالة","السرعة","RX الآن","TX الآن","RX الإجمالي","TX الإجمالي","أخطاء / إسقاط منذ إعادة ضبط الواجهة"]
      : ["Interface","Status","Speed","RX now","TX now","RX total","TX total","Errors / Drops since interface reset"];
    var table = '<p class="muted traffic-note">' + (ar ? "RX/TX هنا اتجاه عداد الواجهة الخام، وليس تنزيل/رفع العميل." : "RX/TX below are raw interface-counter directions, not client download/upload.") + '</p><div class="table-wrap traffic-table"><table><thead><tr>' + labels.map(function (label) {
      return '<th>' + label + '</th>';
    }).join("") + '</tr></thead><tbody>' +
      interfaces.map(function (i) {
        var irx = num(i.rx_bps), itx = num(i.tx_bps);
        var faults = (i.rx_errors||0) + (i.tx_errors||0) + (i.rx_dropped||0) + (i.tx_dropped||0);
        return '<tr><td class="latin traffic-iface">' + esc(i.name) + '</td><td><span class="chip ' + (i.connected ? "ok" : "bad") + '">' + (i.connected ? (ar ? "يعمل" : "up") : (ar ? "متوقف" : "down")) + '</span></td><td class="latin">' + (i.speed_mbps ? i.speed_mbps + " Mbps" : tr("unavailable")) + '</td><td class="latin">' + (finite(irx) ? bps(irx) : "—") + '</td><td class="latin">' + (finite(itx) ? bps(itx) : "—") + '</td><td class="latin">' + bytesNet(i.rx_bytes) + '</td><td class="latin">' + bytesNet(i.tx_bytes) + '</td><td class="latin ' + (faults ? "traffic-fault" : "traffic-clean") + '">' + (i.rx_errors||0) + "/" + (i.tx_errors||0) + " · " + (i.rx_dropped||0) + "/" + (i.tx_dropped||0) + '</td></tr>';
      }).join("") +
      '</tbody></table></div>';
    var latencyHistory = (state.histories.latency || []).filter(finite);
    var currentLatency = latencyHistory.length ? latencyHistory[latencyHistory.length - 1] : num(state.lastLatency);
    var jitterTotal = 0;
    for (var n = 1; n < latencyHistory.length; n++) jitterTotal += Math.abs(latencyHistory[n] - latencyHistory[n - 1]);
    var jitter = latencyHistory.length > 1 ? jitterTotal / (latencyHistory.length - 1) : 0;
    var latencyBody = '<canvas id="latencyCanvas" class="latency-chart"></canvas>' +
      '<div class="latency-metrics"><div><span>' + (ar ? "آخر جلب" : "Latest fetch") + '</span><b class="latin">' + (finite(currentLatency) ? fmt(currentLatency,0) + " ms" : "—") + '</b></div>' +
      '<div><span>' + (ar ? "تذبذب الجلب" : "Fetch jitter") + '</span><b class="latin">' + fmt(jitter,0) + ' ms</b></div>' +
      '<div><span>' + (ar ? "العينات" : "Samples") + '</span><b class="latin">' + latencyHistory.length + '</b></div></div>' +
      '<p class="muted traffic-note">' + (ar ? "هذا زمن استجابة واجهة الراوتر، وليس Ping للإنترنت." : "This is dashboard API response time, not Internet ping.") + '</p>';
    var ping = card(ar ? "استجابة لوحة الراوتر" : "Dashboard response", latencyBody, "live fetch", "net");
    scheduleChartDraw("latencyCanvas", function (canvas) {
      return drawChart(canvas, (state.histories.latency || []).map(function (v) { return { rx:v }; }), { keys:["rx"] });
    });
    var interfaceCard = card(ar ? "حالة الواجهات والمنافذ" : "Interfaces & ports", table, interfaces.length + " interfaces", "net");
    return sectionHead(tr("networkTitle"), ar ? "نقل لحظي، إجماليات، أخطاء، وسرعة جلب الواجهة" : "Live throughput, totals, errors, and dashboard response", data.backhaul && data.backhaul.online ? tr("online") : tr("lanOnly")) +
      '<div class="traffic-layout"><div class="traffic-primary">' + renderTraffic(data, rates, "network") + '</div><div class="traffic-latency">' + ping + '</div></div>' + interfaceCard;
  }
  function adminGroups() {
    var ar = state.lang === "ar";
    // Only sections whose backend is fully supported on this build are listed.
    // (SQM and igmpproxy-IPTV are intentionally omitted: SQM caps throughput and
    //  igmpproxy/udpxy are not installed.)
    // netmgr/wifimgr/sysmgr grouped sections were removed (owner request: they
    // duplicated the existing الشبكة/لاسلكي/النظام sections and confused the menu).
    // Their useful controls live on in Quick Settings (wizard) + TX Power + isolation.
    return {};
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
    if (section === "isolation") return renderIsolationControl(data);
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
      guard: state.lang === "ar" ? "الحمايات العامة" : "General protections",
      wifi: state.lang === "ar" ? "عزل شبكات الواي فاي" : "Wi-Fi isolation",
      ports: state.lang === "ar" ? "المنافذ" : "Ports",
      device: state.lang === "ar" ? "الجهاز" : "Device",
      security: state.lang === "ar" ? "الحماية" : "Security",
      advanced: state.lang === "ar" ? "متقدم" : "Advanced"
    };
    return m[g] || "";
  }
  function controlActionsHtml(section, actions) {
    if (!actions || !actions.length) return "";
    return '<div class="branch-actions isolation-apply">' + actions.filter(function (a) { return !a.url; }).map(function (a) {
      var cls = a.confirm ? "btn" : "btn primary";
      var label = a.label || a.id;
      if (a.id === "apply_isolation")
        label = state.lang === "ar" ? "حفظ وتطبيق" : "Save & Apply";
      return '<button class="' + cls + '" data-ctl-section="' + esc(section) + '" data-ctl-action="' + esc(a.id) + '" data-ctl-input="' + esc(a.input || "") + '" data-ctl-confirm="' + (a.confirm ? "1" : "") + '">' + esc(label) + '</button>';
    }).join("") + '</div>';
  }
  function isolationStatusCards(cards) {
    if (!cards.length) return "";
    return '<div class="ctl-cards compact">' + cards.map(function (c) {
      return '<div class="ctl-card ' + esc(c.level || "neutral") + '"><span>' + esc(c.label) + '</span><b>' + esc(c.value) + '</b><small>' + esc(c.hint || "") + '</small></div>';
    }).join("") + '</div>';
  }
  function dsaPortFieldHtml(f, key) {
    var suffix = f.name.slice(key.length + 1);
    var roles = { enabled:"enabled", vlan_mode:"mode", vlan:"vlan", isolate:"isolation" };
    var labels = state.lang === "ar"
      ? { enabled:"الحالة", mode:"الوضع", vlan:"VLAN ID", isolation:"العزل" }
      : { enabled:"Enabled", mode:"Mode", vlan:"VLAN ID", isolation:"Isolation" };
    var role = roles[suffix] || suffix;
    var field = Object.assign({}, f, {
      label: labels[role] || f.label,
      dsaControl: role
    });
    return fieldHtml(field);
  }
  function renderIsolationControl(data) {
    var form = data.form || [], cards = data.cards || [];
    var guardFields = form.filter(function (f) { return f.group === "guard"; });
    var wifiFields = form.filter(function (f) { return f.group === "wifi"; });
    var guardCards = cards.filter(function (c) { return !/^LAN[123]$/.test(c.label) && !/واي فاي|Wi-Fi/i.test(c.label); });
    var wifiCards = cards.filter(function (c) { return /واي فاي|Wi-Fi/i.test(c.label); });
    var portCards = cards.filter(function (c) { return /^LAN[123]$/.test(c.label); });
    var topology = '<div class="dsa-topology">' + portCards.map(function (c) {
      return '<div class="dsa-node ' + esc(c.level || "neutral") + '"><span>' + esc(c.label) + '</span><b>' + esc(c.value) + '</b><small>' + esc(c.hint || "") + '</small></div>';
    }).join("") + '</div>';
    var portOrder = { enabled:0, vlan_mode:1, vlan:2, isolate:3 };
    var ports = ["lan1", "lan2", "lan3"].map(function (key, idx) {
      var fields = form.filter(function (f) { return f.name.indexOf(key + "_") === 0; }).sort(function (a, b) {
        return (portOrder[a.name.slice(key.length + 1)] || 0) - (portOrder[b.name.slice(key.length + 1)] || 0);
      });
      var status = portCards.filter(function (c) { return c.label === "LAN" + (idx + 1); })[0] || {};
      return '<section class="dsa-port-row" data-dsa-port="' + key + '"><div class="dsa-port-head"><div class="icon">' + icon("net") + '</div><div><strong>LAN' + (idx + 1) + '</strong><span>' + esc(status.value || "") + '</span><small>' + esc(status.hint || "") + '</small></div></div><div class="dsa-port-controls">' + fields.map(function (f) { return dsaPortFieldHtml(f, key); }).join("") + '</div></section>';
    }).join("");
    var ar = state.lang === "ar";
    var tabs = '<div class="isolation-tabs" role="tablist" aria-label="' + esc(ar ? "أقسام الحماية والمنافذ" : "Protection and port sections") + '">' +
      '<button id="isolation-tab-guard" role="tab" aria-selected="false" aria-controls="isolation-panel-guard" tabindex="-1" data-isolation-tab="guard">' + (ar ? "الحماية" : "Protection") + '</button>' +
      '<button id="isolation-tab-wifi" role="tab" aria-selected="false" aria-controls="isolation-panel-wifi" tabindex="-1" data-isolation-tab="wifi">' + (ar ? "عزل Wi-Fi" : "Wi-Fi isolation") + '</button>' +
      '<button id="isolation-tab-ports" role="tab" aria-selected="true" aria-controls="isolation-panel-ports" tabindex="0" class="active" data-isolation-tab="ports">' + (ar ? "المنافذ" : "Ports") + '</button></div>';
    return tabs +
      '<section id="isolation-panel-guard" role="tabpanel" aria-labelledby="isolation-tab-guard" class="isolation-panel" data-isolation-panel="guard" hidden>' + isolationStatusCards(guardCards) + '<div class="ctl-form">' + guardFields.map(fieldHtml).join("") + '</div></section>' +
      '<section id="isolation-panel-wifi" role="tabpanel" aria-labelledby="isolation-tab-wifi" class="isolation-panel" data-isolation-panel="wifi" hidden>' + isolationStatusCards(wifiCards) + '<div class="ctl-form">' + wifiFields.map(fieldHtml).join("") + '</div></section>' +
      '<section id="isolation-panel-ports" role="tabpanel" aria-labelledby="isolation-tab-ports" class="isolation-panel" data-isolation-panel="ports">' + topology + '<div class="dsa-port-list">' + ports + '</div></section>' +
      controlActionsHtml("isolation", data.actions) + '<div class="ctl-note">' + esc(ar ? "Plain للسويتش العادي، Access لجهاز داخل VLAN، وTrunk للميكروتك أو سويتش VLAN." : "Plain for a normal switch port, Access for a VLAN endpoint, and Trunk for MikroTik or a VLAN-aware switch.") + '</div>';
  }
  function syncDsaPortRows(rootNode) {
    var root = rootNode && typeof rootNode.querySelectorAll === "function" ? rootNode : document;
    var rows = root.matches && root.matches("[data-dsa-port]") ? [root] : root.querySelectorAll("[data-dsa-port]");
    Array.prototype.forEach.call(rows, function (row) {
      var mode = row.querySelector('[data-ctl-field$="_vlan_mode"]');
      var vlan = row.querySelector('[data-ctl-field$="_vlan"]');
      var isolate = row.querySelector('[data-ctl-field$="_isolate"]');
      var enabled = row.querySelector('[data-ctl-field$="_enabled"]');
      var status = row.querySelector('.dsa-port-head span');
      var detail = row.querySelector('.dsa-port-head small');
      if (!mode) return;
      var plain = mode.value === "plain", trunk = mode.value === "trunk";
      if (plain && vlan) vlan.value = "1";
      if (vlan) vlan.disabled = plain;
      if (trunk && isolate) isolate.value = "0";
      if (isolate) isolate.disabled = trunk;
      row.dataset.mode = mode.value;
      var modeText = plain ? (state.lang === "ar" ? "بدون VLAN" : "No VLAN") : trunk ? ("Trunk VLAN " + (vlan ? vlan.value : "")) : ("Access VLAN " + (vlan ? vlan.value : ""));
      if (status) status.textContent = ((enabled && enabled.value === "0") ? (state.lang === "ar" ? "متوقف" : "Disabled") : (state.lang === "ar" ? "يعمل" : "Enabled")) + " · " + modeText;
      if (detail) detail.textContent = (isolate && isolate.value === "1") ? (state.lang === "ar" ? "معزول" : "Isolated") : (state.lang === "ar" ? "غير معزول" : "Not isolated");
      [mode, vlan, isolate, enabled].forEach(function (el) {
        if (!el) return;
        el.onchange = function () { syncDsaPortRows(row); };
        if (el === vlan) el.oninput = function () { syncDsaPortRows(row); };
      });
    });
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
    var dsaClass = f.dsaControl ? " dsa-port-field" : "";
    var dsaAttr = f.dsaControl ? ' data-dsa-control="' + esc(f.dsaControl) + '"' : "";
    var wrap = '<label class="royal-field' + dsaClass + '" data-royal-group="' + esc(f.group || "") + '" data-modes="' + esc(f.modes || "") + '"' + dsaAttr + '><span>' + esc(f.label) + '</span>';
    var tail = '<small>' + esc(f.hint || "") + '</small></label>';
    if (type === "select") {
      return wrap + '<select class="latin" data-ctl-field="' + esc(f.name) + '"' + ro + '>' + optionHtml(f.options, f.value) + '</select>' + tail;
    }
    if (type === "number" && f.options) {
      var mm = String(f.options).split(":");
      var at = (mm[0] !== undefined && mm[0] !== "" ? ' min="' + esc(mm[0]) + '"' : '') + (mm[1] ? ' max="' + esc(mm[1]) + '"' : '') + (mm[2] ? ' step="' + esc(mm[2]) + '"' : '');
      if (/^txpower(?:_radio[01])?$/.test(f.name)) {
        var presets = [5, 10, 15, 20, 23, 26, 30, 35, 38].map(function (v) {
          var label = v + " dBm";
          return '<button type="button" class="txpower-preset latin" data-tx-preset="' + esc(f.name) + '" data-value="' + v + '">' + label + '</button>';
        }).join("");
        return wrap + '<div class="txpower-control"><input class="latin" data-tx-range="' + esc(f.name) + '" type="range"' + at + ' value="' + esc(f.value) + '"' + ro + '><input class="latin" data-ctl-field="' + esc(f.name) + '" type="number"' + at + ' value="' + esc(f.value) + '" inputmode="numeric" autocomplete="off"' + ro + '><div class="txpower-presets">' + presets + '</div></div>' + tail;
      }
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
      '<div class="wizard-tabs" role="tablist" aria-label="' + esc(tr("quick")) + '">' +
      '<button id="wizard-tab-device" role="tab" aria-selected="true" aria-controls="wizard-pane-device" tabindex="0" class="wizard-tab active" data-wizard-tab="device">' + esc(tr("wizardDevice")) + '</button>' +
      '<button id="wizard-tab-security" role="tab" aria-selected="false" aria-controls="wizard-pane-security" tabindex="-1" class="wizard-tab" data-wizard-tab="security">' + esc(tr("wizardSecurity")) + '</button>' +
      '<button id="wizard-tab-advanced" role="tab" aria-selected="false" aria-controls="wizard-pane-advanced" tabindex="-1" class="wizard-tab" data-wizard-tab="advanced">' + esc(tr("wizardAdvanced")) + '</button>' +
      '</div>' +
      '<p class="mode-hint">' + esc(tr("wizardApplyNote")) + '</p>' +
      '<section id="wizard-pane-device" role="tabpanel" aria-labelledby="wizard-tab-device" class="royal-pane" data-wizard-pane="device"><div class="royal-grid wizard-fields">' + group("device") + '</div></section>' +
      '<section id="wizard-pane-security" role="tabpanel" aria-labelledby="wizard-tab-security" class="royal-pane" data-wizard-pane="security" hidden><div class="royal-grid wizard-fields">' + group("security") + '</div></section>' +
      '<section id="wizard-pane-advanced" role="tabpanel" aria-labelledby="wizard-tab-advanced" class="royal-pane" data-wizard-pane="advanced" hidden><div class="royal-grid wizard-fields">' + group("advanced") + '</div></section>' +
      '<div class="wizard-preview"><b>' + esc(tr("preview")) + '</b><div id="wizardPreview"></div></div>' + actions + (data.text ? '<pre class="ctl-pre">' + esc(data.text) + '</pre>' : "");
  }
  function updateWizardPreview() {
    var box = $("wizardPreview"); if (!box) return;
    function fv(n) { var el = document.querySelector('[data-control-section="wizard"] [data-ctl-field="' + n + '"]'); return el ? el.value : ""; }
    var modeEl = document.querySelector('[data-control-section="wizard"] [data-ctl-field="program_mode"]');
    var modeLabel = modeEl && modeEl.options ? modeEl.options[modeEl.selectedIndex].text : fv("program_mode");
    box.innerHTML = '<div class="kv"><span>' + esc(tr("previewMode")) + '</span><b class="latin">' + esc(modeLabel || "-") + '</b></div>' +
      '<div class="kv"><span>' + esc(tr("previewManagement")) + '</span><b class="latin">' + esc(fv("device_ip") || "-") + '</b></div>' +
      '<div class="kv"><span>' + esc(tr("previewVlan")) + '</span><b class="latin">' + esc(fv("vlan_id") || "-") + '</b></div>' +
      '<div class="kv"><span>' + esc(tr("previewSsid")) + '</span><b class="latin">' + esc(fv("ssid") || "-") + '</b></div>' +
      '<div class="kv"><span>' + esc(tr("previewSecurity")) + '</span><b class="latin">' + esc(fv("security") || "-") + '</b></div>' +
      '<div class="kv"><span>' + esc(tr("previewServices")) + '</span><b class="latin">' + esc((fv("nat_enabled") || "0") + " / " + (fv("dhcp_server") || "0") + " / " + (fv("firewall_enabled") || "1")) + '</b></div>' +
      '<div class="kv"><span>' + esc(tr("previewTxPower")) + '</span><b class="latin">' + esc((fv("txpower_radio0") || "38") + " / " + (fv("txpower_radio1") || "38")) + ' dBm</b></div>';
  }
  function syncWizardMode() {
    var panel = document.querySelector('[data-control-section="wizard"]');
    if (!panel) return;
    var modeEl = panel.querySelector('[data-ctl-field="program_mode"]');
    var mode = modeEl ? modeEl.value : "ap";
    var pppoe = mode === "pppoe_ap";
    ["broadband_enabled", "nat_enabled", "dhcp_server"].forEach(function (name) {
      var field = panel.querySelector('[data-ctl-field="' + name + '"]');
      if (field) field.value = pppoe ? "1" : "0";
    });
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
    var radios = (state.latest && state.latest.wifi) || [];
    function isUp(band) { return radios.some(function (w) { return w && w.band === band && w.up === true; }); }
    var up24 = isUp("2.4G"), up5 = isUp("5G");
    var actions = [
      ["refresh",tr("refresh"),tr("readApiNow")],
      ["speedtest",tr("speedTest"),tr("localTest")],
      ["wifi_radio0",tr("wifi24"),up24 ? tr("radioOn") : tr("radioOff")],
      ["wifi_radio1",tr("wifi5"),up5 ? tr("radioOn") : tr("radioOff")],
      ["reboot",tr("reboot"),tr("confirmRequired")]
    ];
    return sectionHead(tr("actions"), tr("actionsHint"), tr("safeAction")) +
      '<div class="actions">' + actions.map(function (a) { return '<button class="action" data-action="' + a[0] + '"><strong>' + esc(a[1]) + '</strong><span>' + esc(a[2]) + '</span></button>'; }).join("") + '</div>' + renderEvents(state.latest || {});
  }
  function renderIsolation() {
    return sectionHead(tr("isolation"), tr("isolationHint"), "Xiaomi CR6608") +
      '<div class="branch-detail" data-control-section="isolation">' +
      '<h3>' + esc(tr("isolationTitle")) + '</h3>' +
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
    bytes: bytes, bytesNet: bytesNet, bps: bps, num: num, finite: finite, clamp: clamp, pct: pct,
    quality: quality, distanceM: distanceM, proximity: proximity, tr: tr,
    cssVar: cssVar, hexA: hexA, wifiBand: wifiBand, mergeDevices: mergeDevices,
    secLevel: secLevel, levelColor: levelColor,
    signalPct: signalPct, uptime: uptime, icon: icon,
    stationTraffic: stationTraffic, stationTrafficRows: stationTrafficRows,
    parseStationRateDetail: parseStationRateDetail, stationRateDetail: stationRateDetail,
    stationReportedNss: stationReportedNss, stationInactiveAge: stationInactiveAge,
    radioWidthMHz: radioWidthMHz, configuredPhyCeiling2x2: configuredPhyCeiling2x2,
    verifiedUplinkCapacity: verifiedUplinkCapacity, trafficCoverageNote: trafficCoverageNote,
    stationRateSnapshots: stationRateSnapshots
  };
  // Registry of professional feature cards (populated from the multi-agent design pass).
  // Each entry: { key, ar, en, cat, fn:function(d,H)->html }. Rendered with per-feature
  // isolation so one bad module can never break the section.
  var PRO_FEATURES = [
{key:"airtime_busy",ar:"انشغال الهواء",en:"Airtime Busy",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];if(!w.length)return H.card(H.lang==='ar'?'انشغال الهواء':'Airtime Busy','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا يوجد راديو':'No radios')+'</div>',null,'signal');var rows='';for(var i=0;i<w.length;i++){var r=w[i],sv=r.survey||{};var b=H.num(sv.busy_pct);b=H.finite(b)?H.clamp(b,0,100):null;var col=b==null?'var(--muted)':(b<30?'var(--excellent)':b<60?'var(--good)':b<80?'var(--mid)':'var(--weak)');var lab=b==null?'—':H.fmt(b,0)+'%';rows+='<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+'</span><span style="color:'+col+'">'+lab+'</span></div>'+H.bar(b||0,100,col)+'</div>';}return H.card(H.lang==='ar'?'انشغال الهواء':'Airtime Busy',rows,null,'signal');}},
  {key:"noise_floor",ar:"أرضية الضوضاء",en:"Noise Floor",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var rows='',n=0;for(var i=0;i<w.length;i++){var r=w[i];var nf=H.num(r.noise_dbm);if(nf==null&&r.survey)nf=H.num(r.survey.noise_dbm);if(!H.finite(nf))continue;n++;var pct=H.clamp((nf+100)/40*100,0,100);var col=nf<=-90?'var(--excellent)':nf<=-80?'var(--good)':nf<=-70?'var(--mid)':'var(--weak)';rows+='<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+'</span><span style="color:'+col+'">'+H.fmt(nf,0)+' dBm</span></div>'+H.bar(pct,100,col)+'</div>';}if(!n)rows='<div style="color:var(--muted)">'+(H.lang==='ar'?'لا بيانات ضوضاء':'No noise data')+'</div>';return H.card(H.lang==='ar'?'أرضية الضوضاء':'Noise Floor',rows,null,'signal');}},
  {key:"spectrum_load",ar:"حمل الطيف",en:"Spectrum Load",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var s=0,n=0;for(var i=0;i<w.length;i++){var b=H.num((w[i].survey||{}).busy_pct);if(H.finite(b)){s+=H.clamp(b,0,100);n++;}}if(!n)return H.card(H.lang==='ar'?'حمل الطيف':'Spectrum Load','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا بيانات':'No data')+'</div>',null,'signal');var busy=s/n;var col=busy<30?'var(--excellent)':busy<60?'var(--good)':busy<80?'var(--mid)':'var(--weak)';var C=2*Math.PI*52,off=C*(1-busy/100);var svg='<svg width="140" height="140" viewBox="0 0 140 140" style="display:block;margin:0 auto"><circle cx="70" cy="70" r="52" fill="none" stroke="var(--muted)" stroke-opacity=".2" stroke-width="14"/><circle cx="70" cy="70" r="52" fill="none" stroke="'+col+'" stroke-width="14" stroke-linecap="round" stroke-dasharray="'+C.toFixed(1)+'" stroke-dashoffset="'+off.toFixed(1)+'" transform="rotate(-90 70 70)"/><text x="70" y="66" text-anchor="middle" font-size="26" fill="var(--text)">'+H.fmt(busy,0)+'%</text><text x="70" y="88" text-anchor="middle" font-size="11" fill="var(--muted)">'+(H.lang==='ar'?'مشغول':'busy')+'</text></svg>';var sub='<div style="text-align:center;color:var(--muted);font-size:12px;margin-top:4px">'+n+' '+(H.lang==='ar'?'راديو · متوسط':'radios · avg')+'</div>';return H.card(H.lang==='ar'?'حمل الطيف':'Spectrum Load',svg+sub,H.fmt(busy,0)+'%','signal');}},
  {key:"interference_index",ar:"تقدير انشغال الهواء والضوضاء",en:"Airtime / Noise Estimate",cat:"RF & Airtime",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],arr=[];for(var i=0;i<w.length;i++){var r=w[i],busy=H.num((r.survey||{}).busy_pct),nf=H.num(r.noise_dbm);if(!H.finite(nf)&&r.survey)nf=H.num(r.survey.noise_dbm);var sum=0,weight=0,src=[];if(H.finite(busy)){sum+=H.clamp(busy,0,100)*0.6;weight+=0.6;src.push((a?'انشغال ':'busy ')+H.fmt(busy,0)+'%');}if(H.finite(nf)){sum+=H.clamp((nf+95)/30*100,0,100)*0.4;weight+=0.4;src.push((a?'ضوضاء ':'noise ')+H.fmt(nf,0)+' dBm');}if(!weight)continue;arr.push({band:r.band||'?',ch:r.channel,idx:H.clamp(sum/weight,0,100),src:src.join(' · ')});}var title=a?'تقدير انشغال الهواء والضوضاء':'Airtime / Noise Estimate';if(!arr.length)return H.card(title,'<div style="color:var(--muted)">'+(a?'لا مدخلات انشغال أو ضوضاء':'No airtime or noise inputs')+'</div>',null,'shield');arr.sort(function(x,y){return y.idx-x.idx});var rows='';for(var j=0;j<arr.length;j++){var e=arr[j],col=e.idx<30?'var(--excellent)':e.idx<55?'var(--good)':e.idx<75?'var(--mid)':'var(--weak)';rows+='<div style="margin:6px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(e.band)+' · ch '+H.esc(String(e.ch||'?'))+'</span><span style="color:'+col+'">'+H.fmt(e.idx,0)+'</span></div>'+H.bar(e.idx,100,col)+'<div style="font-size:10px;color:var(--muted)">'+H.esc(e.src)+'</div></div>';}rows+='<small class="muted">'+(a?'تقدير من لقطة الانشغال/الضوضاء المتاحة؛ لا يحدد مصدر التداخل.':'Estimate from available busy/noise snapshots; it cannot identify an interference source.')+'</small>';return H.card(title,rows,null,'shield');}},
  {key:"band_balance",ar:"توازن الترددات",en:"Band Balance",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var c24=0,c5=0,found=false;for(var i=0;i<w.length;i++){var r=w[i];var cl=H.num(r.clients);cl=H.finite(cl)?cl:(Array.isArray(r.stations)?r.stations.length:0);if(r.band==='2.4G')c24+=cl;else if(r.band==='5G')c5+=cl;found=true;}if(!found)return H.card(H.lang==='ar'?'توازن الترددات':'Band Balance','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا راديو':'No radios')+'</div>',null,'wifi');var tot=c24+c5;var p24=tot?c24/tot*100:50,p5=tot?c5/tot*100:50;var bar='<div style="display:flex;height:26px;border-radius:6px;overflow:hidden;background:var(--muted)"><div style="width:'+p24.toFixed(1)+'%;background:var(--mid);display:flex;align-items:center;justify-content:center;font-size:11px;color:#000">'+(p24>12?'2.4G':'')+'</div><div style="width:'+p5.toFixed(1)+'%;background:var(--accent);display:flex;align-items:center;justify-content:center;font-size:11px;color:#000">'+(p5>12?'5G':'')+'</div></div>';var leg='<div style="display:flex;justify-content:space-between;margin-top:8px;font-size:12px"><span style="color:var(--mid)">2.4G · '+c24+' ('+H.fmt(p24,0)+'%)</span><span style="color:var(--accent)">5G · '+c5+' ('+H.fmt(p5,0)+'%)</span></div>';return H.card(H.lang==='ar'?'توازن الترددات':'Band Balance',bar+leg,tot+(H.lang==='ar'?' جهاز':' cl'),'wifi');}},
  {key:"channel_width",ar:"عرض القناة",en:"Channel Width",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];if(!w.length)return H.card(H.lang==='ar'?'عرض القناة':'Channel Width','<div style="color:var(--muted)">'+(H.lang==='ar'?'لا راديو':'No radios')+'</div>',null,'net');var wm={HE20:20,HE40:40,HE80:80,HE160:160,VHT80:80,VHT40:40,VHT20:20,HT20:20,HT40:40};var cells='';for(var i=0;i<w.length;i++){var r=w[i];var ht=String(r.htmode||'').toUpperCase();var mhz=wm[ht]||H.num(r.width)||20;var pct=H.clamp(mhz/160*100,0,100);var col=mhz>=80?'var(--excellent)':mhz>=40?'var(--good)':'var(--mid)';cells+='<div style="flex:1;min-width:118px;padding:10px;border:1px solid var(--muted);border-radius:8px;margin:4px"><div style="font-size:12px;color:var(--muted)">'+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+'</div><div style="font-size:20px;color:'+col+';font-weight:600">'+mhz+' MHz</div><div style="font-size:11px;color:var(--muted);margin-bottom:4px">'+H.esc(ht||'—')+'</div>'+H.bar(pct,100,col)+'</div>';}return H.card(H.lang==='ar'?'عرض القناة':'Channel Width','<div style="display:flex;flex-wrap:wrap">'+cells+'</div>',null,'net');}},
  {key:"cochannel_pressure",ar:"استدلال حمل القناة",en:"Channel Load Heuristic",cat:"RF & Airtime",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],arr=[];for(var i=0;i<w.length;i++){var r=w[i],busy=H.num((r.survey||{}).busy_pct);if(!H.finite(busy))continue;busy=H.clamp(busy,0,100);var cl=H.num(r.clients);cl=H.finite(cl)?cl:(Array.isArray(r.stations)?r.stations.length:0);arr.push({band:r.band||'?',ch:r.channel,value:H.clamp(busy*(1+Math.min(cl,12)/12),0,100),busy:busy,clients:cl});}var title=a?'استدلال حمل القناة':'Channel Load Heuristic';if(!arr.length)return H.card(title,'<div style="color:var(--muted)">'+(a?'لا قراءة انشغال':'No busy reading')+'</div>',null,'signal');arr.sort(function(x,y){return y.value-x.value});var rows='';for(var j=0;j<arr.length;j++){var e=arr[j],col=e.value<35?'var(--excellent)':e.value<60?'var(--good)':e.value<80?'var(--mid)':'var(--weak)';rows+='<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:12px"><span>'+H.esc(e.band)+' ch '+H.esc(String(e.ch||'?'))+'</span><span style="color:'+col+'">'+H.fmt(e.value,0)+'</span></div>'+H.bar(e.value,100,col)+'<div style="font-size:10px;color:var(--muted)">'+H.fmt(e.busy,0)+'% busy · '+e.clients+' '+(a?'عملاء محليون':'local clients')+'</div></div>';}rows+='<small class="muted">'+(a?'استدلال من انشغال القناة وعدد العملاء المحليين فقط؛ لا توجد بيانات تداخل قنوات مجاورة، لذلك لا يثبت ضغطاً مشتركاً.':'Busy airtime plus local-client count only; no neighbor-overlap input is present, so this does not prove co-channel pressure.')+'</small>';return H.card(title,rows,null,'signal');}},
// ---------- Clients & Devices ----------
{key:"client_signal_rank",ar:"ترتيب إشارة العملاء",en:"Client Signal Ranking",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});if(!st.length)return H.card(H.lang==="ar"?"ترتيب إشارة العملاء":"Client Signal Ranking","<div class='empty'>"+(H.lang==="ar"?"لا عملاء":"No clients")+"</div>",null,"device");st.sort(function(a,b){return (H.num(b.signal_dbm)||-999)-(H.num(a.signal_dbm)||-999);});var r=st.slice(0,8).map(function(s){var v=H.num(s.signal_dbm),q=H.quality("rssi",v);return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(s.ip||s.mac||"?")+"</span><span style='color:"+q.color+"'>"+(H.finite(v)?v+" dBm":"?")+"</span></div>"+H.bar(H.finite(v)?H.signalPct("rssi",v):0,100,q.color)+"</div>";}).join("");return H.card(H.lang==="ar"?"ترتيب إشارة العملاء":"Client Signal Ranking",r,st.length+"","device");}},
{key:"sticky_clients",ar:"عملاء 2.4G ذوو إشارة قوية",en:"Strong-signal 2.4G Clients",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push({b:w.band,s:s});});});var candidates=st.filter(function(x){return x.b==="2.4G"&&H.finite(H.num(x.s.signal_dbm))&&H.num(x.s.signal_dbm)>=-70;});var title=H.lang==="ar"?"عملاء 2.4G ذوو إشارة قوية":"Strong-signal 2.4G Clients";var body=candidates.length?candidates.map(function(x){return "<div class='kv'><div><span class='latin'>"+H.esc(x.s.ip||x.s.mac)+"</span><b style='color:var(--mid)'>"+H.num(x.s.signal_dbm)+" dBm</b></div></div>";}).join(""):"<div style='color:var(--muted)'>"+(H.lang==="ar"?"لا توجد لقطة مطابقة للعتبة الحالية":"No snapshot matches the current threshold")+"</div>";body+="<small class='muted'>"+(H.lang==="ar"?"هذه ملاحظة RSSI فقط؛ توافق العميل مع 5G وقرار التوجيه غير متحققين.":"RSSI observation only; 5G client capability and a steering decision are not verified.")+"</small>";return H.card(title,body,candidates.length+"","wifi");}},
{key:"idle_clients",ar:"عملاء خاملون",en:"Idle Clients",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});if(!st.length)return H.card(H.lang==="ar"?"عملاء خاملون":"Idle Clients","<div class='empty'>—</div>",null,"device");var idle=st.filter(function(s){return H.finite(H.num(s.inactive_ms))&&H.num(s.inactive_ms)>60000;});idle.sort(function(a,b){return H.num(b.inactive_ms)-H.num(a.inactive_ms);});var body=idle.length?idle.map(function(s){return "<div class='kv'><div><span class='latin'>"+H.esc(s.ip||s.mac)+"</span><b class='latin'>"+Math.round(H.num(s.inactive_ms)/1000)+"s</b></div></div>";}).join(""):"<div style='color:var(--muted)'>"+(H.lang==="ar"?"كل العملاء نشطون":"All clients active")+"</div>";return H.card(H.lang==="ar"?"عملاء خاملون":"Idle Clients",body,idle.length+"/"+st.length,"device");}},
{key:"client_uptime",ar:"مدة اتصال العملاء",en:"Client Connected Time",cat:"Clients & Devices",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});var wt=st.filter(function(s){return H.finite(H.num(s.conn_s));});if(!wt.length)return H.card(H.lang==="ar"?"مدة الاتصال":"Connected Time","<div class='empty'>—</div>",null,"device");wt.sort(function(a,b){return H.num(b.conn_s)-H.num(a.conn_s);});var r=wt.slice(0,8).map(function(s){var t=H.num(s.conn_s),h=Math.floor(t/3600),m=Math.floor(t%3600/60);return "<div class='kv'><div><span class='latin'>"+H.esc(s.ip||s.mac)+"</span><b class='latin'>"+(h?h+"h "+m+"m":m+"m")+"</b></div></div>";}).join("");return H.card(H.lang==="ar"?"مدة اتصال العملاء":"Client Connected Time",r,wt.length+"","device");}},
{key:"device_type_split",ar:"توزيع أنواع الأجهزة",en:"Device Type Split",cat:"Clients & Devices",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"أنواع الأجهزة":"Device Types","<div class='empty'>—</div>",null,"device");var c={};dv.forEach(function(x){var t=x.type||"?";c[t]=(c[t]||0)+1;});var tot=dv.length,cols={WiFi:"var(--accent)",Ethernet:"var(--primary)",LAN:"var(--good)"};var r=Object.keys(c).map(function(k){var p=c[k]/tot*100;return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(k)+"</span><span>"+c[k]+" ("+H.fmt(p,0)+"%)</span></div>"+H.bar(p,100,cols[k]||"var(--muted)")+"</div>";}).join("");return H.card(H.lang==="ar"?"توزيع أنواع الأجهزة":"Device Type Split",r,tot+"","device");}},
{key:"fastest_client",ar:"نطاق آخر لقطة PHY",en:"Last PHY Snapshot Range",cat:"Clients & Devices",fn:function(d,H){
  var st=H.stationRateSnapshots(d,"tx").filter(function(x){return H.finite(x.info.rate);});
  var title=H.lang==="ar"?"نطاق آخر لقطة PHY":"Last PHY Snapshot Range";
  if(!st.length)return H.card(title,"<div class='empty'>—</div>",null,"net");
  st.sort(function(a,b){return b.info.rate-a.info.rate;});
  var hi=st[0],lo=st[st.length-1];
  function box(x,lbl){var age=H.stationInactiveAge(x.station.inactive_ms);return "<div class='traffic-box'><span>"+lbl+"</span><b class='latin' style='color:var(--accent)'>"+H.fmt(x.info.rate,x.info.rate<100?1:0)+" Mbps</b><small class='muted latin'>"+H.esc(x.station.ip||x.station.mac)+(age?" · "+H.esc(age):"")+"</small></div>";}
  var note="<small class='muted' style='display:block;margin-top:7px'>"+(H.lang==="ar"?"ترتيب لآخر إطار PHY فقط؛ ليس اختبار سرعة أو استهلاكاً.":"Ranks only the last PHY frame snapshot; not a speed test or traffic consumption.")+"</small>";
  return H.card(title,"<div class='grid two'>"+box(hi,H.lang==="ar"?"أعلى لقطة":"Higher snapshot")+box(lo,H.lang==="ar"?"أدنى لقطة":"Lower snapshot")+"</div>"+note,st.length+"","net");
}},
// ---------- Security & Threats ----------
{key:"encryption_posture",ar:"لقطة تشفير الشبكات",en:"SSID Encryption Snapshot",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=d.wifi||[],title=a?'لقطة تشفير الشبكات':'SSID Encryption Snapshot';if(!w.length)return H.card(title,"<div class='empty'>—</div>",null,"shield");var open=0,rows=w.map(function(x){var s=H.secLevel(x.encryption);if(s.key==='open')open++;return "<div class='kv'><div><span class='latin'>"+H.esc(x.ssid||x.iface)+"</span><b style='color:"+s.col+"'>"+H.esc(s.txt)+"</b></div><small class='muted'>"+H.esc(String(x.encryption||'none'))+"</small></div>";}).join('');rows+="<small class='muted'>"+(a?'تشفير SSID المعلن فقط؛ لا يثبت PMF أو العزل أو الجدار الناري أو تعرّض الإدارة.':'Advertised SSID encryption only; this does not prove PMF, isolation, firewall policy, or management exposure.')+"</small>";return H.card(title,rows,open?(open+' '+(a?'مفتوحة':'open')):(a?'لم تُرصد شبكة مفتوحة':'no open SSID observed'),"shield");}},
{key:"mac_random",ar:"العناوين العشوائية",en:"MAC Randomization",cat:"Security & Threats",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"العناوين العشوائية":"MAC Randomization","<div class='empty'>—</div>",null,"shield");var rnd=0;dv.forEach(function(x){var h=String(x.mac||"").replace(/[^0-9a-fA-F]/g,"");if(h.length>=2&&(parseInt(h.slice(0,2),16)&2))rnd++;});var p=rnd/dv.length*100,C=2*Math.PI*46,off=C*(1-p/100);var svg="<svg width='120' height='120' viewBox='0 0 120 120' style='display:block;margin:0 auto'><circle cx='60' cy='60' r='46' fill='none' stroke='var(--muted)' stroke-opacity='.2' stroke-width='12'/><circle cx='60' cy='60' r='46' fill='none' stroke='var(--primary)' stroke-width='12' stroke-linecap='round' stroke-dasharray='"+C.toFixed(1)+"' stroke-dashoffset='"+off.toFixed(1)+"' transform='rotate(-90 60 60)'/><text x='60' y='66' text-anchor='middle' font-size='22' fill='var(--text)'>"+H.fmt(p,0)+"%</text></svg><div style='text-align:center;color:var(--muted);font-size:12px'>"+rnd+"/"+dv.length+" "+(H.lang==="ar"?"خاص":"private")+"</div>";return H.card(H.lang==="ar"?"العناوين العشوائية":"MAC Randomization",svg,null,"shield");}},
{key:"vendor_breakdown",ar:"توزيع الشركات",en:"Vendor Breakdown",cat:"Security & Threats",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"الشركات":"Vendors","<div class='empty'>—</div>",null,"device");var c={};dv.forEach(function(x){var v=x.vendor||(H.lang==="ar"?"غير معروف":"Unknown");c[v]=(c[v]||0)+1;});var ks=Object.keys(c).sort(function(a,b){return c[b]-c[a];}),mx=c[ks[0]]||1;var r=ks.slice(0,7).map(function(k){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(k)+"</span><span>"+c[k]+"</span></div>"+H.bar(c[k],mx,"var(--accent)")+"</div>";}).join("");return H.card(H.lang==="ar"?"توزيع الشركات":"Vendor Breakdown",r,ks.length+"","device");}},
{key:"newest_devices",ar:"أحدث الأجهزة",en:"Newest Devices",cat:"Security & Threats",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"أحدث الأجهزة":"Newest Devices","<div class='empty'>—</div>",null,"shield");var r=dv.slice(-6).reverse().map(function(x){return "<div class='kv'><div><span class='latin'>"+H.esc((x.mac||"?").toUpperCase())+"</span><b class='latin'>"+H.esc(x.ip||x.host||x.type||"")+"</b></div><small class='muted'>"+H.esc(x.vendor||"")+"</small></div>";}).join("");return H.card(H.lang==="ar"?"أحدث الأجهزة المكتشفة":"Newest Devices",r,dv.length+"","shield");}},
{key:"open_net_warn",ar:"رصد الشبكات المفتوحة",en:"Open SSID Observation",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=d.wifi||[],op=w.filter(function(x){var e=String(x.encryption||'').toLowerCase();return !e||/none|open/.test(e);}),body=op.length?("<div style='color:var(--mid)'>"+(a?'شبكات تعلن بلا تشفير:':'SSIDs advertising no encryption:')+"</div>"+op.map(function(x){return "<div class='kv'><div><span class='latin'>"+H.esc(x.ssid||x.iface)+"</span><b style='color:var(--mid)'>OPEN</b></div></div>";}).join('')):("<div style='color:var(--muted)'>"+(a?'لم تُرصد شبكة مفتوحة في هذه اللقطة':'No open SSID observed in this snapshot')+"</div>");return H.card(a?'رصد الشبكات المفتوحة':'Open SSID Observation',body,String(op.length),"shield");}},
{key:"threat_summary",ar:"ملخص ملاحظات الأمان",en:"Security-relevant Observations",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=d.wifi||[],dv=(H.mergeDevices(d)||[]),op=w.filter(function(x){var e=String(x.encryption||'').toLowerCase();return !e||/none|open/.test(e);}).length,rnd=0;dv.forEach(function(x){var h=String(x.mac||'').replace(/[^0-9a-fA-F]/g,'');if(h.length>=2&&(parseInt(h.slice(0,2),16)&2))rnd++;});var items=[[a?'شبكات مفتوحة':'Open SSIDs',op,op?'var(--mid)':'var(--muted)'],[a?'أجهزة مرصودة':'Observed devices',dv.length,'var(--primary)'],[a?'عناوين MAC خاصة':'Private MACs',rnd,'var(--accent)']];var body="<div class='grid two'>"+items.map(function(it){return "<div class='traffic-box'><span>"+it[0]+"</span><b style='color:"+it[2]+"'>"+it[1]+"</b></div>";}).join('')+"</div><small class='muted'>"+(a?'الأعداد وصفية وليست اكتشاف تهديدات.':'Descriptive counts, not threat detection.')+"</small>";return H.card(a?'ملخص ملاحظات الأمان':'Security-relevant Observations',body,null,"shield");}},
// ---------- Traffic & Bandwidth ----------
{key:"live_throughput",ar:"حركة العملاء الحية",en:"Live Client Traffic",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{},download=H.num(t.rx_bps)||0,upload=H.num(t.tx_bps)||0,complete=t.topology_complete===true;var body="<div class='grid two'><div class='traffic-box'><span>↓ "+(H.lang==='ar'?'تنزيل':'Download')+"</span><b class='latin' style='color:var(--accent)'>"+H.bps(download)+"</b></div><div class='traffic-box'><span>↑ "+(H.lang==='ar'?'رفع':'Upload')+"</span><b class='latin' style='color:var(--primary)'>"+H.bps(upload)+"</b></div></div><div style='margin-top:10px'>"+H.bar(download+upload?download/(download+upload)*100:50,100,"var(--accent)")+"</div>";if(!complete)body+="<small class='muted'>"+H.esc(H.trafficCoverageNote(d))+"</small>";return H.card(H.lang==="ar"?"حركة العملاء الحية":"Live Client Traffic",body,complete?null:(H.lang==='ar'?'Wi-Fi فقط':'Wi-Fi only'),"net");}},
{key:"iface_data_rank",ar:"ترتيب عدادات الواجهات الخام",en:"Raw Interface Counter Ranking",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',ifs=d.interfaces||[],title=a?'ترتيب عدادات الواجهات الخام':'Raw Interface Counter Ranking';if(!ifs.length)return H.card(title,"<div class='empty'>—</div>",null,"net");var rows=ifs.map(function(i){return {n:i.name,b:(H.num(i.rx_bytes)||0)+(H.num(i.tx_bytes)||0)};}).sort(function(x,y){return y.b-x.b;}),max=rows[0].b||1,body=rows.slice(0,7).map(function(i){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(i.n)+"</span><span class='latin'>"+H.bytes(i.b)+"</span></div>"+H.bar(i.b,max,"var(--primary)")+"</div>";}).join('');body+="<small class='muted'>"+(a?'عدادات خام مستقلة وغير قابلة للجمع؛ قد تتداخل طبقات الشبكة وتُصفّر كل واجهة مستقلاً.':'Independent, non-additive raw counters; network layers can overlap and each interface can reset independently.')+"</small>";return H.card(title,body,ifs.length+"","net");}},
{key:"error_drop_watch",ar:"مراقب الأخطاء والفقد",en:"Errors & Drops",cat:"Traffic & Bandwidth",fn:function(d,H){var ifs=d.interfaces||[];if(!ifs.length)return H.card(H.lang==="ar"?"الأخطاء":"Errors","<div class='empty'>—</div>",null,"net");var bad=ifs.map(function(i){return {n:i.name,e:(H.num(i.rx_errors)||0)+(H.num(i.tx_errors)||0),dr:(H.num(i.rx_dropped)||0)+(H.num(i.tx_dropped)||0)};}).filter(function(i){return i.e||i.dr;}).sort(function(a,b){return (b.e+b.dr)-(a.e+a.dr);});var body=bad.length?bad.map(function(i){return "<div class='kv'><div><span class='latin'>"+H.esc(i.n)+"</span><b class='latin' style='color:var(--weak)'>"+i.e+" err · "+i.dr+" drop</b></div></div>";}).join(""):"<div style='color:var(--excellent)'>"+(H.lang==="ar"?"لا أخطاء ولا فقد":"No errors or drops")+"</div>";return H.card(H.lang==="ar"?"مراقب الأخطاء والفقد":"Errors & Drops",body,bad.length+"","shield");}},
{key:"total_data",ar:"لقطة عدادات حافة العملاء",en:"Client-edge Counter Snapshot",cat:"Traffic & Bandwidth",fn:function(d,H){var t=d.traffic||{},download=H.num(t.rx_bytes)||0,upload=H.num(t.tx_bytes)||0,complete=t.topology_complete===true;var body="<div class='grid two'><div class='traffic-box'><span>"+(H.lang==="ar"?"تنزيل":"Download")+"</span><b class='latin'>"+H.bytesNet(download)+"</b></div><div class='traffic-box'><span>"+(H.lang==="ar"?"رفع":"Upload")+"</span><b class='latin'>"+H.bytesNet(upload)+"</b></div></div><p class='muted' style='margin-top:8px'>"+(complete?(H.lang==="ar"?"إجمالي حافة العملاء":"Client-edge total"):(H.lang==="ar"?"الإجمالي المرصود (طوبولوجيا جزئية)":"Observed subtotal (partial topology)"))+": "+H.bytesNet(download+upload)+"</p><small class='muted'>"+(H.lang==='ar'?'منذ إعادة ضبط الواجهة؛ ليس أسبوعياً أو شهرياً.':'Since interface reset; not a weekly or monthly total.')+"</small>"+(complete?"":"<small class='muted'>"+H.esc(H.trafficCoverageNote(d))+"</small>");return H.card(H.lang==="ar"?"لقطة عدادات حافة العملاء":"Client-edge Counter Snapshot",body,complete?(H.lang==='ar'?'طوبولوجيا مكتملة':'complete topology'):(H.lang==='ar'?'Wi-Fi فقط':'Wi-Fi only'),"net");}},
  {key:"updown_ratio",ar:"نسبة التنزيل/الرفع",en:"Download / Upload Ratio",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',t=d.traffic||{},download=H.num(t.rx_bytes)||0,upload=H.num(t.tx_bytes)||0,tot=download+upload,title=a?'نسبة التنزيل/الرفع':'Download / Upload Ratio';if(!tot)return H.card(title,"<div class='empty'>—</div>",null,"net");var pd=download/tot*100,pu=upload/tot*100;var body="<div style='display:flex;height:24px;border-radius:6px;overflow:hidden'><div style='width:"+pd.toFixed(1)+"%;background:var(--accent)'></div><div style='width:"+pu.toFixed(1)+"%;background:var(--primary)'></div></div><div style='display:flex;justify-content:space-between;margin-top:6px;font-size:12px'><span style='color:var(--accent)'>↓ "+(a?'تنزيل ':'Download ')+H.fmt(pd,0)+"%</span><span style='color:var(--primary)'>↑ "+(a?'رفع ':'Upload ')+H.fmt(pu,0)+"%</span></div>";if(t.topology_complete!==true)body+="<small class='muted'>"+H.esc(H.trafficCoverageNote(d))+"</small>";return H.card(title,body,null,"net");}},
{key:"backhaul_status",ar:"حالة الوصلة العلوية",en:"Backhaul Status",cat:"Traffic & Bandwidth",fn:function(d,H){var b=d.backhaul||{},on=!!b.online,col=on?"var(--excellent)":"var(--mid)";var body="<div class='kv'><div><span>"+(H.lang==="ar"?"الحالة":"Status")+"</span><b style='color:"+col+"'>"+(on?(H.lang==="ar"?"متصل":"Online"):(H.lang==="ar"?"LAN فقط":"LAN only"))+"</b></div><div><span>"+(H.lang==="ar"?"البوابة":"Gateway")+"</span><b class='latin'>"+H.esc(b.gateway||"—")+"</b></div><div><span>"+(H.lang==="ar"?"المنفذ":"Device")+"</span><b class='latin'>"+H.esc(b.device||"—")+"</b></div></div>";return H.card(H.lang==="ar"?"حالة الوصلة العلوية":"Backhaul Status",body,on?"up":"lan","net");}},
// ---------- System & Health ----------
{key:"cpu_gauge",ar:"المعالج",en:"CPU",cat:"System & Health",fn:function(d,H){var c=d.cpu||{},p=H.clamp(H.num(c.percent)||0,0,100);return H.card(H.lang==="ar"?"المعالج":"CPU",H.gauge("CPU",p+"%","load",(c.cores||"?")+" cores",p,H.quality("system",p).color,"cpu"),null,"cpu");}},
{key:"ram_gauge",ar:"الذاكرة",en:"RAM",cat:"System & Health",fn:function(d,H){var m=d.mem||{},tot=H.num(m.total)||0,av=H.num(m.available)||0,used=tot-av,p=tot?H.clamp(used/tot*100,0,100):0;return H.card(H.lang==="ar"?"الذاكرة":"RAM",H.gauge("RAM",H.fmt(p,0)+"%",H.bytes(used),H.bytes(av)+" free",p,H.quality("system",p).color,"ram"),null,"cpu");}},
{key:"storage_gauge",ar:"التخزين",en:"Storage",cat:"System & Health",fn:function(d,H){var s=d.storage||{},tot=H.num(s.total)||0,us=H.num(s.used)||0,p=tot?H.clamp(us/tot*100,0,100):0;return H.card(H.lang==="ar"?"التخزين":"Storage",H.gauge("Storage",H.fmt(p,0)+"%",H.bytes(us),H.bytes(H.num(s.available)||0)+" free",p,H.quality("system",p).color,"storage"),null,"cpu");}},
{key:"thermal_zones",ar:"الحارس الحراري",en:"Thermal Guardian",cat:"System & Health",fn:function(d,H){var t=H.num(d.temperature_c);if(!H.finite(t))return H.card(H.lang==="ar"?"الحرارة":"Thermal","<div style='color:var(--muted)'>"+(H.lang==="ar"?"المستشعر غير متوفر":"Sensor unavailable")+"</div>",null,"cpu");var z=t<55?[H.lang==="ar"?"طبيعية":"Normal","var(--excellent)"]:t<70?[H.lang==="ar"?"دافئة":"Warm","var(--good)"]:t<82?[H.lang==="ar"?"مرتفعة":"High","var(--mid)"]:[H.lang==="ar"?"حرجة":"Critical","var(--weak)"];var body="<div style='text-align:center;font-size:34px;font-weight:800;color:"+z[1]+"'>"+H.fmt(t,1)+"&deg;</div><div style='text-align:center;color:"+z[1]+";margin-bottom:8px'>"+z[0]+"</div>"+H.bar(H.clamp(t,0,100),100,z[1]);return H.card(H.lang==="ar"?"الحارس الحراري":"Thermal Guardian",body,z[0],"cpu");}},
{key:"load_avg",ar:"متوسط الحمل",en:"Load Average",cat:"System & Health",fn:function(d,H){var l=d.load||[];if(!l.length)return H.card(H.lang==="ar"?"متوسط الحمل":"Load","<div class='empty'>—</div>",null,"cpu");var cores=(d.cpu&&d.cpu.cores)||1,labs=["1m","5m","15m"];var r=l.slice(0,3).map(function(v,i){var la=(H.num(v)||0)/65536,p=H.clamp(la/cores*100,0,100),col=p<60?"var(--excellent)":p<90?"var(--mid)":"var(--weak)";return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+labs[i]+"</span><span class='latin'>"+H.fmt(la,2)+"</span></div>"+H.bar(p,100,col)+"</div>";}).join("");return H.card(H.lang==="ar"?"متوسط الحمل":"Load Average",r,cores+" cores","cpu");}},
{key:"uptime_card",ar:"مدة التشغيل",en:"Uptime",cat:"System & Health",fn:function(d,H){var u=H.num(d.uptime)||0,dd=Math.floor(u/86400),h=Math.floor(u%86400/3600),m=Math.floor(u%3600/60);var big=dd?dd+"d "+h+"h":h+"h "+m+"m";return H.card(H.lang==="ar"?"مدة التشغيل":"Uptime","<div style='text-align:center;font-size:30px;font-weight:800;color:var(--accent)'>"+big+"</div><div style='text-align:center;color:var(--muted);font-size:12px'>"+H.esc(d.hostname||"")+" · "+H.esc(d.os||"")+"</div>",null,"bolt");}},
{key:"health_breakdown",ar:"مدخلات درجة موارد النظام",en:"System Resource Score Inputs",cat:"System & Health",fn:function(d,H){var a=H.lang==='ar',h=d.health||{},sc=H.num(h.score),title=a?'مدخلات درجة موارد النظام':'System Resource Score Inputs';if(!H.finite(sc))return H.card(title,"<div class='empty'>—</div>",null,"shield");var col=sc>=85?"var(--excellent)":sc>=70?"var(--good)":sc>=50?"var(--mid)":"var(--weak)",rs=(h.reasons||[]).map(function(r){var rc=r.level==="ok"?"var(--excellent)":r.level==="mid"?"var(--mid)":"var(--weak)";return "<div style='font-size:12px;padding:5px 8px;border-radius:6px;background:rgba(148,185,255,.08);border-inline-start:3px solid "+rc+";margin:4px 0'>"+H.esc(a?(r.ar||r.en):(r.en||r.ar))+"</div>";}).join("");if(!rs)rs="<small class='muted'>"+(a?'لا تحذيرات موارد في مدخلات الدرجة المتاحة.':'No resource warnings in the available score inputs.')+"</small>";return H.card(title,"<div style='text-align:center;font-size:40px;font-weight:800;color:"+col+"'>"+sc+"</div>"+rs,a?'موارد مأخوذة كعينة':'sampled resources',"shield");}},
// ---------- Latency & Link Quality ----------
{key:"gateway_latency",ar:"زمن جلب لوحة الراوتر",en:"Dashboard Fetch Latency",cat:"Latency & Link Quality",fn:function(d,H){var a=H.lang==='ar',l=H.num(d.latency_ms),title=a?'زمن جلب لوحة الراوتر':'Dashboard Fetch Latency';if(!H.finite(l))return H.card(title,"<div style='color:var(--muted)'>"+(a?'غير متوفر':'N/A')+"</div>",null,"net");var col=l<10?"var(--excellent)":l<30?"var(--good)":l<60?"var(--mid)":"var(--weak)";return H.card(title,"<div style='text-align:center;font-size:36px;font-weight:800;color:"+col+"'>"+H.fmt(l,1)+" ms</div>"+H.bar(H.clamp(100-l,0,100),100,col)+"<small class='muted'>"+(a?'زمن طلب API للوحة، وليس Ping للبوابة أو الإنترنت.':'Dashboard API request time, not gateway or Internet ping.')+"</small>",null,"net");}},
{key:"link_eff_rank",ar:"تفاصيل آخر PHY",en:"Last PHY Details",cat:"Latency & Link Quality",fn:function(d,H){
  var list=H.stationRateSnapshots(d,"tx").filter(function(x){return H.finite(x.info.rate);});
  var title=H.lang==="ar"?"تفاصيل آخر PHY":"Last PHY Details";
  if(!list.length)return H.card(title,"<div class='empty'>—</div>",null,"net");
  var rows=list.slice(0,8).map(function(x){var i=x.info,age=H.stationInactiveAge(x.station.inactive_ms),meta=[];if(i.family)meta.push(i.family);if(H.finite(i.mcs))meta.push("MCS "+i.mcs);if(H.finite(i.nss))meta.push("NSS "+i.nss);if(H.finite(i.width))meta.push(i.width+"MHz");if(age)meta.push((H.lang==="ar"?"خمول ":"inactive ")+age);return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px;gap:8px'><span class='latin'>"+H.esc(x.station.ip||x.station.mac||"?")+"</span><span class='latin' style='color:var(--accent)'>"+H.fmt(i.rate,i.rate<100?1:0)+" Mbps</span></div><small class='muted latin'>"+H.esc(meta.join(" · "))+"</small></div>";}).join("");
  rows+="<small class='muted'>"+(H.lang==="ar"?"لقطة آخر إطار وليست throughput.":"Last-frame snapshot, not throughput.")+"</small>";
  return H.card(title,rows,list.length+"","net");
}},
{key:"snr_board",ar:"لوحة جودة SNR",en:"SNR Quality Board",cat:"Latency & Link Quality",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push(s);});});var wt=st.filter(function(s){return H.finite(H.num(s.snr));});if(!wt.length)return H.card(H.lang==="ar"?"جودة SNR":"SNR Board","<div class='empty'>—</div>",null,"signal");wt.sort(function(a,b){return H.num(b.snr)-H.num(a.snr);});var r=wt.slice(0,8).map(function(s){var v=H.num(s.snr),col=v>=40?"var(--excellent)":v>=25?"var(--good)":v>=15?"var(--mid)":"var(--weak)";return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(s.ip||s.mac)+"</span><span style='color:"+col+"'>"+v+" dB</span></div>"+H.bar(H.clamp(v/50*100,0,100),100,col)+"</div>";}).join("");return H.card(H.lang==="ar"?"لوحة جودة SNR":"SNR Quality Board",r,wt.length+"","signal");}},
{key:"expected_actual",ar:"تقدير الدرايفر للنقل",en:"Driver Throughput Estimate",cat:"Latency & Link Quality",fn:function(d,H){
  var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){var e=H.num(s.expected_mbps);if(H.finite(e))st.push({s:s,e:e});});});
  var title=H.lang==="ar"?"تقدير الدرايفر للنقل":"Driver Throughput Estimate";
  if(!st.length)return H.card(title,"<div class='empty'>"+(H.lang==="ar"?"الدرايفر لا يوفّر التقدير":"Driver estimate unavailable")+"</div>",null,"net");
  var rows=st.slice(0,7).map(function(x){return "<div class='kv'><div><span class='latin'>"+H.esc(x.s.ip||x.s.mac||"?")+"</span><b class='latin'>"+H.fmt(x.e,1)+" Mbps</b></div></div>";}).join("");
  rows+="<small class='muted'>"+(H.lang==="ar"?"تقدير مستقل من الدرايفر؛ لا يُقارن بلقطة PHY اللحظية.":"A separate driver estimate; it is not compared with the instantaneous PHY snapshot.")+"</small>";
  return H.card(title,rows,st.length+"","net");
}},
{key:"weakest_link",ar:"أضعف وصلة",en:"Weakest Link",cat:"Latency & Link Quality",fn:function(d,H){var st=[];(d.wifi||[]).forEach(function(w){(w.stations||[]).forEach(function(s){st.push({b:w.band,s:s});});});if(!st.length)return H.card(H.lang==="ar"?"أضعف وصلة":"Weakest Link","<div class='empty'>—</div>",null,"signal");st.sort(function(a,b){return (H.num(a.s.signal_dbm)||0)-(H.num(b.s.signal_dbm)||0);});var x=st[0],v=H.num(x.s.signal_dbm),q=H.quality("rssi",v),dist=H.distanceM(v);return H.card(H.lang==="ar"?"أضعف وصلة":"Weakest Link","<div style='text-align:center;font-size:26px;font-weight:800;color:"+q.color+"'>"+(H.finite(v)?v+" dBm":"?")+"</div><div style='text-align:center' class='latin'>"+H.esc(x.s.ip||x.s.mac)+"</div><div style='text-align:center;color:var(--muted);font-size:12px'>"+H.esc(x.b||"")+(dist!==null?" · ≈"+(dist<10?dist.toFixed(1):Math.round(dist))+"m":"")+"</div>",q.text,"signal");}},
// ---------- Topology & Discovery ----------
{key:"port_map",ar:"خريطة المنافذ",en:"Port Map",cat:"Topology & Discovery",fn:function(d,H){var ifs=d.interfaces||[];if(!ifs.length)return H.card(H.lang==="ar"?"خريطة المنافذ":"Port Map","<div class='empty'>—</div>",null,"net");var r="<div style='display:flex;flex-wrap:wrap;gap:8px'>"+ifs.map(function(i){var on=i.connected,col=on?"var(--excellent)":"var(--muted)";return "<div style='flex:1;min-width:96px;padding:8px;border:1px solid "+col+";border-radius:8px;text-align:center'><div class='latin' style='font-weight:700'>"+H.esc(i.name)+"</div><div style='font-size:11px;color:"+col+"'>"+(on?(i.speed_mbps?i.speed_mbps+"M":"up"):"down")+"</div></div>";}).join("")+"</div>";return H.card(H.lang==="ar"?"خريطة المنافذ":"Port Map",r,ifs.filter(function(i){return i.connected;}).length+"/"+ifs.length,"net");}},
{key:"dev_per_port",ar:"أجهزة لكل منفذ",en:"Devices per Port",cat:"Topology & Discovery",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"أجهزة لكل منفذ":"Devices per Port","<div class='empty'>—</div>",null,"device");var c={};dv.forEach(function(x){var k=x.iface||"?";c[k]=(c[k]||0)+1;});var ks=Object.keys(c).sort(function(a,b){return c[b]-c[a];}),mx=c[ks[0]]||1;var r=ks.map(function(k){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(k)+"</span><span>"+c[k]+"</span></div>"+H.bar(c[k],mx,"var(--primary)")+"</div>";}).join("");return H.card(H.lang==="ar"?"أجهزة لكل منفذ":"Devices per Port",r,dv.length+"","device");}},
{key:"lan_wifi_split",ar:"توزيع سلكي/لاسلكي",en:"LAN vs WiFi",cat:"Topology & Discovery",fn:function(d,H){var dv=(H.mergeDevices(d)||[]);if(!dv.length)return H.card(H.lang==="ar"?"سلكي/لاسلكي":"LAN/WiFi","<div class='empty'>—</div>",null,"device");var wf=dv.filter(function(x){return x.type==="WiFi";}).length,ln=dv.length-wf,tot=dv.length,pw=wf/tot*100,pl=ln/tot*100;var bar="<div style='display:flex;height:24px;border-radius:6px;overflow:hidden'><div style='width:"+pw.toFixed(1)+"%;background:var(--accent)'></div><div style='width:"+pl.toFixed(1)+"%;background:var(--primary)'></div></div><div style='display:flex;justify-content:space-between;margin-top:6px;font-size:12px'><span style='color:var(--accent)'>WiFi "+wf+"</span><span style='color:var(--primary)'>LAN "+ln+"</span></div>";return H.card(H.lang==="ar"?"توزيع سلكي/لاسلكي":"LAN vs WiFi",bar,tot+"","device");}},
{key:"bridge_members",ar:"أعضاء الجسر",en:"Bridge Members",cat:"Topology & Discovery",fn:function(d,H){var ifs=(d.interfaces||[]).filter(function(i){return /^(lan|wan|phy)/.test(i.name||"");});if(!ifs.length)return H.card(H.lang==="ar"?"أعضاء الجسر":"Bridge Members","<div class='empty'>—</div>",null,"net");var r=ifs.map(function(i){var col=i.connected?"var(--excellent)":"var(--muted)";return "<div class='kv'><div><span class='latin'>"+H.esc(i.name)+"</span><b style='color:"+col+"'>"+(i.connected?"up":"down")+"</b></div></div>";}).join("");return H.card(H.lang==="ar"?"أعضاء الجسر":"Bridge Members",r,ifs.length+"","net");}},
{key:"gateway_path",ar:"مسار البوابة",en:"Gateway Path",cat:"Topology & Discovery",fn:function(d,H){var b=d.backhaul||{},steps=[[H.esc(d.hostname||"AP"),"var(--accent)"],[H.esc(b.device||"br-lan"),"var(--primary)"],[H.esc(b.gateway||(H.lang==="ar"?"البوابة":"gateway")),b.online?"var(--excellent)":"var(--mid)"]];var r="<div style='display:flex;align-items:center;gap:6px;flex-wrap:wrap'>"+steps.map(function(s,i){return "<span style='padding:6px 10px;border-radius:8px;background:rgba(148,185,255,.1);color:"+s[1]+";font-weight:700' class='latin'>"+s[0]+"</span>"+(i<steps.length-1?"<span style='color:var(--muted)'>&rarr;</span>":"");}).join("")+"</div>";return H.card(H.lang==="ar"?"مسار البوابة":"Gateway Path",r,b.online?"online":"lan","net");}},
// ---------- Automation & UX ----------
{key:"net_score_tile",ar:"درجة موارد النظام",en:"System Resource Score",cat:"Automation & UX",fn:function(d,H){var a=H.lang==='ar',h=d.health||{},sc=H.num(h.score),title=a?'درجة موارد النظام':'System Resource Score';if(!H.finite(sc))return H.card(title,"<div class='empty'>—</div>",null,"shield");var col=sc>=85?"var(--excellent)":sc>=70?"var(--good)":sc>=50?"var(--mid)":"var(--weak)",C=2*Math.PI*50,off=C*(1-sc/100);var svg="<svg width='150' height='150' viewBox='0 0 150 150' style='display:block;margin:0 auto'><circle cx='75' cy='75' r='50' fill='none' stroke='var(--muted)' stroke-opacity='.2' stroke-width='14'/><circle cx='75' cy='75' r='50' fill='none' stroke='"+col+"' stroke-width='14' stroke-linecap='round' stroke-dasharray='"+C.toFixed(1)+"' stroke-dashoffset='"+off.toFixed(1)+"' transform='rotate(-90 75 75)'/><text x='75' y='78' text-anchor='middle' font-size='34' font-weight='800' fill='"+col+"'>"+sc+"</text><text x='75' y='98' text-anchor='middle' font-size='11' fill='var(--muted)'>/100</text></svg><small class='muted'>"+(a?'CPU والذاكرة والتخزين والحرارة فقط؛ ليست صحة شبكة شاملة.':'CPU, memory, storage and temperature only; not overall network health.')+"</small>";return H.card(title,svg,a?'موارد مأخوذة كعينة':'sampled resources',"shield");}},
{key:"recommendations",ar:"تنبيهات الموارد",en:"Resource Warnings",cat:"Automation & UX",fn:function(d,H){var a=H.lang==='ar',rs=(d.health&&d.health.reasons)||[],title=a?'تنبيهات الموارد':'Resource Warnings';if(!rs.length)return H.card(title,"<div style='color:var(--muted)'>"+(a?'لا تحذيرات موارد في مدخلات الدرجة المتاحة':'No resource warnings in available score inputs')+"</div>",null,"bolt");var body=rs.map(function(r){var rc=r.level==="ok"?"var(--excellent)":r.level==="mid"?"var(--mid)":"var(--weak)";return "<div style='font-size:13px;padding:7px 10px;border-radius:8px;background:rgba(148,185,255,.08);border-inline-start:3px solid "+rc+";margin:5px 0'>"+H.esc(a?(r.ar||r.en):(r.en||r.ar))+"</div>";}).join("");return H.card(title,body,rs.length+"","bolt");}},
{key:"kpi_strip",ar:"شريط المؤشرات",en:"KPI Strip",cat:"Automation & UX",fn:function(d,H){var w=d.wifi||[],dv=(H.mergeDevices(d)||[]),air=H.num((d.health||{}).busy_pct),lat=H.num(d.latency_ms),tmp=H.num(d.temperature_c);var items=[[H.lang==="ar"?"أجهزة":"Devices",dv.length,"var(--primary)"],[H.lang==="ar"?"شبكات":"SSIDs",w.length,"var(--accent)"],[H.lang==="ar"?"هواء":"Air",H.finite(air)?air+"%":"—","var(--mid)"],[H.lang==="ar"?"استجابة":"Lat",H.finite(lat)?H.fmt(lat,0)+"ms":"—","var(--good)"],[H.lang==="ar"?"حرارة":"Temp",H.finite(tmp)?H.fmt(tmp,0)+"°":"—","var(--weak)"]];var r="<div style='display:flex;flex-wrap:wrap;gap:8px'>"+items.map(function(it){return "<div style='flex:1;min-width:80px;text-align:center;padding:8px;border-radius:8px;background:rgba(148,185,255,.06)'><div style='font-size:22px;font-weight:800;color:"+it[2]+"'>"+it[1]+"</div><div style='font-size:11px;color:var(--muted)'>"+it[0]+"</div></div>";}).join("")+"</div>";return H.card(H.lang==="ar"?"شريط المؤشرات":"KPI Strip",r,null,"bolt");}},
{key:"capacity_headroom",ar:"هامش الموارد المرصود",en:"Observed Resource Headroom",cat:"Automation & UX",fn:function(d,H){var air=H.num((d.health||{}).busy_pct),cpu=H.num((d.cpu||{}).percent),m=d.mem||{},mt=H.num(m.total),ma=H.num(m.available),mp=H.finite(mt)&&H.finite(ma)&&mt>0?(1-ma/mt)*100:null,values=[air,cpu,mp].filter(H.finite),title=H.lang==="ar"?"هامش الموارد المرصود":"Observed Resource Headroom";if(!values.length)return H.card(title,"<div class='empty'>"+(H.lang==="ar"?"لا توجد مدخلات CPU/RAM/زمن بث":"No CPU, RAM, or airtime inputs")+"</div>",H.lang==="ar"?"غير معروف":"unknown","cpu");var mn=values.reduce(function(v,x){return Math.min(v,H.clamp(100-x,0,100));},100),col=mn>=50?"var(--excellent)":mn>=25?"var(--good)":mn>=10?"var(--mid)":"var(--weak)",body="<div style='text-align:center;font-size:36px;font-weight:800;color:"+col+"'>"+H.fmt(mn,0)+"%</div><div style='text-align:center;color:var(--muted);font-size:12px;margin-bottom:8px'>"+(H.lang==="ar"?"أقل هامش من المدخلات المتاحة فقط":"tightest available input only")+"</div>"+H.bar(mn,100,col)+"<small class='muted'>"+(H.lang==="ar"?"لقطة CPU/RAM/زمن بث؛ ليست سعة شبكة أو اختبار تحميل.":"CPU/RAM/airtime snapshot; not network capacity or a load test.")+"</small>";return H.card(title,body,values.length+(H.lang==="ar"?" مدخلات":" inputs"),"cpu");}},
{key:"air_quality_index",ar:"تقدير وقت الهواء الخامل",en:"Observed Idle Airtime Estimate",cat:"Automation & UX",fn:function(d,H){var a=H.lang==='ar',w=d.wifi||[],s=0,n=0;w.forEach(function(x){var b=H.num((x.survey||{}).busy_pct);if(H.finite(b)){s+=H.clamp(b,0,100);n++;}});var title=a?'تقدير وقت الهواء الخامل':'Observed Idle Airtime Estimate';if(!n)return H.card(title,"<div class='empty'>—</div>",null,"signal");var idle=H.clamp(100-s/n,0,100),col=idle>=70?"var(--excellent)":idle>=45?"var(--good)":idle>=25?"var(--mid)":"var(--weak)";var body="<div style='text-align:center;font-size:40px;font-weight:800;color:"+col+"'>"+H.fmt(idle,0)+"%</div>"+H.bar(idle,100,col)+"<small class='muted'>"+(a?'100% ناقص متوسط انشغال الراديوهات المرصود؛ ليس مقياس جودة شامل.':'100% minus observed average radio busy time; not a comprehensive air-quality metric.')+"</small>";return H.card(title,body,n+(a?' راديو':' radios'),"signal");}},
{key:"quick_summary",ar:"الملخص السريع",en:"Quick Summary",cat:"Automation & UX",fn:function(d,H){var dv=(H.mergeDevices(d)||[]),w=d.wifi||[],parts=[];parts.push((H.lang==="ar"?"أجهزة: ":"Devices: ")+dv.length);parts.push((H.lang==="ar"?"شبكات: ":"Networks: ")+w.length);if(H.finite(H.num((d.health||{}).score)))parts.push((H.lang==="ar"?"درجة الموارد: ":"Resource score: ")+H.num(d.health.score));if(H.finite(H.num(d.temperature_c)))parts.push((H.lang==="ar"?"الحرارة: ":"Temp: ")+H.fmt(H.num(d.temperature_c),0)+"°");var body="<div style='font-size:14px;line-height:2'>"+parts.map(function(p){return "<span style='display:inline-block;padding:4px 10px;margin:3px;border-radius:8px;background:rgba(148,185,255,.08)'>"+H.esc(p)+"</span>";}).join("")+"</div>";return H.card(H.lang==="ar"?"الملخص السريع":"Quick Summary",body,d.hostname||"","bolt");}},
   {key:"rf_dfs_channel_board",ar:"لوحة القنوات و DFS",en:"DFS & Channel Board",cat:"RF & Airtime",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[];if(!w.length)return H.card(A?'لوحة القنوات و DFS':'DFS & Channel Board','<div style="color:var(--muted);text-align:center;padding:14px">'+(A?'لا توجد بيانات واي فاي':'No WiFi data')+'</div>','--','shield');var h='',dn=0;for(var i=0;i<w.length;i++){var r=w[i]||{},cn=+(r.channel)||0,b=H.esc(String(r.band||'?')),m=String(r.htmode||'').match(/(\d+)/),wd=m?m[1]:'20',is5=String(r.band||'').indexOf('5')===0,dfs=is5&&cn>=52&&cn<=144,signal=H.num(r.signal_dbm);if(dfs)dn++;var c=dfs?'var(--mid)':'var(--muted)',dfsLabel=dfs?'DFS':(A?'غير DFS':'non-DFS'),signalText=H.finite(signal)?H.fmt(signal,0)+' dBm':'—';h+='<div style="display:flex;align-items:center;gap:6px;padding:7px 0 2px;flex-wrap:wrap"><b style="color:var(--primary);min-width:42px">'+b+'</b><span style="background:var(--border);border-radius:6px;padding:2px 8px;font-weight:600">CH '+(cn||'?')+'</span><span style="background:var(--border);border-radius:6px;padding:2px 8px">'+H.esc(wd)+'MHz</span><span style="margin-'+(A?'right':'left')+':auto;color:'+c+';font-weight:700">&#9679; '+dfsLabel+'</span></div><div style="font-size:11px;color:var(--muted);padding:0 0 6px;border-bottom:1px solid var(--border)">'+H.esc(String(r.ssid||''))+' &middot; '+H.esc(String(r.htmode||''))+' &middot; '+(A?'إشارة ':'sig ')+signalText+'</div>';}var chip=dn?(dn+' DFS'):(A?'غير DFS':'non-DFS');return H.card(A?'لوحة القنوات و DFS':'DFS & Channel Board',h,chip,'shield');}},
   {key:"rf_airtime_efficiency",ar:"لقطة حمل زمن البث",en:"Airtime Load Snapshot",cat:"RF & Airtime",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[],title=A?'لقطة حمل زمن البث':'Airtime Load Snapshot';if(!w.length)return H.card(title,'<div style="color:var(--muted);text-align:center;padding:14px">'+(A?'لا توجد بيانات':'No data')+'</div>','--','signal');var h='',known=0;for(var i=0;i<w.length;i++){var r=w[i]||{},busy=H.num((r.survey||{}).busy_pct),cl=H.num(r.clients);if(!H.finite(busy))continue;known++;busy=H.clamp(busy,0,100);var col=busy<40?'var(--excellent)':busy<65?'var(--good)':busy<85?'var(--mid)':'var(--weak)';h+='<div style="padding:6px 0"><div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:3px"><b>'+H.esc(String(r.band||'?'))+'</b><span class="latin">'+H.fmt(busy,0)+'% busy</span></div>'+H.bar(busy,100,col)+'<div style="font-size:11px;color:var(--muted);margin-top:3px">'+(A?'العملاء المرتبطون: ':'Associated clients: ')+(H.finite(cl)?H.fmt(cl,0):'—')+'</div></div>';}if(!known)h='<div style="color:var(--muted);text-align:center;padding:14px">'+(A?'لا توجد قراءة انشغال':'No busy reading')+'</div>';h+='<small class="muted">'+(A?'هذه قراءة انشغال القناة وعدد العملاء فقط؛ ليست كفاءة أو عدالة زمن بث لكل عميل.':'Channel busy and associated-client telemetry only; this is not per-client airtime efficiency or fairness.')+'</small>';return H.card(title,h,String(known),'signal');}},
   {key:"roaming_candidates",ar:"ملاحظات RSSI للتجوال",en:"RSSI Roaming Observations",cat:"Clients & Devices",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[],has5=w.some(function(r){return r&&r.band==='5G'}),dev={};((d&&d.devices)||[]).forEach(function(x){if(x&&x.mac)dev[String(x.mac).toUpperCase()]=x.host||x.ip||''});var L=[];w.forEach(function(r){if(!r||!r.stations)return;r.stations.forEach(function(s){if(!s)return;var sg=H.num(s.signal_dbm);if(H.finite(sg)&&sg<=-67)L.push({m:String(s.mac||''),b:r.band||'',sg:sg})})});L.sort(function(a,b){return a.sg-b.sg});var n=L.length,h;if(!n)h='<div style="text-align:center;padding:12px;color:var(--muted)">'+(A?'لا توجد لقطة RSSI تحت العتبة الحالية':'No RSSI snapshot below the current threshold')+'</div>';else h=L.slice(0,5).map(function(c){var nm=dev[c.m.toUpperCase()]||c.m.slice(-8),col=c.sg<=-75?'var(--weak)':'var(--mid)',tip=(c.b==='2.4G'&&has5)?(A?'يمكن تقييم 5G يدوياً':'5G can be evaluated manually'):(A?'يمكن تقييم موضع الجهاز':'Device placement can be evaluated');return '<div style="margin:6px 0"><div style="display:flex;justify-content:space-between;font-size:11px"><b>'+H.esc(nm)+'</b><span style="color:'+col+'">'+H.fmt(c.sg,0)+' dBm · '+H.esc(c.b)+'</span></div>'+H.bar(H.clamp(c.sg+95,0,55),55,col)+'<div style="font-size:10px;color:var(--accent)">'+tip+'</div></div>'}).join('');h+='<small class="muted">'+(A?'هذه ملاحظة RSSI لحظية فقط؛ لا تثبت قرار التجوال أو بقاء الاتصال.':'RSSI snapshot only; it does not prove a roam decision or continued connectivity.')+'</small>';return H.card(A?'ملاحظات RSSI للتجوال':'RSSI Roaming Observations',h,String(n)+(A?' تحت العتبة':' below threshold'),'signal')}},
   {key:"distance_leaderboard",ar:"أبعد العملاء",en:"Distance Leaderboard",cat:"Clients & Devices",fn:function(d,H){var A=H.lang==='ar',w=(d&&d.wifi)||[];var dev={};((d&&d.devices)||[]).forEach(function(x){if(x&&x.mac)dev[String(x.mac).toUpperCase()]=x.host||x.ip||''});var L=[];w.forEach(function(r){if(!r||!r.stations)return;r.stations.forEach(function(s){if(!s)return;var sg=H.num(s.signal_dbm);if(!H.finite(sg))return;var dm=H.num(H.distanceM(sg));if(!H.finite(dm)||dm<0)return;L.push({m:String(s.mac||''),b:r.band||'',dm:dm})})});L.sort(function(a,b){return b.dm-a.dm});var mx=L.length?L[0].dm:1,h;if(!L.length){h='<div style="text-align:center;padding:12px;color:var(--muted)">'+(A?'لا عملاء متصلين':'No connected clients')+'</div>'}else{h=L.slice(0,6).map(function(c,i){var nm=dev[c.m.toUpperCase()]||c.m.slice(-8);var col=c.dm>12?'var(--weak)':c.dm>7?'var(--mid)':c.dm>3?'var(--good)':'var(--excellent)';return '<div style="margin:6px 0"><div style="display:flex;justify-content:space-between;font-size:11px"><span>#'+(i+1)+' <b>'+H.esc(nm)+'</b> <span style="color:var(--muted)">'+H.esc(c.b)+'</span></span><b style="color:'+col+'">~'+H.fmt(c.dm,1)+(A?' م':' m')+'</b></div>'+H.bar(c.dm,mx||1,col)+'</div>'}).join('')+'<div style="font-size:10px;color:var(--muted);margin-top:4px">'+(A?'تقدير من قوة الإشارة':'Estimated from RSSI')+'</div>'}
return H.card(A?'أبعد العملاء':'Distance Leaderboard',h,String(L.length)+(A?' جهاز':' clients'),'device')}},
   {key:"client_bw_share",ar:"استهلاك العملاء الفعلي",en:"Real Client Traffic",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',t=a?'استهلاك العملاء الفعلي':'Real Client Traffic',rows=H.stationTrafficRows(d).filter(function(r){return r.rateSource==='byte-counter-delta'&&r.totalRate>0;});if(!rows.length)return H.card(t,'<div class="empty">'+(a?'لا توجد فروق عدادات بايت فعلية':'No measured byte-counter deltas')+'</div>',null,'device');rows.sort(function(x,y){return y.totalRate-x.totalRate;});var total=rows.reduce(function(sum,r){return sum+r.totalRate;},0),body='';rows.slice(0,6).forEach(function(r){body+='<div style="display:flex;justify-content:space-between;gap:8px;margin:6px 0;font-size:12px"><span class="latin">'+H.esc(r.label)+'</span><b class="latin">'+H.bps(r.totalRate)+'</b></div>';});body+='<small class="muted">'+(a?'من فروق عدادات البايت فقط؛ لا تستخدم لقطة PHY أو expected_mbps.':'Byte-counter deltas only; last PHY snapshots and expected_mbps are never used as traffic.')+'</small>';return H.card(t,body,H.bps(total),'device');}},
   {key:"bridge_pps_tile",ar:"حركة حافة العملاء",en:"Client-edge Traffic",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',title=a?'حركة حافة العملاء':'Client-edge Traffic',tr=d.traffic||{},download=H.num(tr.rx_bps)||0,upload=H.num(tr.tx_bps)||0,total=download+upload;if(!total&&!(H.num(tr.rx_bytes)||0)&&!(H.num(tr.tx_bytes)||0))return H.card(title,'<div class="empty">'+(a?'لا بيانات':'No data')+'</div>',null,'net');var pps=total/750,pl=pps>=1000?H.fmt(pps/1000,1)+'k':H.fmt(pps,0),cap=H.verifiedUplinkCapacity(d);var body='<div style="text-align:center"><div class="latin" style="font-size:30px;font-weight:800;color:var(--primary)">'+H.bps(total)+'</div><div style="font-size:11px;color:var(--muted)">≈ '+pl+' pps @750B</div></div><div class="grid two"><div class="traffic-box"><span>↓ '+(a?'تنزيل':'Download')+'</span><b class="latin" style="color:var(--accent)">'+H.bps(download)+'</b></div><div class="traffic-box"><span>↑ '+(a?'رفع':'Upload')+'</span><b class="latin" style="color:var(--primary)">'+H.bps(upload)+'</b></div></div>';if(cap){var downPct=H.clamp(download/cap.bytesPerSecond*100,0,100),upPct=H.clamp(upload/cap.bytesPerSecond*100,0,100);body+='<div style="margin-top:10px"><div style="display:flex;justify-content:space-between;font-size:11px;color:var(--muted)"><span>'+H.esc(cap.device)+' '+(a?'تنزيل':'download')+'</span><span class="latin">'+H.fmt(downPct,1)+'% / '+H.fmt(cap.speedMbps,0)+'M</span></div>'+H.bar(downPct,100,'var(--accent)')+'<div style="display:flex;justify-content:space-between;font-size:11px;color:var(--muted);margin-top:4px"><span>'+H.esc(cap.device)+' '+(a?'رفع':'upload')+'</span><span class="latin">'+H.fmt(upPct,1)+'%</span></div>'+H.bar(upPct,100,'var(--primary)')+'</div>';}else body+='<small class="muted">'+(a?'لا تُعرض نسبة استخدام: يلزم طوبولوجيا مكتملة وسرعة موثقة لمنفذ uplink المحدد.':'No utilization percentage: complete topology and a documented speed for the selected uplink are required.')+'</small>';return H.card(title,body,cap?cap.device:null,'bolt');}},
   {key:"setup_checklist",ar:"قائمة فحص الإعداد",en:"Setup Checklist",cat:"Automation & UX",fn:function(d,H){var A=H.lang==='ar',t=A?'قائمة فحص الإعداد':'Setup Checklist';d=d||{};var hs=H.num((d.health||{}).score),tc=H.num(d.temperature_c),lt=H.num(d.latency_ms),cl=H.num(d.clients),bo=(d.backhaul||{}).online;var L=[[A?'الوصلة الرئيسية متصلة':'Upstream online',bo===true,bo==null],[A?'يوجد أجهزة متصلة':'Clients connected',cl>0,!H.finite(cl)],[A?'درجة الموارد أعلى من 70':'Resource score &gt; 70',hs>70,!H.finite(hs)],[A?'الحرارة أقل من 70°C':'Temp &lt; 70°C',tc<70,!H.finite(tc)],[A?'جلب اللوحة أقل من 20ms':'Dashboard fetch &lt; 20ms',lt<20,!H.finite(lt)]];var ok=0,tot=0,r='';for(var i=0;i<5;i++){var u=L[i][2],p=L[i][1];if(!u){tot++;if(p)ok++}var c=u?'var(--muted)':p?'var(--excellent)':'var(--weak)';r+='<div style="display:flex;align-items:center;gap:9px;margin:7px 0;font-size:12px"><span style="flex:0 0 20px;height:20px;border-radius:50%;border:1.5px solid '+c+';color:'+c+';font-weight:700;display:flex;align-items:center;justify-content:center">'+(u?'?':p?'✓':'✕')+'</span><span style="flex:1">'+L[i][0]+'</span></div>'}var pc=tot?ok/tot*100:0,col=tot?(pc>=80?'var(--excellent)':pc>=60?'var(--good)':pc>=40?'var(--mid)':'var(--weak)'):'var(--muted)';return H.card(t,'<div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px"><span>'+(A?'الفحوص المعروفة':'Known checks')+'</span><b style="color:'+col+'">'+ok+'/'+tot+'</b></div>'+(tot?H.bar(pc,100,col):'')+'<div style="height:6px"></div>'+r,ok+'/'+tot,'gear')}},
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
        var sourceNote = '<small class="muted">' + (a ? 'من فروق عدادات البايت فقط؛ لا تُستخدم لقطة PHY أو expected_mbps كحركة.' : 'Byte-counter deltas only; PHY snapshots and expected_mbps are never traffic.') + '</small>';
        return H.card(title, svg + '<div style="margin-top:8px">' + leg + '</div>' + sourceNote, H.bps(total), 'device');
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
  // #57 - real driver TX power: show requested, driver-reported applied,
  // and the active channel limit without presenting any value as an RF measurement.
  PRO_FEATURES.push({key:"x_mesh_peers",ar:"شبكة الميش (المرسِل/العقد)",en:"Mesh (Sender/Nodes)",cat:"RF & Airtime",fn:function(d,H){var A=H.lang==="ar";var w=Array.isArray(d.wifi)?d.wifi:[];var mesh=w.filter(function(r){return (r&&(r.mode==="mesh"))|| /mesh/i.test((r&&r.iface)||"");});var T=A?"شبكة الميش (المرسِل/العقد)":"Mesh (Sender/Nodes)";if(!mesh.length)return H.card(T,"<div style='color:var(--muted)'>"+(A?"لا يوجد ميش مفعّل":"No mesh active")+"</div>",null,"signal");var rows="",total=0;mesh.forEach(function(m){var peers=Array.isArray(m.stations)?m.stations:[];total+=peers.length;rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin-top:6px'><b>"+H.esc(m.ssid||m.iface||"mesh")+"</b><span class='latin' style='color:var(--muted)'>"+H.esc((m.band||"")+" ch "+(m.channel||"?"))+"</span></div>";if(!peers.length)rows+="<div style='font-size:11px;color:var(--muted)'>"+(A?"بانتظار عقدة/مرسِل للاتصال…":"waiting for a peer/sender to link…")+"</div>";peers.forEach(function(p){var sig=H.num(p.signal_dbm);var col=!H.finite(sig)?"var(--muted)":(sig>-65?"var(--excellent)":(sig>-78?"var(--mid)":"var(--weak)"));rows+="<div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+H.esc(p.mac||"?")+"</span><span class='latin' style='color:"+col+"'>"+(H.finite(sig)?H.fmt(sig,0)+" dBm":"—")+"</span></div>";});});var note="<div style='font-size:11px;color:var(--muted);margin-top:4px'>"+(A?"عقد 802.11s — المرسِل يظهر هنا فور اتصاله":"802.11s peers — the sender appears here once it links")+"</div>";return H.card(T,rows+note,String(total),"signal");}});
  PRO_FEATURES.push({key:"tx_power_status",ar:"طاقة البث (مطلوب/مقبول)",en:"TX Power (Requested/Accepted)",cat:"RF & Airtime",fn:function(d,H){var A=H.lang==="ar", rows="";((d&&d.wifi)||[]).forEach(function(w){var p=(w&&w.txpower)||{}, req=H.num(p.requested_dbm), app=H.num(p.applied_dbm), max=H.num(p.max_dbm), state=String(p.status||"unknown"), reason=String(p.reason||"");var reqTxt=H.finite(req)?H.fmt(req,0)+" dBm":"—";var appTxt=H.finite(app)?H.fmt(app,0)+" dBm":"—";var maxTxt=H.finite(max)?H.fmt(max,0)+" dBm":"—";var match=state==="accepted"||H.finite(req)&&H.finite(app)&&app>=req;var appCol=!H.finite(app)?"var(--muted)":match?"var(--excellent)":"var(--mid)";var head="<div style='display:flex;justify-content:space-between;font-size:12px'><b>"+H.esc((w.band||"?")+" ch "+(w.channel||"?"))+"</b><span class='latin' style='color:var(--muted)'>"+H.esc(w.iface||"")+"</span></div>";var line="<div style='display:flex;justify-content:space-between;font-size:12px;margin-top:3px'><span>"+(A?"مطلوب":"Requested")+"</span><span class='latin'>"+reqTxt+"</span></div>"+"<div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(A?"مقبول (درايفر)":"Accepted (driver)")+"</span><span class='latin' style='color:"+appCol+"'>"+appTxt+"</span></div>"+"<div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(A?"حد القناة":"Channel maximum")+"</span><span class='latin'>"+maxTxt+"</span></div>";var reasonLine=state==="limited"?"<div style='font-size:10px;color:var(--mid);margin-top:4px'>"+H.esc(reason||(A?"تم التخفيض بواسطة التنظيم أو القناة أو المعايرة أو المعدلات أو SAR أو البرنامج الثابت أو الحرارة":"limited by regulatory, channel, calibration, rate, SAR, firmware, or thermal constraints"))+"</div>":"";rows+="<div style='margin:9px 0;padding-bottom:7px;border-bottom:1px solid var(--muted)'>"+head+line+reasonLine+H.bar(H.finite(app)?app:0,38,appCol)+"</div>";});if(!rows) rows="<div style='color:var(--muted)'>"+(A?"لا توجد بيانات طاقة":"No power data")+"</div>";var note="<div style='font-size:10px;color:var(--muted);margin-top:4px'>"+(A?"مطلوب = المحفوظ في UCI · مقبول = ما أعلنه الدرايفر (iw) · ليس قياس RF فيزيائي":"Requested = UCI saved · Accepted = driver-declared (iw) · not a physical RF measurement")+"</div>";return H.card(A?"طاقة البث (مطلوب/مقبول)":"TX Power (Requested/Accepted)",rows+note,null,"signal");}});
  PRO_FEATURES.push({key:"driver_banner",ar:"بصمة السائق (RF)",en:"Driver RF Banner",cat:"System & Health",fn:function(d,H){var A=H.lang==="ar";var b=(d&&d.perf&&d.perf.driver_banner)?String(d.perf.driver_banner):"";var active=/CR6608-LAB-38/i.test(b);var col=active?"var(--excellent)":"var(--muted)";var big=b?H.esc(b):(A?"غير معروف":"unknown");var sub=active?(A?"مسار طلب LAB-38 مفعل؛ القدرة المقبولة تظهر منفصلة":"LAB-38 request path active; accepted power is reported separately"):(A?"لم يُقرأ من dmesg بعد":"not read from dmesg yet");var body="<div style=\"text-align:center;padding:6px 0\"><div style=\"font-size:16px;font-weight:800;color:"+col+";word-break:break-word\">"+big+"</div><div style=\"font-size:11px;color:var(--muted);margin-top:6px\">"+sub+"</div></div>";return H.card(A?"بصمة السائق (dmesg)":"Driver RF Banner (dmesg)",body,active?"LAB-38":null,"cpu");}});
  PRO_FEATURES.push({key:"tx_power_limits",ar:"تفاصيل طاقة البث",en:"TX Power Details",cat:"RF & Airtime",fn:function(d,H){
    var rows="";
    ((d&&d.wifi)||[]).forEach(function(w){
      var p=(w&&w.txpower)||{};
      function value(v){v=H.num(v);return H.finite(v)?H.fmt(v,0)+" dBm":"-";}
      var runtimeReady=w&&w.up===true&&w.disabled!==true;
      var items=[
        ["Requested",p.requested_dbm],
        ["Regulatory maximum",p.regulatory_max_dbm],
        ["Channel maximum",p.channel_max_dbm]
      ];
      if(runtimeReady){
        items.push(["Driver maximum",p.driver_max_dbm]);
        items.push(["Driver accepted",p.driver_accepted_dbm]);
        items.push(["Current reported",p.current_reported_dbm]);
      }
      rows+="<div style='margin:8px 0 12px'><b>"+H.esc((w.radio||"?")+" / "+(w.band||"?")+" / ch "+(w.channel||"?"))+"</b>";
      items.forEach(function(item){
        rows+="<div style='display:flex;justify-content:space-between;gap:10px;font-size:11px'><span>"+H.esc(item[0])+"</span><span class='latin'>"+H.esc(value(item[1]))+"</span></div>";
      });
      if(!runtimeReady) rows+="<div style='font-size:11px;color:var(--mid);margin-top:4px'>"+H.esc(String(w.state||"down"))+"</div>";
      if(p.reason) rows+="<div style='font-size:10px;color:var(--mid);margin-top:4px'>"+H.esc(p.reason)+"</div>";
      rows+="</div>";
    });
    if(!rows) rows="<div style='color:var(--muted)'>No power data</div>";
    return H.card(H.lang==="ar"?"تفاصيل طاقة البث":"TX Power Details",rows+"<div style='font-size:10px;color:var(--muted)'>Driver values are not external RF measurements.</div>",null,"signal");
  }});
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
  // #59 — browser-local operational diary (peak clients and temperature only).
  // Traffic is intentionally excluded: volatile interface counters cannot form
  // truthful calendar accounting across reboots or interface reloads.
  PRO_FEATURES.push({key:"weekly_report",ar:"آخر 7 أيام مرصودة بالمتصفح",en:"Last 7 Browser-observed Days",cat:"Automation & UX",fn:function(d,H){
    var A=H.lang==="ar";
    var persist=!state.suspendHistory;
    var day=localDateKey();
    var log; try{ log=JSON.parse(localStorage.getItem(LS+"weeklyLog")||"[]"); }catch(e){ log=[]; }
    if(!Array.isArray(log)) log=[];
    if(persist){
      var cl=Math.max(Number(d.clients)||0, (H.mergeDevices(d)||[]).length), tc=H.num(d.temperature_c);
      var cur=log[log.length-1];
      if(!cur||cur.day!==day){ cur={day:day,peakCl:cl,maxTemp:H.finite(tc)?tc:0}; log.push(cur); }
      else{ if(cl>cur.peakCl)cur.peakCl=cl; if(H.finite(tc)&&tc>cur.maxTemp)cur.maxTemp=tc; }
      while(log.length>7) log.shift();
      try{ localStorage.setItem(LS+"weeklyLog",JSON.stringify(log)); }catch(e){}
    }
    var maxClients=log.reduce(function(m,x){return Math.max(m,Number(x.peakCl)||0);},1);
    var rows=log.slice().reverse().map(function(x){ var peak=Number(x.peakCl)||0;
      return "<div style='margin:5px 0'><div style='display:flex;justify-content:space-between;font-size:11px'><b class='latin'>"+H.esc(x.day.slice(5))+"</b><span class='latin'>"+peak+(A?" جهاز":" clients")+(x.maxTemp?" · "+H.fmt(x.maxTemp,0)+"&deg;":"")+"</span></div>"+H.bar(peak,maxClients,"var(--accent)")+"</div>"; }).join("");
    var days=log.length, avg=days?log.reduce(function(a,x){return a+(Number(x.peakCl)||0);},0)/days:0;
    var head="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:6px'><span>"+(A?"متوسط الذروة في الأيام المرصودة":"average peak on observed days")+"</span><b class='latin'>"+H.fmt(avg,1)+"</b></div>";
    var note="<small class='muted'>"+(A?"آخر سبعة تواريخ شاهدها هذا المتصفح؛ قد تكون غير متتالية، ولا تُقاس الفترات أثناء إغلاق اللوحة.":"Last seven dates seen by this browser; dates can be non-consecutive and time with the dashboard closed is not measured.")+"</small>";
    return H.card(A?"آخر 7 أيام مرصودة بالمتصفح":"Last 7 Browser-observed Days",head+rows+note,days+" observed","gear");
  }});
  // #60 — bandwidth hog: the client pulling the most right now + one-tap limit.
  PRO_FEATURES.push({key:"bandwidth_hog",ar:"ملتهم النطاق",en:"Bandwidth Hog",cat:"Traffic & Bandwidth",fn:function(d,H){
    var A=H.lang==="ar", rows=((H.stationTrafficRows&&H.stationTrafficRows(d))||[]).filter(function(r){return r.rateSource==="byte-counter-delta"&&r.totalRate>0;});
    if(!rows.length) return H.card(A?"ملتهم النطاق":"Bandwidth Hog","<div class='empty'>"+(A?"لا توجد حركة مقاسة حالياً من فروق عدادات البايت":"No current traffic measured from byte-counter deltas")+"</div>",null,"bolt");
    rows.sort(function(a,b){return (b.totalRate||0)-(a.totalRate||0);});
    var top=rows.slice(0,5), mx=top[0].totalRate||1;
    var body=top.map(function(r,i){ var nm=(typeof deviceName==="function"?deviceName(r.mac):"")||r.label;
      var lim=r.mac?"<button class='btn dev-action' data-dev-mac='"+H.esc(r.mac)+"' data-dev-act='__limit' style='font-size:10px;padding:2px 8px'>"+(A?"حدّ":"limit")+"</button>":"";
      return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px;gap:6px'><b>"+(i===0?"&#128293; ":"")+H.esc(nm)+"</b><span class='latin'>"+H.bps(r.totalRate||0)+" "+lim+"</span></div>"+
        H.bar(r.totalRate||0,mx,i===0?"var(--weak)":"var(--accent)")+"<div style='font-size:10px;color:var(--muted)'>&#8595; "+H.bps(r.down||0)+" &#183; &#8593; "+H.bps(r.up||0)+"</div></div>"; }).join("");
    body+="<small class='muted'>"+(A?"استهلاك حي من فروق عدادات البايت فقط؛ لا تُستخدم معدلات PHY.":"Live consumption from byte-counter deltas only; PHY rates are never used.")+"</small>";
    return H.card(A?"ملتهم النطاق":"Bandwidth Hog",body,String(rows.length),"bolt");
  }});
  // #61 — browser-observed backhaul transitions. Long sampling gaps are unknown,
  // never attributed to the state that preceded a closed/suspended dashboard.
  PRO_FEATURES.push({key:"outage_log",ar:"انتقالات الوصلة المرصودة بالمتصفح",en:"Browser-observed Uplink Transitions",cat:"Automation & UX",fn:function(d,H){
    var A=H.lang==="ar", raw=((d&&d.backhaul)||{}).online, observed=raw===true?true:raw===false?false:null, persist=!state.suspendHistory, now=Date.now(), MAX_GAP=60000;
    var st; try{ st=JSON.parse(localStorage.getItem(LS+"outageLog")||"{}"); }catch(e){ st={}; }
    if(!st||typeof st!=="object"||Array.isArray(st)) st={};
    if(!Array.isArray(st.events)) st.events=[];
    var resumed=false;
    if(persist&&observed!==null){
      var gap=!H.finite(H.num(st.lastObserved))||now-H.num(st.lastObserved)>MAX_GAP;
      if(typeof st.online!=="boolean"||gap){ st.online=observed; st.since=now; resumed=gap; }
      else if(observed!==st.online){ var dur=Math.max(0,now-(st.since||now)); if(st.online===false)st.events.unshift({t:now,down:dur}); st.online=observed; st.since=now; }
      st.lastObserved=now; st.events=st.events.slice(0,20);
      try{ localStorage.setItem(LS+"outageLog",JSON.stringify(st)); }catch(e){}
    }
    function dhm(ms){ var s=Math.round(ms/1000); if(s<60)return s+"s"; if(s<3600)return Math.floor(s/60)+"m "+(s%60)+"s"; return Math.floor(s/3600)+"h "+Math.floor((s%3600)/60)+"m"; }
    var online=observed!==null?observed:(typeof st.online==='boolean'?st.online:null),status=online===true?(A?'متصل':'Online'):online===false?(A?'مقطوع':'Offline'):(A?'غير معروف':'Unknown'),color=online===true?'var(--excellent)':online===false?'var(--weak)':'var(--muted)';
    var cur="<div style='text-align:center;margin-bottom:8px'><span style='color:"+color+";font-weight:700'>"+status+"</span>"+(online!==null?" <small class='muted'>"+(A?'مرصود لمدة ':'observed for ')+dhm(now-(st.since||now))+"</small>":"")+"</div>";
    if(resumed)cur+="<div style='font-size:10px;color:var(--muted);text-align:center'>"+(A?'استؤنفت المراقبة بعد فجوة؛ لم تُنسب مدة الفجوة لأي حالة.':'Monitoring resumed after a gap; the gap duration was not assigned to either state.')+"</div>";
    var list=st.events.length?st.events.map(function(e){ var dt=new Date(e.t),hh=("0"+dt.getHours()).slice(-2)+":"+("0"+dt.getMinutes()).slice(-2);return "<div style='display:flex;justify-content:space-between;font-size:11px;margin:4px 0'><span class='latin'>"+hh+"</span><span style='color:var(--weak)'>"+(A?'انقطاع مرصود ':'observed down ')+dhm(e.down)+"</span></div>";}).join(""):"<div style='font-size:11px;color:var(--muted);text-align:center'>"+(A?'لم تُرصد انقطاعات أثناء نشاط اللوحة':'No outages observed while the dashboard was active')+"</div>";
    var note="<small class='muted'>"+(A?'سجل محلي لهذا المتصفح فقط؛ الفترات والانتقالات أثناء إغلاق اللوحة غير معروفة.':'Browser-local log only; periods and transitions while the dashboard is closed are unknown.')+"</small>";
    return H.card(A?"انتقالات الوصلة المرصودة بالمتصفح":"Browser-observed Uplink Transitions",cur+list+note,String(st.events.length),"net");
  }});
  // #62 — browser-local dashboard fetch timing over observed samples.
  PRO_FEATURES.push({key:"latency_monitor",ar:"سجل جلب اللوحة",en:"Dashboard Fetch History",cat:"Traffic & Bandwidth",fn:function(d,H){
    var A=H.lang==="ar", lt=H.num(d&&d.latency_ms);
    var hist; try{ hist=JSON.parse(localStorage.getItem(LS+"latHist")||"[]"); }catch(e){ hist=[]; }
    if(!Array.isArray(hist)) hist=[];
    if(!state.suspendHistory&&H.finite(lt)){ hist.push(lt); if(hist.length>60) hist.shift(); try{ localStorage.setItem(LS+"latHist",JSON.stringify(hist)); }catch(e){} }
    if(!hist.length) return H.card(A?"سجل جلب اللوحة":"Dashboard Fetch History","<div class='empty'>"+(A?"لا بيانات":"No data")+"</div>",null,"net");
    var avg=hist.reduce(function(a,b){return a+b;},0)/hist.length, mx=Math.max.apply(null,hist), now=hist[hist.length-1];
    var col=now<20?"var(--excellent)":now<50?"var(--good)":now<100?"var(--mid)":"var(--weak)";
    var body="<div style='text-align:center'><div class='latin' style='font-size:28px;font-weight:800;color:"+col+"'>"+H.fmt(now,1)+" ms</div></div>"+
      H.spark(hist,col)+"<div class='grid two' style='margin-top:8px'><div class='traffic-box'><span>"+(A?"متوسط":"avg")+"</span><b class='latin'>"+H.fmt(avg,1)+" ms</b></div><div class='traffic-box'><span>"+(A?"أقصى":"max")+"</span><b class='latin'>"+H.fmt(mx,1)+" ms</b></div></div>";
    body+="<small class='muted'>"+(A?'عينات محفوظة في هذا المتصفح أثناء فتح اللوحة؛ ليست RTT للشبكة.':'Samples stored in this browser while the dashboard is open; not network RTT.')+"</small>";
    return H.card(A?"سجل جلب اللوحة":"Dashboard Fetch History",body,H.fmt(now,0)+"ms","net");
  }});
  // #63 — Performance Pack: configuration checklist. UCI/hostapd intent is
  // kept separate from over-air scheduling, which needs compatible clients.
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
    var head="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px'><span>"+(A?"المُهيّأ":"Configured")+"</span><b class='latin' style='color:var(--excellent)'>"+on+"/"+tot+"</b></div>"+H.bar(on,tot,"var(--excellent)")+
      "<div style='display:flex;justify-content:space-between;font-size:11px;color:var(--muted);margin:6px 0'><span>"+(A?"قوة البث المطلوبة":"Requested TX power")+"</span><b class='latin' style='color:var(--excellent)'>"+(H.finite(H.num(p.txpower))?H.fmt(H.num(p.txpower),0)+" dBm":"—")+"</b></div>";
    var body=head+
      grp(A?"MIMO / AX":"MIMO / AX",
        row(p.mu_bf_he,"MU-MIMO (AX)","MU-MIMO (AX)",A?"مُعلن؛ الجدولة تحتاج عدة عملاء متوافقين":"advertised; scheduling needs compatible clients")+
        row(p.mu_bf_vht,"MU-MIMO (AC)","MU-MIMO (AC)",A?"مُعلن لأجهزة AC؛ الاستخدام غير مقاس":"advertised for AC; use not measured")+
        row(p.su_bf,"Beamforming",  "Beamforming",A?"قدرة وإعلان؛ الاستخدام الهوائي غير مقاس":"capable and advertised; airtime use not measured")+
        row(p.spatial_reuse,A?"إعادة استخدام مكاني":"Spatial Reuse",A?"إعادة استخدام مكاني":"Spatial Reuse",A?"أداء أعلى في الزحام":"better in congestion")+
        row(p.bss_color,"BSS Color","BSS Color",""))+
      grp(A?"إعدادات العملاء البعيدين":"Far-client settings",
        row(p.dynack,A?"مهلة ACK ديناميكية":"Dynamic ACK",A?"مهلة ACK ديناميكية":"Dynamic ACK",A?"إعداد مهيأ؛ النتيجة الهوائية غير مقاسة":"configured; over-air outcome unmeasured")+
        row(p.ldpc,"LDPC","LDPC",A?"قدرة مهيأة؛ نجاح فك الترميز غير مقاس":"configured capability; decode success unmeasured")+
        row(p.stbc,"STBC","STBC",A?"قدرة تنوع مهيأة؛ النتيجة غير مقاسة":"configured diversity capability; outcome unmeasured")+
        row(p.keep_weak,A?"سياسة العميل الضعيف مهيأة":"Weak-client policy configured",A?"سياسة العميل الضعيف مهيأة":"Weak-client policy configured",A?"لا تضمن عدم الفصل":"does not guarantee no disconnect"))+
      grp(A?"السعة":"Capacity",
        row(p.airtime,A?"عدالة وقت الهواء":"Airtime fairness",A?"عدالة وقت الهواء":"Airtime fairness",A?"مهيأة؛ زمن كل عميل غير مقاس":"configured; per-client airtime unmeasured")+
        row(H.num(p.maxassoc)>=200,A?"حد 200 عميل/تردد":"200-client configured limit",A?"حد 200 عميل/تردد":"200-client configured limit",A?"ليس سعة مختبرة":"not tested capacity")+
        row(p.m2u,"Multicast→Unicast","Multicast→Unicast",A?"مهيأ؛ أداء الفيديو غير مقاس":"configured; video performance unmeasured")+
        row(p.kv,"802.11k/v roaming","802.11k/v roaming",""))+
      grp(A?"مسار الحزم السريع":"Fast packet path",
        row(p.hw_offload,A?"تفريغ عتادي":"HW offload",A?"تفريغ عتادي":"HW offload",A?"مهيأ؛ مسار الحزم الفعلي غير مرصود":"configured; active packet path unobserved")+
        row(p.sw_offload,A?"تفريغ برمجي":"SW offload",A?"تفريغ برمجي":"SW offload","")+
        row(p.rps,A?"توزيع على النواتين":"RPS steering",A?"توزيع على النواتين":"RPS steering","")+
        row(p.fastopen,"TCP FastOpen","TCP FastOpen","")+
        row(H.num(p.dns_cache)>=4000,A?"كاش DNS كبير":"Big DNS cache",A?"كاش DNS كبير":"Big DNS cache","4000"));
    return H.card(t,body,on+"/"+tot,"bolt");
  }});
  // #64 — MIMO/AX/AC/N matrix: which acceleration each Wi-Fi generation gets, as a grid.
  PRO_FEATURES.push({key:"mimo_matrix",ar:"مصفوفة AX/AC/N",en:"AX/AC/N Matrix",cat:"Automation & UX",fn:function(d,H){
    var A=H.lang==="ar", p=(d&&d.perf)||{}, t=A?"مصفوفة AX/AC/N":"AX/AC/N Matrix";
    var ulState=String(p.ul_muru_state||"unknown"), ulActive=ulState==="armed"&&String(p.ul_muru_module)==="Y";
    var ulLabel=ulActive?"exp · MCU guarded":(ulState==="disabled"?"disabled · hang guard":(ulState==="reboot-required"?"fault · reboot required":"not armed"));
    var cols=[["WiFi 6 (AX)"],["WiFi 5 (AC)"],["WiFi 4 (N)"]];
    var rows=[
      [A?"سرعة قصوى":"Top rate","HE80 1024-QAM","VHT80 256-QAM","HT40 MCS15"],
      ["DL MU-MIMO",p.mu_bf_he?"cfg · unmeasured":"—",p.mu_bf_vht?"cfg · unmeasured":"—","—"],
      ["UL MU-MIMO",ulLabel,"—","—"],
      ["Beamforming",p.su_bf?"cfg":"—",p.mu_bf_vht||p.su_bf?"cfg":"—","—"],
      ["LDPC",p.ldpc?"✓":"—",p.ldpc?"✓":"—",p.ldpc?"✓":"—"],
      ["STBC",p.stbc?"✓":"—",p.stbc?"✓":"—",p.stbc?"✓":"—"],
      ["DL OFDMA","cap · unmeasured","—","—"],
      ["UL OFDMA",ulLabel,"—","—"],
      ["Background CAC","driver · runtime probe","—","—"],
      [A?"مدى بعيد":"Long range",p.dynack?"✓":"—",p.dynack?"✓":"—",p.dynack?"✓":"—"]];
    var h="<div class='table-wrap'><table style='font-size:11px'><thead><tr><th></th><th>"+cols[0][0]+"</th><th>"+cols[1][0]+"</th><th>"+cols[2][0]+"</th></tr></thead><tbody>";
    rows.forEach(function(r){ h+="<tr><td style='font-weight:700'>"+r[0]+"</td>"; for(var i=1;i<4;i++){ var v=r[i], ok=v.indexOf("✓")===0; h+="<td class='latin' style='color:"+(ok?"var(--excellent)":v==="—"?"var(--muted)":"var(--text)")+"'>"+v+"</td>"; } h+="</tr>"; });
    h+="</tbody></table></div><p class='muted' style='margin-top:6px;font-size:11px'>"+(A?"cfg = مهيّأ وليس قياساً هوائياً. مسار UL في MT7915 تجريبي: يفعّل حقول MCU الحقيقية مع حارس يعطله عند reset/hang، وإثباته يحتاج عدة عملاء متوافقين وعدادات UL‑TB PPDU. بُني Background CAC ويجب أن يعلنه الدرايفر بعد الإقلاع؛ أما تشغيل CAC فعلياً فيحتاج قناة DFS.":"cfg = configured, not over-air proof. The MT7915 UL path is experimental: real MCU fields are armed with a reset/hang guard, and proof requires multiple compatible clients plus UL-TB PPDU counters. Background CAC is built and must be advertised by the driver after boot; an actual CAC run requires a DFS channel.")+"</p>";
    return H.card(t,h,"2×2","signal");
  }});
  // ---- v88 RX/TX + AX/AC/N live cards (from existing dashapi2 fields) ----
  PRO_FEATURES.push({key:"band_rate_summary",ar:"لقطات PHY لكل باند",en:"PHY Snapshots per Band",cat:"Latency & Link Quality",fn:function(d,H){
    var w=Array.isArray(d.wifi)?d.wifi:[], title=H.lang==="ar"?"لقطات PHY لكل باند":"PHY Snapshots per Band";
    if(!w.length)return H.card(title,"<div class='empty'>—</div>",null,"net");
    var body=w.map(function(r){
      var cap=H.configuredPhyCeiling2x2(r), stations=Array.isArray(r.stations)?r.stations:[];
      var capText=cap?H.fmt(cap.mbps,cap.mbps<1000?1:0)+" Mbps":"—";
      var head="<div style='display:flex;justify-content:space-between;font-size:12px;gap:8px'><b>"+H.esc(r.band||"?")+" · "+H.esc(r.htmode||"?")+"</b><span class='latin'>2×2 cfg "+capText+"</span></div>";
      var rows=stations.map(function(s){var tx=H.parseStationRateDetail(s,"tx"),rx=H.parseStationRateDetail(s,"rx"),age=H.stationInactiveAge(s.inactive_ms);return "<div style='margin:5px 0;font-size:11px'><span class='latin'>"+H.esc(s.ip||s.mac||"?")+"</span><div class='latin' style='color:var(--muted)'>TX "+(H.finite(tx.rate)?H.fmt(tx.rate,tx.rate<100?1:0)+"M":"—")+" · RX "+(H.finite(rx.rate)?H.fmt(rx.rate,rx.rate<100?1:0)+"M":"—")+(age?" · inactive "+H.esc(age):"")+"</div></div>";}).join("");
      if(!rows)rows="<small class='muted'>"+(H.lang==="ar"?"لا عملاء متصلين":"No associated clients")+"</small>";
      return "<div style='margin:8px 0'>"+head+rows+"</div>";
    }).join("");
    body+="<small class='muted'>"+(H.lang==="ar"?"2×2 cfg قدرة PHY مهيّأة حسب وضع وعرض الراديو. TX/RX آخر لقطة فقط؛ ليست goodput أو اختبار سرعة.":"2×2 cfg is configured PHY capability for the radio mode and width. TX/RX are last snapshots only, not goodput or a speed test.")+"</small>";
    return H.card(title,body,w.length+"","net");
  }});
  PRO_FEATURES.push({key:"band_rxtx_ratio",ar:"حركة العملاء لكل نطاق",en:"Wi-Fi Client Traffic by Band",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',ifs=Array.isArray(d.interfaces)?d.interfaces:[];var b={"2.4G":{dl:0,ul:0},"5G":{dl:0,ul:0}};ifs.forEach(function(x){var n=x.name||"";var band=/^phy0-ap/.test(n)?"2.4G":/^phy1-ap/.test(n)?"5G":null;if(!band)return;/* At an AP edge, interface TX reaches clients (download) and RX comes from clients (upload). */b[band].dl+=H.num(x.tx_bps)||0;b[band].ul+=H.num(x.rx_bps)||0;});var body=["2.4G","5G"].map(function(k){var dl=b[k].dl,ul=b[k].ul,t=dl+ul||1;var pdl=dl/t*100;return "<div style='margin:8px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span><b>"+k+"</b></span><span class='latin'>↓ "+(a?'تنزيل ':'Download ')+H.bps(dl)+" · ↑ "+(a?'رفع ':'Upload ')+H.bps(ul)+"</span></div><div style='display:flex;height:16px;border-radius:5px;overflow:hidden'><div style='width:"+pdl.toFixed(1)+"%;background:var(--accent)'></div><div style='width:"+(100-pdl).toFixed(1)+"%;background:var(--primary)'></div></div></div>";}).join("");body+="<small class='muted'>"+(a?'تحويل حافة نقطة الوصول: TX تنزيل إلى العملاء، وRX رفع منهم. الواجهات لا تُجمع كإجمالي عالمي.':'AP-edge conversion: interface TX is client download and RX is client upload. Interfaces are not summed as a global total.')+"</small>";return H.card(a?'حركة العملاء لكل نطاق':'Wi-Fi Client Traffic by Band',body,null,"net");}});
  PRO_FEATURES.push({key:"phy_std_badge",ar:"معيار كل راديو AX/AC/N",en:"Per-Radio Standard",cat:"Automation & UX",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];if(!w.length)return H.card(H.lang==="ar"?"المعيار":"Standard","<div class='empty'>—</div>",null,"signal");var body=w.map(function(r){var h=String(r.htmode||"");var std=/HE/.test(h)?["Wi-Fi 6 (AX)","var(--excellent)"]:/VHT/.test(h)?["Wi-Fi 5 (AC)","var(--good)"]:/HT/.test(h)?["Wi-Fi 4 (N)","var(--mid)"]:["Legacy","var(--weak)"];return "<div style='display:flex;justify-content:space-between;align-items:center;margin:7px 0'><span>"+H.esc(r.band||"?")+" · ch "+H.esc(String(r.channel||"?"))+" · "+H.esc(h)+"</span><span style='padding:2px 10px;border-radius:10px;font-size:12px;font-weight:700;color:#fff;background:"+std[1]+"'>"+std[0]+"</span></div>";}).join("");return H.card(H.lang==="ar"?"معيار كل راديو (AX/AC/N)":"Per-Radio Standard (AX/AC/N)",body,w.length+"","signal");}});
  PRO_FEATURES.push({key:"phy_rate_hist",ar:"توزيع آخر لقطات PHY",en:"Last PHY Snapshot Histogram",cat:"Clients & Devices",fn:function(d,H){var snapshots=H.stationRateSnapshots(d,"tx"),edges=[[0,100],[100,300],[300,600],[600,900],[900,1300]],lab=["<100","100-300","300-600","600-900","900-1300"],buck=[0,0,0,0,0],tot=0;snapshots.forEach(function(x){var t=x.info.rate;if(!H.finite(t))return;tot++;for(var i=0;i<edges.length;i++){if(t>=edges[i][0]&&t<edges[i][1]){buck[i]++;break;}}});var title=H.lang==="ar"?"توزيع آخر لقطات PHY":"Last PHY Snapshot Histogram";if(!tot)return H.card(title,"<div class='empty'>—</div>",null,"device");var mx=Math.max.apply(null,buck)||1;var body=lab.map(function(l,i){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span class='latin'>"+l+" Mbps</span><span>"+buck[i]+"</span></div>"+H.bar(buck[i],mx,"var(--accent)")+"</div>";}).join("");body+="<small class='muted'>"+(H.lang==="ar"?"لقطات آخر إطار؛ لا تمثل throughput.":"Last-frame snapshots; they do not represent throughput.")+"</small>";return H.card(title,body,tot+"","device");}});
  // ---- v91 feature pack: 72 agent-generated insight cards (validated: syntax + runtime smoke ar/en x full/empty/partial) ----
  PRO_FEATURES.push({key:"x_rf_channel_score",ar:"تقدير لقطة حمل القناة",en:"Channel-load Snapshot Estimate",cat:"RF & Airtime",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],title=a?'تقدير لقطة حمل القناة':'Channel-load Snapshot Estimate';if(!w.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');var rows='',known=0;for(var i=0;i<w.length;i++){var r=w[i],sv=r.survey||{},busy=H.num(sv.busy_pct),noise=H.num(r.noise_dbm);if(!H.finite(noise))noise=H.num(sv.noise_dbm);if(!H.finite(busy)&&!H.finite(noise))continue;known++;busy=H.finite(busy)?H.clamp(busy,0,100):null;var penalties=[],weights=[];if(busy!=null){penalties.push(busy);weights.push(0.6);}if(H.finite(noise)){penalties.push(H.clamp((noise+95)/35*100,0,100));weights.push(0.4);}var weighted=0,weight=0;for(var k=0;k<penalties.length;k++){weighted+=penalties[k]*weights[k];weight+=weights[k];}var estimate=H.clamp(100-weighted/weight,0,100),col=estimate>75?'var(--excellent)':estimate>55?'var(--good)':estimate>35?'var(--mid)':'var(--weak)',sub=(busy==null?'—':H.fmt(busy,0)+'% busy')+' · '+(H.finite(noise)?H.fmt(noise,0)+' dBm':'—');rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(r.band||'?')+' · ch '+H.esc(String(r.channel||'?'))+"</span><span style='color:"+col+"'>"+H.fmt(estimate,0)+"</span></div>"+H.bar(estimate,100,col)+"<div style='font-size:11px;color:var(--muted)'>"+sub+"</div></div>";}if(!known)rows="<div style='color:var(--muted)'>"+(a?'لا مدخلات متاحة':'No available inputs')+"</div>";rows+="<small class='muted'>"+(a?'تقدير من لقطة busy/noise المتاحة فقط، وليس اختبار قناة أو تداخل.':'Estimate from available busy/noise snapshots only, not a channel or interference test.')+"</small>";return H.card(title,rows,null,'signal');}});
  PRO_FEATURES.push({
    key:"x_rf_bss_color", ar:"إعادة الاستخدام المكاني", en:"Spatial Reuse (BSS Color)", cat:"RF & Airtime",
    fn:function(d,H) {
      var w=Array.isArray(d.wifi)?d.wifi:[];
      var t=H.lang==="ar"?"إعادة الاستخدام المكاني":"Spatial Reuse (BSS Color)";
      if(!w.length) return H.card(t,"<div style='color:var(--muted)'>—</div>",null,"wifi");
      var perf=(d&&d.perf)||{};
      var configured=perf.bss_color===true;
      var rows="", eligible=0;
      for(var i=0;i<w.length;i++) {
        var r=w[i], hm=String(r.htmode||"").toUpperCase();
        var he=hm.indexOf("HE")>-1||hm.indexOf("EHT")>-1;
        var ready=he&&configured;
        if(ready) eligible++;
        var col=ready?"var(--excellent)":he?"var(--mid)":"var(--muted)";
        var txt=ready
          ? (H.lang==="ar"?"مُهيّأ · الاستخدام الهوائي غير مقاس":"configured · airtime use not measured")
          : he
            ? (H.lang==="ar"?"HE متاح · الإعداد غير مؤكد":"HE capable · setting not confirmed")
            : (H.lang==="ar"?"غير متاح لهذا المعيار":"not available for this standard");
        rows+="<div style='display:flex;justify-content:space-between;gap:8px;margin:6px 0;font-size:12px'><span>"+
          H.esc(r.band||"?")+" · "+H.esc(hm||"?")+"</span><span style='color:"+col+"'>"+txt+"</span></div>";
      }
      return H.card(t,rows,eligible+"/"+w.length+" configured","wifi");
    }
  });
  PRO_FEATURES.push({key:"x_rf_nss_estimate",ar:"NSS المبلّغ في آخر PHY",en:"Reported NSS in Last PHY",cat:"RF & Airtime",fn:function(d,H){
    var title=H.lang==='ar'?'NSS المبلّغ في آخر PHY':'Reported NSS in Last PHY',counts={1:0,2:0,3:0,4:0},total=0,unknown=0;
    H.stationRateSnapshots(d,"tx").forEach(function(x){var n=x.info.nss;if(H.finite(n)&&n>=1&&n<=4){counts[n]++;total++;}else unknown++;});
    if(!total&&!unknown)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');
    var rows='';for(var k=1;k<=4;k++){var c=counts[k],pct=total?c/total*100:0;rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+(H.lang==='ar'?k+'×NSS':k+' stream')+"</span><span>"+c+"</span></div>"+H.bar(pct,100,k>=2?'var(--excellent)':'var(--mid)')+"</div>";}
    if(unknown)rows+="<small class='muted'>"+(H.lang==='ar'?'لم يبلّغ الدرايفر NSS: ':'Driver did not report NSS: ')+unknown+"</small>";
    rows+="<small class='muted' style='display:block'>"+(H.lang==='ar'?'من HE/VHT-NSS الفعلي أو ترميز HT-MCS القياسي؛ لا تخمين من Mbps.':'From explicit HE/VHT-NSS or the standard HT-MCS encoding; never guessed from Mbps.')+"</small>";
    return H.card(title,rows,String(total),'net');
  }});
  PRO_FEATURES.push({key:"x_rf_snr_mcs",ar:"MCS المبلّغ في آخر لقطة PHY",en:"Reported MCS in Last PHY Snapshot",cat:"RF & Airtime",fn:function(d,H){var title=H.lang==='ar'?'MCS المبلّغ في آخر لقطة PHY':'Reported MCS in Last PHY Snapshot',arr=H.stationRateSnapshots(d,'tx').filter(function(x){return H.finite(x.info.mcs);});if(!arr.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');arr.sort(function(a,b){return b.info.mcs-a.info.mcs;});var rows='';arr.slice(0,6).forEach(function(x){var i=x.info,s=x.station,age=H.stationInactiveAge(s.inactive_ms),parts=[i.family||'?', 'MCS '+i.mcs];if(H.finite(i.nss))parts.push(i.nss+'SS');if(age)parts.push('inactive '+age);rows+="<div style='display:flex;justify-content:space-between;gap:8px;margin:5px 0;font-size:12px'><span>"+H.esc(s.ip||s.mac||'?')+"</span><span class='latin' style='color:var(--accent)'>"+H.esc(parts.join(' · '))+"</span></div>";});rows+="<small class='muted'>"+(H.lang==='ar'?'من تفاصيل الدرايفر الفعلية؛ لا يُستنتج MCS من SNR.':'From actual driver details; MCS is never inferred from SNR.')+"</small>";return H.card(title,rows,String(arr.length),'signal');}});
  PRO_FEATURES.push({key:"x_rf_spectral_eff",ar:"لقطة PHY مقابل عرض القناة",en:"Last PHY Snapshot per Channel Width",cat:"RF & Airtime",fn:function(d,H){var title=H.lang==='ar'?'لقطة PHY مقابل عرض القناة':'Last PHY Snapshot per Channel Width',w=Array.isArray(d.wifi)?d.wifi:[],rows='',known=0;for(var i=0;i<w.length;i++){var snaps=[];(w[i].stations||[]).forEach(function(s){var x=H.parseStationRateDetail(s,'tx');if(H.finite(x.rate))snaps.push(x.rate);});if(!snaps.length)continue;known++;var sum=snaps.reduce(function(a,b){return a+b;},0),avg=sum/snaps.length,width=H.radioWidthMHz(w[i]);rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;gap:8px;font-size:12px'><span>"+H.esc(w[i].band||'?')+' · '+width+"MHz</span><b class='latin'>"+H.fmt(avg,1)+" Mbps</b></div><div style='font-size:11px;color:var(--muted)'>"+snaps.length+(H.lang==='ar'?' لقطة عميل':' client snapshots')+"</div></div>";}if(!known)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');rows+="<small class='muted'>"+(H.lang==='ar'?'متوسط آخر لقطات PHY للتشخيص فقط؛ ليس كفاءة طيفية ولا throughput.':'Average last PHY snapshots for diagnostics only; not spectral efficiency or throughput.')+"</small>";return H.card(title,rows,String(known),'signal');}});
  PRO_FEATURES.push({key:"x_rf_airtime_est",ar:"قياس وقت البث لكل عميل",en:"Per-Client Airtime Telemetry",cat:"RF & Airtime",fn:function(d,H){var title=H.lang==='ar'?'قياس وقت البث لكل عميل':'Per-Client Airtime Telemetry';var note=H.lang==='ar'?'عدادات airtime لكل عميل غير متاحة في هذه اللقطة. لا يمكن اشتقاق الاستهلاك من معدل PHY الأخير.':'Per-client airtime counters are unavailable in this snapshot. Consumption cannot be derived from the last PHY rate.';return H.card(title,"<div class='empty'>"+note+"</div>",H.lang==='ar'?'غير مقاس':'not measured','signal');}});
  PRO_FEATURES.push({key:"x_rf_spectrum_congestion",ar:"ازدحام الطيف",en:"Spectrum Congestion",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'ازدحام الطيف':'Spectrum Congestion';var vals=[];for(var i=0;i<w.length;i++){var sv=w[i].survey||{};var b=H.num(sv.busy_pct);if(H.finite(b)){vals.push(H.clamp(b,0,100));}}if(!vals.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');var sum=0;for(var j=0;j<vals.length;j++){sum+=vals[j];}var avg=sum/vals.length;var col=avg<30?'var(--excellent)':avg<55?'var(--good)':avg<75?'var(--mid)':'var(--weak)';var txt=avg<30?(H.lang==='ar'?'نظيف':'clear'):avg<55?(H.lang==='ar'?'معتدل':'moderate'):avg<75?(H.lang==='ar'?'مزدحم':'busy'):(H.lang==='ar'?'مكتظ':'congested');var body=H.gauge(H.lang==='ar'?'متوسط الانشغال':'avg busy',H.fmt(avg,0)+'%',txt,vals.length+(H.lang==='ar'?' راديو':' radios'),avg,col,'signal');return H.card(t,body,txt,'signal');}});
  PRO_FEATURES.push({key:"x_rf_phy_ceiling",ar:"قدرة PHY المهيّأة",en:"Configured PHY Capability",cat:"RF & Airtime",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[],title=H.lang==='ar'?'قدرة PHY المهيّأة':'Configured PHY Capability',rows='',any=0;for(var i=0;i<w.length;i++){var cap=H.configuredPhyCeiling2x2(w[i]);if(!cap)continue;any++;rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px;gap:8px'><span>"+H.esc(w[i].band||'?')+' · '+H.esc(cap.mode)+"</span><b class='latin' style='color:var(--accent)'>"+H.fmt(cap.mbps,cap.mbps<1000?1:0)+" Mbps</b></div><small class='muted latin'>"+cap.family+' · '+cap.width+"MHz · 2×2</small></div>";}if(!any)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');rows+="<small class='muted'>"+(H.lang==='ar'?'قدرة نظرية مهيّأة حسب الوضع والعرض؛ ليست goodput ولا نتيجة عميل.':'Configured theoretical capability for mode and width; not goodput or a client result.')+"</small>";return H.card(title,rows,any+'','net');}});
  PRO_FEATURES.push({key:"x_cl_rssi_hist",ar:"توزيع الإشارة RSSI",en:"RSSI Distribution",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var sig=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(H.finite(v))sig.push(v);}}var T=H.lang==='ar'?'توزيع الإشارة RSSI':'RSSI Distribution';if(!sig.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');var b=[{l:H.lang==='ar'?'ممتاز ≥-50':'Excellent ≥-50',c:'var(--excellent)',n:0},{l:H.lang==='ar'?'جيد -50..-60':'Good -50..-60',c:'var(--good)',n:0},{l:H.lang==='ar'?'متوسط -60..-70':'Fair -60..-70',c:'var(--mid)',n:0},{l:H.lang==='ar'?'ضعيف -70..-80':'Weak -70..-80',c:'var(--weak)',n:0},{l:H.lang==='ar'?'حرج <-80':'Edge <-80',c:'var(--weak)',n:0}];for(var k=0;k<sig.length;k++){var s=sig[k];if(s>=-50)b[0].n++;else if(s>=-60)b[1].n++;else if(s>=-70)b[2].n++;else if(s>=-80)b[3].n++;else b[4].n++;}var rows='';for(var m=0;m<b.length;m++){rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+b[m].l+"</span><span style='color:"+b[m].c+"'>"+b[m].n+"</span></div>"+H.bar(b[m].n,sig.length,b[m].c)+"</div>";}return H.card(T,rows,String(sig.length),'signal');}});
  PRO_FEATURES.push({key:"x_cl_link_eff_watch",ar:"لقطة PHY وتقدير النقل",en:"PHY Snapshot & Driver Estimate",cat:"Clients & Devices",fn:function(d,H){var title=H.lang==='ar'?'لقطة PHY وتقدير النقل':'PHY Snapshot & Driver Estimate',arr=H.stationRateSnapshots(d,'tx');if(!arr.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='';arr.slice(0,6).forEach(function(x){var est=H.num(x.station.expected_mbps),age=H.stationInactiveAge(x.station.inactive_ms);rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;gap:8px;font-size:12px'><span>"+H.esc(x.station.ip||x.station.mac||'?')+"</span><b class='latin'>PHY "+H.fmt(x.info.rate,1)+" Mbps</b></div><div style='font-size:11px;color:var(--muted)'>"+(H.lang==='ar'?'تقدير الدرايفر: ':'Driver estimate: ')+(H.finite(est)?H.fmt(est,1)+' Mbps':'—')+(age?' · inactive '+H.esc(age):'')+"</div></div>";});rows+="<small class='muted'>"+(H.lang==='ar'?'مقياسان منفصلان؛ لا تُحسب نسبة كفاءة بينهما.':'Separate telemetry fields; no efficiency ratio is calculated between them.')+"</small>";return H.card(title,rows,String(arr.length),'net');}});
  PRO_FEATURES.push({key:"x_cl_phy_class",ar:"فئة PHY المبلّغ عنها",en:"Reported PHY Class Split",cat:"Clients & Devices",fn:function(d,H){var counts={EHT:0,HE:0,VHT:0,HT:0,unknown:0},arr=H.stationRateSnapshots(d,'tx');arr.forEach(function(x){var f=String(x.info.family||'').toUpperCase();if(Object.prototype.hasOwnProperty.call(counts,f))counts[f]++;else counts.unknown++;});var total=arr.length,title=H.lang==='ar'?'فئة PHY المبلّغ عنها':'Reported PHY Class Split';if(!total)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'wifi');var bands=[['EHT / Wi-Fi 7','EHT','var(--excellent)'],['HE / Wi-Fi 6','HE','var(--excellent)'],['VHT / Wi-Fi 5','VHT','var(--good)'],['HT / Wi-Fi 4','HT','var(--mid)'],[H.lang==='ar'?'غير مبلّغ':'Unknown','unknown','var(--muted)']],rows='';bands.forEach(function(b){var n=counts[b[1]];if(!n)return;rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+b[0]+"</span><span style='color:"+b[2]+"'>"+n+"</span></div>"+H.bar(n,total,b[2])+"</div>";});rows+="<small class='muted'>"+(H.lang==='ar'?'من تفاصيل معدل العميل التي يبلغها الدرايفر، وليس من htmode للراديو.':'From each client rate detail reported by the driver, not the radio htmode.')+"</small>";return H.card(title,rows,String(total),'wifi');}});
  PRO_FEATURES.push({key:"x_cl_nss_estimate",ar:"NSS المبلّغ لكل عميل",en:"Reported NSS per Client",cat:"Clients & Devices",fn:function(d,H){
    var list=H.stationRateSnapshots(d,"tx"),title=H.lang==='ar'?'NSS المبلّغ لكل عميل':'Reported NSS per Client';
    if(!list.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'wifi');
    var known=0,rows=list.slice(0,8).map(function(x){var i=x.info,age=H.stationInactiveAge(x.station.inactive_ms),reported=H.finite(i.nss);if(reported)known++;var meta=[];if(i.family)meta.push(i.family);if(H.finite(i.mcs))meta.push('MCS '+i.mcs);if(age)meta.push((H.lang==='ar'?'خمول ':'inactive ')+age);return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px;gap:8px'><span class='latin'>"+H.esc(x.station.ip||x.station.mac||'?')+"</span><b class='latin' style='color:"+(reported?'var(--accent)':'var(--muted)')+"'>"+(reported?i.nss+'SS':'NSS —')+"</b></div><small class='muted latin'>"+H.esc(meta.join(' · '))+"</small></div>";}).join('');
    rows+="<small class='muted'>"+(H.lang==='ar'?'القيمة من تفاصيل الدرايفر، وليست استنتاجاً من معدل Mbps.':'Value comes from driver rate details, not an inference from Mbps.')+"</small>";
    return H.card(title,rows,known+'/'+list.length,'wifi');
  }});
  PRO_FEATURES.push({key:"x_cl_roam_ready",ar:"مرشحو RSSI للتجوال",en:"RSSI Roaming Candidates",cat:"Clients & Devices",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],cand=[],tot=0;for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(!H.finite(v))continue;tot++;if(v<=-67&&v>=-82)cand.push({s:ss[j],v:v});}}var T=a?'مرشحو RSSI للتجوال':'RSSI Roaming Candidates';if(!tot)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');cand.sort(function(x,y){return x.v-y.v;});var rows="<div style='font-size:12px;color:var(--muted);margin-bottom:6px'>"+cand.length+" / "+tot+" "+(a?'ضمن عتبة RSSI':'within the RSSI threshold')+"</div>";if(!cand.length)rows+="<div style='color:var(--muted);font-size:12px'>"+(a?'لا توجد لقطة ضمن العتبة الحالية':'No snapshot within the current threshold')+"</div>";for(var m=0;m<Math.min(4,cand.length);m++){var q=H.quality('rssi',cand[m].v);rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:4px 0'><span>"+H.esc(cand[m].s.ip||cand[m].s.mac||'?')+"</span><span style='color:"+q.color+"'>"+H.fmt(cand[m].v,0)+" dBm</span></div>";}rows+="<small class='muted'>"+(a?'قائمة من RSSI اللحظي فقط؛ لا تضمن أن العميل سيتجول أو سيبقى متصلاً.':'Instantaneous RSSI list only; it does not guarantee that a client will roam or remain connected.')+"</small>";return H.card(T,rows,String(cand.length),'signal');}});
  PRO_FEATURES.push({key:"x_cl_edge_clients",ar:"أقل قراءات RSSI",en:"Lowest-RSSI Observations",cat:"Clients & Devices",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],arr=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(H.finite(v))arr.push({s:ss[j],v:v});}}var T=a?'أقل قراءات RSSI':'Lowest-RSSI Observations';if(!arr.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'device');arr.sort(function(x,y){return x.v-y.v;});var rows='';for(var m=0;m<Math.min(4,arr.length);m++){var e=arr[m],q=H.quality('rssi',e.v),dm=H.num(H.distanceM(e.v)),ds=H.finite(dm)?'≈ '+H.fmt(dm,0)+' m':'';rows+="<div style='margin:5px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(e.s.ip||e.s.mac||'?')+"</span><span style='color:"+q.color+"'>"+H.fmt(e.v,0)+" dBm</span></div><div style='font-size:11px;color:var(--muted)'>"+ds+"</div></div>";}rows+="<small class='muted'>"+(a?'ترتيب RSSI لحظي؛ المسافة تقريب تقريبي من RSSI وحده، ولا توجد ضمانة اتصال.':'Instantaneous RSSI ranking; distance is an RSSI-only rough estimate and connectivity is not guaranteed.')+"</small>";return H.card(T,rows,String(arr.length),'device');}});
  PRO_FEATURES.push({key:"x_cl_signal_spread",ar:"تشتت الإشارة",en:"Signal Spread",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var sig=[];for(var i=0;i<w.length;i++){var ss=Array.isArray(w[i].stations)?w[i].stations:[];for(var j=0;j<ss.length;j++){var v=H.num(ss[j].signal_dbm);if(H.finite(v))sig.push(v);}}var T=H.lang==='ar'?'تشتت الإشارة':'Signal Spread';if(!sig.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');var mn=sig[0],mx=sig[0],sum=0;for(var k=0;k<sig.length;k++){var s=sig[k];if(s<mn)mn=s;if(s>mx)mx=s;sum+=s;}var avg=sum/sig.length;var rng=mx-mn;function box(lbl,val,col){return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+val+"</b></div>";}var body="<div class='grid two'>"+box(H.lang==='ar'?'الأقوى':'Best',H.fmt(mx,0)+' dBm','var(--excellent)')+box(H.lang==='ar'?'الأضعف':'Worst',H.fmt(mn,0)+' dBm','var(--weak)')+box(H.lang==='ar'?'المتوسط':'Avg',H.fmt(avg,0)+' dBm','var(--good)')+box(H.lang==='ar'?'المدى':'Range',H.fmt(rng,0)+' dB','var(--mid)')+"</div>";return H.card(T,body,String(sig.length),'signal');}});
  PRO_FEATURES.push({key:"x_cl_snr_headroom",ar:"هامش SNR للعملاء",en:"Client SNR Headroom",cat:"Clients & Devices",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var arr=[];for(var i=0;i<w.length;i++){var r=w[i];var nf=H.num(r.noise_dbm);if(!H.finite(nf)&&r.survey)nf=H.num(r.survey.noise_dbm);var ss=Array.isArray(r.stations)?r.stations:[];for(var j=0;j<ss.length;j++){var s=ss[j];var snr=H.num(s.snr);if(!H.finite(snr)){var sg=H.num(s.signal_dbm);if(H.finite(sg)&&H.finite(nf))snr=sg-nf;}if(H.finite(snr))arr.push({s:s,snr:snr});}}var T=H.lang==='ar'?'هامش SNR للعملاء':'Client SNR Headroom';if(!arr.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'signal');arr.sort(function(a,b){return a.snr-b.snr;});var lim=Math.min(5,arr.length);var rows='';for(var m=0;m<lim;m++){var e=arr[m];var col=e.snr>=30?'var(--excellent)':e.snr>=20?'var(--good)':e.snr>=12?'var(--mid)':'var(--weak)';rows+="<div style='margin:5px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(e.s.ip||e.s.mac||'?')+"</span><span style='color:"+col+"'>"+H.fmt(e.snr,0)+" dB</span></div>"+H.bar(H.clamp(e.snr,0,40),40,col)+"</div>";}return H.card(T,rows,String(arr.length),'signal');}});
  PRO_FEATURES.push({key:"x_tr_iface_throughput",ar:"نشاط كل واجهة",en:"Per-interface Activity",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',ifs=Array.isArray(d.interfaces)?d.interfaces:[];var title=a?'نشاط كل واجهة':'Per-interface Activity';if(!ifs.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var max=1;for(var i=0;i<ifs.length;i++){var rx=H.num(ifs[i].rx_bps),tx=H.num(ifs[i].tx_bps);rx=H.finite(rx)?rx:0;tx=H.finite(tx)?tx:0;if(rx>max)max=rx;if(tx>max)max=tx;}var rows='';for(var j=0;j<ifs.length;j++){var f=ifs[j];var r=H.num(f.rx_bps);r=H.finite(r)?r:0;var t=H.num(f.tx_bps);t=H.finite(t)?t:0;rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(f.name||'?')+"</span><span style='color:var(--muted)'>Interface RX "+H.bps(r)+" · Interface TX "+H.bps(t)+"</span></div>"+H.bar(r,max,'var(--good)')+H.bar(t,max,'var(--accent)')+"</div>";}rows+="<small class='muted'>"+(a?'اتجاهات عداد الواجهة الخام؛ ليست تنزيل/رفع للعميل.':'Raw interface-counter directions; these are not client download/upload.')+"</small>";return H.card(title,rows,String(ifs.length),'net');}});
  PRO_FEATURES.push({key:"x_tr_top_talkers",ar:"أكثر العملاء استهلاكاً",en:"Top Talkers",cat:"Traffic & Bandwidth",fn:function(d,H){var title=H.lang==='ar'?'أكثر العملاء استهلاكاً':'Top Talkers';var rows=H.stationTrafficRows(d).filter(function(r){return r.rateSource==='byte-counter-delta'&&r.totalRate>0;});if(!rows.length)return H.card(title,"<div class='empty'>"+(H.lang==='ar'?'لا توجد حركة مقاسة حالياً من فروق عدادات البايت':'No current traffic measured from byte-counter deltas')+"</div>",null,'device');rows.sort(function(a,b){return b.totalRate-a.totalRate;});var max=rows[0].totalRate||1,out='';for(var i=0;i<rows.length&&i<5;i++){var r=rows[i];out+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px;gap:8px'><span>"+H.esc(r.label)+"</span><b class='latin' style='color:var(--accent)'>"+H.bps(r.totalRate)+"</b></div>"+H.bar(r.totalRate,max,'var(--accent)')+"<small class='muted latin'>↓ "+H.bps(r.down)+" · ↑ "+H.bps(r.up)+"</small></div>";}out+="<small class='muted'>"+(H.lang==='ar'?'من فروق عدادات البايت فقط؛ لا تُستخدم معدلات PHY.':'Byte-counter deltas only; PHY rates are never used.')+"</small>";return H.card(title,out,String(rows.length),'device');}});
  PRO_FEATURES.push({key:"x_tr_burst_watch",ar:"لقطة عدادات الواجهات",en:"Interface Counter Observation",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',ifs=Array.isArray(d.interfaces)?d.interfaces:[],title=a?'لقطة عدادات الواجهات':'Interface Counter Observation';if(!ifs.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');var rows='';for(var i=0;i<ifs.length;i++){var f=ifs[i],rx=H.num(f.rx_bps),tx=H.num(f.tx_bps),rb=H.num(f.rx_bytes),tb=H.num(f.tx_bytes);rx=H.finite(rx)?rx:0;tx=H.finite(tx)?tx:0;rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(f.name||'?')+"</span><span class='latin'>RX "+H.bps(rx)+" · TX "+H.bps(tx)+"</span></div><div style='font-size:11px;color:var(--muted)'>RX "+(H.finite(rb)?H.bytes(rb):'—')+" · TX "+(H.finite(tb)?H.bytes(tb):'—')+"</div></div>";}rows+="<small class='muted'>"+(a?'قيم خام مستقلة منذ إعادة ضبط كل واجهة؛ لا يُستنتج منها كشف اندفاعات.':'Independent raw values since each interface reset; no burst verdict is inferred.')+"</small>";return H.card(title,rows,null,'signal');}});
  PRO_FEATURES.push({key:"x_tr_symmetry",ar:"توازن التنزيل والرفع",en:"Download / Upload Balance",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',t=d.traffic||{},download=H.num(t.rx_bps),upload=H.num(t.tx_bps),title=a?'توازن التنزيل والرفع':'Download / Upload Balance';if(!H.finite(download)&&!H.finite(upload))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');download=H.finite(download)?download:0;upload=H.finite(upload)?upload:0;var tot=download+upload,dp=tot>0?download/tot*100:0,up=tot>0?upload/tot*100:0,ratio=upload>0?download/upload:null;var body="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px'><span style='color:var(--good)'>↓ "+(a?'تنزيل ':'Download ')+H.bps(download)+"</span><span style='color:var(--accent)'>↑ "+(a?'رفع ':'Upload ')+H.bps(upload)+"</span></div>"+H.bar(dp,100,'var(--good)')+"<div style='display:flex;justify-content:space-between;font-size:11px;color:var(--muted);margin-top:4px'><span>"+(a?'تنزيل ':'Download ')+H.fmt(dp,0)+"%</span><span>"+(a?'رفع ':'Upload ')+H.fmt(up,0)+"%</span></div>";return H.card(title,body,ratio!=null?H.fmt(ratio,1)+':1':null,'net');}});
  PRO_FEATURES.push({key:"x_tr_pps_estimate",ar:"الحزم في الثانية (تقديري)",en:"Client Packets/sec (estimate)",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',t=d.traffic||{},download=H.num(t.rx_bps),upload=H.num(t.tx_bps),title=a?'الحزم في الثانية (تقديري)':'Client Packets/sec (estimate)';if(!H.finite(download)&&!H.finite(upload))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');download=H.finite(download)?download:0;upload=H.finite(upload)?upload:0;var AVG=1000,downloadPps=download/AVG,uploadPps=upload/AVG,tot=downloadPps+uploadPps;function fmtp(n){if(n>=1000000)return H.fmt(n/1000000,2)+'M';if(n>=1000)return H.fmt(n/1000,1)+'k';return H.fmt(n,0);}var body="<div style='font-size:22px;font-weight:600;color:var(--accent)'>"+fmtp(tot)+" <small style='font-size:12px;color:var(--muted)'>pps</small></div><div style='display:flex;justify-content:space-between;font-size:12px;margin-top:6px'><span style='color:var(--good)'>↓ "+(a?'تنزيل ':'Download ')+fmtp(downloadPps)+"</span><span style='color:var(--accent)'>↑ "+(a?'رفع ':'Upload ')+fmtp(uploadPps)+"</span></div><small class='muted'>"+(a?'تقدير من بايت/ثانية بافتراض 1000 بايت لكل إطار؛ ليس عداد حزم.':'Estimated from bytes/second at 1000 B per frame; not a packet counter.')+"</small>";return H.card(title,body,null,'cpu');}});
  PRO_FEATURES.push({key:"x_tr_iface_share",ar:"نشاط الواجهات المستقل",en:"Independent Per-interface Activity",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',ifs=Array.isArray(d.interfaces)?d.interfaces:[],title=a?'نشاط الواجهات المستقل':'Independent Per-interface Activity';if(!ifs.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var arr=[],max=1;for(var i=0;i<ifs.length;i++){var f=ifs[i],rx=H.num(f.rx_bps),tx=H.num(f.tx_bps);rx=H.finite(rx)?rx:0;tx=H.finite(tx)?tx:0;var v=rx+tx;arr.push({name:f.name||'?',rx:rx,tx:tx,v:v});if(v>max)max=v;}arr.sort(function(x,y){return y.v-x.v;});var cols=['var(--accent)','var(--good)','var(--mid)','var(--primary)','var(--weak)'],rows='';for(var j=0;j<arr.length;j++){var e=arr[j],col=cols[j%cols.length];rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(e.name)+"</span><span class='latin' style='color:"+col+"'>"+H.bps(e.v)+"</span></div>"+H.bar(e.v,max,col)+"<div style='font-size:10px;color:var(--muted)'>Interface RX "+H.bps(e.rx)+" · Interface TX "+H.bps(e.tx)+"</div></div>";}rows+="<small class='muted'>"+(a?'كل واجهة مستقلة وشريطها نسبة إلى أنشط واجهة فقط. قد تتداخل الجسور والمنافذ ونقاط الوصول؛ لا جمع ولا إزالة تكرار.':'Each interface is independent; bars are relative only to the busiest interface. Bridges, ports and APs may overlap; no sum or deduplication is performed.')+"</small>";return H.card(title,rows,null,'net');}});
  PRO_FEATURES.push({key:"x_tr_data_volume",ar:"لقطة عدادات كل واجهة",en:"Per-interface Counter Snapshot",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',ifs=Array.isArray(d.interfaces)?d.interfaces:[],title=a?'لقطة عدادات كل واجهة':'Per-interface Counter Snapshot';if(!ifs.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'storage');var arr=[],max=1;for(var i=0;i<ifs.length;i++){var f=ifs[i],rb=H.num(f.rx_bytes),tb=H.num(f.tx_bytes);rb=H.finite(rb)?rb:0;tb=H.finite(tb)?tb:0;var total=rb+tb;arr.push({name:f.name||'?',rb:rb,tb:tb,total:total});if(total>max)max=total;}arr.sort(function(x,y){return y.total-x.total;});var rows='';for(var j=0;j<arr.length;j++){var e=arr[j];rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(e.name)+"</span><span class='latin' style='color:var(--muted)'>Interface RX "+H.bytes(e.rb)+" · Interface TX "+H.bytes(e.tb)+"</span></div>"+H.bar(e.total,max,'var(--primary)')+"</div>";}rows+="<small class='muted'>"+(a?'عدادات خام منذ إعادة ضبط كل واجهة. قد تتداخل طبقات الجسر/المنفذ/AP، لذلك لا يوجد إجمالي جامع.':'Raw counters since each interface reset. Bridge/port/AP layers may overlap, so no grand total is shown.')+"</small>";return H.card(title,rows,null,'storage');}});
  PRO_FEATURES.push({key:"x_tr_link_saturation",ar:"استخدام منفذ الرفع الموثق",en:"Verified Uplink Utilization",cat:"Traffic & Bandwidth",fn:function(d,H){var a=H.lang==='ar',t=d.traffic||{},download=H.num(t.rx_bps),upload=H.num(t.tx_bps),title=a?'استخدام منفذ الرفع الموثق':'Verified Uplink Utilization';if(!H.finite(download)&&!H.finite(upload))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');download=H.finite(download)?download:0;upload=H.finite(upload)?upload:0;var cap=H.verifiedUplinkCapacity(d),body="<div class='grid two'><div class='traffic-box'><span>↓ "+(a?'تنزيل':'Download')+"</span><b class='latin'>"+H.bps(download)+"</b></div><div class='traffic-box'><span>↑ "+(a?'رفع':'Upload')+"</span><b class='latin'>"+H.bps(upload)+"</b></div></div>";if(!cap){body+="<small class='muted'>"+(a?'حركة مرصودة فقط. لا نسبة ولا حكم من دون طوبولوجيا مكتملة، ومنفذ uplink مطابق ومتصل، وسرعته الموثقة.':'Observed traffic only. No percentage or verdict without complete topology plus a matching, connected uplink with documented speed.')+"</small>";return H.card(title,body,null,'net');}var dp=H.clamp(download/cap.bytesPerSecond*100,0,100),up=H.clamp(upload/cap.bytesPerSecond*100,0,100);body+="<div style='margin-top:8px'><div style='display:flex;justify-content:space-between;font-size:11px'><span>↓ "+(a?'تنزيل':'Download')+"</span><span>"+H.fmt(dp,1)+"%</span></div>"+H.bar(dp,100,'var(--accent)')+"<div style='display:flex;justify-content:space-between;font-size:11px;margin-top:4px'><span>↑ "+(a?'رفع':'Upload')+"</span><span>"+H.fmt(up,1)+"%</span></div>"+H.bar(up,100,'var(--primary)')+"</div><small class='muted'>"+H.esc(cap.device)+" · "+H.fmt(cap.speedMbps,0)+" Mbps · "+(a?'كل اتجاه محسوب منفصلاً لوصلة full-duplex.':'each full-duplex direction is calculated separately.')+"</small>";return H.card(title,body,cap.device,'net');}});
  PRO_FEATURES.push({key:"x_lq_latency_grade",ar:"ملاحظة زمن جلب اللوحة",en:"Dashboard Fetch Observation",cat:"Latency & Link Quality",fn:function(d,H){var a=H.lang==='ar',t=a?'ملاحظة زمن جلب اللوحة':'Dashboard Fetch Observation',L=H.num(d.latency_ms);if(!H.finite(L))return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');L=H.clamp(L,0,10000);var col=L<30?'var(--good)':L<100?'var(--mid)':'var(--weak)',body="<div style='text-align:center;font-size:32px;font-weight:700;color:"+col+"'>"+H.fmt(L,1)+" ms</div><small class='muted'>"+(a?'زمن طلب API للوحة في هذه اللقطة؛ ليس RTT للبوابة ولا اختباراً للشبكة.':'Dashboard API request time in this snapshot; not gateway RTT or a network test.')+"</small>";return H.card(t,body,a?'جلب API':'API fetch','net');}});
  PRO_FEATURES.push({key:"x_lq_jitter_est",ar:"سياق لقطة الجلب والهواء",en:"Fetch / Airtime Snapshot Context",cat:"Latency & Link Quality",fn:function(d,H){var a=H.lang==='ar',t=a?'سياق لقطة الجلب والهواء':'Fetch / Airtime Snapshot Context',L=H.num(d.latency_ms),w=Array.isArray(d.wifi)?d.wifi:[],sum=0,count=0;for(var i=0;i<w.length;i++){var b=H.num((w[i].survey||{}).busy_pct);if(H.finite(b)){sum+=H.clamp(b,0,100);count++;}}var busy=count?sum/count:null;if(!H.finite(L)&&busy==null)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var body="<div class='grid two'><div class='traffic-box'><span>"+(a?'جلب اللوحة':'Dashboard fetch')+"</span><b class='latin'>"+(H.finite(L)?H.fmt(L,1)+' ms':'—')+"</b></div><div class='traffic-box'><span>"+(a?'متوسط انشغال الهواء':'Mean airtime busy')+"</span><b class='latin'>"+(busy==null?'—':H.fmt(busy,0)+'%')+"</b></div></div><small class='muted'>"+(a?'قيمتان مستقلتان؛ لا يُستنتج jitter أو استقرار من لقطة واحدة.':'Independent values; jitter or stability is not inferred from one snapshot.')+"</small>";return H.card(t,body,null,'signal');}});
  PRO_FEATURES.push({key:"x_lq_link_eff",ar:"دلالة قياسات الوصلة",en:"Link Telemetry Meaning",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'دلالة قياسات الوصلة':'Link Telemetry Meaning',snaps=H.stationRateSnapshots(d,'tx'),measured=H.stationTrafficRows(d).filter(function(r){return r.rateSource==='byte-counter-delta'&&r.totalRate>0;});var body="<div class='kv'><div><span>"+(H.lang==='ar'?'آخر لقطات PHY':'Last PHY snapshots')+"</span><b>"+snaps.length+"</b></div><div><span>"+(H.lang==='ar'?'معدلات نقل مقاسة':'Measured traffic rates')+"</span><b>"+measured.length+"</b></div></div><small class='muted'>"+(H.lang==='ar'?'لقطة PHY ليست throughput ولا تُقسّم على expected_mbps لإنتاج كفاءة.':'A PHY snapshot is not throughput and is never divided by expected_mbps to create efficiency.')+"</small>";return H.card(t,body,String(measured.length),'net');}});
  PRO_FEATURES.push({key:"x_lq_airtime_fair",ar:"حالة عدالة زمن الهواء",en:"Airtime Fairness Status",cat:"Latency & Link Quality",fn:function(d,H){var title=H.lang==='ar'?'حالة عدالة زمن الهواء':'Airtime Fairness Status',configured=!!((d.perf||{}).airtime);var stateText=configured?(H.lang==='ar'?'مهيّأة':'configured'):(H.lang==='ar'?'غير معلنة':'not advertised');var note=H.lang==='ar'?'لا تتوفر عدادات airtime لكل عميل، لذلك لا يُحسب مؤشر عدالة زائف من آخر معدلات PHY.':'Per-client airtime counters are unavailable, so no false fairness score is computed from last PHY rates.';return H.card(title,"<div style='font-size:20px;font-weight:700;color:"+(configured?'var(--excellent)':'var(--muted)')+"'>"+stateText+"</div><small class='muted'>"+note+"</small>",stateText,'signal');}});
  PRO_FEATURES.push({key:"x_lq_ceiling_1200",ar:"قدرة 2×2 حسب الراديو",en:"Per-Radio 2×2 Capability",cat:"Latency & Link Quality",fn:function(d,H){var title=H.lang==='ar'?'قدرة 2×2 حسب الراديو':'Per-Radio 2×2 Capability',w=Array.isArray(d.wifi)?d.wifi:[],rows='',known=0;for(var i=0;i<w.length;i++){var cap=H.configuredPhyCeiling2x2(w[i]);if(!cap)continue;known++;rows+="<div class='kv'><div><span>"+H.esc(w[i].band||'?')+' · '+H.esc(cap.mode)+"</span><b class='latin'>"+H.fmt(cap.mbps,cap.mbps<1000?1:0)+" Mbps</b></div></div>";}if(!known)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');rows+="<small class='muted'>"+(H.lang==='ar'?'قدرة مهيّأة وليست throughput أو حكماً من لقطة عميل خامل.':'Configured capability, not throughput or a judgment from an idle-client snapshot.')+"</small>";return H.card(title,rows,known+'','net');}});
  PRO_FEATURES.push({key:"x_lq_phy_eff_rank",ar:"تفاصيل آخر لقطة PHY",en:"Last PHY Snapshot Details",cat:"Latency & Link Quality",fn:function(d,H){var t=H.lang==='ar'?'تفاصيل آخر لقطة PHY':'Last PHY Snapshot Details',arr=H.stationRateSnapshots(d,'tx');if(!arr.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');arr.sort(function(a,b){return b.info.rate-a.info.rate;});var rows='';arr.slice(0,6).forEach(function(x){var p=[H.fmt(x.info.rate,1)+' Mbps',x.info.family||'?'];if(H.finite(x.info.mcs))p.push('MCS '+x.info.mcs);if(H.finite(x.info.nss))p.push(x.info.nss+'SS');var age=H.stationInactiveAge(x.station.inactive_ms);if(age)p.push('inactive '+age);rows+="<div style='display:flex;justify-content:space-between;gap:8px;margin:7px 0;font-size:12px'><span>"+H.esc(x.station.ip||x.station.mac||'?')+"</span><span class='latin'>"+H.esc(p.join(' · '))+"</span></div>";});rows+="<small class='muted'>"+(H.lang==='ar'?'ترتيب لقطة تشخيصية فقط؛ لا يمثل throughput أو استهلاكاً أو كفاءة.':'Diagnostic snapshot ordering only; it is not throughput, consumption, or efficiency.')+"</small>";return H.card(t,rows,String(arr.length),'net');}});
  PRO_FEATURES.push({key:"x_lq_rtt_budget",ar:"عتبة زمن جلب اللوحة",en:"Dashboard Fetch Threshold",cat:"Latency & Link Quality",fn:function(d,H){var a=H.lang==='ar',t=a?'عتبة زمن جلب اللوحة':'Dashboard Fetch Threshold',L=H.num(d.latency_ms),LIMIT=100;if(!H.finite(L))return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');L=H.clamp(L,0,LIMIT*3);var used=H.clamp(L/LIMIT*100,0,100),col=L<30?'var(--good)':L<LIMIT?'var(--mid)':'var(--weak)',body="<div style='display:flex;justify-content:space-between;font-size:12px;margin-bottom:4px'><span>"+(a?'جلب API':'API fetch')+"</span><span style='color:"+col+"'>"+H.fmt(L,1)+' / '+LIMIT+" ms</span></div>"+H.bar(used,100,col)+"<small class='muted'>"+(a?'عتبة عرض محلية وليست ميزانية RTT أو جودة وصلة.':'Local display threshold, not an RTT budget or link-quality result.')+"</small>";return H.card(t,body,'100 ms','net');}});
  PRO_FEATURES.push({key:"x_lq_stability_score",ar:"قياسات لقطة الوصلة",en:"Link Snapshot Telemetry",cat:"Latency & Link Quality",fn:function(d,H){var a=H.lang==='ar',t=a?'قياسات لقطة الوصلة':'Link Snapshot Telemetry',lat=H.num(d.latency_ms),signals=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(w.stations||[]).forEach(function(s){var v=H.num(s.snr);if(!H.finite(v)){var sig=H.num(s.signal_dbm),noise=H.num(w.noise_dbm);if(H.finite(sig)&&H.finite(noise))v=sig-noise;}if(H.finite(v))signals.push(v);});});var avg=signals.length?signals.reduce(function(x,y){return x+y;},0)/signals.length:null;if(!H.finite(lat)&&!H.finite(avg))return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'signal');var rows="<div class='kv'><div><span>"+(a?'زمن جلب اللوحة':'Dashboard fetch time')+"</span><b class='latin'>"+(H.finite(lat)?H.fmt(lat,1)+' ms':'—')+"</b></div><div><span>"+(a?'متوسط SNR الحالي':'Current average SNR')+"</span><b class='latin'>"+(H.finite(avg)?H.fmt(avg,1)+' dB':'—')+"</b></div></div><small class='muted'>"+(a?'قيم لقطة مستقلة؛ لا تثبت الاستقرار عبر الزمن.':'Independent snapshot values; they do not prove longitudinal stability.')+"</small>";return H.card(t,rows,String(signals.length),'signal');}});
  PRO_FEATURES.push({key:"x_se_open_ssid_audit",ar:"لقطة الشبكات المفتوحة",en:"Open SSID Snapshot",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],T=a?'لقطة الشبكات المفتوحة':'Open SSID Snapshot';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var rows='',open=0;for(var i=0;i<w.length;i++){var r=w[i],enc=String(r.encryption||'').toLowerCase(),isOpen=enc===''||enc==='none';if(isOpen)open++;var col=isOpen?'var(--weak)':'var(--good)',lab=isOpen?(a?'مفتوحة':'OPEN'):(a?'تشفير معلن':'encryption advertised');rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(r.ssid||r.band||'?')+"</span><span style='color:"+col+"'>"+lab+"</span></div>";}var chip=open?String(open)+(a?' مفتوحة':' open'):(a?'لم تُرصد مفتوحة':'none open observed');return H.card(T,rows,chip,'shield');}});
  PRO_FEATURES.push({key:"x_se_wpa_posture",ar:"تفاصيل تشفير SSID",en:"SSID Encryption Details",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],T=a?'تفاصيل تشفير SSID':'SSID Encryption Details';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var rows='';for(var i=0;i<w.length;i++){var r=w[i],sl=H.secLevel(r.encryption||''),col=(sl&&sl.col)?sl.col:'var(--muted)',txt=(sl&&sl.txt)?sl.txt:'—';rows+="<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(r.band||'?')+"</span><span style='color:"+col+"'>"+H.esc(txt)+"</span></div><div style='font-size:11px;color:var(--muted)'>"+H.esc(String(r.encryption||'none'))+"</div></div>";}rows+="<small class='muted'>"+(a?'لا يوجد حقل PMF في هذه البيانات؛ لا تُستنتج حالته من اسم WPA.':'No PMF field is present in this data; PMF status is not inferred from the WPA name.')+"</small>";return H.card(T,rows,null,'shield');}});
  PRO_FEATURES.push({key:"x_se_rogue_neighbors",ar:"لقطة عدد الجيران",en:"Neighbor Count Snapshot",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',n=Array.isArray(d.neighbors)?d.neighbors:(Array.isArray(d.lldp)?d.lldp:[]),T=a?'لقطة عدد الجيران':'Neighbor Count Snapshot',cnt=n.length;var body="<div style='text-align:center;font-size:36px;font-weight:800;color:var(--primary)'>"+cnt+"</div><small class='muted'>"+(a?'عدد الجيران المرصودين فقط؛ لا يكتشف جهازاً خبيثاً ولا يثبت الازدحام.':'Observed neighbor count only; it neither detects rogue devices nor proves congestion.')+"</small>";return H.card(T,body,String(cnt),'wifi');}});
  PRO_FEATURES.push({key:"x_se_new_device_watch",ar:"مراقبة أجهزة جديدة",en:"New Device Watch",cat:"Security & Threats",fn:function(d,H){var st=[];(Array.isArray(d.wifi)?d.wifi:[]).forEach(function(w){(Array.isArray(w.stations)?w.stations:[]).forEach(function(s){st.push(s);});});var T=H.lang==='ar'?'مراقبة أجهزة جديدة':'New Device Watch';if(!st.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'device');var recent=[];for(var i=0;i<st.length;i++){var c=H.num(st[i].conn_s);if(H.finite(c)&&c<600){recent.push(st[i]);}}if(!recent.length)return H.card(T,"<div style='color:var(--excellent)'>"+(H.lang==='ar'?'لا أجهزة جديدة':'no new joins')+"</div>",'0','device');recent.sort(function(a,b){return H.num(a.conn_s)-H.num(b.conn_s);});var rows='';for(var j=0;j<recent.length&&j<5;j++){var s=recent[j];rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:5px 0'><span>"+H.esc(s.ip||s.mac||'?')+"</span><span style='color:var(--mid)'>"+H.uptime(H.finite(H.num(s.conn_s))?H.num(s.conn_s):0)+"</span></div>";}return H.card(T,rows,String(recent.length),'device');}});
  PRO_FEATURES.push({key:"x_se_client_isolation",ar:"رؤية العزل غير معروفة",en:"Isolation Visibility Unknown",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],T=a?'رؤية العزل غير معروفة':'Isolation Visibility Unknown';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var clients=0,rows='';for(var i=0;i<w.length;i++){var r=w[i],n=(Array.isArray(r.stations)?r.stations:[]).length;clients+=n;rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(r.band||'?')+"</span><span>"+n+(a?' عميل مرتبط':' associated clients')+"</span></div>";}rows+="<small class='muted'>"+(a?'عدد العملاء لا يكشف سياسة العزل أو إمكانية الوصول المتبادل؛ يلزم حقل إعداد أو اختبار اتصال.':'Station counts do not reveal isolation policy or peer reachability; a configuration field or connectivity test is required.')+"</small>";return H.card(T,rows,a?'غير معروف':'unknown','shield');}});
  PRO_FEATURES.push({key:"x_se_mgmt_exposure",ar:"تقدير التعرّض عبر SSID المفتوح",en:"Open-SSID Exposure Estimate",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],T=a?'تقدير التعرّض عبر SSID المفتوح':'Open-SSID Exposure Estimate';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'net');var clients=0,open=0;for(var i=0;i<w.length;i++){var r=w[i],enc=String(r.encryption||'').toLowerCase();if(enc===''||enc==='none'){open++;var c=H.num(r.clients);if(!H.finite(c))c=(Array.isArray(r.stations)?r.stations:[]).length;clients+=c;}}var body="<div class='grid two'><div class='traffic-box'><span>"+(a?'شبكات مفتوحة':'Open SSIDs')+"</span><b>"+open+"</b></div><div class='traffic-box'><span>"+(a?'عملاء مرتبطون بها':'Associated clients')+"</span><b>"+clients+"</b></div></div><small class='muted'>"+(a?'هذه ملاحظة تشفير فقط؛ وصول صفحة الإدارة والمستمعون والجدار الناري وACL لم تُختبر.':'Encryption observation only; management reachability, listeners, firewall and ACLs were not tested.')+"</small>";return H.card(T,body,a?'الإدارة غير مختبرة':'management untested','net');}});
  PRO_FEATURES.push({key:"x_se_enc_coverage",ar:"ارتباط العملاء بشبكات معلنة التشفير",en:"Clients on Encryption-advertised SSIDs",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],T=a?'ارتباط العملاء بشبكات معلنة التشفير':'Clients on Encryption-advertised SSIDs';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var total=0,encrypted=0;for(var i=0;i<w.length;i++){var r=w[i],c=H.num(r.clients);if(!H.finite(c))c=(Array.isArray(r.stations)?r.stations:[]).length;total+=c;var enc=String(r.encryption||'').toLowerCase();if(enc&&enc!=='none'&&enc!=='open')encrypted+=c;}if(total<=0)return H.card(T,"<div style='color:var(--muted)'>"+(a?'لا عملاء مرتبطين':'no associated clients')+"</div>",null,'shield');var pct=H.clamp(encrypted/total*100,0,100),col=pct>=99?'var(--good)':pct>=60?'var(--mid)':'var(--weak)',body="<div style='font-size:20px;font-weight:700;color:"+col+"'>"+H.fmt(pct,0)+"%</div>"+H.bar(pct,100,col)+"<div style='font-size:11px;color:var(--muted);margin-top:4px'>"+encrypted+' / '+total+(a?' عميل على SSID يعلن تشفيراً':' clients on SSIDs advertising encryption')+"</div><small class='muted'>"+(a?'لا يثبت خصائص أمان أخرى.':'Does not prove other security properties.')+"</small>";return H.card(T,body,H.fmt(pct,0)+'%','shield');}});
  PRO_FEATURES.push({key:"x_se_posture_score",ar:"تقدير تغطية تشفير SSID",en:"SSID Encryption-only Coverage",cat:"Security & Threats",fn:function(d,H){var a=H.lang==='ar',w=Array.isArray(d.wifi)?d.wifi:[],T=a?'تقدير تغطية تشفير SSID':'SSID Encryption-only Coverage';if(!w.length)return H.card(T,"<div style='color:var(--muted)'>—</div>",null,'shield');var encrypted=0;for(var i=0;i<w.length;i++){var enc=String(w[i].encryption||'').toLowerCase();if(enc&&enc!=='none'&&enc!=='open')encrypted++;}var pct=H.clamp(encrypted/w.length*100,0,100),col=pct===100?'var(--good)':pct>0?'var(--mid)':'var(--weak)',body="<div style='font-size:34px;text-align:center;color:"+col+"'>"+H.fmt(pct,0)+"%</div>"+H.bar(pct,100,col)+"<small class='muted'>"+(a?'نسبة SSID التي تعلن تشفيراً فقط؛ ليست درجة أمان ولا تدقيق PMF/جدار ناري/إدارة.':'Share of SSIDs advertising encryption only; not a security score or PMF/firewall/management audit.')+"</small>";return H.card(T,body,encrypted+'/'+w.length,'shield');}});
  PRO_FEATURES.push({key:"x_sy_resource_triad",ar:"موارد النظام",en:"System Resources",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'موارد النظام':'System Resources';var cpu=d.cpu||{};var mem=d.mem||{};var stg=d.storage||{};var cp=H.num(cpu.percent);var mt=H.num(mem.total);var ma=H.num(mem.available);var stt=H.num(stg.total);var stu=H.num(stg.used);var cpct=H.finite(cp)?H.clamp(cp,0,100):null;var mpct=(H.finite(mt)&&mt>0&&H.finite(ma))?H.clamp((mt-ma)/mt*100,0,100):null;var spct=(H.finite(stt)&&stt>0&&H.finite(stu))?H.clamp(stu/stt*100,0,100):null;if(cpct==null&&mpct==null&&spct==null)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');function c(p){return p==null?'var(--muted)':(p<50?'var(--excellent)':p<75?'var(--good)':p<90?'var(--mid)':'var(--weak)');}function row(lab,pct){var col=c(pct);return "<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+lab+"</span><span style='color:"+col+"'>"+(pct==null?'—':H.fmt(pct,0)+'%')+"</span></div>"+H.bar(pct||0,100,col)+"</div>";}var body=row(ar?'المعالج':'CPU',cpct)+row(ar?'الذاكرة':'RAM',mpct)+row(ar?'التخزين':'Flash',spct);return H.card(title,body,null,'cpu');}});
  PRO_FEATURES.push({key:"x_sy_thermal_headroom",ar:"هامش الحرارة",en:"Thermal Headroom",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'هامش الحرارة':'Thermal Headroom';var t=H.num(d.temperature_c);if(!H.finite(t))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');var ceil=105;var head=ceil-t;var pct=H.clamp(t/ceil*100,0,100);var col=t<55?'var(--excellent)':t<70?'var(--good)':t<85?'var(--mid)':'var(--weak)';var body=H.gauge(ar?'المعالج':'SoC',H.fmt(t,0)+'°C',(ar?'هامش ':'headroom ')+H.fmt(head,0)+'°C',(ar?'الحد ':'ceiling ')+ceil+'°C',pct,col,'cpu');return H.card(title,body,H.fmt(head,0)+'°C','cpu');}});
  PRO_FEATURES.push({key:"x_sy_uptime_milestone",ar:"إنجاز التشغيل",en:"Uptime Milestone",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'إنجاز التشغيل':'Uptime Milestone';var u=H.num(d.uptime);if(!H.finite(u)||u<0)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var days=u/86400;var ms=[1,7,30,90,180,365];var next=null,prev=0;for(var i=0;i<ms.length;i++){if(days<ms[i]){next=ms[i];break;}prev=ms[i];}var body="<div style='font-size:22px;font-weight:700'>"+H.esc(H.uptime(u))+"</div>";if(next==null){body+="<div style='color:var(--excellent);font-size:12px;margin-top:6px'>"+(ar?'تجاوز سنة كاملة':'Over a full year')+"</div>";return H.card(title,body,'365d+','net');}var span=next-prev;var into=days-prev;var pct=span>0?H.clamp(into/span*100,0,100):0;var col=pct<50?'var(--good)':pct<85?'var(--mid)':'var(--excellent)';body+="<div style='font-size:12px;color:var(--muted);margin:6px 0'>"+(ar?'التالي':'Next')+': '+next+(ar?' يوم':'d')+"</div>"+H.bar(pct,100,col);return H.card(title,body,H.fmt(days,0)+'d','net');}});
  PRO_FEATURES.push({key:"x_sy_load_verdict",ar:"حكم متوسط الحِمل",en:"Load Verdict",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'حكم متوسط الحِمل':'Load Verdict';var l=Array.isArray(d.load)?d.load:[];var cores=H.num((d.cpu||{}).cores);if(!H.finite(cores)||cores<=0)cores=1;var l1=H.num(l[0]),l5=H.num(l[1]),l15=H.num(l[2]);if(!H.finite(l1)&&!H.finite(l5)&&!H.finite(l15))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');function seg(lab,v){if(!H.finite(v))return "<div class='traffic-box'><span>"+lab+"</span><b style='color:var(--muted)'>—</b></div>";var per=v/cores;var col=per<0.7?'var(--excellent)':per<1?'var(--good)':per<1.5?'var(--mid)':'var(--weak)';return "<div class='traffic-box'><span>"+lab+"</span><b style='color:"+col+"'>"+H.fmt(v,2)+"</b><small class='muted'>"+H.fmt(per*100,0)+"%/core</small></div>";}var body="<div class='grid three'>"+seg('1m',l1)+seg('5m',l5)+seg('15m',l15)+"</div>";var v1=H.finite(l1)?l1/cores:null;var chip=v1==null?null:(v1<0.7?(ar?'خفيف':'Light'):v1<1?(ar?'طبيعي':'Normal'):v1<1.5?(ar?'مرتفع':'Busy'):(ar?'مُحمّل':'Overloaded'));return H.card(title,body,chip,'cpu');}});
  PRO_FEATURES.push({key:"x_sy_mem_pressure",ar:"ضغط الذاكرة",en:"Memory Pressure",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'ضغط الذاكرة':'Memory Pressure';var m=d.mem||{};var mt=H.num(m.total),ma=H.num(m.available);if(!H.finite(mt)||mt<=0||!H.finite(ma))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'ram');var used=mt-ma;if(used<0)used=0;var pct=H.clamp(used/mt*100,0,100);var col=pct<60?'var(--excellent)':pct<80?'var(--good)':pct<92?'var(--mid)':'var(--weak)';var lvl=pct<60?(ar?'مريح':'Comfortable'):pct<80?(ar?'معتدل':'Moderate'):pct<92?(ar?'مرتفع':'Elevated'):(ar?'حرج':'Critical');var body=H.gauge(ar?'مستخدم':'Used',H.fmt(pct,0)+'%',H.bytes(used)+' / '+H.bytes(mt),(ar?'متاح ':'free ')+H.bytes(ma),pct,col,'ram');return H.card(title,body,lvl,'ram');}});
  PRO_FEATURES.push({key:"x_sy_flash_capacity",ar:"سعة التخزين",en:"Flash Storage",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'سعة التخزين':'Flash Storage';var s=d.storage||{};var tt=H.num(s.total),us=H.num(s.used),av=H.num(s.available);if(!H.finite(tt)||tt<=0)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'storage');if(!H.finite(us)&&H.finite(av))us=tt-av;if(!H.finite(us))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'storage');if(us<0)us=0;var pct=H.clamp(us/tt*100,0,100);var free=H.finite(av)?av:tt-us;var col=pct<70?'var(--excellent)':pct<85?'var(--good)':pct<95?'var(--mid)':'var(--weak)';var chip=(H.finite(free)&&free<(tt*0.1))?(ar?'شبه ممتلئ':'Nearly full'):null;var body=H.gauge(ar?'مستخدم':'Used',H.fmt(pct,0)+'%',H.bytes(us)+' / '+H.bytes(tt),(ar?'حر ':'free ')+H.bytes(free),pct,col,'storage');return H.card(title,body,chip,'storage');}});
  PRO_FEATURES.push({key:"x_sy_service_rollup",ar:"حالة الخدمات",en:"Service Health",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'حالة الخدمات':'Service Health';var h=d.services;if(!h||typeof h!=='object'||Array.isArray(h))return H.card(title,"<div style='color:var(--muted)'>"+(ar?'غير متوفر في هذه اللقطة':'Unavailable in this snapshot')+"</div>",null,'shield');var keys=[];for(var k in h){if(Object.prototype.hasOwnProperty.call(h,k))keys.push(k);}if(!keys.length)return H.card(title,"<div style='color:var(--muted)'>"+(ar?'غير متوفر في هذه اللقطة':'Unavailable in this snapshot')+"</div>",null,'shield');function ok(v){if(v===true)return true;if(v===false)return false;if(typeof v==='number')return H.finite(v)&&v>0;if(typeof v==='string'){var s=v.toLowerCase();return s==='ok'||s==='up'||s==='running'||s==='online'||s==='good'||s==='active'||s==='healthy';}return !!v;}var good=0,rows='';for(var i=0;i<keys.length;i++){var isok=ok(h[keys[i]]);if(isok)good++;var col=isok?'var(--excellent)':'var(--weak)';var txt=isok?(ar?'يعمل':'up'):(ar?'متوقف':'down');rows+="<div style='display:flex;justify-content:space-between;align-items:center;font-size:12px;margin:5px 0'><span>"+H.esc(keys[i])+"</span><span style='color:"+col+"'>●&nbsp;"+txt+"</span></div>";}return H.card(title,rows,good+'/'+keys.length,'shield');}});
  PRO_FEATURES.push({key:"x_sy_stability_score",ar:"تقدير هامش الموارد الحالي",en:"Current Resource-headroom Estimate",cat:"System & Health",fn:function(d,H){var ar=H.lang==='ar',title=ar?'تقدير هامش الموارد الحالي':'Current Resource-headroom Estimate',cp=H.num((d.cpu||{}).percent),m=d.mem||{},mt=H.num(m.total),ma=H.num(m.available),temp=H.num(d.temperature_c),l=Array.isArray(d.load)?d.load:[],l1=H.num(l[0]),cores=H.num((d.cpu||{}).cores);if(!H.finite(cores)||cores<=0)cores=1;var scores=[];if(H.finite(cp))scores.push(H.clamp(100-cp,0,100));if(H.finite(mt)&&mt>0&&H.finite(ma))scores.push(H.clamp(ma/mt*100,0,100));if(H.finite(temp))scores.push(H.clamp((105-temp)/105*100,0,100));if(H.finite(l1))scores.push(H.clamp(100-(l1/cores*100),0,100));if(!scores.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'shield');var sum=0;for(var i=0;i<scores.length;i++)sum+=scores[i];var avg=sum/scores.length,col=avg>=80?'var(--excellent)':avg>=60?'var(--good)':avg>=40?'var(--mid)':'var(--weak)';var body=H.gauge(ar?'الهامش الحالي':'Current headroom',H.fmt(avg,0),(ar?'مدخلات مأخوذة كعينة':'sampled inputs'),(ar?'من ':'from ')+scores.length+(ar?' مقاييس':' metrics'),avg,col,'shield')+"<small class='muted'>"+(ar?'تركيب حسابي من لقطة CPU/RAM/حرارة/حمل؛ ليس إثبات استقرار زمني.':'Arithmetic composite of one CPU/RAM/temperature/load snapshot; not longitudinal stability proof.')+"</small>";return H.card(title,body,String(scores.length),'shield');}});
  PRO_FEATURES.push({key:"x_tp_lldp_map",ar:"خريطة الجيران LLDP",en:"LLDP Neighbors",cat:"Topology & Discovery",fn:function(d,H){var n=Array.isArray(d.lldp)?d.lldp:(Array.isArray(d.neighbors)?d.neighbors:[]);var t=H.lang==='ar'?'خريطة الجيران LLDP':'LLDP Neighbors';if(!n.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='';for(var i=0;i<n.length&&i<8;i++){var x=n[i]||{};var nm=x.name||x.host||x.chassis||x.system||x.mac||'?';var pt=x.port||x.iface||x.port_id||'';var ip=x.ip||x.mgmt_ip||'';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(String(nm))+(pt?" <small class='muted'>· "+H.esc(String(pt))+"</small>":"")+"</span><span style='color:var(--muted)'>"+H.esc(String(ip))+"</span></div>";}return H.card(t,rows,String(n.length),'net');}});
  PRO_FEATURES.push({key:"x_tp_radio_ports",ar:"عملاء كل راديو",en:"Clients per Radio",cat:"Topology & Discovery",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var t=H.lang==='ar'?'عملاء كل راديو':'Clients per Radio';if(!w.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'wifi');var mx=1,cnts=[];for(var i=0;i<w.length;i++){var r=w[i]||{};var c=H.num(r.clients);if(!H.finite(c)){var st=Array.isArray(r.stations)?r.stations:[];c=st.length;}c=H.finite(c)?c:0;cnts.push(c);if(c>mx)mx=c;}var rows='',tot=0;for(var j=0;j<w.length;j++){var rr=w[j]||{};var cc=cnts[j];tot+=cc;var lab=(rr.iface||rr.band||'?');rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+H.esc(String(lab))+"</span><span>"+cc+"</span></div>"+H.bar(cc,mx,'var(--accent)')+"</div>";}return H.card(t,rows,String(tot),'wifi');}});
  PRO_FEATURES.push({key:"x_tp_wired_wifi",ar:"سلكي مقابل لاسلكي",en:"Wired vs Wi-Fi",cat:"Topology & Discovery",fn:function(d,H){var dv=H.mergeDevices(d);dv=Array.isArray(dv)?dv:[];var t=H.lang==='ar'?'سلكي مقابل لاسلكي':'Wired vs Wi-Fi';if(!dv.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var wired=0,wifi=0;for(var i=0;i<dv.length;i++){var s=dv[i]||{};var ty=String(s.type||'').toLowerCase();if(ty.indexOf('wire')>=0||ty==='eth'||ty==='lan'){wired++;}else if(ty.indexOf('wif')>=0||ty.indexOf('wl')>=0||ty.indexOf('wireless')>=0){wifi++;}else if(H.finite(H.num(s.signal_dbm))||s.band){wifi++;}else{wired++;}}var tot=wired+wifi;function box(v,lbl,col){var p=tot>0?(v/tot*100):0;return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+v+"</b><small class='muted'>"+H.fmt(p,0)+"%</small></div>";}var body="<div class='grid two'>"+box(wired,H.lang==='ar'?'سلكي':'Wired','var(--good)')+box(wifi,H.lang==='ar'?'لاسلكي':'Wi-Fi','var(--accent)')+"</div>"+H.bar(wifi,tot,'var(--accent)');return H.card(t,body,String(tot),'net');}});
  PRO_FEATURES.push({key:"x_tp_uplink_quality",ar:"حالة الوصلة وسياق جلب اللوحة",en:"Uplink Status + Dashboard Fetch",cat:"Topology & Discovery",fn:function(d,H){var a=H.lang==='ar',b=d.backhaul||{},t=a?'حالة الوصلة وسياق جلب اللوحة':'Uplink Status + Dashboard Fetch',on=b.online,lat=H.num(d.latency_ms),gw=b.gateway||'',dev=b.device||'';if(on==null&&!H.finite(lat)&&!gw&&!dev)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var col=on===false?'var(--weak)':on===true?'var(--good)':'var(--muted)',stTxt=on===false?(a?'غير متصل':'Offline'):on===true?(a?'متصل':'Online'):(a?'غير معروف':'Unknown'),latTxt=H.finite(lat)?H.fmt(lat,0)+' ms':'—';var body="<div style='display:flex;justify-content:space-between;align-items:center;margin:6px 0'><b style='color:"+col+"'>"+stTxt+"</b><span>"+(a?'جلب اللوحة ':'Dashboard fetch ')+latTxt+"</span></div><div style='font-size:12px;color:var(--muted)'>"+(a?'البوابة':'Gateway')+": "+H.esc(String(gw||'—'))+"</div><div style='font-size:12px;color:var(--muted)'>"+(a?'المنفذ':'Device')+": "+H.esc(String(dev||'—'))+"</div><small class='muted'>"+(a?'حالة ومسار معلنان مع زمن API منفصل؛ لا يوجد حكم جودة وصلة.':'Reported status/path plus separate API timing; no link-quality verdict is made.')+"</small>";return H.card(t,body,stTxt,'net');}});
  PRO_FEATURES.push({key:"x_tp_ap_role",ar:"دور الجهاز",en:"Device Role",cat:"Topology & Discovery",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var b=d.backhaul||{};var t=H.lang==='ar'?'دور الجهاز':'Device Role';if(!w.length&&b.online==null)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'wifi');var role=(b.online?(H.lang==='ar'?'نقطة وصول (موصولة)':'Access Point (uplinked)'):(H.lang==='ar'?'نقطة وصول':'Access Point'));var ssids='';for(var i=0;i<w.length;i++){var r=w[i]||{};var ss=r.ssid||'?';ssids+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:5px 0'><span>"+H.esc(String(ss))+"</span><small class='muted'>"+H.esc(String(r.band||''))+"</small></div>";}var body="<div style='font-size:15px;font-weight:600;color:var(--accent);margin-bottom:6px'>"+role+"</div>"+(ssids||"<div style='color:var(--muted)'>—</div>");return H.card(t,body,'AP','wifi');}});
  PRO_FEATURES.push({key:"x_tp_bridge_health",ar:"صحة أعضاء الجسر",en:"Bridge Member Health",cat:"Topology & Discovery",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var t=H.lang==='ar'?'صحة أعضاء الجسر':'Bridge Member Health';if(!ifs.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='',bad=0;for(var i=0;i<ifs.length&&i<8;i++){var f=ifs[i]||{};var e=(H.num(f.rx_errors)||0)+(H.num(f.tx_errors)||0);var dr=(H.num(f.rx_dropped)||0)+(H.num(f.tx_dropped)||0);e=H.finite(e)?e:0;dr=H.finite(dr)?dr:0;var tot=e+dr;var col=tot===0?'var(--excellent)':tot<10?'var(--mid)':'var(--weak)';if(tot>0)bad++;var txt=tot===0?(H.lang==='ar'?'سليم':'OK'):(H.lang==='ar'?(e+' أخطاء '+dr+' مفقود'):(e+' err '+dr+' drop'));rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span>"+H.esc(String(f.name||'?'))+"</span><span style='color:"+col+"'>"+txt+"</span></div>";}return H.card(t,rows,bad>0?String(bad):null,'net');}});
  PRO_FEATURES.push({key:"x_tp_discovery_count",ar:"ملخص الاكتشاف",en:"Discovery Summary",cat:"Topology & Discovery",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var cl=0;for(var i=0;i<w.length;i++){var r=w[i]||{};var c=H.num(r.clients);if(!H.finite(c)){var st=Array.isArray(r.stations)?r.stations:[];c=st.length;}cl+=H.finite(c)?c:0;}var dv=H.mergeDevices(d);dv=Array.isArray(dv)?dv:[];var nb=Array.isArray(d.lldp)?d.lldp.length:(Array.isArray(d.neighbors)?d.neighbors.length:0);var t=H.lang==='ar'?'ملخص الاكتشاف':'Discovery Summary';if(!cl&&!dv.length&&!nb)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'device');function box(v,lbl,col){return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+v+"</b></div>";}var body="<div class='grid two'>"+box(cl,H.lang==='ar'?'عملاء واي فاي':'Wi-Fi Clients','var(--accent)')+box(dv.length,H.lang==='ar'?'أجهزة':'Devices','var(--good)')+box(nb,H.lang==='ar'?'جيران LLDP':'LLDP','var(--primary)')+"</div>";return H.card(t,body,String(dv.length+nb),'device');}});
  PRO_FEATURES.push({key:"x_tp_link_activity",ar:"نشاط الوصلات",en:"Link Activity",cat:"Topology & Discovery",fn:function(d,H){var ifs=Array.isArray(d.interfaces)?d.interfaces:[];var t=H.lang==='ar'?'نشاط الوصلات':'Link Activity';if(!ifs.length)return H.card(t,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='',act=0,shown=0;for(var i=0;i<ifs.length&&i<8;i++){var f=ifs[i]||{};var rb=H.num(f.rx_bps);var tb=H.num(f.tx_bps);rb=H.finite(rb)?rb:0;tb=H.finite(tb)?tb:0;var tot=rb+tb;var up=tot>0;if(up)act++;shown++;var col=up?'var(--excellent)':'var(--muted)';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:6px 0'><span style='color:"+col+"'>● "+H.esc(String(f.name||'?'))+"</span><span class='muted'>"+H.bps(tot)+"</span></div>";}return H.card(t,rows,String(act)+'/'+String(shown),'net');}});
  PRO_FEATURES.push({key:"x_ux_setup_score",ar:"اكتمال الإعداد",en:"Setup Completeness",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'اكتمال الإعداد':'Setup Completeness';var w=Array.isArray(d.wifi)?d.wifi:[];var checks=[];checks.push(w.length>0);var bands={};for(var i=0;i<w.length;i++){bands[w[i].band]=1;}checks.push(!!bands['2.4G']&&!!bands['5G']);var bh=d.backhaul||{};checks.push(!!bh.online);var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);checks.push(H.finite(mt)&&H.finite(ma)&&mt>0&&(ma/mt)>0.1);var cpu=H.num((d.cpu||{}).percent);checks.push(H.finite(cpu)&&cpu<90);var sa=H.num((d.storage||{}).available);checks.push(H.finite(sa)&&sa>0);var clients=0;for(var j=0;j<w.length;j++){clients+=(H.num(w[j].clients)||0);}checks.push(clients>0);var pass=0;for(var k=0;k<checks.length;k++){if(checks[k])pass++;}var tot=checks.length;if(!tot)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'shield');var pct=H.clamp(pass/tot*100,0,100);var col=pct>=80?'var(--excellent)':pct>=50?'var(--good)':pct>=30?'var(--mid)':'var(--weak)';return H.card(title,H.gauge(ar?'مكتمل':'Complete',H.fmt(pct,0)+'%',pass+'/'+tot,ar?'فحوصات':'checks',pct,col,'shield'),pass+'/'+tot,'shield');}});
  PRO_FEATURES.push({key:"x_ux_verdict",ar:"قائمة حالة محدودة",en:"Limited Status Checklist",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar',title=ar?'قائمة حالة محدودة':'Limited Status Checklist',items=[],cpu=H.num((d.cpu||{}).percent),mem=d.mem||{},mt=H.num(mem.total),ma=H.num(mem.available),bh=d.backhaul||{},lat=H.num(d.latency_ms),temp=H.num(d.temperature_c);items.push({l:'CPU',s:H.finite(cpu)?cpu<=85:null});items.push({l:'RAM',s:H.finite(mt)&&H.finite(ma)&&mt>0?(ma/mt)>=0.1:null});items.push({l:ar?'الوصلة':'Uplink',s:bh.online===true?true:bh.online===false?false:null});items.push({l:ar?'جلب اللوحة':'Dashboard fetch',s:H.finite(lat)?lat<=100:null});items.push({l:ar?'الحرارة':'Temperature',s:H.finite(temp)?temp<=80:null});var known=0,pass=0,warn=0,rows='';for(var i=0;i<items.length;i++){var it=items[i];if(it.s!==null){known++;if(it.s)pass++;else warn++;}var col=it.s===null?'var(--muted)':it.s?'var(--excellent)':'var(--weak)',mark=it.s===null?'?':it.s?'✓':'!';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:5px 0'><span>"+it.l+"</span><span style='color:"+col+";font-weight:700'>"+mark+"</span></div>";}rows+="<small class='muted'>"+(ar?'فحوص عتبات للحقول المتاحة فقط؛ ليست حكماً شاملاً على الشبكة.':'Threshold checks for available fields only; not an overall network verdict.')+"</small>";return H.card(title,rows,warn?warn+(ar?' تحذير':' warning'):(known?pass+'/'+known:(ar?'غير معروف':'unknown')),'shield');}});
  PRO_FEATURES.push({key:"x_ux_tips",ar:"تنبيهات العتبات",en:"Threshold Alerts",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar',title=ar?'تنبيهات العتبات':'Threshold Alerts',tips=[],w=Array.isArray(d.wifi)?d.wifi:[];for(var i=0;i<w.length;i++){var b=H.num((w[i].survey||{}).busy_pct);if(H.finite(b)&&b>70){tips.push((ar?'انشغال هواء مرتفع في لقطة ':'High airtime snapshot on ')+H.esc(w[i].band||'?')+(ar?' — افحص ظروف القناة':' — inspect channel conditions'));break;}}var cpu=H.num((d.cpu||{}).percent);if(H.finite(cpu)&&cpu>85)tips.push(ar?'المعالج مرتفع — راجع العمليات':'CPU high — check processes');var mem=d.mem||{},mt=H.num(mem.total),ma=H.num(mem.available);if(H.finite(mt)&&H.finite(ma)&&mt>0&&(ma/mt)<0.12)tips.push(ar?'الذاكرة المتاحة منخفضة':'Low available memory');var weak=0;for(var j=0;j<w.length;j++){var sts=Array.isArray(w[j].stations)?w[j].stations:[];for(var k=0;k<sts.length;k++){var s=H.num(sts[k].signal_dbm);if(H.finite(s)&&s<-75)weak++;}}if(weak>0)tips.push(weak+(ar?' عميل بلقطة RSSI ضعيفة — قيّم الموضع':' weak-RSSI client snapshots — evaluate placement'));var lat=H.num(d.latency_ms);if(H.finite(lat)&&lat>120)tips.push(ar?'جلب لوحة الراوتر بطيء':'Dashboard fetch is slow');if(!tips.length)return H.card(title,"<div style='color:var(--muted)'>"+(ar?'لا تنبيهات عتبات في الحقول المأخوذة كعينة':'No threshold alerts in sampled fields')+"</div>",null,'shield');var rows='';for(var t=0;t<tips.length&&t<5;t++)rows+="<div style='display:flex;gap:6px;margin:5px 0;font-size:12px'><span style='color:var(--accent)'>•</span><span>"+tips[t]+"</span></div>";return H.card(title,rows,String(tips.length),'cpu');}});
  PRO_FEATURES.push({key:"x_ux_all_ok",ar:"فحوص الحالة المأخوذة كعينة",en:"Sampled Status Checks",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar',title=ar?'فحوص الحالة المأخوذة كعينة':'Sampled Status Checks',items=[],w=Array.isArray(d.wifi)?d.wifi:[],bh=d.backhaul||{},cpu=H.num((d.cpu||{}).percent),mem=d.mem||{},mt=H.num(mem.total),ma=H.num(mem.available),sa=H.num((d.storage||{}).available),temp=H.num(d.temperature_c);items.push({l:ar?'الواي فاي':'WiFi',s:Array.isArray(d.wifi)?w.length>0:null});items.push({l:ar?'الاتصال':'Uplink',s:bh.online===true?true:bh.online===false?false:null});items.push({l:ar?'المعالج':'CPU',s:H.finite(cpu)?cpu<85:null});items.push({l:ar?'الذاكرة':'RAM',s:H.finite(mt)&&H.finite(ma)&&mt>0?(ma/mt)>0.1:null});items.push({l:ar?'التخزين':'Disk',s:H.finite(sa)?sa>0:null});items.push({l:ar?'الحرارة':'Temp',s:H.finite(temp)?temp<80:null});var known=0,pass=0,rows='';for(var i=0;i<items.length;i++){var it=items[i];if(it.s!==null){known++;if(it.s)pass++;}var c=it.s===null?'var(--muted)':it.s?'var(--excellent)':'var(--weak)',mark=it.s===null?'?':it.s?'✓':'!';rows+="<div style='display:flex;justify-content:space-between;font-size:12px;margin:4px 0'><span>"+it.l+"</span><span style='color:"+c+";font-weight:700'>"+mark+"</span></div>";}rows+="<small class='muted'>"+(ar?'? تعني أن القياس غير متوفر، ولا يُحسب نجاحاً.':'? means unavailable telemetry and is never counted as a pass.')+"</small>";return H.card(title,rows,known?pass+'/'+known:(ar?'غير معروف':'unknown'),'shield');}});
  PRO_FEATURES.push({key:"x_ux_weekly_digest",ar:"لقطة عدادات وقت التشغيل",en:"Runtime Counter Snapshot",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar',title=ar?'لقطة عدادات وقت التشغيل':'Runtime Counter Snapshot',tr=d.traffic||{},downloadBytes=H.num(tr.rx_bytes),uploadBytes=H.num(tr.tx_bytes),download=H.num(tr.rx_bps),upload=H.num(tr.tx_bps),up=H.num(d.uptime);downloadBytes=H.finite(downloadBytes)?downloadBytes:0;uploadBytes=H.finite(uploadBytes)?uploadBytes:0;download=H.finite(download)?download:0;upload=H.finite(upload)?upload:0;function row(lbl,val,col){return "<div style='display:flex;justify-content:space-between;font-size:12px;margin:5px 0'><span style='color:var(--muted)'>"+lbl+"</span><b style='color:"+(col||'var(--text)')+"'>"+val+"</b></div>";}if(!downloadBytes&&!uploadBytes&&!download&&!upload&&!H.finite(up))return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');var rows='';rows+=row(ar?'تنزيل منذ إعادة العداد':'Download since counter reset',H.bytes(downloadBytes),'var(--accent)');rows+=row(ar?'رفع منذ إعادة العداد':'Upload since counter reset',H.bytes(uploadBytes),'var(--primary)');rows+=row(ar?'التنزيل الآن':'Download now',H.bps(download),'var(--accent)');rows+=row(ar?'الرفع الآن':'Upload now',H.bps(upload),'var(--primary)');rows+=row(ar?'مدة تشغيل النظام':'System uptime',H.finite(up)?H.uptime(up):'—');rows+="<small class='muted'>"+(ar?'هذه ليست فترة أسبوعية: نافذة العداد '+H.esc(String(tr.counter_window||'since-interface-reset'))+'. قد تتغير عند إعادة الواجهة أو الطاقة؛ والطوبولوجيا '+(tr.topology_complete===true?'مكتملة':'جزئية')+'.':'This is not a weekly period. Counter window: '+H.esc(String(tr.counter_window||'since-interface-reset'))+'. It may reset after an interface or power restart; topology is '+(tr.topology_complete===true?'complete':'partial')+'.')+"</small>";return H.card(title,rows,tr.topology_complete===true?(ar?'طوبولوجيا مكتملة':'complete topology'):(ar?'طوبولوجيا جزئية':'partial topology'),'net');}});
  PRO_FEATURES.push({key:"x_ux_readiness_meters",ar:"قائمة الجاهزية",en:"Readiness Meters",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar';var title=ar?'قائمة الجاهزية':'Readiness Meters';var rows='';var any=false;function line(lbl,pct,col){return "<div style='margin:6px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+lbl+"</span><span style='color:"+col+"'>"+H.fmt(pct,0)+"%</span></div>"+H.bar(pct,100,col)+"</div>";}var cpu=H.num((d.cpu||{}).percent);if(H.finite(cpu)){any=true;var ch=H.clamp(100-cpu,0,100);rows+=line(ar?'فراغ المعالج':'CPU free',ch,ch>40?'var(--excellent)':ch>15?'var(--mid)':'var(--weak)');}var mem=d.mem||{};var mt=H.num(mem.total),ma=H.num(mem.available);if(H.finite(mt)&&H.finite(ma)&&mt>0){any=true;var mf=H.clamp(ma/mt*100,0,100);rows+=line(ar?'فراغ الذاكرة':'RAM free',mf,mf>30?'var(--excellent)':mf>12?'var(--mid)':'var(--weak)');}var st=d.storage||{};var stt=H.num(st.total),su=H.num(st.used);if(H.finite(stt)&&H.finite(su)&&stt>0){any=true;var sf=H.clamp((1-su/stt)*100,0,100);rows+=line(ar?'فراغ التخزين':'Disk free',sf,sf>25?'var(--excellent)':sf>10?'var(--mid)':'var(--weak)');}var w=Array.isArray(d.wifi)?d.wifi:[];var bs=0,bn=0;for(var i=0;i<w.length;i++){var b=H.num((w[i].survey||{}).busy_pct);if(H.finite(b)){bs+=b;bn++;}}if(bn>0){any=true;var af=H.clamp(100-bs/bn,0,100);rows+=line(ar?'فراغ الهواء':'Airtime free',af,af>50?'var(--excellent)':af>25?'var(--mid)':'var(--weak)');}if(!any)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'cpu');return H.card(title,rows,null,'cpu');}});
  PRO_FEATURES.push({key:"x_ux_action_items",ar:"تنبيهات الحقول المأخوذة كعينة",en:"Sampled Field Alerts",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar',title=ar?'تنبيهات الحقول المأخوذة كعينة':'Sampled Field Alerts',crit=0,warn=0,known=0,bh=d.backhaul||{};if(bh.online===false){crit++;known++;}else if(bh.online===true)known++;var cpu=H.num((d.cpu||{}).percent);if(H.finite(cpu)){known++;if(cpu>92)crit++;else if(cpu>80)warn++;}var mem=d.mem||{},mt=H.num(mem.total),ma=H.num(mem.available);if(H.finite(mt)&&H.finite(ma)&&mt>0){known++;var fr=ma/mt;if(fr<0.06)crit++;else if(fr<0.15)warn++;}var temp=H.num(d.temperature_c);if(H.finite(temp)){known++;if(temp>85)crit++;else if(temp>75)warn++;}var lat=H.num(d.latency_ms);if(H.finite(lat)){known++;if(lat>200)crit++;else if(lat>100)warn++;}var ifs=Array.isArray(d.interfaces)?d.interfaces:[];if(ifs.length)known++;for(var i=0;i<ifs.length;i++){var e=(H.num(ifs[i].rx_errors)||0)+(H.num(ifs[i].tx_errors)||0);if(e>1000){warn++;break;}}var total=crit+warn,col=crit>0?'var(--weak)':warn>0?'var(--mid)':'var(--muted)',sub=ar?(crit+' حرج · '+warn+' تحذير'):(crit+' critical · '+warn+' warning');var empty=known?(ar?'لا تنبيهات عتبات في الحقول المأخوذة كعينة':'No threshold alerts in sampled fields'):(ar?'لا توجد حقول متاحة للفحص':'No fields available to check');var body="<div style='text-align:center;padding:6px 0'><div style='font-size:28px;font-weight:700;color:"+col+"'>"+String(total)+"</div><div style='font-size:12px;color:var(--muted);margin-top:2px'>"+(total?sub:empty)+"</div></div>";return H.card(title,body,total?String(total):(known?known+(ar?' عينة':' sampled'):(ar?'غير معروف':'unknown')),'shield');}});
  PRO_FEATURES.push({key:"x_ux_verdict_tiles",ar:"لوحة القياسات",en:"Observation Tiles",cat:"Automation & UX",fn:function(d,H){var ar=H.lang==='ar',title=ar?'لوحة القياسات':'Observation Tiles',w=Array.isArray(d.wifi)?d.wifi:[],clients=0;for(var i=0;i<w.length;i++)clients+=(H.num(w[i].clients)||0);var bh=d.backhaul||{},tr=d.traffic||{},download=H.num(tr.rx_bps)||0,upload=H.num(tr.tx_bps)||0,ssum=0,scnt=0;for(var j=0;j<w.length;j++){var sts=Array.isArray(w[j].stations)?w[j].stations:[];for(var k=0;k<sts.length;k++){var sg=H.num(sts[k].signal_dbm);if(H.finite(sg)){ssum+=sg;scnt++;}}}var avg=scnt?ssum/scnt:null;function tile(lbl,val,col){return "<div class='traffic-box'><span>"+lbl+"</span><b style='color:"+col+"'>"+val+"</b></div>";}var upCol=bh.online===true?'var(--excellent)':bh.online===false?'var(--weak)':'var(--muted)',upTxt=bh.online===true?(ar?'متصل':'Up'):bh.online===false?(ar?'مقطوع':'Down'):(ar?'غير معروف':'Unknown'),sigCol=avg==null?'var(--muted)':(avg>-60?'var(--excellent)':avg>-72?'var(--good)':'var(--mid)');var body="<div class='grid two'>"+tile(ar?'الاتصال':'Uplink',upTxt,upCol)+tile(ar?'العملاء':'Clients',String(clients),clients>0?'var(--good)':'var(--muted)')+tile(ar?'تنزيل العملاء':'Client download',H.bps(download),'var(--accent)')+tile(ar?'رفع العملاء':'Client upload',H.bps(upload),'var(--primary)')+tile(ar?'متوسط RSSI':'Avg RSSI',avg==null?'—':H.fmt(avg,0)+' dBm',sigCol)+"</div>";return H.card(title,body,null,'net');}});
  PRO_FEATURES.push({key:"x_cap_link_capacity",ar:"قدرة الراديو المهيّأة",en:"Configured Radio Capability",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[],title=H.lang==='ar'?'قدرة الراديو المهيّأة':'Configured Radio Capability',rows='',known=0;for(var i=0;i<w.length;i++){var cap=H.configuredPhyCeiling2x2(w[i]);if(!cap)continue;known++;rows+="<div class='kv'><div><span>"+H.esc(w[i].band||'?')+' · '+H.esc(cap.mode)+"</span><b class='latin'>"+H.fmt(cap.mbps,cap.mbps<1000?1:0)+" Mbps</b></div><small class='muted latin'>"+cap.family+' · '+cap.width+"MHz · 2×2</small></div>";}if(!known)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');rows+="<small class='muted'>"+(H.lang==='ar'?'قدرة مهيّأة حسب عرض الراديو، وليست ذروة مقاسة أو goodput.':'Configured capacity for the radio width, not a measured peak or goodput.')+"</small>";return H.card(title,rows,known+'','net');}});
  PRO_FEATURES.push({key:"x_cap_stream_util",ar:"التدفقات في آخر لقطة PHY",en:"Streams in Last PHY Snapshot",cat:"Latency & Link Quality",fn:function(d,H){var title=H.lang==='ar'?'التدفقات في آخر لقطة PHY':'Streams in Last PHY Snapshot',counts={1:0,2:0,3:0,4:0},known=0,unknown=0;H.stationRateSnapshots(d,'tx').forEach(function(x){var n=x.info.nss;if(H.finite(n)&&n>=1&&n<=4){counts[n]++;known++;}else unknown++;});if(!known&&!unknown)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'wifi');var body='';for(var i=1;i<=4;i++){body+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px'><span>"+i+"SS</span><span>"+counts[i]+"</span></div>"+H.bar(counts[i],known||1,i>=2?'var(--excellent)':'var(--mid)')+"</div>";}if(unknown)body+="<small class='muted'>"+(H.lang==='ar'?'NSS غير مبلّغ: ':'NSS not reported: ')+unknown+"</small>";body+="<small class='muted' style='display:block'>"+(H.lang==='ar'?'من NSS الفعلي في تفاصيل الدرايفر، لا من عتبة Mbps.':'From actual NSS in driver details, never an Mbps threshold.')+"</small>";return H.card(title,body,known+'/'+(known+unknown),'wifi');}});
  PRO_FEATURES.push({key:"x_cap_mode_badges",ar:"أوضاع HE و VHT",en:"HE / VHT Modes",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[];var title=H.lang==='ar'?'أوضاع HE و VHT':'HE / VHT Modes';if(!w.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');var rows='';for(var i=0;i<w.length;i++){var r=w[i];var m=String(r.htmode||'').toUpperCase();var gen=m.indexOf('HE')===0?'Wi-Fi 6':m.indexOf('VHT')===0?'Wi-Fi 5':m.indexOf('HT')===0?'Wi-Fi 4':(H.lang==='ar'?'قديم':'legacy');var col=m.indexOf('HE')===0?'var(--excellent)':m.indexOf('VHT')===0?'var(--good)':m.indexOf('HT')===0?'var(--mid)':'var(--muted)';rows+="<div style='display:flex;justify-content:space-between;align-items:center;margin:7px 0;font-size:12px'><span>"+H.esc(r.band||'?')+"</span><span style='background:"+col+";color:#000;padding:2px 8px;border-radius:6px;font-weight:600'>"+H.esc(m||'—')+"</span><span style='color:var(--muted)'>"+gen+"</span></div>";}return H.card(title,rows,null,'signal');}});
  PRO_FEATURES.push({key:"x_cap_band_phy",ar:"قدرة PHY المهيّأة لكل نطاق",en:"Configured PHY per Band",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[],title=H.lang==='ar'?'قدرة PHY المهيّأة لكل نطاق':'Configured PHY per Band',rows='',known=0;for(var i=0;i<w.length;i++){var cap=H.configuredPhyCeiling2x2(w[i]);if(!cap)continue;known++;rows+="<div style='margin:7px 0;display:flex;justify-content:space-between;gap:8px;font-size:12px'><span>"+H.esc(w[i].band||'?')+' · '+H.esc(cap.mode)+"</span><b class='latin' style='color:var(--accent)'>"+H.fmt(cap.mbps,cap.mbps<1000?1:0)+" Mbps</b></div>";}if(!known)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');rows+="<small class='muted'>"+(H.lang==='ar'?'لا تُجمع معدلات PHY للعملاء؛ هذه قدرة 2×2 المهيّأة لكل راديو وليست حركة بيانات.':'Client PHY rates are not summed; this is each radio’s configured 2×2 capability, not data traffic.')+"</small>";return H.card(title,rows,known+'','net');}});
  PRO_FEATURES.push({key:"x_cap_headroom",ar:"هامش النقل المقاس",en:"Measured Throughput Headroom",cat:"Latency & Link Quality",fn:function(d,H){var title=H.lang==='ar'?'هامش النقل المقاس':'Measured Throughput Headroom';var note=H.lang==='ar'?'يتطلب حساب الهامش اختبار نقل فعلياً تحت حمل مستمر. لا يُحسب من آخر معدل PHY لعميل خامل.':'Headroom requires an active sustained throughput test. It is not computed from an idle client’s last PHY rate.';return H.card(title,"<div class='empty'>"+note+"</div>",H.lang==='ar'?'يحتاج اختباراً':'test required','signal');}});
  PRO_FEATURES.push({key:"x_cap_phy_eff",ar:"دلالة قياسات PHY",en:"PHY Telemetry Semantics",cat:"Latency & Link Quality",fn:function(d,H){var snapshots=H.stationRateSnapshots(d,'tx'),parsed=0,expected=0;snapshots.forEach(function(x){if(x.info.raw)parsed++;if(H.finite(H.num(x.station.expected_mbps)))expected++;});var title=H.lang==='ar'?'دلالة قياسات PHY':'PHY Telemetry Semantics';if(!snapshots.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'wifi');var body="<div class='kv'><div><span>"+(H.lang==='ar'?'تفاصيل آخر PHY':'Last PHY details')+"</span><b>"+parsed+'/'+snapshots.length+"</b></div><div><span>"+(H.lang==='ar'?'تقدير throughput من الدرايفر':'Driver throughput estimate')+"</span><b>"+expected+'/'+snapshots.length+"</b></div></div><small class='muted'>"+(H.lang==='ar'?'المقياسان منفصلان ولا تُقسم لقطة PHY على تقدير النقل لإصدار درجة كفاءة.':'The metrics are separate; a last PHY snapshot is not divided by a throughput estimate to invent an efficiency score.')+"</small>";return H.card(title,body,parsed+'/'+snapshots.length,'wifi');}});
  PRO_FEATURES.push({key:"x_cap_width_capacity",ar:"قدرة 2×2 حسب عرض القناة",en:"2×2 Capability by Channel Width",cat:"Latency & Link Quality",fn:function(d,H){var w=Array.isArray(d.wifi)?d.wifi:[],title=H.lang==='ar'?'قدرة 2×2 حسب عرض القناة':'2×2 Capability by Channel Width',rows='',known=0;for(var i=0;i<w.length;i++){var cap=H.configuredPhyCeiling2x2(w[i]);if(!cap)continue;known++;rows+="<div style='margin:7px 0'><div style='display:flex;justify-content:space-between;font-size:12px;gap:8px'><span>"+H.esc(w[i].band||'?')+' · '+cap.width+'MHz · '+H.esc(cap.family)+"</span><b class='latin' style='color:var(--accent)'>"+H.fmt(cap.mbps,cap.mbps<1000?1:0)+" Mbps</b></div></div>";}if(!known)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'signal');rows+="<small class='muted'>"+(H.lang==='ar'?'سقف PHY نظري مهيّأ لتيارين؛ ليس throughput ولا قياساً هوائياً.':'Configured theoretical PHY ceiling for two streams; not throughput or an over-air measurement.')+"</small>";return H.card(title,rows,known+'','signal');}});
  PRO_FEATURES.push({key:"x_cap_ceiling_rank",ar:"ترتيب آخر لقطات PHY",en:"Last PHY Snapshot by Client",cat:"Latency & Link Quality",fn:function(d,H){var title=H.lang==='ar'?'ترتيب آخر لقطات PHY':'Last PHY Snapshot by Client',arr=H.stationRateSnapshots(d,'tx');if(!arr.length)return H.card(title,"<div style='color:var(--muted)'>—</div>",null,'net');arr.sort(function(a,b){return b.info.rate-a.info.rate;});var rows='';arr.slice(0,6).forEach(function(x){var p=[H.fmt(x.info.rate,1)+' Mbps'];if(x.info.family)p.push(x.info.family);if(H.finite(x.info.mcs))p.push('MCS '+x.info.mcs);if(H.finite(x.info.nss))p.push(x.info.nss+'SS');var age=H.stationInactiveAge(x.station.inactive_ms);if(age)p.push('inactive '+age);rows+="<div style='display:flex;justify-content:space-between;gap:8px;margin:7px 0;font-size:12px'><span>"+H.esc(x.station.ip||x.station.mac||'?')+"</span><span class='latin'>"+H.esc(p.join(' · '))+"</span></div>";});rows+="<small class='muted'>"+(H.lang==='ar'?'ترتيب آخر لقطة تشخيصية فقط؛ لا توجد مقارنة بسقف عالمي ولا حكم throughput.':'Diagnostic last-snapshot ordering only; no global ceiling comparison or throughput verdict.')+"</small>";return H.card(title,rows,String(arr.length),'net');}});
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
    var priorSuspendHistory = state.suspendHistory;
    state.suspendHistory = priorSuspendHistory || snapshotIsStale(data);
    try {
    if (!PRO_FEATURES.length) return sectionHead(tr("insights"), "Pro", "") + '<div class="empty">' + tr("loading") + '</div>';
    data = sanitizeData(data);
    var cats = {};
    PRO_FEATURES.forEach(function (f) { (cats[f.cat] = cats[f.cat] || []).push(f); });
    // Render one explicit category at a time. The previous all-at-once view created
    // 86 live cards and an extremely long, unstable page on phones.
    var ordered = PRO_CAT_ORDER.filter(function (c) { return cats[c]; });
    Object.keys(cats).forEach(function (c) { if (ordered.indexOf(c) < 0) ordered.push(c); });
    if (!cats[state.insightCategory]) state.insightCategory = ordered[0] || "System & Health";
    var selected = state.insightCategory;
    var wifi = data.wifi || [], clients = mergeDevices(data).length;
    var cpu = num((data.cpu || {}).percent), temp = num(data.temperature_c);
    // Do not double-count bridge, Ethernet-master and Wi-Fi counters as DSA
    // port faults.  Report the physical CR6608 switch ports only, separate
    // errors from ordinary boot-lifetime drops, and label the time scope.
    var dsaCounters = (data.interfaces || []).reduce(function (total, row) {
      if (!row || !/^(?:wan|lan[1-3])$/.test(String(row.name || ""))) return total;
      total.errors += (num(row.rx_errors) || 0) + (num(row.tx_errors) || 0);
      total.drops += (num(row.rx_dropped) || 0) + (num(row.tx_dropped) || 0);
      return total;
    }, { errors:0, drops:0 });
    var retries = 0, packets = 0, failed = 0;
    wifi.forEach(function (radio) { (radio.stations || []).forEach(function (sta) {
      retries += num(sta.tx_retries) || 0; packets += num(sta.tx_packets) || 0; failed += num(sta.tx_failed) || 0;
    }); });
    var retryPct = packets > 0 ? clamp(retries / packets * 100, 0, 100) : null;
    function summary(label, value, hint, tone) {
      return '<div class="insight-summary-item ' + (tone || "") + '"><span>' + esc(label) + '</span><b class="latin">' + esc(value) + '</b><small>' + esc(hint || "") + '</small></div>';
    }
    var out = sectionHead(tr("insights"), state.lang === "ar" ? "مؤشرات مركزة حسب المجال" : "Focused operational analytics", PRO_FEATURES.length + "");
    out += '<div class="insight-summary">' +
      summary(state.lang === "ar" ? "العملاء" : "Clients", String(clients), wifi.length + " radios", clients ? "ok" : "") +
      summary(state.lang === "ar" ? "المعالج" : "CPU", finite(cpu) ? fmt(cpu, 0) + "%" : "—", state.lang === "ar" ? "الحمل اللحظي" : "current load", finite(cpu) && cpu > 85 ? "bad" : "ok") +
      summary(state.lang === "ar" ? "الحرارة" : "Temperature", finite(temp) ? fmt(temp, 0) + " °C" : "—", state.lang === "ar" ? "حرارة النظام" : "system sensor", finite(temp) && temp > 80 ? "bad" : "ok") +
      summary(state.lang === "ar" ? "إعادة الإرسال" : "WiFi retries", finite(retryPct) ? fmt(retryPct, 1) + "%" : "—", failed + " failed", finite(retryPct) && retryPct > 20 ? "warn" : "ok") +
      summary(state.lang === "ar" ? "أخطاء DSA" : "DSA errors", String(dsaCounters.errors), state.lang === "ar" ? "منذ إعادة ضبط الواجهة" : "since interface reset", dsaCounters.errors ? "bad" : "ok") +
      summary(state.lang === "ar" ? "إسقاطات DSA" : "DSA drops", String(dsaCounters.drops), state.lang === "ar" ? "منذ إعادة ضبط الواجهة" : "since interface reset", dsaCounters.drops > 1000 ? "warn" : "ok") +
      '</div>';
    out += '<div class="insight-tabs" role="tablist">' + ordered.map(function (category) {
      var label = state.lang === "ar" ? (PRO_CAT_AR[category] || category) : category;
      return '<button type="button" role="tab" aria-selected="' + (category === selected ? "true" : "false") + '" class="' + (category === selected ? "active" : "") + '" data-insight-category="' + esc(category) + '"><span>' + esc(label) + '</span><b>' + cats[category].length + '</b></button>';
    }).join("") + '</div>';
    var seen = {};
    var selectedLabel = state.lang === "ar" ? (PRO_CAT_AR[selected] || selected) : selected;
    out += '<div class="insight-category-head"><h3>' + esc(selectedLabel) + '</h3><span>' + cats[selected].length + '</span></div><div class="grid pro-grid">';
    cats[selected].forEach(function (f) {
      if (seen[f.key]) return; seen[f.key] = 1;
      var html = "";
      try { html = f.fn(data, H); } catch (e) { html = ""; }
      if (html) out += html;
    });
    return out + '</div>';
    } finally {
      state.suspendHistory = priorSuspendHistory;
    }
  }
  function renderOverviewLite(data, rates) {
    var w24 = wifiBand(data, "2.4G"), w5 = wifiBand(data, "5G"), back = data.backhaul || {};
    var complete = !!(data.traffic && data.traffic.topology_complete === true);
    var throughput = '<div class="grid two"><div class="traffic-box"><span>↓ ' + esc(tr("download")) + '</span><b class="latin">' + bps(rates.rx) + '</b></div><div class="traffic-box"><span>↑ ' + esc(tr("upload")) + '</span><b class="latin">' + bps(rates.tx) + '</b></div></div>' +
      (complete ? "" : '<p class="ctl-note">' + esc(trafficCoverageNote(data)) + '</p>');
    var radios = [w24, w5].filter(Boolean).map(function (w) {
      var p = w.txpower || {},
        applied = num(w.applied_dbm != null ? w.applied_dbm : p.applied_dbm),
        requested = num(w.requested_dbm != null ? w.requested_dbm : p.requested_dbm);
      return '<div class="kv"><div><span>' + esc(w.band || "Wi-Fi") + ' · CH ' + esc(w.channel || "-") + '</span><b class="latin">' + (finite(applied) ? fmt(applied, 0) + ' dBm' : '—') + '</b></div><small>' + esc(w.ssid || w.iface || "") + ' · ' + esc(w.htmode || "") + ' · ' + (w.clients || 0) + ' clients · req ' + (finite(requested) ? fmt(requested, 0) : '—') + '</small></div>';
    }).join("");
    var status = '<div class="kv"><div><span>' + tr("internet") + '</span><b>' + esc(back.online ? (back.device || tr("online")) : tr("lanOnly")) + '</b></div></div>' +
      '<div class="kv"><div><span>' + tr("deviceCount") + '</span><b>' + esc(String(mergeDevices(data).length)) + '</b></div></div>';
    var identity = data.identity || {}, identityEnabled = identity.enabled !== false;
    var identityBody = '<div class="kv"><div><span>' + (state.lang === "ar" ? "هوية Neighbors" : "Neighbors identity") + '</span><b>' + esc(identity.neighbor_identity || identity.device_name || data.hostname || "CR6608") + '</b></div>' +
      '<div><span>' + (state.lang === "ar" ? "الحالة" : "State") + '</span><b style="color:' + (identityEnabled && identity.state === "active" ? "var(--excellent)" : "var(--mid)") + '">' + esc(identityEnabled ? (identity.state || "starting") : "disabled") + '</b></div>' +
      '<div><span>' + (state.lang === "ar" ? "البروتوكول" : "Protocol") + '</span><b class="latin">MNDP · UDP 5678</b></div></div>';
    return sectionHead(tr("overview"), tr("subtitle"), nowTime()) + '<div class="grid two">' +
      card(tr("networkTitle"), throughput, snapshotIsStale(data) ? cachedStatusLabel() : (complete ? "live" : (state.lang === "ar" ? "حواف Wi-Fi فقط" : "Wi-Fi edges only")), "net") +
      card(state.lang === "ar" ? "الراديو والبث" : "Radios & TX", radios || '<div class="empty">—</div>', "iw", "wifi") +
      card(state.lang === "ar" ? "حالة الاتصال" : "Connection status", status, snapshotIsStale(data) ? cachedStatusLabel() : (data.ok ? tr("online") : tr("offline")), "bolt") +
      card(state.lang === "ar" ? "هوية العميل في الميكروتك" : "MikroTik customer identity", identityBody, identityEnabled ? "MNDP" : "off", "device") +
      renderEvents(data) + '</div>';
  }
  function renderLiveSection(id, data, rates, force) {
    if (force !== true && data._liveLite === true && /^(devices|wifi)$/.test(id) && $(id) && $(id).innerHTML) return;
    if (id === "overview") $("overview").innerHTML = renderOverviewLite(data, rates);
    else if (id === "network") $("network").innerHTML = renderNetwork(data, rates);
    else if (id === "devices") $("devices").innerHTML = renderDevices(data);
    else if (id === "wifi") $("wifi").innerHTML = renderWifi(data);
    else if (id === "insights" && $("insights") && (!data.lite || !$("insights").innerHTML)) $("insights").innerHTML = renderProInsights(data);
    else if (id === "system") $("system").innerHTML = renderSystem(data);
    else if (id === "actions") $("actions").innerHTML = renderActions();
    var root = $(id);
    if (root) {
      flushScheduledCharts(root);
      bindDynamic(root);
    }
  }
  function render(data, forceLiveSection) {
    var staleSnapshot = snapshotIsStale(data);
    var liveCounters = !staleSnapshot || data._liveLite === true;
    state.suspendHistory = staleSnapshot;
    try {
    state.latest = data;
    window.__lastApi = data;
    if (!staleSnapshot) detectNewDevices(data);
    var rates = trafficRates(data, liveCounters);
    // A valid cached response proves the management/API path is reachable.
    // Staleness is shown separately and must not be recorded as an outage.
    updateAvailability(!!data.ok);
    pushHistory("latency", state.lastLatency || 0, 60, liveCounters);
    pushHistory("rx", rates.rx, 60, liveCounters); pushHistory("tx", rates.tx, 60, liveCounters);
    renderKpis(data, rates, liveCounters);
    var connectionText = data.ok ? tr("online") : tr("offline");
    if (staleSnapshot) {
      connectionText = state.lang === "ar" ? "بيانات مخزنة · جارٍ التحديث" : "Cached data · updating";
    }
    $("connectionState").textContent = connectionText;
    $("statusPulse").classList.toggle("warn", staleSnapshot);
    $("statusPulse").classList.toggle("bad", !data.ok);
    if ($("connectionChip")) {
      $("connectionChip").classList.toggle("ok", !!data.ok && !staleSnapshot);
      $("connectionChip").classList.toggle("warn", staleSnapshot);
      $("connectionChip").classList.toggle("bad", !data.ok);
    }
    if ($("snapshotWarning")) {
      $("snapshotWarning").hidden = !staleSnapshot;
      $("snapshotWarning").textContent = staleSnapshot
        ? (state.lang === "ar"
          ? "هذه لقطة مخزنة عمرها " + uptime(Math.max(0, num(data.snapshot_age_s) || 0)) + ". القيم الحية قيد التحديث ولا تُعامل كحالة آنية."
          : "This cached snapshot is " + uptime(Math.max(0, num(data.snapshot_age_s) || 0)) + " old. Live values are being refreshed and are not presented as current.")
        : "";
    }
    $("sideTitle").textContent = "Smart AP";
    $("sideStatus").textContent = (data.hostname || "OpenWrt") + " · " +
      (staleSnapshot ? (state.lang === "ar" ? "لقطة مخزنة" : "cached snapshot") : nowTime());
    renderLiveSection(document.body.dataset.activeSection || "overview", data, rates, forceLiveSection === true);
    setTimeout(loadActiveControl, 0);
    saveHistories();
    } finally {
      state.suspendHistory = false;
    }
  }
  async function loadData(forceFull) {
    if (!state.session) return;
    if (forceFull === true) state.fullRefreshRequested = true;
    if (state._pollBusy) {
      // A user/navigation-forced refresh supersedes the older read. Normal
      // interval ticks are coalesced so a slow CGI can never create a queue.
      if (forceFull === true) cancelDataRead();
      return;
    }
    state._pollBusy = true;
    var requestedFull = state.fullRefreshRequested === true;
    state.fullRefreshRequested = false;
    var generation = ++state.dataGeneration;
    var sessionAtStart = state.session;
    var start = performance.now();
    var ctrl = (typeof AbortController !== "undefined") ? new AbortController() : null;
    state.dataController = ctrl;
    try {
      var active = document.body.dataset.activeSection || "overview";
      var detailed = /^(network|devices|wifi|insights)$/.test(active);
      // The 3-second overview uses only procfs counters. Expensive iw/ubus snapshots
      // are refreshed every 15s on detailed pages and every 60s on the overview.
      // Bootstrap with the procfs-only response so the first phone viewport is
      // useful immediately, then fill in the hardware snapshot in the background.
      var bootstrapLite = !state.latest && !requestedFull;
      var latestIsStale = snapshotIsStale(state.latest);
      var fullDue = !!state.latest && (latestIsStale
        ? Date.now() >= (state.nextStaleRetryAt || 0)
        : Date.now() - state.lastFullAt >= (detailed ? 15000 : 60000));
      var full = requestedFull || (!bootstrapLite && fullDue);
      var res = await fetchWithTimeout(authUrl(full ? API : API + "?lite=1"), { credentials:"same-origin", cache:"no-store", headers:authHeaders(), signal: ctrl ? ctrl.signal : undefined }, 15000);
      var text = await res.text();
      if (!isDataRequestCurrent(generation, sessionAtStart)) return;
      state.lastLatency = Math.max(1, performance.now() - start);
      if (res.status === 403) return requireLogin(tr("sessionExpired"));
      if (!res.ok) throw new Error("HTTP " + res.status);
      var data = JSON.parse(text);
      if (!data || data.ok !== true) throw new Error((data && data.error) || "invalid API response");
      var isLite = data.lite === true;
      var staleSnapshot = !isLite && snapshotIsStale(data);
      if (isLite && state.latest) {
        data = Object.assign({}, state.latest, data);
        data._liveLite = true;
        if (snapshotIsStale(data)) {
          var ageAtReceipt = Math.max(0, num(data._snapshotAgeAtReceipt) || num(data.snapshot_age_s) || 0);
          var receivedAt = num(data._snapshotReceivedAt) || Date.now();
          data.snapshot_age_s = ageAtReceipt + Math.max(0, Math.floor((Date.now() - receivedAt) / 1000));
        }
      } else if (!isLite && !staleSnapshot) {
        data._liveLite = false;
        state.lastFullAt = Date.now();
        state._staleRefreshAttempts = 0;
        state.nextStaleRetryAt = 0;
        clearStaleRetry();
      } else if (staleSnapshot) {
        data._liveLite = false;
        data._snapshotAgeAtReceipt = Math.max(0, num(data.snapshot_age_s) || 0);
        data._snapshotReceivedAt = Date.now();
        state._staleRefreshAttempts = (state._staleRefreshAttempts || 0) + 1;
        // Keep four quick retries so a normal <=10-second collector is observed,
        // then back off without ever reclassifying stale data as fresh.
        var staleDelay = state._staleRefreshAttempts <= 4 ? 3000 :
          [6000, 12000, 24000, 30000][Math.min(3, state._staleRefreshAttempts - 5)];
        state.nextStaleRetryAt = Date.now() + staleDelay;
        scheduleStaleRetry(staleDelay);
      }
      state.apiFails = 0; state._apiToastShown = false;   // recovered
      render(data);
      if (bootstrapLite) setTimeout(function () { loadData(true); }, 0);
    } catch (e) {
      if (!isDataRequestCurrent(generation, sessionAtStart) || isAbortError(e)) return;
      if (requestedFull) state.fullRefreshRequested = true;
      // Transient network hiccups (slow CGI, a dropped poll) must NOT spam the
      // Events card or persist across reloads. Only surface after 3 consecutive
      // failures, and never write these to localStorage.
      state.apiFails = (state.apiFails || 0) + 1;
      updateAvailability(false);
      if (state.apiFails >= 3 && !state._apiToastShown) {
        state._apiToastShown = true;
        toast(state.lang === "ar" ? "تعذّر الوصول للوحة — إعادة المحاولة تلقائياً" : "Panel unreachable — retrying");
      }
    } finally {
      var superseded = generation !== state.dataGeneration;
      if (state.dataController === ctrl) state.dataController = null;
      state._pollBusy = false;
      // A forced refresh requested while another poll was in flight is never
      // dropped.  Run it immediately after that older request completes.
      if (state.fullRefreshRequested && state.session && (!requestedFull || superseded))
        setTimeout(function () { loadData(); }, 0);
    }
  }
  async function speedTest() {
    var bytesRead = 0, start = performance.now(), pings = [];
    for (var i = 0; i < 5; i++) {
      var t0 = performance.now();
      var r = await fetchWithTimeout(authUrl(API + "?speed=" + i), { credentials:"same-origin", cache:"no-store", headers:authHeaders() }, API_TIMEOUT_MS);
      if (r.status === 403) { requireLogin(tr("sessionExpired")); return; }
      var tx = await r.text();
      pings.push(performance.now() - t0);
      bytesRead += tx.length;
    }
    var ms = performance.now() - start, avg = pings.reduce(function (a,b) { return a+b; },0) / pings.length;
    var jitter = Math.sqrt(pings.map(function (x) { return Math.pow(x - avg, 2); }).reduce(function (a,b) { return a+b; },0) / pings.length);
    toast(tr("localTest") + ": " + fmt(avg,0) + "ms, jitter " + fmt(jitter,0) + "ms, " + bps(bytesRead / (ms / 1000)));
  }
  async function action(name, button) {
    if (name === "refresh") return loadData(true);
    if (name === "speedtest") return speedTest();
    if (name === "reboot" || name === "reconnect" || name === "wifi_radio0" || name === "wifi_radio1") {
      var now = Date.now();
      if (!state.pendingAction || state.pendingAction.name !== name || state.pendingAction.until < now) {
        state.pendingAction = { name:name, until:now + 6000 };
        return toast(tr("confirmAgain"));
      }
      state.pendingAction = null;
    }
    try {
      var result = await postJsonLocked(ACTION, {
        credentials:"same-origin",
        cache:"no-store",
        headers:authHeaders({ "Content-Type":"application/x-www-form-urlencoded" }),
        body:"action=" + encodeURIComponent(name) + "&confirm=1&" + sidQuery()
      }, dashboardActionTimeoutMs(name), button);
      var r = result.response;
      if (r.status === 403) return requireLogin(tr("sessionExpired"));
      var j = result.data;
      toast(j.message || tr("ok"));
      event(name + ": " + (j.message || ""));
      // Mutation generation changed even when an action reports a partial
      // failure.  Force a full read instead of merging lite data for 60s.
      queueFullRefresh(name === "reboot" ? 6500 : 250);
    } catch (e) {
      if (dashboardActionMayReconnect(name) && controlPostNeedsRecovery(e)) await waitForRouterReachable(name, button);
      else toast(e.message);
    }
  }
  function activeControlSection() {
    var active = document.body.dataset.activeSection;
    if (active === "quick") return "wizard";
    if (active === "isolation") return "isolation";
    var groups = adminGroups(), group = groups[active];
    if (!group) return "";
    var idx = state.adminSelection[active] || 0;
    return (group.items[idx] || group.items[0] || [])[0] || "";
  }
  function controlParams(section, actionName, button) {
    var params = "";
    if (actionName === "keep_changes" || actionName === "rollback_last") {
      var guardedToken = state.controlTokens[section] || "";
      if (/^[0-9a-f]{32}$/.test(guardedToken))
        params += "&rollback_token=" + encodeURIComponent(guardedToken);
    }
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
  function controlActionAffectsSnapshot(actionName) {
    return !!actionName && !/^(sync_time|eeprom_status|eeprom_backup|eeprom_boost|eeprom_restore|create_config_backup|ping|traceroute|nslookup|run_selftest|secscan_run)$/.test(actionName);
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
    var recoveryContext = { targetUrl:"" };
    if (actionName) {
      recoveryContext = controlRecoveryContext(section, actionName, params);
      if (recoveryContext.targetUrl) state.controlRecoveryTargets[section] = recoveryContext;
      else if (/^(keep_changes|rollback_last)$/.test(actionName) && state.controlRecoveryTargets[section])
        recoveryContext = state.controlRecoveryTargets[section];
    }
    if (!actionName && state.postLock) {
      delete box.dataset.loaded;
      setTimeout(function () {
        if (!state.postLock && activeControlSection() === section) loadControl(section);
      }, 250);
      return;
    }
    if (actionName && state.postLock) return toast(postBusyError().message);
    cancelControlRead();
    var generation = state.controlGeneration;
    var readController = null;
    if (!actionName && typeof AbortController !== "undefined") {
      readController = new AbortController();
      state.controlReadController = readController;
      state.controlReadBox = box;
    }
    box.dataset.loaded = "1";
    box.className = "ctl-status";
    box.textContent = actionName ? "Running control..." : "Loading router controls...";
    var stopProgress = actionName ? startControlProgress(box, actionName) : function () {};
    try {
      var url = authUrl(CTL + "?section=" + encodeURIComponent(section));
      var fetchOptions = { credentials:"same-origin", cache:"no-store", headers:authHeaders() };
      var res, data;
      if (actionName) {
        url = CTL;
        fetchOptions = {
          credentials:"same-origin",
          cache:"no-store",
          headers:authHeaders({ "Content-Type":"application/x-www-form-urlencoded" }),
          body:"section=" + encodeURIComponent(section) + "&action=" + encodeURIComponent(actionName) + (params || "") + "&" + sidQuery() + "&_=" + Date.now()
        };
        var posted = await postJsonLocked(url, fetchOptions, controlActionTimeoutMs(section, actionName), button);
        res = posted.response;
        data = posted.data;
      } else {
        fetchOptions.signal = readController ? readController.signal : undefined;
        res = await fetchWithTimeout(url, fetchOptions, API_TIMEOUT_MS);
        data = await res.json();
        if (!isControlRequestCurrent(generation, section, box)) return;
      }
      if (res.status === 403) return requireLogin(tr("sessionExpired"));
      if (controlActionAffectsSnapshot(actionName)) queueFullRefresh(250);
      // A failed POST must NOT repaint the panel to a one-line error (that discards
      // the user's typed form and, for guarded actions, erases the Keep/Rollback
      // buttons of a still-armed transaction). Surface the message and re-fetch the
      // authoritative device state instead.
      if (actionName && data && data.ok === false) {
        if (data.summary || data.text) toast(data.summary || data.text);
        if (actionName === "keep_changes" || actionName === "rollback_last") return;
        delete box.dataset.loaded;
        return loadControl(section);
      }
      if (data && data.ok === true && data.confirmation_ready === true && /^[0-9a-f]{32}$/.test(data.rollback_token || ""))
        state.controlTokens[section] = data.rollback_token;
      if (data && data.ok && (actionName === "keep_changes" || actionName === "rollback_last")) {
        delete state.controlTokens[section];
        delete state.controlRecoveryTargets[section];
        if (data.summary) toast(data.summary);
        delete box.dataset.loaded;
        return loadControl(section);
      }
      state.controlCache[section] = data;
      if (data && data.ok && actionName === "save_royal" && section === "wizard") {
        if (isControlRequestCurrent(generation, section, box)) {
          if (data.summary) toast(data.summary);
          return loadControl(section);
        }
        if (activeControlSection() !== section) delete box.dataset.loaded;
        return;
      }
      if (!isControlRequestCurrent(generation, section, box)) {
        if (activeControlSection() !== section) delete box.dataset.loaded;
        return;
      }
      box.className = "";
      box.innerHTML = renderControlData(section, data);
      if (section === "wizard") syncWizardMode();
      if (actionName && data.summary) toast(data.summary);
      bindDynamic(box);
    } catch (e) {
      stopProgress();
      if (!isControlRequestCurrent(generation, section, box) || (!actionName && isAbortError(e))) {
        if (activeControlSection() !== section) delete box.dataset.loaded;
        return;
      }
      if (actionName && controlPostNeedsRecovery(e) && await recoverControlAction(section, actionName, box, recoveryContext)) return;
      delete box.dataset.loaded;
      if (actionName === "apply_isolation" && section === "isolation") {
        queueFullRefresh(4500);
        box.className = "ctl-status";
        box.textContent = state.lang === "ar" ? "يُعاد تحميل الشبكة، جارٍ تحديث حالة المنافذ…" : "Network is reloading; refreshing port status…";
        setTimeout(function () { loadControl(section); }, 4500);
        return;
      }
      box.className = "ctl-status";
      box.textContent = "Control API error: " + e.message;
    } finally {
      stopProgress();
      if (state.controlReadController === readController) {
        state.controlReadController = null;
        state.controlReadBox = null;
      }
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
  function quickSafeApplyBox() {
    showSection("quick");
    // showSection may start a wizard GET. Invalidate it before painting the
    // authoritative token so a late response cannot erase Keep/Rollback.
    cancelControlRead();
    return $("ctl_wizard");
  }
  async function runDeviceAccessAction(mac, act, button) {
    try {
      var result = await postJsonLocked(CTL, { credentials:"same-origin", cache:"no-store",
        headers:authHeaders({ "Content-Type":"application/x-www-form-urlencoded" }),
        body:"section=devices&action=" + encodeURIComponent(act) + "&mac=" + encodeURIComponent(mac) + "&confirm=1&" + sidQuery() + "&_=" + Date.now() }, 20000, button);
      var response = result.response;
      if (response.status === 403) return requireLogin(tr("sessionExpired"));
      var data = result.data || {};
      var hasPendingToken = data.ok === true && data.confirmation_ready === true && /^[0-9a-f]{32}$/.test(data.rollback_token || "");
      if (data.ok && !hasPendingToken) throw new Error("Safe Apply confirmation token missing");
      if (data.ok && hasPendingToken) {
        var pendingBox = quickSafeApplyBox();
        if (!presentPendingApply("wizard", pendingBox, data))
          throw new Error("Safe Apply confirmation could not be displayed");
      }
      toast(data.summary || data.text || tr("ok"));
      if (data.ok) event((act === "block_mac" ? "Block " : "Allow ") + mac);
      queueFullRefresh(400);
    } catch (e) {
      if (controlPostNeedsRecovery(e)) {
        var recoveryBox = quickSafeApplyBox();
        if (recoveryBox && await recoverControlAction("wizard", act, recoveryBox)) return;
      }
      toast(e.message);
    }
  }
  function dynamicId(root, id) {
    var element = $(id);
    if (!element) return null;
    return root === document || root === element || (typeof root.contains === "function" && root.contains(element)) ? element : null;
  }
  function bindDynamic(rootNode) {
    var root = rootNode && typeof rootNode.querySelectorAll === "function" ? rootNode : document;
    Array.prototype.forEach.call(root.querySelectorAll("[data-insight-category]"), function (button) {
      button.onclick = function () {
        state.insightCategory = button.dataset.insightCategory || "System & Health";
        localStorage.setItem(LS + "insightCategory", state.insightCategory);
        if (state.latest && $("insights")) {
          $("insights").innerHTML = renderProInsights(state.latest);
          bindDynamic($("insights"));
        }
      };
    });
    Array.prototype.forEach.call(root.querySelectorAll("[data-action]"), function (b) { b.onclick = function () { action(b.dataset.action, b); }; });
    Array.prototype.forEach.call(root.querySelectorAll("[data-admin-group]"), function (b) {
      b.onclick = function () {
        var groupId = b.dataset.adminGroup, group = adminGroups()[groupId], idx = Number(b.dataset.adminIndex) || 0;
        if (!group) return;
        state.adminSelection[groupId] = idx;
        Array.prototype.forEach.call(root.querySelectorAll('[data-admin-group="' + groupId + '"]'), function (x) { x.classList.toggle("active", x === b); });
        var panel = $(groupId + "Detail");
        if (panel) panel.innerHTML = renderBranchDetail(groupId, group.items[idx]);
        if (panel) bindDynamic(panel);
        loadControl(group.items[idx][0]);
      };
    });
    Array.prototype.forEach.call(root.querySelectorAll("[data-ctl-refresh]"), function (b) {
      b.onclick = function () { loadControl(b.dataset.ctlRefresh); };
    });
    Array.prototype.forEach.call(root.querySelectorAll("[data-ctl-action]"), function (b) {
      b.onclick = function () {
        var section = b.dataset.ctlSection, actionName = b.dataset.ctlAction;
        if (actionName === "logout") return logout();
        loadControl(section, actionName, controlParams(section, actionName, b), b);
      };
    });
    Array.prototype.forEach.call(root.querySelectorAll('[data-control-section="wizard"] [data-ctl-field]'), function (i) {
      i.oninput = syncWizardMode;
      i.onchange = syncWizardMode;
    });
    Array.prototype.forEach.call(root.querySelectorAll(".txpower-control"), function (box) {
      var number = box.querySelector("[data-ctl-field]"), range = box.querySelector("[data-tx-range]");
      if (!number || !range) return;
      range.oninput = function () { number.value = range.value; number.dispatchEvent(new Event("input", {bubbles:true})); };
      number.oninput = function () {
        var value = Number(number.value);
        if (isFinite(value) && value >= Number(range.min) && value <= Number(range.max)) range.value = String(value);
        if (number.closest('[data-control-section="wizard"]')) syncWizardMode();
      };
    });
    Array.prototype.forEach.call(root.querySelectorAll("[data-tx-preset]"), function (button) {
      button.onclick = function () {
        var panel = button.closest(".txpower-control"), number = panel && panel.querySelector("[data-ctl-field]"), range = panel && panel.querySelector("[data-tx-range]");
        if (!number || !range) return;
        number.value = button.dataset.value; range.value = button.dataset.value;
        number.dispatchEvent(new Event("input", {bubbles:true}));
      };
    });
    function bindTabKeyboard(button, selector, activate) {
      button.onkeydown = function (ev) {
        if (["ArrowLeft", "ArrowRight", "Home", "End"].indexOf(ev.key) < 0) return;
        var tabs = Array.prototype.slice.call(root.querySelectorAll(selector));
        var current = tabs.indexOf(button), next = current;
        if (ev.key === "Home") next = 0;
        else if (ev.key === "End") next = tabs.length - 1;
        else next = (current + (ev.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length;
        ev.preventDefault();
        tabs[next].focus();
        activate(tabs[next]);
      };
    }
    function activateWizardTab(button) {
      var key = button.dataset.wizardTab;
      Array.prototype.forEach.call(root.querySelectorAll("[data-wizard-tab]"), function (x) {
        var active = x === button;
        x.classList.toggle("active", active);
        x.setAttribute("aria-selected", active ? "true" : "false");
        x.tabIndex = active ? 0 : -1;
      });
      Array.prototype.forEach.call(root.querySelectorAll("[data-wizard-pane]"), function (p) { p.hidden = p.dataset.wizardPane !== key; });
      syncWizardMode();
    }
    Array.prototype.forEach.call(root.querySelectorAll("[data-wizard-tab]"), function (b) {
      b.onclick = function () { activateWizardTab(b); };
      bindTabKeyboard(b, "[data-wizard-tab]", activateWizardTab);
    });
    function activateIsolationTab(button) {
      var key = button.dataset.isolationTab;
      Array.prototype.forEach.call(root.querySelectorAll("[data-isolation-tab]"), function (x) {
        var active = x === button;
        x.classList.toggle("active", active);
        x.setAttribute("aria-selected", active ? "true" : "false");
        x.tabIndex = active ? 0 : -1;
      });
      Array.prototype.forEach.call(root.querySelectorAll("[data-isolation-panel]"), function (p) { p.hidden = p.dataset.isolationPanel !== key; });
    }
    Array.prototype.forEach.call(root.querySelectorAll("[data-isolation-tab]"), function (b) {
      b.onclick = function () { activateIsolationTab(b); };
      bindTabKeyboard(b, "[data-isolation-tab]", activateIsolationTab);
    });
    syncDsaPortRows(root);
    Array.prototype.forEach.call(root.querySelectorAll("[data-smart-section]"), function (b) { b.onclick = function (ev) { ev.preventDefault(); showSection(b.dataset.smartSection); }; });
    Array.prototype.forEach.call(root.querySelectorAll("[data-smart-logout]"), function (b) { b.onclick = function (ev) { ev.preventDefault(); logout(); }; });
    Array.prototype.forEach.call(root.querySelectorAll(".dev-action"), function (b) {
      b.onclick = async function () {
        var mac = b.dataset.devMac, act = b.dataset.devAct;
        if (!mac || !act) return toast(tr("simulated"));
        if (act === "__limit") { // bandwidth-hog "limit" -> ask Mbps, set per-client QoS
          var mb = window.prompt(tr("limitPrompt"), "10"); if (mb === null) return;
          mb = String(mb).replace(/[^0-9]/g, ""); if (!mb) return;
          try {
            var result = await postJsonLocked(CTL, { credentials:"same-origin", cache:"no-store", headers:authHeaders({ "Content-Type":"application/x-www-form-urlencoded" }),
              body:"section=devices&action=set_client_limit&mac=" + encodeURIComponent(mac) + "&limit_down=" + mb + "&limit_up=" + mb + "&" + sidQuery() + "&_=" + Date.now() }, 20000, b);
            var rl = result.response;
            if (rl.status === 403) return requireLogin(tr("sessionExpired"));
            var jl = result.data; toast(jl.summary || tr("ok")); event("Limit " + mac + " " + mb + "Mbps");
            queueFullRefresh(250);
          } catch (e) { toast(e.message); }
          return;
        }
        await runDeviceAccessAction(mac, act, b);
      };
    });
    // device rename (custom names stored locally)
    Array.prototype.forEach.call(root.querySelectorAll(".dev-rename"), function (b) {
      b.onclick = function () {
        var mac = b.dataset.devMac; if (!mac) return;
        var cur = deviceName(mac);
        var nm = window.prompt(tr("renamePrompt"), cur || "");
        if (nm === null) return;
        setDeviceName(mac, nm.trim());
        if (state.latest) render(state.latest);
      };
    });
    var scanBtn = dynamicId(root, "wifiScanBtn");
    if (scanBtn) scanBtn.onclick = scanWifi;
    var lanBtn = dynamicId(root, "lanScanBtn");
    if (lanBtn) lanBtn.onclick = scanLan;
    var applyChan = dynamicId(root, "wifiApplyChanBtn");
    if (applyChan) applyChan.onclick = function () { applyBestChannels(applyChan.dataset.ch24, applyChan.dataset.ch5, applyChan); };
    var stBtn = dynamicId(root, "selftestBtn");
    if (stBtn) stBtn.onclick = async function () {
      stBtn.disabled = true; var old = stBtn.textContent; stBtn.textContent = tr("loading") + "...";
      try {
        var result = await postJsonLocked(CTL, { credentials:"same-origin", cache:"no-store",
          headers:authHeaders({ "Content-Type":"application/x-www-form-urlencoded" }),
          body:"section=selftest&action=run_selftest&" + sidQuery() + "&_=" + Date.now() }, SCAN_TIMEOUT_MS, stBtn);
        var r = result.response;
        if (r.status === 403) return requireLogin(tr("sessionExpired"));
        state.selftest = result.data;
        if (state.latest) render(state.latest);
        showSection("system");
      } catch (e) { toast("selftest: " + e.message); stBtn.disabled = false; stBtn.textContent = old; }
    };
    Array.prototype.forEach.call(root.querySelectorAll("[data-steer-mac]"), function (b) {
      b.onclick = async function () {
        b.disabled = true;
        try {
          var result = await postJsonLocked(CTL, { credentials:"same-origin", cache:"no-store",
            headers:authHeaders({ "Content-Type":"application/x-www-form-urlencoded" }),
            body:"section=wifi&action=steer_client&mac=" + encodeURIComponent(b.dataset.steerMac) + "&iface=" + encodeURIComponent(b.dataset.steerIface || "") + "&" + sidQuery() + "&_=" + Date.now() }, API_TIMEOUT_MS, b);
          var r = result.response;
          if (r.status === 403) return requireLogin(tr("sessionExpired"));
          var j = result.data;
          toast(j.summary || tr("ok"));
          event("Steer 5G: " + b.dataset.steerMac);
          queueFullRefresh(250);
        } catch (e) { toast(e.message); } finally { b.disabled = false; }
      };
    });
  }
  function startPolling() {
    if (!state.session) return showLogin();
    clearInterval(state.timer);
    state.interval = validPollInterval(state.interval);
    try { localStorage.setItem(LS + "interval", String(state.interval)); } catch (_) {}
    loadData(snapshotIsStale(state.latest));
    state.timer = setInterval(loadData, state.interval * 1000);
  }
  async function resumeStartupSession(staleSid) {
    var transientAttempts = 0;
    while (state.session) {
      var valid = await validateSession();
      if (valid === true) {
        setLoginBusy(false);
        state.session = "cookie";
        markBrowserSession();
        showDashboard();
        recoverSessionSafeApply().then(function (pending) { if (!pending) syncBrowserTime(); });
        return true;
      }
      if (valid === false) {
        setLoginBusy(false);
        showLogin(staleSid ? tr("sessionExpired") : "", !!staleSid);
        return false;
      }
      transientAttempts++;
      if (transientAttempts >= 2) {
        // A stalled/busy API must not leave the password form disabled in an
        // endless session-probe loop.  The HttpOnly server cookie is left
        // intact; a successful explicit login safely rotates it.
        state.session = "";
        sessionStorage.removeItem(LS + "session");
        setLoginBusy(false);
        showLogin(tr("loginUnavailable"), false);
        return false;
      }
      showLogin(tr("loginUnavailable"), false);
      setLoginBusy(true);
      await new Promise(function (resolve) { setTimeout(resolve, 750); });
    }
    setLoginBusy(false);
    return false;
  }
  function captureControlDraft(section) {
    var panel = document.querySelector('[data-control-section="' + section + '"]');
    if (!panel) return null;
    var values = {};
    Array.prototype.forEach.call(panel.querySelectorAll("[data-ctl-field]"), function (field) {
      var name = field.dataset.ctlField;
      if (name) values[name] = field.value;
    });
    var tabAttribute = section === "wizard" ? "wizardTab" : "isolationTab";
    var tabSelector = section === "wizard" ? "[data-wizard-tab]" : "[data-isolation-tab]";
    var selected = panel.querySelector(tabSelector + '[aria-selected="true"]') || panel.querySelector(tabSelector + ".active");
    return { values:values, tab:selected ? selected.dataset[tabAttribute] : "" };
  }
  function restoreControlDraft(section, draft) {
    if (!draft) return;
    var panel = document.querySelector('[data-control-section="' + section + '"]');
    if (!panel) return;
    Array.prototype.forEach.call(panel.querySelectorAll("[data-ctl-field]"), function (field) {
      var name = field.dataset.ctlField;
      if (!name || !Object.prototype.hasOwnProperty.call(draft.values, name)) return;
      field.value = draft.values[name];
      Array.prototype.forEach.call(panel.querySelectorAll("[data-tx-range]"), function (range) {
        if (range.dataset.txRange === name) range.value = draft.values[name];
      });
    });
    if (section === "wizard") syncWizardMode();
    else syncDsaPortRows(panel);
    var tabSelector = section === "wizard" ? "[data-wizard-tab]" : "[data-isolation-tab]";
    var paneSelector = section === "wizard" ? "[data-wizard-pane]" : "[data-isolation-panel]";
    var tabKey = section === "wizard" ? "wizardTab" : "isolationTab";
    var paneKey = section === "wizard" ? "wizardPane" : "isolationPanel";
    if (!draft.tab) return;
    Array.prototype.forEach.call(panel.querySelectorAll(tabSelector), function (tab) {
      var active = tab.dataset[tabKey] === draft.tab;
      tab.classList.toggle("active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
      tab.tabIndex = active ? 0 : -1;
    });
    Array.prototype.forEach.call(panel.querySelectorAll(paneSelector), function (pane) {
      pane.hidden = pane.dataset[paneKey] !== draft.tab;
    });
  }
  function probeSafeApplyAfterControlRebuild() {
    recoverSessionSafeApply().catch(function (error) {
      toast(error && error.message ? error.message : "Safe Apply status check failed");
    });
  }
  function retranslateControlSection(active) {
    var section = active === "quick" ? "wizard" : "isolation";
    var draft = captureControlDraft(section);
    var container = $(active);
    if (!container) return;
    cancelControlRead();
    container.innerHTML = active === "quick" ? renderQuick() : renderIsolation();
    container.dataset.uiVersion = UI_VERSION;
    bindDynamic(container);
    var box = $("ctl_" + sid(section));
    var cached = state.controlCache[section];
    if (!box || !cached) {
      loadControl(section);
      probeSafeApplyAfterControlRebuild();
      return;
    }
    box.dataset.loaded = "1";
    box.className = "";
    box.innerHTML = renderControlData(section, cached);
    if (section === "wizard") syncWizardMode();
    bindDynamic(box);
    restoreControlDraft(section, draft);
    probeSafeApplyAfterControlRebuild();
  }
  function setLanguage(lang) {
    state.lang = lang === "en" ? "en" : "ar";
    localStorage.setItem(LS + "lang", state.lang);
    renderChrome();
    var active = document.body.dataset.activeSection || "overview";
    if (/^(quick|isolation)$/.test(active)) {
      retranslateControlSection(active);
    } else if (state.latest) {
      render(state.latest, true);
    }
  }
  function init() {
    var loggedOut = false;
    try { loggedOut = new URLSearchParams(window.location.search).get("logged_out") === "1"; } catch (_) {}
    var staleSid = loggedOut ? "" : (sessionStorage.getItem(LS + "session") || "");
    if (loggedOut) sessionStorage.removeItem(LS + "session");
    state.session = loggedOut ? "" : "cookie";
    renderChrome();
    setLoginText();
    if ($("loginForm")) {
      $("loginForm").onsubmit = function (ev) {
        ev.preventDefault();
        login(($("loginUser") && $("loginUser").value) || "root", ($("loginPass") && $("loginPass").value) || "");
      };
    }
    $("langAr").onclick = function () { setLanguage("ar"); };
    $("langEn").onclick = function () { setLanguage("en"); };
    if ($("loginLangAr")) $("loginLangAr").onclick = function () { setLanguage("ar"); };
    if ($("loginLangEn")) $("loginLangEn").onclick = function () { setLanguage("en"); };
    $("themeBtn").onclick = function () {
      state.theme = state.theme === "dark" ? "light" : "dark";
      localStorage.setItem(LS + "theme", state.theme);
      renderChrome();
      // Repaint everything so canvas charts/gauges pick up the new theme colors,
      // and re-open the active control section so its chart (if any) redraws too.
      if (state.latest) render(state.latest);
      var act = document.body.dataset.activeSection;
      if (act) {
        var el = $(act);
        if (el && el.dataset) { el.dataset.uiVersion = ""; }
        showSection(act);
        if (/^(quick|isolation)$/.test(act)) probeSafeApplyAfterControlRebuild();
      }
    };
    $("intervalSelect").onchange = function () { state.interval = validPollInterval(this.value); localStorage.setItem(LS + "interval", state.interval); startPolling(); };
    $("logoutBtn").onclick = logout;
    if ($("openWrtBtn")) $("openWrtBtn").onclick = async function () {
      var button = this;
      button.disabled = true;
      button.textContent = tr("openWrtOpening");
      try {
        await ensureLuciSession();
        window.location.assign("/cgi-bin/luci/admin/network/wireless");
      } catch (e) {
        if (e && (e.status === 401 || e.status === 403)) requireLogin(tr("sessionExpired"));
        else toast(tr("openWrtAuthFailed"));
        button.disabled = false;
        button.textContent = tr("openWrtSettings");
      }
    };
    $("refreshBtn").onclick = function () { loadData(true); };
    document.addEventListener("visibilitychange", function () {
      if (document.hidden) { clearInterval(state.timer); clearStaleRetry(); }
      else startPolling();
    });
    if (loggedOut) {
      showLogin(tr("loggedOut"), false);
      try { window.history.replaceState(null, "", window.location.pathname || "/"); } catch (_) {}
      startupSessionCleanup = Promise.resolve(false);
    } else {
      showLogin();
      startupSessionCleanup = resumeStartupSession(staleSid);
    }
  }
  window.addEventListener("pagehide", function () { saveHistories(true); });
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
        var r = await fetchWithTimeout("dashboard.js?sp=" + Math.random(), { cache: "no-store" }, API_TIMEOUT_MS);
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
        si.id = "navSearch"; si.type = "search"; si.setAttribute("dir", "auto");
        si.placeholder = state.lang === "ar" ? "بحث سريع…" : "Quick search…";
        // styled from the stylesheet (#navSearch) so the mobile bottom-bar rules apply
        navEl.parentElement.insertBefore(si, navEl);
        si.oninput = function () {
          var q = si.value.trim().toLowerCase();
          Array.prototype.forEach.call(navEl.querySelectorAll("button"), function (b) {
            b.style.display = (!q || b.textContent.toLowerCase().indexOf(q) > -1) ? "" : "none";
          });
        };
      }
    } catch (e) { /* UX pack must never break the dashboard */ }
  });
}());
