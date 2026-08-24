#!/usr/bin/env perl
# The interface the INSTALLED system brings up must be resolved in xCAT's own order --
# noderes.installnic, else noderes.primarynic, else match on mac.mac -- and either attribute may
# hold an interface NAME or a MAC address. Treating an empty installnic as "mac" straight away
# skips primarynic entirely, so a node that configures only primarynic is provisioned with a
# netplan that matches on mac.mac and never renames the interface.
#
# Two halves are covered: the resolution itself (xCAT::Template, which delegates the order to
# xCAT::NetworkUtils::gen_net_boot_params rather than re-deriving it), and the netplan the
# template's late-command actually writes once rendered with the resolved values.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Temp qw(tempdir);
use Test::More;
use xCAT::Template;

my $NODE = 'node01';
my $NODE_MAC = 'AA:BB:CC:DD:EE:01';

# ---- resolution: installnic -> primarynic -> mac.mac, each of which may be a name or a MAC ------
my @cases = (
    {
        name       => 'installnic names an interface',
        installnic => 'ens4',
        primarynic => 'eno1',
        setname    => 'ens4',
        macaddress => 'aa:bb:cc:dd:ee:01',
        why        => 'renames the device matched by mac.mac',
    },
    {
        name       => 'installnic holds a MAC address',
        installnic => 'aa:bb:cc:dd:ee:02',
        primarynic => 'eno1',
        setname    => '',
        macaddress => 'aa:bb:cc:dd:ee:02',
        why        => 'matches that MAC and renames nothing',
    },
    {
        name       => 'installnic empty, primarynic names an interface',
        installnic => '',
        primarynic => 'eno1',
        setname    => 'eno1',
        macaddress => 'aa:bb:cc:dd:ee:01',
        why        => 'falls back to primarynic instead of skipping to mac',
    },
    {
        name       => 'installnic empty, primarynic holds a MAC address',
        installnic => '',
        primarynic => 'aa:bb:cc:dd:ee:03',
        setname    => '',
        macaddress => 'aa:bb:cc:dd:ee:03',
        why        => 'falls back to the primarynic MAC',
    },
    {
        name       => 'installnic and primarynic both unset',
        installnic => '',
        primarynic => '',
        setname    => '',
        macaddress => 'aa:bb:cc:dd:ee:01',
        why        => 'finally falls back to mac.mac',
    },
    {
        name       => 'installnic set to the literal "mac"',
        installnic => 'mac',
        primarynic => 'eno1',
        setname    => '',
        macaddress => 'aa:bb:cc:dd:ee:01',
        why        => 'is an explicit request to match by MAC, so primarynic is not consulted',
    },
);

for my $case (@cases) {
    my ($setname, $macaddress) = xCAT::Template::subiquity_install_netcfg(
        $case->{installnic}, $case->{primarynic}, $NODE_MAC, $NODE);
    is($setname, $case->{setname}, "$case->{name}: $case->{why} (set-name)");
    is($macaddress, $case->{macaddress}, "$case->{name}: $case->{why} (macaddress)");
}

# mac.mac carries |-separated, !hostname-suffixed entries; the netplan must match this node's.
{
    my $entry = "aa:bb:cc:dd:ee:09!other|aa:bb:cc:dd:ee:0a!$NODE";
    my (undef, $macaddress) =
      xCAT::Template::subiquity_install_netcfg('', '', $entry, $NODE);
    is($macaddress, 'aa:bb:cc:dd:ee:0a',
        'a multi-entry mac.mac resolves to this node\'s address, lower-cased');
}

# ---- rendering: run the template's own late-command and read the netplan it writes --------------
my $tmpl_path = defined $ENV{XCATROOT}
    ? "$ENV{XCATROOT}/share/xcat/install/ubuntu/compute.subiquity.tmpl" : '';
$tmpl_path = 'xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl'
    unless -f $tmpl_path;
$tmpl_path = "$FindBin::Bin/../../xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl"
    unless -f $tmpl_path;

SKIP: {
    skip 'compute.subiquity.tmpl not found', 4 unless -f $tmpl_path;
    my $tmpl = do { local $/; open my $fh, '<', $tmpl_path or die $!; <$fh> };

    # The netplan-writing part of late-commands, verbatim: from the resolved values down to the
    # chmod. Rendering it here is what proves the shell branches on what Perl resolved.
    my ($snippet) = $tmpl =~ /(installnic="#SUBIQUITYINSTALLNIC#".*?fi;)/s;
    ok($snippet, 'the netplan late-command is rendered from the resolved values');

    skip 'netplan late-command not found in the template', 3 unless $snippet;
    $snippet =~ s/''/'/g;    # undo the YAML single-quote escaping

    for my $case (
        { name => 'a resolved interface name', setname => 'eno1', mac => 'aa:bb:cc:dd:ee:01' },
        { name => 'no interface name',         setname => '',     mac => 'aa:bb:cc:dd:ee:03' },
      )
    {
        my $dir = tempdir(CLEANUP => 1);
        my $script = $snippet;
        $script =~ s/#SUBIQUITYINSTALLNIC#/$case->{setname}/g;
        $script =~ s/#SUBIQUITYINSTALLMAC#/$case->{mac}/g;
        $script =~ s{/target/}{$dir/target/}g;
        system('sh', '-c', "set -e\n$script") == 0
          or die "netplan late-command failed for $case->{name}\n";

        my $netplan = do {
            local $/;
            open my $fh, '<', "$dir/target/etc/netplan/00-xcat-install.yaml" or die $!;
            <$fh>;
        };
        my @expected = (
            'network:', '  version: 2', '  ethernets:', '    xcat-install:',
            '      match:', qq(        macaddress: "$case->{mac}"),
            ($case->{setname} ne '' ? "      set-name: $case->{setname}" : ()),
            '      dhcp4: true',
        );
        is($netplan, join("\n", @expected) . "\n",
            "the netplan written for $case->{name} matches the resolved values");
    }
}

done_testing();
