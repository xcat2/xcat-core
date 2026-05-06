use strict;
use warnings;

use Cwd qw(realpath);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";

use xCAT::SvrUtils;
use imgutils;

my @ubuntu_2404_search = xCAT::SvrUtils::get_os_search_list('ubuntu24.04');
is_deeply(
    \@ubuntu_2404_search,
    ['ubuntu24.04'],
    'leading-zero minor release lookup does not fall back to the major-only suffix'
);

my @ubuntu_point_search = xCAT::SvrUtils::get_os_search_list('ubuntu24.04.1');
is_deeply(
    \@ubuntu_point_search,
    [qw(ubuntu24.04.1 ubuntu24.04.0 ubuntu24.04)],
    'point release lookup can fall back within the same leading-zero minor release'
);

my @rocky_search = xCAT::SvrUtils::get_os_search_list('rocky9.6');
is_deeply(
    \@rocky_search,
    [qw(rocky9.6 rocky9.5 rocky9.4 rocky9.3 rocky9.2 rocky9.1 rocky9.0 rocky9)],
    'non-leading-zero minor release lookup keeps existing major-version fallback behavior'
);

my @ol_search = xCAT::SvrUtils::get_os_search_list('ol8.4.0');
is_deeply(
    \@ol_search,
    [qw(ol8.4.0 ol8.4 ol8.3 ol8.2 ol8.1 ol8.0 ol8)],
    'trailing zero update release lookup can fall back to the major.minor release'
);

ok(
    xCAT::SvrUtils::_profile_file_matches(
        'compute.ubuntu24.04.x86_64.pkglist',
        'ubuntu24.04',
        'ubuntu24',
        'subiquity',
        'x86_64'
    ),
    'profile discovery treats ubuntu24.04 as the OS suffix and x86_64 as the arch suffix'
);

ok(
    xCAT::SvrUtils::_profile_file_matches(
        'compute.rocky9.x86_64.pkglist',
        'rocky9.6',
        'rocky9',
        'rocky9',
        'x86_64'
    ),
    'profile discovery keeps major-version fallback assets eligible for non-leading-zero minor releases'
);

ok(
    xCAT::SvrUtils::_profile_file_matches(
        'compute.ol8.4.x86_64.pkglist',
        'ol8.4.0',
        'ol8',
        'ol8',
        'x86_64'
    ),
    'profile discovery lets update releases fall back to major.minor assets'
);

ok(
    !xCAT::SvrUtils::_profile_file_matches(
        'compute.ubuntu24.x86_64.pkglist',
        'ubuntu24.04',
        'ubuntu24',
        'subiquity',
        'x86_64'
    ),
    'profile discovery does not treat ubuntu24 as equivalent to ubuntu24.04'
);

ok(
    xCAT::SvrUtils::_profile_file_matches(
        'compute.ubuntu24.04.pkglist',
        'ubuntu24.04',
        'ubuntu24',
        'subiquity',
        'x86_64'
    ),
    'profile discovery accepts dotted Ubuntu OS-only suffixes'
);

ok(
    xCAT::SvrUtils::_profile_file_matches(
        'compute.ubuntu24.04.x86_64.otherpkgs.pkglist',
        'ubuntu24.04',
        'ubuntu24',
        'subiquity',
        'x86_64'
    ),
    'profile discovery handles compound package-list extensions after dotted Ubuntu suffixes'
);

ok(
    xCAT::SvrUtils::_profile_file_matches(
        'compute.otherpkgs.pkglist',
        'ubuntu24.04',
        'ubuntu24',
        'subiquity',
        'x86_64'
    ),
    'profile discovery keeps profile-only compound package-list assets eligible'
);

my $svrutils_dir = tempdir(CLEANUP => 1);
_write_file(File::Spec->catfile($svrutils_dir, 'compute.pkglist'), "default\n");
_write_file(File::Spec->catfile($svrutils_dir, 'compute.ubuntu24.x86_64.pkglist'), "wrong\n");

is(
    xCAT::SvrUtils::get_pkglist_file_name($svrutils_dir, 'compute', 'ubuntu24.04', 'x86_64', 'subiquity'),
    File::Spec->catfile($svrutils_dir, 'compute.pkglist'),
    'SvrUtils lookup does not fall back from ubuntu24.04 to ubuntu24'
);

_write_file(File::Spec->catfile($svrutils_dir, 'compute.ubuntu24.04.x86_64.pkglist'), "exact\n");
is(
    xCAT::SvrUtils::get_pkglist_file_name($svrutils_dir, 'compute', 'ubuntu24.04', 'x86_64', 'subiquity'),
    File::Spec->catfile($svrutils_dir, 'compute.ubuntu24.04.x86_64.pkglist'),
    'SvrUtils lookup selects exact dotted Ubuntu arch-specific pkglist'
);

