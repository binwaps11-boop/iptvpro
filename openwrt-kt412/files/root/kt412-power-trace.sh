#!/bin/sh
# KT412 power-trace: prove EXACTLY what is running on the device and where 30->24.
# Run: sh /root/kt412-power-trace.sh   (copy the whole output back).
echo "========================= KT412 POWER TRACE ========================="
echo "## build info"; cat /etc/kt412-build-info 2>/dev/null || echo "(no build-info)"
echo; echo "## kernel"; uname -a; cat /etc/openwrt_release 2>/dev/null
echo; echo "## PATCH ACTIVE? (must show KT412-30DBM-PATCH-ACTIVE if patched ath9k is running)"
dmesg 2>/dev/null | grep -i 'KT412-30DBM-PATCH-ACTIVE' || echo "NOT FOUND -> running kernel/ath9k is NOT the patched code!"
echo; echo "## kernel config (ATH_USER_REGD / ath drivers)"
( zcat /proc/config.gz 2>/dev/null || cat /etc/kt412-kernel-config.txt 2>/dev/null ) | grep -E 'ATH_USER_REGD|CONFIG_ATH9K|CONFIG_ATH10K|CFG80211|MAC80211' || echo "(no kernel config on device)"
echo; echo "## regulatory"; iw reg get 2>/dev/null
echo; echo "## iwinfo 2.4G"; iwinfo phy1-ap0 info 2>/dev/null
echo "## iwinfo 5G"; iwinfo phy0-ap0 info 2>/dev/null
echo; echo "## iw phy phy1 (2.4G per-channel dBm)"
iw phy phy1 info 2>/dev/null | grep -E "2412|2417|2422|2427|2432|2437|2442|2447|2452|2457|2462|dBm" -A1
echo; echo "## iw phy phy0 (5G)"; iw phy phy0 info 2>/dev/null | grep -E 'MHz \[' | head
echo; echo "## debugfs power"
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
echo -n "phy1 user_power        = "; cat /sys/kernel/debug/ieee80211/phy1/user_power 2>/dev/null
echo -n "phy1 netdev txpower    = "; cat /sys/kernel/debug/ieee80211/phy1/netdev:phy1-ap0/txpower 2>/dev/null
echo -n "phy0 user_power        = "; cat /sys/kernel/debug/ieee80211/phy0/user_power 2>/dev/null
echo -n "phy0 netdev txpower    = "; cat /sys/kernel/debug/ieee80211/phy0/netdev:phy0-ap0/txpower 2>/dev/null
echo; echo "## ath9k EEPROM / tpc (read-only)"
cat /sys/kernel/debug/ieee80211/phy1/ath9k/tpc 2>/dev/null | head -40
echo "--- base_eeprom ---"; cat /sys/kernel/debug/ieee80211/phy1/ath9k/base_eeprom 2>/dev/null | head -30
echo "--- modal_eeprom ---"; cat /sys/kernel/debug/ieee80211/phy1/ath9k/modal_eeprom 2>/dev/null | head -40
echo; echo "## uci txpower"; uci -q get wireless.radio0.txpower; uci -q get wireless.radio1.txpower
echo; echo "## dmesg (ath9k/power/regdomain/eeprom)"
dmesg 2>/dev/null | grep -Ei "KT412|30DBM|ath9k|qca955|wmac|txpower|power|regdomain|eeprom|cal" | tail -200
echo "========================= END TRACE ========================="
