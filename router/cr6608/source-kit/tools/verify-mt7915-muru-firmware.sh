#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s MT76_SOURCE_DIR\n' "$0" >&2
	exit 2
}

source_dir="$1"
[ -d "$source_dir" ] && [ ! -L "$source_dir" ] || {
	printf 'invalid mt76 source directory: %s\n' "$source_dir" >&2
	exit 1
}

verify_blob() {
	name="$1"
	expected="$2"
	path="$source_dir/firmware/$name"
	[ -f "$path" ] && [ ! -L "$path" ] || {
		printf 'missing regular firmware blob: %s\n' "$path" >&2
		exit 1
	}
	actual="$(sha256sum "$path" | awk '{print $1}')"
	[ "$actual" = "$expected" ] || {
		printf 'firmware hash mismatch: %s expected=%s actual=%s\n' \
			"$name" "$expected" "$actual" >&2
		exit 1
	}
}

verify_blob mt7915_rom_patch.bin \
	43883a5d78758e895b2a294478e3fd136cf98737100fe44ba1f57cb54332317f
verify_blob mt7915_wa.bin \
	686d6a049a7fa07b47bd09fdcb86c7b807f66f6a9808af55440d5e5276e4c860
verify_blob mt7915_wm.bin \
	73ae4c95fcef55f2e537e2d122d267d4cb666f896e96ec5e88573839bcf985b2

# Pin both identity and content. The printable identity is useful in runtime
# evidence, while SHA-256 prevents a same-name replacement.
grep -aFq 'MT7915_MP_7_4_2045-20240429200502' \
	"$source_dir/firmware/mt7915_wm.bin" || {
	printf 'unexpected MT7915 WM firmware identity\n' >&2
	exit 1
}

printf 'mt7915_muru_firmware_baseline=pass\n'
