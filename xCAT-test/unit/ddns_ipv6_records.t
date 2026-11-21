#!/usr/bin/env perl
# makedns on a dual-stack or IPv6-only cluster: the records it queues, the reverse zones it
# picks for a node, the named.conf it writes, and the host entries makehosts gives it.
#
# Every block runs the routine and reads what came out. Table, resolver and message access are
# Perl stubs; no file outside a temporary directory is written.
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }

# add_or_delete_records pauses one second after each zone update.
BEGIN { *CORE::GLOBAL::sleep = sub { return 0; }; }

use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

foreach my $plugin (qw(ddns hosts)) {
    my $path = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/$plugin.pm";
    if   (-f $path) { require $path }
    else            { require "xCAT_plugin/$plugin.pm" }
}

no warnings qw(once redefine);

my $V6_NET   = '2001:db8:7308::/62';
my $V6_ZONE  = '1.0.0.0.8.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.';
my $V4_ZONE  = '2.0.192.IN-ADDR.ARPA.';
my $DOMAIN   = 'example.com';

#---------------------------------------------------------------------------
# get_reverse_zones_for_entity: a node in an IPv6 network whose prefix is not a multiple of 4.
#
# process_request calls this routine for every node. getzonesfornet already splits a /62 into
# four /64 zones; this second copy died, and makedns stopped before any record was written.
#---------------------------------------------------------------------------
subtest 'a node in an IPv6 /62 gets the /64 reverse zone that holds it' => sub {
    my $ctx = {
        hoststab => { node01 => [ { ip => '2001:db8:7308:1::5' } ] },
        nets     => {
            $V6_NET => {
                mask => xCAT::NetworkUtils->getipaddr( 'ffff:ffff:ffff:fffc::', GetNumber => 1 ),
                netn => xCAT::NetworkUtils->getipaddr( '2001:db8:7308::',       GetNumber => 1 ),
            },
        },
    };
    my @zones = eval { xCAT_plugin::ddns::get_reverse_zones_for_entity( $ctx, 'node01' ) };
    is( $@, '', 'the /62 network does not abort makedns' );
    is_deeply( \@zones, [$V6_ZONE], 'the zone is the /64 of the node address' );
    ok( ( grep { $_ eq $V6_ZONE } xCAT_plugin::ddns::getzonesfornet( { net => $V6_NET } ) ),
        'getzonesfornet creates that same zone' );
};

#---------------------------------------------------------------------------
# find_nameserver_for_dns: an address outside every local reverse zone.
#
# The walk up the reverse name stops at IN-ADDR.ARPA. and never asks the resolver about it.
# ip6.arpa. and arpa. are written in lower case and the stop list is upper case, so the walk
# asked the resolver for the NS of the public ip6.arpa. zone.
#---------------------------------------------------------------------------
subtest 'the reverse walk does not ask for the NS of ip6.arpa.' => sub {
    my $resolver = Local::Resolver->new;
    my $address  = '2001:db8:ffff::1';
    my $ctx      = {
        currip        => $address,
        currname      => "node01.$DOMAIN",
        currnode      => 'node01',
        currrevname   => xCAT::NetworkUtils->getIPv6ReverseName($address),
        nodeips       => { node01 => {} },
        nsmap         => {},
        resolver      => $resolver,
        updatesbyzone => {},
    };
    local *xCAT::SvrUtils::sendmsg = sub { return; };
    xCAT_plugin::ddns::find_nameserver_for_dns( $ctx, $ctx->{currrevname} );

    ok( scalar( @{ $resolver->{queries} } ), 'the walk asked about the nibble zones' );
    ok( !( grep { lc($_) eq 'ip6.arpa.' } @{ $resolver->{queries} } ),
        'no NS query for ip6.arpa.' );
    ok( !( grep { lc($_) eq 'arpa.' } @{ $resolver->{queries} } ), 'no NS query for arpa.' );
    is_deeply( $ctx->{updatesbyzone}, {}, 'no update is queued' );

    # The control: the IPv4 walk stops before IN-ADDR.ARPA. already.
    my $v4 = Local::Resolver->new;
    my $ctx4 = { %$ctx, currip => '10.9.8.7', currrevname => '7.8.9.10.IN-ADDR.ARPA.',
        nsmap => {}, resolver => $v4, updatesbyzone => {} };
    xCAT_plugin::ddns::find_nameserver_for_dns( $ctx4, $ctx4->{currrevname} );
    ok( !( grep { uc($_) eq 'IN-ADDR.ARPA.' } @{ $v4->{queries} } ),
        'control: no NS query for IN-ADDR.ARPA.' );
};

