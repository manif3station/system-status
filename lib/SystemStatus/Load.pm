package SystemStatus::Load;

use strict;
use warnings;

use JSON::PP qw(encode_json);
use SystemStatus::Util qw(capture_command fmt_num run_powershell);

my @UNITS = qw(B KB MB GB TB PB EB ZB YB);
my %UNIT_POWER = map { $UNITS[$_] => $_ } 0 .. $#UNITS;

sub main {
    my (@argv) = @_;
    if (@argv && grep { $_ eq '--help' || $_ eq '-h' } @argv) {
        print STDOUT usage();
        return 0;
    }
    my $result = run( argv => \@argv );
    print STDOUT $result->{stdout} if length $result->{stdout};
    print STDERR $result->{stderr} if length $result->{stderr};
    return $result->{exit};
}

sub run {
    my (%args) = @_;
    my ($unit, $check, $error) = parse_args(@{ $args{argv} || [] });
    return success(usage()) if defined $unit && $unit eq 'HELP';
    return failure($error) if defined $error;

    my $os = defined $args{os} ? $args{os} : $^O;
    my $capture = $args{capture};
    my $read_file = $args{read_file} || \&default_read_file;

    if ($check eq 'cpu') {
        my ($load, $err) = cpu_load_percent(
            os        => $os,
            capture   => $capture,
            read_file => $read_file,
        );
        return defined $err ? failure($err) : success(print_load_result('cpu', $load));
    }

    if ($check eq 'gpu') {
        my ($load, $err) = gpu_load_percent(
            os         => $os,
            capture    => $capture,
            read_file  => $read_file,
            glob_paths => $args{glob_paths},
        );
        return defined $err ? failure($err) : success(print_load_result('gpu', $load));
    }

    if ($check eq 'ram') {
        my ($total, $free, $err) = ram_bytes(
            os        => $os,
            capture   => $capture,
            read_file => $read_file,
        );
        return defined $err ? failure($err) : success(print_memory_result('ram', $total, $free, $unit));
    }

    if ($check eq 'swap') {
        my ($total, $free, $err) = swap_bytes(
            os        => $os,
            capture   => $capture,
            read_file => $read_file,
        );
        return defined $err ? failure($err) : success(print_memory_result('swap', $total, $free, $unit));
    }

    my ($ram_total, $ram_free, $ram_err) = ram_bytes(
        os        => $os,
        capture   => $capture,
        read_file => $read_file,
    );
    return failure($ram_err) if defined $ram_err;

    my ($swap_total, $swap_free, $swap_err) = swap_bytes(
        os        => $os,
        capture   => $capture,
        read_file => $read_file,
    );
    return failure($swap_err) if defined $swap_err;

    return success(print_memory_result('memory', $ram_total + $swap_total, $ram_free + $swap_free, $unit));
}

sub parse_args {
    my @args = @_;
    my $unit = 'AUTO';
    my @positional;

    while (@args) {
        my $arg = shift @args;
        if ($arg =~ /^--unit=(.+)$/i) {
            my ($norm, $error) = normalize_unit($1);
            return (undef, undef, $error) if defined $error;
            $unit = $norm;
        } elsif ($arg =~ /^--unit$/i || $arg =~ /^-u$/i) {
            return (undef, undef, "Missing value after $arg") unless @args;
            my ($norm, $error) = normalize_unit(shift @args);
            return (undef, undef, $error) if defined $error;
            $unit = $norm;
        } elsif ($arg =~ /^--help$/i || $arg =~ /^-h$/i) {
            return ('HELP', undef, undef);
        } else {
            push @positional, lc $arg;
        }
    }

    return (undef, undef, 'Usage: system-check [--unit auto|KB|MB|GB|TB|PB|EB|ZB|YB] cpu|gpu|ram|swap|memory')
        unless @positional == 1;

    my $check = $positional[0];
    return (undef, undef, "Unknown check '$check'. Use cpu, gpu, ram, swap, or memory")
        unless grep { $_ eq $check } qw(cpu gpu ram swap memory swap+ram);

    $check = 'memory' if $check eq 'swap+ram';
    return ($unit, $check, undef);
}

