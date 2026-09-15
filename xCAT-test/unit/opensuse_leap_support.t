#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use Cwd qw(realpath);

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";

require sles;
use xCAT::SvrUtils;
use xCAT::Template;
use imgutils;

my $leap_compute_template_path = "$FindBin::Bin/../../xCAT-server/share/xcat/install/sles/compute.leap15.tmpl";
open(my $leap_compute_template_fh, '<', $leap_compute_template_path) or die "Cannot read Leap compute template: $!";
my $leap_compute_template = do { local $/; <$leap_compute_template_fh> };
close($leap_compute_template_fh);

like($leap_compute_template, qr/<product>Leap<\/product>/, 'Leap install template selects Leap base product');
like($leap_compute_template, qr/<self_update config:type="boolean">false<\/self_update>/, 'Leap install template disables installer self-update');
like($leap_compute_template, qr/<do_online_update config:type="boolean">false<\/do_online_update>/, 'Leap install template disables online update');

my $leap_compute_pkglist_path = "$FindBin::Bin/../../xCAT-server/share/xcat/install/sles/compute.leap15.pkglist";
open(my $leap_compute_pkglist_fh, '<', $leap_compute_pkglist_path) or die "Cannot read Leap compute pkglist: $!";
my $leap_compute_pkglist = do { local $/; <$leap_compute_pkglist_fh> };
close($leap_compute_pkglist_fh);

like($leap_compute_pkglist, qr/^\@base$/m, 'Leap compute install pkglist requests a non-empty base pattern');
unlike($leap_compute_pkglist, qr/^(?:insserv-compat|net-tools-deprecated|ntp)$/m, 'Leap compute install pkglist avoids unavailable SLE package names');

my $sle15_netboot_pkglist_path = "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/sles/compute.sle15.pkglist";
open(my $sle15_netboot_pkglist_fh, '<', $sle15_netboot_pkglist_path) or die "Cannot read SLE 15 netboot pkglist: $!";
my $sle15_netboot_pkglist = do { local $/; <$sle15_netboot_pkglist_fh> };
close($sle15_netboot_pkglist_fh);

like($sle15_netboot_pkglist, qr/^xfsprogs$/m, 'SLE 15 netboot pkglist includes xfs tools required by the xCAT dracut module');
is(xCAT::Template::_sle15_install_product_name('Product-SLES'), 'SLES', 'SLE 15 install source keeps the generic SLES product');
is(xCAT::Template::_sle15_install_product_name('Module-Basesystem'), 'sle-module-basesystem', 'SLE 15 install source keeps regular modules');
is(xCAT::Template::_sle15_install_product_name('Module-SAP-Applications'), undef, 'SLE 15 install source skips SAP application module');
is(xCAT::Template::_sle15_install_product_name('Module-SAP-Business-One'), undef, 'SLE 15 install source skips SAP Business One module');
is(xCAT::Template::_sle15_install_product_name('Product-SLES_SAP'), undef, 'SLE 15 install source skips SAP product media');

my $sle_post_common_path = "$FindBin::Bin/../../xCAT-server/share/xcat/install/scripts/post.sles.common";
open(my $sle_post_common_fh, '<', $sle_post_common_path) or die "Cannot read SLE post-install script: $!";
my $sle_post_common = do { local $/; <$sle_post_common_fh> };
close($sle_post_common_fh);

like($sle_post_common, qr/systemctl stop firewalld\.service/, 'SLE post-install script stops firewalld on systemd releases');
like($sle_post_common, qr/systemctl disable firewalld\.service/, 'SLE post-install script disables firewalld after stateful install');

my $tmpdir = tempdir(CLEANUP => 1);

open(my $treeinfo, '>', "$tmpdir/.treeinfo") or die "Cannot write .treeinfo: $!";
print {$treeinfo} <<'EOF';
[release]
name = openSUSE Leap
version = 15.6

[general]
arch = x86_64
family = openSUSE Leap
name = openSUSE Leap 15.6
version = 15.6
platforms = x86_64,xen

[images-x86_64]
kernel = boot/x86_64/loader/linux
initrd = boot/x86_64/loader/initrd
EOF
close($treeinfo);

