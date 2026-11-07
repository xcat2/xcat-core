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

my $release = '6.12.0-124.el10.x86_64';

# Copies the kernel of $release from an image root that holds the named files.
sub copy_case {
    my (@files) = @_;
    my $root = tempdir(CLEANUP => 1);
    for my $file (@files) {
        make_path("$root/" . ($file =~ s{/[^/]+$}{}r));
        write_text("$root/$file", "$file\n");
        chmod(0755, "$root/$file");
    }
    my $dir = tempdir(CLEANUP => 1);
    my $ok = eval { imgutils::copy_kernel($root, $release, $dir) };
    return ($ok, $@, $dir);
}

for my $files (
    [ "boot/vmlinux-$release", "boot/vmlinuz-$release", "boot/image-$release", "lib/modules/$release/vmlinuz" ],
    [ "boot/vmlinuz-$release", "boot/image-$release", "lib/modules/$release/vmlinuz" ],
    [ "boot/image-$release", "lib/modules/$release/vmlinuz" ],
    [ "lib/modules/$release/vmlinuz" ],
) {
    my ($ok, $error, $dir) = copy_case(@$files);
    ok($ok, "copies a kernel from an image with @$files") or diag($error);
    is(read_text("$dir/kernel"), "$files->[0]\n", "copies $files->[0] from an image with @$files");
    is((stat("$dir/kernel"))[2] & oct(7777), oct(755), "keeps the mode of $files->[0]");
}

{
    my ($ok, $error, $dir) = copy_case('boot/vmlinuz-6.12.0-55.el10.x86_64', 'lib/modules/6.12.0-55.el10.x86_64/vmlinuz');
    ok(!$ok, 'fails when the image has no kernel of the release');
    like($error, qr/couldn't find the kernel file matched \Q$release\E/, 'names the release of the missing kernel');
    ok(!-e "$dir/kernel", 'copies no kernel of another release');
}

{
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/boot");
    write_text("$root/boot/vmlinuz-$release", "kernel\n");
    my $ok = eval { imgutils::copy_kernel($root, $release, "$root/missing") };
    ok(!$ok, 'fails when the kernel cannot be copied');
    like($@, qr/^Error: failed to copy the kernel to \Q$root\E\/missing: /, 'reports the failed copy');
}

# Packs a directory of two files, with each named command replaced by one that fails without output.
sub pack_case {
    my (@failing) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $src = "$dir/initrd";
    make_path("$src/bin", "$dir/bin");
    write_text("$src/init",         "init\n");
    write_text("$src/bin/netstart", "netstart\n");
    for my $command (@failing) {
        write_text("$dir/bin/$command", "#!/bin/sh\nexit 1\n");
        chmod(0755, "$dir/bin/$command");
    }
    my ($ok, $error);
    {
        local $ENV{PATH} = "$dir/bin:$ENV{PATH}";
        local *STDOUT;
        open(STDOUT, '>', \my $printed) or die "STDOUT: $!";
        $ok    = eval { imgutils::pack_initrd($src, "$dir/initrd.gz", 'gzip', 'stateless') };
        $error = $@;
    }
    return ($ok, $error, $dir, $src);
}

{
    my ($ok, $error, $dir, $src) = pack_case();
    ok($ok, 'packs the initial ramdisk') or diag($error);
    my @listing = sort map { chomp; $_ } `gzip -dc $dir/initrd.gz | cpio -it 2>/dev/null`;
    is_deeply(\@listing, [ '.', 'bin', 'bin/netstart', 'init' ], 'the initial ramdisk holds the packed directory');
    ok(!-e $src, 'removes the packed directory');
}

for my $command (qw(find cpio gzip)) {
    my ($ok, $error, $dir, $src) = pack_case($command);
    ok(!$ok, "fails when $command fails");
    is($error, "Error: failed to generate the initial ramdisk for stateless.\n", "reports the failed $command");
    ok(!-e $src, "removes the packed directory when $command fails");
}

{
    my $dir = tempdir(CLEANUP => 1);
    local *STDOUT;
    open(STDOUT, '>', \my $printed) or die "STDOUT: $!";
    my $ok = eval { imgutils::pack_initrd("$dir/missing", "$dir/initrd.gz", 'gzip', 'statelite') };
    ok(!$ok, 'fails when the directory to pack does not exist');
    is($@, "Error: failed to generate the initial ramdisk for statelite.\n", 'reports the missing directory');
}

done_testing();