sub normalize_unit {
    my ($u) = @_;
    $u = uc($u // q{});
    $u =~ s/^\s+|\s+$//g;
    return ('AUTO', undef) if $u eq 'AUTO';
    return (undef, "Invalid unit '$u'. Use auto, KB, MB, GB, TB, PB, EB, ZB, or YB")
        unless exists $UNIT_POWER{$u} && $u ne 'B';
    return ($u, undef);
}

sub usage {
    return <<'TXT';
Usage:
  system-check cpu
  system-check gpu
  system-check ram
  system-check swap
  system-check memory
  system-check --unit MB ram
  system-check --unit GB memory

Examples:
  {"cpu":{"load":"5%"}}
  {"gpu":{"load":"5%"}}
  {"ram":{"total":[32,"GB","100%"],"free":[10,"GB","31.25%"]}}
TXT
}

sub cpu_load_percent {
    my (%args) = @_;
    my $os = $args{os} || $^O;

    return windows_cpu_load_percent(%args) if $os =~ /MSWin32/i;
    return macos_cpu_load_percent(%args)   if $os eq 'darwin';

    my ($total1, $idle1, $error1) = read_linux_cpu_totals(%args);
    if (!defined $error1) {
        my ($total2, $idle2, $error2) = read_linux_cpu_totals(%args);
        if (!defined $error2) {
            my $total_delta = $total2 - $total1;
            my $idle_delta  = $idle2  - $idle1;
            if ($total_delta > 0) {
                return (clamp_pct((( $total_delta - $idle_delta ) * 100) / $total_delta), undef);
            }
        }
    }

    my ($top_load, $top_err) = linux_cpu_load_from_top(%args);
    return ($top_load, undef) if !defined $top_err;

    return (undef, 'Could not calculate CPU load');
}

sub linux_cpu_load_from_top {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'top', '-bn1' ],
    );
    return (undef, 'top unavailable') if $rc != 0 || !defined $out;

    for my $line (split /\r?\n/, $out) {
        next unless $line =~ /^%?Cpu/i;
        if ($line =~ /([0-9]+(?:\.[0-9]+)?)\s*id\b/i || $line =~ /([0-9]+(?:\.[0-9]+)?)\s*idle\b/i) {
            return (clamp_pct(100 - $1), undef);
        }
    }

    return (undef, 'top parse failure');
}

sub macos_cpu_load_percent {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'top', '-l', '1', '-n', '0' ],
    );
    return (undef, 'Could not read macOS CPU load') if $rc != 0 || !defined $out;

    for my $line (split /\r?\n/, $out) {
        next unless $line =~ /^CPU usage:/i;
        if ($line =~ /([0-9]+(?:\.[0-9]+)?)%\s*idle/i) {
            return (clamp_pct(100 - $1), undef);
        }
    }

    return (undef, 'Could not parse macOS CPU load');
}

sub read_linux_cpu_totals {
    my (%args) = @_;
    my $content = $args{read_file}->('/proc/stat');
    return (undef, undef, 'Could not read /proc/stat') unless defined $content;
    my ($line) = split /\r?\n/, $content;
    return (undef, undef, 'Could not parse /proc/stat')
        unless defined $line && $line =~ /^cpu\s+/;

    my @fields = split /\s+/, $line;
    shift @fields;
    @fields = @fields[ 0 .. 7 ] if @fields > 8;

    my $idle = ($fields[3] || 0) + ($fields[4] || 0);
    my $total = 0;
    $total += $_ for @fields;

    return ($total, $idle, undef);
}

sub windows_cpu_load_percent {
    my (%args) = @_;
    my $out = run_powershell(
        capture => $args{capture},
        script  => q{
            $v = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            if ($null -eq $v) { exit 3 }
            [Math]::Round($v, 2)
        },
    );
    if (!defined $out || $out !~ /([0-9]+(?:\.[0-9]+)?)/) {
        my ($rc, $wmic) = capture_command(
            capture => $args{capture},
            cmd     => [ 'wmic', 'cpu', 'get', 'loadpercentage', '/value' ],
        );
        $out = $wmic if $rc == 0;
    }
    return (undef, 'Could not read Windows CPU load')
        unless defined $out && $out =~ /([0-9]+(?:\.[0-9]+)?)/;
    return (clamp_pct($1), undef);
}

