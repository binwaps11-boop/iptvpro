#!/usr/bin/env bash
# Convenience entry point for the single maintained CR6608 build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -ne 0 ] || {
	printf 'ERROR: OpenWrt must be built by an unprivileged user.\n' >&2
	exit 1
}
[ -x "${SCRIPT_DIR}/build.sh" ] || {
	printf 'ERROR: %s/build.sh is missing or not executable.\n' "${SCRIPT_DIR}" >&2
	exit 1
}

cd "${SCRIPT_DIR}"
exec ./build.sh
