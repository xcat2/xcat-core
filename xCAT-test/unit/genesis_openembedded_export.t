#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

sub write_file {
    my ($path, $content) = @_;
    open(my $fh, '>:raw', $path) or die "Unable to write $path: $!";
    print {$fh} $content;
    close($fh) or die "Unable to close $path: $!";
}

sub read_file {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "Unable to read $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

my $root = File::Spec->catdir($FindBin::Bin, '..', '..');
my $export = File::Spec->catfile($root, 'xCAT-genesis-builder', 'oe', 'export');
my $tmpdir = tempdir(CLEANUP => 1);
my $deploy = File::Spec->catdir($tmpdir, 'deploy');
my $machine = 'xcat-genesis-x86-64';
my $image = "xcat-genesis-image-$machine.rootfs";
my $metadata = "xcat-genesis-image-$machine";
my $machine_dir = File::Spec->catdir($deploy, 'images', $machine);
my $license_dir = File::Spec->catdir(
    $deploy, 'licenses', 'xcat_genesis_x86_64', $image,
);
my $output = File::Spec->catdir($tmpdir, 'export');

make_path($machine_dir, $license_dir);
write_file(File::Spec->catfile($machine_dir, 'bzImage'), 'kernel');
write_file(File::Spec->catfile($machine_dir, "$image.cpio.gz"), 'initramfs');
write_file(File::Spec->catfile($machine_dir, "$image.manifest"), 'packages');
write_file(File::Spec->catfile($machine_dir, "$metadata.spdx.json"), '{}');
write_file(File::Spec->catfile($machine_dir, "$metadata.vex.json"), '{}');
write_file(File::Spec->catfile($license_dir, 'license.manifest'), 'licenses');

is(system($export, 'x86_64', $deploy, $output), 0, 'the image exports');
ok( -f File::Spec->catfile( $output, 'image.spdx.json' ),
    'the export includes the image SBOM' );
ok( -f File::Spec->catfile( $output, 'image.vex.json' ),
    'the export includes the VEX report' );

my $manifest = File::Spec->catfile($output, 'xcat-genesis.manifest');
is(
    read_file($manifest),
    "format=xcat-genesis\nversion=1\narchitecture=x86_64\n",
    'the export identifies its format and architecture',
);

my $checksums = File::Spec->catfile($output, 'SHA256SUMS');
like(
    read_file($checksums),
    qr{^[0-9a-f]{64}  xcat-genesis\.manifest$}m,
    'the export manifest has a checksum',
);

my $verify_status = system('sh', '-c', 'cd "$1" && sha256sum -c SHA256SUMS >/dev/null', 'sh', $output);
is($verify_status, 0, 'all exported checksums verify');

done_testing();
