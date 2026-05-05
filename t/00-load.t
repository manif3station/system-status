use strict;
use warnings;

use Test::More;

use lib 'lib';

BEGIN {
    use_ok('SystemStatus::Util');
    use_ok('SystemStatus::Disk');
    use_ok('SystemStatus::Load');
    use_ok('SystemStatus::Temperature');
}

done_testing;
