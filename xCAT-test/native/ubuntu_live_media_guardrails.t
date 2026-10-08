#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP qw(decode_json);
use Test::More;
use XCAT::Test::UbuntuImage;

plan skip_all => 'Linux filesystem namespaces are required' unless $^O eq 'linux';

for my $case (
    ['install-source metadata', ['casper/install-sources.yaml'], 1],
    ['squashfs payload', ['casper/ubuntu-server.squashfs'], 1],
    ['both live markers', ['casper/install-sources.yaml', 'casper/root.squashfs'], 1],
    ['ordinary installer', ['install/vmlinuz'], 0],
    ['casper without a live marker', ['casper/vmlinuz'], 0],
    ['similarly named files', ['casper/root.squashfs.bak', 'casper/install-sources.yml'], 0],
    ['marker outside casper', ['casper/vmlinuz', 'install-sources.yaml', 'root.squashfs'], 0],
) {
    my ($name, $files, $live) = @$case;
    subtest $name => sub {
        my $image = XCAT::Test::UbuntuImage->new();
        $image->write('work/media/.disk/info', "Ubuntu-Server 24.04 LTS \"Noble Numbat\" - Release amd64 (20240423)\n");
        $image->write('work/media/README.diskdefines', "#define DISKNUM 1\n");
        $image->write('work/media/dists/noble/Release', "Suite: noble\n");
        $image->write("work/media/$_", "fixture $_\n") for @$files;
        my ($status, $output) = $image->run('perl',
            '/repo/xCAT-test/native/fixtures/ubuntu_image/media.pl');
        is($status, 0, 'copycd request completes') or diag($output);
        return unless $status == 0;
        my $result = decode_json($image->read('work/result.json'));
        is_deeply([grep { $_->{error} || ($_->{data} || '') =~ /^Error/ }
            @{ $result->{responses} }], [], 'import reports no errors');
        is_deeply($result->{osdistro}, { arch => 'x86_64', type => 'Linux',
            dirpaths => '/install/ubuntu24.04/x86_64' }, 'import records the copied distribution');
        is($result->{detected}, $live, 'media classification matches its contents');
        my @warnings = map { @{ $_->{warning} || [] } } @{ $result->{responses} };
        is(scalar @warnings, $live, 'only live media produces a package-source warning');
        if ($live) {
            like($warnings[0], qr/not a complete Ubuntu apt package mirror/,
                'warning explains the live media limitation');
            like($warnings[0], qr/linuximage\.pkgdir.*linuximage\.otherpkgdir.*HTTP\/HTTPS/,
                'warning identifies configurable package sources');
        }
        ok(grep({ ($_->{data} || '') eq 'Media copy operation successful' }
            @{ $result->{responses} }), 'request reports a successful import');
        for my $file (@$files) {
            is($image->read("install/ubuntu24.04/x86_64/$file"), "fixture $file\n",
                "$file reaches the copied media");
        }
    };
}

done_testing();
