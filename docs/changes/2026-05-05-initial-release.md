# 2026-05-05 Initial Release

- packaged the existing `disk`, `load`, and `temperature` scripts as a DD skill
- split the logic into `SystemStatus::Disk`, `SystemStatus::Load`, and `SystemStatus::Temperature`
- added shared utility helpers in `SystemStatus::Util`
- kept JSON-style command output
- documented Linux, macOS, and Windows support
- added Docker-tested coverage and release records
