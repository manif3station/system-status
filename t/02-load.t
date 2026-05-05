use strict;
use warnings;

use File::Temp qw(tempfile);
use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use SystemStatus::Load;
use SystemStatus::Util qw(capture_command fmt_num json_error json_string run_powershell);

sub capture_main {
    my ($code) = @_;
    my ($stdout, $stderr) = ( q{}, q{} );
    open my $out, '>', \$stdout or die $!;
    open my $err, '>', \$stderr or die $!;
    local *STDOUT = $out;
    local *STDERR = $err;
    my $exit = $code->();
    return ($exit, $stdout, $stderr);
}

{
    my ( $unit, $check, $error ) = SystemStatus::Load::parse_args('--unit=GB', 'memory');
    is( $unit, 'GB', 'parse_args handles equals-sign unit syntax' );
    is( $check, 'memory', 'equals-sign syntax still targets the requested check' );
    ok( !defined $error, 'equals-sign syntax is accepted' );
}

{
    my ( $unit, $check, $error ) = SystemStatus::Load::parse_args(qw(--unit GB memory));
    is( $unit, 'GB', 'parse_args handles long --unit syntax' );
    is( $check, 'memory', 'parse_args returns requested check' );
    ok( !defined $error, 'parse_args does not fail for valid input' );
}

{
    my ( $unit, undef, undef ) = SystemStatus::Load::parse_args(qw(-u mb ram));
    is( $unit, 'MB', 'parse_args handles short unit syntax' );
}

{
    my ( undef, undef, $error ) = SystemStatus::Load::parse_args('--unit');
    like( $error, qr/Missing value/, 'parse_args rejects missing unit value' );
}

{
    my ( undef, undef, $error ) = SystemStatus::Load::parse_args('bogus');
    like( $error, qr/Unknown check/, 'parse_args rejects unknown checks' );
}

{
    my ( $unit, $check, undef ) = SystemStatus::Load::parse_args('swap+ram');
    is( $unit, 'AUTO', 'swap+ram keeps auto unit by default' );
    is( $check, 'memory', 'swap+ram normalizes to memory' );
}

{
    my ( $unit, undef, undef ) = SystemStatus::Load::parse_args('--help');
    is( $unit, 'HELP', 'help path is returned to the caller' );
}

{
    my ( undef, $error ) = SystemStatus::Load::normalize_unit('wat');
    like( $error, qr/Invalid unit/, 'normalize_unit rejects invalid values' );
}

{
    my ( $unit, $error ) = SystemStatus::Load::normalize_unit('auto');
    is( $unit, 'AUTO', 'normalize_unit accepts auto explicitly' );
    ok( !defined $error, 'auto does not produce an error' );
}

like( SystemStatus::Load::usage(), qr/system-check cpu/, 'usage text is available' );

{
    my $calls = 0;
    my $result = SystemStatus::Load::run(
        argv      => ['cpu'],
        os        => 'linux',
        read_file => sub {
            $calls++;
            return "cpu  100 0 50 850 0 0 0 0\n" if $calls == 1;
            return "cpu  200 0 70 930 0 0 0 0\n";
        },
        capture => sub { return ( 1, undef ) },
    );
    is( $result->{exit}, 0, 'linux cpu run succeeds from /proc/stat' );
    like( $result->{stdout}, qr/"cpu":\{"load":"60%"\}/, 'linux cpu load is calculated from deltas' );
}

