# CR6608 retail provisioning gate

The source has two explicit build profiles. `lab` remains the default and
retains the historical operator/open-WLAN behavior. A generic, fail-closed
Retail-v1 artifact is selected with either equivalent invocation:

```sh
profile=retail ./build.sh
CR6608_BUILD_PROFILE=retail ./build.sh
```

Supplying both variables with different values is rejected. Retail-v1 uses a
distinct `RETAIL-v1-UNPROVISIONED-NONSALE-RADIO-LOCKED` filename and immutable
`profile=retail-v1`, `sale_ready=NO`, `radio_policy=retail-disabled` metadata.
Both physical radios and primary BSSs are disabled, the BSS placeholders have
protected encryption but no key, root and Web verifiers are locked, neither a
country nor TX power is forced, and the mt7915e line fixes both
`cr6608_rf_38dbm=0` and `cr6608_ul_muru=0`. A trusted serial/factory shell is
therefore required to run per-device provisioning; the generic Retail image
has no reusable network bootstrap credential. For a board without an already
trusted factory shell, the build also supports a separate **RAM-only**
commissioning image containing exactly one factory ED25519 public key. It is
explicitly non-sale, disables password authentication, publishes no
sysupgrade/combined firmware, and must never be written to flash. Factory-38
maintenance mode is LAB-only and is rejected with the Retail profile.

Place the factory public key (never its private key) under the final source
tree's `device-inputs/` directory and build the temporary image with:

```sh
CR6608_BUILD_PROFILE=retail \
CR6608_RETAIL_COMMISSIONING_MODE=1 \
CR6608_RETAIL_COMMISSIONING_KEY="$PWD/../device-inputs/factory-ed25519.pub" \
./build.sh
```

The resulting filename contains
`FACTORY-COMMISSIONING-NONSALE-RAMBOOT-ONLY`. The inspector binds its
`authorized_keys` bytes and SSH fingerprint to a root-owned `0400`
commissioning marker and proves both Dropbear password switches are off. The
image is valid only when `/` is a `tmpfs` initramfs root; the provisioner
rejects the commissioning identity on a persistent overlay root.

The Retail build-time overlay also atomically replaces the legacy LAB Web
verifier embedded in the preserved-config migration with `!`. The Retail
rootfs therefore contains neither an active shared credential nor the retired
shared verifier bytes. The LAB profile remains byte-for-byte unchanged so its
controlled recovery migration continues to work.

The owner-requested operator firmware image is intentionally **not
sale-ready**. SSH and the serial console are password-gated on a clean boot,
but that recovery credential is shared across operator images. No Wi-Fi key is
embedded, and the two primary APs are intentionally visible, enabled and open
for the requested lab/onboarding workflow. The release metadata therefore
reports that unique-device provisioning is pending. An open-lab image with a
shared operator credential must never be packaged for sale unchanged.

In that operator state, `system.@system[0].ttylogin=1` requires the root
credential on the serial console as well as SSH. Physical access and the open
onboarding WLANs must still remain inside the controlled factory station. A
board-scoped migration repairs older settings-preserving installations whose
usable root hash exists but whose console gate was not enabled. Successful
fresh provisioning keeps `ttylogin=1`; the sale audit rejects the shared
operator hash, a passwordless console, or any open primary AP.

For every physical unit, the factory must generate three pairwise-distinct
random secrets: a 12-80 character root password, a 12-63 character Wi-Fi key,
and a 12-80 character Smart AP/LuCI Web password. All three must be unique
across the fleet, must not be derived from the MAC address or serial number,
and must be printed or delivered to the owner through a controlled channel.
The Web login username remains `root`, but its password is deliberately
independent from the SSH/serial `root` password. The source tree and generic
firmware must never contain any per-device secret.
The generated Wi-Fi key and Smart AP Web password must use only ASCII letters,
digits, `.`, `_`, `~`, or `-`; this narrow alphabet lets the provisioner quote
the Wi-Fi key exactly in UCI batch input without accepting a command-language
metacharacter, and guarantees that mobile clipboard cleanup cannot alter a
provisioned Web credential.

From a trusted serial-console or isolated factory shell, write each secret as
one line in a different regular, non-symlink, root-owned `0400` or `0600` file,
then run:

