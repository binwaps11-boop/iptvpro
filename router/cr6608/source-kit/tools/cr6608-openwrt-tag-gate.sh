#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

# Caller-controlled Git environment variables must not be able to redirect the
# repository, object store or configuration consulted by this trust gate.
for git_environment_name in "${!GIT_@}"; do
	unset "${git_environment_name}"
done
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_ATTR_NOSYSTEM=1
export GIT_NO_REPLACE_OBJECTS=1
export GIT_TERMINAL_PROMPT=0
export GIT_NO_LAZY_FETCH=1

fail() {
	printf 'openwrt_source_gate=fail reason=%s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 13 ] || fail 'invalid argument count'
repo="$1"
expected_origin="$2"
tag="$3"
expected_commit="$4"
expected_tag_object="$5"
key_file="$6"
expected_key_sha256="$7"
expected_signer="$8"
network_mode="$9"
retry_delay="${10}"
git_bin="${11}"
gpg_bin="${12}"
timeout_bin="${13}"

case "${network_mode}" in online-fallback|offline-only) ;; *) fail 'invalid network mode' ;; esac
case "${retry_delay}" in ''|*[!0-9]*) fail 'invalid retry delay' ;; esac
[[ "${expected_commit}" =~ ^[0-9a-f]{40}$ ]] || fail 'invalid pinned commit'
[[ "${expected_tag_object}" =~ ^[0-9a-f]{40}$ ]] || fail 'invalid pinned tag object'
[[ "${expected_key_sha256}" =~ ^[0-9a-f]{64}$ ]] || fail 'invalid pinned key hash'
[[ "${expected_signer}" =~ ^[0-9A-F]{40}$ ]] || fail 'invalid signer fingerprint'
[[ "${tag}" != *[/$'\n'$'\r'$'\t']* && "${tag}" != .* ]] || fail 'invalid tag name'
[[ "${expected_origin}" == https://* && "${expected_origin}" != *[$'\n'$'\r'$'\t']* ]] || fail 'invalid origin'
[ -d "${repo}/.git" ] && [ ! -L "${repo}/.git" ] || fail 'local OpenWrt checkout missing'
for command_path in "${git_bin}" "${gpg_bin}" "${timeout_bin}"; do
	[ -x "${command_path}" ] && [ ! -L "${command_path}" ] || fail "unsafe command path: ${command_path}"
done
[ -f "${key_file}" ] && [ ! -L "${key_file}" ] || fail 'release signing key missing or unsafe'
[ "$(sha256sum "${key_file}" | awk '{print $1}')" = "${expected_key_sha256}" ] ||
	fail 'release signing key hash mismatch'

mapfile -t origin_urls < <("${git_bin}" -C "${repo}" remote get-url --all origin)
[ "${#origin_urls[@]}" -eq 1 ] && [ "${origin_urls[0]}" = "${expected_origin}" ] ||
	fail 'local OpenWrt origin mismatch'
[ "$("${git_bin}" -C "${repo}" cat-file -t "refs/tags/${tag}" 2>/dev/null)" = tag ] ||
	fail 'local release ref is not an annotated tag'
[ "$("${git_bin}" -C "${repo}" rev-parse --verify "refs/tags/${tag}")" = "${expected_tag_object}" ] ||
	fail 'local release tag object mismatch'
[ "$("${git_bin}" -C "${repo}" rev-parse --verify "refs/tags/${tag}^{}")" = "${expected_commit}" ] ||
	fail 'local release tag commit mismatch'
[ "$("${git_bin}" -C "${repo}" rev-parse --verify HEAD)" = "${expected_commit}" ] ||
	fail 'local OpenWrt HEAD mismatch'

gnupg_home="$(mktemp -d)" || fail 'cannot allocate isolated GnuPG home'
signature_log="$(mktemp)" || { rm -rf -- "${gnupg_home}"; fail 'cannot allocate signature log'; }
remote_output="$(mktemp)" || { rm -rf -- "${gnupg_home}"; rm -f -- "${signature_log}"; fail 'cannot allocate remote output'; }
remote_error="$(mktemp)" || { rm -rf -- "${gnupg_home}"; rm -f -- "${signature_log}" "${remote_output}"; fail 'cannot allocate remote error'; }
cleanup() { rm -rf -- "${gnupg_home}"; rm -f -- "${signature_log}" "${remote_output}" "${remote_error}"; }
trap cleanup EXIT HUP INT TERM
chmod 0700 "${gnupg_home}"
key_listing="$(GNUPGHOME="${gnupg_home}" "${gpg_bin}" --batch --no-options --with-colons \
	--import-options show-only --import "${key_file}" 2>/dev/null)" ||
	fail 'release signing key cannot be parsed'
printf '%s\n' "${key_listing}" | grep -Fqx "fpr:::::::::${expected_signer}:" ||
	fail 'release signing key fingerprint mismatch'
GNUPGHOME="${gnupg_home}" "${gpg_bin}" --batch --no-options --import "${key_file}" >/dev/null 2>&1 ||
	fail 'release signing key import failed'
if ! GNUPGHOME="${gnupg_home}" "${git_bin}" -c gpg.format=openpgp \
	-c "gpg.program=${gpg_bin}" -c "gpg.openpgp.program=${gpg_bin}" -C "${repo}" \
	verify-tag --raw "refs/tags/${tag}" >"${signature_log}" 2>&1; then
	fail 'local release tag signature invalid'
fi
grep -Fq "[GNUPG:] VALIDSIG ${expected_signer} " "${signature_log}" ||
	fail 'local release tag signer mismatch'

if [ "${network_mode}" = offline-only ]; then
	printf 'openwrt_source_gate=pass remote=skipped local_signature=verified commit=%s\n' "${expected_commit}"
	exit 0
fi

network_error() {
	local status="$1"
	[ "${status}" -eq 124 ] && return 0
	grep -Eqi 'Could not resolve host|Temporary failure in name resolution|Name or service not known|Network is unreachable|No route to host|Connection (timed out|refused|reset by peer)|Failed to connect|Could not connect to server|Operation timed out|The operation timed out|Recv failure|Empty reply from server|remote end hung up unexpectedly|HTTP[^0-9]*(502|503|504)|requested URL returned error: (502|503|504)' "${remote_error}"
}

attempt=1
while [ "${attempt}" -le 3 ]; do
	: >"${remote_output}"
	: >"${remote_error}"
	set +e
	"${timeout_bin}" 30 "${git_bin}" -c protocol.version=2 -C / ls-remote \
		"${expected_origin}" "refs/tags/${tag}" "refs/tags/${tag}^{}" \
		>"${remote_output}" 2>"${remote_error}"
	remote_status=$?
	set -e
	if [ "${remote_status}" -eq 0 ]; then
		mapfile -t remote_lines <"${remote_output}"
		[ "${#remote_lines[@]}" -eq 2 ] || fail 'official release tag refs are absent or ambiguous'
		remote_tag_seen=0
		remote_commit_seen=0
		for remote_line in "${remote_lines[@]}"; do
			IFS=$'\t' read -r remote_oid remote_ref extra <<<"${remote_line}"
			[ -z "${extra:-}" ] && [[ "${remote_oid}" =~ ^[0-9a-f]{40}$ ]] ||
				fail 'official release tag response malformed'
			case "${remote_ref}" in
				"refs/tags/${tag}")
					[ "${remote_tag_seen}" -eq 0 ] || fail 'official release tag object is ambiguous'
					[ "${remote_oid}" = "${expected_tag_object}" ] || fail 'official release tag object mismatch'
					remote_tag_seen=1
					;;
				"refs/tags/${tag}^{}")
					[ "${remote_commit_seen}" -eq 0 ] || fail 'official peeled release tag is ambiguous'
					[ "${remote_oid}" = "${expected_commit}" ] || fail 'official release tag commit mismatch'
					remote_commit_seen=1
					;;
				*) fail 'official release tag response contains an unexpected ref' ;;
			esac
		done
		[ "${remote_tag_seen}" -eq 1 ] && [ "${remote_commit_seen}" -eq 1 ] ||
			fail 'official release tag refs are incomplete'
		printf 'openwrt_source_gate=pass remote=verified local_signature=verified commit=%s\n' "${expected_commit}"
		exit 0
	fi
	network_error "${remote_status}" || fail 'remote release-tag check failed for a non-network reason'
	[ "${attempt}" -lt 3 ] || break
	printf 'WARNING: OpenWrt tag network check failed (attempt %s/3); retrying\n' "${attempt}" >&2
	[ "${retry_delay}" -eq 0 ] || sleep "$((retry_delay * attempt))"
	attempt=$((attempt + 1))
done

printf 'openwrt_source_gate=pass remote=unavailable local_signature=verified commit=%s\n' "${expected_commit}"
