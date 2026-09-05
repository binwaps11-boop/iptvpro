#!/usr/bin/env bash
# مُثبّت ذاتي بأمر واحد لخادم تراخيص «مدير الكروت».
#
# الاستخدام على الـVPS (أوبونتو/دبيان):
#   curl -fsSL <رابط هذا الملف> | sudo bash
#
# ينزّل بقية الملفات من نفس المستودع ثم يشغّل install.sh الذي يثبّت كل شيء.
set -euo pipefail

OWNER=binwaps11-boop
REPO=iptvpro
# يمكن تجاوز الفرع/الوسم بمتغيّر بيئة عند الحاجة
REF="${LICENSE_SERVER_REF:-claude/user-card-management-app-6nhwlj}"
RAW="https://raw.githubusercontent.com/$OWNER/$REPO/$REF/license-server"

if [ "$(id -u)" -ne 0 ]; then
  echo "✗ شغّله بصلاحية الجذر:  curl -fsSL <الرابط> | sudo bash" >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq curl; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "▸ تنزيل ملفات الخادم من المستودع…"
for f in server.js admin.html package.json install.sh; do
  curl -fsSL "$RAW/$f" -o "$TMP/$f" || { echo "✗ تعذّر تنزيل $f" >&2; exit 1; }
done

bash "$TMP/install.sh"
