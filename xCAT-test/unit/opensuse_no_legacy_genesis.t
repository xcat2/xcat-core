#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Slurper qw(read_lines);
use Test::More;

use lib "$FindBin::Bin/../../build-utils/lib";
use XCAT::BuildUtils ();

# openSUSE ships no legacy Genesis. Operator decision, 2026-10-22, the same decision taken for
# openEuler on 2026-10-01.
#
# Two artifacts carry it. The build plan decides the (package, target) pairs buildrpms.pl
# builds, and xCAT-genesis-scripts carries the payload requirement that makes an install fail
# when the payload is absent.
#
# Measured 2026-10-22: sles/devel/xcat-dep has no common/ tree (repomd.xml 404, against 200 for
# the EL one), so no OpenEmbedded payload is published for the family either. Nothing in the
# openSUSE graph can satisfy the payload name.
my @opensuse_targets = qw(
    opensuse-leap-15.6-x86_64
    opensuse-leap-42.3-x86_64
    opensuse-leap-15.6-ppc64le
);
my @payload_targets = qw(
    alma+epel-8-x86_64
    alma+epel-9-x86_64
    alma+epel-10-x86_64
    alma+epel-10-ppc64le
    openeuler-22.03sp4-x86_64
);

my $decides = XCAT::BuildUtils->can('package_skip_reason');
ok($decides, 'BuildUtils decides which packages a target builds');

SKIP: {
    skip 'BuildUtils has no build-plan decision', 17 unless $decides;

    foreach my $target (@opensuse_targets) {
        ok($decides->('xCAT-genesis-base', $target),
            "xCAT-genesis-base is not built for $target");
    }

    foreach my $target (@payload_targets) {
        is($decides->('xCAT-genesis-base', $target), undef,
            "xCAT-genesis-base is built for $target");
    }

    # The gate names one package. openSUSE keeps every other package, including the scripts
    # half of Genesis: xCAT requires it, and dropping it would be a second decision.
    foreach my $pkg (qw(perl-xCAT xCAT xCATsn xCAT-client xCAT-server xCAT-probe
        xCAT-genesis-scripts xCAT-test xCAT-release)) {
        is($decides->($pkg, 'opensuse-leap-15.6-x86_64'), undef,
            "$pkg is built for openSUSE");
    }
}

# zypper install xCAT reaches this requirement through xCAT-genesis-scripts. An openSUSE core
# that states it cannot install at all, because no repository the family reads carries the
# payload.
my $root = "$FindBin::Bin/../..";
my @lines = read_lines("$root/xCAT-genesis-scripts/xCAT-genesis-scripts.spec");
my ($index) = grep {
    $lines[$_] =~ /^Requires:\s*xCAT-genesis-base-%\{tarch\}\s*>=\s*2:2\.18\.0\s*$/
} 0 .. $#lines;
ok(defined $index, 'xCAT-genesis-scripts requires the legacy Genesis payload');

my $if = defined $index ? $lines[$index - 1] : '';
like($if, qr/^%if\b/, '... behind a condition');
like($if, qr/\Q0%{?suse_version}\E/, '... that reads suse_version');
like($if, qr/^%if\s*!/, '... and excludes openSUSE rather than selecting it');

done_testing();
