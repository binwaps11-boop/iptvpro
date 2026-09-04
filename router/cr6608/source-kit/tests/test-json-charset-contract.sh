#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CGI_DIR="$ROOT/files/www/cgi-bin"

fail() {
	printf 'JSON charset contract failed: %s\n' "$*" >&2
	exit 1
}

found=0
for file in "$CGI_DIR"/*; do
	[ -f "$file" ] || continue
	grep -q 'Content-Type: application/json' "$file" || continue
	found=1
	bad="$(grep -n 'Content-Type: application/json' "$file" | grep -v 'charset=utf-8' || true)"
	[ -z "$bad" ] || fail "$file has JSON responses without an explicit UTF-8 charset: $bad"
	dash_shell="$(sed -n '1p' "$file")"
	case "$dash_shell" in
		'#!/bin/sh') sh -n "$file" || fail "$file is not valid POSIX shell syntax" ;;
	esac
done

[ "$found" = 1 ] || fail 'no JSON CGI endpoint was discovered'
printf 'json_charset_contract=pass\n'
