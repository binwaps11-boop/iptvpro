#!/bin/sh
set -eu

fail() {
	printf '%s\n' "$*" >&2
	exit 1
}

if [ -z "${OPENWRT_ROOT:-}" ]; then
	OPENWRT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../openwrt" 2>/dev/null && pwd)" ||
		fail "Set OPENWRT_ROOT to the pinned OpenWrt checkout"
fi

PATCH_FILE="${PATCH_FILE:-${OPENWRT_ROOT}/target/linux/ramips/patches-6.12/140-net-dsa-mt7530-do-not-advertise-EEE-on-MT7621-switch.patch}"
DTS_FILE="${OPENWRT_ROOT}/target/linux/ramips/dts/mt7621.dtsi"

[ -f "$PATCH_FILE" ] || fail "missing MT7621 early-EEE patch: $PATCH_FILE"
[ -f "$DTS_FILE" ] || fail "missing MT7621 DTS: $DTS_FILE"

grep -Fq 'if (priv->id == ID_MT7621)' "$PATCH_FILE" ||
	fail "patch is not gated to the MT7621 switch"
grep -Fq 'MT7530_NUM_PHYS' "$PATCH_FILE" ||
	fail "patch does not cover every integrated switch PHY"
grep -Fq 'MDIO_AN_EEE_ADV, 0' "$PATCH_FILE" ||
	fail "patch does not clear EEE advertisement"

broken_100tx_count="$(grep -Fc 'eee-broken-100tx;' "$DTS_FILE" || true)"
broken_1000t_count="$(grep -Fc 'eee-broken-1000t;' "$DTS_FILE" || true)"
[ "$broken_100tx_count" -ge 5 ] ||
	fail "DTS does not mark all five MT7530 PHYs broken at 100BASE-TX"
[ "$broken_1000t_count" -ge 5 ] ||
	fail "DTS does not mark all five MT7530 PHYs broken at 1000BASE-T"

if [ -n "${LINUX_TREE:-}" ]; then
	[ -f "${LINUX_TREE}/drivers/net/dsa/mt7530.c" ] ||
		fail "LINUX_TREE does not contain drivers/net/dsa/mt7530.c"
	patch -d "$LINUX_TREE" -p1 --dry-run < "$PATCH_FILE" >/dev/null ||
		fail "MT7621 early-EEE patch does not apply cleanly to LINUX_TREE"
fi

printf '%s\n' 'mt7621_eee_early_disable_contract=pass'
