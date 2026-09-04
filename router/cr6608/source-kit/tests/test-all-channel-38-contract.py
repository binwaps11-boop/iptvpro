#!/usr/bin/env python3
"""Source contract for the CR6608 all-channel 38 dBm request path.

This test proves coverage of the persisted per-chain EEPROM targets and the
driver transaction plumbing.  It deliberately does not claim measured RF
output: the displayed current power must continue to come from MCU readback.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from types import ModuleType


KIT_DIR = Path(__file__).resolve().parent.parent
BUILDER_PATH = KIT_DIR / "factory38" / "build_factory38.py"
FACTORY_PATCH_PATH = KIT_DIR / "patches" / "zz-mt7915-cr6608-factory38-path.patch"
FIRMWARE_SHADOW_PATCH_PATH = KIT_DIR / "patches" / "zzz-mt7915-cr6608-firmware-eeprom-shadow.patch"
RF_PATCH_PATH = KIT_DIR / "patches" / "999-mt7915-cr6608-rf-38dbm-request-path.patch"
LUCI_PATCH_PATH = KIT_DIR / "patches" / "993-luci-wireless-preserve-configured-txpower.patch"
FULL_VERIFY_PATH = KIT_DIR / "files" / "usr" / "bin" / "cr6608-wifi-full-verify"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"all-channel-38 contract failed: {message}")


def load_builder() -> ModuleType:
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("cr6608_factory38_builder", BUILDER_PATH)
    require(spec is not None and spec.loader is not None, "cannot load Factory-38 builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def added_lines(patch_text: str) -> str:
    """Return code added by a unified diff, excluding its +++ file header."""

    return "\n".join(
        line[1:]
        for line in patch_text.splitlines()
        if line.startswith("+") and not line.startswith("+++")
    )


def mt7915_group_5g(channel: int) -> int:
    """Model mt7915_get_channel_group_5g(channel, false) for the CR6608."""

    if 184 <= channel <= 196:
        return 0
    if channel <= 48:
        return 1
    if channel <= 64:
        return 2
    if channel <= 96:
        return 3
    if channel <= 112:
        return 4
    if channel <= 128:
        return 5
    if channel <= 144:
        return 6
    return 7


builder = load_builder()
require(
    getattr(builder, "FACTORY38_CHAIN_COUNT", None) == 4,
    "builder must declare all four EEPROM chains",
)
require(
    getattr(builder, "FACTORY38_2G_CHANNEL_GROUP_COUNT", None) == 1,
    "builder must declare the single 2.4 GHz channel group",
)
require(
    getattr(builder, "FACTORY38_5G_CHANNEL_GROUP_COUNT", None) == 8,
    "builder must declare all eight 5 GHz channel groups",
)

changes = builder.target_changes()
require(len(changes) == 36, "builder must change exactly 36 target bytes")
coverage = builder.channel_group_coverage(changes)
require(coverage.get("chain_count") == 4, "coverage manifest must declare four chains")
require(
    coverage.get("all_supported_channels_targeted") is True,
    "coverage manifest must bind every supported channel to a target group",
)
require(
    coverage.get("2g")
    == {
        "group_count": 1,
        "groups": [0],
        "all_supported_channels_targeted": True,
    },
    "coverage manifest must declare the complete 2.4 GHz group set",
)
require(
    coverage.get("5g")
    == {
        "group_count": 8,
        "groups": list(range(8)),
        "all_supported_channels_targeted": True,
    },
    "coverage manifest must declare the complete 5 GHz group set",
)

actual = [
    (
        change.get("band"),
        change.get("chain"),
        change.get("group"),
        change.get("offset"),
        change.get("expected_old"),
        change.get("new"),
    )
    for change in changes
]
expected = [
    (
        "2g",
        chain,
        0,
        builder.TX0_POWER_2G + chain * 3,
        builder.EXPECTED_2G_RAW,
        builder.FACTORY38_2G_RAW,
    )
    for chain in range(4)
] + [
    (
        "5g",
        chain,
        group,
        builder.TX0_POWER_5G + chain * 12 + group,
        builder.EXPECTED_5G_RAW,
        builder.FACTORY38_5G_RAW,
    )
    for chain in range(4)
    for group in range(8)
]
require(actual == expected, "builder target map is not the exact 4x1 plus 4x8 layout")
require(len({entry[3] for entry in actual}) == 36, "builder target offsets must be unique")
require(builder.FACTORY38_2G_RAW == 0x40, "2.4 GHz raw target must remain 0x40")
require(builder.FACTORY38_5G_RAW == 0x42, "5 GHz raw target must remain 0x42")
rate_delta_2g = builder.EXPECTED_RATE_DELTA_2G & 0x3F
rate_delta_5g = builder.EXPECTED_RATE_DELTA_5G & 0x3F
two_chain_path_delta = 6
require(rate_delta_2g == 6, "2.4 GHz rate delta must remain six half-dBm")
require(rate_delta_5g == 4, "5 GHz rate delta must remain four half-dBm")
require(
    (builder.FACTORY38_2G_RAW + rate_delta_2g + two_chain_path_delta) / 2 == 38,
    "2.4 GHz Factory target no longer calculates to 38 dBm",
)
require(
    (builder.FACTORY38_5G_RAW + rate_delta_5g + two_chain_path_delta) / 2 == 38,
    "5 GHz Factory target no longer calculates to 38 dBm",
)
stock_2g_dbm = (builder.EXPECTED_2G_RAW + rate_delta_2g + two_chain_path_delta) / 2
stock_5g_dbm = (builder.EXPECTED_5G_RAW + rate_delta_5g + two_chain_path_delta) / 2
require(stock_2g_dbm == 26, "2.4 GHz stock Factory calculation changed")
require(stock_5g_dbm == 24, "5 GHz stock Factory calculation changed")
require(
    max(stock_2g_dbm, stock_5g_dbm) < 38,
    "volatile override fixture no longer distinguishes stock Factory from 38 dBm",
)
corrupt_rate_delta = 0xFF & 0x3F
require(
    (builder.EXPECTED_2G_RAW + corrupt_rate_delta + two_chain_path_delta) / 2 > 38,
    "rate-delta mutation fixture must demonstrate the unclamped 2.4 GHz hazard",
)
require(
    (builder.EXPECTED_5G_RAW + corrupt_rate_delta + two_chain_path_delta) / 2 > 38,
    "rate-delta mutation fixture must demonstrate the unclamped 5 GHz hazard",
)

target_by_coordinate = {
    (str(change["band"]), int(change["chain"]), int(change["group"])): int(change["new"])
    for change in changes
}
require(len(target_by_coordinate) == 36, "band/chain/group coordinates must be unique")

# Boundary and representative channel probes for every branch of the upstream
# non-MT7976 mt7915 group mapping used by the CR6608.
group_channel_probes = {
    0: (184, 188, 192, 196),
    1: (36, 40, 44, 48),
    2: (52, 56, 60, 64),
    3: (68, 80, 96),
    4: (100, 104, 108, 112),
    5: (116, 120, 124, 128),
    6: (132, 136, 140, 144),
    7: (149, 153, 157, 161, 165, 169, 173, 177),
}
require(set(group_channel_probes) == set(range(8)), "5 GHz mapping probes must cover groups 0..7")
for expected_group, channels in group_channel_probes.items():
    for channel in channels:
        group = mt7915_group_5g(channel)
        require(group == expected_group, f"channel {channel} mapped to group {group}")
        for chain in range(4):
            require(
                target_by_coordinate.get(("5g", chain, group)) == 0x42,
                f"channel {channel} chain {chain} lacks its 5 GHz target byte",
            )
for channel in range(1, 15):
    for chain in range(4):
        require(
            target_by_coordinate.get(("2g", chain, 0)) == 0x40,
            f"2.4 GHz channel {channel} chain {chain} lacks its target byte",
        )

factory_patch = added_lines(FACTORY_PATCH_PATH.read_text(encoding="utf-8"))
require(
    re.search(r"^#define\s+CR6608_FACTORY38_5G_GROUPS\s+8\s*$", factory_patch, re.MULTILINE)
    is not None,
    "companion patch must define eight 5 GHz groups",
)
require(
    re.search(
        r"for\s*\(group\s*=\s*0;\s*group\s*<\s*CR6608_FACTORY38_5G_GROUPS;\s*group\+\+\)",
        factory_patch,
    )
    is not None,
    "companion persisted-byte gate must iterate the named 5 GHz group count",
)
require(
    re.search(r"group\s*<\s*8\b", factory_patch) is None,
    "companion persisted-byte gate must not regress to a magic group count",
)
for marker in (
    "#define CR6608_FACTORY38_TARGET_2G",
    "0x40",
    "#define CR6608_FACTORY38_TARGET_5G",
    "0x42",
    "#define CR6608_FACTORY38_SAFE_2G",
    "0x28",
    "#define CR6608_FACTORY38_SAFE_5G",
    "0x26",
    "#define CR6608_FACTORY38_SAFE_DELTA_2G",
    "#define CR6608_FACTORY38_SAFE_DELTA_5G",
    "MT_EE_TX0_POWER_2G + chain * 3",
    "MT_EE_TX0_POWER_5G + chain * 12 + group",
    "target_power = CR6608_FACTORY38_TARGET_2G",
    "target_power = CR6608_FACTORY38_TARGET_5G",
    "mt7915_cr6608_factory38_raw_match(dev)",
    "bool mt7915_cr6608_rf_request_armed(struct mt7915_dev *dev);",
    "bool mt7915_cr6608_factory38_raw_match(struct mt7915_dev *dev);",
    "request_armed && !persisted_match",
    "CR6608_FACTORY38_SAFE_2G",
    "CR6608_FACTORY38_SAFE_5G",
    "if (mt7915_cr6608_rf_request_armed(dev))",
    "return CR6608_FACTORY38_SAFE_DELTA_2G;",
    "return CR6608_FACTORY38_SAFE_DELTA_5G;",
    "all eight 5 GHz EEPROM channel groups",
):
    require(marker in factory_patch, f"companion patch lacks {marker!r}")
for name, value in (
    ("CR6608_FACTORY38_SAFE_DELTA_2G", 6),
    ("CR6608_FACTORY38_SAFE_DELTA_5G", 4),
):
    require(
        re.search(rf"^#define\s+{name}\s+{value}\s*$", factory_patch, re.MULTILINE)
        is not None,
        f"companion patch must define {name} as {value}",
    )
require(
    re.search(
        r"if\s*\(mt7915_cr6608_rf_request_armed\(dev\)\)\s*\{\s*"
        r"/\*\s*Match the audited Factory-38 rate deltas in volatile RAM\.\s*\*/\s*"
        r"if\s*\(band\s*==\s*NL80211_BAND_2GHZ\)\s*"
        r"return\s+CR6608_FACTORY38_SAFE_DELTA_2G;\s*"
        r"if\s*\(band\s*==\s*NL80211_BAND_5GHZ\)\s*"
        r"return\s+CR6608_FACTORY38_SAFE_DELTA_5G;\s*\}",
        factory_patch,
        re.DOTALL,
    )
    is not None,
    "armed volatile override must select both audited rate deltas before reading the persisted byte",
)

firmware_shadow_raw = FIRMWARE_SHADOW_PATCH_PATH.read_text(encoding="utf-8")
firmware_shadow = added_lines(firmware_shadow_raw)
for marker in (
    "mt7915_cr6608_prepare_firmware_eeprom_shadow",
    "mt7915_cr6608_rf_request_enabled(dev)",
    "kmemdup(eep, eeprom_size, GFP_KERNEL)",
    "kfree(shadow);",
    "CR6608_FIRMWARE_TARGET_2G",
    "CR6608_FIRMWARE_TARGET_5G",
    "shadow[MT_EE_TX0_POWER_2G + chain * 3]",
    "shadow[MT_EE_TX0_POWER_5G + chain * 12 + group]",
    "physical Factory stays read-only",
    "rate-SKU readback can witness 70 half-dBm",
):
    require(marker in firmware_shadow, f"firmware EEPROM shadow patch lacks {marker!r}")
for name, value in (
    ("CR6608_FIRMWARE_TARGET_2G", "0x40"),
    ("CR6608_FIRMWARE_TARGET_5G", "0x42"),
    ("CR6608_FIRMWARE_CHAINS", "4"),
    ("CR6608_FIRMWARE_5G_GROUPS", "8"),
):
    require(
        re.search(rf"^#define\s+{name}\s+{value}\s*$", firmware_shadow, re.MULTILINE)
        is not None,
        f"firmware EEPROM shadow must define {name} as {value}",
    )
require(
    all(token not in firmware_shadow for token in ("mtd_write", "mtd_erase", "MTD_OPS_PLACE_OOB")),
    "firmware EEPROM shadow must never write physical calibration storage",
)

rf_patch_raw = RF_PATCH_PATH.read_text(encoding="utf-8")
rf_patch = added_lines(rf_patch_raw)
for marker in (
    "chan->max_power = min_t(int, target_power, 38)",
    "chan->orig_mpwr = min_t(int, target_power, 38)",
    "every channel change requires MCU SKU readback",
    "mt7915_cr6608_poll_sku_readback",
    "mt7915_mcu_get_txpower_sku",
    "rate-SKU MCU witness verified",
):
    require(marker in rf_patch, f"RF patch lacks {marker!r}")

armed_start = rf_patch.find("bool mt7915_cr6608_rf_request_armed(struct mt7915_dev *dev)")
gate_start = rf_patch.find("bool mt7915_cr6608_rf_request_enabled(struct mt7915_dev *dev)")
gate_end = rf_patch.find("static bool mt7915_cr6608_channel_ready", gate_start)
require(
    armed_start >= 0 and gate_start > armed_start and gate_end > gate_start,
    "cannot isolate the CR6608 armed and exact-Factory request gates",
)
armed_gate = rf_patch[armed_start:gate_start]
request_gate = rf_patch[gate_start:gate_end]
require(
    '"mediatek,cr6608-lab-txpower-38dbm"' in armed_gate
    and "cr6608_rf_38dbm" in armed_gate
    and "factory38_raw_match" not in armed_gate,
    "RF armed gate is not the exact device/DTS/module predicate",
)
require(
    "bool enabled = mt7915_cr6608_rf_request_armed(dev);" in request_gate
    and "mt7915_cr6608_factory38_raw_match(dev);" in request_gate,
    "RF request gate does not arm the volatile target while retaining persisted telemetry",
)
require(
    "WRITE_ONCE(cr6608_rf_38dbm_active, enabled);" in request_gate,
    "RF active telemetry is not cleared when the persisted Factory gate fails",
)
require(
    "CR6608 DTS property and cr6608_rf_38dbm=1 are both required" in rf_patch,
    "RF rejection path does not identify the device/DTS/module requirements",
)

set_channel_start = rf_patch_raw.find("int mt7915_set_channel(struct mt76_phy *mphy)")
set_channel_end = rf_patch_raw.find("static int mt7915_set_sar_specs", set_channel_start)
require(set_channel_start >= 0 and set_channel_end > set_channel_start, "cannot isolate channel-change path")
set_channel = rf_patch_raw[set_channel_start:set_channel_end]
lowering_call = "mt7915_mcu_set_txpower_sku(phy, true, false, true, true)"
raising_call = "mt7915_mcu_set_txpower_sku(phy, true, false, true, false)"
require(lowering_call in set_channel, "channel change lacks its pre-switch lowering/readback transaction")
require(raising_call in set_channel, "channel change lacks its post-switch set/readback transaction")
require(
    set_channel.index(lowering_call) < set_channel.index(raising_call),
    "channel-change SKU transactions are out of order",
)

transaction_start = rf_patch.find("mt7915_cr6608_mcu_set_txpower_sku(struct mt7915_phy *phy")
transaction_end = rf_patch.find("int mt7915_mcu_set_txpower_sku(struct mt7915_phy *phy", transaction_start)
require(
    transaction_start >= 0 and transaction_end > transaction_start,
    "cannot isolate verified MCU SKU transaction",
)
transaction = rf_patch[transaction_start:transaction_end]
readback_index = transaction.find("ret = mt7915_cr6608_poll_sku_readback(")
witness_index = transaction.find("rate-SKU MCU witness verified", readback_index)
current_index = transaction.find("mphy->txpower_cur = accepted_txpower_cur;", witness_index)
require(readback_index >= 0, "RF transaction lacks MCU SKU readback")
require(witness_index > readback_index, "RF transaction publishes a witness before readback")
require(current_index > witness_index, "verified current power is not published after the MCU witness")
require(
    re.search(r"\btxpower_cur\s*=\s*(?:38|requested_power|kernel_power)\b", rf_patch) is None,
    "RF patch hardcodes current power instead of using verified MCU state",
)
require(
    re.search(
        r"if\s*\(mt7915_cr6608_rf_request_armed\(dev\)\)\s*"
        r"return\s+-EPERM;",
        rf_patch,
    )
    is not None,
    "armed CR6608 path must reject the unverified debugfs SKU write bypass",
)

luci_patch = added_lines(LUCI_PATCH_PATH.read_text(encoding="utf-8"))
require("for (let dbm = 1; dbm <= 38; dbm++)" in luci_patch, "LuCI selector does not list 1..38 dBm")
require("this.value(key, `${key} dBm`);" in luci_patch, "LuCI 38 dBm label is not compact")
for removed_text in (
    "configured request, outside current driver list; actual may be lower",
    "outside current driver list",
    "actual may be lower",
):
    require(removed_text not in luci_patch, f"LuCI still adds the removed suffix {removed_text!r}")
require(
    re.search(r"\bpowerval\s*=\s*38\b", luci_patch) is None,
    "LuCI must not hardcode Current power to 38",
)
require(
    re.search(r"Current power.*38\s*dBm", luci_patch, re.IGNORECASE) is None,
    "LuCI must not render a literal Current power of 38 dBm",
)

full_verify = FULL_VERIFY_PATH.read_text(encoding="utf-8")
for marker in (
    'uci -q set "wireless.${radio}.txpower=38"',
    "rf_witness_for_channel",
    "cr6608_rf_38dbm_active",
    "cr6608_factory38_persisted_match",
    "requested_dbm",
    "kernel_dbm",
    "path_delta_half_dbm",
    "eeprom_target_per_path_half_dbm",
    "sku_applied_per_path_half_dbm",
    "mcu_generation",
    "mcu_result",
    '[ "$mcu_witness" = verified ]',
    '"$error;probe=$probe_result;mcu=$mcu_witness"',
    "run_coverage_complete",
    "runnable_channels_2g",
    "runnable_channels_5g",
    "RUN_COVERAGE=2.4GHz:",
):
    require(marker in full_verify, f"all-channel runtime verifier lacks {marker!r}")
require(
    "($1 + 0) == 38" in full_verify,
    "all-channel runtime verifier must require exact live 38 dBm",
)
require(
    "($1 + 0) >= 38" not in full_verify,
    "all-channel runtime verifier must not accept a non-exact Current value",
)

with tempfile.TemporaryDirectory(prefix="cr6608-rf-witness-contract.") as fixture_dir:
    fixture = Path(fixture_dir)
    (fixture / "cr6608_rf_38dbm_active").write_text("Y\n", encoding="ascii")
    (fixture / "cr6608_factory38_persisted_match").write_text("Y\n", encoding="ascii")
    for band_idx, channel, frequency in ((0, 1, 2412), (1, 149, 5745)):
        values = {
            "generation": 12,
            "requested_dbm": 38,
            "kernel_dbm": 38,
            "frequency_mhz": frequency,
            "channel": channel,
            "path_delta_half_dbm": 6,
            "sar_bounded_per_path_half_dbm": 70,
            "rate_limited_per_path_half_dbm": 70,
            "eeprom_target_per_path_half_dbm": 70,
            "sku_applied_per_path_half_dbm": 70,
            "override_active": 1,
            "channel_ready": 1,
            "mcu_generation": 12,
            "mcu_result": 0,
        }
        for name, value in values.items():
            (fixture / f"cr6608_rf_band{band_idx}_{name}").write_text(
                f"{value}\n", encoding="ascii"
            )

    shell = "/bin/sh"
    if os.name == "nt":
        shell = str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/sh.exe")
    require(Path(shell).is_file(), f"POSIX shell is unavailable at {shell}")
    shell_contract = r'''
set -eu
fixture_root="$1"
verifier_path="$2"
set --
CR6608_WIFI_FULL_VERIFY_LIBRARY_ONLY=1
CR6608_RF_PARAM_ROOT="$fixture_root"
export CR6608_WIFI_FULL_VERIFY_LIBRARY_ONLY CR6608_RF_PARAM_ROOT
. "$verifier_path"
if run_coverage_complete; then
    exit 11
fi
runnable_channels_2g=11
run_attempts_2g=22
run_passes_2g=22
if run_coverage_complete; then
    exit 12
fi
runnable_channels_5g=25
run_attempts_5g=50
run_passes_5g=50
run_coverage_complete
run_passes_5g=49
if run_coverage_complete; then
    exit 13
fi
run_passes_5g=50
test "$(widths_for_row 5GHz 0 0 0 165)" = "HE20"
test "$(widths_for_row 5GHz 0 0 0 149)" = "$(printf 'HE20\nHE40\nHE80')"
rf_witness_for_channel 2.4GHz 1 2412
rf_witness_for_channel 5GHz 149 5745
if rf_witness_for_channel 2g 1 2412; then
    exit 21
fi
printf '%s\n' -5 > "$fixture_root/cr6608_rf_band1_mcu_result"
if rf_witness_for_channel 5GHz 149 5745; then
    exit 22
fi
printf '%s\n' 0 > "$fixture_root/cr6608_rf_band1_mcu_result"
printf '%s\n' 71 > "$fixture_root/cr6608_rf_band1_sar_bounded_per_path_half_dbm"
if rf_witness_for_channel 5GHz 149 5745; then
    exit 25
fi
printf '%s\n' 70 > "$fixture_root/cr6608_rf_band1_sar_bounded_per_path_half_dbm"
printf '%s\n' N > "$fixture_root/cr6608_factory38_persisted_match"
if ! rf_witness_for_channel 5GHz 149 5745; then
    exit 23
fi
printf '%s\n' Y > "$fixture_root/cr6608_factory38_persisted_match"
printf '%s\n' 13 > "$fixture_root/cr6608_rf_band0_generation"
if rf_witness_for_channel 2.4GHz 1 2412; then
    exit 24
fi
printf '%s\n' rf_witness_contract=pass
'''
    result = subprocess.run(
        [
            shell,
            "-c",
            shell_contract,
            "cr6608-rf-witness-contract",
            str(fixture).replace("\\", "/"),
            str(FULL_VERIFY_PATH).replace("\\", "/"),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    require(
        result.returncode == 0,
        f"runtime RF witness fixture failed ({result.returncode}): {result.stderr.strip()}",
    )
    require(
        result.stdout.strip() == "rf_witness_contract=pass",
        f"runtime RF witness fixture returned unexpected output: {result.stdout!r}",
    )

print("all_channel_38_contract=pass")