#---------------------------------------------------------------------------
# add_or_delete_records: a dual-stack node whose hosts.ip is IPv4.
#
# The IPv6 address reaches $ctx->{nodeips} through the makehosts content. It is published as an
# AAAA beside the A, but the PTR loop walked only hosts.ip, so the IPv6 address had no PTR.
#---------------------------------------------------------------------------
subtest 'a dual-stack node with an IPv4 hosts.ip gets A, AAAA and both PTRs' => sub {
    my $ctx = dual_stack_ctx();
    run_records($ctx);
    my $fwd = $ctx->{updatesbyzone}->{"$DOMAIN."} || [];
    ok( ( grep { $_ eq "node01.$DOMAIN. IN A 192.0.2.10" } @$fwd ),    'A record' );
    ok( ( grep { $_ eq "node01.$DOMAIN. IN AAAA 2001:db8:7308:1::5" } @$fwd ), 'AAAA record' );
    is_deeply( $ctx->{updatesbyzone}->{$V4_ZONE},
        ["10.2.0.192.IN-ADDR.ARPA. IN PTR node01.$DOMAIN."], 'IPv4 PTR' );
    is_deeply(
        $ctx->{updatesbyzone}->{$V6_ZONE},
        [ xCAT::NetworkUtils->getIPv6ReverseName('2001:db8:7308:1::5') . " IN PTR node01.$DOMAIN." ],
        'IPv6 PTR'
    );
};

subtest 'makedns -d on that node deletes both PTRs' => sub {
    my $ctx = dual_stack_ctx();
    $ctx->{deletemode} = 1;
    run_records($ctx);
    ok( exists $ctx->{updatesbyzone}->{$V4_ZONE}, 'the IPv4 PTR is queued for deletion' );
    ok( exists $ctx->{updatesbyzone}->{$V6_ZONE}, 'the IPv6 PTR is queued for deletion' );
    ok( ( grep { $_ eq "node01.$DOMAIN. AAAA" } @{ $ctx->{updatesbyzone}->{"$DOMAIN."} } ),
        'every AAAA of the name is deleted' );
};

#---------------------------------------------------------------------------
# update_namedconf
#---------------------------------------------------------------------------
my $EL_OPTIONS = <<'EOF';
options {
	listen-on port 53 { 127.0.0.1; };
	listen-on-v6 port 53 { ::1; };
	directory 	"/var/named";
	allow-query     { localhost; };
	recursion yes;
};
EOF

# site.dnsinterfaces on an EL server whose named.conf is the distribution file. The rewrite
# matched "listen-on-v6 {" and the distribution writes "listen-on-v6 port 53 {", so the
# interface list was dropped and named kept listening on ::1 only.
subtest 'dnsinterfaces replaces the listen-on-v6 of the EL named.conf' => sub {
    my $out = run_namedconf(
        $EL_OPTIONS,
        dnslistenonifs => { ipv4 => [ '127.0.0.1', '192.0.2.53' ], ipv6 => [ '::1', '2001:db8::53' ] }
    );
    my ($options) = $out =~ /^(options \{.*?^\};)/ms;
    like( $options, qr/listen-on-v6 \{\s*::1;\s*2001:db8::53;\s*\};/,
        'listen-on-v6 names the interface address' );
    like( $options, qr/listen-on \{\s*127\.0\.0\.1;\s*192\.0\.2\.53;\s*\};/,
        'listen-on names the interface address' );
    unlike( $options, qr/\{ ::1; \};/, 'the distribution listen-on-v6 is gone' );
    like( $options, qr/^\s*directory\s/m,  'the line after a one-line block is kept' );
    like( $options, qr/^\s*recursion yes;/m, 'the rest of the options block is kept' );
};

