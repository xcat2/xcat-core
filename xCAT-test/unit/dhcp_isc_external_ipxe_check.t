#!/usr/bin/env perl
# makedhcp does not write the configuration of an external dhcpd, and OMAPI removes a host before it
# adds it again. Before it updates netboot=ipxe nodes there, makedhcp creates a host of its own whose
# statement tests every iPXE feature option, reads it back in a second omshell run, and removes it.
# Only that host, returned by the dhcpd, lets the update go ahead.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::OmapiPolicy;

$ENV{XCATCFG} ||= 'SQLite:/tmp';
my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

my $settings = xCAT::DHCP::OmapiPolicy->settings( site_values => {} );
my %nrhash = (
    'cn-ipxe' => [ { netboot => 'ipxe' } ],
    'cn-xnba' => [ { netboot => 'xnba' } ],
    'cn-none' => [ {} ],
);
# The replies of dhcpd 4.4 without the declarations (rejected) and with them (kept), for the host that
# the first omshell run of the check creates.
sub mac_of { my ($commands) = @_; return $commands =~ /^set hardware-address = (\S+)$/m ? $1 : ''; }
my @rejected = ( "> can't open object: parse error(s) occurred\n", "obj: host\n", "hardware-type = 1\n" );
my @not_found = ( "> can't open object: not found\n", "obj: host\n" );
sub created { my ($mac) = @_; return ( "> obj: host\n", "hardware-address = $mac\n", "hardware-type = 00:00:00:01\n" ); }
sub kept { my ($mac) = @_; return ( "> obj: host\n", "hardware-address = $mac\n", "hardware-type = 00:00:00:01\n", "> obj: <null>\n" ); }

# Each reply is a list of lines or a code that gets the commands of the first run.
my ( @commands, @replies );
no warnings 'redefine';
local *xCAT_plugin::dhcp::_run_omshell = sub {
    push @commands, $_[0];
    my $reply = shift(@replies) || [];
    return ref($reply) eq 'CODE' ? $reply->( $commands[0] ) : @$reply;
};

sub check {
    my ( $server, @nodes ) = @_;
    local $::XCATSITEVALS{externaldhcpservers} = $server;
    @commands = ();
    return xCAT_plugin::dhcp::_isc_external_ipxe_check( \@nodes, \%nrhash, $settings, 'c2VjcmV0' );
}
my @accepts = ( sub { created( mac_of(shift) ) }, sub { kept( mac_of(shift) ) } );

@replies = @accepts;
my ( $unchanged, $error ) = check( undef, 'cn-ipxe' );
is_deeply( [ $unchanged, $error, scalar @commands ], [ {}, undef, 0 ], 'a local dhcpd gets no check' );

( $unchanged, $error ) = check( '192.0.2.53', 'cn-xnba', 'cn-none' );
is_deeply( [ $unchanged, $error, scalar @commands ], [ {}, undef, 0 ], 'an external dhcpd gets no check without netboot=ipxe nodes' );

@replies = @accepts;
( $unchanged, $error ) = check( '192.0.2.53', 'cn-ipxe', 'cn-xnba' );
is_deeply( [ $unchanged, $error ], [ {}, undef ], 'an external dhcpd that keeps the check host updates every node' );
is( scalar @commands, 2, 'after one omshell run that creates the host and one that reads it back' );
like( $commands[0], qr/^server 192\.0\.2\.53$/m, 'against the external dhcpd' );
like( $commands[0],
    qr/^set statements = "if exists gpxe\.iscsi and exists gpxe\.http and exists gpxe\.bzimage and exists gpxe\.pxe and exists gpxe\.efi \{ filename = \\"\\"; \}"\ncreate$/m,
    'a host whose statement tests every iPXE feature option' );
unlike( $commands[0], qr/^(?:open|remove)$/m, 'the first run opens no host before it creates one' );
my ($name) = $commands[0] =~ /^set name = "(xcat-ipxe-check-[0-9a-f]+)"$/m;
ok( $name, 'the check host has a name of its own' );
like( mac_of( $commands[0] ), qr/^02(?::[0-9a-f]{2}){5}$/, 'and a locally administered address' );
like( $commands[1], qr/^set name = "\Q$name\E"\nopen\nremove$/m, 'the second run reads that host back and removes it' );
unlike( $commands[1], qr/^set hardware-address/m, 'setting only its name' );

my @first = @commands;
@replies = @accepts;
check( '192.0.2.53', 'cn-ipxe' );
isnt( mac_of( $commands[0] ), mac_of( $first[0] ), 'another run creates a host with another address' );

@replies = ( [ @rejected ], [ @not_found ] );
( $unchanged, $error ) = check( '192.0.2.53', 'cn-ipxe', 'cn-xnba' );
is_deeply( $unchanged, { 'cn-ipxe' => 1 }, 'an external dhcpd without the options leaves the netboot=ipxe nodes unchanged' );
like( $error, qr/^The DHCP server 192\.0\.2\.53 does not declare the iPXE feature options.*: cn-ipxe\. /,
    'and makedhcp names the server and the nodes' );

for my $case (
    [ 'a first run cut short', [ [ "> obj: host\n" ], [@not_found] ] ],
    [ 'a second run without a reply', [ $accepts[0], [] ] ],
    [ 'a second run cut short', [ $accepts[0], [ "> obj: host\n" ] ] ],
    [ 'a host of another run', [ $accepts[0], [ kept('02:00:00:00:00:01') ] ] ],
    [ 'a lost connection', [ ["> not connected\n"], ["> not connected\n"] ] ],
  )
{
    @replies = @{ $case->[1] };
    ( $unchanged, $error ) = check( '192.0.2.53', 'cn-ipxe' );
    is_deeply( $unchanged, { 'cn-ipxe' => 1 }, "$case->[0] leaves the netboot=ipxe nodes unchanged" );
    like( $error, qr/did not confirm a check of the iPXE feature options/, "$case->[0] is reported" );
}

done_testing();
