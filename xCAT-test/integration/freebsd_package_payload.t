#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

my ($rpm, $deb, $perl_rpm, $perl_deb) = @ENV{qw(XCAT_FREEBSD_SERVER_RPM XCAT_FREEBSD_SERVER_DEB
    XCAT_FREEBSD_PERL_RPM XCAT_FREEBSD_PERL_DEB)};
plan skip_all => 'Set XCAT_FREEBSD_SERVER_RPM/DEB and XCAT_FREEBSD_PERL_RPM/DEB to built packages'
    if grep { !defined($_) } ($rpm, $deb, $perl_rpm, $perl_deb);
die 'Package artifacts must be regular files' if grep { !-f $_ } ($rpm, $deb, $perl_rpm, $perl_deb);

sub capture {
    open(my $command, '-|', @_) or die "Cannot run $_[0]: $!";
    my $text = do { local $/; <$command> };
    close($command) or die "$_[0] failed";
    return $text;
}

my %payload = (
    (map { ("/opt/xcat/lib/perl/xCAT/FreeBSD$_.pm", '-rw-r--r--') } qw(Boot Config Image Install)),
    '/opt/xcat/lib/perl/xCAT_plugin/freebsd.pm' => '-rw-r--r--',
    '/opt/xcat/share/xcat/install/freebsd/buildmfsbsd.sh' => '-rwxr-xr-x',
    '/opt/xcat/share/xcat/install/freebsd/xcat-install' => '-rwxr-xr-x',
    (map { ("/opt/xcat/share/xcat/install/freebsd/$_", '-rw-r--r--') }
        qw(xcat-install-lib.sh installerconfig.tmpl patch-bsdinstall-umount.sh)),
);
my $requirements = capture('rpm', '-qp', '--requires', $rpm);
for my $required ('/usr/bin/ssh-keygen', map { "perl($_)" } qw(IO::Uncompress::Gunzip JSON MIME::Base64 Digest::SHA)) {
    like($requirements, qr/^\Q$required\E$/m, "RPM requires $required");
}
my $rpm_files = capture('rpm', '-qp', '--queryformat',
    '[%{FILENAMES}\t%{FILEMODES:perms}\t%{FILEUSERNAME}/%{FILEGROUPNAME}\n]', $rpm);
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
done_testing();
