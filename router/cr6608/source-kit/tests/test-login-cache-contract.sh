#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KIT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
INDEX="${KIT_DIR}/files/www/index.html"
DASHBOARD="${KIT_DIR}/files/www/dashboard.js"
DASHBOARD_CSS="${KIT_DIR}/files/www/dashboard.css"
ZERO_RETENTION="${KIT_DIR}/files/www/smartap-zero-retention.js"
ZERO_RETENTION_SHA256='94563b77aedaeaa30c241d84a50299f67f379d6f432d0693ceff44f37dfdd3b2'
DASHAPI="${KIT_DIR}/files/www/cgi-bin/dashapi2"
DASHLOGIN="${KIT_DIR}/files/www/cgi-bin/dashlogin"
BUILD="${KIT_DIR}/build.sh"
INSPECTOR="${KIT_DIR}/inspect-image.sh"
UHTTPD_PATCH="${KIT_DIR}/patches/992-uhttpd-normalize-dispatch-and-close-unread-body.patch"
EXPECTED_DASHBOARD_UI_VERSION='cr6608-smartap-v86-live-design-27.0.0'
EXPECTED_DASHBOARD_CSS_ASSET='/dashboard.css?v=20260902-smartap-v86-live-design-v1'
EXPECTED_DASHBOARD_JS_ASSET='/dashboard.js?v=20260902-smartap-v86-live-design-v1'

dashboard_asset_identity_valid() {
	asset_index="$1"
	asset_dashboard="$2"
	asset_css="$3"
	asset_inspector="$4"
	[ -s "${asset_index}" ] &&
		[ -s "${asset_dashboard}" ] &&
		[ -s "${asset_css}" ] &&
		[ -s "${asset_inspector}" ] &&
		[ "$(grep -Fxc "  <meta name=\"smartap-ui-version\" content=\"${EXPECTED_DASHBOARD_UI_VERSION}\">" "${asset_index}")" -eq 1 ] &&
		[ "$(grep -Fc "${EXPECTED_DASHBOARD_CSS_ASSET}" "${asset_index}")" -eq 1 ] &&
		[ "$(grep -Fxc "  <link rel=\"stylesheet\" href=\"${EXPECTED_DASHBOARD_CSS_ASSET}\">" "${asset_index}")" -eq 1 ] &&
		[ "$(grep -Fc "${EXPECTED_DASHBOARD_JS_ASSET}" "${asset_index}")" -eq 1 ] &&
		[ "$(grep -Fxc "  <script src=\"${EXPECTED_DASHBOARD_JS_ASSET}\" defer></script>" "${asset_index}")" -eq 1 ] &&
		grep -Fq "var UI_VERSION = \"${EXPECTED_DASHBOARD_UI_VERSION}\";" "${asset_dashboard}" &&
		grep -Fqx "EXPECTED_DASHBOARD_UI_VERSION=\"${EXPECTED_DASHBOARD_UI_VERSION}\"" "${asset_inspector}" &&
		grep -Fqx "EXPECTED_DASHBOARD_CSS_ASSET=\"${EXPECTED_DASHBOARD_CSS_ASSET}\"" "${asset_inspector}" &&
		grep -Fqx "EXPECTED_DASHBOARD_JS_ASSET=\"${EXPECTED_DASHBOARD_JS_ASSET}\"" "${asset_inspector}" &&
		[ "$(grep -Fc '/dashboard.css?v=' "${asset_inspector}")" -eq 1 ] &&
		[ "$(grep -Fc '/dashboard.js?v=' "${asset_inspector}")" -eq 1 ]
}

dashboard_asset_identity_valid "${INDEX}" "${DASHBOARD}" "${DASHBOARD_CSS}" "${INSPECTOR}" || {
	printf 'dashboard asset identity is missing, duplicated, or stale\n' >&2
	exit 1
}

# Exercise the same fail-closed predicate against the two easy-to-regress CSS
# cases: an absent file and a second reference to the otherwise correct asset.
asset_contract_tmp="$(mktemp -d "${TMPDIR:-/tmp}/smartap-dashboard-assets.XXXXXX")"
trap 'rm -rf -- "${asset_contract_tmp}"' 0 1 2 15
if dashboard_asset_identity_valid "${INDEX}" "${DASHBOARD}" \
	"${asset_contract_tmp}/missing-dashboard.css" "${INSPECTOR}"; then
	printf 'dashboard asset identity accepted a missing stylesheet\n' >&2
	exit 1