{
    my $result = SystemStatus::Load::run(
        argv      => ['cpu'],
        os        => 'linux',
        read_file => sub { return "cpu  100 0 50 850 0 0 0 0\n" },
        capture   => sub { return ( 0, "%Cpu(s): 10 us, 20 sy, 70 id\n" ) },
    );
    like( $result->{stdout}, qr/"30%"/, 'linux cpu falls back to top parsing when deltas do not move' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['cpu'],
        os      => 'darwin',
        capture => sub { return ( 0, "CPU usage: 5% user, 15% sys, 80% idle\n" ) },
    );
    like( $result->{stdout}, qr/"20%"/, 'macOS cpu load is parsed from top output' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['cpu'],
        os      => 'MSWin32',
        capture => sub {
            my (@cmd) = @_;
            return ( 0, "42\n" ) if $cmd[0] =~ /powershell|pwsh/;
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"42%"/, 'windows cpu load uses PowerShell' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['cpu'],
        os      => 'MSWin32',
        capture => sub {
            my (@cmd) = @_;
            return ( 0, "not-a-number\n" ) if $cmd[0] =~ /powershell|pwsh/;
            return ( 0, "LoadPercentage=77\n" ) if $cmd[0] eq 'wmic';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"77%"/, 'windows cpu load falls back to wmic when PowerShell output is unusable' );
}

{
    my ( undef, $error ) = SystemStatus::Load::cpu_load_percent(
        os        => 'linux',
        read_file => sub { return undef },
        capture   => sub { return ( 1, undef ) },
    );
    like( $error, qr/Could not calculate CPU load/, 'cpu load reports total failure when no backend works' );
}

{
    my ( undef, $error ) = SystemStatus::Load::linux_cpu_load_from_top(
        capture => sub { return ( 0, "bogus\n" ) },
    );
    like( $error, qr/top parse failure/, 'linux top parser reports invalid output' );
}

{
    my ( undef, $error ) = SystemStatus::Load::macos_cpu_load_percent(
        capture => sub { return ( 0, "not cpu text\n" ) },
    );
    like( $error, qr/Could not parse macOS CPU load/, 'macOS top parser reports invalid output' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['gpu'],
        os      => 'linux',
        capture => sub {
            my (@cmd) = @_;
            return ( 0, "17\n" ) if $cmd[0] eq 'nvidia-smi';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"17%"/, 'gpu load prefers nvidia-smi' );
}

{
    my ( undef, $error ) = SystemStatus::Load::gpu_load_from_nvidia_smi(
        capture => sub { return ( 0, "n/a\n" ) },
    );
    like( $error, qr/nvidia-smi parse failure/, 'nvidia-smi parser reports invalid output' );
}

{
    my $result = SystemStatus::Load::run(
        argv       => ['gpu'],
        os         => 'linux',
        capture    => sub { return ( 1, undef ) },
        read_file  => sub { return "33\n" if $_[0] eq '/fake/gpu_busy'; return undef; },
        glob_paths => sub { return ('/fake/gpu_busy'); },
    );
    like( $result->{stdout}, qr/"33%"/, 'gpu load can come from linux sysfs' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['gpu'],
        os      => 'linux',
        capture => sub {
            my (@cmd) = @_;
            return ( 1, undef ) if $cmd[0] eq 'nvidia-smi';
            return ( 0, "card0 88\n" ) if $cmd[0] eq 'rocm-smi';
            return ( 1, undef );
        },
        read_file  => sub { return undef },
        glob_paths => sub { return () },
    );
    like( $result->{stdout}, qr/"88%"/, 'gpu load can come from rocm-smi' );
}

{
    my ( undef, $error ) = SystemStatus::Load::linux_gpu_load_from_rocm_smi(
        capture => sub { return ( 0, "rocm without percentages\n" ) },
    );
    like( $error, qr/rocm-smi parse failure/, 'rocm parser reports invalid output' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['gpu'],
        os      => 'MSWin32',
        capture => sub {
            my (@cmd) = @_;
            return ( 1, undef ) if $cmd[0] eq 'nvidia-smi';
            return ( 0, "61\n" ) if $cmd[0] =~ /powershell|pwsh/;
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"61%"/, 'windows gpu load uses PowerShell counters' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['gpu'],
        os      => 'darwin',
        capture => sub { return ( 1, undef ) },
    );
    is( $result->{exit}, 1, 'macOS gpu load fails clearly when no vendor CLI exists' );
    like( $result->{stderr}, qr/macOS/, 'macOS gpu failure explains the limitation' );
}

{
    my $result = SystemStatus::Load::run(
        argv       => ['gpu'],
        os         => 'linux',
        capture    => sub { return ( 1, undef ) },
        read_file  => sub { return undef },
        glob_paths => sub { return () },
    );
    like( $result->{stderr}, qr/nvidia-smi|Windows may expose GPU Engine/, 'linux gpu failure reports a backend shortage clearly' );
}

{
    my $meminfo = <<'TXT';
MemTotal:       4096000 kB
MemFree:         512000 kB
MemAvailable:   1024000 kB
SwapTotal:      2048000 kB
SwapFree:       1024000 kB
TXT
    my $ram = SystemStatus::Load::run(
        argv      => [qw(--unit MB ram)],
        os        => 'linux',
        read_file => sub { return $meminfo },
        capture   => sub { return ( 1, undef ) },
    );
    like( $ram->{stdout}, qr/"ram":\{"total":\[4000,"MB","100%"\],"free":\[1000,"MB","25%"\]\}/, 'linux ram uses meminfo' );

    my $swap = SystemStatus::Load::run(
        argv      => [qw(--unit GB swap)],
        os        => 'linux',
        read_file => sub { return $meminfo },
        capture   => sub { return ( 1, undef ) },
    );
    like( $swap->{stdout}, qr/"swap":\{"total":\[1.95,"GB","100%"\]/, 'linux swap uses meminfo' );

    my $mem = SystemStatus::Load::run(
        argv      => [qw(--unit GB memory)],
        os        => 'linux',
        read_file => sub { return $meminfo },
        capture   => sub { return ( 1, undef ) },
    );
    like( $mem->{stdout}, qr/"memory":\{"total":\[5.86,"GB","100%"\]/, 'memory combines ram and swap' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['ram'],
        os      => 'darwin',
        capture => sub {
            my (@cmd) = @_;
            return ( 0, "8589934592\n" ) if $cmd[0] eq 'sysctl' && $cmd[1] eq '-n';
            return ( 0, "Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: 100.\nPages speculative: 50.\nPages inactive: 25.\n" ) if $cmd[0] eq 'vm_stat';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"ram":\{"total":\[8,"GB","100%"\]/, 'macOS ram uses sysctl and vm_stat' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['swap'],
        os      => 'darwin',
        capture => sub { return ( 0, "vm.swapusage: total = 2.00G  used = 0.50G  free = 1.50G\n" ) },
    );
    like( $result->{stdout}, qr/"swap":\{"total":\[2,"GB","100%"\],"free":\[1.5,"GB","75%"\]\}/, 'macOS swap uses sysctl vm.swapusage' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['ram'],
        os      => 'MSWin32',
        capture => sub { return ( 0, "4096000 1024000\n" ) },
    );
    like( $result->{stdout}, qr/"ram":\{"total":\[3.91,"GB","100%"\]/, 'windows ram uses PowerShell' );
}

{
    my $result = SystemStatus::Load::run(
        argv    => ['swap'],
        os      => 'MSWin32',
        capture => sub { return ( 0, "4096 1024\n" ) },
    );
    like( $result->{stdout}, qr/"swap":\{"total":\[4,"GB","100%"\],"free":\[3,"GB","75%"\]\}/, 'windows swap uses pagefile usage' );
}

{
    my ( undef, $error ) = SystemStatus::Load::read_linux_meminfo( read_file => sub { return undef } );
    like( $error, qr/\/proc\/meminfo/, 'read_linux_meminfo reports missing file' );
}

is( SystemStatus::Load::choose_auto_unit( 1024**4 ), 'TB', 'auto unit picks the largest sensible unit' );
is( SystemStatus::Load::choose_auto_unit( 12 ), 'KB', 'auto unit falls back to KB for tiny values' );
is( SystemStatus::Load::bytes_to_unit( 2 * 1024**3, 'GB' ), 2, 'bytes_to_unit converts to target units' );
is( SystemStatus::Load::clamp_pct(150), 100, 'clamp_pct caps high values' );
is( SystemStatus::Load::clamp_pct(-5), 0, 'clamp_pct caps low values' );
like( SystemStatus::Load::print_load_result( 'cpu', 12.5 ), qr/"12.5%"/, 'load result renderer works directly' );
like( SystemStatus::Load::print_memory_result( 'ram', 2 * 1024**3, 1 * 1024**3, 'GB' ), qr/"free":\[1,"GB","50%"\]/, 'memory renderer works directly' );
is_deeply( [ SystemStatus::Load::glob_paths( '/tmp/does-not-matter', glob_paths => sub { return ('x') } ) ], ['x'], 'glob helper can be injected' );
is( scalar( SystemStatus::Load::glob_paths('/definitely/not/a/match/*') ) || 0, 0, 'glob helper falls back to the builtin glob when not injected' );

{
    my ( $fh, $path ) = tempfile();
    print {$fh} "hello\n";
    close $fh;
    is( SystemStatus::Load::default_read_file($path), "hello\n", 'default_read_file reads a file path' );
}

{
    is_deeply( [ capture_command( cmd => ['definitely-not-a-real-command-xyz'] ) ], [ 1, undef ], 'util capture_command reports real command launch failure cleanly' );
    is_deeply( [ capture_command( capture => sub { return ( undef, undef ) }, cmd => ['ignored'] ) ], [ 0, undef ], 'util capture_command keeps undef output from injected captures' );
    is_deeply( [ capture_command( cmd => [ 'sh', '-lc', 'printf util-ok' ] ) ], [ 0, 'util-ok' ], 'util capture_command can run a real command' );
    is_deeply( [ capture_command( quiet => 1, cmd => [ 'sh', '-lc', 'printf quiet-ok' ] ) ], [ 0, 'quiet-ok' ], 'util capture_command can run quietly when optional probes should not leak stderr noise' );
    my $quiet_stderr = q{};
    {
        open my $err, '>', \$quiet_stderr or die $!;
        local *STDERR = $err;
        is_deeply(
            [ capture_command( quiet => 1, cmd => [ 'sh', '-lc', 'printf quiet-out; printf quiet-err >&2' ] ) ],
            [ 0, 'quiet-out' ],
            'quiet capture keeps stdout while discarding child stderr',
        );
    }
    is( $quiet_stderr, q{}, 'quiet capture does not leak child stderr to the caller' );
    is( run_powershell( capture => sub { return ( 0, " \n" ) }, script => 'noop' ), undef, 'util run_powershell rejects blank output' );
    is( fmt_num(), '0', 'util fmt_num handles undef input' );
    is( json_error('x'), "{\"error\":\"x\"}\n", 'util json_error encodes a json error string' );
    is( json_string({ ok => 1 }), '{"ok":1}', 'util json_string encodes arbitrary data' );
}

{
    my ( $exit, $stdout, $stderr ) = capture_main(
        sub { SystemStatus::Load::main('--help') }
    );
    is( $exit, 0, 'load module main exits cleanly for help' );
    like( $stdout, qr/system-check cpu/, 'load module main prints usage for help' );
    is( $stderr, q{}, 'load module main help keeps stderr empty' );
}

{
    my ( $exit, $stdout, $stderr ) = capture_main(
        sub { SystemStatus::Load::main('cpu') }
    );
    is( $exit, 0, 'load module main exits cleanly for a real check' );
    like( $stdout, qr/"cpu":\{"load":"/, 'load module main writes the cpu payload' );
    is( $stderr, q{}, 'load module main success keeps stderr empty' );
}

{
    my $stdout = qx{$^X cli/load --help};
    my $exit   = $? >> 8;
    is( $exit, 0, 'cli/load help exits cleanly' );
    like( $stdout, qr/system-check memory/, 'cli/load prints the usage text' );
}

done_testing;
