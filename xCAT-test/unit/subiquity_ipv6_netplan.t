#!/usr/bin/env perl
# The netplan the Subiquity installer uses, and the one it writes into the installed system.
#
# Both said "dhcp4: true" for every node. An IPv6-only node has no DHCPv4 server to answer, so
# netplan brought the interface up with no address: the installer could not reach its package
# source and fell back to asking at the console, which on a serial console waits forever. The
# installed system had no address either, which is the same defect xcatroot had for a diskless
# node.
#
# DHCPv6 replaced that and was still wrong. A DHCPv6 client is identified by its DUID, so the
# installer took an address out of the dynamic range instead of the one makedhcp reserved. That
# address has no PTR record, and xcatd identifies a client over IPv6 only by the name its address
# resolves to, so post.xcat fetched a mypostscript that getpostscript could not build and the
# install stopped. Both netplans are static for an IPv6-only node now.
use strict;
use warnings;
no warnings 'once';

use File::Slurper qw(read_text);
use File::Spec;
use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use xCAT::Template;

my $NODE   = 'cn7';
my $ADDR   = '2001:db8:147::20';
my $PREFIX = 64;
my $MASTER = '2001:db8:147::1';

# The node's own network configuration, and the resolvers site.nameservers hands it. The IPv4
# resolver is in the list on purpose: an IPv6-only node cannot reach it, and an unreachable
# server in resolv.conf makes every lookup wait for its timeout.
my $cfg6        = [ $ADDR, $NODE, '<xcatmaster>', $PREFIX ];
my $nameservers = '<xcatmaster>,192.0.2.53';
my $DEFAULT_CFG6        = [ @$cfg6 ];
my $DEFAULT_NAMESERVERS = $nameservers;

no warnings 'redefine';
local *xCAT::NetworkUtils::getNodeNetworkCfg6 = sub {
    my $candidate = shift;
    $candidate = shift if defined($candidate) && $candidate eq 'xCAT::NetworkUtils';
    return @$cfg6;
};
local *xCAT::NetworkUtils::ipv6_server_for_node = sub {
    my $candidate = shift;
    $candidate = shift if defined($candidate) && $candidate eq 'xCAT::NetworkUtils';
    my $server = shift;
    return $MASTER if defined($server) && $server eq '<xcatmaster>';
    return $server;
};
local *xCAT::NetworkUtils::getNodeNameservers = sub {
    my $nodes = shift;
    $nodes = shift if defined($nodes) && $nodes eq 'xCAT::NetworkUtils';
    return { $nodes->[0] => $nameservers };
};

sub keys_for {
    my ($ipv6_only, $indent) = @_;
    local $xCAT::Template::node_ipv6_only = $ipv6_only;
    return xCAT::Template::subiquity_dhcp_keys($indent, $NODE);
}

sub target_for {
    my ($ipv6_only) = @_;
    local $xCAT::Template::node_ipv6_only = $ipv6_only;
    return xCAT::Template::subiquity_target_dhcp_keys($NODE);
}

# An IPv4 node keeps exactly what it had.
is( keys_for( 0, 8 ), '        dhcp4: true',
    'an IPv4 node is addressed with DHCPv4' );
is( target_for(0),
    '"      dhcp4: true" "      dhcp4-overrides:" "        use-domains: true"',
    'and the installed system too, byte for byte as before' );

