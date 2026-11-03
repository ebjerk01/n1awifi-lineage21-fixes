#!/system/bin/sh
# Performance tuning for the Galaxy Note 10.1 2014 (n1awifi) on LineageOS 21. Runs at boot from Magisk service.d; delete it to undo.
sleep 30
for c in 0 1 2 3; do echo interactive > /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor 2>/dev/null; done
I=/sys/devices/system/cpu/cpufreq/interactive
[ -d $I ] && {
  echo 1300000 > $I/hispeed_freq
  echo 85      > $I/go_hispeed_load
  echo 20000   > $I/timer_rate
  echo 40000   > $I/min_sample_time
  echo 20000   > $I/above_hispeed_delay
  echo 1       > $I/boost 2>/dev/null; echo 0 > $I/boost 2>/dev/null
  echo 80000   > $I/boostpulse_duration 2>/dev/null
  echo 1       > $I/io_is_busy 2>/dev/null
}
for q in /sys/block/mmcblk0/queue /sys/block/mmcblk1/queue; do
  [ -d $q ] && { echo deadline > $q/scheduler; echo 512 > $q/read_ahead_kb; }
done
