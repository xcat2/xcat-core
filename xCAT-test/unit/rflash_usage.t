#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

BEGIN {
    package xCAT::Utils;
    sub Version { return 'test'; }
}

{
    local $INC{'xCAT/Utils.pm'} = __FILE__;
    require xCAT::Usage;
}

my $usage = xCAT::Usage->parseCommand( 'rflash', '--help' );

like( $usage, qr/\QNeXtScale FPC specific:\E/x,
    'rflash help identifies the NeXtScale FPC form' );
like(
    $usage,
    qr{\Qrflash <noderange> http://<server>/path/to/update.rom\E}x,
    'rflash help gives the complete FPC firmware URL syntax'
);

like( $usage, qr/\QPPC (using Direct FSP Management) specific:\E/x,
    'rflash help retains the Direct FSP form' );
like( $usage, qr/\QOpenPOWER BMC specific (using IPMI):\E/x,
    'rflash help retains the OpenPOWER IPMI form' );

done_testing();
