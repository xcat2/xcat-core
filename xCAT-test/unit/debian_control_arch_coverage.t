#!/usr/bin/env perl
# xCAT and xCATsn name their Debian architectures explicitly. An architecture missing from that
# list is not a build failure -- it is a package that never exists: apt on that architecture says
#
#   E: Unable to locate package xcat
#
# and the management node cannot be installed at all. riscv64 was missing while the rest of the
# tree already carried riscv64 install templates, DHCP boot policy and a Genesis machine config.
#
# The list is compared against the architectures the DEB build itself supports, taken from
# build-utils/lib/XCAT/BuildUtils or, failing that, the documented set.
use strict;
use warnings;

use FindBin;
use Test::More;

my $root = "$FindBin::Bin/../..";

# The Debian architectures xCAT ships. dpkg names, not rpm ones.
my @arches = qw(amd64 ppc64el riscv64);

my @controls = grep { -f } ("$root/xCAT/debian/control", "$root/xCATsn/debian/control");
plan skip_all => 'no Debian control files in this tree' unless @controls;

for my $ctl (@controls) {
    open my $fh, '<', $ctl or die "read $ctl: $!";
    local $/; my $text = <$fh>; close $fh;
    (my $short = $ctl) =~ s{^\Q$root\E/}{};
    my @lines = ($text =~ /^Architecture:\s*(.+)$/mg);
    my @explicit = grep { !/^(?:any|all)$/ } map { s/^\s+|\s+$//gr } @lines;
    ok(scalar(@explicit), "$short names architectures explicitly") or next;
    for my $line (@explicit) {
        my %have = map { $_ => 1 } split /\s+/, $line;
        my @missing = grep { !$have{$_} } @arches;
        is_deeply(\@missing, [], "$short covers @arches");
    }
}

done_testing();
