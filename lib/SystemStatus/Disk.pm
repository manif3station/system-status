package SystemStatus::Disk;

use strict;
use warnings;

use JSON::PP qw(encode_json);
use SystemStatus::Util qw(capture_command fmt_num);

sub main {
    my (@argv) = @_;
    my $result = run( argv => \@argv );
    print STDOUT $result->{stdout} if length $result->{stdout};
    print STDERR $result->{stderr} if length $result->{stderr};
    return $result->{exit};
}

sub run {
    my (%args) = @_;
    my $argv   = $args{argv} || [];
    my $os     = defined $args{os} ? $args{os} : $^O;
    my $target = $argv->[0];

    return failure('Usage: diskspace-check <drive-or-path>, e.g. c:, d:, /, /dev/sda')
        unless defined $target && length $target;

    my ($total, $used, $avail, $error);

    if ($os =~ /MSWin32/i) {
        ($total, $used, $avail, $error) = windows_disk_space(
            $target,
            capture => $args{capture},
        );
    } else {
        ($total, $used, $avail, $error) = unix_disk_space(
            $target,
            os      => $os,
            capture => $args{capture},
        );
    }

    return failure($error) if defined $error;

    return success(render_json_result($total, $used, $avail));
}

sub windows_disk_space {
    my ($target, %args) = @_;

    my $drive;
    if ($target =~ /^([A-Za-z]):(?:[\\\/].*)?$/) {
        $drive = uc($1) . ':\\';
    } else {
        return (undef, undef, undef, 'On Windows, use a drive like c: or d:');
    }

    my $script = qq{
        \$d = New-Object System.IO.DriveInfo '$drive'
        if (-not \$d.IsReady) { exit 3 }
        Write-Output ("{0} {1}" -f \$d.TotalSize, \$d.AvailableFreeSpace)
    };

    my ($rc, $out);
    for my $exe ('powershell.exe', 'powershell', 'pwsh') {
        ($rc, $out) = capture_command(
            capture => $args{capture},
            cmd     => [ $exe, '-NoProfile', '-NonInteractive', '-Command', $script ],
        );
        last if defined $out && $out =~ /(\d+)\s+(\d+)/;
    }

    return (undef, undef, undef, "Could not read Windows disk information for $target")
        unless defined $out && $out =~ /(\d+)\s+(\d+)/;

    my ($total, $avail) = ($1, $2);
    my $used = $total - $avail;

    return ($total, $used, $avail, undef);
}

sub unix_disk_space {
    my ($target, %args) = @_;
    my $os = $args{os} || $^O;

    my @targets;
    if ($os eq 'linux' && $target =~ m{^/dev/}) {
        @targets = linux_mountpoints_for_device(
            $target,
            capture => $args{capture},
        );
        return (undef, undef, undef, "$target has no mounted filesystem. Use a mounted partition like /dev/sda1 or a mount path like /")
            unless @targets;
    } else {
        @targets = ($target);
    }

    my ($total, $used, $avail) = (0, 0, 0);
    for my $path (@targets) {
        my ($t, $u, $a, $error) = df_bytes(
            $path,
            os      => $os,
            capture => $args{capture},
        );
        return (undef, undef, undef, $error) if defined $error;
        $total += $t;
        $used  += $u;
        $avail += $a;
    }

    return ($total, $used, $avail, undef);
}

sub linux_mountpoints_for_device {
    my ($dev, %args) = @_;
    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => [ 'lsblk', '-P', '-o', 'NAME,MOUNTPOINT', $dev ],
    );
    return () if $rc != 0 || !defined $out;

    my @mounts;
    for my $line (split /\r?\n/, $out) {
        my %kv;
        while ($line =~ /(\w+)="((?:[^"\\]|\\.)*)"/g) {
            my ($k, $v) = ($1, $2);
            $v =~ s/\\x([0-9a-fA-F]{2})/chr(hex($1))/eg;
            $v =~ s/\\"/"/g;
            $v =~ s/\\\\/\\/g;
            $kv{$k} = $v;
        }
        next unless defined $kv{MOUNTPOINT} && length $kv{MOUNTPOINT};
        next if $kv{MOUNTPOINT} =~ /^\[/;
        push @mounts, $kv{MOUNTPOINT};
    }

    my %seen;
    return grep { !$seen{$_}++ } @mounts;
}

sub df_bytes {
    my ($path, %args) = @_;
    my $os = $args{os} || $^O;
    my @cmd = $os eq 'linux'
        ? ('df', '-Pk', '--', $path)
        : ('df', '-Pk', $path);

    my ($rc, $out) = capture_command(
        capture => $args{capture},
        cmd     => \@cmd,
    );

    return (undef, undef, undef, "Could not run df for $path")
        if !defined $out && $rc != 0;
    return (undef, undef, undef, "df failed for $path")
        if $rc != 0;

    my @lines = grep { /\S/ } split /\r?\n/, ($out // q{});
    return (undef, undef, undef, "No df output for $path")
        unless @lines >= 2;

    my @f = split /\s+/, $lines[-1];
    return (undef, undef, undef, "Could not parse df output for $path")
        unless @f >= 6 && $f[1] =~ /^\d+$/ && $f[2] =~ /^\d+$/ && $f[3] =~ /^\d+$/;

    return ($f[1] * 1024, $f[2] * 1024, $f[3] * 1024, undef);
}

sub render_json_result {
    my ($total, $used, $avail) = @_;
    my $used_pct  = $total > 0 ? ($used  * 100 / $total) : 0;
    my $avail_pct = $total > 0 ? ($avail * 100 / $total) : 0;

    return sprintf(
        '{"total":[%s,"GB","100%%"],"used":[%s,"GB","%s%%"],"available":[%s,"GB","%s%%"]}' . "\n",
        fmt_num($total / 1024 / 1024 / 1024),
        fmt_num($used / 1024 / 1024 / 1024),
        fmt_num($used_pct),
        fmt_num($avail / 1024 / 1024 / 1024),
        fmt_num($avail_pct),
    );
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
