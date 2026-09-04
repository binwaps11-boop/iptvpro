#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APPLY="$ROOT/files/usr/sbin/smartap-qos-apply"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin" "$TMP/runtime"
chmod 0700 "$TMP/runtime"

cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
case "${1:-}:${2:-}:${3:-}" in
  '-q:show:smartap') [ -e "$CR6608_QOS_TEST_EMPTY" ] || printf '%s\n' 'smartap.qos_a=qos' ;;
  '-q:show:firewall')
    while IFS='|' read -r section name mac target || [ -n "$section" ]; do
      [ -n "$section" ] && printf 'firewall.%s=rule\n' "$section"
    done <"$CR6608_QOS_TEST_BLOCK_DB"
    ;;
  '-q:get:smartap.qos_a.mac') sed -n '1p' "$CR6608_QOS_TEST_STATE" ;;
  '-q:get:smartap.qos_a.down') sed -n '2p' "$CR6608_QOS_TEST_STATE" ;;
  '-q:get:smartap.qos_a.up') sed -n '3p' "$CR6608_QOS_TEST_STATE" ;;
  -q:get:firewall.*)
    item="${3#firewall.}"
    property="${item##*.}"
    section="${item%.*}"
    case "$property" in name) column=2 ;; src_mac) column=3 ;; target) column=4 ;; *) exit 1 ;; esac
    awk -F'|' -v wanted="$section" -v column="$column" '
      $1 == wanted { print $column; found=1; exit }
      END { exit(found ? 0 : 1) }
    ' "$CR6608_QOS_TEST_BLOCK_DB"
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$TMP/bin/nft" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CR6608_QOS_TEST_NFT_LOG"
case "$1" in
  list)
    [ ! -e "$CR6608_QOS_TEST_FAIL_LIST" ] || exit 44
    [ "$*" != 'list tables bridge' ] || exit 0
    [ -e "$CR6608_QOS_TEST_TABLE_PRESENT" ]
    exit $?
    ;;
  delete)
    [ ! -e "$CR6608_QOS_TEST_FAIL_DELETE" ] || exit 43
    rm -f "$CR6608_QOS_TEST_TABLE_PRESENT"
    rm -f "$CR6608_QOS_TEST_LIVE_TABLE"
    exit 0
    ;;
  -c)
    [ "$2" = -f ] && [ "$3" = - ] || exit 64
    rules="$(cat)"
    printf '%s\n' "$rules" >"$CR6608_QOS_TEST_CHECKED"
    printf '%s\n' "$rules" | grep -Fq 'table bridge smartap_qos' || exit 1
    exit 0
    ;;
  -f)
    [ "$2" = - ] || exit 64
    rules="$(cat)"
    [ ! -e "$CR6608_QOS_TEST_FAIL_APPLY" ] || exit 42
    if [ -n "${CR6608_QOS_TEST_FAIL_RATE:-}" ] &&
       printf '%s\n' "$rules" | grep -Fq "rate over $CR6608_QOS_TEST_FAIL_RATE kbytes/second"; then
      exit 42
    fi
    if [ -e "$CR6608_QOS_TEST_PAUSE_APPLY" ] &&
       printf '%s\n' "$rules" | grep -Fq 'rate over 12500 kbytes/second'; then
      : >"$CR6608_QOS_TEST_APPLY_ENTERED"
      n=0
      while [ ! -e "$CR6608_QOS_TEST_APPLY_RELEASE" ]; do
        n=$((n + 1)); [ "$n" -le 20 ] || exit 45
        sleep 1
      done
    fi
    printf '%s\n' "$rules" >"$CR6608_QOS_TEST_APPLIED"
    printf '%s\n' "$rules" >"$CR6608_QOS_TEST_LAST_LOADED"
    printf '%s\n' "$rules" | sed '/^delete table bridge smartap_qos$/d' >"$CR6608_QOS_TEST_LIVE_TABLE"
    : >"$CR6608_QOS_TEST_TABLE_PRESENT"
    exit 0
    ;;
