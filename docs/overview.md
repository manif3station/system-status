# Overview

`system-status` packages three host-inspection commands into a DD skill:

- `disk`
- `load`
- `temperature`

The commands keep the original JSON-first style from the reference scripts, but the implementation is now modular and testable.

## Command Summary

`dashboard system-status.disk`

- input: a filesystem path on Unix-like systems or a drive such as `c:` on Windows
- output: total, used, and available capacity in GB plus percentages

`dashboard system-status.load`

- input: `cpu`, `gpu`, `ram`, `swap`, or `memory`
- output: load percentage for CPU or GPU, or availability figures for RAM, swap, or combined memory

`dashboard system-status.temperature`

- input: `cpu` or `gpu`
- output: Celsius and Fahrenheit values when the host exposes a usable sensor source

## Platform Notes

Linux

- disk checks use `df` and optionally `lsblk` when the user passes `/dev/...`
- load checks use `/proc/stat`, `/proc/meminfo`, `top`, `nvidia-smi`, sysfs, or `rocm-smi`
- temperature checks use hwmon, thermal zones, `sensors`, `nvidia-smi`, or `rocm-smi`

macOS

- disk checks use `df`
- load checks use `top`, `sysctl`, and `vm_stat`
- CPU temperature can use `powermetrics` or `istats` when available
- GPU load and GPU temperature are limited by available vendor tooling

Windows

- disk checks use PowerShell drive information
- load checks use PowerShell and pagefile or processor counters
- temperature checks rely on exposed sensors, ACPI thermal zones, or compatible monitoring providers