# Without dnsinterfaces the existing options are kept as they are. This is also true for IPv4;
# makedns -n is the path that writes an options block without the distribution limits.
subtest 'makedns -n writes no listen-on-v6 or allow-query limit' => sub {
    my $out = run_namedconf( undef, forwarders => ['2001:db8::1'] );
    my ($options) = $out =~ /^(options \{.*?^\};)/ms;
    unlike( $options, qr/listen-on-v6/, 'no listen-on-v6: named listens on every IPv6 address' );
    unlike( $options, qr/allow-query/,  'no allow-query: IPv6 clients may query' );
    like( $options, qr/forwarders \{\s*2001:db8::1;\s*\};/, 'an IPv6 forwarder is written' );
};

# site.dnsupdaters on a new zone. The updaters were written after the allow-update block was
# closed, which named rejects as an unknown option in the zone.
subtest 'dnsupdaters are inside allow-update of a new zone' => sub {
    my $out = run_namedconf( undef, dnsupdaters => ['2001:db8::7'] );
    my ($zone) = $out =~ /^(zone "\Q$DOMAIN\E" in \{.*?^\};)/ms;
    ok( defined $zone, 'the zone is written' );
    like( $zone, qr/allow-update \{\s*key [^;]+;\s*2001:db8::7;\s*\};/,
        'the updater is in the allow-update list' );
};

#---------------------------------------------------------------------------
# makehosts content, which makedns <noderange> reads
#---------------------------------------------------------------------------

# A second address under the node name comes from hosts.otherinterfaces with the node name as
# the interface name.
subtest 'otherinterfaces gives the node name an IPv6 entry beside hosts.ip' => sub {
    is_deeply(
        hosts_content('node01!2001:db8:7308:1::5'),
        [ "192.0.2.10 node01 node01.$DOMAIN \n", "2001:db8:7308:1::5 node01 node01.$DOMAIN \n" ],
        'the "!" form'
    );
    # The ":" form split the address at its first colon, so the IPv6 entry was dropped.
    is_deeply(
        hosts_content('node01:2001:db8:7308:1::5'),
        [ "192.0.2.10 node01 node01.$DOMAIN \n", "2001:db8:7308:1::5 node01 node01.$DOMAIN \n" ],
        'the ":" form'
    );
};

# nics.nicips with the ":" separator. The address was cut at its first colon and the entry
# carried "2001" as its address, which makedns then rejects as malformed.
subtest 'nicips with the ":" separator keeps the IPv6 address' => sub {
    is_deeply( nics_content('eth1!2001:db8:7308:1::6'),
        ["2001:db8:7308:1::6 node01-eth1 node01-eth1.$DOMAIN \n"], 'the "!" form' );
    is_deeply( nics_content('eth1:2001:db8:7308:1::6'),
        ["2001:db8:7308:1::6 node01-eth1 node01-eth1.$DOMAIN \n"], 'the ":" form' );
};

done_testing();

#---------------------------------------------------------------------------

=head3 dual_stack_ctx

    Description: The makedns context of node01, hosts.ip 192.0.2.10, with 2001:db8:7308:1::5
                 from the makehosts content. The resolver names a server for the forward zone
                 and for both reverse zones.
    Returns:     the context

=cut

#---------------------------------------------------------------------------
sub dual_stack_ctx {
    return {
        nodes    => ['node01'],
        hoststab => { node01 => [ { ip => '192.0.2.10' } ] },
        nodeips  => { node01 => { '192.0.2.10' => 1, '2001:db8:7308:1::5' => 1 } },
        privkey  => 'c2VjcmV0',
        resolver => Local::Resolver->new( "$DOMAIN.", $V4_ZONE, $V6_ZONE ),
        omapi_settings => { key_name => 'xcat_key' },
    };
}

#---------------------------------------------------------------------------

=head3 run_records

    Description: Run add_or_delete_records with the name lookups and the update transport
                 stubbed. The queued records stay in $ctx->{updatesbyzone}.
    Arguments:   the context

=cut

#---------------------------------------------------------------------------
sub run_records {
    my ($ctx) = @_;
    local *xCAT::NetworkUtils::getNodeDomains = sub { return { node01 => $DOMAIN } };
    local *xCAT::NetworkUtils::getipaddr      = sub { return '192.0.2.53' };
    local *xCAT_plugin::ddns::ensure_ddns_key_file = sub { return };
    local *xCAT_plugin::ddns::send_ddns_update     = sub { return 0 };
    local *xCAT::SvrUtils::sendmsg = sub { return };
    xCAT_plugin::ddns::add_or_delete_records($ctx);
}

