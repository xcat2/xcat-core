#!/usr/bin/env perl
# xCAT cannot be installed on either openSUSE management node:
#
#   leap15.6: nothing provides 'perl-DB_File' needed by xCAT-server
#   sles12:   nothing provides (/usr/sbin/dhcpd if openEuler-release else
#             ((kea and kea-hooks) if (system-release >= 10) else /usr/sbin/dhcpd))
#             needed by xCAT
#
# Both requirements are written for EL and have no answer on openSUSE.
#
# perl-DB_File: no package of that name exists on Leap 15.6 or 42.3. Leap 15.6 calls it
# perl-core-DB_File and 42.3 has no such package either, but BOTH provide the capability
# perl(DB_File), so the capability is the portable name.
#
# The dhcpd expression: the sles12 cell is an openSUSE 42.3 management node whose rpm is 4.11,
# which has no rich dependencies -- it reports the whole expression as a capability nothing
# provides. Neither Leap release carries kea, and both carry chrony, ntp and ISC dhcpd, so the
# plain names are what these expressions resolve to on openSUSE anyway.
#
# A spec is a packaging manifest: the text IS the contract, there is nothing to execute, and
# these assertions are on package names in it. The build that proves the requirements resolve is
# the openSUSE core build plus the install step on each management node.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;
use File::Slurper qw(read_text);

my $root = "$RealBin/../..";

# Each entry: the spec, and what its openSUSE branch must and must not ask for.
my @cases = (
    {
        spec    => 'xCAT/xCAT.spec',
        require => [ 'chrony', '/usr/sbin/dhcpd' ],
    },
    {
        spec    => 'xCATsn/xCATsn.spec',
        require => [ '/usr/sbin/dhcpd' ],
    },
    {
        # openSUSE has no perl-generators, so no perl(...) requirement is auto-generated and the
        # modules each package loads must be named. Measured on xcat20-mn after a successful
        # install: xcatd stayed inactive because xCAT::Table dies loading JSON, and Date::Parse,
        # Expect, HTML::Form and SNMP were absent too. The other 80 modules the EL build
        # auto-requires were present. Each list below mirrors what EL's generator emits for that
        # package.
        spec    => 'xCAT-server/xCAT-server.spec',
        require => [ 'perl(DB_File)',
                     'perl(Date::Parse)', 'perl(Expect)', 'perl(JSON)', 'perl(SNMP)' ],
    },
    {
        spec    => 'perl-xCAT/perl-xCAT.spec',
        require => [ 'perl(Expect)', 'perl(HTML::Form)', 'perl(JSON)', 'perl(SNMP)' ],
    },
    {
        spec    => 'xCAT-client/xCAT-client.spec',
        require => [ 'perl(Expect)' ],
    },
);

for my $c (@cases) {
    my $path = "$root/$c->{spec}";
    ok(-f $path, "$c->{spec} exists") or next;
    my $text = read_text($path);

    # The openSUSE branch is the region guarded by %if 0%{?suse_version}. Collect those regions
    # so an assertion cannot be satisfied by a line that only EL ever sees.
    my @suse;
    my $depth = 0;
    for my $line (split /\n/, $text) {
        if ($line =~ /^\s*%if\s+0%\{\?suse_version\}/) { $depth = 1; next }
        if ($depth) {
            if ($line =~ /^\s*%(?:endif|else)/) { $depth = 0; next }
            push @suse, $line;
        }
    }
    my $suse = join "\n", @suse;

    for my $want (@{ $c->{require} }) {
        # a Requires: line may name several capabilities, so match the token anywhere on it
        my $found = grep { /^\s*Requires:/ && /(?:^|\s)\Q$want\E(?:\s|$)/ } @suse;
        ok($found, "$c->{spec} asks openSUSE for $want");
    }
}

subtest 'no rich dependency reaches an openSUSE build' => sub {
    # rpm 4.11 on the sles12 management node cannot evaluate one, and a single core build serves
    # both the sles15 and sles12 cells, so the openSUSE branch must carry none.
    for my $spec (qw(xCAT/xCAT.spec xCATsn/xCATsn.spec)) {
        my $path = "$root/$spec";
        my $text = read_text($path);
        my @suse;
        my $depth = 0;
        for my $line (split /\n/, $text) {
            if ($line =~ /^\s*%if\s+0%\{\?suse_version\}/) { $depth = 1; next }
            if ($depth) {
                if ($line =~ /^\s*%(?:endif|else)/) { $depth = 0; next }
                push @suse, $line;
            }
        }
        my @rich = grep { /^\s*Requires:\s*\(/ } @suse;
        is(scalar @rich, 0, "$spec gives openSUSE no rich dependency");
        diag("rich dependency in the openSUSE branch: $_") for @rich;
    }
};

# The EL and openEuler expressions must survive: this is an addition for openSUSE, not a
# replacement of the behaviour every other platform has today.
subtest 'EL and openEuler keep the expressions they have' => sub {
    my $xcat = read_text("$root/xCAT/xCAT.spec");
    like($xcat, qr/\Qif openEuler-release else\E/,
        'xCAT.spec still carries the openEuler/EL10 dhcpd expression');
    like($xcat, qr/\Q(chrony or ntp)\E/,
        'xCAT.spec still offers EL the choice of chrony or ntp');
    my $sn = read_text("$root/xCATsn/xCATsn.spec");
    like($sn, qr/\Qif openEuler-release else\E/,
        'xCATsn.spec still carries the openEuler/EL10 dhcpd expression');
    my $srv = read_text("$root/xCAT-server/xCAT-server.spec");
    like($srv, qr/^\s*Recommends:\s*perl-DB_File\s*$/m,
        'xCAT-server.spec still asks EL10 weakly for perl-DB_File');
};

done_testing();
