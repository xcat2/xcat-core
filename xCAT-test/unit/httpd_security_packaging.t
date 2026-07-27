#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($relative_path) = @_;
    my $path = File::Spec->catfile( $repo_root, split( '/', $relative_path ) );
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

my $xcat_spec = read_file('xCAT/xCAT.spec');
like( $xcat_spec, qr{a2enmod headers},
    'management RPM enables mod_headers where Apache requires it' );
like( $xcat_spec,
    qr{if \[ "\$1" = "1" \]; then.*?xcatconfig -i.*?else.*?xcatconfig -u -V.*?systemctl is-active --quiet "\$apachedaemon".*?systemctl reload "\$apachedaemon".*?/etc/init\.d/\$apachedaemon reload}s,
    'management RPM reloads an active Apache service after upgrades' );
like( $xcat_spec, qr{apachedaemon='httpd'.*?apachedaemon='apache2'}s,
    'management RPM covers both EL and SUSE Apache service names' );
like( $xcat_spec,
    qr{/proc/1/root/\. 2>/dev/null.*?systemctl is-active --quiet "\$apachedaemon"}s,
    'management RPM skips service management inside image chroots' );

my $xcatsn_spec = read_file('xCATsn/xCATsn.spec');
like( $xcatsn_spec, qr{a2enmod headers},
    'service-node RPM enables mod_headers where Apache requires it' );
like( $xcatsn_spec,
    qr{apacheserviceunit='httpd\.service'.*?apacheserviceunit='apache2\.service'}s,
    'service-node RPM covers both EL and SUSE Apache service units' );
like( $xcatsn_spec,
    qr{# for install or upgrade restart the daemon.*?/etc/init\.d/\$apachedaemon reload.*?systemctl reload \$apacheserviceunit}s,
    'service-node RPM reloads Apache after installs and upgrades' );

my $xcat_postinst = read_file('xCAT/debian/postinst');
like( $xcat_postinst, qr{a2enmod -q headers.*?/etc/init\.d/apache2 restart}s,
    'management Debian package enables mod_headers before restarting Apache' );

my $xcatsn_postinst = read_file('xCATsn/debian/postinst');
like( $xcatsn_postinst,
    qr{a2enmod -q headers.*?/etc/init\.d/\$apachedaemon reload}s,
    'service-node Debian package enables mod_headers before reloading Apache' );

done_testing();
