#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KIT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
RPCD="${KIT_DIR}/files/etc/config/rpcd"
SHADOW="${KIT_DIR}/files/etc/shadow"
DASHBOARD="${KIT_DIR}/files/www/dashboard.js"
DASHCTL="${KIT_DIR}/files/www/cgi-bin/dashctl"

[ -s "${RPCD}" ]
[ -s "${SHADOW}" ]
grep -Fq "option username 'root'" "${RPCD}"

rpcd_hash="$(sed -n "s/^[[:space:]]*option password '\([^']*\)'/\1/p" "${RPCD}" | head -n 1)"
shadow_hash="$(awk -F: '$1 == "root" { print $2; exit }' "${SHADOW}")"
case "${rpcd_hash}" in \$6\$*\$*) ;; *) exit 1 ;; esac
rpcd_salt="$(printf '%s' "${rpcd_hash}" | cut -d'$' -f3)"
[ "$(printf 'admin\n' | openssl passwd -6 -salt "${rpcd_salt}" -stdin)" = "${rpcd_hash}" ]
[ -n "${shadow_hash}" ]
[ "${rpcd_hash}" != "${shadow_hash}" ]

grep -Fq "This device's Smart AP dashboard password" "${DASHBOARD}"
! grep -Fq 'default: admin' "${DASHBOARD}"
! grep -Fq 'الافتراضية admin' "${DASHBOARD}"
grep -Fq 'per-device' "${RPCD}"
grep -Fq 'The SSH/console root password cannot be changed from Smart AP.' "${DASHCTL}"
! grep -Fq 'passwd root' "${DASHCTL}"

printf 'ui_password_separation=pass\n'
