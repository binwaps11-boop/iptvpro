#!/bin/sh
# KT412 Wi-Fi verification (2.4G ath9k + 5G ath10k-ct). Real values only.
echo "===== WIFI STATUS ====="; wifi status 2>/dev/null
echo "===== REG DOMAIN ====="; iw reg get 2>/dev/null
echo "===== IWINFO (per radio) ====="
for d in $(iwinfo 2>/dev/null | grep -oE '^[a-z0-9]+' | sort -u); do
	echo "--- $d ---"
	iwinfo "$d" info 2>/dev/null
	echo "  TxPower(real): $(iwinfo "$d" info 2>/dev/null | grep -i 'tx-power')"
	echo "  Clients:"
	iwinfo "$d" assoclist 2>/dev/null | grep -c 'dBm' 2>/dev/null
done
echo "===== WIRELESS CONFIG ====="; cat /etc/config/wireless 2>/dev/null
echo
echo "Tip: scan ->  iwinfo <dev> scan   (run manually; scanning briefly drops AP)"