sub gpu_load_percent {
    my (%args) = @_;

    my ($load, $err) = gpu_load_from_nvidia_smi(%args);
    return ($load, undef) if !defined $err;

    my $os = $args{os} || $^O;
    if ($os =~ /MSWin32/i) {
        return windows_gpu_load_percent(%args);
    }
    if ($os eq 'darwin') {
        return (undef, 'GPU load is not available on macOS without a vendor-specific CLI such as nvidia-smi.');
    }

    ($load, $err) = linux_gpu_load_from_sysfs(%args);
    return ($load, undef) if !defined $err;

    ($load, $err) = linux_gpu_load_from_rocm_smi(%args);
    return ($load, undef) if !defined $err;

    return (undef, 'GPU load is not available. NVIDIA GPUs need nvidia-smi; some Linux AMD/Intel GPUs expose /sys/class/drm/card*/device/gpu_busy_percent; Windows may expose GPU Engine performance counters.');
}

sub gpu_load_from_nvidia_smi {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'nvidia-smi', '--query-gpu=utilization.gpu', '--format=csv,noheader,nounits' ],
    );
    return (undef, 'nvidia-smi unavailable') if $rc != 0 || !defined $out;
    for my $line (split /\r?\n/, $out) {
        return (clamp_pct($1), undef) if $line =~ /([0-9]+(?:\.[0-9]+)?)/;
    }
    return (undef, 'nvidia-smi parse failure');
}

sub linux_gpu_load_from_sysfs {
    my (%args) = @_;
    for my $file (glob_paths('/sys/class/drm/card*/device/gpu_busy_percent', %args)) {
        my $content = $args{read_file}->($file);
        next unless defined $content && $content =~ /([0-9]+(?:\.[0-9]+)?)/;
        return (clamp_pct($1), undef);
    }
    return (undef, 'sysfs gpu unavailable');
}

sub linux_gpu_load_from_rocm_smi {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'rocm-smi', '--showuse' ],
    );
    return (undef, 'rocm-smi unavailable') if $rc != 0 || !defined $out;
    for my $line (split /\r?\n/, $out) {
        my @nums = $line =~ /([0-9]+(?:\.[0-9]+)?)/g;
        return (clamp_pct($nums[-1]), undef) if @nums;
    }
    return (undef, 'rocm-smi parse failure');
}

sub windows_gpu_load_percent {
    my (%args) = @_;
    my $out = run_powershell(
        capture => $args{capture},
        script  => q{
            $vals = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
            if ($null -eq $vals) { exit 3 }
            $samples = $vals.CounterSamples | ForEach-Object { $_.CookedValue }
            if ($samples.Count -eq 0) { exit 3 }
            [Math]::Round((($samples | Measure-Object -Average).Average), 2)
        },
    );
    return (undef, 'Could not read Windows GPU load')
        unless defined $out && $out =~ /([0-9]+(?:\.[0-9]+)?)/;
    return (clamp_pct($1), undef);
}

sub ram_bytes {
    my (%args) = @_;
    my $os = $args{os} || $^O;
    return windows_ram_bytes(%args) if $os =~ /MSWin32/i;
    return macos_ram_bytes(%args)   if $os eq 'darwin';
    return linux_ram_bytes(%args);
}

sub linux_ram_bytes {
    my (%args) = @_;
    my ($mem, $err) = read_linux_meminfo(%args);
    return (undef, undef, $err) if defined $err;

    my $total = ($mem->{MemTotal} || 0) * 1024;
    my $free  = (($mem->{MemAvailable} || $mem->{MemFree} || 0)) * 1024;
    return ($total, $free, undef);
}

sub macos_ram_bytes {
    my (%args) = @_;
    my ($rc1, $total_out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'sysctl', '-n', 'hw.memsize' ],
    );
    my ($rc2, $vm_out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'vm_stat' ],
    );
    return (undef, undef, 'Could not read macOS memory')
        if $rc1 != 0 || $rc2 != 0 || !defined $total_out || !defined $vm_out;
    return (undef, undef, 'Could not parse macOS memory')
        unless $total_out =~ /(\d+)/;

    my $total = $1;
    my $page_size = 4096;
    $page_size = $1 if $vm_out =~ /page size of (\d+) bytes/i;

    my %pages;
    for my $line (split /\r?\n/, $vm_out) {
        if ($line =~ /^Pages\s+([^:]+):\s+(\d+)\./) {
            $pages{$1} = $2;
        }
    }

    my $free_pages = ($pages{'free'} || 0) + ($pages{'speculative'} || 0) + ($pages{'inactive'} || 0);
    return ($total, $free_pages * $page_size, undef);
}

sub swap_bytes {
    my (%args) = @_;
    my $os = $args{os} || $^O;
    return windows_swap_bytes(%args) if $os =~ /MSWin32/i;
    return macos_swap_bytes(%args)   if $os eq 'darwin';
    return linux_swap_bytes(%args);
}

