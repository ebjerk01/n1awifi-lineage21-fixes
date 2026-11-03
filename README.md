# n1awifi-lineage21-fixes

Fixes for the **Samsung Galaxy Note 10.1 2014 Edition, Wi-Fi (SM-P600, codename n1awifi)** running the unofficial
LineageOS 21 (Android 14) build by retiredtab:

1. **The IR blaster works again.** IR remote apps can now use it through the normal Android API (`ConsumerIrManager`).
2. **Performance tuning** for a smoother UI.

Tested on `lineage-21.0-20261006-UNOFFICIAL-n1awifi` (userdebug, SELinux enforcing, Magisk installed).

## ROM image

| | |
|---|---|
| Download (SourceForge, retiredtab) | https://sourceforge.net/projects/retiredtab/files/SM-P600/21/ |
| Build these fixes were made on | [lineage-21.0-20261006-UNOFFICIAL-n1awifi.zip](https://sourceforge.net/projects/retiredtab/files/SM-P600/21/lineage-21.0-20261006-UNOFFICIAL-n1awifi.zip/download) (681.7 MB, `.sha256sum` next to it) |
| XDA thread (install steps, known issues) | https://xdaforums.com/t/unofficial-rom-alpha-lineageos-21-for-sm-p600-oct-6-2026.4702764/ |

Only for the SM-P600. The SM-P601 and SM-P605 are different devices. Back up before flashing.

## Fix 1: IR blaster

### What was wrong
The hardware and kernel driver work fine. The IR LED is driven by an iCE40 FPGA ("barcode emulator"), and the kernel loads its firmware at
boot and exposes `/sys/class/sec/sec_ir/ir_send`. The ROM is missing the whole Android side:

- **No IR HAL.** Nothing provides `android.hardware.ir.IConsumerIr`.
- **No `android.hardware.consumerir` feature flag.** Apps conclude the tablet has no IR emitter.
- **SELinux blocks the write.** The IR HAL domain (`hal_ir_default`) may not write the generic `sysfs` label that `ir_send` has.

### What this adds
| File on the tablet | What it is |
|---|---|
| `/vendor/bin/hw/android.hardware.ir-service.example` | Small AIDL IR HAL (`ir-hal/src/service.cpp`). It turns Android's microsecond pattern into the driver's `carrier,cycles,cycles,...` format. The ROM's file_contexts already label this path `hal_ir_default_exec`. |
| `/vendor/etc/init/android.hardware.ir-service.example.rc` | Starts it as `system`, group `radio` (the owner of `ir_send`). |
| `/vendor/etc/vintf/manifest/android.hardware.ir-service.example.xml` | Declares `android.hardware.ir` V1 so servicemanager accepts it. |
| `/vendor/etc/permissions/android.hardware.consumerir.xml` | The feature flag. |
| `/vendor/etc/selinux/precompiled_sepolicy` | The ROM's own policy, rebuilt with **one** extra rule (`sepolicy/ir.cil`): `allow hal_ir_default sysfs:file { open write getattr }`. |

Verified: the service runs in `hal_ir_default` with SELinux enforcing, the framework reports an emitter at 30–60 kHz, and a
68-value NEC frame reaches the driver whole and lasts the expected ~70 ms.

### Install
Requirements:
- adb on your computer.
- *Developer options → Rooted debugging* turned on.
- A backup of the tablet.

```bash
./install.sh             # prebuilt files, only for the 20261006 build
./install.sh --tuning    # also install the performance script (needs Magisk)
```

The script installs in two stages with a reboot after each. The feature flag goes in only once the HAL is confirmed running,
because with the flag but no working HAL, `system_server` crashes at boot.

**Other LineageOS 21 builds:** build from source, then install the built files:

```bash
ir-hal/build.sh                     # downloads NDK r27c + aidl, links against the tablet's libbinder_ndk.so
sepolicy/rebuild.sh                 # needs secilc; rebuilds the tablet's own policy + ir.cil and diffs the rules
./install.sh --built
```

`./uninstall.sh` removes everything and restores the original policy.

### Notes
- **Updating or reflashing the ROM removes the fix**, because `/vendor` lives on the system partition. Run `install.sh` again afterwards.
- The kernel logs `Checksum NG!` and `ir_send_result` stays `0` on every send. It does that even when the LED fires, so ignore it.
- On a phone camera one button press is a single faint ~70 ms flash. The LED's power is set by hardware and can't be changed in software.
- Apps that use it (F-Droid): IR Blaster Remote, Nope Remote, IR Remote.
- adb on this kernel: use `adb install --no-streaming` (streamed installs fail with `splice failed: EINVAL`).

## Fix 2: performance

The Exynos 5420 (big.LITTLE with in-kernel switching, 4 logical CPUs, 3 GB RAM) is slow on Android 14. What helped:

| Change | How |
|---|---|
| Compile every app to native code. Out of the box about 120 apps ran uncompiled (`verify`/`error`/`unknown`), including parts of the system UI. | `adb shell su -c "cmd package compile -m speed -f -a"` (one-off, about 12 min, uses about 1 GB on /data; a few system apps report Failure, which is harmless) |
| CPU governor `interactive` instead of `ondemand`: ramps on touch, hispeed 1.3 GHz at 85 % load, 20 ms timer | `tuning/99-n1awifi-tune.sh` in `/data/adb/service.d/` (Magisk, runs every boot) |
| eMMC I/O scheduler `deadline`, read-ahead 512 KB | same script |
| Animations at 0.5× | `adb shell settings put global {window,transition}_animation_scale 0.5; adb shell settings put global animator_duration_scale 0.5` |
| **GPU floor 480 MHz.** The Mali-T628's default DVFS governor almost never leaves 100–177 MHz, because utilisation is under-reported. Its `Interactive` and `Booster` governors don't help either. | `echo 480 > /sys/devices/platform/mali.0/dvfs_min_lock` (in the tuning script; `echo 0` removes it). Costs battery and some heat. |
| Render at 1920×1200, density 240 (same layout, slightly softer text) | `adb shell wm size 1920x1200; adb shell wm density 240` (persists; undo with `wm size reset; wm density reset`) |

### Measured
Same test each time: 12 swipes opening/closing the app drawer, frames from `dumpsys gfxinfo com.android.launcher3`. More frames in the same
time means smoother.

| Setting | Frames | Median frame | 90th percentile |
|---|---|---|---|
| Stock (after app compilation and CPU governor) | 285 | 69 ms | 150 ms |
| 1920×1200 only | 304 | 57 ms | 101 ms |
| GPU floor 480 MHz only | 410 | 34 ms | 53 ms |
| GPU floor 600 MHz only | 425 | 32 ms | 46 ms |
| **GPU floor 480 MHz + 1920×1200 @ 240 dpi** | **441** | **27 ms** | **40 ms** |

## License
Apache-2.0. The AIDL files in `ir-hal/aidl` are from AOSP (Apache-2.0). `prebuilt/precompiled_sepolicy` is LineageOS's
policy for this build with the one added rule.
