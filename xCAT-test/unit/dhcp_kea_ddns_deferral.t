use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    package xCAT::Table;
    our $networks;
    sub new {
        my ( $class, $name ) = @_;
        return $name eq 'networks' ? $networks : undef;
    }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub getTftpDir { return '/srv/tftp'; }
    sub get_site_attribute { return; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::getipaddr"} = \&getipaddr;
    }
    sub getipaddr { return '10.0.0.1'; }
    sub my_ip_facing { return ( 0, '10.0.0.1' ); }
    sub thishostisnot { return 0; }
    sub ip_forwarding_enabled { return 0; }
    sub nodeonmynet { return 1; }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::ServiceNodeUtils;
    sub getSNList { return; }
    $INC{'xCAT/ServiceNodeUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    $INC{'xCAT/NodeRange.pm'} = __FILE__;
}

require xCAT::Utils;
{
    no warnings 'redefine';
    *xCAT::Utils::osver  = sub { return 'rhels10'; };
    *xCAT::Utils::runcmd = sub { return; };
}

my $source_dhcp_plugin = repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm');
require $source_dhcp_plugin;

{
    package DDNSNetworksTable;
    sub new {
        my ( $class, @rows ) = @_;
        return bless { rows => [@rows] }, $class;
    }
    sub getAllAttribs {
        my ($self) = @_;
        return map { { %{$_} } } @{ $self->{rows} };
    }
    sub close { return; }
}

my %provision_network = (
    net         => '10.0.0.0',
    mask        => '255.255.255.0',
    nameservers => '10.0.0.1',
    domain      => 'cluster.test',
);

$xCAT::Table::networks = DDNSNetworksTable->new( \%provision_network );

# site.dnshandler decides whether Kea gets a D2 connection at all.
{
    local %::XCATSITEVALS = ( dnshandler => 'nsupdate' );
    my $ddns_intent = xCAT_plugin::dhcp::kea_build_ddns_intent();
    is(
        $ddns_intent,
        undef,
        'a management node that does not run ddns asks for no D2 configuration',
    );
}

# A new management node has site.dnshandler=ddns and no key: makedhcp -n must still
# render a configuration.
{
    local %::XCATSITEVALS = ( dnshandler => 'ddns' );
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_ddns_key = sub { return; };

    my $ddns_intent = xCAT_plugin::dhcp::kea_build_ddns_intent();
    ok( !$ddns_intent->{error}, 'a missing DDNS key is not an error' );
    like(
        $ddns_intent->{warning},
        qr/makedns -n/,
        'the deferral names the command that creates the key',
    );
    ok( !$ddns_intent->{'tsig-keys'}, 'no TSIG key is built without key material' );

    my %dhcp4 = ( subnets => [ { id => 1 } ] );
    my %dhcp6 = ( subnets => [ { id => 10001 } ] );
    my ( $using_ddns, $warning ) =
      xCAT_plugin::dhcp::kea_apply_ddns_intent( $ddns_intent, \%dhcp4, \%dhcp6, 1 );

    is( $using_ddns, 0, 'DNS updates stay off' );
    like(
        $warning,
        qr/DNS updates stay off until makedns -n runs/,
        'makedhcp -n warns that DNS updates stay off',
    );
    ok( !exists $dhcp4{'dhcp-ddns'},          'the DHCPv4 configuration carries no D2 connection' );
    ok( !exists $dhcp6{'dhcp-ddns'},          'the DHCPv6 configuration carries no D2 connection' );
    ok( !exists $dhcp4{'ddns-send-updates'},  'the DHCPv4 configuration requests no DNS update' );
    ok( !exists $dhcp4{'ddns-qualifying-suffix'}, 'the DHCPv4 configuration sets no DDNS suffix' );
}

# A management node on which makedns -n has run keeps the D2 connection.
{
    local %::XCATSITEVALS = ( dnshandler => 'ddns' );
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_ddns_key = sub { return ( 'HMAC-SHA256', 'c2VjcmV0' ); };

    my $ddns_intent = xCAT_plugin::dhcp::kea_build_ddns_intent();
    ok( !$ddns_intent->{warning}, 'key material defers nothing' );
    ok( !$ddns_intent->{error},    'key material reports no error' );
    is_deeply(
        $ddns_intent->{'tsig-keys'},
        [ { name => 'xcat_key', algorithm => 'HMAC-SHA256', secret => 'c2VjcmV0' } ],
        'the TSIG key comes from the key material',
    );
    is(
        $ddns_intent->{forward_domains}[0]{name},
        'cluster.test.',
        'the forward domain comes from the networks table',
    );

    my %dhcp4;
    my %dhcp6;
    my ( $using_ddns, $warning ) =
      xCAT_plugin::dhcp::kea_apply_ddns_intent( $ddns_intent, \%dhcp4, \%dhcp6, 1 );

    is( $using_ddns, 1,     'DNS updates stay on' );
    is( $warning,    undef, 'makedhcp -n warns about nothing' );
    is( $dhcp4{'dhcp-ddns'}{'server-port'}, 53001, 'the DHCPv4 configuration keeps the D2 connection' );
    is( $dhcp6{'dhcp-ddns'}{'server-port'}, 53001, 'the DHCPv6 configuration keeps the D2 connection' );
    ok( $dhcp4{'ddns-send-updates'}, 'the DHCPv4 configuration requests DNS updates' );

    my %v4_only;
    my %v6_untouched;
    xCAT_plugin::dhcp::kea_apply_ddns_intent( $ddns_intent, \%v4_only, \%v6_untouched, 0 );
    ok( exists $v4_only{'dhcp-ddns'},      'a cluster without DHCPv6 keeps the DHCPv4 D2 connection' );
    ok( !exists $v6_untouched{'dhcp-ddns'}, 'a cluster without DHCPv6 gets no DHCPv6 D2 connection' );
}

# The networks table is a different failure and stays an error.
{
    local %::XCATSITEVALS       = ( dnshandler => 'ddns' );
    local $xCAT::Table::networks = undef;
    my $ddns_intent = xCAT_plugin::dhcp::kea_build_ddns_intent();
    like(
        $ddns_intent->{error},
        qr/networks table/,
        'an unreadable networks table stays an error',
    );
}

done_testing();