esac
exit 2
EOF

cat >"$TMP/bin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CR6608_QOS_TEST_LOGGER_LOG"
EOF

cat >"$TMP/bin/flock" <<'EOF'
#!/bin/sh
case "$*" in
  '-xn 9')
    printf 'try|%s\n' "$PPID" >>"$CR6608_QOS_TEST_FLOCK_LOG"
    mkdir "$CR6608_QOS_TEST_FLOCK_HELD" 2>/dev/null || exit 1
    printf '%s\n' "$PPID" >"$CR6608_QOS_TEST_FLOCK_HELD/owner"
    printf 'acquire|%s\n' "$PPID" >>"$CR6608_QOS_TEST_FLOCK_LOG"
    exit 0
    ;;
  '-u 9')
    owner="$(sed -n '1p' "$CR6608_QOS_TEST_FLOCK_HELD/owner" 2>/dev/null)"
    [ "$owner" = "$PPID" ] || exit 1
    rm -f "$CR6608_QOS_TEST_FLOCK_HELD/owner"
    rmdir "$CR6608_QOS_TEST_FLOCK_HELD" || exit 1
    printf 'release|%s\n' "$PPID" >>"$CR6608_QOS_TEST_FLOCK_LOG"
    exit 0
    ;;
  *) printf 'unsupported|%s\n' "$*" >>"$CR6608_QOS_TEST_FLOCK_LOG"; exit 64 ;;
esac
EOF
chmod 0755 "$TMP/bin/uci" "$TMP/bin/nft" "$TMP/bin/logger" "$TMP/bin/flock"

CR6608_QOS_TEST_STATE="$TMP/state"
CR6608_QOS_TEST_BLOCK_DB="$TMP/block-db"
CR6608_QOS_TEST_NFT_LOG="$TMP/nft.log"
CR6608_QOS_TEST_LOGGER_LOG="$TMP/logger.log"
CR6608_QOS_TEST_LAST_LOADED="$TMP/last-loaded.nft"
CR6608_QOS_TEST_LIVE_TABLE="$TMP/live-table.nft"
CR6608_QOS_TEST_CHECKED="$TMP/checked.nft"
CR6608_QOS_TEST_APPLIED="$TMP/applied.nft"
CR6608_QOS_TEST_TABLE_PRESENT="$TMP/table-present"
CR6608_QOS_TEST_EMPTY="$TMP/empty"
CR6608_QOS_TEST_FAIL_DELETE="$TMP/fail-delete"
CR6608_QOS_TEST_FAIL_LIST="$TMP/fail-list"
CR6608_QOS_TEST_FAIL_APPLY="$TMP/fail-apply"
CR6608_QOS_TEST_PAUSE_APPLY="$TMP/pause-apply"
CR6608_QOS_TEST_APPLY_ENTERED="$TMP/apply-entered"
CR6608_QOS_TEST_APPLY_RELEASE="$TMP/apply-release"
CR6608_QOS_TEST_FLOCK_LOG="$TMP/flock.log"
CR6608_QOS_TEST_FLOCK_HELD="$TMP/runtime/apply.lock.mock-held"
CR6608_QOS_UCI_BIN="$TMP/bin/uci"
CR6608_QOS_NFT_BIN="$TMP/bin/nft"
CR6608_QOS_LOGGER_BIN="$TMP/bin/logger"
CR6608_QOS_FLOCK_BIN="$TMP/bin/flock"
CR6608_QOS_RUNTIME_DIR="$TMP/runtime"
export CR6608_QOS_TEST_STATE CR6608_QOS_TEST_BLOCK_DB CR6608_QOS_TEST_NFT_LOG
export CR6608_QOS_TEST_LOGGER_LOG CR6608_QOS_TEST_LAST_LOADED CR6608_QOS_TEST_LIVE_TABLE
export CR6608_QOS_TEST_CHECKED CR6608_QOS_TEST_APPLIED
export CR6608_QOS_TEST_TABLE_PRESENT CR6608_QOS_TEST_EMPTY CR6608_QOS_TEST_FAIL_DELETE
export CR6608_QOS_TEST_FAIL_LIST CR6608_QOS_TEST_FAIL_APPLY
export CR6608_QOS_TEST_PAUSE_APPLY CR6608_QOS_TEST_APPLY_ENTERED CR6608_QOS_TEST_APPLY_RELEASE
export CR6608_QOS_TEST_FLOCK_LOG CR6608_QOS_TEST_FLOCK_HELD
export CR6608_QOS_UCI_BIN CR6608_QOS_NFT_BIN CR6608_QOS_LOGGER_BIN CR6608_QOS_FLOCK_BIN
export CR6608_QOS_RUNTIME_DIR

