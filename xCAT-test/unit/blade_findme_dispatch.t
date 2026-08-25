#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;
use lib File::Spec->catdir( $FindBin::Bin, '..', '..',
    'perl-xCAT' ),
  File::Spec->catdir( $FindBin::Bin, '..', '..',
    'xCAT-server', 'lib', 'perl' );
use xCAT::DiscoveryUtils;

sub entry_for {
    my ($req) = @_;
    return xCAT::DiscoveryUtils::findme_request_for_handler($req);
}

# This is the request a booting node sends: a command and its own details, and
# no node, because the node is what the request asks xCAT to find.
my $request = {
    command => ['findme'],
    arch    => ['x86_64'],
    uuid    => ['00000000-0000-0000-0000-000000000000'],
};
my $got = entry_for($request);
is( ref $got, 'ARRAY', 'a findme request is handed on to the handler' );

# The request that comes back has to be the one that arrived, or the handler
# loses the client address that it matches the node by.
is( $got->[0], $request, 'the request that arrived is handed on unchanged' );

# A request that was already preprocessed elsewhere is still handed on.
$got = entry_for( { command => ['findme'], _xcatpreprocessed => [1] } );
is( ref $got, 'ARRAY', 'an already preprocessed findme request is handed on' );

# Every other command keeps the noderange requirement.
foreach my $command (qw(rpower rinv rvitals rbeacon)) {
    is( entry_for( { command => [$command] } ), undef,
        "a $command request is left for normal preprocessing" );
}

is( entry_for({}), undef, 'a request without a command is left alone' );
is( entry_for(undef), undef, 'an undefined request is left alone' );

ok( !xCAT::DiscoveryUtils::findme_request_is_claimed($request),
    'a fresh findme request is available to a discovery handler' );
ok(
    !xCAT::DiscoveryUtils::findme_request_is_claimed(
        { command => ['findme'], discoverymethod => ['undef'] }
    ),
    'the discovery sentinel leaves a findme request available'
);
ok(
    xCAT::DiscoveryUtils::findme_request_is_claimed(
        { command => ['findme'], discoverymethod => ['blade'] }
    ),
    'a named discovery method claims the findme request'
);
ok(
    !xCAT::DiscoveryUtils::findme_request_is_claimed(
        { command => ['rinv'], discoverymethod => ['blade'] }
    ),
    'a discovery method does not turn another command into findme'
);

done_testing();
