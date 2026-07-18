#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $helper = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'scripts', 'xcatd-init-compat'
);
my $template = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'etc', 'init.d', 'xcatd'
);

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

sub stage_root {
    my $root = tempdir( CLEANUP => 1 );
    my $scripts = File::Spec->catdir(
        $root, 'opt', 'xcat', 'share', 'xcat', 'scripts'
    );
    make_path($scripts);
    copy( $template, File::Spec->catfile( $scripts, 'xcatd' ) )
      or die "Unable to stage legacy init template: $!";
    return $root;
}

sub run_helper {
    my ( $root, @arguments ) = @_;
    local $ENV{XCAT_COMPAT_ROOT} = $root;
    local $ENV{XCATROOT}         = '/opt/xcat';
    system( '/bin/sh', $helper, @arguments );
    return $? >> 8;
}

sub legacy_init {
    my ($root) = @_;
    return File::Spec->catfile( $root, 'etc', 'init.d', 'xcatd' );
}

my $active_systemd_root = stage_root();
make_path( File::Spec->catdir( $active_systemd_root, 'run', 'systemd', 'system' ) );
make_path( File::Spec->catdir( $active_systemd_root, 'etc', 'init.d' ) );
open( my $old_init, '>', legacy_init($active_systemd_root) )
  or die "Unable to stage old init script: $!";
print {$old_init} "old init script\n";
close($old_init);
is( run_helper( $active_systemd_root, 'uses-systemd' ), 0,
    'an active systemd marker identifies a systemd target' );
is( run_helper( $active_systemd_root, 'configure' ), 0,
    'systemd configuration succeeds' );
ok( !-e legacy_init($active_systemd_root),
    'systemd configuration removes an upgraded legacy init script' );

my $systemd_image_root = stage_root();
make_path( File::Spec->catdir( $systemd_image_root, 'sbin' ) );
symlink( '../lib/systemd/systemd', File::Spec->catfile( $systemd_image_root, 'sbin', 'init' ) )
  or die "Unable to stage systemd init symlink: $!";
is( run_helper( $systemd_image_root, 'uses-systemd' ), 0,
    'a target-root systemd init symlink identifies a systemd image' );
is( run_helper( $systemd_image_root, 'configure' ), 0,
    'systemd image configuration succeeds without a running manager' );
ok( !-e legacy_init($systemd_image_root),
    'systemd images do not receive the legacy init script' );

my $minimal_systemd_root = stage_root();
my $systemd_binary = File::Spec->catfile(
    $minimal_systemd_root, 'usr', 'lib', 'systemd', 'systemd'
);
make_path( File::Spec->catdir( $minimal_systemd_root, 'usr', 'lib', 'systemd' ) );
open( my $minimal_systemd, '>', $systemd_binary )
  or die "Unable to stage minimal systemd binary: $!";
close($minimal_systemd);
chmod 0755, $systemd_binary;
is( run_helper( $minimal_systemd_root, 'uses-systemd' ), 0,
    'an installed systemd binary identifies a stopped or minimal systemd target' );
is( run_helper( $minimal_systemd_root, 'configure' ), 0,
    'minimal systemd target configuration succeeds' );
ok( !-e legacy_init($minimal_systemd_root),
    'minimal systemd targets do not receive the legacy init script' );

my $modern_os_root = stage_root();
make_path( File::Spec->catdir( $modern_os_root, 'etc' ) );
open( my $modern_os_release, '>', File::Spec->catfile( $modern_os_root, 'etc', 'os-release' ) )
  or die "Unable to stage modern os-release: $!";
print {$modern_os_release} qq{ID="rocky"\nVERSION_ID="9.6"\n};
close($modern_os_release);
is( run_helper( $modern_os_root, 'uses-systemd' ), 0,
    'a modern supported distro is systemd even in a stripped-down environment' );
is( run_helper( $modern_os_root, 'configure' ), 0,
    'stripped-down modern distro configuration succeeds' );
ok( !-e legacy_init($modern_os_root),
    'stripped-down modern distros do not receive the legacy init script' );

my $legacy_os_root = stage_root();
make_path( File::Spec->catdir( $legacy_os_root, 'etc' ) );
open( my $legacy_os_release, '>', File::Spec->catfile( $legacy_os_root, 'etc', 'os-release' ) )
  or die "Unable to stage legacy os-release: $!";
print {$legacy_os_release} qq{ID="sles"\nVERSION_ID="11.4"\n};
close($legacy_os_release);
isnt( run_helper( $legacy_os_root, 'uses-systemd' ), 0,
    'SLES 11 remains classified as a legacy init target' );

my $debian_sid_root = stage_root();
make_path( File::Spec->catdir( $debian_sid_root, 'etc' ) );
open( my $debian_sid_release, '>', File::Spec->catfile( $debian_sid_root, 'etc', 'os-release' ) )
  or die "Unable to stage Debian sid os-release: $!";
