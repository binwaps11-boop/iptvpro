#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/src/cr6608-mndp-advertise.c"
SERVICE="$ROOT/files/usr/sbin/cr6608-neighbor-service"
INIT="$ROOT/files/etc/init.d/cr6608-neighbor"
DASHCTL="$ROOT/files/www/cgi-bin/dashctl"
DASHAPI="$ROOT/files/www/cgi-bin/dashapi2"
HELPER="$ROOT/files/usr/libexec/cr6608-private-runtime"
OVERLAY_BINARY="$ROOT/files/usr/sbin/cr6608-mndp-advertise"
PACKAGE_MAKEFILE="$ROOT/packages/cr6608-mndp/Makefile"
SEED="$ROOT/cr6608.seed.config"

fail() {
	printf 'mndp_source_contract=fail: %s\n' "$*" >&2
	exit 1
}

for required in "$SOURCE" "$SERVICE" "$INIT" "$DASHCTL" "$DASHAPI" "$HELPER" \
	"$PACKAGE_MAKEFILE" "$SEED" "$ROOT/build.sh" "$ROOT/build.remote.sh"; do
	[ -s "$required" ] || fail "missing $required"
done
[ ! -e "$OVERLAY_BINARY" ] && [ ! -L "$OVERLAY_BINARY" ] || \
	fail "opaque overlay MNDP binary remains"
grep -Fqx 'CONFIG_PACKAGE_cr6608-mndp=y' "$SEED" || \
	fail "seed does not select the source-built MNDP package"
grep -Fq '$(CP) ./src/cr6608-mndp-advertise.c $(PKG_BUILD_DIR)/' \
	"$PACKAGE_MAKEFILE" && \
	grep -Fq '$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS)' \
		"$PACKAGE_MAKEFILE" && \
	grep -Fq -- '-std=c11 -Wall -Wextra -Werror' "$PACKAGE_MAKEFILE" && \
	grep -Fq '$(INSTALL_BIN) $(PKG_BUILD_DIR)/cr6608-mndp-advertise' \
		"$PACKAGE_MAKEFILE" && \
	grep -Fq '$(1)/usr/sbin/cr6608-mndp-advertise' "$PACKAGE_MAKEFILE" || \
	fail "MNDP package does not compile/install the audited source"
for build_script in "$ROOT/build.sh" "$ROOT/build.remote.sh"; do
	grep -Fq 'SRC_MNDP_PACKAGE="${SCRIPT_DIR}/packages/cr6608-mndp"' \
		"$build_script" && \
		grep -Fq 'SRC_MNDP_SOURCE="${SCRIPT_DIR}/src/cr6608-mndp-advertise.c"' \
			"$build_script" && \
		grep -Fq 'cp -a -- "${SRC_MNDP_PACKAGE}" "${MNDP_PACKAGE_DIR}"' \
			"$build_script" && \
		grep -Fq 'install -m 0644 -- "${SRC_MNDP_SOURCE}"' "$build_script" && \
		grep -Fq '"${MNDP_PACKAGE_DIR}/src/cr6608-mndp-advertise.c"' \
			"$build_script" && \
		grep -Fq 'Opaque MNDP overlay binary is forbidden' "$build_script" && \
		grep -Fq 'sh "${MNDP_SOURCE_TEST}"' "$build_script" || \
		fail "$(basename "$build_script") does not stage/test source-built MNDP or forbid the overlay binary"
done
for stale_path in /tmp/cr6608-mndp.fields /tmp/cr6608-neighbor.status; do
	! grep -Fq "$stale_path" "$SERVICE" "$DASHCTL" "$DASHAPI" "$SOURCE" || \
		fail "predictable legacy path remains: $stale_path"
done
grep -Fq 'cr6608_private_runtime_dir neighbor' "$SERVICE" || \
	fail "neighbor service does not use private runtime helper"
grep -Fq 'procd_set_param command /usr/sbin/cr6608-neighbor-service' "$INIT" || \
	fail "neighbor init does not launch the audited service"
grep -Fq 'cr6608_private_mktemp' "$SERVICE" && \
	grep -Fq 'cr6608_private_publish_file' "$SERVICE" || \
	fail "neighbor fields are not random/private/atomic"
grep -Fq '/var/run/cr6608-private/neighbor/status' "$DASHCTL" "$DASHAPI" || \
	fail "neighbor status consumers do not use the private path"
grep -Fq '/var/run/cr6608-private/neighbor/fields' "$DASHAPI" || \
	fail "neighbor identity consumer does not use the private path"
! grep -Fq 'cr6608-neighbor-service --once' "$DASHCTL" || \
	fail "dashboard launches a competing one-shot sender instead of refreshing the persistent daemon"
grep -Fq 'neighbor_service_refresh_bounded()' "$DASHCTL" && \
	grep -Fq 'run_limit "${CR6608_NEIGHBOR_TIMEOUT:-45}" "$_neighbor_init" restart' "$DASHCTL" && \
	grep -Fq "cr6608_private_stat -c '%u:%a:%h' \"\$_neighbor_fields\"" "$DASHCTL" && \
	grep -Fq '0:disabled|1:active' "$DASHCTL" || \
	fail "dashboard does not restart and verify the persistent neighbor daemon"
