#!/usr/bin/env python3
# CR6608 38 dBm mt76 driver patch — TARGETED (anchored to real mt76-2025.11 source).
# Only touches per-rate SKU power arrays + per-channel max_power + adds a driver banner.
# NO blind number replacement. Units: mt76 SKU arrays are half-dBm (0.5 dBm) -> 76=38.0,
# 72=36.0, 68=34.0 dBm. chan->max_power is whole dBm -> 38.
import os, sys

MT76 = os.environ["MT76DIR"]

def apply(relpath, anchor, insert, tag):
    p = os.path.join(MT76, relpath)
    s = open(p).read()
    n = s.count(anchor)
    if n != 1:
        sys.stderr.write("FATAL: anchor %r found %d times in %s (need exactly 1)\n" % (tag, n, relpath))
        sys.exit(3)
    end = s.find(anchor) + len(anchor)
    s = s[:end] + insert + s[end:]
    open(p, "w").write(s)
    print("OK: applied %s in %s" % (tag, relpath))

# --- mt7915/mcu.c : raise the per-rate SKU limits (struct mt76_power_limits la) before
#     they are marshalled to firmware. Anchor is unique to set_txpower_sku's sku_limit_en
#     branch (the &la, tx_power call followed by mt7915_update_txpower). ---
MCU_ANCHOR = "\t\t\t\t\t\t      &la, tx_power);\n\t\tmt7915_update_txpower(phy, tx_power);\n"
MCU_INSERT = (
"\t\t{\n"
"\t\t\t/* CR6608-RF-38DBM-LINEAR: raise per-rate SKU ceiling (0.5 dBm units): */\n"
"\t\t\t/* cck/ofdm -> 76 (38.0 dBm), mcs -> 72 (36.0 dBm), ru -> 68 (34.0 dBm). */\n"
"\t\t\t/* Request ceiling only; real radiated power stays PA/hardware limited. */\n"
"\t\t\tint _i, _j;\n"
"\t\t\tfor (_i = 0; _i < (int)sizeof(la.cck); _i++)\n"
"\t\t\t\tif (la.cck[_i] < 76) la.cck[_i] = 76;\n"
"\t\t\tfor (_i = 0; _i < (int)sizeof(la.ofdm); _i++)\n"
"\t\t\t\tif (la.ofdm[_i] < 76) la.ofdm[_i] = 76;\n"
"\t\t\tfor (_i = 0; _i < (int)(sizeof(la.mcs) / sizeof(la.mcs[0])); _i++)\n"
"\t\t\t\tfor (_j = 0; _j < (int)sizeof(la.mcs[0]); _j++)\n"
"\t\t\t\t\tif (la.mcs[_i][_j] < 72) la.mcs[_i][_j] = 72;\n"
"\t\t\tfor (_i = 0; _i < (int)(sizeof(la.ru) / sizeof(la.ru[0])); _i++)\n"
"\t\t\t\tfor (_j = 0; _j < (int)sizeof(la.ru[0]); _j++)\n"
"\t\t\t\t\tif (la.ru[_i][_j] < 68) la.ru[_i][_j] = 68;\n"
"\t\t\tfor (_i = 0; _i < (int)sizeof(la.path.cck); _i++)\n"
"\t\t\t\tif (la.path.cck[_i] < 76) la.path.cck[_i] = 76;\n"
"\t\t\tfor (_i = 0; _i < (int)sizeof(la.path.ofdm); _i++)\n"
"\t\t\t\tif (la.path.ofdm[_i] < 76) la.path.ofdm[_i] = 76;\n"
"\t\t\tfor (_i = 0; _i < (int)(sizeof(la.path.ru) / sizeof(la.path.ru[0])); _i++)\n"
"\t\t\t\tfor (_j = 0; _j < (int)sizeof(la.path.ru[0]); _j++)\n"
"\t\t\t\t\tif (la.path.ru[_i][_j] < 68) la.path.ru[_i][_j] = 68;\n"
"\t\t}\n"
)
apply("mt7915/mcu.c", MCU_ANCHOR, MCU_INSERT, "SKU-power-raise-76/72/68")

# --- mt7915/init.c : (a) driver banner printed once (2.4G pass), (b) force per-channel
#     max_power/max_reg_power to at least 38 dBm so iw/iwinfo report the 38 request. ---
# (a) file-scope banner string forced into the .ko with __attribute__((used)) so it can
#     NEVER be optimized/section-GC'd out — this is what `strings mt7915e.ko` must find.
GLOBAL_ANCHOR = "static void __mt7915_init_txpower(struct mt7915_phy *phy,\n"
GLOBAL_INSERT = (
"/* CR6608: file-scope banner forced into the .ko (__used => never GC'd). This is\n"
" * what `strings -a mt7915e.ko` must find to prove the 38 dBm driver is compiled in. */\n"
"const char cr6608_rf_38dbm_banner[] __attribute__((used)) =\n"
"\t\"CR6608-RF-38DBM-LINEAR enabled\";\n\n"
)
# insert the global BEFORE the function (prepend: put global then the original anchor)
def prepend(relpath, anchor, insert, tag):
    import os as _os
    p = _os.path.join(MT76, relpath)
    s = open(p).read()
    if s.count(anchor) != 1:
        sys.stderr.write("FATAL: prepend anchor %r count %d in %s\n" % (tag, s.count(anchor), relpath)); sys.exit(3)
    s = s.replace(anchor, insert + anchor, 1)
    open(p, "w").write(s)
    print("OK: prepended %s in %s" % (tag, relpath))
prepend("mt7915/init.c", GLOBAL_ANCHOR, GLOBAL_INSERT, "banner-global-__used")

# (b) runtime dmesg print that references the retained global (so dmesg shows the banner
#     AND the reference keeps the global alive on every toolchain).
INIT_BANNER_ANCHOR = "\tphy->sku_path_en = true;\n"
INIT_BANNER_INSERT = (
"\tif (sband->band == NL80211_BAND_2GHZ)\n"
"\t\tdev_info(dev->mt76.dev, \"%s (SKU cck/ofdm=76 mcs=72 ru=68 half-dBm; \"\n"
"\t\t\t \"request ceiling only, actual RF hardware/PA limited)\\n\",\n"
"\t\t\t cr6608_rf_38dbm_banner);\n"
)
apply("mt7915/init.c", INIT_BANNER_ANCHOR, INIT_BANNER_INSERT, "driver-banner")

INIT_MAXPWR_ANCHOR = "\t\tchan->orig_mpwr = target_power;\n"
INIT_MAXPWR_INSERT = (
"\t\t/* CR6608: request up to 38 dBm at the per-channel ceiling (whole dBm). */\n"
"\t\tif (chan->max_reg_power < 38) chan->max_reg_power = 38;\n"
"\t\tif (chan->max_power < 38) chan->max_power = 38;\n"
)
apply("mt7915/init.c", INIT_MAXPWR_ANCHOR, INIT_MAXPWR_INSERT, "chan-max_power->38")

print("CR6608 mt76 38dBm patch applied successfully.")
