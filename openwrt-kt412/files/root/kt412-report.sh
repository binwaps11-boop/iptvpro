#!/bin/sh
# KT412 — REAL proof report (all 2.4G channels 1..11). Device values only.

echo "===== BOARD ====="
ubus call system board
cat /etc/openwrt_release

echo "===== IWINFO ====="
iwinfo

echo "===== 2.4G IWINFO ====="
iwinfo phy1-ap0 info

echo "===== 5G IWINFO ====="
iwinfo phy0-ap0 info

echo "===== PHY1 2.4G ALL CHANNELS POWER TABLE ====="
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

echo "===== 2.4G CHANNEL TEST (1..11) ====="
for ch in 1 2 3 4 5 6 7 8 9 10 11; do
    echo "---- CHANNEL $ch ----"
    uci set wireless.radio0.channel="$ch"
    uci set wireless.radio0.txpower="30"
    uci commit wireless
    wifi reload
    sleep 8
    iwinfo phy1-ap0 info | grep -i "Tx-Power"
    iw dev phy1-ap0 info 2>/dev/null | grep -iE "channel|txpower"
    echo -n "user_power="; cat /sys/kernel/debug/ieee80211/phy1/user_power 2>/dev/null
    echo -n "netdev txpower="; cat /sys/kernel/debug/ieee80211/phy1/netdev:phy1-ap0/txpower 2>/dev/null
done

echo "===== ATH9K EEPROM DEBUG (read only) ====="
cat /sys/kernel/debug/ieee80211/phy1/ath9k/base_eeprom 2>/dev/null
cat /sys/kernel/debug/ieee80211/phy1/ath9k/modal_eeprom 2>/dev/null

echo "===== LOGS ====="
dmesg | grep -Ei "ath9k|eeprom|cal|art|txpower|power|regdomain" | tail -200

echo "===== POWER 4-LAYER REPORT ====="
cat /root/POWER-REPORT.txt 2>/dev/null
