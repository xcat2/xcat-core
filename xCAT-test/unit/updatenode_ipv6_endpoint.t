#!/usr/bin/env perl
# updatenode tells xcatdsklspost on the node where to fetch from, as an
# authority it builds from the service node name and the httpport site
# attribute. An IPv6 service node has to be bracketed there, or the node reads
# the last colon group of the address as the port.
#
# Each case runs the real dispatch path and reads the xdsh command updatenode
# would have run.
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

BEGIN {
    $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server";

    # monitorctrl pulls in the notification plugin and the whole monitoring
    # tree, which updatenode never calls on this path.
    package xCAT_monitoring::monitorctrl;
    sub setNodeStatusAttributes { return; }
    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
}

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/updatenode.pm";

our $server_nodes;

# Runs one updatenode entry point and answers the commands it dispatched and
# the responses it sent to the callback.
sub dispatch {
    my ( $entrypoint, $server, @extra ) = @_;
    $server_nodes = { $server => ['node01'] };
    my ( @commands, @responses );

    no warnings qw(once redefine);
    local *xCAT::TableUtils::getInstallDir       = sub { return '/install'; };
    local *xCAT::TableUtils::getTftpDir          = sub { return '/tftpboot'; };
    local *xCAT::TableUtils::get_site_attribute  = sub {
        my ( $class, $name ) = @_;
        return ('80') if $name eq 'httpport';
        return ();
    };
    local *xCAT::InstUtils::get_server_nodes = sub { return $server_nodes; };
    local *xCAT::InstUtils::getOSnodes =
      sub { return ( 0, [], ['node01'] ); };
    local *xCAT::MsgUtils::message = sub { return; };

    my $subreq = sub {
        my $request = shift;
        push @commands, $request->{arg}->[-1];
        return;
    };
    my $callback = sub { push @responses, $_[0]; return; };

    my $run = \&{"xCAT_plugin::updatenode::$entrypoint"};
    $run->( { node => ['node01'], postscripts => ['syslog'] },
        $subreq, $callback, @extra );

    return ( \@commands, \@responses );
}

# updatenode -P, without --setservers.
my ( $commands, $responses ) = dispatch( 'updatenoderunps', '2001:db8::1' );
is( scalar( @{$commands} ), 1, 'updatenode -P dispatches one command' );
like(
    $commands->[0],
    qr{\Qxcatdsklspost 1 -m '[2001:db8::1]:80'\E},
    'updatenode -P brackets an IPv6 service node in the HTTP endpoint'
);

( $commands, $responses ) = dispatch( 'updatenoderunps', '192.0.2.10' );
like(
    $commands->[0],
    qr{\Qxcatdsklspost 1 -m '192.0.2.10:80'\E},
    'updatenode -P leaves an IPv4 service node unbracketed'
);

# updatenode -P --setservers takes the -M form of the same endpoint.
{
    local $::SETSERVER = 1;
    ( $commands, $responses ) = dispatch( 'updatenoderunps', '2001:db8::1' );
    like(
        $commands->[0],
        qr{\Qxcatdsklspost 1 -M '[2001:db8::1]:80'\E},
        'updatenode --setservers brackets an IPv6 service node too'
    );
}

# updatenode -S.
( $commands, $responses ) = dispatch( 'updatenodesoftware', '2001:db8::1' );
is( scalar( @{$commands} ), 1, 'updatenode -S dispatches one command' );
like(
    $commands->[0],
    qr{\Qxcatdsklspost 2 -m '[2001:db8::1]:80'\E},
    'updatenode -S brackets an IPv6 service node in the HTTP endpoint'
);

# A service node name that is not a usable URI authority has no endpoint, and
# the nodes behind it are skipped rather than sent a malformed command.
foreach my $entrypoint (qw(updatenoderunps updatenodesoftware)) {
    ( $commands, $responses ) = dispatch( $entrypoint, 'bad host name' );
    is_deeply( $commands, [],
        "$entrypoint dispatches nothing for an unusable service node name" );
    is_deeply(
        [ map { $_->{errorcode}->[0] } grep { $_->{errorcode} } @{$responses} ],
        [1],
        "$entrypoint reports an error for an unusable service node name"
    );
}

done_testing();
