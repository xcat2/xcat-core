#!/usr/bin/env perl
# mock creates --resultdir and its logs as chrootuid, and buildrpms.pl passes a relative
# one under a tree it owns as root. These assertions read the RENDERED configuration, and
# check which owner the result directories get. native/mock_resultdir_owner.t runs mock's
# loader and the real chown.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);

# Record chown instead of doing it, so the test runs without root.
our @CHOWNED;
BEGIN {
    *CORE::GLOBAL::chown = sub {
        my ($uid, $gid, @files) = @_;
        push @CHOWNED, map { [ $uid, $gid, $_ ] } @files;
        return scalar @files;
    };
}
use XCAT::BuildUtils qw(mock_config_text);

my $ppc = <<'CFG';
config_opts['root'] = 'openeuler-24.03-ppc64le'
config_opts['target_arch'] = 'ppc64le'
config_opts['chrootuid'] = 1000
config_opts['chrootgid'] = 1000
config_opts['useradd'] = '/usr/sbin/useradd -o -m -u {{chrootuid}} -g {{chrootgid}} -d {{chroothome}} -N {{chrootuser}}'
config_opts['use_bootstrap'] = False
CFG

my $x86 = <<'CFG';
include('templates/openeuler-24.03.tpl')
config_opts['root'] = 'openeuler-24.03sp4-x86_64'
config_opts['target_arch'] = 'x86_64'
CFG

# mock takes the last assignment.
sub effective {
    my ($text, $opt) = @_;
    my $v;
    for my $line (split /\n/, $text) {
        $v = $1 if $line =~ /\Aconfig_opts\['\Q$opt\E'\]\s*=\s*(.+?)\s*\z/;
    }
    return $v;
}

my $out = mock_config_text('xCAT', 'openeuler-24.03-ppc64le', $ppc, 1790988617);
is(effective($out, 'chrootuid'), '1000', 'the build uid the target declares is preserved');
is(effective($out, 'chrootgid'), '1000', 'and so is the group');
is(effective($out, 'root'), '"xCAT-openeuler-24.03-ppc64le"', 'the chroot is still named per package');

my $plain = mock_config_text('xCAT', 'openeuler-24.03sp4-x86_64', $x86, 1790988617);
is(effective($plain, 'chrootuid'), undef, 'a target that declares no uid is left to mock');
is(effective($plain, 'chrootgid'), undef, 'and no group is invented for it');
is(effective($plain, 'target_arch'), "'x86_64'", 'nothing else in the base configuration changes');

like($out, qr/\Qconfig_opts['environment']['SOURCE_DATE_EPOCH'] = '1790988617'\E/,
    'the reproducible build date is passed into the chroot');
like($out, qr/\Qconfig_opts['isolation'] = 'simple'\E/, 'nspawn is avoided');
like(mock_config_text('perl-xCAT', 'openeuler-24.03-ppc64le', $ppc, 1),
    qr/\Qconfig_opts['chroot_additional_packages'] = 'perl-generators'\E/,
    'perl-xCAT still gets perl-generators on an rpm-md target');
unlike(mock_config_text('perl-xCAT', 'opensuse-leap-15.6-x86_64', $x86, 1),
    qr/perl-generators/, 'and still does not on a SUSE target');

# prepare_mock_resultdirs gives the result directories, and the files a previous
# build left in them, to the owner mock's loader reports.
my $tmp = tempdir(CLEANUP => 1);
my @dirs = ("$tmp/rpms", "$tmp/rpms/SRPMS");
make_path(@dirs);
write_text("$_/build.log", "interrupted\n") for @dirs;
write_text("$tmp/rpms/SRPMS/xCAT-2.19.1-1.src.rpm", '');
my $chroot = 'xCAT-openeuler-24.03-ppc64le';

my (@asked, @owner);
no warnings 'redefine';
local *XCAT::BuildUtils::mock_build_owner = sub { push @asked, [@_]; return @owner };
use warnings 'redefine';

@owner = (1000, 135);
@CHOWNED = ();
XCAT::BuildUtils::prepare_mock_resultdirs($chroot, undef, @dirs);
is_deeply(\@asked, [ [ $chroot, undef ] ], 'the owner comes from the chroot mock builds with');
is_deeply([ sort { $a->[2] cmp $b->[2] } @CHOWNED ],
    [ map { [ 1000, 135, $_ ] } sort(@dirs, "$tmp/rpms/build.log",
        "$tmp/rpms/SRPMS/build.log", "$tmp/rpms/SRPMS/xCAT-2.19.1-1.src.rpm") ],
    'both directories and the files left in them go to that uid and gid');
is((stat $_)[2] & 07777, 0775, "$_ is group-writable") for @dirs;

@owner = ($>, 135);
@CHOWNED = ();
XCAT::BuildUtils::prepare_mock_resultdirs($chroot, undef, "$tmp/caller");
is_deeply(\@CHOWNED, [], 'nothing changes owner when mock builds as the caller');
ok(-d "$tmp/caller", 'the directory is still created');

done_testing();