fi
duplicate_index="${asset_contract_tmp}/duplicate-index.html"
cp "${INDEX}" "${duplicate_index}"
printf '%s\n' "  <link rel=\"stylesheet\" href=\"${EXPECTED_DASHBOARD_CSS_ASSET}\">" >> "${duplicate_index}"
if dashboard_asset_identity_valid "${duplicate_index}" "${DASHBOARD}" \
	"${DASHBOARD_CSS}" "${INSPECTOR}"; then
	printf 'dashboard asset identity accepted a duplicate stylesheet reference\n' >&2
	exit 1
fi
rm -rf -- "${asset_contract_tmp}"
trap - 0 1 2 15

grep -Fq 'http-equiv="Cache-Control" content="no-store, no-cache, must-revalidate"' "${INDEX}"
grep -Fq 'http-equiv="Pragma" content="no-cache"' "${INDEX}"
grep -Fq 'http-equiv="Expires" content="0"' "${INDEX}"
grep -Fq '/smartap-zero-retention.js?v=20260826-exact-legacy-purge-v1' "${INDEX}"
[ "$(sha256sum "${ZERO_RETENTION}" | awk '{print $1}')" = "${ZERO_RETENTION_SHA256}" ]

# The migration is an exact, history-derived allowlist.  It may delete the
# retired keys once per document, but may never read storage, create a marker,
# enumerate a namespace, clear a whole store, or touch an unknown smartap.* key.
grep -Fqx '  var LEGACY_LOCAL_KEYS = ["smartap.availability", "smartap.cardOrder", "smartap.dailyBudgetGb", "smartap.dayBaseRx", "smartap.dayBaseTx", "smartap.devNames", "smartap.events", "smartap.histories", "smartap.insightCategory", "smartap.interval", "smartap.knownMacs", "smartap.lang", "smartap.latHist", "smartap.monthBaseRx", "smartap.monthBaseTx", "smartap.monthBudgetGb", "smartap.outageLog", "smartap.theme", "smartap.themePref", "smartap.uiVersion", "smartap.weeklyLog", "smartap.yearBaseRx", "smartap.yearBaseTx"];' "${ZERO_RETENTION}"
grep -Fqx '  var LEGACY_SESSION_KEYS = ["smartap.session"];' "${ZERO_RETENTION}"
[ "$(grep -Fc 'storage.removeItem(key);' "${ZERO_RETENTION}")" -eq 1 ]
[ "$(grep -Fc 'purgeExactKeys(window.localStorage, LEGACY_LOCAL_KEYS);' "${ZERO_RETENTION}")" -eq 1 ]
[ "$(grep -Fc 'purgeExactKeys(window.sessionStorage, LEGACY_SESSION_KEYS);' "${ZERO_RETENTION}")" -eq 1 ]
! grep -Eq '\.(setItem|getItem|clear|key)\(' "${ZERO_RETENTION}"
! grep -Eq 'Object\.(keys|values|entries)|for[[:space:]]*\([^)]*in[[:space:]]' "${ZERO_RETENTION}"
[ "$(grep -Fxc '  <script src="/smartap-zero-retention.js?v=20260826-exact-legacy-purge-v1" defer></script>' "${INDEX}")" -eq 1 ]
[ "$(grep -Ec 'src="/smartap-zero-retention[.]js([?"/])' "${INDEX}")" -eq 1 ]
[ "$(grep -Ec 'src="/dashboard[.]js([?"/])' "${INDEX}")" -eq 1 ]
zero_retention_line="$(grep -nF '/smartap-zero-retention.js?v=20260826-exact-legacy-purge-v1' "${INDEX}" | cut -d: -f1)"
dashboard_line="$(grep -nF "${EXPECTED_DASHBOARD_JS_ASSET}" "${INDEX}" | cut -d: -f1)"
[ -n "${zero_retention_line}" ] && [ -n "${dashboard_line}" ] &&
	[ "${zero_retention_line}" -lt "${dashboard_line}" ]
node --check "${ZERO_RETENTION}" >/dev/null

grep -Fq 'id="loginUser" name="smartap-user-once"' "${INDEX}"
grep -Fq 'value="root" data-form-type="other"' "${INDEX}"
! grep -Eq 'id="loginUser"[^>]*readonly' "${INDEX}"
grep -Fq 'id="loginForm" autocomplete="off"' "${INDEX}"
grep -Fq 'id="loginUser" name="smartap-user-once" autocomplete="off"' "${INDEX}"
grep -Fq 'id="loginPass" name="smartap-secret-once" type="password" autocomplete="new-password"' "${INDEX}"
grep -Fq 'data-1p-ignore="true" data-lpignore="true"' "${INDEX}"
! grep -Fq 'loginPassToggle' "${INDEX}"
! grep -Fq 'setPasswordVisible' "${DASHBOARD}"
grep -Fq 'function normalizeMobilePassword(value)' "${DASHBOARD}"
grep -Fq 'if (e && e.status === 401 && $("loginPass")) $("loginPass").value = "";' "${DASHBOARD}"
grep -Fq 'function clearLoginCredentialInput()' "${DASHBOARD}"
[ "$(grep -Fc 'clearLoginCredentialInput();' "${DASHBOARD}")" -ge 4 ]
grep -Fq 'root|admin) user=root' "${KIT_DIR}/files/www/cgi-bin/dashlogin"
grep -Fq 'login(($(' "${DASHBOARD}"
grep -Fq 'root or admin' "${DASHBOARD}"
grep -Fq 'sessionExpired:' "${DASHBOARD}"
grep -Fq 'if (transientAttempts >= 2)' "${DASHBOARD}"
grep -Fq 'function fetchWithTimeout(' "${DASHBOARD}"
grep -Fq 'var bodyReaders = ["arrayBuffer", "blob", "formData", "json", "text"]' "${DASHBOARD}"
grep -Fq 'return Promise.race([bodyPromise, timeout]).then' "${DASHBOARD}"
! grep -Fq 'Promise.race([fetch(url, requestOptions), timeout]).finally' "${DASHBOARD}"
grep -Fq 'if (state.loginPending) return;' "${DASHBOARD}"
grep -Fq 'setLoginBusy(true);' "${DASHBOARD}"
grep -Fq 'setLoginBusy(false);' "${DASHBOARD}"
grep -Fq 'loginUnavailable:' "${DASHBOARD}"
grep -Fq 'async function ensureLuciSession()' "${DASHBOARD}"
grep -Fq 'fetchWithTimeout("/cgi-bin/dashluci"' "${DASHBOARD}"
grep -Fq 'window.location.assign("/cgi-bin/luci/admin/network/wireless")' "${DASHBOARD}"
grep -Fq 'id="openWrtBtn"' "${INDEX}"
grep -Fq 'authUrl(API + "?lite=1&probe=1&live=1")' "${DASHBOARD}"
grep -Fq 'if (res.status === 401 || res.status === 403)' "${DASHBOARD}"
grep -Fq 'if (res.status !== 200) return null;' "${DASHBOARD}"
grep -Fq 'resumeStartupSession()' "${DASHBOARD}"
grep -Fq 'data.snapshot_stale === true || data.snapshot_invalidated === true' "${DASHBOARD}"
grep -Fq 'snapshotIsStale(state.latest)' "${DASHBOARD}"
grep -Fq 'var liveCounters = !staleSnapshot || data._liveLite === true' "${DASHBOARD}"
grep -Fq 'var recordLiveCounters = liveCounters && repaintOnly !== true' "${DASHBOARD}"
grep -Fq 'trafficRates(data, recordLiveCounters)' "${DASHBOARD}"
grep -Fq 'pushHistory("rx", rates.rx, 60, recordLiveCounters)' "${DASHBOARD}"
grep -Fq 'state.suspendHistory = staleSnapshot || repaintOnly === true' "${DASHBOARD}"
grep -Fq 'state.suspendHistory = priorSuspendHistory' "${DASHBOARD}"
grep -Fq 'updateAvailability(!!data.ok)' "${DASHBOARD}"
grep -Fq 'state.lastFullAt = 0;' "${DASHBOARD}"
grep -Fq 'controlActionAffectsSnapshot(actionName)' "${DASHBOARD}"
grep -Fq 'data.snapshot_live !== true' "${DASHBOARD}"
grep -Fq 'window.__lastApi = null' "${DASHBOARD}"
grep -Fq 'window.addEventListener("pagehide"' "${DASHBOARD}"
grep -Fq 'window.addEventListener("pageshow"' "${DASHBOARD}"
grep -Fq 'if (!event.persisted) return;' "${DASHBOARD}"
grep -Fq 'window.location.reload();' "${DASHBOARD}"
grep -Fq 'chartDrawJobs = Object.create(null);' "${DASHBOARD}"
grep -Fq 'state.session = "";' "${DASHBOARD}"
grep -Fq 'no previous snapshot is displayed' "${DASHBOARD}"
grep -Fq 'snapshotWarning' "${INDEX}"
grep -Fq "*'&lite=1&'*)" "${DASHAPI}"
grep -Fq "*'&probe=1&'*) session_probe=1" "${DASHAPI}"
grep -Fq "*'&live=1&'*) live_only=1" "${DASHAPI}"
grep -Fq "printf 'Status: 403 Forbidden" "${DASHAPI}"
grep -Fq '"authenticated":false' "${DASHAPI}"
grep -Fq 'cr6608_dashboard_cache_reader_acquire' "${DASHAPI}"
grep -Fq 'live_only=1' "${DASHAPI}"
grep -Fq 'if [ "$internal_refresh" = 1 ]; then' "${DASHAPI}"
grep -Fq 'dashapi_telemetry_purge' "${DASHAPI}"
grep -Fq '"snapshot_live":true' "${DASHAPI}"
grep -Fq '"snapshot_stored":false' "${DASHAPI}"
grep -Fq 'while ! cr6608_dashboard_cache_collector_acquire' "${DASHAPI}"
grep -Fq '"$cache_dir/response.json" "$cache_dir/perf" "$cache_dir/lite.cpu"' "${DASHAPI}"
grep -Fq '"$cache_dir/cpu" "$cache_dir/traffic" "$cache_dir/traffic.topology"' "${DASHAPI}"
grep -Fq -- "-name 'iface.*' -o -name 'sta.*' -o -name 'survey.*'" "${DASHAPI}"
! grep -Eq 'cr6608_dashboard_cache_(snapshot|inspect|publish)|cache_(load_view|emit_or_error)' "${DASHAPI}"
! grep -Eq '>[[:space:]]*"\$cache_dir/(response\.json|perf|lite\.cpu|cpu|traffic|traffic\.topology|iface\.|sta\.|survey\.)' "${DASHAPI}"
! grep -Fq 'CR6608_DASHAPI_INTERNAL=1 /www/cgi-bin/dashapi2' "${DASHAPI}"
! grep -Fq 'Object.assign({}, state.latest, data)' "${DASHBOARD}"
! grep -Fq 'function saveHistories(' "${DASHBOARD}"
! grep -Fq 'localStorage' "${DASHBOARD}"
! grep -Fq 'sessionStorage' "${DASHBOARD}"
grep -Fq 'liveAvailability: []' "${DASHBOARD}"
grep -Fq 'deviceNames: {}' "${DASHBOARD}"
grep -Fq 'liveSessionSummary: null' "${DASHBOARD}"
grep -Fq 'liveTransitions: { events:[] }' "${DASHBOARD}"
grep -Fq 'fetchSamples: []' "${DASHBOARD}"
grep -Fq 'state.liveAvailability = state.liveAvailability.slice(-60)' "${DASHBOARD}"
! grep -Fq 'last 24h' "${DASHBOARD}"
! grep -Fq 'Last 7 Browser-observed Days' "${DASHBOARD}"

! grep -Fq 'SRC_UHTTPD_PATCH=' "${BUILD}"
! grep -Fq 'record_regular_input webserver-patch' "${BUILD}"
grep -Fq 'rm -f -- "${UHTTPD_PATCH_DIR}"/994-uhttpd-smartap-no-store.patch' "${BUILD}"
grep -Fq 'LOGIN_CACHE_TEST=' "${BUILD}"

# Every static response must bypass conditional 304 handling and carry the
# explicit no-store policy; this includes future UI assets without an allowlist.
[ "$(grep -Fc 'cl->dispatch.no_cache = true;' "${UHTTPD_PATCH}")" -eq 1 ]
grep -Fq 'cl->dispatch.no_cache = true;' "${UHTTPD_PATCH}"
grep -Fq 'Cache-Control: no-store, no-cache, must-revalidate' "${UHTTPD_PATCH}"
grep -Fq 'Pragma: no-cache' "${UHTTPD_PATCH}"
grep -Fq 'Expires: 0' "${UHTTPD_PATCH}"
! grep -Fq 'smartap_entry' "${UHTTPD_PATCH}"
! grep -Fq 'smartap_no_store' "${UHTTPD_PATCH}"

# Authentication and live status must never be cached either.
for cgi in dashlogin dashlogout dashluci dashapi2 dashctl; do
	grep -Fq 'Cache-Control: no-store' "${KIT_DIR}/files/www/cgi-bin/${cgi}"
done

# A successful login cookie is browser-session-only. Server-side monotonic
# expiry remains authoritative, while logout cookies retain Max-Age=0.
grep -Fq 'SET_COOKIE="$cookie_name=$tok; Path=/;${secure_cookie} HttpOnly; SameSite=Strict"' "${DASHLOGIN}"
! grep -Fq 'SET_COOKIE="$cookie_name=$tok; Path=/; Max-Age=' "${DASHLOGIN}"

printf 'login_cache_contract=pass\n'
