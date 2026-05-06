# TESTING

## DD-072

Docker functional proof:

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test \
  bash -lc 'cd /workspace/skills/system-status && prove -lvr t'
```

Result:

- pass
- `Files=6, Tests=139`

Docker coverage proof:

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test \
  bash -lc 'cd /workspace/skills/system-status && rm -rf cover_db /workspace/cover_db/* && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lvr t && cover -report text'
```

Result:

- pass
- `lib/SystemStatus/Disk.pm` statement `100.0%`, subroutine `100.0%`
- `lib/SystemStatus/Load.pm` statement `100.0%`, subroutine `100.0%`
- `lib/SystemStatus/Temperature.pm` statement `100.0%`, subroutine `100.0%`
- `lib/SystemStatus/Util.pm` statement `100.0%`, subroutine `100.0%`

Installed-path proof:

```bash
dashboard skills install ~/projects/skills/skills/system-status
dashboard system-status.disk /
dashboard system-status.load cpu
dashboard system-status.load memory
dashboard system-status.temperature cpu
```

Observed results:

- `dashboard skills install ~/projects/skills/skills/system-status`
  - `system-status  /home/mv/projects/skills/skills/system-status  0.01  0.01  no update`
- `dashboard system-status.disk /`
  - returned disk JSON with `total`, `used`, and `available`
- `dashboard system-status.load cpu`
  - returned `{"cpu":{"load":"77.9%"}}`
- `dashboard system-status.load memory`
  - returned `{"memory":{"total":[39.4,"GB","100%"],"free":[21.1,"GB","53.55%"]}}`
- `dashboard system-status.temperature cpu`
  - returned `{"cpu":{"temperature":{"celsius":[63,"°C"],"fahrenheit":[145.4,"°F"]}}}`

Platform note:

- live Linux installed-path proof was completed
- `macdev` and `windev` were down during the release gate, so macOS and Windows validation relied on automated branch coverage inside `t/`

2026-05-05 maintenance fix:

- reran `t/03-temperature.t` locally after the macOS probe fix
- macOS automated proof now covers:
  - direct `powermetrics` success
  - retry after `smc` sampler rejection into a supported `powermetrics` sampler set
  - `iStats` fallback
  - quiet failure when no backend exists

2026-05-05 quiet subprocess fix:

- reran `t/02-load.t` and `t/03-temperature.t` after changing the quiet probe runner
- direct helper proof now shows `capture_command(quiet => 1, ...)` keeps stdout and discards child stderr
- full Docker re-run completed for the patch version

2026-05-05 macOS Homebrew backend:

- `t/03-temperature.t` now proves macOS CPU temperature selection in this order:
  - `osx-cpu-temp`
  - `powermetrics`
  - `iStats`
- the temperature payload examples now use `°C` and `°F`
- `brewfile` now declares `osx-cpu-temp`
- full Docker suite passed after the backend-order update: `Files=6, Tests=145`

2026-05-05 degree-unit payload update:

- `t/03-temperature.t` now proves `°C` and `°F` in the emitted temperature payload
- full Docker suite passed after the payload update: `Files=6, Tests=146`

2026-05-05 macOS host proof on `macdev`:

- `osx-cpu-temp` is installed and currently returns `0.0°C` on that host
- copied proof tree command:
  - `cd /tmp/system-status-proof && perl cli/temperature cpu`
- observed result:
  - `{"error":"CPU temperature is not available on macOS unless osx-cpu-temp, powermetrics, or a compatible sensor tool is available."}`

2026-05-06 MIT license gate:

- functional proof:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/system-status && prove -lvr t'`
  - Result: pass
- coverage proof:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/system-status && rm -rf cover_db /workspace/cover_db/* && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lvr t && cover -report text'`
  - Result: pass
  - `lib/SystemStatus/Disk.pm` statement `100.0%`, subroutine `100.0%`
  - `lib/SystemStatus/Load.pm` statement `100.0%`, subroutine `100.0%`
  - `lib/SystemStatus/Temperature.pm` statement `100.0%`, subroutine `100.0%`
  - `lib/SystemStatus/Util.pm` statement `100.0%`, subroutine `100.0%`
- this proves the skill rejects the bogus `0.0°C` reading instead of returning fake success
- real DD proof through `~/.zshrc`-loaded shell:
  - `dashboard skills install /tmp/system-status`
  - `dashboard system-status.temperature cpu`
- observed result:
  - `{"error":"CPU temperature is not available on macOS unless osx-cpu-temp, powermetrics, or a compatible sensor tool is available."}`
