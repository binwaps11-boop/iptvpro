#!/bin/sh
# repack.sh — إعادة تغليف صورة sysupgrade لراوتر Xiaomi Mi Router CR6608 (OpenWrt NAND tar)
#
# يأخذ صورة sysupgrade أصلية (.bin) ويستبدل ملفات داخل rootfs (مثل لوحة Smart AP في /www)
# ثم يعيد بناء squashfs والـ tar ويلحق fwtool metadata حتى يقبلها sysupgrade على الجهاز.
#
# المتطلبات (على لينكس):
#   - squashfs-tools (unsquashfs / mksquashfs مع دعم xz)
#   - gcc  (لتجميع fwtool من https://github.com/openwrt/fwtool)
#   - python3, tar
#
# الاستخدام:
#   ./repack.sh <original-sysupgrade.bin> <overlay-dir> <output.bin>
#   overlay-dir: مجلد بنفس بنية الجذر (مثلاً overlay/www/cgi-bin/dashapi) تُنسخ ملفاته فوق rootfs
set -eu

ORIG="$1"
OVERLAY="$2"
OUT="$3"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1) تجميع fwtool (أداة OpenWrt الرسمية للتعامل مع metadata/التوقيع في نهاية الصورة)
if ! command -v fwtool >/dev/null 2>&1; then
	if [ ! -x "$WORK/fwtool" ]; then
		git clone --depth 1 https://github.com/openwrt/fwtool.git "$WORK/fwtool-src"
		gcc -O2 -o "$WORK/fwtool" "$WORK/fwtool-src/fwtool.c"
	fi
	FWTOOL="$WORK/fwtool"
else
	FWTOOL="$(command -v fwtool)"
fi

# 2) فصل metadata والتوقيع عن الـ tar
cp "$ORIG" "$WORK/image.bin"
"$FWTOOL" -q -t -s "$WORK/sig.ucert" "$WORK/image.bin" || true   # التوقيع (إن وجد) يُزال — لا نملك مفتاح التوقيع الأصلي
"$FWTOOL" -t -i "$WORK/meta.json" "$WORK/image.bin"              # metadata تُحفظ ويعاد إلحاقها لاحقاً

# 3) فك الـ tar و rootfs
tar -C "$WORK" -xf "$WORK/image.bin"
BOARD_DIR="$(find "$WORK" -maxdepth 1 -type d -name 'sysupgrade-*')"
unsquashfs -q -d "$WORK/rootfs" "$BOARD_DIR/root"

# 4) تطبيق التعديلات (نسخ ملفات الـ overlay فوق rootfs مع الحفاظ على الصلاحيات)
cp -a "$OVERLAY"/. "$WORK/rootfs"/

# 5) إعادة بناء squashfs بنفس خيارات OpenWrt (xz، بلوك 256KiB، ملكية root)
MKFS_TIME="$(python3 -c "import struct;print(struct.unpack_from('<I',open('$BOARD_DIR/root','rb').read(12),8)[0])")"
mksquashfs "$WORK/rootfs" "$WORK/root.new" -nopad -noappend -root-owned \
	-comp xz -b 262144 -mkfs-time "$MKFS_TIME" -all-time "$MKFS_TIME" -quiet

# 6) حشو بالأصفار إلى مضاعف 1024 (مثل الأصل) واستبدال العضو داخل tar
python3 - "$BOARD_DIR" "$WORK" <<'PYEOF'
import io, os, sys, tarfile
board_dir, work = sys.argv[1], sys.argv[2]
data = open(os.path.join(work, 'root.new'), 'rb').read()
data += b'\x00' * ((-len(data)) % 1024)
src = tarfile.open(os.path.join(work, 'image.bin'), 'r:')
dst = tarfile.open(os.path.join(work, 'new.tar'), 'w:', format=tarfile.GNU_FORMAT)
for m in src.getmembers():
    if m.name.endswith('/root'):
        m.size = len(data)
        dst.addfile(m, io.BytesIO(data))
    else:
        dst.addfile(m, src.extractfile(m) if m.isfile() else None)
src.close(); dst.close()
PYEOF

# 7) إلحاق metadata — إلزامي حتى يقبلها sysupgrade (بدون هذه الخطوة يظهر خطأ
#    "Image metadata not present"). نفضّل ملف fwtool-metadata.json المرفق بالمستودع
#    (compat_version 1.0 + supported_devices الصحيح) لأن الصورة الأصلية قد تكون بلا metadata.
cp "$WORK/new.tar" "$OUT"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -s "$SCRIPT_DIR/fwtool-metadata.json" ]; then
	META="$SCRIPT_DIR/fwtool-metadata.json"
elif [ -s "$WORK/meta.json" ]; then
	META="$WORK/meta.json"
else
	echo "خطأ: لا يوجد ملف metadata — الصورة لن تُقبل بدون -F" >&2; exit 1
fi
"$FWTOOL" -I "$META" "$OUT"
# تحقّق أن metadata أصبحت موجودة وتطابق اللوحة
"$FWTOOL" -q -i "$WORK/verify-meta.json" "$OUT" && grep -q 'xiaomi,mi-router-cr6608' "$WORK/verify-meta.json" \
	&& echo "✓ metadata مضافة واللوحة مطابقة" || { echo "خطأ: فشل التحقق من metadata" >&2; exit 1; }

echo "تم: $OUT"
echo "الفلاش: LuCI → System → Backup/Flash Firmware، أو: sysupgrade -v $OUT"
