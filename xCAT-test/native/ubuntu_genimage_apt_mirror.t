#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP qw(decode_json);
use Test::More;
use XCAT::Test::UbuntuImage;

plan skip_all => 'Linux filesystem namespaces are required' unless $^O eq 'linux';

my $archive = 'http://archive.ubuntu.com/ubuntu';
my $ports = 'http://ports.ubuntu.com/ubuntu-ports';
my $site = 'https://site.example.invalid/ubuntu';
my $explicit = 'https://image.example.invalid/ubuntu';

for my $case (
    ['amd64 default', {arch => 'x86_64'}, 'amd64', $archive, 'noble'],
    ['i386 default', {arch => 'x86'}, 'i386', $archive, 'noble'],
    ['POWER default', {arch => 'ppc64el'}, 'ppc64el', $ports, 'noble'],
    ['RISC-V default', {arch => 'riscv64'}, 'riscv64', $ports, 'noble'],
    ['s390x default', {arch => 's390x'}, 's390x', $ports, 'noble'],
    ['site overrides archive', {mirror => $site}, 'amd64', $site, 'noble'],
    ['site overrides ports', {arch => 'riscv64', mirror => $site}, 'riscv64', $site, 'noble'],
    ['cleared site keeps default', {arch => 'riscv64', mirror => ''}, 'riscv64', $ports, 'noble'],
    ['pkgdir overrides site', {mirror => $site,
        pkgdir => "/work/packages,$explicit jammy main"}, 'amd64', $explicit, 'jammy'],
    ['first pkgdir mirror wins', {pkgdir =>
        "/work/packages,$explicit noble main,$site jammy universe"}, 'amd64', $explicit, 'noble'],
) {
    my ($name, $options, $arch, $mirror, $suite) = @$case;
    subtest $name => sub {
        my $image = XCAT::Test::UbuntuImage->new();
        my ($status, $output, $args) = $image->bootstrap(%$options, bootstrap_success => 1);
        if (exists $options->{mirror} && $options->{mirror} eq '') {
            is_deeply(decode_json($image->read('work/site-row.json'))->{mirror},
                { key => 'ubuntu_apt_mirror' }, 'the cleared setting remains as an empty database row');
        }
        ok($status > 0 && ($status & 127) == 0,
            'genimage exits unsuccessfully after the injected package-metadata failure') or diag($output);
        is_deeply($args, ['--verbose', '--arch', $arch, $suite,
            '/work/image/rootimg', $mirror], 'the selected mirror reaches debootstrap') or diag($output);
        like($output, qr/Failed to update package metadata/,
            'package-metadata failure is reported');
        unlike($output, qr/Unexpected chroot command/, 'only the expected chroot command runs');
        is($image->read('work/apt-update.args'), "/work/image/rootimg\napt-get\nupdate\n",
            'APT uses the generated image root');
        my @sources = grep { /\S/ } split /\n/,
            $image->read('work/image/rootimg/etc/apt/sources.list');
        my @expected = exists $options->{pkgdir}
          ? map { "deb $_" } grep { /^https?:/ } split /,/, $options->{pkgdir}
          : map { "deb $mirror $_ main universe" } ($suite, "$suite-updates", "$suite-security");
        unshift @expected, "deb [trusted=yes] http://192.0.2.1:80/work/packages $suite main restricted universe";
        is_deeply([map { [split ' '] } @sources], [map { [split ' '] } @expected],
            'image APT sources retain the local mirror and all configured remote pockets');
    };
}

subtest 'explicit mirror without a suite' => sub {
    my $image = XCAT::Test::UbuntuImage->new();
    my ($status, $output, $args) = $image->bootstrap(
        pkgdir => "/work/packages,$explicit");
    is($status, 256, 'invalid mirror is rejected');
    is($args, undef, 'debootstrap is not invoked');
    like($output, qr/first http mirror path must includes http URL and distribute name/,
        'rejection identifies the missing suite');
};

done_testing();