sub linux_swap_bytes {
    my (%args) = @_;
    my ($mem, $err) = read_linux_meminfo(%args);
    return (undef, undef, $err) if defined $err;

    my $total = ($mem->{SwapTotal} || 0) * 1024;
    my $free  = ($mem->{SwapFree}  || 0) * 1024;
    return ($total, $free, undef);
}

sub macos_swap_bytes {
    my (%args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'sysctl', 'vm.swapusage' ],
    );
    return (undef, undef, 'Could not read macOS swap')
        if $rc != 0 || !defined $out;

    my ($total, $total_unit, $used, $used_unit) = $out =~ /total = ([0-9.]+)([MG])\s+used = ([0-9.]+)([MG])/i;
    return (undef, undef, 'Could not parse macOS swap')
        unless defined $total && defined $used;

    my $factor = uc($total_unit) eq 'G' ? 1024 * 1024 * 1024 : 1024 * 1024;
    my $total_b = $total * $factor;
    my $used_factor = uc($used_unit) eq 'G' ? 1024 * 1024 * 1024 : 1024 * 1024;
    my $used_b = $used * $used_factor;
    my $free_b = $total_b - $used_b;
    $free_b = 0 if $free_b < 0;
    return ($total_b, $free_b, undef);
}

sub read_linux_meminfo {
    my (%args) = @_;
    my $content = $args{read_file}->('/proc/meminfo');
    return (undef, 'Could not read /proc/meminfo') unless defined $content;

    my %mem;
    for my $line (split /\r?\n/, $content) {
        next unless $line =~ /^(\w+):\s+(\d+)/;
        $mem{$1} = $2;
    }
    return (\%mem, undef);
}

sub windows_ram_bytes {
    my (%args) = @_;
    my $out = run_powershell(
        capture => $args{capture},
        script  => q{
            $os = Get-CimInstance Win32_OperatingSystem
            if ($null -eq $os) { exit 3 }
            Write-Output ("{0} {1}" -f $os.TotalVisibleMemorySize, $os.FreePhysicalMemory)
        },
    );
    return (undef, undef, 'Could not read Windows memory')
        unless defined $out && $out =~ /(\d+)\s+(\d+)/;
    return ($1 * 1024, $2 * 1024, undef);
}

sub windows_swap_bytes {
    my (%args) = @_;
    my $out = run_powershell(
        capture => $args{capture},
        script  => q{
            $files = Get-CimInstance Win32_PageFileUsage
            if ($null -eq $files) { exit 3 }
            $alloc = ($files | Measure-Object -Property AllocatedBaseSize -Sum).Sum
            $used  = ($files | Measure-Object -Property CurrentUsage -Sum).Sum
            Write-Output ("{0} {1}" -f $alloc, $used)
        },
    );
    return (0, 0, undef) unless defined $out && $out =~ /(\d+)\s+(\d+)/;
    my $total = $1 * 1024 * 1024;
    my $used  = $2 * 1024 * 1024;
    my $free  = $total - $used;
    $free = 0 if $free < 0;
    return ($total, $free, undef);
}

sub print_load_result {
    my ($label, $load) = @_;
    return sprintf('{"%s":{"load":"%s%%"}}' . "\n", $label, fmt_num($load));
}

sub print_memory_result {
    my ($label, $total, $free, $unit) = @_;
    $unit = choose_auto_unit($total) if $unit eq 'AUTO';
    my $used = $total - $free;
    my $free_pct = $total > 0 ? ($free * 100 / $total) : 0;
    return sprintf(
        '{"%s":{"total":[%s,"%s","100%%"],"free":[%s,"%s","%s%%"]}}' . "\n",
        $label,
        fmt_num(bytes_to_unit($total, $unit)),
        $unit,
        fmt_num(bytes_to_unit($free, $unit)),
        $unit,
        fmt_num($free_pct),
    );
}

sub choose_auto_unit {
    my ($bytes) = @_;
    for my $unit (reverse @UNITS) {
        next if $unit eq 'B';
        return $unit if bytes_to_unit($bytes, $unit) >= 1;
    }
    return 'KB';
}

sub bytes_to_unit {
    my ($bytes, $unit) = @_;
    return 0 if !$bytes;
    return $bytes / (1024 ** $UNIT_POWER{$unit});
}

sub clamp_pct {
    my ($pct) = @_;
    $pct = 0   if $pct < 0;
    $pct = 100 if $pct > 100;
    return $pct;
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
