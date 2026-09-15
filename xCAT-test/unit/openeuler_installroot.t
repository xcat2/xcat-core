#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

for my $case (
    ['openeuler20.03sp4', '20.03LTS_SP4'],
    ['openeuler22.03sp4', '22.03LTS_SP4'],
    ['openeuler24.03sp1', '24.03LTS_SP1'],
    ['openeuler24.03sp3', '24.03LTS_SP3'],
    ['openeuler24.03sp4', '24.03LTS_SP4'],
    ['openeuler24.03', '24.03LTS'],
) {
    my ($os, $release) = @$case;
    my $cmd = imgutils::rpm_installroot_command($os, '/var/tmp/native-image', '-y', 1);
    like($cmd, qr/^dnf -y /, "$os uses native DNF");
    like($cmd, qr/--releasever=\Q$release\E /, "$os retains the native RPM release value");
    like($cmd, qr{--installroot=/var/tmp/native-image/ }, "$os keeps the selected image root");
    unlike($cmd, qr/module_platform_id/, "$os does not fabricate an EL module platform");
    like($cmd, qr/--setopt=strict=1 /, "$os fails on missing requested packages");
    like($cmd, qr/'--setopt=\*\.gpgcheck=1' /, "$os verifies repository packages");
    like($cmd, qr/'--setopt=\*\.skip_if_unavailable=False' /, "$os requires all selected repositories");
    is(imgutils::el_major_version($os), undef, "$os is not an EL release");
}

for my $os ('openeuler24.09', 'openeuler25.03', 'openeuler24.03sp0') {
    my $ok = eval { imgutils::rpm_installroot_command($os, '/var/tmp/native-image', '-y', 1); 1 };
    ok(!$ok, "$os cannot fall through to an unrelated package manager");
    like($@, qr/Unsupported openEuler image release/, 'invalid release reports its cause');
}

my $ok = eval { imgutils::rpm_installroot_command('openeuler24.03sp3', '/var/tmp/native-image', '-y', 0); 1 };
ok(!$ok, 'missing DNF fails before package installation');
like($@, qr/openEuler image creation requires dnf/, 'missing native package manager is explicit');

my $repo = imgutils::rpm_repository_config('openeuler24.03sp3', 'compute-os',
    'https://mirror.example/OS/x86_64/', 'file:///tmp/trusted-keys');
is($repo, "[compute-os]\nname=compute-os\nbaseurl=https://mirror.example/OS/x86_64/\n" .
    "gpgcheck=1\ngpgkey=file:///tmp/trusted-keys\nskip_if_unavailable=False\n\n",
    'native repository uses the builder trust set and requires availability');
$ok = eval { imgutils::rpm_repository_config('openeuler24.03sp3', 'otherpkgs',
    'file:///install/otherpkgs'); 1 };
ok(!$ok, 'native repository cannot silently omit its signing keys');
is(imgutils::rpm_repository_config('rhels9.6', 'legacy-os', 'file:///install/rhels9.6/x86_64'),
    "[legacy-os]\nname=legacy-os\nbaseurl=file:///install/rhels9.6/x86_64\ngpgcheck=0\nskip_if_unavailable=True\n\n",
    'existing repository configuration is preserved');

done_testing();
