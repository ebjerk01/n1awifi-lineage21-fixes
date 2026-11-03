#!/usr/bin/env bash
# Builds the IR HAL (android.hardware.ir AIDL V1) for armeabi-v7a.
# Needs: curl, unzip, a connected tablet over adb (to link against its libbinder_ndk.so).
# Output: ir-hal/out/android.hardware.ir-service.example
set -euo pipefail
cd "$(dirname "$0")"
T=${TOOLS:-$PWD/.tools}
mkdir -p "$T" out gen plat/android lib

NDK=$T/android-ndk-r27c
if [[ ! -d $NDK ]]; then
  curl -fsSL -o "$T/ndk.zip" https://dl.google.com/android/repository/android-ndk-r27c-linux.zip
  unzip -q "$T/ndk.zip" -d "$T" && rm "$T/ndk.zip"
fi
AIDL=$T/android-14/aidl
if [[ ! -x $AIDL ]]; then
  curl -fsSL -o "$T/bt.zip" https://dl.google.com/android/repository/build-tools_r34-linux.zip
  unzip -q "$T/bt.zip" -d "$T" && rm "$T/bt.zip"
fi

# Platform-only binder headers (service manager, process, stability) are not in the NDK.
B=https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-14.0.0_r1/libs/binder/ndk/include_platform/android
for h in binder_manager.h binder_process.h binder_stability.h; do
  [[ -s plat/android/$h ]] || curl -fsSL "$B/$h?format=TEXT" | base64 -d > "plat/android/$h"
done

# Link against the device's own libbinder_ndk (it exports the LLNDK symbols the NDK stub lacks).
[[ -s lib/libbinder_ndk.so ]] || adb pull /system/lib/libbinder_ndk.so lib/libbinder_ndk.so

"$AIDL" --lang=ndk --stability=vintf --structured --version=1 \
  --hash=3e04aed366e96850c6164287eaf78a8e4ab071b0 -I aidl -o gen -h gen/include \
  aidl/android/hardware/ir/IConsumerIr.aidl aidl/android/hardware/ir/ConsumerIrFreqRange.aidl

"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi34-clang++" \
  -O2 -std=c++17 -Wall -Igen/include -Iplat -static-libstdc++ \
  -ffile-prefix-map="$(readlink -f "$NDK")"=ndk -ffile-prefix-map="$NDK"=ndk -ffile-prefix-map="$PWD"=. \
  src/service.cpp gen/android/hardware/ir/*.cpp -Llib -lbinder_ndk -llog \
  -Wl,--gc-sections -s -o out/android.hardware.ir-service.example
echo "built ir-hal/out/android.hardware.ir-service.example"
