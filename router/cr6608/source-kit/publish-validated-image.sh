#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 0 ]; then
	printf 'usage: %s\n' "$0" >&2
	printf 'This compatibility entry point accepts no legacy publish arguments.\n' >&2
	exit 64
fi

printf 'publish-validated-image.sh is deprecated; running the single maintained release-candidate build.\n' >&2
exec "${SCRIPT_DIR}/build.sh"
