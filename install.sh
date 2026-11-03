#!/usr/bin/env bash
# Installs the IR fix on a Galaxy Note 10.1 2014 (SM-P600, n1awifi) running LineageOS 21.
# Needs: adb, "Rooted debugging" on in Developer options, a backup of the tablet.
#   ./install.sh            use the prebuilt files (only for lineage-21.0-20261006)
#   ./install.sh --built    use ir-hal/out and sepolicy/out from build.sh / rebuild.sh
#   ./install.sh --tuning   also install the performance script (needs Magisk)
set -euo pipefail
cd "$(dirname "$0")"
HAL=prebuilt/android.hardware.ir-service.example POL=prebuilt/precompiled_sepolicy CIL="" TUNE=0
for a in "$@"; do case $a in
  --built) HAL=ir-hal/out/android.hardware.ir-service.example POL=sepolicy/out/precompiled_sepolicy CIL=sepolicy/out/vendor_sepolicy.cil ;;
  --tuning) TUNE=1 ;;
  *) echo "unknown option $a"; exit 2 ;;
esac; done

A() { adb "$@" </dev/null; }
S() { adb shell "$@" </dev/null; }
wait_boot() {
  adb wait-for-device
  until [[ $(S getprop sys.boot_completed | tr -d '\r') == 1 ]]; do sleep 3; done
  A root >/dev/null; sleep 3; adb wait-for-device
}

A root >/dev/null; sleep 3; adb wait-for-device
DEV=$(S getprop ro.lineage.device | tr -d '\r'); VER=$(S getprop ro.lineage.version | tr -d '\r')
[[ $DEV == n1awifi ]] || { echo "not an n1awifi ($DEV)"; exit 1; }
if [[ $POL == prebuilt/* && $VER != 21.0-20261006-UNOFFICIAL-n1awifi ]]; then
  echo "prebuilt policy is for 21.0-20261006 only, this is $VER: run sepolicy/rebuild.sh and use --built"; exit 1
fi

echo "stage 1: HAL, VINTF fragment, policy"
S 'mount -o rw,remount / 2>/dev/null || mount -o rw,remount /system'
A push "$HAL" /vendor/bin/hw/android.hardware.ir-service.example >/dev/null
A push ir-hal/etc/android.hardware.ir-service.example.rc /vendor/etc/init/ >/dev/null
A push ir-hal/etc/android.hardware.ir-service.example.xml /vendor/etc/vintf/manifest/ >/dev/null
S cp /vendor/etc/selinux/precompiled_sepolicy /data/local/tmp/precompiled_sepolicy.orig
A push "$POL" /vendor/etc/selinux/precompiled_sepolicy >/dev/null
[[ -n $CIL ]] && A push "$CIL" /vendor/etc/selinux/vendor_sepolicy.cil >/dev/null
S 'cd /vendor && chown root:shell bin/hw/android.hardware.ir-service.example && chmod 755 bin/hw/android.hardware.ir-service.example &&
   chmod 644 etc/init/android.hardware.ir-service.example.rc etc/vintf/manifest/android.hardware.ir-service.example.xml etc/selinux/* &&
   restorecon bin/hw/android.hardware.ir-service.example etc/init/android.hardware.ir-service.example.rc etc/vintf/manifest/android.hardware.ir-service.example.xml etc/selinux/* && sync'
A reboot; sleep 10; wait_boot
if ! S service check android.hardware.ir.IConsumerIr/default | grep -q found; then
  echo "IR HAL did not register; NOT adding the feature flag. Check: adb logcat -s ir-n1awifi, dmesg | grep avc"; exit 1
fi

# The feature flag only goes in once the HAL works: with the flag but no HAL, system_server crashes at boot.
echo "stage 2: consumerir feature"
S 'mount -o rw,remount / 2>/dev/null || mount -o rw,remount /system'
A push ir-hal/etc/android.hardware.consumerir.xml /vendor/etc/permissions/ >/dev/null
S 'chmod 644 /vendor/etc/permissions/android.hardware.consumerir.xml && restorecon /vendor/etc/permissions/android.hardware.consumerir.xml && sync'

if [[ $TUNE == 1 ]]; then
  A push tuning/99-n1awifi-tune.sh /data/local/tmp/ >/dev/null
  S su -c "'cp /data/local/tmp/99-n1awifi-tune.sh /data/adb/service.d/ && chmod 755 /data/adb/service.d/99-n1awifi-tune.sh'"
fi
A reboot; sleep 10; wait_boot
S pm list features | grep -q consumerir && echo "done: android.hardware.consumerir is present"
