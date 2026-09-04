#!/usr/bin/env python3
"""Fault-injection tests for bounded Smart AP authentication requests.

The production CGI files are copied to a private temporary directory.  Only
absolute OpenWrt runtime paths are relocated in those copies so the tests can
run on a development host.  Stub ``ubus`` and ``flock`` commands then model a
service that never replies and a lock held by another request.

No router, network, RF setting, or production file is touched.
"""

from __future__ import annotations

import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOGIN_SOURCE = ROOT / "files/www/cgi-bin/dashlogin"
LUCI_SOURCE = ROOT / "files/www/cgi-bin/dashluci"
LOGOUT_SOURCE = ROOT / "files/www/cgi-bin/dashlogout"
AUTH_SOURCE = ROOT / "files/usr/libexec/cr6608-session-auth"
REAPER_SOURCE = ROOT / "files/usr/sbin/cr6608-session-reaper"

# This remains below dashboard.js' 12-second authentication deadline while
# leaving enough room for a short server-side ubus/flock timeout and response.
CASE_DEADLINE_SECONDS = 6.0
SID = "0123456789abcdef0123456789abcdef"


class HarnessError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise HarnessError(message)


def write_executable(path: pathlib.Path, source: str) -> None:
    path.write_text(source, encoding="utf-8", newline="\n")
    path.chmod(0o755)


def find_bash() -> str:
    candidates = [
        os.environ.get("CR6608_TEST_BASH"),
        shutil.which("bash"),
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).is_file():
            return str(pathlib.Path(candidate))
    raise HarnessError(
        "bash is required (set CR6608_TEST_BASH, or install Git Bash on Windows)"
    )


def relocated_copy(source: pathlib.Path, destination: pathlib.Path) -> None:
    data = source.read_text(encoding="utf-8")
    require("/usr/share/libubox/jshn.sh" in data or source in (AUTH_SOURCE, LUCI_SOURCE, REAPER_SOURCE),
            f"unexpected source layout: {source}")
    data = data.replace(
        "/usr/share/libubox/jshn.sh", '"${CR6608_TEST_JSHN}"'
    )
    data = data.replace(
        "RATE_DIR=/tmp/dashlogin-rate",
        'RATE_DIR="${CR6608_TEST_RUNTIME}/dashlogin-rate"',
    )
    data = data.replace("/tmp/dashsess", "${CR6608_TEST_RUNTIME}/dashsess")
    data = data.replace("/tmp/dashluci", "${CR6608_TEST_RUNTIME}/dashluci")
    data = data.replace("/tmp/dashrevoke", "${CR6608_TEST_RUNTIME}/dashrevoke")
    data = data.replace(
        ". /usr/libexec/cr6608-session-auth",
        '. "${CR6608_SESSION_AUTH_LIB}"',
    )
    destination.write_text(data, encoding="utf-8", newline="\n")
    destination.chmod(0o755)


