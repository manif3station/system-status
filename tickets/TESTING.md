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
  - returned `{"cpu":{"temperature":{"celsius":[63,"C"],"fahrenheit":[145.4,"F"]}}}`

Platform note:

- live Linux installed-path proof was completed
- `macdev` and `windev` were down during the release gate, so macOS and Windows validation relied on automated branch coverage inside `t/`
