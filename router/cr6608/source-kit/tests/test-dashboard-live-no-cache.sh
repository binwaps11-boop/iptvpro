#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
API="$ROOT/files/www/cgi-bin/dashapi2"
STATE_LIB="$ROOT/files/usr/libexec/cr6608-dashboard-cache-state"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-live-no-cache.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'dashboard_live_no_cache=FAIL %s\n' "$1" >&2; exit 1; }

cat >"$TMP/auth-allow" <<'SH'
cr6608_session_from_request() { printf '%s' test; }
cr6608_session_valid() { return 0; }
cr6608_ubus() { return 1; }
SH

state="$TMP/state"
mkdir -m 0700 "$state"
printf 'network-v1\n' >"$TMP/config-network"
printf 'wireless-v1\n' >"$TMP/config-wireless"

seed_telemetry() {
  for _leaf in response.json perf lite.cpu cpu traffic traffic.topology \
    iface.lan1 sta.001122334455 survey.phy0-ap0; do
    printf 'must-not-return\n' >"$state/$_leaf"
  done
  for _leaf in \
    .dashcmd-out.700.RESIDUE .dashcmd-err.700.RESIDUE \
    .linklog.700.RESIDUE .devices.700 .arp.700 .fdb.700 .lease.700 \
    .degraded.700 .view.700.RESIDUE .emit.700.RESIDUE \
    .publish.700.RESIDUE .publish-final.700.RESIDUE \
    .perf.700.RESIDUE .collect.700.RESIDUE; do
    printf 'must-not-return\n' >"$state/$_leaf"
  done
}

assert_no_telemetry() {
  _phase="$1"
  for _leaf in response.json perf lite.cpu cpu traffic traffic.topology \
    iface.lan1 sta.001122334455 survey.phy0-ap0; do
    { [ ! -e "$state/$_leaf" ] && [ ! -L "$state/$_leaf" ]; } ||
      fail "$_phase retained $_leaf"
  done
  if find "$state" -maxdepth 1 \( \
      -name '.dashcmd-out.*.*' -o -name '.dashcmd-err.*.*' -o \
      -name '.linklog.*.*' -o -name '.devices.*' -o \
      -name '.arp.*' -o -name '.fdb.*' -o -name '.lease.*' -o \
      -name '.degraded.*' -o -name '.collect.*.*' -o \
      -name '.view.*.*' -o -name '.emit.*.*' -o \
      -name '.publish.*.*' -o -name '.publish-final.*.*' -o \
      -name '.perf.*.*' \) \
      -print -quit | grep -q .; then
    fail "$_phase retained a response/cache temporary"
  fi
}

assert_metadata_preserved() {
  _phase="$1"
  for _leaf in meta.lock mutation.lock collector.lock; do
    [ -f "$state/$_leaf" ] && [ ! -L "$state/$_leaf" ] ||
      fail "$_phase removed or replaced metadata $_leaf"
  done
  [ "$(cat "$state/operator.keep")" = unrelated-runtime-state ] ||
    fail "$_phase deleted unrelated runtime state"
}

run_api() {
  _query="$1"
  REQUEST_METHOD=GET QUERY_STRING="$_query" \
    CR6608_SESSION_AUTH_LIB="$TMP/auth-allow" \
    CR6608_DASHBOARD_CACHE_STATE_LIB="$STATE_LIB" \
    CR6608_DASHBOARD_CACHE_DIR="$state" \
    CR6608_DASHBOARD_CACHE_EXPECT_UID="$(id -u)" \
    CR6608_DASHBOARD_FINGERPRINT_PATHS="$TMP/config-network $TMP/config-wireless" \
    CR6608_DASHAPI_BUDGET=5 sh "$API"
}

printf 'unrelated-runtime-state\n' >"$state/operator.keep"

# The legacy request without live=1 is forced onto the same live, non-stored
# path and may not reuse the planted response.
seed_telemetry
non_live="$(run_api 'lite=1')"
printf '%s\n' "$non_live" | grep -q '"ok":true,"lite":true,"snapshot_live":true,"snapshot_stored":false' ||
  fail 'legacy non-live lite request was not forced live'
! printf '%s\n' "$non_live" | grep -q 'must-not-return' || fail 'non-live request reused old response'
assert_no_telemetry 'legacy non-live lite request'
assert_metadata_preserved 'legacy non-live lite request'

seed_telemetry
live_lite="$(run_api 'lite=1&live=1')"
printf '%s\n' "$live_lite" | grep -q '"ok":true,"lite":true,"snapshot_live":true,"snapshot_stored":false' ||
  fail 'explicit live lite request failed'
assert_no_telemetry 'explicit live lite request'

# The old internal prewarm mode is now a purge-only no-op: no JSON output, no
# collector product and no retained artifact.
seed_telemetry
internal_out="$(CR6608_DASHAPI_INTERNAL=1 \
  CR6608_SESSION_AUTH_LIB="$TMP/auth-allow" \
  CR6608_DASHBOARD_CACHE_STATE_LIB="$STATE_LIB" \
  CR6608_DASHBOARD_CACHE_DIR="$state" \
  CR6608_DASHBOARD_CACHE_EXPECT_UID="$(id -u)" \
  CR6608_DASHBOARD_FINGERPRINT_PATHS="$TMP/config-network $TMP/config-wireless" \
  sh "$API")"
[ -z "$internal_out" ] || fail 'internal compatibility mode emitted telemetry'
assert_no_telemetry 'internal compatibility mode'

# Exercise the full collector once. Missing optional router commands on a build
# host may mark it degraded, but it must still return only a live request-local
# document or a fail-closed live error, never a cached snapshot.
seed_telemetry
full_out="$(run_api 'live=1')"
if printf '%s\n' "$full_out" | grep -q '"ok":true'; then
  printf '%s\n' "$full_out" | grep -q '"snapshot_live":true,"snapshot_stored":false' ||
    fail 'full response did not declare non-stored live semantics'
else
  printf '%s\n' "$full_out" | grep -Eq '"error":"(invalidated|busy|coordination_[^"]+)"' ||
    fail 'full collector did not fail closed'
fi
! printf '%s\n' "$full_out" | grep -q 'must-not-return' || fail 'full request reused old response'
assert_no_telemetry 'full live request'
assert_metadata_preserved 'full live request'

# Overlapping lightweight requests serialize on collector.lock and both purge
# before release. No later request can observe a prior response.
parallel_pids=""
for _n in 1 2; do
  run_api 'lite=1' >"$TMP/parallel.$_n" &
  parallel_pids="$parallel_pids $!"
done
for _pid in $parallel_pids; do wait "$_pid" || fail 'parallel live request failed'; done
for _n in 1 2; do
  grep -q '"snapshot_live":true,"snapshot_stored":false' "$TMP/parallel.$_n" ||
    fail "parallel request $_n did not complete live"
done
assert_no_telemetry 'parallel live requests'

printf 'dashboard_live_no_cache=pass\n'
