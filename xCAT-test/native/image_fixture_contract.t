#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::ImageSandbox;
use XCAT::Test::UbuntuImage;

plan skip_all => 'image namespaces require Linux' unless $^O eq 'linux';

for my $class ('XCAT::Test::ImageSandbox', 'XCAT::Test::UbuntuImage') {
    subtest $class => sub {
        my $image = $class->new();
        for my $bytes ('', '0', "\0\xff\r\n") {
            $image->write('work/nested/bytes', $bytes);
            is($image->read('work/nested/bytes'), $bytes, 'fixture I/O preserves bytes');
        }
        my $read = eval { $image->read('work/missing'); 1 };
        ok(!$read && $@, 'a missing required file fails');
        my @result = $image->run('/bin/sh', '-c',
            'printf "%s" "$XCATROOT"; printf error >&2; exit 7');
        if ($class eq 'XCAT::Test::UbuntuImage') {
            is_deeply(\@result, [7 << 8, '/repoerror'], 'retains raw status and merged output');
        } else {
            is_deeply(\@result, [7, '/repo/xCAT-server', 'error'], 'retains decoded status and separate streams');
        }
        @result = $image->run('/bin/sh', '-c',
            'test ! -e /etc/os-release && test -r /repo/Version && '
            . '! test -w /repo && printf private > /etc/fixture-marker');
        is($result[0], 0, 'host configuration is hidden and the repository is read-only');
        is($image->read('etc/fixture-marker'), 'private', 'writes reach only the fixture');
    };
}

my $image = XCAT::Test::ImageSandbox->new();
$image->write('work/mounted', 'extra mount');
$image->{mounts} = ['--ro-bind', "$image->{root}/work/mounted", '/opt/input'];
my ($status, $output) = $image->run('/bin/cat', '/opt/input');
is($status, 0, 'the image adapter retains extra mounts');
is($output, 'extra mount', 'the command reads the supplied mount');
done_testing();
