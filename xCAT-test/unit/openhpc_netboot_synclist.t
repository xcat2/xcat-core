#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = tempdir(CLEANUP => 1);
my $root = "$fixture/rootimg";
my $syncdir = '/var/lib/xcat/openhpc';
make_path("$fixture/db", "$root/etc/munge", "$root/$syncdir");
local $ENV{XCATCFG} = "SQLite:$fixture/db";
local $ENV{XCATROOT} = $fixture;
require xCAT::DSHCLI;
require(repo_path('xCAT-server/lib/xcat/plugins/packimage.pm'));

my $source = "$fixture/munge.key";
my $synclist = "$fixture/openhpc.synclist";
write_text($source, "test key\n");
write_text($synclist, "$source -> (cn1) $syncdir/munge.key\n");
{
    no warnings qw(redefine once);
    local *xCAT::Utils::runcmd = sub { die 'image sync must not copy a node-qualified file'; };
    is(xCAT::DSHCLI::rsync_to_image($synclist, $root), 0, 'image sync skips node-qualified entries');
    ok(!-e "$root/$syncdir/munge.key", 'the staging root has no synced key');
    local *xCAT::DSHCLI::noderange = sub { return 'cn1'; };
    local $::SYNCSN = 0;
    my $options = {'node-rcp' => '/usr/bin/rsync'};
    is(xCAT::DSHCLI::parse_rsync_input_file_on_MN(['cn1', 'cn2'], $options, $synclist, 0), 0,
        'runtime sync accepts the same list');
    is_deeply($options->{destDir_srcFile}, {cn1 => {$syncdir => {same_dest_name => [$source]}}},
        'runtime sync copies the key only to the permitted node');
}

my $image = 'rocky10.3-x86_64-netboot-compute';
my $managed = "/site.synclist,$syncdir/$image.synclist";
is(xCAT_plugin::packimage::openhpc_image_key($image, $managed, $root), undef, 'a clean managed root can be packed');
write_text("$root/etc/munge/munge.key", "image-generated key\n");
is(xCAT_plugin::packimage::openhpc_image_key($image, $managed, $root), 'etc/munge/munge.key',
    'a managed root with a package-generated key is rejected');
is(xCAT_plugin::packimage::openhpc_image_key($image, '/site.synclist', $root), undef,
    'the OpenHPC guard does not change unrelated images');
unlink "$root/etc/munge/munge.key" or die $!;
symlink('/absent-key', "$root/$syncdir/munge.key") or die $!;
is(xCAT_plugin::packimage::openhpc_image_key($image, $managed, $root), 'var/lib/xcat/openhpc/munge.key',
    'the guard also recognizes the managed sync destination and dangling symlinks');

done_testing;
