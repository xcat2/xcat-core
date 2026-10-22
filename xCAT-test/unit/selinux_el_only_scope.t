#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Slurper qw(read_lines);
use Test::More;

use lib "$FindBin::Bin/../../build-utils/lib";
use XCAT::BuildUtils ();

# SELinux support is EL only. Two artifacts carry that scope: the build plan,
# which decides the (package, target) pairs buildrpms.pl builds, and the two
# specs that make a management node or a service node pull xCAT-selinux in.
#
# Measured 2026-10-22 in mock chroots: openEuler 20.03sp4 and 22.03sp4 carry
# selinux-policy 3.14.2 and cannot compile the module, 24.03sp4 carries 40.7
# and can. 24.03sp4 is excluded as well, so no openEuler release ships a
# package the other releases cannot build.
my @openeuler_targets = qw(
    openeuler-20.03sp4-x86_64
    openeuler-22.03sp4-x86_64
    openeuler-24.03sp4-x86_64
    openeuler-24.03-ppc64le
);
my @el_targets = qw(
    alma+epel-8-x86_64
    alma+epel-9-x86_64
    alma+epel-10-x86_64
    alma+epel-10-ppc64le
);

my $decides = XCAT::BuildUtils->can('package_skip_reason');
ok($decides, 'BuildUtils decides which packages a target builds');

SKIP: {
    skip 'BuildUtils has no build-plan decision', 17 unless $decides;

    foreach my $target (@openeuler_targets) {
        ok($decides->('xCAT-selinux', $target),
            "xCAT-selinux is not built for $target");
    }

    foreach my $target (@el_targets) {
        is($decides->('xCAT-selinux', $target), undef,
            "xCAT-selinux is built for $target");
    }

    # The gate names one package. Every other package keeps every target.
    foreach my $pkg (qw(perl-xCAT xCAT xCATsn xCAT-client xCAT-server xCAT-probe
        xCAT-genesis-scripts xCAT-test xCAT-release)) {
        is($decides->($pkg, 'openeuler-22.03sp4-x86_64'), undef,
            "$pkg is built for openEuler");
    }
}

# A node that resolves this dependency on openEuler cannot install xCAT, because
# the package is no longer in the repository. openEuler defines %openEuler and
# no %rhel, so the condition must not name openEuler.
my $root = "$FindBin::Bin/../..";
foreach my $pkg (qw(xCAT-server xCATsn)) {
    my @lines = read_lines("$root/$pkg/$pkg.spec");
    my ($index) = grep {
        $lines[$_] =~ /^Requires:\s*\(xCAT-selinux = 4:%\{version\}-%\{release\} if selinux-policy-targeted\)\s*$/
    } 0 .. $#lines;
    ok(defined $index, "$pkg requires xCAT-selinux when selinux-policy-targeted is installed");

    my $if = defined $index ? $lines[$index - 1] : '';
    like($if, qr/^%if\b/, "... behind a condition");
    like($if, qr/0%\{\?rhel\} >= 8/, "... that holds on EL 8 and later");
    unlike($if, qr/openEuler/i, "... and not on openEuler");
}

done_testing();