unlink File::Spec->catfile($svrutils_dir, 'compute.ubuntu24.04.x86_64.pkglist');
_write_file(File::Spec->catfile($svrutils_dir, 'compute.ubuntu24.04.pkglist'), "release\n");
is(
    xCAT::SvrUtils::get_pkglist_file_name($svrutils_dir, 'compute', 'ubuntu24.04.1', 'x86_64', 'subiquity'),
    File::Spec->catfile($svrutils_dir, 'compute.ubuntu24.04.pkglist'),
    'SvrUtils lookup allows Ubuntu point releases to fall back to the same major.minor release'
);

my $svrutils_rpm_dir = tempdir(CLEANUP => 1);
_write_file(File::Spec->catfile($svrutils_rpm_dir, 'compute.pkglist'), "default\n");
_write_file(File::Spec->catfile($svrutils_rpm_dir, 'compute.rocky9.x86_64.pkglist'), "major\n");

is(
    xCAT::SvrUtils::get_pkglist_file_name($svrutils_rpm_dir, 'compute', 'rocky9.6', 'x86_64', 'rocky9'),
    File::Spec->catfile($svrutils_rpm_dir, 'compute.rocky9.x86_64.pkglist'),
    'SvrUtils lookup keeps major-version fallback for non-leading-zero minor releases'
);

_write_file(File::Spec->catfile($svrutils_rpm_dir, 'compute.ol8.4.x86_64.pkglist'), "minor\n");
is(
    xCAT::SvrUtils::get_pkglist_file_name($svrutils_rpm_dir, 'compute', 'ol8.4.0', 'x86_64', 'ol8'),
    File::Spec->catfile($svrutils_rpm_dir, 'compute.ol8.4.x86_64.pkglist'),
    'SvrUtils lookup lets update releases fall back to major.minor assets before major-only assets'
);

my $imgutils_dir = tempdir(CLEANUP => 1);
my $real_imgutils_dir = realpath($imgutils_dir) || $imgutils_dir;
_write_file(File::Spec->catfile($imgutils_dir, 'compute.pkglist'), "default\n");
_write_file(File::Spec->catfile($imgutils_dir, 'compute.ubuntu24.x86_64.pkglist'), "wrong\n");

is(
    imgutils::get_profile_def_filename('ubuntu24.04', 'compute', 'x86_64', $imgutils_dir, 'pkglist'),
    File::Spec->catfile($real_imgutils_dir, 'compute.pkglist'),
    'imgutils lookup does not fall back from ubuntu24.04 to ubuntu24'
);

_write_file(File::Spec->catfile($imgutils_dir, 'compute.ubuntu24.04.x86_64.pkglist'), "exact\n");
is(
    imgutils::get_profile_def_filename('ubuntu24.04', 'compute', 'x86_64', $imgutils_dir, 'pkglist'),
    File::Spec->catfile($real_imgutils_dir, 'compute.ubuntu24.04.x86_64.pkglist'),
    'imgutils lookup selects exact dotted Ubuntu arch-specific pkglist'
);

is(
    imgutils::get_profile_def_filename('ubuntu24.04.1', 'compute', 'x86_64', $imgutils_dir, 'pkglist'),
    File::Spec->catfile($real_imgutils_dir, 'compute.ubuntu24.04.x86_64.pkglist'),
    'imgutils lookup allows Ubuntu point releases to fall back to the same major.minor release'
);

my $imgutils_rpm_dir = tempdir(CLEANUP => 1);
my $real_imgutils_rpm_dir = realpath($imgutils_rpm_dir) || $imgutils_rpm_dir;
_write_file(File::Spec->catfile($imgutils_rpm_dir, 'compute.pkglist'), "default\n");
_write_file(File::Spec->catfile($imgutils_rpm_dir, 'compute.rocky9.x86_64.pkglist'), "major\n");

is(
    imgutils::get_profile_def_filename('rocky9.6', 'compute', 'x86_64', $imgutils_rpm_dir, 'pkglist'),
    File::Spec->catfile($real_imgutils_rpm_dir, 'compute.rocky9.x86_64.pkglist'),
    'imgutils lookup keeps major-version fallback for non-leading-zero minor releases'
);

_write_file(File::Spec->catfile($imgutils_rpm_dir, 'compute.ol8.4.x86_64.pkglist'), "minor\n");
is(
    imgutils::get_profile_def_filename('ol8.4.0', 'compute', 'x86_64', $imgutils_rpm_dir, 'pkglist'),
    File::Spec->catfile($real_imgutils_rpm_dir, 'compute.ol8.4.x86_64.pkglist'),
    'imgutils lookup lets update releases fall back to major.minor assets before major-only assets'
);

done_testing();

sub _write_file {
    my ($path, $content) = @_;

    open(my $fh, '>', $path) or die "Cannot write $path: $!";
    print {$fh} $content;
    close($fh);

    return;
}
