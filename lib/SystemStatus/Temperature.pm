package SystemStatus::Temperature;

use strict;
use warnings;

use JSON::PP qw(encode_json);
use SystemStatus::Util qw(capture_command fmt_num run_powershell);

sub main {
    my (@argv) = @_;
    my $result = run( argv => \@argv );
    print STDOUT $result->{stdout} if length $result->{stdout};
    print STDERR $result->{stderr} if length $result->{stderr};
    return $result->{exit};
}

sub run {
    my (%args) = @_;
    my $target = lc(($args{argv} || [])->[0] // q{});

    return success(usage())
        if $target eq '--help' || $target eq '-h';

    return failure('Usage: system-temperature cpu|gpu')
        unless ($target eq 'cpu' || $target eq 'gpu') && @{ $args{argv} || [] } == 1;

    my ($temp, $error) = $target eq 'cpu'
        ? cpu_temperature_c(%args)
        : gpu_temperature_c(%args);

    return defined $error
        ? failure($error)
        : success(print_temperature_result($target, $temp));
}

sub usage {
    return <<'TXT';
Usage:
  system-temperature cpu
  system-temperature gpu

Examples:
  {"cpu":{"temperature":{"celsius":[55,"C"],"fahrenheit":[131,"F"]}}}
  {"gpu":{"temperature":{"celsius":[62,"C"],"fahrenheit":[143.6,"F"]}}}
TXT
}

sub cpu_temperature_c {
    my (%args) = @_;
    my $os = $args{os} || $^O;

    if ($os =~ /MSWin32/i) {
        my ($temp, $err) = windows_cpu_temperature_c(%args);
        return ($temp, undef) if !defined $err;
        return (undef, 'CPU temperature is not available. On Windows, install LibreHardwareMonitor/OpenHardwareMonitor for reliable CPU sensor data, or use a system that exposes ACPI thermal zones.');
    }

    if ($os eq 'darwin') {
        my ($temp, $err) = macos_cpu_temperature_c(%args);
        return ($temp, undef) if !defined $err;
        return (undef, 'CPU temperature is not available on macOS unless powermetrics or a compatible sensor tool is available.');
    }

    for my $probe (\&linux_cpu_temperature_from_hwmon, \&linux_cpu_temperature_from_thermal_zone, \&linux_cpu_temperature_from_sensors) {
        my ($temp, $err) = $probe->(%args);
        return ($temp, undef) if !defined $err;
    }

    return (undef, 'CPU temperature is not available. On Linux, install lm-sensors or make sure /sys/class/hwmon or /sys/class/thermal exposes CPU temperature sensors.');
}

sub gpu_temperature_c {
    my (%args) = @_;

    my ($temp, $err) = gpu_temperature_from_nvidia_smi(%args);
    return ($temp, undef) if !defined $err;

    my $os = $args{os} || $^O;
    if ($os =~ /MSWin32/i) {
        ($temp, $err) = windows_gpu_temperature_c(%args);
        return ($temp, undef) if !defined $err;
        return (undef, 'GPU temperature is not available. NVIDIA GPUs usually work with nvidia-smi. Other Windows GPUs may need LibreHardwareMonitor/OpenHardwareMonitor sensor data.');
    }
    if ($os eq 'darwin') {
        return (undef, 'GPU temperature is not available on macOS unless a vendor-specific sensor tool is installed.');
    }

    for my $probe (\&linux_gpu_temperature_from_hwmon, \&linux_gpu_temperature_from_rocm_smi, \&linux_gpu_temperature_from_sensors) {
        ($temp, $err) = $probe->(%args);
        return ($temp, undef) if !defined $err;
    }

    return (undef, 'GPU temperature is not available. NVIDIA GPUs need nvidia-smi; AMD Linux GPUs often expose /sys/class/drm/card*/device/hwmon; ROCm systems may use rocm-smi.');
}

sub linux_cpu_temperature_from_hwmon {
    my (%args) = @_;
    my @values;

    for my $dir (glob_paths('/sys/class/hwmon/hwmon*', %args)) {
        my $name = read_first_line("$dir/name", %args) // q{};
        next unless $name =~ /(coretemp|k10temp|zenpower|cpu|x86_pkg_temp)/i;
        for my $file (glob_paths("$dir/temp*_input", %args)) {
            my $temp = read_temp_file_c($file, %args);
            push @values, $temp if defined $temp;
        }
    }

    my $temp = max_temp_c(@values);
    return defined $temp ? ($temp, undef) : (undef, 'hwmon cpu unavailable');
}

sub linux_cpu_temperature_from_thermal_zone {
    my (%args) = @_;
    my @values;
    for my $zone (glob_paths('/sys/class/thermal/thermal_zone*', %args)) {
        my $type = read_first_line("$zone/type", %args) // q{};
        next unless $type =~ /(cpu|x86_pkg_temp|soc)/i;
        my $temp = read_temp_file_c("$zone/temp", %args);
        push @values, $temp if defined $temp;
    }
    my $temp = max_temp_c(@values);
    return defined $temp ? ($temp, undef) : (undef, 'thermal zone cpu unavailable');
}

sub linux_cpu_temperature_from_sensors {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'sensors' ],
    );
    return (undef, 'sensors unavailable') if $rc != 0 || !defined $out;

    my @values;
    for my $line (split /\r?\n/, $out) {
        push @values, $2 if $line =~ /(Package|Core|Tctl|Tdie|CPU|CCD).*?([+-]?\d+(?:\.\d+)?)\s*°?C/i;
    }

    my $temp = max_temp_c(@values);
    return defined $temp ? ($temp, undef) : (undef, 'sensors cpu unavailable');
}

