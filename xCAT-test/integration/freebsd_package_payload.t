#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

my ($rpm, $deb, $perl_rpm, $perl_deb, $meta_rpm, $meta_deb) = @ENV{qw(
    XCAT_FREEBSD_SERVER_RPM XCAT_FREEBSD_SERVER_DEB
    XCAT_FREEBSD_PERL_RPM XCAT_FREEBSD_PERL_DEB
    XCAT_FREEBSD_META_RPM XCAT_FREEBSD_META_DEB)};
plan skip_all => 'Set XCAT_FREEBSD_SERVER, PERL and META RPM/DEB variables to built packages'
    if grep { !defined($_) } ($rpm, $deb, $perl_rpm, $perl_deb, $meta_rpm, $meta_deb);
die 'Package artifacts must be regular files'
    if grep { !-f $_ } ($rpm, $deb, $perl_rpm, $perl_deb, $meta_rpm, $meta_deb);

sub capture {
    open(my $command, '-|', @_) or die "Cannot run $_[0]: $!";
    my $text = do { local $/; <$command> };
    close($command) or die "$_[0] failed";
    return $text;
}

my %payload = (
    (map { ("/opt/xcat/lib/perl/xCAT/FreeBSD$_.pm", '-rw-r--r--') }
        qw(Boot Config Image Install PackagePlan Pkg Postscript Repo RepoImport Update)),
    '/opt/xcat/lib/perl/xCAT_plugin/freebsd.pm' => '-rw-r--r--',
    '/opt/xcat/lib/perl/xCAT_plugin/freebsdrepo.pm' => '-rw-r--r--',
    '/opt/xcat/share/xcat/install/freebsd/buildmfsbsd.sh' => '-rwxr-xr-x',
    '/opt/xcat/share/xcat/install/freebsd/build-dhcpcd.sh' => '-rwxr-xr-x',
    '/opt/xcat/share/xcat/install/freebsd/patches/dhcpcd-10.5.2-ipoib.patch' => '-rw-r--r--',
    '/opt/xcat/share/xcat/install/freebsd/xcat-install' => '-rwxr-xr-x',
    '/opt/xcat/share/xcat/install/freebsd/stage-pkgbase-adapter.sh' => '-rwxr-xr-x',
    '/opt/xcat/share/xcat/install/freebsd/xcat-postscript' => '-rwxr-xr-x',
    (map { ("/opt/xcat/share/xcat/install/freebsd/$_", '-rw-r--r--') }
        qw(xcat-install-lib.sh installerconfig.tmpl patch-bsdinstall-umount.sh
        patch-bsdinstall-bootconfig.sh patch-bsdinstall-mount_aux.sh
        patch-bsdinstall-pkgbase.sh patch-bsdinstall-script.sh patch-bsdinstall-zfsboot.sh
        stage-pkgbase-runtime.sh xcat-package-plan.lua xcat-pkgbase.lua
        xcat-postboot xcat-postscript-packages xcat-postscript-time.c
        xcat-storage xcat-storage-efi.sh
        xcat-storage-hooks.sh patches/pkg-2.6.2-apply.patch)),
);
my $requirements = capture('rpm', '-qp', '--requires', $rpm);
for my $required ('/usr/bin/ssh-keygen', map { "perl($_)" } qw(Archive::Tar IO::Uncompress::Gunzip JSON MIME::Base64 Digest::SHA)) {
    like($requirements, qr/^\Q$required\E$/m, "RPM requires $required");
}
my $rpm_files = capture('rpm', '-qp', '--queryformat',
    '[%{FILENAMES}\t%{FILEMODES:perms}\t%{FILEUSERNAME}/%{FILEGROUPNAME}\n]', $rpm);
like($rpm_files, qr{^/var/lib/xcat\tdrwxr-xr-x\troot/root$}mx,
    'RPM provides the protected parent for installation and postscript state');
for my $path (sort keys %payload) {
    like($rpm_files, qr/^\Q$path\E\t\Q$payload{$path}\E\troot\/root$/m, "RPM packages $path with protected modes");
}
my $dependencies = capture('dpkg-deb', '--field', $deb, 'Depends');
for my $required (qw(openssh-client perl libjson-perl)) {
    like($dependencies, qr/(?:\A|,\s*)\Q$required\E(?:\s*\([^)]*\))?(?:,|\s*\z)/,
        "DEB requires $required");
}
my $deb_files = capture('dpkg-deb', '--contents', $deb);
for my $path (sort keys %payload) {
    like($deb_files, qr/^\Q$payload{$path}\E\s+root\/root\s+.*\s\.\Q$path\E$/m,
        "DEB packages $path with protected modes");
}
like(capture('rpm', '-qp', '--requires', $perl_rpm), qr/^perl\(JSON\)$/m,
    'Perl RPM requires JSON for the boot policy');
