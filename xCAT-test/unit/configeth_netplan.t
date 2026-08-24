#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# Regression (issue #7454): on Ubuntu 18.04+ the network is rendered by netplan. ifupdown is
# not installed and /etc/network/interfaces.d/* is ignored entirely, so configeth's Debian
# branch configured nothing at all. It must write /etc/netplan/*.yaml and `netplan apply`.
#
# Three things the writer has to get right, all of which a naive in-place editor gets wrong:
#
#   * A VLAN interface (<parent>.<vid>) belongs under `vlans:` with `id` and `link`. Declared
#     as a plain ethernet it is never recreated after a reboot.
#   * Multiple addresses on one NIC must keep the order they were added.
#   * Routes must be idempotent on the whole (to, via) pair -- not on either field alone, or a
#     second route sharing a gateway is silently swallowed.
#
# nicextraparams must survive too: the ifupdown branch writes them into the interface stanza,
# so dropping them on netplan nodes would silently discard requested configuration.
#
# Drives the real functions: they are extracted from configeth and run against a temp
# NETPLAN_DIR, so this tracks the script rather than a copy of it.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $configeth = File::Spec->catfile( $repo_root, 'xCAT', 'postscripts', 'configeth' );
plan skip_all => "configeth not found" unless -f $configeth;

my $src = do { local $/; open my $fh, '<', $configeth or die $!; <$fh> };

my ($helpers) = $src =~ /^(netplan_active=0\n.*?\n\})\n+function configipv4/ms;
ok( defined $helpers, 'extracted the netplan helpers from configeth' )
  or do { done_testing(); exit };

my $dir = tempdir( CLEANUP => 1 );

sub run_netplan {
    my ($script) = @_;
    my $harness = File::Spec->catfile( $dir, 'harness.sh' );
    open my $fh, '>', $harness or die $!;
    print $fh "#!/bin/bash\nstr_default_token='XCAT_DEFAULT'\nexport NETPLAN_DIR='$dir'\n";
    print $fh "$helpers\n$script\n";
    close $fh;
    system( '/bin/bash', $harness ) == 0 or die "harness failed";
    return;
}

sub slurp_yaml {
    my ($nic) = @_;
    my $f = File::Spec->catfile( $dir, "90-xcat-$nic.yaml" );
    return '' unless -f $f;
    local $/;
    open my $fh, '<', $f or die $!;
    my $c = <$fh>;
    # the "# xcat-state:" lines are this writer's own bookkeeping, not netplan config
    $c =~ s/^# xcat-state:.*\n//mg;
    return $c;
}

# --- a plain ethernet, two addresses, an mtu and an extra param ---------------
run_netplan( <<'SH' );
write_netplan_addr eth0 10.0.0.5/24 1500
write_netplan_addr eth0 10.0.1.5/24
write_netplan_param eth0 optional true
write_netplan_route eth0 default 10.0.0.1
write_netplan_route eth0 default 10.0.0.1
write_netplan_route eth0 192.168.5.0/24 10.0.0.1
SH

my $eth0 = slurp_yaml('eth0');

like( $eth0, qr/^  ethernets:$/m, 'a plain NIC is declared under ethernets:' );
unlike( $eth0, qr/^  vlans:$/m,   'a plain NIC is not declared as a vlan' );
like( $eth0, qr/addresses:\n\s*- 10\.0\.0\.5\/24\n\s*- 10\.0\.1\.5\/24/,
    'multiple addresses keep the order they were added' );
like( $eth0, qr/^      mtu: 1500$/m, 'the mtu is written' );
like( $eth0, qr/^      optional: true$/m,
    'nicextraparams are written into the interface stanza' );

my @default_routes = ( $eth0 =~ /- to: default/g );
is( scalar(@default_routes), 1, 'an identical route added twice appears once' );
like( $eth0, qr/- to: 192\.168\.5\.0\/24\n\s*via: 10\.0\.0\.1/,
    'a second route sharing the same gateway is still written' );

# --- a VLAN interface ---------------------------------------------------------
run_netplan( <<'SH' );
write_netplan_addr eth0.100 10.100.0.5/24
SH

my $vlan = slurp_yaml('eth0.100');

like( $vlan, qr/^  vlans:$/m, 'a <parent>.<vid> NIC is declared under vlans:' );
unlike( $vlan, qr/^  ethernets:$/m, 'a VLAN is not declared as an ethernet' );
like( $vlan, qr/^      id: 100$/m,     'the VLAN carries its id' );
like( $vlan, qr/^      link: eth0$/m,  'the VLAN is linked to its parent interface' );

# --- a dotted name that is NOT a vlan ----------------------------------------
run_netplan( <<'SH' );
write_netplan_addr eno1.custom 10.9.0.5/24
SH
like( slurp_yaml('eno1.custom'), qr/^  ethernets:$/m,
    'a dotted name with a non-numeric suffix is not treated as a VLAN' );

# --- and netplan itself must accept what we wrote -----------------------------
SKIP: {
    my $netplan = `command -v netplan 2>/dev/null`;
    chomp $netplan;
    skip 'netplan not installed', 1 unless $netplan && -x $netplan;
    my $out = `netplan generate --root-dir '$dir' 2>&1`;
    is( $? >> 8, 0, "netplan generate accepts the generated configuration" )
      or diag($out);
}

done_testing();