sub gpu_temperature_from_nvidia_smi {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'nvidia-smi', '--query-gpu=temperature.gpu', '--format=csv,noheader,nounits' ],
    );
    return (undef, 'nvidia-smi unavailable') if $rc != 0 || !defined $out;
    my @values;
    for my $line (split /\r?\n/, $out) {
        push @values, $1 if $line =~ /([+-]?\d+(?:\.\d+)?)/;
    }
    my $temp = max_temp_c(@values);
    return defined $temp ? ($temp, undef) : (undef, 'nvidia-smi parse failure');
}

sub linux_gpu_temperature_from_hwmon {
    my (%args) = @_;
    my %seen;
    my @values;
    my @dirs = (
        glob_paths('/sys/class/drm/card*/device/hwmon/hwmon*', %args),
        glob_paths('/sys/class/hwmon/hwmon*', %args),
    );
    for my $dir (@dirs) {
        next if $seen{$dir}++;
        my $name = read_first_line("$dir/name", %args) // q{};
        next unless $name =~ /(amdgpu|nouveau|nvidia|radeon|i915|gpu)/i;
        for my $file (glob_paths("$dir/temp*_input", %args)) {
            my $temp = read_temp_file_c($file, %args);
            push @values, $temp if defined $temp;
        }
    }
    my $temp = max_temp_c(@values);
    return defined $temp ? ($temp, undef) : (undef, 'hwmon gpu unavailable');
}

sub linux_gpu_temperature_from_rocm_smi {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'rocm-smi', '--showtemp' ],
    );
    return (undef, 'rocm-smi unavailable') if $rc != 0 || !defined $out;
    my @values;
    for my $line (split /\r?\n/, $out) {
        next unless $line =~ /temp/i;
        my @nums = $line =~ /([+-]?\d+(?:\.\d+)?)/g;
        push @values, $nums[-1] if @nums;
    }
    my $temp = max_temp_c(@values);
    return defined $temp ? ($temp, undef) : (undef, 'rocm-smi parse failure');
}

sub linux_gpu_temperature_from_sensors {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'sensors' ],
    );
    return (undef, 'sensors unavailable') if $rc != 0 || !defined $out;

    my (@values, $chip);
    for my $line (split /\r?\n/, $out) {
        if ($line =~ /^([A-Za-z0-9_.:-]+)\s*$/) {
            $chip = $1;
            next;
        }
        my $looks_gpu = ($chip || q{}) =~ /(amdgpu|nouveau|nvidia|radeon|i915|gpu)/i
                     || $line =~ /(GPU|edge|junction|hotspot|memory)/i;
        next unless $looks_gpu;
        push @values, $1 if $line =~ /([+-]?\d+(?:\.\d+)?)\s*°?C/;
    }

    my $temp = max_temp_c(@values);
    return defined $temp ? ($temp, undef) : (undef, 'sensors gpu unavailable');
}