save_identity_block="$(sed -n '/^  save_identity)/,/^  save_royal)/p' "$DASHCTL")"
printf '%s\n' "$save_identity_block" | grep -Fq 'neighbor_service_refresh_bounded || {' || \
	fail "identity save path does not fail when the persistent daemon cannot load fields"
save_royal_block="$(sed -n '/^  save_royal)/,/^  reset_royal)/p' "$DASHCTL")"
printf '%s\n' "$save_royal_block" | grep -Fq 'neighbor_service_refresh_bounded || royal_abort_transaction' || \
	fail "Quick Setup save claims success without refreshing the persistent neighbor daemon"
apply_royal_block="$(sed -n '/^  apply_royal)/,/^  save_quick)/p' "$DASHCTL")"
printf '%s\n' "$apply_royal_block" | grep -Fq 'neighbor_service_refresh_bounded || royal_abort_apply' || \
	fail "Quick Setup apply claims success without refreshing the persistent neighbor daemon"
grep -Fq 'neighbor_service_refresh_bounded || _royal_restore_rc=1' "$DASHCTL" || \
	fail "dashboard rollback can leave the daemon advertising rejected identity fields"
grep -Fq 'destination.sin_addr.s_addr = htonl(INADDR_BROADCAST)' "$SOURCE" || \
	fail "MNDP does not target limited broadcast"
grep -Fq 'destination.sin_port = htons(MNDP_PORT)' "$SOURCE" && \
	grep -Fq 'local.sin_port = htons(MNDP_PORT)' "$SOURCE" || \
	fail "MNDP source/destination UDP port 5678 contract is absent"
grep -Fq '#define MNDP_RECEIVE_DRAIN_LIMIT 64' "$SOURCE" && \
	grep -Fq 'recv(sender, discard, sizeof(discard), MSG_DONTWAIT)' "$SOURCE" && \
	grep -Fq 'drained < MNDP_RECEIVE_DRAIN_LIMIT' "$SOURCE" && \
	grep -Fq 'drain_or_reopen_sender(&sender)' "$SOURCE" && \
	grep -Fq '*sender = open_sender_socket();' "$SOURCE" && \
	grep -Fq 'if (!drain_or_reopen_sender(&sender))' "$SOURCE" && \
	grep -Fq 'bool sender_should_run = false;' "$SOURCE" && \
	grep -Fq 'if (sender_should_run)' "$SOURCE" && \
	grep -Fq 'sender = -1;' "$SOURCE" && \
	grep -Fq '"--inject-live-probe"' "$SOURCE" && \
	grep -Fq 'mndp_live_queue_probe=sent:%u' "$SOURCE" || \
	fail "MNDP bounded nonblocking receive drain and disabled close contract is absent"
grep -Fq 'packet_info->ipi_spec_dst = source' "$SOURCE" || \
	fail "MNDP source address is not pinned to the LAN interface"
grep -Fq 'br-lan.' "$SOURCE" || fail "MNDP VLAN bridge support is absent"
grep -Fq 'RESCUE_IPV4_HOST UINT32_C(0xdddddddd)' "$SOURCE" && \
	grep -Fq '!source_address_advertisable(address->sin_addr)' "$SOURCE" || \
	fail "MNDP can advertise the protected 221.221.221.221 rescue endpoint"
grep -Fq 'internet_checksum(packet, used)' "$SOURCE" && \
	grep -Fq 'packet[2] = 0x00' "$SOURCE" && \
	grep -Fq 'put_be16(packet + 2' "$SOURCE" || \
	fail "MNDP deployed checksum wire contract is absent"
! grep -Eq 'uint16_t sequence|sequence[+][+]|put_be16[(]packet [+] 2, sequence' \
	"$SOURCE" || \
	fail "MNDP checksum word regressed to a sequence number"

CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || fail "host C compiler unavailable"
STRINGS_BIN="${STRINGS:-strings}"
command -v "$STRINGS_BIN" >/dev/null 2>&1 || fail "host strings tool unavailable"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-mndp-source.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
"$CC_BIN" -std=c11 -O2 -Wall -Wextra -Werror -fdata-sections \
	-Wl,--gc-sections "$SOURCE" -o "$TMP/cr6608-mndp-advertise" || \
	fail "auditable MNDP source does not compile cleanly"
"$STRINGS_BIN" "$TMP/cr6608-mndp-advertise" | \
	grep -Fqx 'cr6608-mndp-source-v4' || \
	fail "MNDP source provenance marker was garbage-collected"
python3 "$ROOT/tests/test-mndp-packet.py" "$TMP/cr6608-mndp-advertise" || \
	fail "MNDP packet/private-file runtime contract"

printf 'mndp_source_contract=pass\n'
