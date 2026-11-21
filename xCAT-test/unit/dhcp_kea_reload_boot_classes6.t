#!/usr/bin/env perl
# makedhcp updates the host reservations of a running Kea through the Control Agent, and restarts
# Kea only when the configuration changed in a way that the host commands cannot carry. A client
# class is such a change. The per-node DHCPv6 boot classes are client classes, so a change to them
# must restart Kea as a change to the DHCPv4 classes does. Otherwise a new class stays inactive
# and a deleted class stays active until the next restart.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG}  = 'SQLite:' . tempdir( CLEANUP => 1 );
}

use xCAT::DHCP::BootPolicy;
require( repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm') );

# A Kea backend whose live host commands succeed. It records the restarts.
{
    package ReloadBackend;
    our @restarts;
    sub new                      { return bless {}, shift; }
    sub load_dhcp4_config        { return { Dhcp4 => { subnet4 => [ { id => 1 } ] } }; }
    sub load_dhcp6_config        { return { Dhcp6 => { subnet6 => [ { id => 2 } ] } }; }
    sub delete_reservations      { return []; }
    sub upsert_reservations      { return; }
    sub encode_config            { return '{}'; }
    sub write_dhcp4_json         { return {}; }
    sub write_dhcp6_json         { return {}; }
    sub live_delete_reservations { return { ok => 1 }; }
    sub live_upsert_reservations { return { ok => 1 }; }
    sub restart_services         { push @restarts, { @_[ 1 .. $#_ ] }; return {}; }
}

# Which of the four class updates report a change.
our %changed;

sub makedhcp {
    my (%opt) = @_;
    @ReloadBackend::restarts = ();
    my @responses;
    no warnings 'redefine';
    local $xCAT_plugin::dhcp::callback = sub { push @responses, @_; };
    local $::XCATSITEVALS{externaldhcpservers};
    local *xCAT_plugin::dhcp::kea_build_dhcp4_intent       = sub { return {}; };
    local *xCAT_plugin::dhcp::kea_build_dhcp6_intent       = sub { return { subnets => [ { id => 2 } ] }; };
    local *xCAT_plugin::dhcp::kea_build_ddns_intent        = sub { return; };
    local *xCAT_plugin::dhcp::kea_apply_ddns_intent        = sub { return ( 0, undef ); };
    local *xCAT_plugin::dhcp::kea_expand_request_nodes     = sub { return ['cn1']; };
    local *xCAT_plugin::dhcp::kea_reservation_matches_for_nodes = sub { return [ { hostname => 'cn1' } ]; };
    local *xCAT_plugin::dhcp::kea_build_node_reservations  = sub { return []; };
    local *xCAT_plugin::dhcp::kea_build_node_reservations6 = sub { return []; };
    local *xCAT_plugin::dhcp::kea_sync_node_client_classes   = sub { return $changed{sync4} ? 1 : 0; };
    local *xCAT_plugin::dhcp::kea_remove_node_client_classes = sub { return $changed{remove4} ? 1 : 0; };
    local *xCAT_plugin::dhcp::kea_sync_node_boot_classes6    = sub { return $changed{sync6} ? 1 : 0; };
    local *xCAT_plugin::dhcp::kea_remove_node_boot_classes6  = sub { return $changed{remove6} ? 1 : 0; };
    local *xCAT_plugin::dhcp::kea_control_agent_live_enabled = sub { return 1; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled      = sub { return 1; };
    local *xCAT_plugin::dhcp::configure_router_advertisements = sub { return; };
    local *xCAT::DHCP::BootPolicy::kea_declare_ipxe_features = sub { return ( 0, undef ); };
    use warnings 'redefine';

    xCAT_plugin::dhcp::kea_process_request( ReloadBackend->new, { node => ['cn1'] }, \%opt, [], 0 );
    return scalar(@ReloadBackend::restarts);
}

{
    local %changed = ();
    is( makedhcp(), 0, 'makedhcp does not restart Kea when only the reservations change' );
}
{
    local %changed = ( sync4 => 1 );
    is( makedhcp(), 1, 'makedhcp restarts Kea when a DHCPv4 node class changes' );
}
{
    local %changed = ( sync6 => 1 );
    is( makedhcp(), 1, 'makedhcp restarts Kea when a DHCPv6 boot class is added' );
}
{
    local %changed = ( remove6 => 1 );
    is( makedhcp( d => 1 ), 1, 'makedhcp -d restarts Kea when a DHCPv6 boot class is removed' );
}

done_testing();
