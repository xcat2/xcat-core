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

my %host  = map { $_ => read_text("/etc/$_") } qw(hosts resolv.conf);
my $stub  = '../run/systemd/resolve/stub-resolv.conf';
my $dummy = '#Dummy resolv.conf to make boot cleaner';

# A root image as an earlier genimage run leaves it: resolv.conf links to the stub that holds the dummy.
sub image_root {
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/etc", "$root/run/systemd/resolve");
    write_text("$root/etc/hosts", "127.0.0.1 localhost\n");
    write_text("$root/run/systemd/resolve/stub-resolv.conf", $dummy);
    symlink($stub, "$root/etc/resolv.conf") or die "symlink: $!";
    return $root;
}

sub has_host_files {
    my ($root, $label) = @_;
    for my $file (qw(hosts resolv.conf)) {
        ok(!-l "$root/etc/$file", "$label: etc/$file is a file, not a link");
        is(read_text("$root/etc/$file"), $host{$file}, "$label: etc/$file holds the file of the build host");
    }
    return;
}

{
    my $root = image_root();
    for my $pass (1, 2) {
        imgutils::use_host_resolver($root);
        has_host_files($root, "pass $pass");
        is(read_text("$root/etc/hosts.bak"), "127.0.0.1 localhost\n", "pass $pass: hosts.bak holds the hosts of the image");
        is(readlink("$root/etc/resolv.conf.bak"), $stub, "pass $pass: resolv.conf.bak is the link of the image");
    }
    is(read_text("$root/run/systemd/resolve/stub-resolv.conf"), $dummy, 'the stub that the link names is not written');
}

{
    my $root    = image_root();
    my $outside = tempdir(CLEANUP => 1) . '/stub-resolv.conf';
    write_text($outside, "nameserver 192.0.2.1\n");
    unlink("$root/etc/resolv.conf");
    symlink($outside, "$root/etc/resolv.conf") or die "symlink: $!";
    imgutils::use_host_resolver($root);
    is(readlink("$root/etc/resolv.conf.bak"), $outside, 'an absolute link is moved aside, not followed');

    # A package script can turn resolv.conf back into a link while the .bak files exist.
    unlink("$root/etc/resolv.conf");
    symlink($outside, "$root/etc/resolv.conf") or die "symlink: $!";
    imgutils::use_host_resolver($root);
    has_host_files($root, 'after resolv.conf is linked again');
    is(readlink("$root/etc/resolv.conf.bak"), $outside, 'after resolv.conf is linked again: resolv.conf.bak still holds the link of the image');
    is(read_text($outside), "nameserver 192.0.2.1\n", 'a file outside the image is never written through a link');
}

{
    my $root = image_root();
    unlink("$root/etc/hosts");
    imgutils::use_host_resolver($root);
    has_host_files($root, 'an image without hosts');
    ok(!-e "$root/etc/hosts.bak", 'an image without hosts gets no hosts.bak');
}

done_testing();
