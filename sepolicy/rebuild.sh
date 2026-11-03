#!/usr/bin/env bash
# Rebuilds /vendor/etc/selinux/precompiled_sepolicy from the tablet's own CIL files plus ir.cil.
# Needs: adb (root), secilc (Debian/Ubuntu package "secilc"), optionally setools (sesearch) to verify.
# Output: sepolicy/out/precompiled_sepolicy and sepolicy/out/vendor_sepolicy.cil
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out src
adb root >/dev/null; adb wait-for-device
V=$(adb shell cat /vendor/etc/selinux/plat_sepolicy_vers.txt | tr -d '\r')
pull() { adb pull "$1" "src/$2" >/dev/null; }
pull /system/etc/selinux/plat_sepolicy.cil plat.cil
pull /system/etc/selinux/mapping/$V.cil plat_mapping.cil
pull /system_ext/etc/selinux/system_ext_sepolicy.cil system_ext.cil
pull /system_ext/etc/selinux/mapping/$V.cil system_ext_mapping.cil
pull /vendor/etc/selinux/plat_pub_versioned.cil plat_pub_versioned.cil
pull /vendor/etc/selinux/vendor_sepolicy.cil vendor.cil
pull /vendor/etc/selinux/precompiled_sepolicy precompiled_sepolicy.orig

cp src/vendor.cil out/vendor_sepolicy.cil
grep -qF "$(cat ir.cil)" out/vendor_sepolicy.cil || sed "s/_202404/_$V/" ir.cil >> out/vendor_sepolicy.cil

PV=$(python3 -c "import struct,sys;d=open('src/precompiled_sepolicy.orig','rb').read();print(struct.unpack('<I',d[16:20])[0])")
secilc -m -M true -G -N -c "$PV" src/plat.cil src/plat_mapping.cil src/system_ext.cil src/system_ext_mapping.cil \
  src/plat_pub_versioned.cil out/vendor_sepolicy.cil -o out/precompiled_sepolicy -f /dev/null

# Android's libsepol sets two extra config flags (netlink route/getneigh); copy the original header word.
python3 - <<'EOF'
o = open('src/precompiled_sepolicy.orig', 'rb').read()
n = bytearray(open('out/precompiled_sepolicy', 'rb').read())
n[20:24] = o[20:24]
open('out/precompiled_sepolicy', 'wb').write(n)
EOF

if command -v sesearch >/dev/null; then
  echo "rule differences against the device policy (expect exactly the IR rule):"
  diff <(sesearch src/precompiled_sepolicy.orig -A | sort) <(sesearch out/precompiled_sepolicy -A | sort) || true
fi
