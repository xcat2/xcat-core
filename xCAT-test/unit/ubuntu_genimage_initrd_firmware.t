#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# grub2 on a pseries node cannot load the netboot initrd when it carries the whole Ubuntu
# firmware tree. Run genimage's firmware step over a root image that holds firmware no
# driver in the initrd asks for, and read what the step put in the initrd.

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));
my $genimage  = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'netboot', 'ubuntu', 'genimage');
die "genimage not found at $genimage\n" unless -f $genimage;

my $src = do { local $/; open my $fh, '<', $genimage or die $!; <$fh> };

# The step sits between the loop that copies the initrd files and the copy of the module
# index. Both anchors hold whatever the firmware step itself looks like.
my ($step) = $src =~ m{
    copy_initrd_file\(\$srcpath,\ "/tmp/xcatinitrd\.\$\$/\$_"\);\n
    \ {8}\}\n\ {4}\}\n
    (.*?)
    \n\ {4}if\ \(-d\ "\$rootimg_dir/lib/modules/\$kernelver/"\)\ \{
}sx;
die "genimage no longer has a firmware step between the initrd file loop and the module index\n"
  unless defined $step;

my ($copy_initrd_file) = $src =~ m{^(sub copy_initrd_file \{.*?\n\}\n)}ms;
die "genimage no longer defines copy_initrd_file\n" unless defined $copy_initrd_file;

# The helper the step calls once the firmware copy is filtered. A genimage that copies the
# tree whole has no such routine, and the step below then needs none.
my ($helper) = $src =~ m{^(sub initrd_firmware_files \{.*?\n\}\n)}ms;

my $scratch    = tempdir(CLEANUP => 1);
my $rootimg    = "$scratch/rootimg";
my $initrd_dir = "$scratch/initrd";

my $rewritten = ($step =~ s{/tmp/xcatinitrd\.\$\$}{$initrd_dir}g);
die "the firmware step no longer writes to /tmp/xcatinitrd.\$\$\n" unless $rewritten;

# modinfo reports the firmware of a module. Answer for the modules of this root image only.
my $bin = "$scratch/bin";
make_path($bin);
open(my $fake, '>', "$bin/modinfo") or die $!;
print $fake <<'SH';
#!/bin/sh
case "$*" in
    *mlx5_core*)  echo mellanox/fw-a.mfa2 ;;
    *bnx2x*)      echo bnx2x/bnx2x-e2.fw ;;
    *e1000e*)     echo intel/absent-from-this-image.bin ;;
    *custom_nic*) echo custom/custom-nic.bin ;;
    *virtio_net*) : ;;
    *)            exit 1 ;;
esac
SH
close($fake);
chmod 0755, "$bin/modinfo";
$ENV{PATH} = "$bin:$ENV{PATH}";

foreach my $file (
    'lib/firmware/mellanox/fw-a.mfa2',
    'lib/firmware/updates/7.0.0/mellanox/fw-a.mfa2',
    'lib/firmware/custom/custom-nic.bin',
    'lib/firmware/bnx2x/bnx2x-e2.fw.zst',
    'lib/firmware/amdgpu/never-asked-for.bin',
    'lib/firmware/qcom/never-asked-for-either.bin',
    'lib/modules/7.0.0/kernel/drivers/net/virtio_net.ko',
    'lib/modules/7.0.0/kernel/drivers/net/mlx5_core.ko',
    'lib/modules/7.0.0/kernel/drivers/net/bnx2x.ko.zst',
    'lib/modules/7.0.0/kernel/drivers/net/e1000e.ko',
    'bin/busybox',
  )
{
    my $full = "$rootimg/$file";
    ($full =~ m{^(.*)/[^/]+$}) and make_path($1);
    open(my $fh, '>', $full) or die $!;
    print $fh "content of $file\n";
    close($fh);
}
make_path("$initrd_dir/lib/firmware");

# A driver the administrator put in the custom directory. genimage takes the module from there
# and not from the root image, so that is the file its firmware has to be read from.
my $customdir   = "$scratch/custom";
my $pathtofiles = "$scratch/pathtofiles";
make_path("$customdir/lib/modules/7.0.0/kernel/drivers/net");
make_path($pathtofiles);
open(my $custom, '>', "$customdir/lib/modules/7.0.0/kernel/drivers/net/custom_nic.ko") or die $!;
print $custom "content of a custom driver\n";
close($custom);

{
    package Scratch;
    use strict;
    use warnings;
    use File::Basename;
    use File::Copy;
    use File::Path qw(mkpath);
    our $rootimg_dir;
    our @filestoadd;
    sub xdie { die @_ }
}

## no critic (BuiltinFunctions::ProhibitStringyEval)
eval "package Scratch;\n$copy_initrd_file\n1" or die $@;
if (defined $helper) {
    eval "package Scratch;\n$helper\n1" or die $@;
}

$Scratch::rootimg_dir = $rootimg;
$Scratch::customdir   = $customdir;
$Scratch::pathtofiles = $pathtofiles;
$Scratch::kernelver   = '7.0.0';
@Scratch::filestoadd  = (
    [ 'lib/modules/7.0.0/kernel/drivers/net/virtio_net.ko', 'lib/virtio_net.ko' ],
    [ 'lib/modules/7.0.0/kernel/drivers/net/mlx5_core.ko',  'lib/mlx5_core.ko' ],
    [ 'lib/modules/7.0.0/kernel/drivers/net/bnx2x.ko.zst',  'lib/bnx2x.ko' ],
    [ 'lib/modules/7.0.0/kernel/drivers/net/e1000e.ko',     'lib/e1000e.ko' ],
    [ 'lib/modules/7.0.0/kernel/drivers/net/custom_nic.ko', 'lib/custom_nic.ko' ],
    [ 'bin/busybox',                                        'bin/busybox' ],
);
eval "package Scratch;\nno strict 'vars';\n$step\n1" or die $@;

ok(-e "$initrd_dir/lib/firmware/mellanox/fw-a.mfa2",
    'the initrd keeps the firmware a driver in it asks for');
ok(-e "$initrd_dir/lib/firmware/bnx2x/bnx2x-e2.fw.zst",
    'a compressed firmware file answers the plain name the driver asks for');
ok(!-e "$initrd_dir/lib/firmware/amdgpu/never-asked-for.bin",
    'the initrd does not carry firmware no driver in it asks for');
ok(!-e "$initrd_dir/lib/firmware/qcom/never-asked-for-either.bin",
    'the whole firmware tree does not reach the initrd');
ok(!-e "$initrd_dir/lib/firmware/intel/absent-from-this-image.bin",
    'a firmware name the root image does not have is left out');
ok(-e "$initrd_dir/lib/firmware/custom/custom-nic.bin",
    'the firmware of a driver taken from the custom directory reaches the initrd');
ok(-e "$initrd_dir/lib/firmware/updates/7.0.0/mellanox/fw-a.mfa2",
    'a firmware override under updates/<kernel> reaches the initrd');

done_testing();
