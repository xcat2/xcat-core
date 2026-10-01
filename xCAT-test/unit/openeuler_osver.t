#!/usr/bin/env perl
use strict;
use warnings;

our $os_release_fixture;
BEGIN {
    *CORE::GLOBAL::open = sub (*;$@) {
        if (@_ == 3 && defined($_[2]) && !ref($_[2]) &&
            $_[1] eq '<' && $_[2] eq '/etc/os-release' &&
            defined($main::os_release_fixture)) {
            return CORE::open($_[0], '<', \$main::os_release_fixture);
        }
        return CORE::open($_[0], $_[1]) if @_ == 2;
        return CORE::open($_[0], $_[1], @_[2 .. $#_]);
    };
}

use FindBin;
use Test::More;
use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::Utils;

plan skip_all => 'host release tests require a Linux os-release file'
    unless -f '/etc/os-release';

foreach my $case (
    ['20.03 (LTS-SP4)', '20.03', '20', '03sp4'],
    ['22.03 (LTS-SP4)', '22.03', '22', '03sp4'],
    ['24.03 (LTS-SP1)', '24.03', '24', '03sp1'],
    ['24.03 (LTS-SP3)', '24.03', '24', '03sp3'],
    ['24.03 (LTS-SP4)', '24.03', '24', '03sp4'],
    ['24.03 (LTS)', '24.03', '24', '03'],
) {
    my ($version, $version_id, $major, $release) = @$case;
    subtest $version => sub {
        local $os_release_fixture =
            "NAME=\"openEuler\"\nVERSION=\"$version\"\nID=\"openEuler\"\n" .
            "VERSION_ID=\"$version_id\"\nPRETTY_NAME=\"openEuler $version\"\n";
        is(xCAT::Utils->osver(), "openeuler$major", 'default keeps major-version convention');
        is(xCAT::Utils->osver('os'), 'openeuler', 'native identity is normalized');
        is(xCAT::Utils->osver('all'), "openeuler,$major.$release", 'complete release retains the service pack');
        is(xCAT::Utils->osver('version'), $major, 'major version stays numeric');
        is(xCAT::Utils->osver('release'), $release, 'minor version retains the service pack');
        is(xCAT::Utils->osver('platform'), '', 'calendar version does not become an EL platform');
    };
}

foreach my $id ('openEuler', 'openeuler', '"openEuler"', "'openEuler'") {
    local $os_release_fixture = "ID=$id\nVERSION='24.03 (LTS-SP4)'\nVERSION_ID=\"24.03\"\n";
    is(xCAT::Utils->osver('all'), 'openeuler,24.03sp4', "$id retains single-quoted VERSION");
}

{
    local $os_release_fixture = "ID=openEuler\nVERSION_ID=\"24.03\"\n";
    is(xCAT::Utils->osver('all'), 'openeuler,24.03', 'VERSION_ID supplies GA when VERSION is absent');
}
{
    local $os_release_fixture = "ID=openEuler\nVERSION=\"24.03 (LTS-SP4)\"\nPLATFORM_ID=\"platform:el24\"\n";
    is(xCAT::Utils->osver('platform'), '', 'native identity does not inherit an EL platform marker');
}
{
    local $os_release_fixture = "ID=openEuler\nVERSION=\"20.09\"\nVERSION_ID=\"20.03\"\n";
    is(xCAT::Utils->osver('all'), 'openeuler,', 'invalid VERSION cannot silently fall back to a different VERSION_ID');
}
{
    local $os_release_fixture = "ID=rocky\nNAME=\"Rocky Linux\"\nVERSION=\"9.6 (Blue Onyx)\"\nVERSION_ID=\"9.6\"\nPLATFORM_ID=\"platform:el9\"\n";
    is(xCAT::Utils->osver(), 'rocky9', 'existing RPM host keeps its major identity');
    is(xCAT::Utils->osver('all'), 'rocky,9.6', 'existing RPM host keeps its full numeric version');
    is(xCAT::Utils->osver('platform'), 'el9', 'existing EL platform is preserved');
}
{
    local $os_release_fixture = "ID=ubuntu\nNAME=\"Ubuntu\"\nVERSION=\"24.04.1 LTS (Noble Numbat)\"\nVERSION_ID=\"24.04\"\n";
    is(xCAT::Utils->osver(), 'ubuntu24', 'Ubuntu default output is unchanged');
    is(xCAT::Utils->osver('all'), 'ubuntu,24.04.1', 'Ubuntu point release is unchanged');
}

subtest 'native version normalization' => sub {
    my $normalize = xCAT::Utils->can('normalize_openeuler_version');
    ok($normalize, 'the production release normalizer is available') or return;
    foreach my $case (
        ['20.03', '20.03'],
        ['20.03sp4', '20.03sp4'],
        ['22.03-LTS-SP4', '22.03sp4'],
        ['24.03-LTS-SP1', '24.03sp1'],
        ['24.03-LTS-SP3', '24.03sp3'],
        ['24.03-LTS-SP4', '24.03sp4'],
        ['24.03-LTS', '24.03'],
        ['2403-LTS', '24.03'],
        [' 24.03 (LTS-SP4) ', '24.03sp4'],
    ) {
        is($normalize->($case->[0]), $case->[1], "$case->[0] normalizes");
    }
    foreach my $invalid (undef, '', '20.09', '25.03', '26.03-LTS',
        '2403-LTS-SP4', '2403', '24.03-LTS-SP0', '24.03sp04',
        '24.03-LTS-preview', 'x24.03-LTS', '24.03-LTS/../../x') {
        is($normalize->($invalid), undef, defined($invalid) ? "$invalid is rejected" : 'missing version is rejected');
    }
};

done_testing();
