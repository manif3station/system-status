# 2026-05-05 Quiet Probe STDERR Fix

- changed the quiet optional-probe runner to discard child `stderr` explicitly instead of letting backend tool noise leak into the terminal
- this keeps macOS temperature failures clean when `powermetrics` rejects a sampler or requires superuser access
