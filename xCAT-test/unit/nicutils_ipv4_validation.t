#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $nicutils = File::Spec->catfile( $repo_root, 'xCAT', 'postscripts', 'nicutils.sh' );

sub first_ipv4 {
    my ($input) = @_;
    my $script = q{
        source "$1" >/dev/null
        log_error() {
            printf '%s\n' "[E]:Error: $*"
            return 1
        }
        get_first_addr_ipv4 "$2"
    };

    open(
        my $fh,
        '-|',
        'bash',
        '--noprofile',
        '--norc',
        '-c',
        $script,
        'bash',
        $nicutils,
        $input
    ) or die "Unable to run bash: $!";

    my $output = do { local $/; <$fh> };
    close($fh);

    chomp $output;
    return ( $? >> 8, $output );
}

my @accepted = (
    [ '10.10.1.0',       '10.10.1.0',       'final octet zero is allowed' ],
    [ '10.10.1.0|extra', '10.10.1.0',       'first address is extracted before nicips separator' ],
    [ '10.10.1.255',     '10.10.1.255',     'final octet 255 remains allowed' ],
    [ '223.255.255.0',   '223.255.255.0',   'highest unicast first octet is allowed' ],
    [ '010.010.001.000', '010.010.001.000', 'leading zeros are handled as decimal octets' ],
);

foreach my $case (@accepted) {
    my ( $rc, $output ) = first_ipv4( $case->[0] );
    is( $rc, 0, "$case->[2] return code" );
    is( $output, $case->[1], "$case->[2] output" );
}

my @rejected = (
    [ '0.1.2.3',     'first octet zero is rejected' ],
    [ '127.0.0.1',   'loopback range is rejected' ],
    [ '224.0.0.1',   'multicast range is rejected' ],
    [ '255.1.2.3',   'reserved first octet is rejected' ],
    [ '10.0.0.256',  'octet above 255 is rejected' ],
    [ '10.0.0.text', 'non-numeric octet is rejected' ],
);

foreach my $case (@rejected) {
    my ( $rc, $output ) = first_ipv4( $case->[0] );
    is( $rc, 1, "$case->[1] return code" );
    like( $output, qr/^\[E\]:Error:/, "$case->[1] output" );
}

done_testing();
