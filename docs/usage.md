# Usage

## Disk

Linux or macOS path:

```bash
dashboard system-status.disk /
```

Linux block device:

```bash
dashboard system-status.disk /dev/sda
```

Windows drive:

```bash
dashboard system-status.disk c:
```

## Load

CPU:

```bash
dashboard system-status.load cpu
```

GPU:

```bash
dashboard system-status.load gpu
```

RAM:

```bash
dashboard system-status.load ram
```

Swap:

```bash
dashboard system-status.load swap
```

Combined memory:

```bash
dashboard system-status.load memory
```

Explicit output unit:

```bash
dashboard system-status.load --unit GB memory
```

## Temperature

CPU:

```bash
dashboard system-status.temperature cpu
```

GPU:

```bash
dashboard system-status.temperature gpu
```

## Error Cases

The skill returns JSON errors on `stderr` and a nonzero exit when:

- a required argument is missing
- the operating system path is invalid for the command
- the needed disk, load, or sensor backend is not available
- the host exposes no usable metric for the requested check
