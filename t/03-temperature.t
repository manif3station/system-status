use strict;
use warnings;

use File::Temp qw(tempfile);
use Test::More;

use lib 'lib';
use SystemStatus::Temperature;

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
    my $help = SystemStatus::Temperature::run( argv => ['--help'] );
    is( $help->{exit}, 0, 'temperature help exits successfully' );
    like( $help->{stdout}, qr/system-temperature cpu/, 'temperature help text is returned' );
}

{
    my $bad = SystemStatus::Temperature::run( argv => [] );
    is( $bad->{exit}, 1, 'temperature run rejects missing target' );
    like( $bad->{stderr}, qr/cpu\|gpu/, 'temperature usage error is preserved' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['cpu'],
        os         => 'linux',
        read_file  => sub {
            return "coretemp\n" if $_[0] eq '/fake/hwmon0/name';
            return "61000\n"    if $_[0] eq '/fake/hwmon0/temp1_input';
            return undef;
        },
        glob_paths => sub {
            my ($pattern) = @_;
            return ('/fake/hwmon0')              if $pattern eq '/sys/class/hwmon/hwmon*';
            return ('/fake/hwmon0/temp1_input')  if $pattern eq '/fake/hwmon0/temp*_input';
            return ();
        },
        capture => sub { return ( 1, undef ) },
    );
    like( $result->{stdout}, qr/"celsius":\[61,"C"\]/, 'linux cpu temperature can come from hwmon' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['cpu'],
        os         => 'linux',
        read_file  => sub {
            return "x86_pkg_temp\n" if $_[0] eq '/fake/thermal0/type';
            return "53000\n"        if $_[0] eq '/fake/thermal0/temp';
            return undef;
        },
        glob_paths => sub {
            my ($pattern) = @_;
            return ()                  if $pattern eq '/sys/class/hwmon/hwmon*';
            return ('/fake/thermal0')  if $pattern eq '/sys/class/thermal/thermal_zone*';
            return ();
        },
        capture => sub { return ( 1, undef ) },
    );
    like( $result->{stdout}, qr/"celsius":\[53,"C"\]/, 'linux cpu temperature can come from thermal zones' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['cpu'],
        os         => 'linux',
        read_file  => sub { return undef },
        glob_paths => sub { return () },
        capture    => sub { return ( 0, "Package id 0: +57.5°C\n" ) },
    );
    like( $result->{stdout}, qr/"celsius":\[57.5,"C"\]/, 'linux cpu temperature can come from sensors' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['cpu'],
        os      => 'darwin',
        capture => sub {
            my (@cmd) = @_;
            return ( 0, "CPU die temperature: 49.5 C\n" ) if $cmd[0] eq '/usr/bin/powermetrics';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"celsius":\[49.5,"C"\]/, 'macOS cpu temperature can come from powermetrics' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['cpu'],
        os      => 'darwin',
        capture => sub {
            my (@cmd) = @_;
            return ( 1, undef ) if $cmd[0] eq '/usr/bin/powermetrics';
            return ( 0, "CPU temp: 48.0°C\n" ) if $cmd[0] eq 'istats';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"celsius":\[48,"C"\]/, 'macOS cpu temperature can fall back to istats' );
}

{
    my $calls = 0;
    my $result = SystemStatus::Temperature::run(
        argv    => ['cpu'],
        os      => 'darwin',
        capture => sub {
            my (@cmd) = @_;
            if ($cmd[0] eq '/usr/bin/powermetrics') {
                $calls++;
                return ( 1, "powermetrics: unrecognized sampler: smc\n" ) if $calls == 1;
                return ( 0, "CPU die temperature: 47.25 C\n" ) if $calls == 2;
            }
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"celsius":\[47.25,"C"\]/, 'macOS cpu temperature retries powermetrics with supported samplers' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['cpu'],
        os      => 'darwin',
        capture => sub {
            my (@cmd) = @_;
            return ( 0, "CPU average: 46.0 C\n" ) if $cmd[0] eq '/usr/bin/powermetrics';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"celsius":\[46,"C"\]/, 'macOS cpu temperature can use the broader powermetrics cpu parser' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['cpu'],
        os      => 'darwin',
        capture => sub { return ( 1, undef ) },
    );
    is( $result->{exit}, 1, 'macOS cpu temperature fails clearly when no tool exists' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['cpu'],
        os      => 'MSWin32',
        capture => sub { return ( 0, "44.5\n" ) },
    );
    like( $result->{stdout}, qr/"celsius":\[44.5,"C"\]/, 'windows cpu temperature uses PowerShell' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['cpu'],
        os      => 'MSWin32',
        capture => sub { return ( 1, undef ) },
    );
    like( $result->{stderr}, qr/LibreHardwareMonitor|ACPI thermal zones/, 'windows cpu failure explains the dependency' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['cpu'],
        os         => 'linux',
        read_file  => sub { return undef },
        glob_paths => sub { return () },
        capture    => sub { return ( 1, undef ) },
    );
    like( $result->{stderr}, qr/lm-sensors|thermal exposes CPU temperature sensors/, 'linux cpu total failure reports the missing sensor backends' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['gpu'],
        os      => 'linux',
        capture => sub { return ( 0, "66\n" ) },
    );
    like( $result->{stdout}, qr/"celsius":\[66,"C"\]/, 'gpu temperature prefers nvidia-smi' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['gpu'],
        os         => 'linux',
        read_file  => sub {
            return "amdgpu\n" if $_[0] eq '/fake/gpu/name';
            return "72000\n"  if $_[0] eq '/fake/gpu/temp1_input';
            return undef;
        },
        glob_paths => sub {
            my ($pattern) = @_;
            return ('/fake/gpu')             if $pattern eq '/sys/class/drm/card*/device/hwmon/hwmon*';
            return ()                        if $pattern eq '/sys/class/hwmon/hwmon*';
            return ('/fake/gpu/temp1_input') if $pattern eq '/fake/gpu/temp*_input';
            return ();
        },
        capture => sub { return ( 1, undef ) },
    );
    like( $result->{stdout}, qr/"celsius":\[72,"C"\]/, 'linux gpu temperature can come from hwmon' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['gpu'],
        os         => 'linux',
        read_file  => sub { return undef },
        glob_paths => sub { return () },
        capture    => sub {
            my (@cmd) = @_;
            return ( 1, undef ) if $cmd[0] eq 'nvidia-smi';
            return ( 0, "card0 temp 63.0\n" ) if $cmd[0] eq 'rocm-smi';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"celsius":\[63,"C"\]/, 'linux gpu temperature can come from rocm-smi' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['gpu'],
        os         => 'linux',
        read_file  => sub { return undef },
        glob_paths => sub { return () },
        capture    => sub {
            my (@cmd) = @_;
            return ( 1, undef ) if $cmd[0] eq 'nvidia-smi';
            return ( 1, undef ) if $cmd[0] eq 'rocm-smi';
            return ( 0, "amdgpu-pci-0100\nedge: +70.0°C\n" ) if $cmd[0] eq 'sensors';
            return ( 1, undef );
        },
    );
    like( $result->{stdout}, qr/"celsius":\[70,"C"\]/, 'linux gpu temperature can come from sensors' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['gpu'],
        os      => 'MSWin32',
        capture => sub {
            my (@cmd) = @_;
            return ( 1, undef ) if $cmd[0] eq 'nvidia-smi';
            return ( 0, "51\n" );
        },
    );
    like( $result->{stdout}, qr/"celsius":\[51,"C"\]/, 'windows gpu temperature uses PowerShell' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['gpu'],
        os      => 'MSWin32',
        capture => sub { return ( 1, undef ) },
    );
    like( $result->{stderr}, qr/LibreHardwareMonitor|OpenHardwareMonitor/, 'windows gpu failure explains the dependency' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv    => ['gpu'],
        os      => 'darwin',
        capture => sub { return ( 1, undef ) },
    );
    like( $result->{stderr}, qr/macOS/, 'macOS gpu failure explains the limitation' );
}

{
    my $result = SystemStatus::Temperature::run(
        argv       => ['gpu'],
        os         => 'linux',
        read_file  => sub { return undef },
        glob_paths => sub { return () },
        capture    => sub { return ( 1, undef ) },
    );
    like( $result->{stderr}, qr/NVIDIA GPUs need nvidia-smi/, 'linux gpu failure explains available backends' );
}

is( SystemStatus::Temperature::read_temp_file_c( '/fake/temp', read_file => sub { return "45000\n" } ), 45, 'read_temp_file_c normalizes millidegrees' );
is( SystemStatus::Temperature::read_first_line( '/fake/line', read_file => sub { return "a\nb\n" } ), 'a', 'read_first_line returns only the first line' );
is( SystemStatus::Temperature::max_temp_c( 20, 30, 25 ), 30, 'max_temp_c selects the hottest value' );
ok( SystemStatus::Temperature::valid_temp_c(50), 'valid_temp_c accepts sane temperatures' );
ok( !SystemStatus::Temperature::valid_temp_c(500), 'valid_temp_c rejects impossible temperatures' );
like( SystemStatus::Temperature::print_temperature_result( 'cpu', 50 ), qr/"fahrenheit":\[122,"F"\]/, 'temperature renderer works directly' );
is_deeply( [ SystemStatus::Temperature::glob_paths( '/tmp/whatever', glob_paths => sub { return ('x') } ) ], ['x'], 'temperature glob helper can be injected' );
is( scalar( SystemStatus::Temperature::glob_paths('/definitely/not/a/match/*') ) || 0, 0, 'temperature glob helper falls back to builtin glob' );

{
    my ( $fh, $path ) = tempfile();
    print {$fh} "hello\n";
    close $fh;
    is( SystemStatus::Temperature::default_read_file($path), "hello\n", 'temperature default_read_file reads a path' );
}

{
    my ( $exit, $stdout, $stderr ) = capture_main(
        sub { SystemStatus::Temperature::main('cpu') }
    );
    is( $exit, 0, 'temperature module main exits cleanly for cpu on the current host' );
    like( $stdout, qr/"cpu":\{"temperature":/, 'temperature module main writes the cpu payload' );
    is( $stderr, q{}, 'temperature module main success keeps stderr empty' );
}

{
    my $stdout = qx{$^X cli/temperature --help};
    my $exit   = $? >> 8;
    is( $exit, 0, 'cli/temperature help exits cleanly' );
    like( $stdout, qr/system-temperature gpu/, 'cli/temperature prints the usage text' );
}

done_testing;
