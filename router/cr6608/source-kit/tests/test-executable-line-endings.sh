#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cr="$(printf '\r')"
bad="$(
	find "$ROOT" \
		-path "$ROOT/.git" -prune -o \
		-path "$ROOT/release-evidence" -prune -o \
		-type f -exec sh -c '
		cr="$1"
		shift
		for path do
			case "$(dd if="$path" bs=2 count=1 2>/dev/null |
				od -An -tx1 | tr -d " \n")" in
				2321)
					if LC_ALL=C grep -Fq "$cr" "$path"; then
						printf "%s\n" "$path"
					fi
					;;
			esac
		done
	' sh "$cr" {} +
)"

[ -z "$bad" ] || {
	printf 'Executable files contain CRLF and would request /bin/sh\\r:\n%s\n' "$bad" >&2
	exit 1
}

overlay_bad="$(
	find "$ROOT/files" -type f -exec grep -Il "$cr" {} + || true
)"

[ -z "$overlay_bad" ] || {
	printf 'Text files in the runtime overlay contain CRLF:\n%s\n' "$overlay_bad" >&2
	exit 1
}

printf 'executable_line_endings=pass\n'
printf 'overlay_text_line_endings=pass\n'