# ---- the installer netplan of an IPv6-only node ------------------------------------------------
my $v6 = keys_for( 1, 8 );
is( $v6, <<'EOV6' =~ s/\n\z//r, 'an IPv6-only node is given its reserved address, statically' );
        dhcp4: false
        addresses: [2001:db8:147::20/64]
        routes:
          - to: default
            via: 2001:db8:147::1
        nameservers:
          addresses: [2001:db8:147::1]
EOV6
like( $v6, qr/^\s+addresses: \[\Q$ADDR\E\/$PREFIX\]$/m,
    '... with the prefix length netplan needs' );
like( $v6, qr/^\s+- to: default$/m, '... and a default route' );
like( $v6, qr/^\s+via: \Q$MASTER\E$/m, '... through the resolved IPv6 gateway' );
like( $v6, qr/^\s+addresses: \[\Q$MASTER\E\]$/m, '... resolving through the IPv6 resolver' );
unlike( $v6, qr/192\.0\.2\.53/,
    '... and not through the IPv4 resolver it cannot reach' );
like( $v6, qr/^\s+dhcp4: false$/m, '... with DHCPv4 turned off explicitly' );
unlike( $v6, qr/dhcp6/, '... asking for no DHCPv6, whose DUID matches no reservation' );
unlike( $v6, qr/dhcp4: true/, '... never asking for DHCPv4' );

# A literal resolver address is kept as it stands; only the IPv4 one is dropped.
{
    $nameservers = '2001:db8:147::53,192.0.2.53';
    my $literal = keys_for( 1, 8 );
    $nameservers = $DEFAULT_NAMESERVERS;
    like( $literal, qr/^\s+addresses: \[2001:db8:147::53\]$/m,
        'a resolver named by address is used as it stands' );
}

# A node with no address must fail the template rather than install and hang at post.xcat.
{
    $cfg6 = [ undef, $NODE, '<xcatmaster>', undef ];
    is( keys_for( 1, 8 ), '',
        'an IPv6-only node with no resolvable address renders nothing' );
    $cfg6 = [ @$DEFAULT_CFG6 ];
}

# A link with no gateway still reaches an install server on its own link.
{
    $cfg6 = [ $ADDR, $NODE, '', $PREFIX ];
    my $norouter = keys_for( 1, 8 );
    $cfg6 = [ @$DEFAULT_CFG6 ];
    like( $norouter, qr/^\s+addresses: \[\Q$ADDR\E\/$PREFIX\]$/m,
        'a node on a link with no gateway still gets its address' );
    unlike( $norouter, qr/routes:/, '... and no default route it cannot use' );
}

# ---- the netplan of the installed system -------------------------------------------------------
my $t6 = target_for(1);
is( $t6,
    '"      dhcp4: false" "      addresses: [2001:db8:147::20/64]" "      routes:"'
      . ' "        - to: default" "          via: 2001:db8:147::1" "      nameservers:"'
      . ' "        addresses: [2001:db8:147::1]"',
    'the installed system keeps the same static address' );
like( $t6, qr/"      addresses: \[\Q$ADDR\E\/$PREFIX\]"/,
    '... as a quoted printf argument' );
like( $t6, qr/"        - to: default"/, '... with the default route as its own argument' );
like( $t6, qr/"          via: \Q$MASTER\E"/, '... through the resolved gateway' );
unlike( $t6, qr/"      dhcp6: true"/,
    '... never asking for DHCPv6, which would take a third address' );
unlike( $t6, qr/dhcp4: true/, '... and never for DHCPv4' );

# The indent is what keeps the YAML valid where the tag sits.
is( keys_for( 0, 8 ), '        dhcp4: true', 'the keys are indented as the tag asks' );
is( keys_for( 0, 6 ), '      dhcp4: true', '... at whichever indent it asks for' );
like( keys_for( 1, 4 ), qr/^    dhcp4: false\n    addresses: /,
    'and the IPv6 form shares that indent' );

# The templates carry the tags rather than a literal, or the subs are dead code.
foreach my $kind (qw(compute service)) {
    my $tmpl = File::Spec->catfile( $FindBin::Bin, '..', '..', 'xCAT-server', 'share',
        'xcat', 'install', 'ubuntu', "$kind.subiquity.tmpl" );
    SKIP: {
        skip "$kind.subiquity.tmpl not found", 3 unless -f $tmpl;
        my $text = read_text($tmpl);
        like( $text, qr/#SUBIQUITYDHCP:\d+#/,
            "$kind template asks for the installer keys" );
        is( scalar( () = $text =~ /#SUBIQUITYTARGETDHCP#/g ), 2,
            "$kind template asks for the installed-system keys on both branches" );
        unlike( $text, qr/dhcp4: true/,
            "$kind template carries no hardcoded DHCPv4" );
    }
}

done_testing();
