#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../lib";

use Test::More;
use File::Slurper qw(read_text);
use XCAT::Test::File qw(repo_path);
use xCAT::Utils;

# An IPv6-only node still has to be given a netboot method it can use, so the
# method the node templates ship must be one lookupNetboot offers for that
# architecture, and a plugin of that name must exist to serve it. The method
# names themselves are not asserted: the shipped set changes per release and a
# literal list here would pass after the plugin it names is removed.
my @cases = (
    [ 'x86_64.stanza',          'x86_64',  'alma10.1' ],
    [ 'x86_64kvmguest.stanza',  'x86_64',  'alma10.1' ],
    [ 'ppc64le-ipmi.stanza',    'ppc64le', 'alma10.1' ],
    [ 'ppc64lekvmguest.stanza', 'ppc64le', 'alma10.1' ],
);

foreach my $case (@cases) {
    my ( $stanza, $osarch, $osvers ) = @{$case};
    my $text = read_text( repo_path("xCAT/templates/objects/node/$stanza") );
    my ($shipped) = $text =~ /^\s*netboot=(\S+)\s*$/m;
    ok( $shipped, "$stanza ships a netboot method" ) or next;

    my %offered = map { $_ => 1 } split( /,/, xCAT::Utils->lookupNetboot( $osvers, $osarch, 'Linux' ) );
    ok( $offered{$shipped}, "lookupNetboot offers '$shipped' for $osarch" );
    ok( -f repo_path("xCAT-server/lib/xcat/plugins/$shipped.pm"),
        "a netboot plugin serves '$shipped'" );
}

# lookupNetboot answers per architecture, and an architecture it does not know
# must answer nothing rather than fall back to another architecture's method.
ok( !xCAT::Utils->lookupNetboot( 'alma10.1', 's390x', 'Linux' ),
    'an unknown architecture is offered no netboot method' );

done_testing();
