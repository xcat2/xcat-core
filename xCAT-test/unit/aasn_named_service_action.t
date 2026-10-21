#!/usr/bin/env perl

# setup_DNS writes named.conf through makenamed.conf and then brings the daemon up. It used to
# START the service. On Debian the package already runs named, so a start is a no-op: the daemon
# keeps serving the configuration it read at install time, the zone xCAT has just written is
# never loaded, and a compute node cannot resolve its service node.
#
# A minimization of this change set dropped that fix, because no fast test could see it. The
# decision lives in xCAT::SvrUtils, which a test can load; AAsn.pm cannot be loaded from a source
# tree at all, since it pulls in xCAT::Table and the rest of the server.

use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::SvrUtils;

can_ok('xCAT::SvrUtils', 'named_service_action') or do { done_testing(); exit 1 };

is(xCAT::SvrUtils::named_service_action('linux'), 'restart',
    'Linux restarts named, so the configuration just written is the one it serves');
is(xCAT::SvrUtils::named_service_action('aix'), 'start',
    'AIX keeps the start it has always used');
is(xCAT::SvrUtils::named_service_action(''), '',
    'an unknown platform does nothing rather than guessing an action');
is(xCAT::SvrUtils::named_service_action(undef), '',
    'an undefined platform does nothing');

done_testing();
