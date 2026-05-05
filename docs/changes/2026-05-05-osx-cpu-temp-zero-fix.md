# 2026-05-05 osx-cpu-temp Zero Reading Fix

- rejected `0°C` readings from the macOS `osx-cpu-temp` backend as invalid CPU temperatures
- when that bogus reading appears, the skill now falls through to `powermetrics` or `iStats` instead of returning a fake success payload
- temperature output examples and payload labels now use `°C` and `°F`
