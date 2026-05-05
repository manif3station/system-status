use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use SystemStatus::Disk;

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
    my $result = SystemStatus::Disk::run( argv => [] );
    is( $result->{exit}, 1, 'disk run fails without a target' );
    like( $result->{stderr}, qr/diskspace-check/, 'disk usage error is preserved' );
}

{
    my $result = SystemStatus::Disk::run(
        argv    => ['/'],
        os      => 'linux',
        capture => sub {
            my (@cmd) = @_;
            if ( $cmd[0] eq 'df' ) {
                return ( 0, "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 1000 400 600 40% /\n" );
            }
            return ( 1, undef );
        },
    );
    is( $result->{exit}, 0, 'linux path run succeeds' );
    my $data = decode_json( $result->{stdout} );
    is( $data->{used}[2], '40%', 'disk used percentage is rendered' );
}

{
    my $result = SystemStatus::Disk::run(
        argv    => ['/dev/sda'],
        os      => 'linux',
        capture => sub {
            my (@cmd) = @_;
            if ( $cmd[0] eq 'lsblk' ) {
                return ( 0, qq{NAME="sda" MOUNTPOINT=""\nNAME="sda1" MOUNTPOINT="/"\nNAME="sda2" MOUNTPOINT="/boot"\n} );
            }
            return ( 0, "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 1000 250 750 25% /\n" )
                if $cmd[0] eq 'df' && $cmd[-1] eq '/';
            return ( 0, "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda2 200 50 150 25% /boot\n" )
                if $cmd[0] eq 'df' && $cmd[-1] eq '/boot';
            return ( 1, undef );
        },
    );
    is( $result->{exit}, 0, 'linux device run aggregates mounted partitions' );
    like( $result->{stdout}, qr/"used":\[/, 'aggregated device output is emitted' );
}

{
    my $result = SystemStatus::Disk::run(
        argv    => ['/dev/sdz'],
        os      => 'linux',
        capture => sub { return ( 0, qq{NAME="sdz" MOUNTPOINT=""\n} ) },
    );
    is( $result->{exit}, 1, 'linux device without mountpoints fails clearly' );
    like( $result->{stderr}, qr/no mounted filesystem/, 'mount guidance is preserved' );
}

{
    my $result = SystemStatus::Disk::run(
        argv    => ['c:'],
        os      => 'MSWin32',
        capture => sub { return ( 0, "1000 250\n" ) },
    );
    is( $result->{exit}, 0, 'windows drive run succeeds' );
}

{
    my $result = SystemStatus::Disk::run(
        argv    => ['bad'],
        os      => 'MSWin32',
        capture => sub { return ( 1, undef ) },
    );
    is( $result->{exit}, 1, 'windows invalid target fails' );
    like( $result->{stderr}, qr/use a drive/i, 'windows drive guidance is preserved' );
}

{
    my @mounts = SystemStatus::Disk::linux_mountpoints_for_device(
        '/dev/sda',
        capture => sub {
            return ( 0, qq{NAME="sda1" MOUNTPOINT="\\x2f"\nNAME="sda2" MOUNTPOINT="/"\nNAME="sda3" MOUNTPOINT="[SWAP]"\n} );
        },
    );
    is_deeply( \@mounts, ['/'], 'duplicate and swap mountpoints are filtered' );
}

{
    my ( undef, undef, undef, $error ) = SystemStatus::Disk::df_bytes(
        '/',
        os      => 'linux',
        capture => sub { return ( 1, undef ) },
    );
    like( $error, qr/Could not run df/, 'df command launch failure is reported' );
}

{
    my ( undef, undef, undef, $error ) = SystemStatus::Disk::df_bytes(
        '/',
        os      => 'linux',
        capture => sub { return ( 1, "oops\n" ) },
    );
    like( $error, qr/df failed/, 'df nonzero status is reported' );
}

{
    my ( undef, undef, undef, $error ) = SystemStatus::Disk::df_bytes(
        '/',
        os      => 'linux',
        capture => sub { return ( 0, "header only\n" ) },
    );
    like( $error, qr/No df output/, 'missing df data rows are rejected' );
}

{
    my ( undef, undef, undef, $error ) = SystemStatus::Disk::df_bytes(
        '/',
        os      => 'linux',
        capture => sub { return ( 0, "Filesystem 1024-blocks Used Available Capacity Mounted on\nbroken line\n" ) },
    );
    like( $error, qr/Could not parse df output/, 'invalid df data rows are rejected' );
}

{
    my @mounts = SystemStatus::Disk::linux_mountpoints_for_device(
        '/dev/sda',
        capture => sub { return ( 1, undef ) },
    );
    is_deeply( \@mounts, [], 'lsblk failure returns an empty mount list' );
}

{
    my $json = SystemStatus::Disk::render_json_result( 10 * 1024**3, 4 * 1024**3, 6 * 1024**3 );
    like( $json, qr/"used":\[4,"GB","40%"\]/, 'direct renderer keeps the expected contract' );
}

{
    my $json = SystemStatus::Disk::render_json_result( 0, 0, 0 );
    like( $json, qr/"available":\[0,"GB","0%"\]/, 'direct renderer handles zero totals' );
}

{
    my ( $exit, $stdout, $stderr ) = capture_main(
        sub { SystemStatus::Disk::main('/') }
    );
    is( $exit, 0, 'module main returns success on a valid host path' );
    like( $stdout, qr/"total":\[/, 'module main writes stdout payload' );
    is( $stderr, q{}, 'module main does not write stderr on success' );
}

{
    my ( $exit, $stdout, $stderr ) = capture_main(
        sub { SystemStatus::Disk::main() }
    );
    is( $exit, 1, 'module main returns failure without arguments' );
    is( $stdout, q{}, 'failing module main keeps stdout empty' );
    like( $stderr, qr/diskspace-check/, 'failing module main writes the usage error' );
}

{
    my $stdout = qx{$^X cli/disk /};
    my $exit   = $? >> 8;
    is( $exit, 0, 'cli/disk exits cleanly' );
    like( $stdout, qr/"total":\[/, 'cli/disk prints json' );
}

done_testing;
