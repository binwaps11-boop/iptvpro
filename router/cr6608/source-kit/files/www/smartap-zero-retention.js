(function () {
  "use strict";

  // Exact historical Smart AP browser keys recovered from released dashboard
  // source.  This is deliberately not a prefix scan: unknown keys, including
  // other smartap.* keys, belong to neither this migration nor this UI.
  var LEGACY_LOCAL_KEYS = ["smartap.availability", "smartap.cardOrder", "smartap.dailyBudgetGb", "smartap.dayBaseRx", "smartap.dayBaseTx", "smartap.devNames", "smartap.events", "smartap.histories", "smartap.insightCategory", "smartap.interval", "smartap.knownMacs", "smartap.lang", "smartap.latHist", "smartap.monthBaseRx", "smartap.monthBaseTx", "smartap.monthBudgetGb", "smartap.outageLog", "smartap.theme", "smartap.themePref", "smartap.uiVersion", "smartap.weeklyLog", "smartap.yearBaseRx", "smartap.yearBaseTx"];
  var LEGACY_SESSION_KEYS = ["smartap.session"];

  function removeLegacyKey(storage, key) {
    try {
      storage.removeItem(key);
    } catch (_) {
      // Storage can be unavailable by browser policy.  The live UI neither
      // reads nor creates browser storage, so an inaccessible store is safe.
    }
  }

  function purgeExactKeys(storage, keys) {
    keys.forEach(function (key) {
      removeLegacyKey(storage, key);
    });
  }

  // Run once for this document.  A persistent "migration complete" marker
  // would itself violate zero retention; repeated page loads are idempotent.
  try {
    purgeExactKeys(window.localStorage, LEGACY_LOCAL_KEYS);
  } catch (_) {}
  try {
    purgeExactKeys(window.sessionStorage, LEGACY_SESSION_KEYS);
  } catch (_) {}
}());
