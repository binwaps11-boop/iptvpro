#!/bin/sh
# KT412 RF + system-power report for 2.4GHz (QCA9558/ath9k/phy1).
# Reads ONLY. Never writes ART/EEPROM/caldata/mtd10. Produces SYSTEM_POWER_RESULT.txt.
# Run: sh /root/kt412-rf-report.sh   (then copy the output + /root/SYSTEM_POWER_RESULT.txt)
OUT=/root/SYSTEM_POWER_RESULT.txt
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
P=/sys/kernel/debug/ieee80211/phy1
IF="$(iw dev 2>/dev/null | awk '/^phy#1/{p=1;next}/^phy#/{p=0} p&&$1=="Interface"{print $2;exit}')"
[ -n "$IF" ] || IF=phy1-ap0

req="$(uci -q get wireless.radio0.txpower)"
userp="$(cat $P/user_power 2>/dev/null)"
netp="$(cat $P/netdev:$IF/txpower 2>/dev/null)"
[ -n "$netp" ] || netp="$(find $P -path '*netdev*txpower' 2>/dev/null | head -1 | xargs cat 2>/dev/null)"
iwp="$(iwinfo "$IF" info 2>/dev/null | sed -n 's/.*Tx-Power:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)"
phyp="$(iw phy phy1 info 2>/dev/null | sed -n 's/.*2412.0 MHz.*(\([0-9.]*\) dBm).*/\1/p' | head -1)"
# EEPROM target (max of the calibrated 2.4G target power table, as ath9k reports it)
eeptgt="$(cat $P/ath9k/tpc 2>/dev/null | sed -n 's/.*[Mm]ax[^0-9-]*\([0-9]*\).*/\1/p' | head -1)"
markers="$(dmesg 2>/dev/null | grep -c 'KT412-30DBM')"
trace="$(dmesg 2>/dev/null | grep 'KT412-30DBM-TRACE' | head -1)"

{
echo "=========================================================================="
echo "KT412 2.4GHz SYSTEM POWER RESULT  (QCA9558 / ath9k / phy1 / $IF)"
echo "generated: $(date 2>/dev/null)"
echo "build: $(grep -h . /etc/kt412-build-info 2>/dev/null | tr '\n' ' ')"
echo "=========================================================================="
echo
echo "------ A) SYSTEM / DRIVER POWER (what the chip is commanded to do) ------"
echo "System requested power (uci txpower) ... ${req:-?} dBm"
echo "debugfs user_power ..................... ${userp:-?} dBm   (the request reached the stack)"
echo "PHY advertised power (iw phy CH1) ...... ${phyp:-?} dBm"
echo "iwinfo Tx-Power ........................ ${iwp:-?} dBm"
echo "System applied netdev power ............ ${netp:-?} dBm   <== THE decisive value"
echo "EEPROM target power (ath9k tpc max) .... ${eeptgt:-see tpc/base_eeprom} (calibrated clean ceiling)"
echo "dmesg KT412-30DBM markers found ........ ${markers:-0}"
echo "trace line ............................. ${trace:-<none - patched kernel NOT running>}"
echo
if [ "$netp" = "30" ] || [ "$netp" = "30.00" ]; then
  echo "RESULT(System): PASS — netdev txpower = 30 (driver layer fixed)."
else
  echo "RESULT(System): FAIL — netdev txpower = ${netp:-?}, not 30. If markers=0 then the"
  echo "                 patched ath9k is NOT the running module (wrong image/patch path)."
fi
echo
echo "------ B) RF REALITY (honest; not measured here unless you have a meter) ------"
echo "Chains (TX mask) ....................... 2 (chain0+1, 2x2) — see base_eeprom"
echo "External PA ............................ PRESENT (XPA fields in modal_eeprom)"
echo "Estimated conducted RF / chain ......... ~24-26 dBm CLEAN (PA P1dB; EEPROM target=24)"
echo "Estimated aggregate conducted (2 ch) ... ~27-29 dBm"
echo "Antenna gain (typ) ..................... ~2-4 dBi"
echo "Cable/connector loss ................... ~0.5-1 dB"
echo "Estimated EIRP ......................... ~29-32 dBm (plausible 30 EIRP)"
echo "Measured conducted RF .................. NOT MEASURED (needs power meter + attenuator)"
echo "RF clean limit (this board) ............ ~25-26 dBm/chain conducted"
echo "Thermal ................................ Temp comp ON (Temp Slope=56) -> backs off when hot"
echo "Required HW for real 30 dBm conducted .. bigger external PA (P1dB>=32dBm)/chain + supply +"
echo "                                          cooling + recal; OR use +6 dBi antennas for 30 EIRP"
echo
echo "------ C) RAW EEPROM TABLES (read-only proof) ------"
echo "--- ath9k/tpc ---";          cat $P/ath9k/tpc 2>/dev/null | head -50
echo "--- base_eeprom (chains/PA) ---"; cat $P/ath9k/base_eeprom 2>/dev/null | sed -n '1,40p'
echo "--- modal_eeprom (2GHz PA/atten/temp) ---"; cat $P/ath9k/modal_eeprom 2>/dev/null | sed -n '1,45p'
echo "=========================================================================="
echo "See /root/RF_CHAIN_ANALYSIS.txt and /root/RF_SOLUTION.txt for the full analysis."
echo "=========================================================================="
} | tee "$OUT"
echo
echo "Saved -> $OUT"
