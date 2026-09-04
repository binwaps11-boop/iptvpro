#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
policy="${CR6608_LEGACY_11B_POLICY:-${script_dir}/../files/etc/uci-defaults/95-cr6608-enable-legacy-11b}"
wireless="${CR6608_WIRELESS_CONFIG:-${script_dir}/../files/etc/config/wireless}"

sh -n "$policy"
[ -s "$wireless" ]
grep -Fq "xiaomi,mi-router-cr6608" "$policy"
grep -Fq '2g|2.4g)' "$policy"
grep -Fq 'legacy_rates=1' "$policy"
! grep -Eq '5g\|.*legacy_rates=1|legacy_rates=1.*5g' "$policy"
grep -Fq 'uci commit wireless' "$policy"

awk '
	/^config wifi-device '\''radio0'\''$/ { radio = "radio0"; next }
	/^config wifi-device '\''radio1'\''$/ { radio = "radio1"; next }
	/^config / { radio = "" }
	radio == "radio0" && /option legacy_rates '\''1'\''/ { radio0 = 1 }
	radio == "radio1" && /option legacy_rates '\''0'\''/ { radio1 = 1 }
	END { exit !(radio0 && radio1) }
' "$wireless"

printf 'legacy_11b_contract=pass\n'
