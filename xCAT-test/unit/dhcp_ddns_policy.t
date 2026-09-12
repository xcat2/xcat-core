#!/usr/bin/env perl
#
# S-76, S-77 and S-78 of specs/dhcp-wire.md: who performs the DNS update, which
# zones and key it is aimed at, and what a cluster that does not use dynamic DNS
# has instead. All three are marked [config] in the specification, because no
# client can observe them -- a server answers a node correctly and still
# registers the wrong name, or registers nothing at all.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $plugin ) { require $plugin } else { require xCAT_plugin::dhcp }

BAIL_OUT('xCAT_plugin::dhcp::isc_ddns_zone_statements is missing')
  unless defined &xCAT_plugin::dhcp::isc_ddns_zone_statements;

sub isc_zones { return xCAT_plugin::dhcp::isc_ddns_zone_statements(@_) }

# ---------------------------------------------------------------------------
# S-77 -- ISC: the forward zone and every reverse zone, each with the key.

{
    my @lines = isc_zones(
        enabled    => 1,
        domain     => 'cluster.local.',
        ddnsdomain => undef,
        server     => '10.0.0.1',
        key_name   => 'xcat_key',
        zones      => [ '0.0.10.in-addr.arpa.', '1.0.10.in-addr.arpa.' ],
    );
    my $text = join '', @lines;

    like( $text, qr/zone cluster\.local\. \{/,
        'S-77 the forward zone is named' );
    like( $text, qr/zone 0\.0\.10\.in-addr\.arpa\. \{/,
        'S-77 the first reverse zone is named' );
    like( $text, qr/zone 1\.0\.10\.in-addr\.arpa\. \{/,
        'S-77 every reverse zone is named, not just the first' );
    is( scalar( grep { /primary 10\.0\.0\.1; key xcat_key;/ } @lines ), 3,
        'S-77 each of the three zones carries the server and the key' );
}

{
    # networks.ddnsdomain overrides site.domain for the forward zone, and is
    # also declared so dhcpd qualifies the name it registers.
    my @lines = isc_zones(
        enabled    => 1,
        domain     => 'cluster.local.',
        ddnsdomain => 'rack4.cluster.local',
        server     => '10.0.0.1',
        key_name   => 'xcat_key',
        zones      => [],
    );
    my $text = join '', @lines;
    like( $text, qr/ddns-domainname "rack4\.cluster\.local";/,
        'S-77 the network ddnsdomain is declared' );
    like( $text, qr/zone rack4\.cluster\.local\. \{/,
        'S-77 and is the forward zone' );
    unlike( $text, qr/zone cluster\.local\. \{/,
        'S-77 the site domain is not named as well' );
}

{
    # A zone dhcpd cannot reach, or reaches unsigned, is worse than no zone:
    # named refuses the update and nothing on the DHCP side says so.
    my $text = join '', isc_zones(
        enabled    => 1,
        domain     => 'cluster.local.',
        server     => '',
        key_name   => 'xcat_key',
        zones      => [],
    );
    unlike( $text, qr/primary/,
        'S-77 a network with no nameserver writes no primary statement' );

    $text = join '', isc_zones(
        enabled    => 1,
        domain     => 'cluster.local.',
        server     => '10.0.0.1',
        key_name   => undef,
        zones      => [],
    );
    unlike( $text, qr/key/,
        'S-77 an unsigned update is not configured either' );
}

# ---------------------------------------------------------------------------
# S-78 -- nothing at all when the cluster's DNS is not dynamic.

{
    is_deeply(
        [
            isc_zones(
                enabled    => 0,
                domain     => 'cluster.local.',
                ddnsdomain => 'rack4.cluster.local',
                server     => '10.0.0.1',
                key_name   => 'xcat_key',
                zones      => ['0.0.10.in-addr.arpa.'],
            )
        ],
        [],
        'S-78 dnshandler without ddns writes no zone and no key'
    );

    is_deeply(
        [ isc_zones( enabled => 1, domain => '', ddnsdomain => '',
                     server => '10.0.0.1', key_name => 'xcat_key' ) ],
        [],
        'S-78 a network with no domain of any kind names no zone'
    );
}

# ---------------------------------------------------------------------------
# S-76 -- the server updates DNS itself, whatever the client asked for.

{
    my %intent;
    xCAT_plugin::dhcp::kea_apply_ddns_behavior( \%intent );

    ok( $intent{'ddns-send-updates'},
        'S-76 Kea is told to send the updates' );
    ok( $intent{'ddns-override-client-update'},
        'S-76 and to send them for a client that asked to do its own' );
    ok( $intent{'ddns-override-no-update'},
        'S-76 and for a client that asked for none' );
    ok( $intent{'ddns-qualifying-suffix'},
        'S-76 the name it registers is qualified with a domain' );
}

# ISC says the same thing once, globally, with "ignore client-updates" in the
# preamble both configurations start from. dhcp_omapi_key_config.t asserts that
# statement is there; it is not repeated here.

# ---------------------------------------------------------------------------
# S-78 -- Kea: with dynamic DNS off there is no D2 intent to write at all.

{
    local %::XCATSITEVALS = ( dnshandler => 'ddns' );
    ok( xCAT_plugin::dhcp::kea_ddns_enabled(),
        'S-77 dnshandler naming ddns turns the Kea D2 configuration on' );

    %::XCATSITEVALS = ( dnshandler => 'makedns' );
    ok( !xCAT_plugin::dhcp::kea_ddns_enabled(),
        'S-78 any other dnshandler leaves it off' );

    %::XCATSITEVALS = ();
    ok( !xCAT_plugin::dhcp::kea_ddns_enabled(),
        'S-78 and an unset dnshandler leaves it off' );

    is( xCAT_plugin::dhcp::kea_build_ddns_intent(), undef,
        'S-78 no D2 intent is built when it is off' );
}

done_testing();
