#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
JS="$ROOT/files/www/dashboard.js"
HTML="$ROOT/files/www/index.html"
LUCI="$ROOT/files/etc/config/luci"
RESOURCES="$ROOT/files/www/luci-static/resources"

grep -Fq 'cr6608-smartap-v29-mobile-r1-25.12.5' "$JS"
grep -Fq 'insightCategory:' "$JS"
grep -Fq 'data-insight-category' "$JS"
grep -Fq 'cats[selected].forEach(function (f)' "$JS"
grep -Fq 'else if (id === "insights"' "$JS"
grep -Fq '!data.lite || !$("insights").innerHTML' "$JS"
! grep -Fq 'smartap.cardOrder' "$JS"
! grep -Fq 'draggable="true"' "$JS"

grep -Fq '/dashboard.js?v=20260716-v29-mobile-r1' "$HTML"
grep -Fq '.insight-summary' "$HTML"
grep -Fq '.insight-tabs' "$HTML"
grep -Fq '@media(max-width:820px)' "$HTML"
grep -Fq 'top:auto; inset-inline:6px' "$HTML"
grep -Fq 'height:68px; min-height:0' "$HTML"
grep -Fq 'env(safe-area-inset-bottom)' "$HTML"
grep -Fq -- '-webkit-line-clamp:2' "$HTML"
grep -Fq "option rollback '90'" "$LUCI"

# Only the Argon menu adapter and the CR6608 view may override LuCI resources.
resource_count="$(find "$RESOURCES" -type f | wc -l | tr -d ' ')"
[ "$resource_count" = 2 ]
[ -f "$RESOURCES/menu-argon.js" ]
[ -f "$RESOURCES/view/cr6608/quicksettings.js" ]
[ ! -e "$RESOURCES/luci.js" ]
[ ! -e "$ROOT/files/sbin/sysupgrade" ]
[ ! -e "$ROOT/files/lib/netifd/wireless/mac80211.sh" ]
[ ! -e "$ROOT/files/usr/lib/lua/luci/version.lua" ]

printf 'dashboard_ui_contracts=pass\n'
