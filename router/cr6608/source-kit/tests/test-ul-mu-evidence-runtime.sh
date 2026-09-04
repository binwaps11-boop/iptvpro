#!/bin/sh
#
# Runtime contract for cr6608-ul-mu-evidence against a mocked debugfs tree.
# The tool must never claim uplink MU-MIMO from a single peer, must never
# claim anything at all when the driver lacks the attribution nodes, and must
# always print its evidence boundary.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/files/usr/sbin/cr6608-ul-mu-evidence"

fail() {
	printf 'ul mu evidence contract failed: %s\n' "$*" >&2
	exit 1
}

[ -x "$TOOL" ] || fail 'tool missing or not executable'
sh -n "$TOOL" || fail 'tool syntax error'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

mask_file="$WORK/mask"
printf '15\n' > "$mask_file"

radio() {
	# radio <phy> <band> <tb> <ofdma_ru> <full_bw> <ofdma_groups> <mumimo_groups> <max_peers>
	d="$WORK/debug/$1/mt76"
	mkdir -p "$d"
	{
		printf 'band=%s\n' "$2"
		printf 'armed_mask=15\n'
		printf 'he_tb_ppdu=%s\n' "$3"
		printf 'he_tb_ul_ofdma_ru=%s\n' "$4"
		printf 'he_tb_full_bw=%s\n' "$5"
		printf 'ul_ofdma_multi_user_ppdus=%s\n' "$6"
		printf 'ul_mumimo_multi_user_ppdus=%s\n' "$7"
		printf 'max_peers_in_one_ppdu=%s\n' "$8"
		printf 'evidence=client-attributed-rx-descriptor-wcid\n'
		printf 'note=host-observed-scheduling-evidence-not-a-regulatory-or-rf-measurement\n'
	} > "$d/cr6608_ul_attribution"
}

peer() {
	# peer <phy> <mac> <wcid> <tb> <ofdma_ru> <full_bw> <shared>
	d="$WORK/debug/$1/netdev:wlan0/stations/$2"
	mkdir -p "$d"
	{
		printf 'wcid=%s\n' "$3"
		printf 'he_tb_ppdu=%s\n' "$4"
		printf 'he_tb_ul_ofdma_ru=%s\n' "$5"
		printf 'he_tb_full_bw=%s\n' "$6"
		printf 'he_tb_ul_mumimo_shared=%s\n' "$7"
		printf 'last_tb_timestamp=123456\n'
		printf 'evidence=client-attributed-rx-descriptor-wcid\n'
	} > "$d/cr6608_ul_attribution"
}

run() {
	CR6608_UL_MURU_DEBUG_ROOT="$WORK/debug" \
	CR6608_MURU_MASK_MODULE_PARAM="$mask_file" \
	sh "$TOOL"
}

verdict_is() {
	out="$(run)"
	got="$(printf '%s\n' "$out" | sed -n 's/^verdict=//p')"
	[ "$got" = "$1" ] || {
		printf '%s\n' "$out" >&2
		fail "expected verdict $1, got ${got:-<none>}"
	}
}

# 1. No driver nodes at all.
mkdir -p "$WORK/debug"
verdict_is NO_ATTRIBUTION_NODES

# 2. Radio present, nothing received.
radio phy0 1 0 0 0 0 0 0
verdict_is NO_TRIGGER_RESPONSE_OBSERVED

# 3. One peer answering triggers is NOT multi-user.
radio phy0 1 40 40 0 0 0 1
peer phy0 aa:bb:cc:dd:ee:01 1 40 40 0 0
verdict_is TRIGGER_RESPONSE_ONLY_NO_MULTI_USER_PPDU_YET

# 4. Two peers sharing sub-bandwidth RU PPDUs is UL OFDMA.
radio phy0 1 80 80 0 7 0 2
peer phy0 aa:bb:cc:dd:ee:02 2 40 40 0 0
verdict_is UL_OFDMA_CLIENT_ATTRIBUTED

# 5. A single peer must never be enough for UL MU-MIMO, even when the radio
#    reports multi-user groups: attribution needs two distinct peers.
radio phy0 1 80 0 80 0 5 2
rm -rf "$WORK/debug/phy0/netdev:wlan0/stations"
peer phy0 aa:bb:cc:dd:ee:01 1 80 0 80 5
verdict_is TRIGGER_RESPONSE_ONLY_NO_MULTI_USER_PPDU_YET
run | grep -q 'verdict=UL_MUMIMO' && fail 'a single peer produced a UL MU-MIMO claim'

# 6. Two peers each carrying shared full-bandwidth TB PPDUs is UL MU-MIMO.
peer phy0 aa:bb:cc:dd:ee:02 2 80 0 80 5
verdict_is UL_MUMIMO_CLIENT_ATTRIBUTED

# 7. Malformed counters must not be reported as evidence.
printf 'band=1\narmed_mask=15\nhe_tb_ppdu=notanumber\n' \
	> "$WORK/debug/phy0/mt76/cr6608_ul_attribution"
run | grep -q 'status=malformed' || fail 'malformed radio record was not rejected'

# 8. The evidence boundary must always be printed.
radio phy0 1 0 0 0 0 0 0
run | grep -qx 'evidence_boundary=host-observed-scheduling-evidence-not-an-rf-regulatory-or-throughput-measurement' ||
	fail 'evidence boundary line is missing'

# 9. The tool must be read-only: no writes into the mocked tree.
before="$(find "$WORK/debug" -type f -newer "$mask_file" | wc -l)"
run >/dev/null
after="$(find "$WORK/debug" -type f -newer "$mask_file" | wc -l)"
[ "$before" = "$after" ] || fail 'tool modified the debugfs tree'

printf 'ul_mu_evidence_runtime=pass\n'
