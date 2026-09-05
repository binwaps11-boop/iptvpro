#!/bin/sh
# KT412 UI/backend check (read-only): confirm LuCI + custom dashboard backend live.
OUT=/root/UI_BACKEND_RESULT.txt
{
echo "===================== KT412 UI / BACKEND CHECK ====================="
echo "## services"; for s in uhttpd rpcd; do echo -n "$s: "; pidof "$s" >/dev/null 2>&1 && echo running || echo STOPPED; done
echo "## LuCI present?"; ls /www/cgi-bin/luci 2>/dev/null && echo "LuCI CGI OK" || echo "LuCI CGI MISSING"
echo "## LuCI http"; wget -q -T5 -O- http://127.0.0.1/cgi-bin/luci 2>/dev/null | head -3
echo "## custom dashboard backend"; ls -l /www/cgi-bin/kt412 2>/dev/null
echo "## package manager (apk on snapshot)"; which apk 2>/dev/null && apk --version 2>/dev/null | head -1 || echo "(apk not found)"; which opkg 2>/dev/null || echo "(opkg not present - snapshot uses apk)"
echo "===================== END ====================="
} | tee "$OUT"
