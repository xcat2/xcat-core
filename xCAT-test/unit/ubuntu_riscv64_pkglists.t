#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# A diskless image needs a kernel and the tools its boot scripts call. Without a package
# list for the architecture, genimage debootstraps whatever the generic list holds and the
# image cannot boot. Compare the riscv64 lists with the x86_64 ones they follow.

use lib "$FindBin::Bin/../lib";
use XCAT::Test::File qw(repo_path);

sub packages {
    my ($path) = @_;
    my $full = repo_path($path);
    return unless -r $full;
    open(my $fh, '<', $full) or die "cannot read $full: $!";
    my @packages = grep { length && !/^#/ } map { my $l = $_; chomp $l; $l =~ s/\s+//g; $l } <$fh>;
    close($fh);
    return \@packages;
}

foreach my $release (qw(24.04 26.04)) {
    my $netboot = "xCAT-server/share/xcat/netboot/ubuntu/compute.ubuntu$release.riscv64.pkglist";
    my $x86     = "xCAT-server/share/xcat/netboot/ubuntu/compute.ubuntu$release.x86_64.pkglist";
    my $riscv_packages = packages($netboot);
    ok($riscv_packages, "$release has a riscv64 netboot package list");
    is_deeply($riscv_packages, packages($x86),
        "the $release riscv64 image installs what the x86_64 image installs");
    ok(scalar(grep { $_ eq 'linux-image-generic' } @{$riscv_packages}),
        "the $release riscv64 image installs a kernel");
    ok(scalar(grep { $_ eq 'nfs-common' } @{$riscv_packages}),
        "the $release riscv64 image can mount its root over NFS");
}

my $install = packages(
    'xCAT-server/share/xcat/install/ubuntu/compute.ubuntu26.04.riscv64.pkglist');
ok($install, '26.04 has a riscv64 install package list');
is_deeply($install,
    packages('xCAT-server/share/xcat/install/ubuntu/compute.ubuntu26.04.x86_64.pkglist'),
    'the 26.04 riscv64 install takes what the x86_64 install takes');

done_testing();
