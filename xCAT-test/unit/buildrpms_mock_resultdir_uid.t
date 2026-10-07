#!/usr/bin/env perl
# mock creates --resultdir as chrootuid, and buildrpms.pl passes a relative one under a
# root-owned tree. These assertions read the RENDERED configuration, not the builder.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;
use XCAT::BuildUtils qw(mock_config_text);

my $ppc = <<'CFG';
config_opts['root'] = 'openeuler-24.03-ppc64le'
config_opts['target_arch'] = 'ppc64le'
config_opts['chrootuid'] = 1000
config_opts['chrootgid'] = 1000
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
is(effective($out, 'chrootuid'), '0', 'the ppc64le core build writes its resultdir as root');
is(effective($out, 'chrootgid'), '1000', 'the group the target declared is left alone');
is(effective($out, 'root'), '"xCAT-openeuler-24.03-ppc64le"', 'the chroot is still named per package');

my $plain = mock_config_text('xCAT', 'openeuler-24.03sp4-x86_64', $x86, 1790988617);
is(effective($plain, 'chrootuid'), '0', 'a target that declares no uid is pinned to root too');
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

done_testing();
