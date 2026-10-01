#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../build-utils/lib";
use Test::More;
use XCAT::BuildUtils qw(openeuler_build_target openeuler_repo_subdir targetarch_from_target);

foreach my $version (['20.03 (LTS-SP4)', '20.03sp4'], ['22.03 (LTS-SP4)', '22.03sp4'],
                    ['24.03 (LTS-SP1)', '24.03sp1'], ['24.03 (LTS-SP3)', '24.03sp3'],
                    ['24.03 (LTS-SP4)', '24.03sp4'], ['24.03 (LTS)', '24.03']) {
    foreach my $arch ('x86_64', 'ppc64le') {
        my $target = "openeuler-$version->[1]-$arch";
        is(openeuler_build_target({ID => 'openEuler', VERSION => $version->[0], VERSION_ID => '24.03'}, $arch),
            $target, "$target retains native host service pack");
        is(openeuler_repo_subdir($target), "openeuler$version->[1]/$arch", 'repository subdirectory matches bootstrap');
        is(targetarch_from_target($target), $arch, 'existing architecture parser handles the native target');
    }
}
is(openeuler_build_target({ID => 'openeuler', VERSION_ID => '24.03'}, 'ppc64le'), 'openeuler-24.03-ppc64le',
    'VERSION_ID supplies GA when VERSION is absent');
is(openeuler_build_target({ID => 'rocky', VERSION_ID => '9.6'}, 'x86_64'), undef, 'EL host selection remains outside native mapping');
is(openeuler_repo_subdir('alma+epel-10-x86_64'), undef, 'EL repository layout remains outside native mapping');
foreach my $invalid ('openeuler-24.09-x86_64', 'openeuler-25.03-x86_64', 'openeuler-24.03sp0-x86_64', 'openeuler-24.03-ppc64') {
    eval {openeuler_repo_subdir($invalid)};
    like($@, qr/Unsupported openEuler build target/, "$invalid is rejected");
}

done_testing();
