use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use File::Slurper qw(read_text);
use File::Temp qw(tempdir);
use JSON;
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

# Recovery on a new management node: makedhcp -n before makedns -n, then makedhcp -a.
{
    require xCAT::DHCP::Backend::Kea;

    my $dir     = tempdir( CLEANUP => 1 );
    my $backend = xCAT::DHCP::Backend::Kea->new(
        dhcp4_config_file      => "$dir/kea-dhcp4.conf",
        dhcp6_config_file      => "$dir/kea-dhcp6.conf",
        ddns_config_file       => "$dir/kea-dhcp-ddns.conf",
        ctrl_agent_config_file => "$dir/kea-ctrl-agent.conf",
    );

    my @restarts;
    my @warnings;
    my @errors;
    my $key_secret;

    no warnings 'redefine';
    local %::XCATSITEVALS = ( dnshandler => 'ddns' );
    local *xCAT::DHCP::Backend::Kea::_validate_config_with = sub { return { output => '' }; };
    local *xCAT::DHCP::Backend::Kea::restart_services = sub {
        my ( $self, %opts ) = @_;
        push @restarts, \%opts;
        return {};
    };
    local *xCAT_plugin::dhcp::kea_build_dhcp4_intent = sub {
        return {
            interfaces => ['eth0'],
            subnets    => [ { id => 1, subnet => '10.0.0.0/24' } ],
        };
    };
    local *xCAT_plugin::dhcp::kea_build_dhcp6_intent     = sub { return { subnets => [] }; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled  = sub { return 0; };
    local *xCAT_plugin::dhcp::kea_expand_request_nodes   = sub { return []; };
    local *xCAT_plugin::dhcp::kea_build_node_reservations = sub { return []; };
    local *xCAT_plugin::dhcp::kea_ddns_key = sub {
        return $key_secret ? ( 'HMAC-SHA256', $key_secret ) : ();
    };
    local *xCAT::MsgUtils::message = sub { return; };
    local *xCAT::MsgUtils::trace   = sub { return; };

    # process_request is the only way to set the plugin callback.
    my $saved_umask      = umask;
    my $saved_ignorecase = $Getopt::Long::ignorecase;
    {
        local @ARGV;
        xCAT_plugin::dhcp::process_request(
            { _xcatpreprocessed => [0], arg => [ '-q', '-a' ] },
            sub {
                my $response = shift;
                push @warnings, @{ $response->{warning} || [] };
                push @errors,   @{ $response->{error}   || [] };
            }
        );
    }
    umask $saved_umask;
    $Getopt::Long::ignorecase = $saved_ignorecase;
    Getopt::Long::Configure('pass_through');
    @warnings = ();
    @errors   = ();

    xCAT_plugin::dhcp::kea_process_request( $backend, {}, { n => 1 }, { eth0 => 1 }, 0 );
    my $dhcp4 = decode_json( read_text("$dir/kea-dhcp4.conf") );
    ok( !exists $dhcp4->{Dhcp4}{'dhcp-ddns'}, 'makedhcp -n without a key writes no D2 connection' );
    ok( !-e "$dir/kea-dhcp-ddns.conf",         'makedhcp -n without a key writes no D2 configuration' );
    is( scalar(@warnings), 1, 'makedhcp -n without a key warns once' );

    # makedns -n writes the key.
    $key_secret = 'c2VjcmV0';
    @warnings   = ();
    @restarts   = ();

    xCAT_plugin::dhcp::kea_process_request( $backend, {}, { a => 1 }, { eth0 => 1 }, 0 );
    is_deeply( \@errors,   [], 'makedhcp -a after makedns -n reports no error' );
    is_deeply( \@warnings, [], 'makedhcp -a after makedns -n warns about nothing' );

    $dhcp4 = decode_json( read_text("$dir/kea-dhcp4.conf") );
    is( $dhcp4->{Dhcp4}{'dhcp-ddns'}{'server-port'}, 53001, 'makedhcp -a adds the D2 connection to the DHCPv4 configuration' );
    ok( $dhcp4->{Dhcp4}{'ddns-send-updates'}, 'makedhcp -a turns on DNS updates in the DHCPv4 configuration' );
    is( $dhcp4->{Dhcp4}{subnet4}[0]{subnet}, '10.0.0.0/24', 'makedhcp -a keeps the subnets of the loaded configuration' );

    ok( -e "$dir/kea-dhcp-ddns.conf", 'makedhcp -a writes the D2 configuration' );
    my $d2 = -e "$dir/kea-dhcp-ddns.conf" ? decode_json( read_text("$dir/kea-dhcp-ddns.conf") ) : {};
    is( $d2->{DhcpDdns}{'tsig-keys'}[0]{secret}, 'c2VjcmV0', 'the D2 configuration carries the key that makedns -n wrote' );
    is( $d2->{DhcpDdns}{'forward-ddns'}{'ddns-domains'}[0]{name}, 'cluster.test.', 'the D2 configuration carries the forward domain' );

    ok( $restarts[-1]{ddns},   'makedhcp -a starts kea-dhcp-ddns' );
    ok( $restarts[-1]{enable}, 'makedhcp -a enables kea-dhcp-ddns' );
}

done_testing();
