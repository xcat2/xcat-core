#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# genimage builds the netboot initrd for ppc64el with mkinitrd, not dracut, and mkinitrd
# copies usr/bin/dig out of the rootimg. A release with no ppc64el package list falls back
# to compute.pkglist, which installs no dig, and genimage stops with
# "Failed to find usr/bin/dig". The package that holds dig changed name in 22.04.

use lib "$FindBin::Bin/../lib";
use XCAT::Test::File qw(repo_path);

my $netboot = 'xCAT-server/share/xcat/netboot/ubuntu';

sub packages {
    my ($path) = @_;
    my $full = repo_path($path);
    return unless -r $full;
    open(my $fh, '<', $full) or die "cannot read $full: $!";
    my @packages = grep { length && !/^#/ } map { my $l = $_; chomp $l; $l =~ s/\s+//g; $l } <$fh>;
    close($fh);
    return \@packages;
}

foreach my $release (qw(20.04 22.04 24.04 26.04)) {
    my $list = packages("$netboot/compute.ubuntu$release.ppc64el.pkglist");
    ok($list, "$release has a ppc64el netboot package list");

    SKIP: {
        skip "no $release ppc64el package list to inspect", 4 unless $list;

        ok(scalar(grep { $_ eq 'dnsutils' || $_ eq 'bind9-dnsutils' } @{$list}),
            "the $release ppc64el image installs the dig that mkinitrd copies");
        ok(scalar(grep { $_ eq 'linux-image-generic' } @{$list}),
            "the $release ppc64el image installs a kernel");
        ok(scalar(grep { $_ eq 'nfs-common' } @{$list}),
            "the $release ppc64el image can mount its root over NFS");
        is_deeply(packages("$netboot/compute.ubuntu$release.ppc64le.pkglist"), $list,
            "the $release ppc64le list matches the ppc64el list");
    }
}

done_testing();
