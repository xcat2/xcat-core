#!/usr/bin/env perl
# The packages that build man pages must declare, on openSUSE, something that ships pod2man.
#
# An openSUSE build root installs only perl-base, which does not ship pod2man, and xpod2man runs
# it in %build. The four specs below guarded "BuildRequires: perl-Pod-Html" with
# "%if !0%{?suse_version}" and declared nothing in its place, so every one of them failed with
# "pod2man: command not found" and buildrpms.pl refused to index a partial repository.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

# The packages whose %build runs xpod2man.
my @SPECS = qw(
    xCAT-buildkit/xCAT-buildkit.spec
    xCAT-client/xCAT-client.spec
    xCAT-test/xCAT-test.spec
    xCAT-vlan/xCAT-vlan.spec
);

# build_requires <spec> <define> -- the BuildRequires of one spec for one distro
sub build_requires {
    my ($spec, $define) = @_;
    open(my $fh, '-|', $rpmspec, '-q', '--buildrequires', '--target', 'x86_64',
        '--define', 'version 2.20.0', '--define', 'release 1',
        '--undefine', 'rhel', '--undefine', 'suse_version', '--undefine', 'openEuler',
        '--define', $define, repo_path($spec)) or die "run rpmspec: $!";
    my @requires = <$fh>;
    close($fh) or die "rpmspec failed for $spec with $define";
    chomp @requires;
    return @requires;
}

foreach my $spec (@SPECS) {
    my @suse = build_requires($spec, 'suse_version 1500');
    # perl-base is not enough: the full perl package is what carries pod2man there.
    is(scalar(grep { $_ eq 'perl' } @suse), 1,
        "$spec requires perl on openSUSE, which ships pod2man");

    # The EL side is unchanged: there perl-Pod-Html pulls in the man page tooling.
    my @el = build_requires($spec, 'rhel 10');
    is(scalar(grep { $_ eq 'perl-Pod-Html' } @el), 1,
        "$spec keeps perl-Pod-Html on EL");
    is(scalar(grep { $_ eq 'perl' } @el), 0,
        "$spec does not add a bare perl requirement on EL");
}

done_testing();