#---------------------------------------------------------------------------

=head3 run_namedconf

    Description: Run update_namedconf against a named.conf in a temporary directory.
    Arguments:   the starting named.conf, or undef for none (makedns -n); context fields
    Returns:     the named.conf it wrote

=cut

#---------------------------------------------------------------------------
sub run_namedconf {
    my ( $current, %fields ) = @_;
    my $dir  = tempdir( CLEANUP => 1 );
    my $conf = "$dir/named.conf";
    write_text( $conf, $current ) if defined $current;

    my $ctx = {
        omapi_settings => xCAT::DHCP::OmapiPolicy->settings(
            site_values => { dhcpomapialgorithm => 'hmac-sha256' }
        ),
        privkey      => 'c2VjcmV0',
        zonesdir     => $dir,
        zonestotouch => { $DOMAIN => 1 },
        %fields,
    };
    local *xCAT_plugin::ddns::get_conf             = sub { return $conf };
    local *xCAT_plugin::ddns::ensure_ddns_key_file = sub { return };
    local *xCAT::TableUtils::get_site_attribute    = sub { return () };
    local *xCAT::Utils::runcmd                     = sub { return () };
    local *xCAT::Table::new = sub { return bless {}, 'Local::Table' };
    xCAT_plugin::ddns::update_namedconf( $ctx, 0 );
    return read_text($conf);
}

#---------------------------------------------------------------------------

=head3 hosts_content

    Description: The host entries add_hosts_content gives makedns for node01, hosts.ip
                 192.0.2.10, with the given hosts.otherinterfaces.
    Arguments:   the otherinterfaces value
    Returns:     the non-empty host entries

=cut

#---------------------------------------------------------------------------
sub hosts_content {
    my ($other) = @_;
    local *xCAT_plugin::hosts::getIPdomain = sub { return ( $DOMAIN, 'net' ) };
    local *xCAT::Table::new = sub {
        return bless { rows => { node01 => [ { ip => '192.0.2.10', otherinterfaces => $other } ] } },
          'Local::Table';
    };
    xCAT_plugin::hosts::_set_host_lines( [] );
    my @content;
    xCAT_plugin::hosts::add_hosts_content( nodelist => ['node01'], callback => sub { },
        hostsref => \@content );
    return [ grep { /\S/ } @content ];
}

#---------------------------------------------------------------------------

=head3 nics_content

    Description: The host entries donics gives makedns for node01 with the given nics.nicips.
    Arguments:   the nicips value
    Returns:     the non-empty host entries

=cut

#---------------------------------------------------------------------------
sub nics_content {
    my ($nicips) = @_;
    local *xCAT_plugin::hosts::getIPdomain = sub { return ( $DOMAIN, 'net' ) };
    local *xCAT::Table::new = sub { return bless { nic => { nicips => $nicips } }, 'Local::Table' };
    xCAT_plugin::hosts::_set_host_lines( [] );
    my @content;
    xCAT_plugin::hosts::donics( nodes => ['node01'], callback => sub { }, hostsref => \@content );
    return [ grep { /\S/ } @content ];
}

{
    package Local::Table;
    sub getNodesAttribs { return $_[0]->{rows} }
    sub getNodeAttribs  { return $_[0]->{nic} }
    sub getAttribs      { return {} }
    sub setAttribs      { return 1 }
    sub close           { return 1 }
}

{
    # Records every NS query. Answers one NS record for each zone given to new, and nothing
    # for any other name.
    package Local::Resolver;
    sub new {
        my ( $class, @zones ) = @_;
        return bless { queries => [], zones => { map { $_ => 1 } @zones } }, $class;
    }
    sub query {
        my ( $self, $zone ) = @_;
        push @{ $self->{queries} }, $zone;
        return unless $self->{zones}->{$zone};
        return bless {}, 'Local::Reply';
    }

    package Local::Reply;
    sub header  { return $_[0] }
    sub rcode   { return 'NOERROR' }
    sub answer  { return $_[0] }
    sub nsdname { return 'ns.example.com' }
}
