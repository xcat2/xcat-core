#!/usr/bin/env perl
# The netplan the Subiquity installer uses, and the one it writes into the installed system.
#
# Both said "dhcp4: true" for every node. An IPv6-only node has no DHCPv4 server to answer, so
# netplan brought the interface up with no address: the installer could not reach its package
# source and fell back to asking at the console, which on a serial console waits forever. The
# installed system had no address either, which is the same defect xcatroot had for a diskless
# node.
use strict;
use warnings;

use File::Spec;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

my $template = File::Spec->catfile(
    $FindBin::Bin, '..', '..', 'xCAT-server', 'lib', 'perl', 'xCAT', 'Template.pm'
);
plan skip_all => "Template.pm not found" unless -f $template;

# The subs read the file-scoped $node_ipv6_only that subvars sets, so they are driven by
# setting it rather than by stubbing a lookup.
require $template;

sub keys_for {
    my ($ipv6_only, $indent) = @_;
    no warnings 'once';
    local $xCAT::Template::node_ipv6_only = $ipv6_only;
    return xCAT::Template::subiquity_dhcp_keys($indent);
}

sub target_for {
    my ($ipv6_only) = @_;
    no warnings 'once';
    local $xCAT::Template::node_ipv6_only = $ipv6_only;
    return xCAT::Template::subiquity_target_dhcp_keys();
}

# An IPv4 node keeps exactly what it had.
is( keys_for( 0, 8 ), '        dhcp4: true',
    'an IPv4 node is addressed with DHCPv4' );
is( target_for(0),
    '"      dhcp4: true" "      dhcp4-overrides:" "        use-domains: true"',
    'and the installed system too, byte for byte as before' );

# An IPv6-only node asks for DHCPv6 and says so for IPv4, because netplan defaults
# dhcp4 to false only when nothing names it.
my $v6 = keys_for( 8, 8 );
like( $v6, qr/^\s+dhcp6: true$/m, 'an IPv6-only node is addressed with DHCPv6' );
like( $v6, qr/^\s+dhcp4: false$/m, '... and DHCPv4 is turned off explicitly' );
unlike( $v6, qr/dhcp4: true/, '... never asking for DHCPv4' );

my $t6 = target_for(1);
like( $t6, qr/dhcp6: true/, 'the installed system is addressed with DHCPv6' );
like( $t6, qr/dhcp4: false/, '... with DHCPv4 off' );
like( $t6, qr/dhcp6-overrides/, '... and the overrides follow the family it uses' );
unlike( $t6, qr/"      dhcp4: true"/, '... never asking for DHCPv4' );

# The indent is what keeps the YAML valid where the tag sits.
is( keys_for( 0, 6 ), '      dhcp4: true', 'the keys are indented as the tag asks' );
like( keys_for( 1, 4 ), qr/^    dhcp6: true\n    dhcp4: false$/,
    'and both lines of the IPv6 form share that indent' );

# The templates carry the tags rather than a literal, or the subs are dead code.
foreach my $kind (qw(compute service)) {
    my $tmpl = File::Spec->catfile( $FindBin::Bin, '..', '..', 'xCAT-server', 'share',
        'xcat', 'install', 'ubuntu', "$kind.subiquity.tmpl" );
    SKIP: {
        skip "$kind.subiquity.tmpl not found", 3 unless -f $tmpl;
        my $text = do { local ( @ARGV, $/ ) = ($tmpl); <> };
        like( $text, qr/#SUBIQUITYDHCP:\d+#/,
            "$kind template asks for the installer keys" );
        is( scalar( () = $text =~ /#SUBIQUITYTARGETDHCP#/g ), 2,
            "$kind template asks for the installed-system keys on both branches" );
        unlike( $text, qr/dhcp4: true/,
            "$kind template carries no hardcoded DHCPv4" );
    }
}

done_testing();
