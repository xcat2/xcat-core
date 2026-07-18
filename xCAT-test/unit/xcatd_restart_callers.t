#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

my $unit = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'etc', 'init.d', 'xcatd.service' )
);
unlike( $unit, qr{/etc/init\.d/xcatd},
    'the native systemd unit does not invoke the legacy script' );
like( $unit, qr{^ExecStart=.*?/usr/sbin/xcatd}m,
    'the native systemd unit starts xcatd directly' );

my $imgport = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', 'imgport.pm' )
);
like( $imgport, qr{system\("\$::XCATROOT/sbin/restartxcatd"\)},
    'imgport preserves the xcatd fast-restart path' );
unlike( $imgport, qr{xCAT::Utils->restartservice\("xcatd"\)},
    'imgport does not replace a fast restart with a full service restart' );
unlike( $imgport, qr{system\("/etc/init\.d/xcatd},
    'imgport no longer hard-codes the legacy init path' );

my %reload_callers = (
    'xCAT-OpenStack Debian scriptlet' => 'xCAT-OpenStack/debian/postinst',
    'xCAT-rmc Debian scriptlet' => 'xCAT-rmc/debian/postinst',
    'perl-xCAT Debian scriptlet' => 'perl-xCAT/debian/postrm',
);

foreach my $name ( sort keys %reload_callers ) {
    my $caller = read_file(
        File::Spec->catfile( $repo_root, split( '/', $reload_callers{$name} ) )
    );
    like( $caller, qr{/sbin/restartxcatd -r},
        "$name preserves xcatd fast-reload semantics" );
    unlike( $caller, qr{systemctl restart xcatd|/etc/init\.d/xcatd},
        "$name does not perform a full restart or require the legacy init path" );
}

my %restart_callers = (
    'xCAT-OpenStack RPM scriptlet' => 'xCAT-OpenStack/xCAT-OpenStack.spec',
    'xCAT-UI RPM scriptlet' => 'xCAT-UI/xCAT-UI.spec',
);

foreach my $name ( sort keys %restart_callers ) {
    my $caller = read_file(
        File::Spec->catfile( $repo_root, split( '/', $restart_callers{$name} ) )
    );
    like( $caller, qr{/sbin/restartxcatd},
        "$name preserves xcatd fast-restart semantics" );
    unlike( $caller, qr{systemctl restart xcatd|/etc/init\.d/xcatd},
        "$name does not perform a full restart or require the legacy init path" );
}

my $xcatsn_deb = read_file(
    File::Spec->catfile( $repo_root, 'xCATsn', 'debian', 'postinst' )
);
like( $xcatsn_deb,
    qr{systemctl start xcatd\.service.*?elif \[ -x /etc/init\.d/xcatd \]}s,
    'xCATsn Debian starts xcatd under the native service manager' );

my $xcatsn_spec = read_file(
    File::Spec->catfile( $repo_root, 'xCATsn', 'xCATsn.spec' )
);
like( $xcatsn_spec,
    qr{systemctl restart xcatd\.service.*?elif \[ -x /etc/init\.d/xcatd \]}s,
    'xCATsn RPM retains its existing service-node restart with a legacy fallback' );

my $perl_xcat_spec = read_file(
    File::Spec->catfile( $repo_root, 'perl-xCAT', 'perl-xCAT.spec' )
);
unlike( $perl_xcat_spec, qr{/etc/init\.d/xcatd},
    'perl-xCAT upgrade logic no longer assumes the legacy init path exists' );
like( $perl_xcat_spec, qr{\$RPM_INSTALL_PREFIX0/sbin/xcatd},
    'perl-xCAT detects the installed server independently of its init system' );

done_testing();
