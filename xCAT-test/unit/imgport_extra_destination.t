#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use File::Slurper qw(read_binary write_binary);
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
local $ENV{XCATCFG} = "$root/cfg";
make_path($ENV{XCATCFG}, "$root/bundle/extra", "$root/parent");
require(repo_path('xCAT-server/lib/xcat/plugins/imgport.pm'));
write_binary("$root/bundle/extra/site.conf", "extra file from the bundle\n");

# imgexport records an extra file with its source path and its destination directory.
sub move_extra {
    my ($dest) = @_;
    my @errors;
    my $moved = xCAT_plugin::imgport::moveExtra(sub { push @errors, @{ $_[0]{error} || [] } }, '/etc/site.conf', $dest, "$root/bundle");
    return ($moved, join("\n", @errors));
}

for my $missing ('parent/dir', 'missing/parent/dir') {
    # The destination directory does not exist on the importing host.
    my $dest = "$root/$missing";
    my ($moved, $errors) = move_extra($dest);
    ok($moved, "$missing: an extra file is copied when its destination directory is missing");
    is($errors, '', "$missing: no error is reported");
    ok(-d $dest, "$missing: the destination directory is created");
    is(-f "$dest/site.conf" ? read_binary("$dest/site.conf") : undef, "extra file from the bundle\n", "$missing: the file is copied into it");
}

{
    make_path("$root/existing");
    write_binary("$root/existing/site.conf", "previous file\n");
    my ($moved, $errors) = move_extra("$root/existing");
    ok($moved, 'an extra file is copied into an existing directory');
    is(read_binary("$root/existing/site.conf"), "extra file from the bundle\n", 'the file replaces the previous one');
    is(read_binary("$root/existing/site.conf.ORIG"), "previous file\n", 'the previous file is kept as .ORIG');
}

{
    write_binary("$root/a-file", "a file where a directory goes\n");
    my ($moved, $errors) = move_extra("$root/a-file");
    ok(!$moved, 'an extra file fails when a file is at its destination directory');
    like($errors, qr/Failed to create \Q$root\/a-file\E/, 'the destination that is not a directory is reported');
    is(read_binary("$root/a-file"), "a file where a directory goes\n", 'the file at the destination stays');
}

{
    write_binary("$root/a-parent", "a file where a parent directory goes\n");
    my ($moved, $errors) = move_extra("$root/a-parent/dir");
    ok(!$moved, 'an extra file fails when a file is at a parent of its destination directory');
    like($errors, qr/Failed to create \Q$root\/a-parent\/dir\E/, 'the destination under the file is reported');
    is(read_binary("$root/a-parent"), "a file where a parent directory goes\n", 'the file at the parent stays');
}

{
    # The name of an extra file can hold glob characters, and another file at the destination can match them.
    write_binary("$root/bundle/extra/site[1].conf", "extra file with brackets\n");
    make_path("$root/glob");
    write_binary("$root/glob/site1.conf", "unrelated file\n");
    my @errors;
    my $moved = xCAT_plugin::imgport::moveExtra(sub { push @errors, @{ $_[0]{error} || [] } }, '/etc/site[1].conf', "$root/glob", "$root/bundle");
    ok($moved, 'an extra file with glob characters in its name is copied');
    is(-f "$root/glob/site[1].conf" ? read_binary("$root/glob/site[1].conf") : undef, "extra file with brackets\n", 'the file keeps its literal name');
    is(read_binary("$root/glob/site1.conf"), "unrelated file\n", 'the file that its name matches as a glob stays');
}

{
    # A directory is at the path of the extra file, and its backup fails because the backup path holds a directory.
    make_path("$root/conflict/site.conf", "$root/conflict/site.conf.ORIG/kept");
    my ($moved, $errors) = move_extra("$root/conflict");
    ok(!$moved, 'an extra file fails when the backup of its path fails');
    like($errors, qr/Failed to move \Q$root\/conflict\/site.conf\E/, 'the failed backup is reported');
    ok(!-e "$root/conflict/site.conf/site.conf", 'nothing is copied into the directory at the path');
}

done_testing();