: >"$CR6608_QOS_TEST_BLOCK_DB"
printf '%s\n' 'AA:BB:CC:DD:EE:FF' 100 50 >"$CR6608_QOS_TEST_STATE"
sh "$APPLY"
ACTIVE="$TMP/runtime/cr6608-smartap-qos.active.nft"
[ -e "$CR6608_QOS_TEST_TABLE_PRESENT" ] || {
  printf 'smartap qos mock did not retain live-table state\n' >&2
  exit 1
}
grep -Fq 'ether daddr aa:bb:cc:dd:ee:ff limit rate over 12500 kbytes/second' "$ACTIVE"
grep -Fq 'ether saddr aa:bb:cc:dd:ee:ff limit rate over 6250 kbytes/second' "$ACTIVE"
grep -Fq 'type filter hook forward priority 10' "$ACTIVE"
grep -Fq 'type filter hook input priority 10' "$ACTIVE"
grep -Fq 'type filter hook output priority 10' "$ACTIVE"
[ "$(grep -Fc 'ether daddr aa:bb:cc:dd:ee:ff limit rate over 12500 kbytes/second' "$ACTIVE")" = 2 ]
[ "$(grep -Fc 'ether saddr aa:bb:cc:dd:ee:ff limit rate over 6250 kbytes/second' "$ACTIVE")" = 2 ]
grep -Fq 'installed 2 per-client rates and 0 blocked MACs across bridge and routed paths' "$CR6608_QOS_TEST_LOGGER_LOG"
cmp -s "$CR6608_QOS_TEST_CHECKED" "$CR6608_QOS_TEST_APPLIED"

# A valid but runtime-rejected update must restore the last installed policy.
printf '%s\n' 'AA:BB:CC:DD:EE:FF' 200 75 >"$CR6608_QOS_TEST_STATE"
CR6608_QOS_TEST_FAIL_RATE=25000
export CR6608_QOS_TEST_FAIL_RATE
if sh "$APPLY"; then
  printf 'smartap qos rollback test unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'rate over 12500 kbytes/second' "$ACTIVE"
! grep -Fq 'rate over 25000 kbytes/second' "$ACTIVE"
grep -Fq 'previous policy kept' "$CR6608_QOS_TEST_LOGGER_LOG" || {
  sed 's/^/logger: /' "$CR6608_QOS_TEST_LOGGER_LOG" >&2
  exit 1
}
grep -Fq 'rate over 12500 kbytes/second' "$CR6608_QOS_TEST_LAST_LOADED"

# Dashboard-owned firewall rules must also block AP-mode traffic that is
# switched entirely inside the bridge.  Source and destination directions are
# enforced, duplicates collapse to one client policy, and the check/apply nft
# transactions are byte-identical.
unset CR6608_QOS_TEST_FAIL_RATE
printf '%s\n' 'AA:BB:CC:DD:EE:FF' 100 50 >"$CR6608_QOS_TEST_STATE"
printf '%s\n' '@rule[0]|CR6608-Block-02:11:22:33:44:55|02:11:22:33:44:55|REJECT' >"$CR6608_QOS_TEST_BLOCK_DB"
sh "$APPLY"
grep -Fq 'ether saddr 02:11:22:33:44:55 counter drop' "$ACTIVE"
grep -Fq 'ether daddr 02:11:22:33:44:55 counter drop' "$ACTIVE"
[ "$(grep -Fc 'ether saddr 02:11:22:33:44:55 counter drop' "$ACTIVE")" = 2 ]
[ "$(grep -Fc 'ether daddr 02:11:22:33:44:55 counter drop' "$ACTIVE")" = 2 ]
cmp -s "$CR6608_QOS_TEST_CHECKED" "$CR6608_QOS_TEST_APPLIED"
grep -Fq 'delete table bridge smartap_qos' "$CR6608_QOS_TEST_APPLIED"

