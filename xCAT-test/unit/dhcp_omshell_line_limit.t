#!/usr/bin/env perl
# omshell reads 1023 bytes of a line, and the commands of an ISC host remove the old host before they
# create it again. makedhcp must send no command of a host with a longer line, so that the host keeps
# its reservation.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';
my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

no warnings 'redefine';
local *xCAT_plugin::dhcp::_omapi_pre_create_cleanup_supported = sub { return 1; };
local *xCAT_plugin::dhcp::_omapi_ip_lookup_supported = sub { return 1; };

# The commands of host cn01 with statements whose "set statements" line has $bytes bytes.
sub host_commands {
    my ( $bytes, $mgtifname ) = @_;
    my $statements = 'x' x ( $bytes - length(qq{set statements = ""\n}) );
    return xCAT_plugin::dhcp::_isc_omapi_host_commands( 'cn01', 'b8:3f:d2:4a:68:aa', 1, $mgtifname // 'eth0', '192.0.2.11',
        $statements, 0 );
}

sub send_host {
    my ($commands) = @_;
    open( my $omshell, '>', \my $sent ) or die "Cannot open an in-memory handle: $!";
    my $error = xCAT_plugin::dhcp::_send_isc_omapi_host( $omshell, 'cn01', $commands );
    close($omshell);
    return ( $error, $sent // '' );
}

my $fits = host_commands(1023);
my ( $error, $sent ) = send_host($fits);
is( $error, undef, 'a host whose longest line has 1023 bytes gives no error' );
is( $sent, $fits, 'and makedhcp sends its commands unchanged' );
like( $sent, qr/^set statements = "x{1003}"$/m, 'which set the whole statements' );
ok( index( $sent, "remove\n" ) < index( $sent, "create\n" ), 'and remove the old host before they create it' );

( $error, $sent ) = send_host( host_commands(1024) );
like( $error, qr/^cn01: an omshell command for its DHCP host is 1024 bytes, over the 1023 bytes/, 'a 1024-byte line gives an error that names the node' );
like( $error, qr/leaves the host unchanged$/, 'and says that the host stays' );
is( $sent, '', 'and makedhcp sends no command, so the old host is not removed' );

my $twin = host_commands( 1024, 'ib0' );
like( $twin, qr/-xcat-ib/, 'a host on an InfiniBand interface also gets a twin' );
( $error, $sent ) = send_host($twin);
ok( $error && $sent eq '', 'and makedhcp sends neither host when their statements are too long' );

done_testing();
