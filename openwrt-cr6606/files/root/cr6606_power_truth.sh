#!/bin/sh

echo "===== CR6606 POWER TRUTH ====="

echo ""
echo "===== REGDOMAIN ====="
iw reg get 2>/dev/null

echo ""
echo "===== IWINFO ====="
iwinfo 2>/dev/null

echo ""
echo "===== PHY TABLE ====="
iw phy 2>/dev/null | grep -E "Wiphy|Band|2412|2417|2422|2427|2432|2437|2442|2447|2452|2457|2462|5180|5200|5220|5240|5260|5280|5300|5320|5500|5520|5540|5560|5580|5600|5620|5640|5660|5680|5700|5720|5745|5765|5785|5805|5825|dBm|disabled" -A5

echo ""
echo "===== UCI WIRELESS ====="
uci show wireless | grep -E "country|channel|htmode|txpower|txantenna|rxantenna|diversity|disabled|band|path"

echo ""
echo "===== IW DEV ====="
iw dev 2>/dev/null

echo ""
echo "===== STATION DUMP ====="
for i in $(iw dev 2>/dev/null | awk '/Interface/ {print $2}'); do
  echo ""
  echo "----- $i -----"
  iw dev "$i" station dump 2>/dev/null | grep -E "Station|signal:|signal avg:|tx bitrate|rx bitrate|tx retries|tx failed|expected throughput|connected time"
done

echo ""
echo "===== SURVEY / CHANNEL BUSY ====="
for i in $(iw dev 2>/dev/null | awk '/Interface/ {print $2}'); do
  echo ""
  echo "----- $i -----"
  iw dev "$i" survey dump 2>/dev/null | grep -A8 "in use"
done

echo ""
echo "===== DMESG ====="
dmesg | grep -Ei "CR6606|30DBM|mt76|mt7915|eeprom|factory|cal|power|txpower|thermal|chain|antenna|regdomain|country|dfs" | tail -300