printf '%s\n' \
  '@rule[0]|CR6608-Block-02:11:22:33:44:55|02:11:22:33:44:55|REJECT' \
  '@rule[1]|CR6608-Block-02:11:22:33:44:55|02:11:22:33:44:55|REJECT' \
  >"$CR6608_QOS_TEST_BLOCK_DB"
sh "$APPLY"
[ "$(grep -Fc 'ether saddr 02:11:22:33:44:55 counter drop' "$ACTIVE")" = 2 ]
[ "$(grep -Fc 'ether daddr 02:11:22:33:44:55 counter drop' "$ACTIVE")" = 2 ]
grep -Fq 'installed 2 per-client rates and 1 blocked MACs' "$CR6608_QOS_TEST_LOGGER_LOG"

# A dashboard-prefixed rule with an injected/mismatched MAC, wrong target, or
# group address is rejected before nft is invoked.  The live table and ACTIVE
# snapshot therefore remain the last valid block policy.
active_blocked="$(cat "$ACTIVE")"
for bad_record in \
  '@rule[0]|CR6608-Block-02:11:22:33:44:55;delete-table|02:11:22:33:44:55|REJECT' \
  '@rule[0]|CR6608-Block-02:11:22:33:44:55|02:11:22:33:44:56|REJECT' \
  '@rule[0]|CR6608-Block-02:11:22:33:44:55|02:11:22:33:44:55|ACCEPT' \
  '@rule[0]|CR6608-Block-01:00:5e:00:00:01|01:00:5e:00:00:01|REJECT' \
  '@rule[0]|CR6608-Block-ff:ff:ff:ff:ff:ff|ff:ff:ff:ff:ff:ff|REJECT' \
  '@rule[0]|CR6608-Block-00:00:00:00:00:00|00:00:00:00:00:00|REJECT'
do
  printf '%s\n' "$bad_record" >"$CR6608_QOS_TEST_BLOCK_DB"
  nft_lines_before="$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")"
  if sh "$APPLY"; then
    printf 'malformed CR6608 block rule unexpectedly succeeded: %s\n' "$bad_record" >&2
    exit 1
  fi
  [ "$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")" = "$nft_lines_before" ]
  [ "$(cat "$ACTIVE")" = "$active_blocked" ]
done
grep -Fq 'malformed CR6608 block rule; previous bridge policy kept' "$CR6608_QOS_TEST_LOGGER_LOG"

# QoS sections independently reject non-unicast or injected MAC values; a
# poisoned rate record can never become a broadcast/multicast-wide policer.
printf '%s\n' '@rule[0]|CR6608-Block-02:11:22:33:44:55|02:11:22:33:44:55|REJECT' >"$CR6608_QOS_TEST_BLOCK_DB"
for bad_mac in '00:00:00:00:00:00' 'ff:ff:ff:ff:ff:ff' '01:00:5e:00:00:01' '02:11:22:33:44:55;drop'; do
  printf '%s\n' "$bad_mac" 100 50 >"$CR6608_QOS_TEST_STATE"
  nft_lines_before="$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")"
  if sh "$APPLY"; then
    printf 'invalid QoS MAC unexpectedly succeeded: %s\n' "$bad_mac" >&2
    exit 1
  fi
  [ "$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")" = "$nft_lines_before" ]
  [ "$(cat "$ACTIVE")" = "$active_blocked" ]
