#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

foreach my $spec ('xCAT/xCAT.spec', 'xCATsn/xCATsn.spec') {
    foreach my $build (
        ['EL8', 'rhel 8'], ['EL9', 'rhel 9'], ['EL10', 'rhel 10'],
        ['SLES15', 'suse_version 1500'], ['openEuler', 'openEuler 1'],
    ) {
        foreach my $arch (qw(x86_64 ppc64le aarch64 s390x riscv64)) {
            open(my $fh, '-|', $rpmspec, '-q', '--requires', '--target', $arch,
                '--define', 'version 2.20.0', '--define', 'release 1',
                '--undefine', 'rhel', '--undefine', 'suse_version',
                '--undefine', 'openEuler', '--define', $build->[1],
                repo_path($spec)) or die "run rpmspec: $!";
            my @requires = <$fh>;
            close($fh) or BAIL_OUT("rpmspec failed for $spec on $build->[0]/$arch");
            chomp @requires;
            is_deeply(
                [grep { /\bdhcp-server\b/ } @requires], [],
                "$spec built on $build->[0]/$arch adds no SHA-only DHCP package floor"
            );
            is(scalar(grep { m{/usr/sbin/dhcpd} } @requires), 1,
                "$spec built on $build->[0]/$arch retains its DHCP backend requirement");
        }
    }
}

done_testing();
