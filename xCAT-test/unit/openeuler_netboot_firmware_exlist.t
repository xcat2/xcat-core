#!/usr/bin/perl
# openEuler's kernel carries `Requires: linux-firmware`, so a diskless image cannot drop the
# package the way an EL image can -- EL only recommends it, and AlmaLinux splits it into
# per-device subpackages. openEuler ships one 1364 MB linux-firmware, which took the compute
# rootimg to 2616 MB. A stateless node unpacks the image into a tmpfs of half its RAM, so a
# 4096 MB node has 2 GiB and the unpack fails with ENOSPC.
#
# The exclude list is the only lever left. This test reads the delivered exlist and asks, for
# representative paths, whether packimage would strip them: the lines become
# `find . -xdev '!' -path '<line>'`, so a line is a find glob relative to the image root.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Slurper qw(read_lines);

my $root   = "$RealBin/../..";
my $exlist = "$root/xCAT-server/share/xcat/netboot/openeuler/compute.openeuler.exlist";
die "$exlist is missing; this test covers nothing\n" unless -f $exlist;

# `find -path` globs: * spans any character, / included.
sub excludes {
    my ($patterns, $path) = @_;
    for my $p (@$patterns) {
        my $re = quotemeta $p;
        $re =~ s/\\\*/.*/g;
        return 1 if $path =~ /\A$re\z/;
    }
    return 0;
}

my (@exclude, @reinclude);
for my $line (read_lines($exlist)) {
    $line =~ s/\s+\z//;
    next if $line eq '' || $line =~ /\A#/;
    if ($line =~ s/\A\+//) { push @reinclude, $line } else { push @exclude, $line }
}
die "the exlist holds no exclusion; this test covers nothing\n" unless @exclude;

# A compute node cannot use these. Each entry is a real path from
# linux-firmware-20260519-2.oe2403sp4, with its measured size.
my @must_strip = (
    ['./usr/lib/firmware/qcom/x1e80100/gpu.mbn',        'Qualcomm laptop SoC, 462 MB tree'],
    ['./usr/lib/firmware/qcom/sdm845/a630_gmu.bin',     'Qualcomm phone SoC'],
    ['./usr/lib/firmware/intel/iwlwifi-cc-a0-77.ucode', 'Intel WiFi, 266 MB tree'],
    ['./usr/lib/firmware/nvidia/ga102/gsp/gsp-535.113.01.bin', 'NVIDIA GSP, 152 MB tree'],
    ['./usr/lib/firmware/amdgpu/navi10_ce.bin',         'AMD GPU, 108 MB tree'],
    ['./usr/lib/firmware/i915/dg2_guc_70.bin',          'Intel GPU'],
    ['./usr/lib/firmware/rtw89/rtw8852c_fw.bin',        'Realtek WiFi'],
    ['./usr/lib/firmware/dpaa2/dpni/dpni-0.0.1.bin',    'NXP SoC'],
    ['./usr/lib/firmware/radeon/BONAIRE_ce.bin',        'Radeon GPU'],
    ['./usr/lib/firmware/xe/bmg_guc_70.bin',            'Intel Xe GPU'],
    ['./usr/lib/firmware/amdnpu/1502_00/npu.sbin',      'AMD NPU'],
    ['./usr/lib/firmware/ueagle-atm/adi930.fw',         'ADSL modem'],
);
for my $c (@must_strip) {
    ok(excludes(\@exclude, $c->[0]), "stripped: $c->[0] ($c->[1])");
}

# The negative control, and the reason this test is not just a line count: a cluster
# interconnect and a server NIC must survive. An exclusion of the whole firmware tree would
# pass every assertion above and break every ConnectX and E810 node.
my @must_keep = (
    ['./usr/lib/firmware/mellanox/mlxsw_spectrum-13.2010.1006.mfa2', 'ConnectX / Spectrum, the interconnect'],
    ['./usr/lib/firmware/intel/ice/ddp/ice.pkg',                    'Intel E810 DDP, a server NIC'],
    ['./usr/lib/firmware/intel/qat_4xxx.bin',                       'QuickAssist'],
    ['./usr/lib/firmware/bnx2x/bnx2x-e2-7.13.21.0.fw',              'Broadcom NIC'],
    ['./usr/lib/firmware/cxgb4/t5fw.bin',                           'Chelsio NIC'],
    ['./usr/lib/firmware/qed/qed_init_values_zipped-8.59.1.0.bin',  'QLogic NIC'],
);
for my $c (@must_keep) {
    ok(!excludes(\@exclude, $c->[0]), "kept: $c->[0] ($c->[1])");
}

# The lines are find globs relative to the image root; a line without the ./ prefix silently
# matches nothing, because packimage runs find from inside the rootimg.
for my $line (@exclude, @reinclude) {
    like($line, qr{\A\./}, "relative to the image root: $line");
}

done_testing;