done
printf '%s\n' 'AA:BB:CC:DD:EE:FF' 100 50 >"$CR6608_QOS_TEST_STATE"

# Removing the firewall record updates the same atomic table while retaining
# unrelated QoS rules.
: >"$CR6608_QOS_TEST_BLOCK_DB"
sh "$APPLY"
! grep -Fq 'SmartAP block' "$ACTIVE"
grep -Fq 'rate over 12500 kbytes/second' "$ACTIVE"

case "$(uname -s)" in
  MINGW*|MSYS*) : ;; # MSYS reports host ACL projection rather than chmod bits.
  *)
    [ "$(stat -c '%a' "$TMP/runtime")" = 700 ]
    [ "$(stat -c '%a' "$ACTIVE")" = 600 ]
    ;;
esac
! grep -Fq '/tmp' "$APPLY"
! grep -Eq 'cr6608-smartap-qos\.(forward|input|output|previous)\.\$\$' "$APPLY"
grep -Fq '"$NFT_BIN" -c -f -' "$APPLY"
grep -Fq '"$NFT_BIN" -f -' "$APPLY"
grep -Fq 'exec 9>"$LOCK_FILE"' "$APPLY"
grep -Fq '"$FLOCK_BIN" -xn 9' "$APPLY"
grep -Fq '"$FLOCK_BIN" -u 9' "$APPLY"
if grep -Eq '"\$FLOCK_BIN" .*(-w|-E)|CR6608_QOS_LOCK_HELD|"\$FLOCK_BIN" .*"\$LOCK_FILE" .*"\$SELF"' "$APPLY"; then
  printf 'QoS lock uses a non-BusyBox flock interface or bypass marker\n' >&2
  exit 1
fi

# Neither an active-policy symlink nor a symlinked runtime directory may be
# followed or replaced. Both cases fail before invoking nft.
saved_active="$TMP/saved-active"
mv "$ACTIVE" "$saved_active"
victim="$TMP/qos-victim"
printf 'victim-unchanged\n' >"$victim"
ln -s "$victim" "$ACTIVE"
nft_lines_before="$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")"
case "$(uname -s)" in
  MINGW*|MSYS*)
    # Git for Windows may materialize `ln -s` as a private regular text file;
    # that host representation cannot exercise the target's symlink gate.
    set +e
    sh "$APPLY" >/dev/null 2>&1
    set -e
    ;;
  *)
    if sh "$APPLY"; then
      printf 'smartap qos active symlink test unexpectedly succeeded\n' >&2
      exit 1
    fi
    [ "$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")" = "$nft_lines_before" ]
    ;;
esac
grep -Fqx 'victim-unchanged' "$victim"
rm -f "$ACTIVE"
mv "$saved_active" "$ACTIVE"

chmod 0644 "$ACTIVE"
case "$(uname -s)" in
  MINGW*|MSYS*)
    set +e
    sh "$APPLY" >/dev/null 2>&1
    set -e
    ;;
  *)
    if sh "$APPLY"; then
      printf 'smartap qos wrong-mode active file unexpectedly succeeded\n' >&2
      exit 1
    fi
    ;;
esac
grep -Fq 'rate over 12500 kbytes/second' "$ACTIVE"
chmod 0600 "$ACTIVE"

ln -s "$TMP/runtime" "$TMP/runtime-link"
case "$(uname -s)" in
  MINGW*|MSYS*)
    set +e
    CR6608_QOS_RUNTIME_DIR="$TMP/runtime-link" sh "$APPLY" >/dev/null 2>&1
    set -e
    ;;
  *)
    if CR6608_QOS_RUNTIME_DIR="$TMP/runtime-link" sh "$APPLY"; then
      printf 'smartap qos runtime symlink test unexpectedly succeeded\n' >&2
      exit 1
    fi
    ;;
esac

