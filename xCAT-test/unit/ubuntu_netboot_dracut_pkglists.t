#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# genimage enters dracut mode only when the rootimg carries dracut
# (xCAT-server/share/xcat/netboot/ubuntu/genimage). A netboot package list with no
# dracut falls back to the legacy /init, which waits for an "inet addr" line and cuts
# XCATSERVER at the first colon. Both are IPv4-only, so an IPv6-only diskless node
# never boots. The package list is the artifact that decides this.
#
# 24.04 x86_64 is the reference: it already carries the entries and boots IPv6-only.

use lib "$FindBin::Bin/../lib";
use XCAT::Test::File qw(repo_path);
use File::Slurper qw(read_lines);

my $netboot = 'xCAT-server/share/xcat/netboot/ubuntu';

my @lists = (
    "compute.ubuntu24.04.x86_64.pkglist",     # the working reference
    "compute.ubuntu24.04.ppc64el.pkglist",
    "compute.ubuntu24.04.ppc64le.pkglist",
    "compute.ubuntu26.04.pkglist",
    "compute.ubuntu26.04.ppc64el.pkglist",
    "compute.ubuntu26.04.ppc64le.pkglist",
    "compute.ubuntu26.04.riscv64.pkglist",
    "compute.ubuntu26.04.x86_64.pkglist",
);

sub packages {
    my ($name) = @_;
    my $path = repo_path("$netboot/$name");
    return unless -r $path;
    my @packages = grep { length && !/^#/ }
      map { my $line = $_; $line =~ s/\s+//g; $line } read_lines($path);
    return \@packages;
}

foreach my $name (@lists) {
    my $list = packages($name);
    ok($list, "$name is readable");

    SKIP: {
        skip "no $name to inspect", 2 unless $list;

        ok(scalar(grep { $_ eq 'dracut' } @{$list}),
            "$name installs dracut, so genimage enters dracut mode");
        ok(scalar(grep { $_ eq 'dracut-network' } @{$list}),
            "$name installs dracut-network, which brings the IPv6 boot modules");
    }
}

done_testing();
