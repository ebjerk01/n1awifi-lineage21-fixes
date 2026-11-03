#!/usr/bin/env bash
# Removes the IR fix and the tuning script. The original policy is restored from the copy
# install.sh left in /data/local/tmp (or reflash the ROM if that copy is gone).
set -euo pipefail
S() { adb shell "$@" </dev/null; }
adb root >/dev/null </dev/null; sleep 3; adb wait-for-device
S 'mount -o rw,remount / 2>/dev/null || mount -o rw,remount /system'
S 'rm -f /vendor/etc/permissions/android.hardware.consumerir.xml /vendor/bin/hw/android.hardware.ir-service.example \
     /vendor/etc/init/android.hardware.ir-service.example.rc /vendor/etc/vintf/manifest/android.hardware.ir-service.example.xml'
S '[ -s /data/local/tmp/precompiled_sepolicy.orig ] && cp /data/local/tmp/precompiled_sepolicy.orig /vendor/etc/selinux/precompiled_sepolicy && restorecon /vendor/etc/selinux/precompiled_sepolicy; sync'
S su -c "'rm -f /data/adb/service.d/99-n1awifi-tune.sh'" || true
adb reboot </dev/null
