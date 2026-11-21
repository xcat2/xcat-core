#!/usr/bin/env perl
# The static IPv6 boot argument debian.pm gives an IPv6-only node.
#
# networks.gateway holds what the administrator wrote, and '<xcatmaster>' is the common value.
# It was passed to dracut_static_ip6 unresolved, so the command line carried
# "[<xcatmaster>]" in the gateway field. That is not an address, and a node whose image
# server sits off its own link had no route to it.
#
# static_ip6_boot_arg takes its two lookups as coderefs, so the composition is driven here
# while the real dracut_static_ip6 formats the result.
use strict;
use warnings;

use File::Spec;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

use xCAT::NetworkUtils;

my $plugin = File::Spec->catfile(
    $FindBin::Bin, '..', '..', 'xCAT-server', 'lib', 'xcat', 'plugins', 'debian.pm'
);
plan skip_all => "debian.pm not found" unless -f $plugin;

my $src = do { local $/; open my $fh, '<', $plugin or die $!; <$fh> };
my ($sub) = $src =~ /\n(sub static_ip6_boot_arg \{.*?\n\})\n/s;
die "could not extract static_ip6_boot_arg from debian.pm" unless defined $sub;

{
    package T;
    eval "$sub; 1" or die "could not eval static_ip6_boot_arg: $@";
}

# The placeholder is resolved before it reaches the boot argument.
{
    my @asked;
    my $cfg6    = sub { return ( '2001:db8::10', $_[0], '<xcatmaster>', 64 ) };
    my $resolve = sub { push @asked, [@_]; return '2001:db8::1' };
    is( T::static_ip6_boot_arg( 'cn1', { nicname => 'ens3' }, $cfg6, $resolve ),
        'rd.bootif=0 ip=[2001:db8::10]::[2001:db8::1]:64::ens3:none',
        'the gateway is resolved before it reaches the boot argument' );
    is_deeply( \@asked, [ [ 'cn1', '<xcatmaster>' ] ],
        '... through the helper that knows the placeholder' );
}

# A gateway that does not resolve is dropped, not written as a bad address.
{
    my $cfg6    = sub { return ( '2001:db8::10', $_[0], '<xcatmaster>', 64 ) };
    my $resolve = sub { return };
    my $arg = T::static_ip6_boot_arg( 'cn1', { nicname => 'ens3' }, $cfg6, $resolve );
    is( $arg, 'rd.bootif=0 ip=[2001:db8::10]:::64::ens3:none',
        'an unresolvable gateway leaves the field empty' );
    unlike( $arg, qr/xcatmaster/, '... and the placeholder does not reach the command line' );
}

# A literal address is passed through and bracketed.
{
    my $cfg6    = sub { return ( '2001:db8::10', $_[0], '2001:db8::fe', 64 ) };
    my $resolve = sub { return $_[1] };
    like( T::static_ip6_boot_arg( 'cn1', { nicname => 'ens3' }, $cfg6, $resolve ),
        qr/\Q::[2001:db8::fe]:\E/,
        'a literal gateway reaches the boot argument bracketed' );
}

# A node with no IPv6 address gets no argument, and the caller falls back.
{
    my $cfg6    = sub { return ( undef, $_[0], undef, undef ) };
    my $resolve = sub { return $_[1] };
    is( T::static_ip6_boot_arg( 'cn1', { nicname => 'ens3' }, $cfg6, $resolve ), undef,
        'a node with no address gets no argument' );
}

# grub2 adds BOOTIF= to every node. The systemd-network-generator of Ubuntu 26.04 then writes
# 70-BOOTIF.network, which sorts before the file that ip= names and carries no address, and it
# drops an ip= that names no interface. rd.bootif=0 removes that file, and a node with no
# installnic gets an interface name from its MAC, as on EL.
{
    my $cfg6    = sub { return ( '2001:db8::10', $_[0], '2001:db8::1', 64 ) };
    my $resolve = sub { return $_[1] };
    is( T::static_ip6_boot_arg( 'cn1', { mac => '52:54:00:AA:BB:CC' }, $cfg6, $resolve ),
        'ifname=xcatboot0:52:54:00:aa:bb:cc rd.bootif=0 '
          . 'ip=[2001:db8::10]::[2001:db8::1]:64::xcatboot0:none',
        'a node with no installnic names its boot interface by MAC' );
    is( T::static_ip6_boot_arg( 'cn1', { nicname => 'ens3', mac => '52:54:00:aa:bb:cc' },
            $cfg6, $resolve ),
        'rd.bootif=0 ip=[2001:db8::10]::[2001:db8::1]:64::ens3:none',
        '... and a node with an installnic keeps that name' );
    is( T::static_ip6_boot_arg( 'cn1', {}, $cfg6, $resolve ),
        'rd.bootif=0 ip=[2001:db8::10]::[2001:db8::1]:64:::none',
        'a node with no MAC still turns off BOOTIF=, so ip= is not dropped' );
}

done_testing();
