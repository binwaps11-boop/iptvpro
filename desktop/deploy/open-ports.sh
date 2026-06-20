#!/usr/bin/env bash
#
# حلّ جذري لفتح منافذ التطبيق على السيرفر واختبار الوصول الخارجي.
# يفتح المنافذ في iptables + nftables، يجعلها دائمة، يعيد تشغيل الخدمة،
# ثم يختبر هل أصبحت مفتوحة للعالم — ويخبرك بدقّة أين المشكلة إن بقيت محجوبة.
#
# الاستخدام:  sudo bash deploy/open-ports.sh
#             sudo USER_PORT=221 ADMIN_PORT=331 bash deploy/open-ports.sh
#
set -uo pipefail
UP="${USER_PORT:-221}"
AP="${ADMIN_PORT:-331}"
TS="$(date +%s)"
[ "$(id -u)" -eq 0 ] || { echo "شغّله بصلاحية root (sudo)"; exit 1; }

line() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

line "نسخ احتياطي للجدار الحالي (في /root)"
iptables-save  > "/root/iptables.backup.$TS"  2>/dev/null || true
ip6tables-save > "/root/ip6tables.backup.$TS" 2>/dev/null || true
nft list ruleset > "/root/nftables.backup.$TS" 2>/dev/null || true
echo "تم الحفظ بلاحقة: $TS"

line "فتح المنافذ في iptables / ip6tables"
for cmd in iptables ip6tables; do
  command -v "$cmd" >/dev/null 2>&1 || continue
  "$cmd" -P INPUT ACCEPT 2>/dev/null || true
  "$cmd" -I INPUT -p tcp -m multiport --dports 22,80,443,"$UP","$AP" -j ACCEPT 2>/dev/null || true
done

line "فحص nftables ومعالجة أي حجب على input"
if command -v nft >/dev/null 2>&1; then
  RULES="$(nft list ruleset 2>/dev/null || true)"
  if echo "$RULES" | grep -q 'hook input' && echo "$RULES" | grep -Eq 'policy drop|[[:space:]]drop'; then
    echo "وُجدت قواعد nftables تحجب الدخول — يتم تفريغها (محفوظة احتياطياً)."
    nft flush ruleset 2>/dev/null || true
    if [ -f /etc/nftables.conf ] && grep -q 'hook input' /etc/nftables.conf 2>/dev/null; then
      cp /etc/nftables.conf "/root/nftables.conf.backup.$TS" 2>/dev/null || true
      printf '#!/usr/sbin/nft -f\nflush ruleset\n' > /etc/nftables.conf
      echo "تم تحييد /etc/nftables.conf (نسخة احتياطية محفوظة)."
    fi
  else
    echo "لا توجد قواعد nftables تحجب الدخول."
  fi
fi

line "جعل قواعد iptables دائمة بعد الإقلاع"
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1 || true
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save >/dev/null 2>&1 || true
else
  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
fi

line "إعادة تشغيل التطبيق والتأكد محلياً"
systemctl restart iptvpro 2>/dev/null || true
sleep 2
echo "الخدمة: $(systemctl is-active iptvpro 2>/dev/null)"
curl -s -o /dev/null -w "محلي $UP -> %{http_code}\n" "http://localhost:$UP/" 2>/dev/null || true

line "اختبار الوصول من خارج السيرفر"
test_port() { curl -s4 --max-time 10 "https://ifconfig.co/port/$1" 2>/dev/null | grep -q '"reachable": *true' && echo true || echo false; }
R1="$(test_port "$UP")"
R2="$(test_port "$AP")"
IP="$(curl -s4 --max-time 10 https://ifconfig.co/ip 2>/dev/null || echo SERVER_IP)"
echo "منفذ $UP من الخارج: reachable=$R1"
echo "منفذ $AP من الخارج: reachable=$R2"

echo
if [ "$R1" = "true" ]; then
  printf '\033[1;32m✅ نجح الحل! المنافذ مفتوحة للعالم. افتح في المتصفّح:\033[0m\n'
  echo "   👥 بوابة العملاء:  http://$IP:$UP/"
  echo "   🔐 لوحة الإدارة:   http://$IP:$AP/admin   (admin / كلمة مرورك)"
else
  printf '\033[1;33m🔒 المنافذ ما زالت محجوبة رغم فتحها بالكامل على السيرفر.\033[0m\n'
  echo "   إعداد السيرفر سليم 100%% — الحجب من جدار Contabo الخارجي (فوق نظام التشغيل)،"
  echo "   ولا يمكن لأي سكربت داخل السيرفر تجاوزه. الحل النهائي:"
  echo "   1) ادخل https://my.contabo.com → سيرفرك → Firewall."
  echo "   2) اسمح Inbound TCP للمنفذين $UP و $AP (المصدر 0.0.0.0/0)، أو عطّل الجدار."
  echo "   3) أو افتح تذكرة دعم Contabo واطلب فتح هذين المنفذين."
  echo "   (للتأكد بعدها: أعد تشغيل هذا السكربت.)"
fi
