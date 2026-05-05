requires 'perl', '5.38.0';

# Explicit core-module dependency record for this skill.
requires 'Exporter';
requires 'File::Spec';
requires 'JSON::PP';
requires 'POSIX';

# Skill-local modules used by the implementation:
# - SystemStatus::Util
# - SystemStatus::Disk
# - SystemStatus::Load
# - SystemStatus::Temperature
