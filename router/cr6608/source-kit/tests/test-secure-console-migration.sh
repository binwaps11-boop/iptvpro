#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
MIGRATION="${ROOT}/files/etc/uci-defaults/99-cr6608-secure-console"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() {
	printf 'secure console migration test failed: %s\n' "$*" >&2
	exit 1
}

[ -s "$MIGRATION" ] || fail 'migration is missing'
sh -n "$MIGRATION" || fail 'migration syntax is invalid'

mkdir -p "$TMP/bin"
cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$TEST_LOG"
case "$1" in
	-q) shift ;;
esac
case "${1:-}" in
	get)
		[ "${FAIL_GET:-0}" = 0 ] || exit 1
		[ -f "$TEST_STATE" ] && cat "$TEST_STATE"
		;;
	set)
		[ "${FAIL_SET:-0}" = 0 ] || exit 1
		printf '%s\n' "${2##*=}" > "$TEST_PENDING"
		;;
	delete)
		: > "$TEST_PENDING"
		;;
	commit)
		[ "${FAIL_COMMIT:-0}" = 0 ] || exit 1
		if [ -f "$TEST_PENDING" ]; then
			if [ -s "$TEST_PENDING" ]; then cp "$TEST_PENDING" "$TEST_STATE"; else rm -f "$TEST_STATE"; fi
		fi
		;;
	*) exit 1 ;;
esac
EOF
cat > "$TMP/bin/logger" <<'EOF'
#!/bin/sh
printf 'logger %s\n' "$*" >> "$TEST_LOG"
EOF
chmod +x "$TMP/bin/uci" "$TMP/bin/logger"

run_case() {
	case_name="$1"
	root_hash="$2"
	board_name="$3"
	initial_value="$4"
	expected_rc="$5"
	expected_value="$6"
	shift 6
	case_dir="$TMP/$case_name"
	mkdir -p "$case_dir"
	printf '%s\n' "$board_name" > "$case_dir/board_name"
	printf 'root:%s:20647:0:99999:7:::\n' "$root_hash" > "$case_dir/shadow"
	: > "$case_dir/log"
	[ -z "$initial_value" ] || printf '%s\n' "$initial_value" > "$case_dir/state"
	if env \
		UCI_BIN="$TMP/bin/uci" \
		LOGGER_BIN="$TMP/bin/logger" \
		BOARD_NAME_FILE="$case_dir/board_name" \
		SHADOW_FILE="$case_dir/shadow" \
		TEST_LOG="$case_dir/log" \
		TEST_STATE="$case_dir/state" \
		TEST_PENDING="$case_dir/pending" \
		"$@" sh "$MIGRATION"; then
		rc=0
	else
		rc=$?
	fi
	[ "$rc" -eq "$expected_rc" ] || fail "$case_name returned $rc, expected $expected_rc"
	actual=''
	[ ! -f "$case_dir/state" ] || actual="$(cat "$case_dir/state")"
	[ "$actual" = "$expected_value" ] || fail "$case_name left ttylogin=$actual, expected $expected_value"
	CASE_DIR="$case_dir"
}

run_case usable_hash '$6$unit$saltedhash' 'xiaomi,mi-router-cr6608' 0 0 1
grep -Fq 'set system.@system[0].ttylogin=1' "$CASE_DIR/log" || fail 'usable hash did not stage ttylogin=1'
grep -Fq 'commit system' "$CASE_DIR/log" || fail 'usable hash did not commit system'
grep -Fq 'logger -t cr6608-secure-console -- enabled password-gated serial login' "$CASE_DIR/log" || \
	fail 'successful migration was not logged'

run_case already_enabled '$6$unit$saltedhash' 'xiaomi,mi-router-cr6608' 1 0 1
[ "$(grep -c '^commit system$' "$CASE_DIR/log" || :)" -eq 0 ] || fail 'idempotent path committed unexpectedly'

for locked_hash in '' '!' '!!' '!*' '*' '*LOCK*' x; do
	run_case "locked_$(printf '%s' "$locked_hash" | tr -cd '[:alnum:]' | sed 's/^$/empty/')" \
		"$locked_hash" 'xiaomi,mi-router-cr6608' 0 0 0
	[ ! -s "$CASE_DIR/log" ] || fail "locked hash $locked_hash mutated UCI"
done

run_case other_board '$6$unit$saltedhash' 'other,router' 0 0 0
[ ! -s "$CASE_DIR/log" ] || fail 'migration changed another board'

run_case set_failure '$6$unit$saltedhash' 'xiaomi,mi-router-cr6608' 0 1 0 FAIL_SET=1
run_case commit_failure '$6$unit$saltedhash' 'xiaomi,mi-router-cr6608' 0 1 0 FAIL_COMMIT=1

# A failed verification must roll the previous value back.  This mock makes
# every get fail, so the migration cannot falsely report success.
run_case verify_failure '$6$unit$saltedhash' 'xiaomi,mi-router-cr6608' 0 1 0 FAIL_GET=1

bad_dir="$TMP/symlink"
mkdir -p "$bad_dir"
printf '%s\n' 'xiaomi,mi-router-cr6608' > "$bad_dir/board_real"
printf '%s\n' 'root:$6$unit$saltedhash:20647:0:99999:7:::' > "$bad_dir/shadow_real"
ln -s "$bad_dir/board_real" "$bad_dir/board_name"
ln -s "$bad_dir/shadow_real" "$bad_dir/shadow"
if BOARD_NAME_FILE="$bad_dir/board_name" SHADOW_FILE="$bad_dir/shadow" sh "$MIGRATION"; then
	fail 'symlink board file was accepted'
fi
rm -f "$bad_dir/board_name"
cp "$bad_dir/board_real" "$bad_dir/board_name"
if BOARD_NAME_FILE="$bad_dir/board_name" SHADOW_FILE="$bad_dir/shadow" sh "$MIGRATION"; then
	fail 'symlink shadow file was accepted'
fi

printf 'secure_console_migration=pass\n'
