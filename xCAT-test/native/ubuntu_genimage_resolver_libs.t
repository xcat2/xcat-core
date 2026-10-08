#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::UbuntuImage;

plan skip_all => 'Linux filesystem namespaces are required' unless $^O eq 'linux';

my @x86 = qw(lib64/libnss_dns.so.2 lib/x86_64-linux-gnu/libnss_dns.so.2 lib64/libresolv.so.2);
my @power = qw(lib/powerpc64le-linux-gnu/libnss_files.so.2 lib/powerpc64le-linux-gnu/libnss_dns.so.2);
my @riscv = qw(lib/riscv64-linux-gnu/libnss_files.so.2 lib/riscv64-linux-gnu/libnss_dns.so.2);
my @generic = ('lib/libnss_dns.so.2');
my @all = (@x86, @power, @riscv, @generic);

for my $case (
    ['x86_64', \@all, \@x86],
    ['ppc64el', \@all, \@power],
    ['riscv64', \@all, \@riscv],
    ['s390x', \@all, \@generic],
    ['x86', \@all, \@generic],
    ['riscv64', \@generic, []],
    ['riscv64', [$riscv[1]], [$riscv[1]]],
    ['x86_64', [], []],
) {
    my ($arch, $present, $expected) = @$case;
    subtest "$arch with " . (@$present ? join(', ', @$present) : 'no resolver files') => sub {
        my $image = XCAT::Test::UbuntuImage->new();
        my ($status, $output) = $image->initrd($arch, @$present);
        is($status, 0, 'genimage completes both initrds') or diag($output);
        unlike($output, qr/Unexpected chroot command/, 'only expected image chroot commands run');
        return unless $status == 0;
        is($image->read('work/image/kernel'), "fixture boot/vmlinuz-7.0\n",
            'the selected image kernel is published');
        for my $mode (qw(stateless statelite)) {
            my ($unpack, $diagnostics) = $image->run('sh', '-c',
                "gzip -t /work/image/initrd-$mode.gz && mkdir /work/$mode && "
                . "cd /work/$mode && gzip -dc /work/image/initrd-$mode.gz | cpio -id --quiet");
            is($unpack, 0, "$mode archive can be unpacked") or diag($diagnostics);
            next unless $unpack == 0;
            ok(-s "$image->{root}/work/$mode/init", "$mode contains the generated init script");
            my @actual = grep { -f "$image->{root}/work/$mode/$_" } @all;
            is_deeply([sort @actual], [sort @$expected],
                "$mode contains only the image architecture's available resolver libraries");
            for my $file (@$expected) {
                next unless -f "$image->{root}/work/$mode/$file";
                is($image->read("work/$mode/$file"), "fixture $file\n",
                    "$mode preserves the bytes of $file");
            }
        }
    };
}

done_testing();
