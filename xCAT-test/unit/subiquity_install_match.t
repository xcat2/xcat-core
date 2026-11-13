#!/usr/bin/env perl
# The netplan match key of the Subiquity installer.
#
# Both autoinstall templates carried the literal glob name: "e*". A DHCPv4 node can take it: the
# lease is offered on one interface only, so the other candidates stay unaddressed. An IPv6-only
# node is given a static address instead, and three interfaces of one bridge all match "e*", so
# netplan put the same static address on each of them. The node then answered on whichever
# interface won, and the installer could not reach its package source. An IPv6-only node is
# matched by its own MAC.
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

my $NODE = 'cn7';
my %TAB  = (
    'noderes:installnic' => '',
    'noderes:primarynic' => '',
    'mac:mac'            => 'AA:BB:CC:DD:EE:07',
);

no warnings 'redefine';
local *xCAT::Template::tabdb = sub {
    my ($table, undef, $field) = @_;
    my $value = $TAB{"$table:$field"};
    return defined($value) ? $value : '';
};

sub match_for {
    my ($ipv6_only, $indent) = @_;
    local $xCAT::Template::node_ipv6_only = $ipv6_only;
    return xCAT::Template::subiquity_install_match($indent, $NODE);
}

# An IPv4 node keeps the glob the templates carried, byte for byte.
is( match_for( 0, 10 ), '          name: "e*"',
    'an IPv4 node matches every ethernet candidate, as before' );
is( match_for( 0, 8 ), '        name: "e*"',
    '... at whichever indent the tag asks for' );

# An IPv6-only node matches one interface, and netplan wants the address lower-cased.
is( match_for( 1, 10 ), '          macaddress: "aa:bb:cc:dd:ee:07"',
    'an IPv6-only node matches its own MAC, lower-cased' );
unlike( match_for( 1, 10 ), qr/name:/,
    '... and no longer every interface on the bridge' );
is( match_for( 1, 8 ), '        macaddress: "aa:bb:cc:dd:ee:07"',
    '... indented as the tag asks' );

# noderes.installnic is resolved by the same path the set-name key uses, so a MAC named there
# wins over mac.mac.
{
    local $TAB{'noderes:installnic'} = 'aa:bb:cc:dd:ee:09';
    is( match_for( 1, 10 ), '          macaddress: "aa:bb:cc:dd:ee:09"',
        'the MAC noderes.installnic names is the one netplan matches' );
}

# A node with no MAC cannot be matched at all. Rendering macaddress: "" gives the installer a
# netplan it cannot apply, and the install stops at the console.
{
    local $TAB{'mac:mac'} = '';
    is( match_for( 1, 10 ), '',
        'an IPv6-only node with no MAC renders no match key' );
}

# The templates ask for the tag, or the sub is dead code and the glob is still shipped.
foreach my $kind (qw(compute service)) {
    my $tmpl = File::Spec->catfile( $FindBin::Bin, '..', '..', 'xCAT-server', 'share',
        'xcat', 'install', 'ubuntu', "$kind.subiquity.tmpl" );
    SKIP: {
        skip "$kind.subiquity.tmpl not found", 3 unless -f $tmpl;
        my $text = read_text($tmpl);
        like( $text, qr/^#SUBIQUITYINSTALLMATCH:10#$/m,
            "$kind template asks for the match key" );
        unlike( $text, qr/name: "e\*"/,
            "$kind template carries no hardcoded interface glob" );
        like( $text, qr/^\s+match:\n#SUBIQUITYINSTALLMATCH:10#$/m,
            "$kind template puts the key under its own match block" );
    }
}

done_testing();
