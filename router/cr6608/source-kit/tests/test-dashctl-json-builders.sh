#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASHCTL="$ROOT/files/www/cgi-bin/dashctl"

fail() {
	printf 'dashctl_json_builders=fail: %s\n' "$*" >&2
	exit 1
}

[ -s "$DASHCTL" ] || fail 'dashctl source is missing'
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-json-builders.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

sed -n '/^cards_json() {/,/^emit() {/p' "$DASHCTL" | sed '$d' >"$TMP/builders.sh"
sh -n "$TMP/builders.sh" || fail 'extracted builder syntax failed'
. "$TMP/builders.sh"

sed -n '/^jnum() {$/,/^}$/p' "$DASHCTL" > "$TMP/jnum.sh"
sh -n "$TMP/jnum.sh" || fail 'numeric JSON builder syntax failed'
# shellcheck disable=SC1090
. "$TMP/jnum.sh"
[ "$(jnum 0)" = 0 ]
[ "$(jnum 42)" = 42 ]
[ "$(jnum -73)" = -73 ]
[ "$(jnum 1.25)" = 1.25 ]
[ "$(jnum 038)" = null ]
[ "$(jnum -01)" = null ]
[ "$(jnum --1)" = null ]
[ "$(jnum 1-2)" = null ]
[ "$(jnum .)" = null ]

[ "$(grep -c "awk -F '|'" "$TMP/builders.sh")" = 2 ] ||
	fail 'builders no longer use one bulk awk serializer each'
! grep -Fq 'jstr ' "$TMP/builders.sh" ||
	fail 'builders returned to per-field jstr process spawning'

legacy_json_escape() {
	tr '\011' ' ' | tr -d '\000-\010\013\014\016-\037\177' |
		awk 'BEGIN{ORS=""}{gsub(/\\/,"\\\\");gsub(/"/,"\\\"");if(NR>1)printf "\\n";printf "%s",$0}'
}
legacy_jstr() { printf '"'; printf '%s' "$1" | legacy_json_escape; printf '"'; }
legacy_cards_json() {
	printf '['; first=1
	while IFS='|' read -r label value hint level; do
		[ -n "$label$value$hint$level" ] || continue
		[ "$first" = 1 ] || printf ','
		printf '{"label":%s,"value":%s,"hint":%s,"level":%s}' \
			"$(legacy_jstr "$label")" "$(legacy_jstr "$value")" \
			"$(legacy_jstr "$hint")" "$(legacy_jstr "${level:-neutral}")"
		first=0
	done
	printf ']'
}
legacy_form_json() {
	printf '['; first=1
	while IFS='|' read -r name label value hint type readonly group modes options; do
		[ -n "$name$label$value$hint" ] || continue
		[ "$first" = 1 ] || printf ','
		printf '{"name":%s,"label":%s,"value":%s,"hint":%s,"type":%s,"readonly":%s,"group":%s,"modes":%s,"options":%s}' \
			"$(legacy_jstr "$name")" "$(legacy_jstr "$label")" \
			"$(legacy_jstr "$value")" "$(legacy_jstr "$hint")" \
			"$(legacy_jstr "${type:-text}")" \
			"$([ "$readonly" = 1 ] && printf true || printf false)" \
			"$(legacy_jstr "$group")" "$(legacy_jstr "$modes")" \
			"$(legacy_jstr "$options")"
		first=0
	done
	printf ']'
}

cat >"$TMP/safe.cards" <<'EOF'
Radio 0|Enabled|Live driver state|ok
Country|US|Regulatory domain|
||||
Tail|Value|Hint|warn|detail
EOF
cat >"$TMP/safe.form" <<'EOF'
country|Country|US|Live domain|select|1|device|all|US:US,DE:DE
ssid|SSID|Smart AP|Network name||0|device|all|
||||select|1|ignored|all|ignored
tail|Tail|value|hint|text|0|advanced|all|one:One|two:Two
EOF

[ "$(cards_json <"$TMP/safe.cards")" = "$(legacy_cards_json <"$TMP/safe.cards")" ] ||
	fail 'cards builder changed safe legacy semantics'
[ "$(form_json <"$TMP/safe.form")" = "$(legacy_form_json <"$TMP/safe.form")" ] ||
	fail 'form builder changed safe legacy semantics'

{
	printf 'quoted|اسم "ذكي"|C:\\WiFi|tab\tand\001control||1|device|all|one:واحد,two:Two|Pipe\n'
	printf 'default|Default value||Uses defaults|||||\n'
	printf '||||select|1|ignored|all|ignored\n'
} >"$TMP/special.form"
{
	printf 'quoted "card"|C:\\WiFi|tab\tand\001control|\n'
	printf '||||\n'
} >"$TMP/special.cards"

form_json <"$TMP/special.form" >"$TMP/form.json"
cards_json <"$TMP/special.cards" >"$TMP/cards.json"

python3 - "$TMP/form.json" "$TMP/cards.json" <<'PY' || exit 1
import json
import sys

form = json.load(open(sys.argv[1], encoding="utf-8"))
cards = json.load(open(sys.argv[2], encoding="utf-8"))

assert len(form) == 2, form
assert form[0]["label"] == 'اسم "ذكي"', form[0]
assert form[0]["value"] == r"C:\WiFi", form[0]
assert form[0]["hint"] == "tab andcontrol", form[0]
assert form[0]["type"] == "text", form[0]
assert form[0]["readonly"] is True, form[0]
assert form[0]["options"] == "one:واحد,two:Two|Pipe", form[0]
assert form[1]["type"] == "text", form[1]
assert form[1]["readonly"] is False, form[1]
assert len(cards) == 1, cards
assert cards[0]["label"] == 'quoted "card"', cards[0]
assert cards[0]["value"] == r"C:\WiFi", cards[0]
assert cards[0]["hint"] == "tab andcontrol", cards[0]
assert cards[0]["level"] == "neutral", cards[0]
PY

printf 'dashctl_json_builders=pass\n'
