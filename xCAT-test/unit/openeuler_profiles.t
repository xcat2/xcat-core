#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::SvrUtils;
use xCAT::Utils;

sub asset {
    my ($directory, $name) = @_;
    my $path = File::Spec->catfile($directory, $name);
    open(my $file, '>', $path) or die "Cannot create $path: $!";
    print {$file} "$name\n";
    close($file) or die "Cannot close $path: $!";
    return $path;
}

for my $case (
    ['openeuler20.03sp4', [qw(openeuler20.03sp4 openeuler20.03 openeuler)], '20', '03sp4'],
    ['openeuler22.03sp4', [qw(openeuler22.03sp4 openeuler22.03 openeuler)], '22', '03sp4'],
    ['openeuler24.03sp1', [qw(openeuler24.03sp1 openeuler24.03 openeuler)], '24', '03sp1'],
    ['openeuler24.03sp3', [qw(openeuler24.03sp3 openeuler24.03 openeuler)], '24', '03sp3'],
    ['openeuler24.03sp4', [qw(openeuler24.03sp4 openeuler24.03 openeuler)], '24', '03sp4'],
    ['openeuler24.03', [qw(openeuler24.03 openeuler)], '24', '03'],
) {
    my ($os, $expected, $major, $minor) = @$case;
    my $base = "openeuler$major.03";
    is_deeply([xCAT::SvrUtils::get_os_search_list($os)], $expected,
        "$os falls back within its LTS family without an earlier SP");
    is_deeply([xCAT::SvrUtils::parseosver($os)], ['openeuler', $major, $minor],
        "$os keeps the service pack in osdistro version fields");
    is(xCAT::SvrUtils->getplatform($os), 'openeuler', "$os uses native platform assets");

    foreach my $arch (qw(x86_64 ppc64le)) {
        subtest "$os $arch assets" => sub {
            my $directory = tempdir(CLEANUP => 1);
            my $fallback = asset($directory, 'compute.pkglist');
            asset($directory, 'compute.openeuler24.pkglist');
            asset($directory, 'compute.openeuler22.03sp3.pkglist');
            asset($directory, 'compute.openeuler24.03sp2.pkglist');
            is(xCAT::SvrUtils::get_file_name($directory, 'pkglist', 'compute', $os, $arch, 'openeuler24'),
                $fallback, 'year-only and other-SP candidates do not satisfy lookup');

            my $family = asset($directory, "compute.openeuler.$arch.pkglist");
            is(xCAT::SvrUtils::get_file_name($directory, 'pkglist', 'compute', $os, $arch, 'openeuler24'),
                $family, 'native family asset is eligible');
            my $release = asset($directory, "compute.$base.pkglist");
            is(xCAT::SvrUtils::get_file_name($directory, 'pkglist', 'compute', $os, $arch, 'openeuler24'),
                $release, 'same LTS asset wins over generic native assets');
            my $exact = asset($directory, "compute.$os.$arch.pkglist");
            is(xCAT::SvrUtils::get_file_name($directory, 'pkglist', 'compute', $os, $arch, 'openeuler24'),
                $exact, 'exact service pack and architecture win');
            ok(xCAT::SvrUtils::_profile_file_matches("compute.$os.$arch.otherpkgs.pkglist", $os, 'openeuler24', 'openeuler24', $arch),
                'profile discovery includes compound native package-list suffix');
            ok(!xCAT::SvrUtils::_profile_file_matches("compute.openeuler24.$arch.pkglist", $os, 'openeuler24', 'openeuler24', $arch),
                'profile discovery excludes abbreviated year-only assets');
            my $other_arch = $arch eq 'x86_64' ? 'ppc64le' : 'x86_64';
            ok(!xCAT::SvrUtils::_profile_file_matches("compute.$os.$other_arch.pkglist", $os, 'openeuler24', 'openeuler24', $arch),
                'profile discovery excludes the other architecture');

            my $postinstall = tempdir(CLEANUP => 1);
            foreach my $suffix ('openeuler24', 'openeuler22.03sp3', 'openeuler24.03sp2', "$os.$other_arch") {
                my $path = asset($postinstall, "compute.$suffix.postinstall");
                chmod 0755, $path or die "Cannot make $path executable: $!";
            }
            is(xCAT::SvrUtils->get_postinstall_file_name($postinstall, 'compute', $os, $arch, 'openeuler24'),
                undef, 'postinstall rejects another SP, architecture and abbreviated year');
            my $exact_script = asset($postinstall, "compute.$os.$arch.postinstall");
            is(xCAT::SvrUtils->get_postinstall_file_name($postinstall, 'compute', $os, $arch),
                undef, 'a non-executable postinstall is not returned');
            unlink $exact_script or die "Cannot remove $exact_script: $!";
            my $family_script = asset($postinstall, "compute.openeuler.$arch.postinstall");
            chmod 0755, $family_script or die "Cannot make $family_script executable: $!";
            is(xCAT::SvrUtils->get_postinstall_file_name($postinstall, 'compute', $os, $arch),
                $family_script, 'postinstall can use the executable native family asset');
            my $release_script = asset($postinstall, "compute.$base.postinstall");
            chmod 0755, $release_script or die "Cannot make $release_script executable: $!";
            is(xCAT::SvrUtils->get_postinstall_file_name($postinstall, 'compute', $os, $arch),
                $release_script, 'postinstall prefers the same LTS asset');
            $exact_script = asset($postinstall, "compute.$os.$arch.postinstall");
            chmod 0755, $exact_script or die "Cannot make $exact_script executable: $!";
            is(xCAT::SvrUtils->get_postinstall_file_name($postinstall, 'compute', $os, $arch),
                $exact_script, 'postinstall prefers the exact SP and architecture');
        };
    }
}

