#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

plan skip_all => 'the build host has no /etc/hosts or /etc/resolv.conf'
  unless -r '/etc/hosts' && -r '/etc/resolv.conf';

sub sources {
    my ($dir) = @_;
    opendir(my $dh, $dir) or die "opendir $dir: $!";
    my @files = sort grep { !/^\./ } readdir($dh);
    closedir($dh);
    return \@files;
}

my $root    = tempdir(CLEANUP => 1);
my $sources = "$root/etc/apt/sources.list.d";
my $site    = "deb http://192.0.2.2/site ./\n";
make_path($sources);
write_text("$sources/$_", "deb http://192.0.2.1/retired ./\n") for qw(genimage.apt.list genimage1.apt.list);
write_text("$sources/site.list", $site);
write_text("$root/etc/hosts", "127.0.0.1 localhost\n");
write_text("$root/etc/resolv.conf", '#Dummy resolv.conf to make boot cleaner');

for my $pass (1, 2) {
    imgutils::prepare_reused_root($root);
    is_deeply(sources($sources), ['site.list'], "pass $pass: only the apt sources that genimage writes are removed");
    is(read_text("$sources/site.list"), $site, "pass $pass: a site source is kept as it is");
    is(read_text("$root/etc/resolv.conf"), read_text('/etc/resolv.conf'),
        "pass $pass: the image gets the resolv.conf of the build host");
    is(read_text("$root/etc/resolv.conf.bak"), '#Dummy resolv.conf to make boot cleaner',
        "pass $pass: resolv.conf.bak holds the resolv.conf of the image");
}

{
    my $bare = tempdir(CLEANUP => 1);
    make_path("$bare/etc");
    imgutils::prepare_reused_root($bare);
    is(read_text("$bare/etc/hosts"), read_text('/etc/hosts'), 'an image without apt sources still gets the hosts of the build host');
}

done_testing();