print {$debian_sid_release} qq{ID=debian\nVERSION_CODENAME=sid\n};
close($debian_sid_release);
is( run_helper( $debian_sid_root, 'uses-systemd' ), 0,
    'Debian testing and sid remain systemd targets without VERSION_ID' );

my $legacy_root = stage_root();
make_path( File::Spec->catdir( $legacy_root, 'sbin' ) );
symlink( 'upstart', File::Spec->catfile( $legacy_root, 'sbin', 'init' ) )
  or die "Unable to stage upstart init symlink: $!";
isnt( run_helper( $legacy_root, 'uses-systemd' ), 0,
    'an upstart target is not classified as systemd' );
is( run_helper( $legacy_root, 'configure' ), 0,
    'legacy configuration succeeds' );
ok( -x legacy_init($legacy_root),
    'legacy configuration materializes an executable init script' );
is( read_file( legacy_init($legacy_root) ), read_file($template),
    'the materialized legacy init script matches the packaged template' );

my $dangling_legacy_root = stage_root();
make_path( File::Spec->catdir( $dangling_legacy_root, 'etc', 'init.d' ) );
symlink( '/missing/xcatd', legacy_init($dangling_legacy_root) )
  or die "Unable to stage dangling init symlink: $!";
is( run_helper( $dangling_legacy_root, 'configure' ), 0,
    'legacy configuration replaces a dangling init symlink' );
ok( !-l legacy_init($dangling_legacy_root),
    'the replacement for a dangling init symlink is a regular file' );
is( read_file( legacy_init($dangling_legacy_root) ), read_file($template),
    'the dangling init symlink replacement matches the packaged template' );

open( my $custom_init, '>', legacy_init($legacy_root) )
  or die "Unable to customize staged init script: $!";
print {$custom_init} "administrator customization\n";
close($custom_init);
is( run_helper( $legacy_root, 'configure' ), 0,
    'reconfiguring a legacy target succeeds' );
is( read_file( legacy_init($legacy_root) ), "administrator customization\n",
    'legacy reconfiguration preserves an existing init script' );
is( run_helper( $legacy_root, 'configure', '--replace' ), 0,
    'RPM-style legacy upgrade configuration succeeds' );
is( read_file( legacy_init($legacy_root) ), read_file($template),
    'RPM-style legacy upgrades refresh the init script from the packaged template' );
is( run_helper( $legacy_root, 'remove' ), 0,
    'legacy cleanup succeeds' );
ok( !-e legacy_init($legacy_root),
    'legacy cleanup removes the generated init script' );

my $rpm_spec = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'xCAT-server.spec' )
);
like( $rpm_spec,
    qr{cp etc/init\.d/xcatd \$RPM_BUILD_ROOT/%\{prefix\}/share/xcat/scripts/xcatd},
    'RPM stages the legacy script as a compatibility template' );
like( $rpm_spec,
    qr{%if 0%\{\?rhel\} && 0%\{\?rhel\} < 7\n%ghost %attr\(0755,root,root\) /etc/init\.d/xcatd},
    'RPM tracks the runtime-created init path only on legacy RHEL' );
like( $rpm_spec,
    qr{%if 0%\{\?suse_version\} && 0%\{\?suse_version\} < 1200\n%ghost %attr\(0755,root,root\) /etc/init\.d/xcatd},
    'RPM tracks the runtime-created init path only on legacy SUSE' );
like( $rpm_spec, qr{xcatd-init-compat.*uses-systemd}s,
    'RPM scriptlets select the init implementation at install time' );
like( $rpm_spec,
    qr{xcatd_init_compat=.*?"\$xcatd_init_compat" configure --replace}s,
    'RPM upgrades refresh an existing SysV init script' );
my @xcatroot_exports =
  ( $rpm_spec =~ /^export XCATROOT="\$RPM_INSTALL_PREFIX0"$/mg );
is( scalar @xcatroot_exports, 2,
    'RPM install and erase scriptlets forward a relocated package root' );
my @empty_init_cleanup =
  ( $rpm_spec =~ /^\s*rmdir \/etc\/init\.d 2>\/dev\/null \|\| true$/mg );
is( scalar @empty_init_cleanup, 1,
    'only RPM systemd upgrades remove an empty legacy init directory' );
like( $rpm_spec,
    qr{%if 0%\{\?suse_version\}\s+%else\s+# Remove only an empty directory.*?rmdir /etc/init\.d 2>/dev/null \|\| true\s+%endif}s,
    'RPM upgrades preserve the SUSE-owned init directory' );
like( $rpm_spec,
    qr{if \[ -e "\$legacy_xcatd_link" \] \|\| \[ -L "\$legacy_xcatd_link" \]},
    'RPM upgrade recognizes enabled state through dangling legacy links' );

done_testing();