is_deeply([xCAT::SvrUtils::get_os_search_list('rocky9.2')],
    [qw(rocky9.2 rocky9.1 rocky9.0 rocky9)], 'EL numeric release fallback is unchanged');
is_deeply([xCAT::SvrUtils::get_os_search_list('ubuntu24.04.1')],
    [qw(ubuntu24.04.1 ubuntu24.04.0 ubuntu24.04)], 'Ubuntu dotted release fallback is unchanged');
is_deeply([xCAT::SvrUtils::parseosver('rhels9.6')],
    ['rhels', '9', '6'], 'existing osdistro numeric fields are unchanged');

{
    no warnings 'redefine';
    my $install = tempdir(CLEANUP => 1);
    my $directory = File::Spec->catdir($install, 'custom', 'netboot', 'openeuler');
    make_path($directory);
    my $synclist = asset($directory, 'compute.openeuler24.03.ppc64le.synclist');
    local *xCAT::TableUtils::getInstallDir = sub { return $install; };
    is(xCAT::SvrUtils->getsynclistfile(undef, 'openeuler24.03sp4', 'ppc64le', 'compute', 'netboot'),
        $synclist, 'image synclist resolves through the native custom directory');
}

{
    package Local::SynclistTable;
    sub getNodesAttribs { return $_[0]->{nodes}; }
    sub getAttribs { return $_[0]->{images}->{$_[1]->{imagename}}; }
}

{
    no warnings 'redefine';
    my $install = tempdir(CLEANUP => 1);
    my %paths;
    foreach my $fixture (
        ['native_boot', 'netboot/openeuler', 'compute.openeuler24.03.ppc64le.synclist'],
        ['native_install', 'install/openeuler', 'service.openeuler24.03sp4.x86_64.synclist'],
        ['legacy_install', 'install/rh', 'compute.rhels9.6.x86_64.synclist'],
        ['image_override', 'netboot/openeuler', 'custom.synclist'],
    ) {
        my ($node, $subdir, $name) = @$fixture;
        my $directory = File::Spec->catdir($install, 'custom', $subdir);
        make_path($directory);
        $paths{$node} = asset($directory, $name);
    }
    my $table = bless {
        nodes => {
            native_boot => [{os => 'openeuler24.03sp4', arch => 'ppc64le', profile => 'compute', provmethod => 'netboot'}],
            native_install => [{os => 'openeuler24.03sp4', arch => 'x86_64', profile => 'service', provmethod => 'install'}],
            legacy_install => [{os => 'rhels9.6', arch => 'x86_64', profile => 'compute', provmethod => 'install'}],
            image_override => [{os => 'openeuler24.03sp4', arch => 'ppc64le', profile => 'compute', provmethod => 'custom-image'}],
        },
        images => {'custom-image' => {synclists => $paths{image_override}}},
    }, 'Local::SynclistTable';
    local *xCAT::TableUtils::getInstallDir = sub { return $install; };
    local *xCAT::Table::new = sub { return $table; };
    is_deeply(xCAT::SvrUtils->getsynclistfile([sort keys %paths]), \%paths,
        'node synclists use native install and netboot directories, preserving legacy and explicit image paths');
    is(xCAT::SvrUtils->getsynclistfile(undef, 'openeuler24.03sp4', 'ppc64le', 'compute', 'netboot', 'custom-image'),
        $paths{image_override}, 'an explicit image synclist overrides native profile lookup');
}

{
    package Local::StatusTable;
    sub getNodesAttribs {
        return {
            oe_install => [{os => 'openeuler24.03sp4'}],
            oe_netboot => [{os => 'openeuler24.03'}],
            el_install => [{os => 'rhels9.6'}],
            other_install => [{os => 'aix72'}],
            other_netboot => [{os => 'notopeneuler24.03'}],
        };
    }
    sub close { return; }
}

{
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return bless {}, 'Local::StatusTable'; };
    my %status = (
        $::STATUS_INSTALLING => [qw(oe_install el_install other_install)],
        $::STATUS_NETBOOTING => [qw(oe_netboot other_netboot)],
        booted => ['ready'],
    );
    xCAT::Utils->filter_nostatusupdate(\%status);
    is_deeply(\%status, {
        $::STATUS_INSTALLING => ['other_install'],
        $::STATUS_NETBOOTING => ['other_netboot'],
        booted => ['ready'],
    }, 'native provisioning feedback is preserved without changing unrelated states');
}

done_testing();