def prepare_harness(base: pathlib.Path) -> dict[str, pathlib.Path]:
    bin_dir = base / "bin"
    bin_dir.mkdir()

    login = base / "dashlogin"
    luci = base / "dashluci"
    logout = base / "dashlogout"
    auth = base / "cr6608-session-auth"
    reaper = base / "cr6608-session-reaper"
    relocated_copy(LOGIN_SOURCE, login)
    relocated_copy(LUCI_SOURCE, luci)
    relocated_copy(LOGOUT_SOURCE, logout)
    relocated_copy(AUTH_SOURCE, auth)
    relocated_copy(REAPER_SOURCE, reaper)

    # Source the real helper, then replace only host-specific ownership,
    # entropy, time, and session-file checks.  cr6608_luci_session_lock()
    # remains the production implementation under test.
    auth_stub = base / "auth-stub"
    write_executable(
        auth_stub,
        """#!/bin/sh
. "${CR6608_TEST_AUTH_COPY}" || return 1
cr6608_path_owned_by_root() { return 0; }
cr6608_prepare_root_dir() {
    printf 'prepare dir=%s mode=%s\\n' "$1" "$2" >>"${CR6608_STUB_LOG}"
    mkdir -p "$1" 2>/dev/null || return 1
    chmod "$2" "$1" 2>/dev/null || return 1
}
cr6608_uptime_seconds() { printf '100'; }
cr6608_random_hex32() { printf 'fedcba9876543210fedcba9876543210'; }
cr6608_session_valid() { cr6608_valid_hex32 "$1"; }
""",
    )

    jshn = base / "jshn.sh"
    write_executable(
        jshn,
        """#!/bin/sh
json_init() { :; }
json_add_string() { :; }
json_add_int() { :; }
json_add_array() { :; }
json_close_array() { :; }
json_add_object() { :; }
json_close_object() { :; }
json_dump() { printf '{}'; }
""",
    )

    acl = base / "acl-names"
    write_executable(acl, "#!/bin/sh\nprintf 'luci-base\\n'\n")

    write_executable(
        bin_dir / "jsonfilter",
        f"""#!/bin/sh
case "$*" in
    *'@.access'*)
        [ "${{CR6608_STUB_UBUS:-pass}}" = denied ] && printf 'false\\n' || printf 'true\\n'
        ;;
    *) printf '{SID}\\n' ;;
esac
""",
    )
    write_executable(
        bin_dir / "uci",
        "#!/bin/sh\nprintf '3600\\n'\n",
    )
    write_executable(
        bin_dir / "logger",
        '#!/bin/sh\nprintf \'logger args=%s\\n\' "$*" >>"${CR6608_STUB_LOG}"\n',
    )
    write_executable(
        bin_dir / "ubus",
        f"""#!/bin/sh
printf 'ubus mode=%s args=%s\\n' "${{CR6608_STUB_UBUS:-pass}}" "$*" >>"${{CR6608_STUB_LOG}}"
if [ "${{CR6608_STUB_UBUS:-pass}}" = pass ]; then
    case "$*" in
        *'session access'*) printf '{{"access":true}}\\n' ;;
        *'session login'*|*'session create'*) printf '{{"ubus_rpc_session":"{SID}"}}\\n' ;;
        *) printf '{{}}\\n' ;;
    esac
    exit 0
fi
if [ "${{CR6608_STUB_UBUS:-pass}}" = missing ]; then
    case "$*" in *'session get'*|*'session access'*) exit 4 ;; esac
    exit 0
fi
if [ "${{CR6608_STUB_UBUS:-pass}}" = denied ]; then
    case "$*" in *'session access'*) printf '{{"access":false}}\n'; exit 0 ;; esac
    exit 0
fi

# Model ubus' own -t/--timeout contract.  A corrected caller using it returns
# promptly; an unbounded caller remains blocked until the outer test deadline.
bounded=0
for argument in "$@"; do
    case "$argument" in
        -t|--timeout|-t[0-9]*|--timeout=*) bounded=1 ;;
    esac
done
[ "$bounded" -eq 0 ] || exit 7
remaining=8
while [ "$remaining" -gt 0 ] && kill -0 "$PPID" 2>/dev/null; do
    sleep 1
    remaining=$((remaining - 1))
done
exit 7
""",
    )
    write_executable(
        bin_dir / "flock",
        f"""#!/bin/sh
printf 'flock mode=%s args=%s\\n' "${{CR6608_STUB_FLOCK:-pass}}" "$*" >>"${{CR6608_STUB_LOG}}"
[ "${{CR6608_STUB_FLOCK:-pass}}" = pass ] && exit 0
if [ "${{CR6608_STUB_FLOCK:-pass}}" = transient ]; then
    count_file="${{CR6608_STUB_LOG}}.flock-attempts"
    count=0
    [ ! -r "$count_file" ] || read -r count <"$count_file"
    count=$((count + 1))
    printf '%s\\n' "$count" >"$count_file"
    [ "$count" -ge 2 ] && exit 0
    exit 1
fi

# Model flock -w/--timeout and -n.  External `timeout flock ...` wrappers are
# handled by the real host timeout command found later in PATH.
bounded=0
for argument in "$@"; do
    case "$argument" in
        -n|--nonblock|-*n*|-w|--timeout|-w[0-9]*|--timeout=*) bounded=1 ;;
    esac
done
[ "$bounded" -eq 0 ] || exit 1
remaining=8
while [ "$remaining" -gt 0 ] && kill -0 "$PPID" 2>/dev/null; do
    sleep 1
    remaining=$((remaining - 1))
done
exit 1
""",
    )

    runner = base / "run-case.sh"
    write_executable(
        runner,
        """#!/bin/bash
set -u
HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)" || exit 90
chmod 0755 "$HARNESS_DIR"/bin/* "$HARNESS_DIR/acl-names" 2>/dev/null || exit 91
export PATH="$HARNESS_DIR/bin:/usr/bin:/bin"
export CR6608_TEST_RUNTIME="$HARNESS_DIR/runtime"
export CR6608_STUB_LOG="$HARNESS_DIR/stub.log"
printf 'runner dir=%s flock=%s ubus=%s\\n' "$HARNESS_DIR" \
    "$(command -v flock 2>/dev/null || printf missing)" \
    "$(command -v ubus 2>/dev/null || printf missing)" >>"${CR6608_STUB_LOG}"
export CR6608_SESSION_AUTH_LIB="$HARNESS_DIR/auth-stub"
export CR6608_LUCI_ACL_HELPER="$HARNESS_DIR/acl-names"
export CR6608_TEST_AUTH_COPY="$HARNESS_DIR/cr6608-session-auth"
export CR6608_TEST_JSHN="$HARNESS_DIR/jshn.sh"
export CR6608_UBUS_BIN="$HARNESS_DIR/bin/ubus"
export CR6608_JSONFILTER_BIN="$HARNESS_DIR/bin/jsonfilter"
export REQUEST_METHOD=POST
export REMOTE_ADDR="198.51.100.${CR6608_CASE_OCTET:-10}"
export HTTPS=off

if [ "${CR6608_ENDPOINT}" = login ]; then
    body="${CR6608_TEST_LOGIN_BODY:-username=root&password=admin}"
    export CONTENT_TYPE='application/x-www-form-urlencoded'
    export CONTENT_LENGTH="${#body}"
    printf '%s' "$body" | /bin/sh "$HARNESS_DIR/dashlogin"
    exit $?
fi

if [ "${CR6608_ENDPOINT}" = reaper ]; then
    exec /bin/sh "$HARNESS_DIR/cr6608-session-reaper"
fi

if [ "${CR6608_ENDPOINT}" = logout ]; then
    export CONTENT_TYPE='application/x-www-form-urlencoded'
    export CONTENT_LENGTH=0
    export HTTP_COOKIE='cr6608_sid_http=0123456789abcdef0123456789abcdef'
    exec /bin/sh "$HARNESS_DIR/dashlogout"
fi

export CONTENT_TYPE='application/x-www-form-urlencoded'
export CONTENT_LENGTH=0
export HTTP_COOKIE='cr6608_sid_http=0123456789abcdef0123456789abcdef'
exec /bin/sh "$HARNESS_DIR/dashluci"
""",
    )

    return {
        "runner": runner,
        "runtime": base / "runtime",
    }