my ($tree_dist, $tree_arch) = xCAT_plugin::sles::_detect_opensuse_leap_treeinfo($tmpdir);
is($tree_dist, 'leap15.6', 'detects openSUSE Leap distname from .treeinfo');
is($tree_arch, 'x86_64', 'detects openSUSE Leap arch from .treeinfo');

my $media = <<'EOF';
openSUSE - openSUSE-Leap-15.6-NET-x86_64-Build710.3-Media
openSUSE-Leap-15.6-NET-x86_64-Build710.3
1
EOF
my $products = "/ openSUSE-Leap 15.6-1\n";
my ($media_dist, $media_arch) = xCAT_plugin::sles::_detect_opensuse_leap_media($media, $products);
is($media_dist, 'leap15.6', 'detects openSUSE Leap distname from media files');
is($media_arch, 'x86_64', 'detects openSUSE Leap arch from media files');

my ($unsupported_dist) = xCAT_plugin::sles::_detect_opensuse_leap_media(
    "openSUSE - openSUSE-Leap-16.0-NET-x86_64-Media\n",
    "/ openSUSE-Leap 16.0-1\n"
);
is($unsupported_dist, undef, 'does not detect unvalidated openSUSE Leap 16 media as supported');
ok(xCAT_plugin::sles::_copycd_distname_supported('leap15.6'), 'copycd accepts explicit Leap distname override');
ok(!xCAT_plugin::sles::_copycd_distname_supported('leap16.0'), 'copycd rejects unvalidated Leap 16 distname override');
ok(!xCAT_plugin::sles::_copycd_distname_supported('opensuse15.6'), 'copycd does not accept generic openSUSE distname override');

my %commands = %{ xCAT_plugin::sles->handled_commands };
like($commands{mkinstall}, qr/leap15\.\*/, 'mkinstall handles openSUSE Leap 15 nodes');
like($commands{mknetboot}, qr/leap15\.\*/, 'mknetboot handles openSUSE Leap 15 nodes');
like($commands{mkstatelite}, qr/leap15\.\*/, 'mkstatelite handles openSUSE Leap 15 nodes');

my @os_search = xCAT::SvrUtils::get_os_search_list('leap15.6');
is_deeply(
    \@os_search,
    [qw(leap15.6 leap15.5 leap15.4 leap15.3 leap15.2 leap15.1 leap15.0 leap15 sle15)],
    'openSUSE Leap 15.x searches exact, minor, major, then SLE 15 fallback'
);

my @unsupported_os_search = xCAT::SvrUtils::get_os_search_list('leap16.0');
unlike(
    join(' ', @unsupported_os_search),
    qr/\bsle16\b/,
    'openSUSE Leap 16 does not silently use an unvalidated SLE 16 fallback'
);

my $install_dir = tempdir(CLEANUP => 1);
open(my $tmpl, '>', "$install_dir/compute.leap15.tmpl") or die "Cannot write openSUSE template: $!";
print {$tmpl} "opensuse template\n";
close($tmpl);
open(my $compute_fallback_tmpl, '>', "$install_dir/compute.sle15.tmpl") or die "Cannot write compute SLE template: $!";
print {$compute_fallback_tmpl} "sles template\n";
close($compute_fallback_tmpl);
open(my $fallback_tmpl, '>', "$install_dir/service.sle15.tmpl") or die "Cannot write SLE template: $!";
print {$fallback_tmpl} "sles template\n";
close($fallback_tmpl);
open(my $install_pkglist, '>', "$install_dir/compute.leap15.pkglist") or die "Cannot write openSUSE install pkglist: $!";
print {$install_pkglist} "chrony\n";
close($install_pkglist);
open(my $install_fallback_pkglist, '>', "$install_dir/service.sle15.pkglist") or die "Cannot write SLE install pkglist: $!";
print {$install_fallback_pkglist} "ntp\n";
close($install_fallback_pkglist);

