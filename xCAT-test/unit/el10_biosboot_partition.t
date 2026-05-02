#!/usr/bin/env perl

use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $pre_script = File::Spec->catfile( $repo_root, 'xCAT-server/share/xcat/install/scripts/pre.rhels10' );
my $template = File::Spec->catfile( $repo_root, 'xCAT-server/share/xcat/install/rh/compute.rhels10.tmpl' );
my $rocky_template = File::Spec->catfile( $repo_root, 'xCAT-server/share/xcat/install/rocky/compute.rocky10.tmpl' );

open( my $pre_fh, '<', $pre_script ) or die "Unable to read $pre_script: $!";
my $pre = do { local $/; <$pre_fh> };
close($pre_fh);

open( my $template_fh, '<', $template ) or die "Unable to read $template: $!";
my $tmpl = do { local $/; <$template_fh> };
close($template_fh);

like(
    $tmpl,
    qr{#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/pre\.rhels10#},
    'EL10 compute kickstart includes the EL10 pre-install partition script'
);

is(
    readlink($rocky_template),
    '../rh/compute.rhels10.tmpl',
    'Rocky 10 compute kickstart uses the EL10 compute template'
);

like(
    $pre,
    qr{"ppc64"\|"ppc64le"\)\s+echo "part prepboot --fstype=prepboot --asprimary --ondisk=\$instdisk --size=8"}s,
    'ppc64 and ppc64le keep the PReP boot partition'
);

like(
    $pre,
    qr{"x86_64"\)\s+(?:\#.*\n\s+)*if \[ ! -d /sys/firmware/efi \]; then\s+echo "part biosboot --ondisk=\$instdisk --size=1"}s,
    'x86_64 legacy BIOS gets a BIOS boot partition'
);

like(
    $pre,
    qr{if \[ -d /sys/firmware/efi \]\s+then\s+echo "part /boot/efi --fstype=\$EFIFSTYPE --ondisk=\$instdisk --size=256"}s,
    'UEFI systems keep the EFI system partition'
);

my $biosboot_pos = index( $pre, 'part biosboot --ondisk=$instdisk --size=1' );
my $boot_pos = index( $pre, 'part /boot --fstype=$BOOTFSTYPE' );
ok( $biosboot_pos >= 0, 'BIOS boot partition is generated' );
ok( $boot_pos >= 0, 'regular /boot partition is generated' );
cmp_ok( $biosboot_pos, '<', $boot_pos, 'BIOS boot partition is generated before /boot' );

unlike( $pre, qr{/dev/xvda}, 'partition generation does not inspect a hard-coded disk' );
unlike( $pre, qr{disklabeltype}, 'partition generation does not depend on the pre-install disk label' );

done_testing;
