# 2026-05-05 macOS Temperature Probe Fix

- retried macOS `powermetrics` with supported sampler combinations instead of assuming `--samplers smc` always works
- kept `iStats` fallback support and added common Homebrew install paths
- suppressed noisy optional-backend failures so missing tools do not leak raw `Can't exec ...` lines into command output
