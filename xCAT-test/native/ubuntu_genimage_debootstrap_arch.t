#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::UbuntuImage;

plan skip_all => 'Linux filesystem namespaces are required' unless $^O eq 'linux';

for my $case (
    ['x86_64', 'amd64'], ['x86', 'i386'], ['ppc64el', 'ppc64el'],
    ['ppc64le', 'ppc64le', 'ppc64le is currently passed through unchanged'],
    ['s390x', 's390x'], ['riscv64', 'riscv64'],
) {
    my ($arch, $debian_arch, $name) = @$case;
    $name ||= $arch;
    subtest $name => sub {
        my $image = XCAT::Test::UbuntuImage->new();
        my ($status, $output, $args) = $image->bootstrap(
            arch => $arch,
            pkgdir => '/work/packages,https://mirror.example.invalid/ubuntu noble main');
        is($status, 256, 'genimage reports the injected debootstrap failure') or diag($output);
        is_deeply($args, ['--verbose', '--arch', $debian_arch, 'noble',
            '/work/image/rootimg', 'https://mirror.example.invalid/ubuntu'],
            'debootstrap receives the image architecture and configured source') or diag($output);
        like($output, qr/Can not create bootstraps for rootimage/,
            'the failure reaches the package-source diagnostic');
    };
}

done_testing();