is(
    xCAT::SvrUtils::get_tmpl_file_name($install_dir, 'compute', 'leap15.6', 'x86_64'),
    "$install_dir/compute.leap15.tmpl",
    'openSUSE template lookup prefers leap15 over SLE 15'
);
is(
    xCAT::SvrUtils::get_tmpl_file_name($install_dir, 'service', 'leap15.6', 'x86_64'),
    "$install_dir/service.sle15.tmpl",
    'openSUSE template lookup can fall back to SLE 15'
);
is(
    xCAT::SvrUtils::get_pkglist_file_name($install_dir, 'compute', 'leap15.6', 'x86_64'),
    "$install_dir/compute.leap15.pkglist",
    'openSUSE install pkglist lookup prefers leap15 over SLE 15'
);
is(
    xCAT::SvrUtils::get_pkglist_file_name($install_dir, 'service', 'leap15.6', 'x86_64'),
    "$install_dir/service.sle15.pkglist",
    'openSUSE install pkglist lookup can fall back to SLE 15'
);

my $table_netboot_dir = tempdir(CLEANUP => 1);
open(my $table_opensuse_pkglist, '>', "$table_netboot_dir/compute.leap15.pkglist") or die "Cannot write openSUSE table pkglist: $!";
print {$table_opensuse_pkglist} "zypper\n";
close($table_opensuse_pkglist);
open(my $table_pkglist, '>', "$table_netboot_dir/compute.sle15.pkglist") or die "Cannot write table pkglist: $!";
print {$table_pkglist} "aaa_base\n";
close($table_pkglist);
open(my $table_exlist, '>', "$table_netboot_dir/compute.sle15.exlist") or die "Cannot write table exlist: $!";
print {$table_exlist} "/tmp\n";
close($table_exlist);
open(my $table_postinstall, '>', "$table_netboot_dir/compute.sle15.postinstall") or die "Cannot write table postinstall: $!";
print {$table_postinstall} "#!/bin/sh\n";
close($table_postinstall);
chmod 0755, "$table_netboot_dir/compute.sle15.postinstall";

is(
    xCAT::SvrUtils::get_pkglist_file_name($table_netboot_dir, 'compute', 'leap15.6', 'x86_64'),
    "$table_netboot_dir/compute.leap15.pkglist",
    'openSUSE diskless table lookup prefers leap15 pkglist over SLE 15'
);
unlink "$table_netboot_dir/compute.leap15.pkglist";
is(
    xCAT::SvrUtils::get_pkglist_file_name($table_netboot_dir, 'compute', 'leap15.6', 'x86_64', 'sle15'),
    "$table_netboot_dir/compute.sle15.pkglist",
    'openSUSE diskless table lookup can fall back to SLE 15 pkglist'
);
is(
    xCAT::SvrUtils::get_exlist_file_name($table_netboot_dir, 'compute', 'leap15.6', 'x86_64', 'sle15'),
    "$table_netboot_dir/compute.sle15.exlist",
    'openSUSE diskless table lookup can fall back to SLE 15 exlist'
);
is(
    xCAT::SvrUtils::get_postinstall_file_name($table_netboot_dir, 'compute', 'leap15.6', 'x86_64', 'sle15'),
    "$table_netboot_dir/compute.sle15.postinstall",
    'openSUSE diskless table lookup can fall back to SLE 15 postinstall'
);

my $netboot_dir = tempdir(CLEANUP => 1);
open(my $opensuse_pkglist, '>', "$netboot_dir/compute.leap15.pkglist") or die "Cannot write openSUSE pkglist: $!";
print {$opensuse_pkglist} "zypper\n";
close($opensuse_pkglist);
open(my $pkglist, '>', "$netboot_dir/compute.sle15.pkglist") or die "Cannot write SLE pkglist: $!";
print {$pkglist} "aaa_base\n";
close($pkglist);
my $real_netboot_dir = realpath($netboot_dir) || $netboot_dir;

is(
    imgutils::get_profile_def_filename('leap15.6', 'compute', 'x86_64', $netboot_dir, 'pkglist'),
    "$real_netboot_dir/compute.leap15.pkglist",
    'openSUSE diskless profile lookup prefers leap15 pkglist over SLE 15'
);
unlink "$netboot_dir/compute.leap15.pkglist";
is(
    imgutils::get_profile_def_filename('leap15.6', 'compute', 'x86_64', $netboot_dir, 'pkglist'),
    "$real_netboot_dir/compute.sle15.pkglist",
    'openSUSE diskless profile lookup falls back to SLE 15 pkglist'
);

done_testing();
