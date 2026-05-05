# 2026-05-05 macOS osx-cpu-temp Backend

- added `osx-cpu-temp` to the skill `brewfile`
- changed the macOS CPU temperature probe order to try `osx-cpu-temp` before `powermetrics` and `iStats`
- this gives macOS users a non-privileged Homebrew path for `dashboard system-status.temperature cpu`