like(capture('dpkg-deb', '--field', $perl_deb, 'Depends'),
    qr/(?:\A|,\s*)libjson-perl(?:\s*\([^)]*\))?(?:,|\s*\z)/,
    'Perl DEB requires JSON for the boot policy');
my $policy = '/opt/xcat/lib/perl/xCAT/DHCP/BootPolicy.pm';
like(capture('rpm', '-qp', '--queryformat',
    '[%{FILENAMES}\t%{FILEMODES:perms}\t%{FILEUSERNAME}/%{FILEGROUPNAME}\n]', $perl_rpm),
    qr/^\Q$policy\E\t-rw-r--r--\troot\/root$/m, 'Perl RPM protects the boot policy payload');
like(capture('dpkg-deb', '--contents', $perl_deb),
    qr/^-rw-r--r--\s+root\/root\s+.*\s\.\Q$policy\E$/m, 'Perl DEB protects the boot policy payload');

my $meta_rpm_files = capture('rpm', '-qp', '--queryformat',
    '[%{FILENAMES}\t%{FILEMODES:perms}\t%{FILEUSERNAME}/%{FILEGROUPNAME}\n]', $meta_rpm);
my $meta_deb_files = capture('dpkg-deb', '--contents', $meta_deb);
for my $script (qw(remoteshell.freebsd syncfiles.freebsd syslog.freebsd xcatpackages.freebsd confignetwork confignetwork.freebsd confignetwork-ipoib-dhcp4.freebsd)) {
    my $postscript_path = "/install/postscripts/$script";
    like($meta_rpm_files, qr/^\Q$postscript_path\E\t-rwxr-xr-x\troot\/root$/mx,
        "RPM packages executable $script");
    like($meta_deb_files, qr/^-rwxr-xr-x\s+root\/root\s+.*\s\.\Q$postscript_path\E$/mx,
        "DEB packages executable $script");
}
my $network_planner_path = '/install/postscripts/confignetwork-freebsd.awk';
like($meta_rpm_files, qr{^\Q$network_planner_path\E\t-rwxr-xr-x\troot/root$}mx,
    'RPM packages the native network planner');
like($meta_deb_files, qr{^-rw-r--r--\s+root/root\s+.*\s[.]\Q$network_planner_path\E$}mx,
    'DEB packages the native network planner');

my $rpm_tree = tempdir(CLEANUP => 1);
my $deb_tree = tempdir(CLEANUP => 1);
capture('bsdtar', '-xf', $meta_rpm, '-C', $rpm_tree);
capture('dpkg-deb', '--extract', $meta_deb, $deb_tree);
for my $package_tree (['RPM', $rpm_tree], ['DEB', $deb_tree]) {
    for my $native_script (qw(syslog remoteshell syncfiles ospkgs otherpkgs
        syslog.freebsd remoteshell.freebsd syncfiles.freebsd xcatpackages.freebsd confignetwork confignetwork.freebsd confignetwork-ipoib-dhcp4.freebsd)) {
        my $installed_path = "$package_tree->[1]/install/postscripts/$native_script";
        open(my $installed_script, '<', $installed_path) or BAIL_OUT("Cannot read $installed_path: $!");
        my $interpreter = <$installed_script>;
        close($installed_script) or BAIL_OUT("Cannot close $installed_path: $!");
        is($interpreter, "#!/bin/sh\n", "$package_tree->[0] preserves the native interpreter for $native_script");
    }
    my $planner = "$package_tree->[1]/install/postscripts/confignetwork-freebsd.awk";
    open(my $installed_planner, '<', $planner) or BAIL_OUT("Cannot read $planner: $!");
    my $interpreter = <$installed_planner>;
    close($installed_planner) or BAIL_OUT("Cannot close $planner: $!");
    is($interpreter, "#!/usr/bin/awk -f\n", "$package_tree->[0] preserves the native AWK interpreter");
}
done_testing();
