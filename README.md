# system-status

## Description

`system-status` is a Developer Dashboard skill that exposes three CLI probes:

- `dashboard system-status.disk`
- `dashboard system-status.load`
- `dashboard system-status.temperature`

It gives the user a small, scriptable status surface for storage, load, and temperature checks across Linux, macOS, and Windows.

## Value

This skill gives the user quick operational answers without leaving DD:

- how full a filesystem or drive is
- how busy CPU, GPU, RAM, swap, or combined memory are
- what CPU or GPU temperature the system currently reports

## Problem It Solves

Developers and operators often want a lightweight status probe they can call directly from the same DD environment they already use for other workflow automation. Raw ad-hoc shell snippets are easy to lose, inconsistent across operating systems, and awkward to document or share.

## What It Does To Solve It

`system-status` standardizes the reference scripts into a DD skill with stable JSON output, cross-platform code paths, tests, docs, and release records.

- `disk` reports total, used, and available capacity
- `load` reports CPU load, GPU load, or memory availability
- `temperature` reports CPU or GPU temperature when the host exposes a supported sensor path

## Developer Dashboard Feature Added

This skill adds:

- `dashboard system-status.disk <path-or-drive>`
- `dashboard system-status.load [--unit UNIT] cpu|gpu|ram|swap|memory`
- `dashboard system-status.temperature cpu|gpu`

## Layout

- `cli/disk`
- `cli/load`
- `cli/temperature`
- `lib/SystemStatus/`
- `docs/`
- `t/`
- `tickets/`

## Installation

Install from a git source:

```bash
dashboard skills install git@github.mf:manif3station/system-status.git
```

Install from a local checkout during development:

```bash
dashboard skills install ~/projects/skills/skills/system-status
```

## License

`system-status` is released under the MIT License.

See [LICENSE](LICENSE).

## How To Use

Check the filesystem that contains the current root mount:

```bash
dashboard system-status.disk /
```

Check a Windows drive:

```bash
dashboard system-status.disk c:
```

Check CPU load:

```bash
dashboard system-status.load cpu
```

Check RAM in gigabytes:

```bash
dashboard system-status.load --unit GB ram
```

Check combined RAM and swap:

```bash
dashboard system-status.load memory
```

Check CPU temperature:

```bash
dashboard system-status.temperature cpu
```

Check GPU temperature:

```bash
dashboard system-status.temperature gpu
```

## Collector Example

You can wire these commands into your root DD collector config so the values show up in prompt indicators. Add entries to `~/.developer-dashboard/config/config.json` yourself.

Example:

```json
{
  "collectors": [
    {
      "command": "dashboard system-status.load memory",
      "cwd": "home",
      "indicator": {
        "icon": "[% memory.free.2 %] RAM"
      },
      "interval": 5,
      "name": "memory-free",
      "rotation": {
        "lines": 10
      }
    },
    {
      "command": "dashboard system-status.load cpu",
      "cwd": "home",
      "indicator": {
        "icon": "[% cpu.load %] CPU"
      },
      "interval": 5,
      "name": "cpu-load",
      "rotation": {
        "lines": 10
      }
    },
    {
      "command": "dashboard system-status.temperature cpu",
      "cwd": "home",
      "indicator": {
        "icon": "[% cpu.temperature.celsius.0 %]°C TEMP"
      },
      "interval": 5,
      "name": "cpu-temp",
      "rotation": {
        "lines": 10
      }
    }
  ]
}
```

The important part is that the indicator paths match the proven JSON payload:

- `memory.free.2` points at the percentage string from `dashboard system-status.load memory`
- `cpu.load` points at the CPU load string from `dashboard system-status.load cpu`
- `cpu.temperature.celsius.0` points at the numeric Celsius value from `dashboard system-status.temperature cpu`

## Practical Examples

Normal case, inspect Linux or macOS root disk usage:

```bash
dashboard system-status.disk /
```

Normal case, inspect a mounted Linux block device by device path:

```bash
dashboard system-status.disk /dev/sda
```

Normal case, inspect memory in megabytes:

```bash
dashboard system-status.load --unit MB memory
```

Normal case, inspect GPU load on a system with `nvidia-smi`:

```bash
dashboard system-status.load gpu
```

Normal case, inspect CPU temperature on Linux:

```bash
dashboard system-status.temperature cpu
```

Normal case, inspect CPU temperature on macOS when `osx-cpu-temp`, `powermetrics`, or `iStats` is available:

```bash
dashboard system-status.temperature cpu
```

## Edge Cases

- if `disk` is called without a path or drive, it exits with a JSON usage error
- if a Linux `/dev/...` target has no mounted filesystem, `disk` explains that the user should pick a mounted partition or mount path
- if Windows disk checks are given a non-drive argument, `disk` explains that a drive such as `c:` is required
- if GPU load tooling is missing, `load gpu` returns a JSON error that explains which backend is missing
- if CPU or GPU temperature is not exposed by the host, `temperature` returns a JSON error instead of fake data
- on macOS, GPU load and GPU temperature may require vendor-specific tooling and are not guaranteed by the operating system itself
- on Windows, some temperature checks depend on system-exposed sensors or third-party monitor providers

## Supported Platforms

- Linux
- macOS
- Windows

Support means the skill has explicit platform-aware code paths and automated tests for those branches. Some sensor-heavy checks still depend on what the host exposes.
For this release, Linux runtime proof was completed through the real `dashboard` entrypoint. `macdev` and `windev` were down during the release gate, so macOS and Windows were covered by automated platform-branch tests rather than live host runs.

On macOS, `dashboard system-status.temperature cpu` now tries `osx-cpu-temp` first, then retries `powermetrics` with supported sampler combinations, and finally falls back to `iStats` if it is installed. Bogus `0°C` readings from `osx-cpu-temp` are rejected and do not count as a valid CPU temperature. If none of those backends is available, the command returns a clean JSON error instead of leaking raw tool-launch noise.

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-05-05-initial-release.md`