def terminate_tree(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=2,
            )
        except (OSError, subprocess.TimeoutExpired):
            # Git-for-Windows process trees can outlive taskkill's own short
            # diagnostic deadline.  The direct child kill below remains the
            # final bounded fallback and lets the harness report the real case.
            pass
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if process.poll() is None:
        process.kill()


def parse_status(output: str) -> int:
    match = re.search(r"(?m)^Status: ([0-9]{3}) ", output)
    return int(match.group(1)) if match else 200


def main() -> int:
    bash = find_bash()
    sources = [LOGIN_SOURCE, LUCI_SOURCE, LOGOUT_SOURCE, AUTH_SOURCE, REAPER_SOURCE]
    for source in sources:
        require(source.is_file() and not source.is_symlink(),
                f"missing or symlinked production input: {source}")

    cases = [
        {
            "name": "dashlogin_slow_ubus_is_bounded",
            "endpoint": "login",
            "ubus": "block",
            "flock": "pass",
            "statuses": {503},
            "body": "authentication service timed out",
        },
        {
            "name": "dashluci_missing_map_has_no_ubus_fallback",
            "endpoint": "luci",
            "ubus": "block",
            "flock": "pass",
            "expect_ubus": False,
            "statuses": {409},
            "body": "luci_session_reauthentication_required",
        },
        {
            "name": "dashluci_live_mapped_rpcd_session_is_published",
            "endpoint": "luci",
            "ubus": "pass",
            "flock": "pass",
            "mapped_sid": SID,
            "expect_map": True,
            "statuses": {200},
            "body": '"target":"/cgi-bin/luci/admin/network/wireless"',
        },
        {
            "name": "dashluci_dead_rpcd_session_requires_reauthentication",
            "endpoint": "luci",
            "ubus": "missing",
            "flock": "pass",
            "mapped_sid": SID,
            "expect_map": False,
            "statuses": {409},
            "body": "luci_session_reauthentication_required",
        },
        {
            "name": "dashluci_rpcd_session_without_luci_acl_requires_reauthentication",
            "endpoint": "luci",
            "ubus": "denied",
            "flock": "pass",
            "mapped_sid": SID,
            "expect_map": False,
            "statuses": {409},
            "body": "luci_session_reauthentication_required",
        },
        {
            "name": "dashluci_rpcd_timeout_preserves_private_map",
            "endpoint": "luci",
            "ubus": "block",
            "flock": "pass",
            "mapped_sid": SID,
            "expect_map": True,
            "statuses": {503},
            "body": "luci_session_service_unavailable",
        },
        {
            "name": "session_reaper_preserves_live_authorized_rpcd_map",
            "endpoint": "reaper",
            "ubus": "pass",
            "flock": "pass",
            "mapped_sid": SID,
            "parent_sid": True,
            "expect_map": True,
            "statuses": {200},
            "body": None,
        },
        {
            "name": "session_reaper_removes_dead_rpcd_map",
            "endpoint": "reaper",
            "ubus": "missing",
            "flock": "pass",
            "mapped_sid": SID,
            "parent_sid": True,
            "expect_map": False,
            "statuses": {200},
            "body": None,
        },
        {
            "name": "session_reaper_removes_unauthorized_rpcd_map",
            "endpoint": "reaper",
            "ubus": "denied",
            "flock": "pass",
            "mapped_sid": SID,
            "parent_sid": True,
            "expect_map": False,
            "statuses": {200},
            "body": None,
        },
        {
            "name": "session_reaper_preserves_map_when_rpcd_is_unavailable",
            "endpoint": "reaper",
            "ubus": "block",
            "flock": "pass",
            "mapped_sid": SID,
            "parent_sid": True,
            "expect_map": True,
            "statuses": {200},
            "body": None,
            "exit_codes": {1},
        },
        {
            "name": "dashlogout_held_session_lock_queues_original_sid",
            "endpoint": "logout",
            "ubus": "pass",
            "flock": "block",
            "mapped_sid": SID,
            "parent_sid": True,
            "expect_map": True,
            "expect_parent": True,
            "expect_pending": True,
            "statuses": {503},
            "body": "revocation_failed",
            "headers": ("Retry-After: 1", "Set-Cookie: cr6608_sid_http=;"),
        },
        {
            "name": "dashlogout_transient_session_lock_recovers",
            "endpoint": "logout",
            "ubus": "pass",
            "flock": "transient",
            "mapped_sid": SID,
            "parent_sid": True,
            "expect_map": False,
            "expect_parent": False,
            "expect_pending": False,
            "statuses": {200},
            "body": '"ok":true',
        },
        {
            "name": "dashlogout_destroy_failure_keeps_map_for_reaper",
            "endpoint": "logout",
            "ubus": "block",
            "flock": "pass",
            "mapped_sid": SID,
            "parent_sid": True,
            "expect_map": True,
            "expect_parent": False,
            "expect_pending": True,
            "statuses": {503},
            "body": "revocation_failed",
            "headers": ("Retry-After: 1", "Set-Cookie: cr6608_sid_http=;"),
        },
        {
            "name": "session_reaper_completes_pending_logout",
            "endpoint": "reaper",
            "ubus": "pass",
            "flock": "pass",
            "mapped_sid": SID,
            "parent_sid": True,
            "pending_sid": True,
            "expect_map": False,
            "expect_parent": False,
            "expect_pending": False,
            "expect_acl_validation": False,
            "statuses": {200},
            "body": None,
        },
        {
            "name": "dashlogin_held_rate_lock_is_bounded",
            "endpoint": "login",
            "ubus": "pass",
            "flock": "block",
            "statuses": {503},
            "body": "login limiter busy; retry",
        },
        {
            "name": "dashlogin_root_username_is_accepted",
            "endpoint": "login",
            "ubus": "pass",
            "flock": "pass",
            "request_body": "username=root&password=admin",
            "statuses": {200},
            "body": '{"ok":true}',
        },
        {
            "name": "dashlogin_admin_alias_is_accepted",
            "endpoint": "login",
            "ubus": "pass",
            "flock": "pass",
            "request_body": "username=AdMiN&password=admin",
            "statuses": {200},
            "body": '{"ok":true}',
        },
        {
            "name": "dashlogin_unknown_username_is_rejected",
            "endpoint": "login",
            "ubus": "pass",
            "flock": "pass",
            "request_body": "username=operator&password=admin",
            "statuses": {401},
            "body": "invalid username or password",
        },
    ]

    failures: list[str] = []
    with tempfile.TemporaryDirectory(
        prefix="cr6608-auth-faults-", ignore_cleanup_errors=True
    ) as temp_name:
        temp = pathlib.Path(temp_name)
        running = []
        for index, case in enumerate(cases, start=1):
            case_dir = temp / f"case-{index}"
            case_dir.mkdir()
            harness = prepare_harness(case_dir)
            runtime = harness["runtime"]
            runtime.mkdir()
            if "mapped_sid" in case:
                map_dir = runtime / "dashluci"
                map_dir.mkdir(mode=0o700)
                map_file = map_dir / SID
                map_file.write_text(case["mapped_sid"] + "\n", encoding="ascii", newline="\n")
                map_file.chmod(0o600)
            if case.get("parent_sid"):
                session_dir = runtime / "dashsess"
                session_dir.mkdir(mode=0o700)
                session_file = session_dir / SID
                session_file.write_text("1 1\n", encoding="ascii", newline="\n")
                session_file.chmod(0o600)
            if case.get("pending_sid"):
                pending_dir = runtime / "dashrevoke"
                pending_dir.mkdir(mode=0o700)
                pending_file = pending_dir / SID
                pending_file.write_text(SID + "\n", encoding="ascii", newline="\n")
                pending_file.chmod(0o600)
            environment = os.environ.copy()
            environment.update(
                {
                    "CR6608_ENDPOINT": case["endpoint"],
                    "CR6608_STUB_UBUS": case["ubus"],
                    "CR6608_STUB_FLOCK": case["flock"],
                    "CR6608_CASE_OCTET": str(10 + index),
                }
            )
            if "request_body" in case:
                environment["CR6608_TEST_LOGIN_BODY"] = case["request_body"]
            output_path = case_dir / "cgi-output.log"
            output_handle = output_path.open("w", encoding="utf-8", newline="\n")
            popen_options = {
                "cwd": str(case_dir),
                "env": environment,
                "stdin": subprocess.DEVNULL,
                "stdout": output_handle,
                "stderr": subprocess.STDOUT,
                "text": True,
            }
            if os.name == "nt":
                popen_options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
            else:
                popen_options["start_new_session"] = True
            process = subprocess.Popen(
                [bash, str(harness["runner"])], **popen_options
            )
            running.append(
                (
                    case,
                    process,
                    time.monotonic(),
                    case_dir / "stub.log",
                    output_path,
                    output_handle,
                )
            )

        # All cases start together, so deliberate stalls cost one deadline
        # instead of consecutive deadlines.
        overall_deadline = time.monotonic() + CASE_DEADLINE_SECONDS
        while time.monotonic() < overall_deadline:
            if all(process.poll() is not None for _, process, _, _, _, _ in running):
                break
            time.sleep(0.05)

        timed_out_processes = {
            process.pid
            for _, process, _, _, _, _ in running
            if process.poll() is None
        }
        # Kill every overdue case before collecting any pipe.  This avoids one
        # stuck child delaying cleanup of the other fault-injection children.
        for _, process, _, _, _, _ in running:
            if process.pid in timed_out_processes:
                terminate_tree(process)

        # Even if a Windows process-tree utility is unavailable, the stubs'
        # own eight-second fuse expires shortly after the six-second contract.
        if timed_out_processes:
            time.sleep(2.5)

        for case, process, started, stub_log_path, output_path, output_handle in running:
            timed_out = process.pid in timed_out_processes
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                terminate_tree(process)
            output_handle.close()
            output = (
                output_path.read_text(encoding="utf-8", errors="replace")
                if output_path.exists()
                else ""
            )
            stub_log = (
                stub_log_path.read_text(encoding="utf-8", errors="replace")
                if stub_log_path.exists()
                else ""
            )
            elapsed = time.monotonic() - started
            if timed_out:
                message = (
                    f"hung beyond {CASE_DEADLINE_SECONDS:.1f}s "
                    "(unbounded ubus/flock call)"
                )
                failures.append(f"{case['name']}: {message}")
                print(f"{case['name']}=FAIL elapsed={elapsed:.2f}s reason={message}")
                continue

            status = parse_status(output)
            expected_statuses = case["statuses"]
            expected_body = case["body"]
            reasons = []
            expected_exit_codes = case.get("exit_codes", {0})
            if process.returncode not in expected_exit_codes:
                reasons.append(
                    f"process exit={process.returncode}, expected={sorted(expected_exit_codes)}"
                )
            if status not in expected_statuses:
                reasons.append(
                    f"HTTP status={status}, expected={sorted(expected_statuses)}"
                )
            if expected_body is not None and expected_body not in output:
                reasons.append(f"missing response marker {expected_body!r}")
            for expected_header in case.get("headers", ()):
                if expected_header not in output:
                    reasons.append(f"missing response header {expected_header!r}")
            if case.get("expect_ubus") is False:
                if "ubus mode=" in stub_log:
                    reasons.append("unexpected ubus fallback was reached")
            else:
                expected_stub = (
                    "ubus mode=" if case["ubus"] == "block" else "flock mode="
                )
                if expected_stub not in stub_log:
                    reasons.append(
                        f"fault stub was not reached ({expected_stub.strip()})"
                    )
            if (
                case.get("mapped_sid")
                and case["endpoint"] in {"luci", "reaper"}
                and case.get("expect_acl_validation", True)
            ):
                for marker in ("session access", "access-group", "luci-base", "read"):
                    if marker not in stub_log:
                        reasons.append(f"rpcd ACL validation omitted {marker!r}")
            if "expect_map" in case:
                map_path = output_path.parent / "runtime" / "dashluci" / SID
                if map_path.exists() is not case["expect_map"]:
                    reasons.append(
                        "private rpcd map preservation mismatch "
                        f"(exists={map_path.exists()}, expected={case['expect_map']})"
                    )
            if "expect_parent" in case:
                parent_path = output_path.parent / "runtime" / "dashsess" / SID
                if parent_path.exists() is not case["expect_parent"]:
                    reasons.append(
                        "Smart parent preservation mismatch "
                        f"(exists={parent_path.exists()}, expected={case['expect_parent']})"
                    )
            if "expect_pending" in case:
                pending_path = output_path.parent / "runtime" / "dashrevoke" / SID
                if pending_path.exists() is not case["expect_pending"]:
                    reasons.append(
                        "pending logout preservation mismatch "
                        f"(exists={pending_path.exists()}, expected={case['expect_pending']})"
                    )
            if reasons:
                compact_output = " ".join(output.strip().split())
                if len(compact_output) > 1200:
                    compact_output = compact_output[:1197] + "..."
                compact_stub_log = " ".join(stub_log.strip().split())
                message = (
                    "; ".join(reasons)
                    + f"; output={compact_output!r}; stubs={compact_stub_log!r}"
                )
                failures.append(f"{case['name']}: {message}")
                print(f"{case['name']}=FAIL elapsed={elapsed:.2f}s reason={message}")
            else:
                print(
                    f"{case['name']}=PASS elapsed={elapsed:.2f}s status={status}"
                )

    if failures:
        print("auth_bounded_blocking_test=FAIL", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print("auth_bounded_blocking_test=PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as error:
        print(f"auth_bounded_blocking_test=ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