```sh
cr6608-retail-provision \
  --root-password-file /tmp/device-root.secret \
  --wifi-key-file /tmp/device-wifi.secret \
  --web-password-file /tmp/device-web.secret \
  --market-country SA \
  --ssid24 'Customer 2.4G' \
  --ssid5 'Customer 5G'
reboot
```

When this command runs in the RAM-only commissioning image, the provisioner
also changes Dropbear from factory-key-only access to the new unique root
password, performs the pending audit, deletes the factory authorized key and
commissioning marker, synchronizes the deletion, and only then publishes the
completed Retail marker. Any failure restores the original factory access and
configuration for a controlled retry while the unit is still running from
RAM. The success record includes `commissioning_finalized=1`; it is still not
sale approval.

The tool deliberately refuses plaintext secret command-line arguments so they
do not leak through process listings or shell history. Root and Web secrets go
only to stdin consumers; Wi-Fi values go to `uci -q batch` on stdin and are
never written to a reusable plaintext temporary file. It rejects short,
reused, known-common and retired shared credentials, enables WPA2/WPA3 mixed
mode with PMF, enables both radios, enables HTTP-to-HTTPS redirection, and
writes a salted SHA-512-crypt root verifier through BusyBox `passwd` and a
separate salted SHA-512-crypt Web verifier into the single `rpcd` root-login
section. Both passwords are supplied through stdin, so neither appears in a
process argument. It first takes the same apply and kernel mutation locks used
by Quick Settings/dashctl. Before creating the apply-lock directory it
atomically publishes a root-owned PID/start claim, allowing a killed ownerless
creation window to be recovered without stealing the lock from a live creator.
Once both locks are held, it atomically writes and synchronizes a root-only
`0400` `/etc/cr6608-retail-provisioning-pending` journal before the first
credential or UCI mutation. A concurrent provisioner or UI writer is rejected
without waiting or changing state. In the same rollback-protected UCI
transaction it writes the
market code to both radio `country` options, both `smartap.quick` country
mirrors, and all three `cr6608quick.default` country mirrors. It commits and
reads back every mirror before activating the new configuration. The
provisioner then restarts `rpcd` to invalidate sessions made with the old
shared credential, restarts `uhttpd`, and reloads Wi-Fi so the synchronized
country configuration is applied before the final audit. That audit verifies
the pending state and the live marker-selected AP on each radio. Because
netifd/hostapd activation is asynchronous, transient primary-runtime binding
failures are retried for a bounded 30-second window while both transaction
locks remain held; a permanent failure rolls the whole transaction back. Only
after it passes does the provisioner atomically publish the non-secret, read-only
`0400` `/etc/cr6608-retail-provisioned` marker with `audit_complete=YES`, remove
the pending journal, and synchronize storage. The marker binds the
manufacturing market code but deliberately records `sale_ready=NO`. On a LAB
artifact its radio policy remains `LAB_ARTIFACT_BLOCKED`; on an immutable
Retail-v1 artifact it becomes `retail-disabled-after-reboot`, which still
requires a reboot and the separate radio audit. Neither marker is sale approval
and a writable overlay cannot promote a LAB artifact. It discovers the primary AP for
each radio deterministically: a validated canonical client AP wins; otherwise
exactly one eligible LAN/VLAN AP must exist. Guest, WDS backhaul and Multi-AP
backhaul sections are never selected by first-match order. A canonical AP left
in WDS sender mode by Quick Settings remains deterministic and is explicitly
converted back to a normal AP; an unnamed WDS fallback is never selected.
Provisioning also removes alternate PSK/SAE/RADIUS/PPSK/Multi-AP/WPS sources and opaque raw
hostapd directives from the managed BSSs and both radios. If country
staging/readback, any UCI commit, rpcd, uhttpd, Wi-Fi reload, marker creation,
or the final audit fails, it verifies restoration of `/etc/shadow`, every
affected UCI file (including all previous country mirrors), the marker, and
each previous service runtime before reporting failure. HUP, INT, and TERM
exit through the same rollback path. The old complete marker is restored only
after every configuration and requested runtime restore succeeds. Any copy,
UCI-revert, marker, or runtime restoration failure instead republishes and
synchronizes the pending journal first, removes/synchronizes the complete
marker, and keeps normal QA fail-closed for a controlled retry.