# Two callers that overlap at nft apply must serialize the complete read/apply/
# publish transaction. The second caller is started while the first mock nft
# apply is paused; it cannot acquire the lock or read/apply policy until the
# first publishes and releases. Final live rules and ACTIVE must be identical.
rm -f "$CR6608_QOS_TEST_EMPTY"
: >"$CR6608_QOS_TEST_BLOCK_DB"
printf '%s\n' 'AA:BB:CC:DD:EE:FF' 100 50 >"$CR6608_QOS_TEST_STATE"
: >"$CR6608_QOS_TEST_FLOCK_LOG"
rm -f "$CR6608_QOS_TEST_APPLY_ENTERED" "$CR6608_QOS_TEST_APPLY_RELEASE"
: >"$CR6608_QOS_TEST_PAUSE_APPLY"
sh "$APPLY" >"$TMP/concurrent-first.out" 2>"$TMP/concurrent-first.err" &
first_pid=$!
n=0
while [ ! -e "$CR6608_QOS_TEST_APPLY_ENTERED" ]; do
  n=$((n + 1)); [ "$n" -le 100 ] || { printf 'first concurrent QoS apply never reached nft\n' >&2; exit 1; }
  sleep 0.1
done
printf '%s\n' 'AA:BB:CC:DD:EE:FF' 200 80 >"$CR6608_QOS_TEST_STATE"
sh "$APPLY" >"$TMP/concurrent-second.out" 2>"$TMP/concurrent-second.err" &
second_pid=$!
n=0
while [ "$(grep -c '^try|' "$CR6608_QOS_TEST_FLOCK_LOG" 2>/dev/null || true)" -lt 2 ]; do
  n=$((n + 1)); [ "$n" -le 100 ] || { printf 'second concurrent QoS apply never requested lock\n' >&2; exit 1; }
  sleep 0.1
done
[ "$(grep -c '^acquire|' "$CR6608_QOS_TEST_FLOCK_LOG")" = 1 ] || {
  printf 'concurrent QoS callers entered the critical transaction together\n' >&2
  exit 1
}
: >"$CR6608_QOS_TEST_APPLY_RELEASE"
wait "$first_pid" || { sed 's/^/first: /' "$TMP/concurrent-first.err" >&2; exit 1; }
wait "$second_pid" || { sed 's/^/second: /' "$TMP/concurrent-second.err" >&2; exit 1; }
rm -f "$CR6608_QOS_TEST_PAUSE_APPLY" "$CR6608_QOS_TEST_APPLY_ENTERED" "$CR6608_QOS_TEST_APPLY_RELEASE"
[ "$(grep -c '^acquire|' "$CR6608_QOS_TEST_FLOCK_LOG")" = 2 ]
first_release_line="$(grep -n '^release|' "$CR6608_QOS_TEST_FLOCK_LOG" | sed -n '1s/:.*//p')"
second_acquire_line="$(grep -n '^acquire|' "$CR6608_QOS_TEST_FLOCK_LOG" | sed -n '2s/:.*//p')"
[ -n "$first_release_line" ] && [ -n "$second_acquire_line" ] &&
  [ "$first_release_line" -lt "$second_acquire_line" ] || {
    printf 'second QoS transaction acquired before the first released\n' >&2
    exit 1
  }
grep -Fq 'rate over 25000 kbytes/second' "$ACTIVE"
! grep -Fq 'rate over 12500 kbytes/second' "$ACTIVE"
cmp -s "$ACTIVE" "$CR6608_QOS_TEST_LIVE_TABLE" || {
  printf 'serialized QoS live table and ACTIVE snapshot diverged\n' >&2
  exit 1
}
[ ! -d "$TMP/runtime/apply.lock.mock-held" ]

# Lock contention has a bounded, explicit failure and cannot touch nft. Kernel
# flock releases ownership automatically when a holder exits, avoiding stale
# PID/lock-directory cleanup races.
mkdir "$TMP/runtime/apply.lock.mock-held"
printf '999999\n' >"$TMP/runtime/apply.lock.mock-held/owner"
nft_lines_before="$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")"
if CR6608_QOS_LOCK_WAIT_MAX=1 sh "$APPLY"; then
  printf 'contended QoS apply lock unexpectedly succeeded\n' >&2
  exit 1
