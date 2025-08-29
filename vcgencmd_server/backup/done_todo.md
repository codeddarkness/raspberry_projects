# TODO

#1# make system status objects confined to 2x4 rows instead of 7 over 1

Temperature Clock Speed Voltage Throttled Uptime CPU Load Memory
88.9°C  1000 MHz 0.7500 V YES -- --% --%
Load Avg
--

Temperature Clock Speed Voltage     Throttled
88.9°C      1000 MHz    0.7500 V    YES
Uptime CPU Load Memory Load Avg
--      --%     --%       --

#2# verify the uptime, cpu, memory and load stats are showing up/active, currently shows nothing

#3# warning should only appear when user attempts to go over system defaults/thresolds
⚠️ Overclocking can damage your Pi. Ensure adequate cooling.

#4# add the system stats data to the results file /snapshots for historical comparison of system activity to temps/clock/voltage/throttled data

#5# unable to apply the overclock settings
2025-08-27 06:05:07 - Applying overclock: CPU=2200MHz, GPU=700MHz, Voltage=0μV
2025-08-27 06:05:07 - Error applying overclock settings: [Errno 13] Permission denied: '/boot/firmware/config.txt.tmp'
