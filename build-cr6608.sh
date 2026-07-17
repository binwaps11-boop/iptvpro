#!/usr/bin/env bash
# ============================================================================
#  CR6608 v29 — bootstrap جذري (يأتي طازجاً مع كل git clone من الفرع).
#
#  المشكلة التي يحلّها: البوتستراب القديم على السيرفر كان يعيد استخدام نسخة
#  مصدر قديمة مخبّأة في /home/builder/CR6608-FINAL/kit، فيشغّل build.sh قديماً
#  بلا إصلاح التوقيع ⇒ يفشل عند "Required signing input missing".
#
#  هذا السكربت يعتمد حصراً على المصدر الطازج المجاور له (نسخة git clone)،
#  يحذف الـkit القديم المخبّأ، ينسخ الطازج فوقه، ويتحقق أن إصلاح التوقيع موجود
#  قبل البناء. يُبنى تحت مستخدم غير جذري لأن OpenWrt يرفض البناء كـroot.
#
#  التشغيل (كـroot):
#    cd /root && rm -rf kit-v29 && \
#      git clone -b cr6608-v29-src https://github.com/binwaps11-boop/iptvpro kit-v29 && \
#      bash kit-v29/build-cr6608.sh
# ============================================================================
set -euo pipefail

BUILDER="builder"
BROOT="/home/${BUILDER}/CR6608-FINAL"
KIT="${BROOT}/kit"
# مجلد هذا السكربت = نسخة git الطازجة (المصدر الحقيقي المحدَّث).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok(){  printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "شغّله كـroot (ينشئ مستخدم البناء وينظّف الحالة القديمة)."
[ -x "${SELF_DIR}/build.sh" ] || die "لم أجد build.sh بجانب هذا السكربت في ${SELF_DIR} — استنسخ الفرع كاملاً."

# تحقّق مبكّر: أن المصدر الطازج فعلاً يحوي إصلاح التوقيع (لا نبني نسخة قديمة أبداً).
grep -q 'CR6608_PIN_SIGNING' "${SELF_DIR}/build.sh" \
  || die "build.sh في هذا الاستنساخ قديم بلا إصلاح التوقيع — تأكّد أن git clone سحب أحدث cr6608-v29-src."

say "[1/6] تنظيف جذري لأي مصدر/بناء قديم مخبّأ"
# جذر المشكلة: kit قديم مخبّأ. نحذفه دائماً ونعيد بناءه من الطازج.
rm -rf "${KIT}"
rm -rf "${BROOT}/logs" "${BROOT}/output" "${BROOT}/.cr6608-build.lock" 2>/dev/null || true
# مفاتيح توقيع قديمة قد تُفعّل مساراً غير متطابق — احذفها (build.sh الآن يوقّع ذاتياً).
rm -rf "${BROOT}/secrets" 2>/dev/null || true
ok "الحالة القديمة نُظّفت (kit + secrets القديمة حُذفت؛ ذاكرة تنزيل openwrt/dl إن وُجدت تبقى)"

say "[2/6] تثبيت أدوات البناء"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev python3 python3-setuptools rsync unzip zlib1g-dev \
  file wget aria2 subversion swig time libelf-dev signify-openbsd tar xz-utils perl which sudo
ok "الأدوات جاهزة"

say "[3/6] مستخدم البناء + نسخ المصدر الطازج فوق أي قديم"
id "${BUILDER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${BUILDER}"
mkdir -p "${KIT}"
# انسخ نسخة git الطازجة (بدون .git وبدون حالة بناء) إلى KIT.
rsync -a --delete --exclude='.git' --exclude='openwrt' --exclude='logs' \
      --exclude='output' "${SELF_DIR}/" "${KIT}/"
[ -x "${KIT}/build.sh" ] || die "فشل نسخ build.sh إلى ${KIT}"
# تأكيد نهائي أن النسخة المبنيّة تحوي الإصلاح.
grep -q 'CR6608_PIN_SIGNING' "${KIT}/build.sh" \
  || die "build.sh المنسوخ في ${KIT} قديم بلا إصلاح — توقّف قبل بناء نسخة خاطئة."
chown -R "${BUILDER}:${BUILDER}" "${BROOT}"
ok "المصدر الطازج في ${KIT} (build.sh محدَّث بإصلاح التوقيع الذاتي)"

say "[4/6] وضع التوقيع الذاتي (بلا مفاتيح سرية مطلوبة)"
# لا نولّد أي مفاتيح: build.sh سيجعل OpenWrt يولّد مفتاح البناء الخاص به تلقائياً.
ok "OpenWrt سيولّد مفتاح توقيع محلياً أثناء make"

say "[5/6] البناء من الصفر تحت '${BUILDER}' (30-90 دقيقة، لا تقطعه)"
su - "${BUILDER}" -c "cd '${KIT}' && ./build.sh"

say "[6/6] الناتج"
BIN="$(find "${BROOT}" \( -name '*mi-router-cr6608*squashfs-sysupgrade.bin' \
        -o -name 'cr6608-SMARTAP-v29-*sysupgrade.bin' \) 2>/dev/null | head -1)"
if [ -n "${BIN}" ]; then
  ok "تمّ البناء: ${BIN}"
  sha256sum "${BIN}"
  echo
  echo "انسخ الملف إلى الراوتر ثم:  sysupgrade -n \"$(basename "${BIN}")\""
else
  die "لم أجد صورة الناتج — راجع ${BROOT}/logs/"
fi