fi
[ "$(wc -l <"$CR6608_QOS_TEST_NFT_LOG")" = "$nft_lines_before" ]
grep -Fq 'timed out waiting for serialized QoS apply' "$CR6608_QOS_TEST_LOGGER_LOG"
rm -f "$TMP/runtime/apply.lock.mock-held/owner"
rmdir "$TMP/runtime/apply.lock.mock-held"
case "$(uname -s)" in
  MINGW*|MSYS*) : ;;
  *)
    [ "$(stat -c '%a' "$TMP/runtime/apply.lock")" = 600 ]
    chmod 0644 "$TMP/runtime/apply.lock"
    if sh "$APPLY"; then
      printf 'QoS apply accepted a non-private lock file\n' >&2
      exit 1
    fi
    chmod 0600 "$TMP/runtime/apply.lock"
    ;;
esac

# A block-only configuration must keep the bridge table even when no QoS
# sections exist. A failed replacement keeps the previous blocked MAC
# atomically and never publishes the requested update.
: >"$CR6608_QOS_TEST_EMPTY"
printf '%s\n' '@rule[0]|CR6608-Block-02:11:22:33:44:55|02:11:22:33:44:55|REJECT' >"$CR6608_QOS_TEST_BLOCK_DB"
sh "$APPLY"
grep -Fq 'ether saddr 02:11:22:33:44:55 counter drop' "$ACTIVE"
! grep -Fq 'rate over' "$ACTIVE"
block_only_before="$(cat "$ACTIVE")"
printf '%s\n' '@rule[0]|CR6608-Block-02:aa:bb:cc:dd:ee|02:aa:bb:cc:dd:ee|REJECT' >"$CR6608_QOS_TEST_BLOCK_DB"
: >"$CR6608_QOS_TEST_FAIL_APPLY"
if sh "$APPLY"; then
  printf 'smartap block atomic-failure test unexpectedly succeeded\n' >&2
  exit 1
fi
[ "$(cat "$ACTIVE")" = "$block_only_before" ]
grep -Fq '02:11:22:33:44:55' "$CR6608_QOS_TEST_LAST_LOADED"
! grep -Fq '02:aa:bb:cc:dd:ee' "$CR6608_QOS_TEST_LAST_LOADED"
rm -f "$CR6608_QOS_TEST_FAIL_APPLY"

# Empty policy removal is successful only after nft confirms the live table is
# absent. Query and delete failures preserve both the table and ACTIVE copy.
: >"$CR6608_QOS_TEST_BLOCK_DB"
active_before="$(cat "$ACTIVE")"
: >"$CR6608_QOS_TEST_FAIL_LIST"
if sh "$APPLY"; then
  printf 'smartap qos nft-query-failure test unexpectedly succeeded\n' >&2
  exit 1
fi
[ -e "$CR6608_QOS_TEST_TABLE_PRESENT" ]
[ "$(cat "$ACTIVE")" = "$active_before" ]
rm -f "$CR6608_QOS_TEST_FAIL_LIST"
: >"$CR6608_QOS_TEST_FAIL_DELETE"
if sh "$APPLY"; then
  printf 'smartap qos delete-failure test unexpectedly succeeded\n' >&2
  exit 1
fi
[ -e "$CR6608_QOS_TEST_TABLE_PRESENT" ]
[ "$(cat "$ACTIVE")" = "$active_before" ]
grep -Fq 'active snapshot kept' "$CR6608_QOS_TEST_LOGGER_LOG"
rm -f "$CR6608_QOS_TEST_FAIL_DELETE"
sh "$APPLY"
[ ! -e "$CR6608_QOS_TEST_TABLE_PRESENT" ]
[ ! -e "$ACTIVE" ]

printf 'smartap_qos_apply=pass\n'
