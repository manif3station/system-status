use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

my $config = do {
    local $/;
    open my $fh, '<', 'config/config.json' or die $!;
    <$fh>;
};

is_deeply( decode_json($config), {}, 'config/config.json is a valid empty object for a command-only skill' );

{
    my $stdout = qx{$^X cli/load cpu};
    my $exit   = $? >> 8;
    is( $exit, 0, 'cli/load cpu exits cleanly on the current host' );
    like( $stdout, qr/"cpu":\{"load":"[0-9.]+%"\}/, 'cli/load cpu prints a valid payload' );
}

{
    my $stdout = qx{$^X cli/temperature cpu};
    my $exit   = $? >> 8;
    is( $exit, 0, 'cli/temperature cpu exits cleanly on the current host' );
    like( $stdout, qr/"cpu":\{"temperature":/, 'cli/temperature cpu prints a valid payload' );
}

done_testing;