sub windows_cpu_temperature_c {
    my (%args) = @_;
    my $out = run_powershell(
        capture => $args{capture},
        script  => q{
            $zones = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction SilentlyContinue
            if ($zones) {
                $temps = $zones | ForEach-Object { (($_.CurrentTemperature / 10) - 273.15) }
                if ($temps.Count -gt 0) { [Math]::Round((($temps | Measure-Object -Maximum).Maximum), 2); exit 0 }
            }
            exit 3
        },
    );
    return (undef, 'windows cpu unavailable')
        unless defined $out && $out =~ /([+-]?\d+(?:\.\d+)?)/;
    return ($1, undef);
}

sub windows_gpu_temperature_c {
    my (%args) = @_;
    my $out = run_powershell(
        capture => $args{capture},
        script  => q{
            $sensors = Get-CimInstance -Namespace root/LibreHardwareMonitor -ClassName Sensor -ErrorAction SilentlyContinue
            if ($sensors) {
                $temps = $sensors | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'GPU' } | Select-Object -ExpandProperty Value
                if ($temps.Count -gt 0) { [Math]::Round((($temps | Measure-Object -Maximum).Maximum), 2); exit 0 }
            }
            exit 3
        },
    );
    return (undef, 'windows gpu unavailable')
        unless defined $out && $out =~ /([+-]?\d+(?:\.\d+)?)/;
    return ($1, undef);
}

sub macos_cpu_temperature_c {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'powermetrics', '--samplers', 'smc', '-n', '1' ],
    );
    if ($rc == 0 && defined $out) {
        for my $line (split /\r?\n/, $out) {
            return ($1, undef) if $line =~ /CPU.*?([+-]?\d+(?:\.\d+)?)\s*C/i;
        }
    }

    ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'istats', 'cpu', 'temp', '--no-graphs' ],
    );
    if ($rc == 0 && defined $out) {
        return ($1, undef) if $out =~ /([+-]?\d+(?:\.\d+)?)\s*°?C/i;
    }

    return (undef, 'macos cpu unavailable');
}

sub read_temp_file_c {
    my ($path, %args) = @_;
    my $value = read_first_line($path, %args);
    return undef unless defined $value && $value =~ /([+-]?\d+(?:\.\d+)?)/;
    my $temp = $1;
    $temp /= 1000 if abs($temp) > 300;
    return valid_temp_c($temp) ? $temp : undef;
}

sub read_first_line {
    my ($path, %args) = @_;
    my $reader = $args{read_file} || \&default_read_file;
    my $content = $reader->($path);
    return undef unless defined $content;
    my ($line) = split /\r?\n/, $content;
    return $line;
}

sub max_temp_c {
    my @values = grep { defined && valid_temp_c($_) } @_;
    return undef unless @values;
    my $max = $values[0];
    for my $value (@values) {
        $max = $value if $value > $max;
    }
    return $max;
}

sub valid_temp_c {
    my ($temp) = @_;
    return defined $temp && $temp >= -40 && $temp <= 150;
}

sub print_temperature_result {
    my ($label, $temp_c) = @_;
    my $temp_f = ($temp_c * 9 / 5) + 32;
    return sprintf(
        '{"%s":{"temperature":{"celsius":[%s,"C"],"fahrenheit":[%s,"F"]}}}' . "\n",
        $label,
        fmt_num($temp_c),
        fmt_num($temp_f),
    );
}

sub default_read_file {
    my ($path) = @_;
    open my $fh, '<', $path or return undef;
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub glob_paths {
    my ($pattern, %args) = @_;
    if ($args{glob_paths}) {
        return $args{glob_paths}->($pattern);
    }
    return glob($pattern);
}

sub success {
    my ($stdout) = @_;
    return { exit => 0, stdout => $stdout, stderr => q{} };
}

sub failure {
    my ($msg) = @_;
    return { exit => 1, stdout => q{}, stderr => encode_json({ error => $msg }) . "\n" };
}

1;
