#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# go-xcat installs a fixed package list. On riscv64 that list asked for the amd64 and ppc64
# Genesis scripts and bases, so the supported install path put the x86 Genesis on a riscv64
# management node even though the xcat metapackage excludes it there.
#
# The x86 boot loaders are a different matter: they are payload the management node serves to x86
# nodes, so they belong on a riscv64 management node of a mixed cluster and must survive the filter.
#
# The function that builds the riscv64 list is taken from the shipped script and run, so the
# assertions read the package names go-xcat would hand to the package manager.

my $go_xcat = "$FindBin::Bin/../../xCAT-server/share/xcat/tools/go-xcat";
plan skip_all => 'go-xcat not found' unless -r $go_xcat;

my $tmpdir = tempdir( CLEANUP => 1 );
my $driver = "$tmpdir/driver.sh";
open( my $fh, '>', $driver ) or die "open $driver: $!";
print {$fh} <<'DRIVER';
#!/bin/bash
set -euo pipefail
eval "$(awk '
    $0 == "function riscv64_install_list()" { copy = 1 }
    copy { print }
    copy && /^}$/ { exit }
' "$GO_XCAT_SOURCE")"

# The real list, as go-xcat defines it for each package manager.
if [[ ${WITH_DPKG:-0} == 1 ]]; then
    dpkg() { :; }
    list=(perl-xcat xcat-client xcat xcat-buildkit
        xcat-genesis-scripts-amd64 xcat-genesis-scripts-ppc64 xcat-server
        elilo-xcat grub2-xcat ipmitool-xcat syslinux-xcat
        xcat-genesis-base-amd64 xcat-genesis-base-ppc64 xnba-undi)
else
    type() { return 1; }
    list=(perl-xCAT xCAT-client xCAT xCAT-buildkit
        xCAT-genesis-scripts-ppc64 xCAT-genesis-scripts-x86_64 xCAT-server
        elilo-xcat grub2-xcat ipmitool-xcat syslinux-xcat
        xCAT-genesis-base-ppc64 xCAT-genesis-base-x86_64 xnba-undi)
fi
riscv64_install_list "${list[@]}"
DRIVER
close($fh);
chmod 0755, $driver;

sub riscv64_list {
    my ($with_dpkg) = @_;
    my $out = `GO_XCAT_SOURCE='$go_xcat' WITH_DPKG=$with_dpkg bash '$driver' 2>&1`;
    is( $?, 0, "the riscv64 list builds (dpkg=$with_dpkg)" ) or diag($out);
    return [ grep { length } split( /\n/, $out ) ];
}

foreach my $case ( [ 1, 'deb', 'xcat-genesis-openembedded-riscv64', 'xcat-server' ],
                   [ 0, 'rpm', 'xCAT-genesis-openembedded-riscv64', 'xCAT-server' ] )
{
    my ( $with_dpkg, $name, $genesis, $server ) = @{$case};
    my $list = riscv64_list($with_dpkg);

    is_deeply( [ grep { /genesis-scripts-/i } @{$list} ], [],
        "$name: no legacy Genesis scripts on riscv64" );
    is_deeply( [ grep { /genesis-base-/i } @{$list} ], [],
        "$name: no legacy Genesis base on riscv64" );
    is_deeply( [ sort grep { /^(elilo-xcat|syslinux-xcat|xnba-undi)$/ } @{$list} ],
        [ sort qw(elilo-xcat syslinux-xcat xnba-undi) ],
        "$name: the x86 boot payload a mixed cluster needs is still installed" );

    ok( scalar( grep { $_ eq $genesis } @{$list} ),
        "$name: the riscv64 OpenEmbedded Genesis package is asked for" );

    # The filter must take nothing else with it.
    foreach my $keep ( $server, 'grub2-xcat', 'ipmitool-xcat' ) {
        ok( scalar( grep { $_ eq $keep } @{$list} ), "$name: $keep is still installed" );
    }
}

done_testing();
