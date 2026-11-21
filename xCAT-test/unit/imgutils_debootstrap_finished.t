#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

sub image_root {
    my (@files) = @_;
    my $root = tempdir(CLEANUP => 1) . '/rootimg';
    make_path($root);
    for my $file (@files) {
        if ($file =~ m{/$}) {
            make_path("$root/$file");
        } else {
            make_path("$root/" . ($file =~ s{/[^/]+$}{}r));
            write_text("$root/$file", '');
        }
    }
    return $root;
}

is(imgutils::debootstrap_finished(tempdir(CLEANUP => 1) . '/rootimg'), 0,
    'a missing root image needs debootstrap');
is(imgutils::debootstrap_finished(image_root('etc/fstab')), 0,
    'a root image with only the dummy fstab of genimage needs debootstrap');
is(imgutils::debootstrap_finished(image_root('var/lib/dpkg/')), 0,
    'a root image without a dpkg status file needs debootstrap');
is(imgutils::debootstrap_finished(image_root('etc/fstab', 'var/lib/dpkg/status')), 1,
    'a root image that debootstrap finished is reused');

for my $case (
    [ 'debootstrap/debootstrap.log', 'var/lib/dpkg/status' ],
    [ 'debootstrap/' ],
) {
    my $root = image_root(@$case);
    my $finished = eval { imgutils::debootstrap_finished($root) };
    is($finished, undef, "an unfinished root image with @$case stops genimage");
    like($@, qr/^Error: \Q$root\E holds an unfinished debootstrap\. Remove \Q$root\E /,
        "the error for a root image with @$case names the root image to remove");
}

done_testing();