A power cut cannot run that rollback. If reboot finds the pending journal, or
finds a malformed/incomplete final marker, the board-scoped preserved-config
migration preserves the newly written credentials, disables both Wi-Fi radios,
does not enter open onboarding, and exits nonzero so the migration remains
retryable. Factory staff must inspect the journal and rerun controlled
provisioning; deleting it and reopening the APs is not a recovery procedure.

This synchronization is configuration application, not regulatory/RF proof.
The success line therefore still reports `reboot_required=1`; after reboot the
separate retail artifact must pass `cr6608-retail-radio-audit`, including its
live `iw reg get` check, before any market-specific radio approval.

Keep the root, Wi-Fi and Web secret files inside the controlled station until final
QA. After reboot and immediately before packaging, run:

```sh
cr6608-retail-audit \
  --root-password-file /tmp/device-root.secret \
  --wifi-key-file /tmp/device-wifi.secret \
  --web-password-file /tmp/device-web.secret
```

The audit fails closed without all three root-only files. It verifies the
supplied root password against the salted SHA-512 `/etc/shadow` hash, the exact
primary Wi-Fi key, and the supplied Web password against the salted `rpcd` hash.
It rejects a pending provisioning journal in normal QA mode, retired shared
root/Web hashes, duplicate/ambiguous root-login sections,
unsafe ACLs, a pre-v2/incomplete marker, open or unsupported enabled wireless
roles, alternate credentials, enabled WPS, Multi-AP/raw-hostapd overrides, and
reuse of the Web password as any active wireless key. It also requires the
exact IPv4 and IPv6 HTTPS endpoints,
configured certificate/key files whose certificate is currently valid, whose
private key parses and passes OpenSSL's consistency check, and whose public
keys match; live IPv4 and IPv6 TCP/443 listeners; a successful bounded TLS
request to the IPv4 loopback HTTPS
endpoint, password-gated serial login, at least one enabled WPA-protected PMF
AP on each radio, and a live netifd section -> interface -> `iw type AP` ->
enabled-hostapd chain for both marker primary APs. Its success line retains
`sale_ready=NO` and repeats the artifact-bound marker policy: LAB remains
`LAB_ARTIFACT_BLOCKED`, while Retail-v1 reports
`retail-disabled-after-reboot`. This is a credential/TLS result, never sale
approval.
After recording that result, securely remove the station's three temporary
secret files according to factory policy. The manufacturing database must
enforce fleet-wide uniqueness; a single router cannot prove that its secrets
are different from every other router.

A settings-preserving sysupgrade keeps the unit's `/etc/shadow`, wireless
configuration, complete provisioning marker, and pending provisioning journal
when it runs from the successfully commissioned RAM image to the matching clean
generic Retail sysupgrade.
It must be run only after `commissioning_finalized=1` and after independently
verifying that both `/etc/dropbear/authorized_keys` and
`/etc/cr6608-retail-commissioning-ram` are absent. Do not use `sysupgrade -n`:
that intentionally discards the unique credentials and returns the unit to the
locked unprovisioned profile. The clean generic Retail image itself contains
neither factory key nor commissioning marker, and the commissioning build
publishes no flashable image.
When a valid complete marker exists and no pending journal exists,
`99-cr6608-preserved-config-v2` does not modify `rpcd` or any wireless option:
it cannot restore the shared Web hash or reopen protected APs. A pending
journal, symlinked marker, or malformed/incomplete complete marker takes
precedence and disables Wi-Fi while preserving credentials; it never falls
through to onboarding. Only a genuinely unprovisioned LAB unit with neither
marker uses the board-scoped deterministic recovery Web credential and open
primary-AP policy. An unprovisioned Retail-v1 unit instead keeps root/Web locked
and both radios disabled; a malformed immutable profile takes the same
fail-closed path. The secure-console
migration still password-gates the serial console when a usable root hash
exists. A clean install or `sysupgrade -n` returns to the selected profile's
immutable defaults: shared/open only for LAB, locked/radio-off for Retail-v1.
Retail-v1 remains `sale_ready=NO` even after credential provisioning; reboot,
factory-reset proof, artifact hash, the radio-policy audit, device runtime QA,
and external RF approval are still required.

`luci-ssl` creates a device-local self-signed TLS key/certificate when no
factory certificate is installed. This prevents cleartext credential
submission after provisioning, but browsers will warn until the factory
installs a certificate trusted by its managed clients or the owner explicitly
trusts the device certificate. A publicly trusted certificate cannot safely be
shared in the image.
