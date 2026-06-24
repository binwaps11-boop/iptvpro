#!/bin/sh
# KT412 — REAL proof report. Run:  sh /root/kt412-report.sh
# Outputs are the device's actual values — nothing is fabricated.

echo "===== BOARD ====="
ubus call system board
cat /etc/openwrt_release

echo "===== IWINFO ====="
iwinfo

echo "===== 2.4G IWINFO ====="
iwinfo phy1-ap0 info

echo "===== 5G IWINFO ====="
iwinfo phy0-ap0 info

echo "===== PHY1 2.4G TABLE ====="
iw phy phy1 info | grep -E "2412|2417|2422|2427|2432|2437|2442|2447|2452|2457|2462|dBm|disabled" -A2

echo "===== PHY0 5G TABLE ====="
iw phy phy0 info

echo "===== WIFI STATUS ====="
wifi status 2>/dev/null || ubus call network.wireless status

echo "===== REGDOMAIN ====="
iw reg get

echo "===== DEBUGFS POWER ====="
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
echo "user_power:"
cat /sys/kernel/debug/ieee80211/phy1/user_power 2>/dev/null
echo "netdev txpower:"
cat /sys/kernel/debug/ieee80211/phy1/netdev:phy1-ap0/txpower 2>/dev/null

echo "===== ATH9K EEPROM DEBUG ====="
cat /sys/kernel/debug/ieee80211/phy1/ath9k/base_eeprom 2>/dev/null
cat /sys/kernel/debug/ieee80211/phy1/ath9k/modal_eeprom 2>/dev/null

echo "===== LOGS ====="
dmesg | grep -Ei "ath9k|eeprom|cal|art|txpower|power|regdomain" | tail -200
