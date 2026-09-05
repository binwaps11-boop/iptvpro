# Derived working tree — not an attested v86 release

This tree started as the delivered `cr6608-source-kit` v86 payload and has
since been modified. The original attestation therefore no longer applies to
it, and it deliberately has not been re-attested.

## What that means concretely

`.cr6608-source-identity` still records the **received** v86 identity:

```
product_version=v86
original_commit=97bb169fc102ad9028be723153816349bd6a2772
original_tree=dfc66160f8058ca2e0b14d8c39e98bd015a090a4
```

Those hashes describe the upstream kit, not the files here. Running
`tools/cr6608_source_kit.py verify-bundle` against this tree with the v86
operator trust record will fail, and that failure is correct — this tree is
not that release. It has not been renamed to a new product version either,
because a version number would imply an attestation that does not exist.

`.cr6608-source-payload.tsv` is likewise the v86 listing and no longer matches
the files on disk. It is generated from a Git commit in the maintainer's
private repository (`payload_manifest()` in `tools/cr6608_source_kit.py`), so
regenerating it here would require fabricating a commit identity. That was not
done.

To turn this tree back into an attested release, the maintainer must run the
documented `create` / `verify-bundle` flow from `README.md` on their own
repository, with the private signing keys and an independently delivered
operator trust record.

## What changed

Driver (`patches/`), both host-side only, no new firmware command:

- `zzzzzz-06-mt7915-cr6608-muru-fault-attribution.patch`
- `zzzzzz-07-mt7915-cr6608-muru-ul-tb-attribution.patch`
- `zzzzzz-08-mt7915-cr6608-muru-live-refresh.patch`
- `zzzzzz-09-mt7915-cr6608-muru-uniform-cfg-vendor-parity.patch`
- `zzzzzz-10-mt7915-cr6608-muru-evidence-honesty.patch`
- `zzzzzz-11-mt7915-cr6608-muru-record-serialisation.patch`
- `zzzzzz-12-mt7915-cr6608-muru-he-dcm-max-ru-upstream-e5932438.patch`
- `zzzzzz-13-mt7915-cr6608-muru-recovery-lifecycle.patch`
- `zzzzzz-14-mt7915-cr6608-muru-ul-attribution-v2.patch`
- `994-mt76-makefile-mac80211-debugfs.patch` (OpenWrt tree: forwards
  `CONFIG_PACKAGE_MAC80211_DEBUGFS` to the mt76 build; without it the
  per-station debugfs nodes are compiled out on every OpenWrt image)

Build wiring:

- `build.sh` / `build.remote.sh`: the two patches added to
  `SRC_MURU_PORT_PATCHES`, the ordered-patch count raised from five to fourteen,
  and the two new source gates registered and executed.

Tests:

- `tests/test-muru-fault-attribution.sh` (new)
- `tests/test-ul-mu-evidence-runtime.sh` (new)
- `tests/test-muru-live-refresh.sh` (new)
- `tests/test-muru-vendor-parity.sh` (new)
- `tests/test-ax-feature-contracts.sh`: updated for the 26-line support
  manifest and the changed fault/OTA-evidence records.

Runtime:

- `files/usr/sbin/cr6608-ul-mu-evidence` (new, read-only)
- `files/usr/share/cr6608/ax-feature-support`: `ul_muru_fault_policy` and
  `ota_evidence` updated to describe the new behaviour; `ul_muru_rearm_policy`
  and `ul_muru_dl_floor` added (24 -> 26 lines).
- `files/usr/sbin/cr6608-ax-verify` and `inspect-image.sh`: updated to the
  same 26-line contract.

Documentation:

- `docs/CR6608-MURU-FAULT-ATTRIBUTION.md` (new)
- `README.md`: the two patches described.

## What did not change

The 38 dBm request path is untouched. `patches/999-*`, `patches/zz-*`,
`patches/zzz-*`, the DTS gates, `files/etc/config/wireless` (`txpower 38` on
both radios), `files/usr/libexec/cr6608-txpower-lib` and every power-related
verifier are byte-identical to the received v86 payload. Patch 06 only stops
an unrelated MU-RU latch from being spent when the power path schedules a
recovery; it does not change what power is requested, applied or verified.
