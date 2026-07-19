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

sub stage_systemd_binary {
    my ($root) = @_;
    my $binary = File::Spec->catfile(
        $root, 'usr', 'lib', 'systemd', 'systemd'
    );
    make_path( File::Spec->catdir( $root, 'usr', 'lib', 'systemd' ) );
    open( my $fh, '>', $binary )
      or die "Unable to stage systemd binary: $!";
    close($fh);
    chmod 0755, $binary;
    return $binary;
}

sub run_helper {
    my ( $root, @arguments ) = @_;
    local $ENV{XCAT_COMPAT_ROOT} = $root;
    local $ENV{XCATROOT}         = '/opt/xcat';
    system( '/bin/sh', $helper, @arguments );
    return $? >> 8;
}

sub helper_output {
    my ( $root, @arguments ) = @_;
    local $ENV{XCAT_COMPAT_ROOT} = $root;
    local $ENV{XCATROOT}         = '/opt/xcat';
    open( my $pipe, '-|', '/bin/sh', $helper, @arguments )
      or die "Unable to run compatibility helper: $!";
    my $output = do { local $/; <$pipe> };
    close($pipe) or die "Compatibility helper failed: $?";
    $output =~ s/\s+\z//;
    return $output;
}

sub stage_symlink {
    my ( $root, $target, @path ) = @_;
    my $name = pop @path;
    my $dir = File::Spec->catdir( $root, @path );
    make_path($dir);
    my $link = File::Spec->catfile( $dir, $name );
    symlink( $target, $link ) or die "Unable to stage $link: $!";
    return $link;
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

my $active_hybrid_root = stage_root();
make_path( File::Spec->catdir( $active_hybrid_root, 'run', 'systemd', 'system' ) );
make_path( File::Spec->catdir( $active_hybrid_root, 'sbin' ) );
symlink( 'upstart', File::Spec->catfile( $active_hybrid_root, 'sbin', 'init' ) )
  or die "Unable to stage stale upstart init symlink: $!";
stage_systemd_binary($active_hybrid_root);
is( run_helper( $active_hybrid_root, 'uses-systemd' ), 0,
    'an active systemd manager overrides stale legacy target evidence' );

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
stage_systemd_binary($minimal_systemd_root);
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
stage_systemd_binary($legacy_os_root);
is( run_helper( $legacy_os_root, 'uses-systemd' ), 0,
    'the compatibility classifier preserves installed systemd precedence on SLES 11' );
isnt( run_helper( $legacy_os_root, 'uses-systemd', '--explicit-target' ), 0,
    'SLES 11 overrides an installed but inactive systemd binary' );

my $legacy_ubuntu_root = stage_root();
make_path( File::Spec->catdir( $legacy_ubuntu_root, 'etc' ) );
open( my $legacy_ubuntu_release, '>',
    File::Spec->catfile( $legacy_ubuntu_root, 'etc', 'os-release' ) )
  or die "Unable to stage legacy Ubuntu os-release: $!";
print {$legacy_ubuntu_release} qq{ID=ubuntu\nVERSION_ID=14.04\n};
close($legacy_ubuntu_release);
stage_systemd_binary($legacy_ubuntu_root);
is( run_helper( $legacy_ubuntu_root, 'uses-systemd' ), 0,
    'the compatibility classifier preserves installed systemd precedence on Ubuntu 14.04' );
isnt( run_helper( $legacy_ubuntu_root, 'uses-systemd', '--explicit-target' ), 0,
    'Ubuntu 14.04 overrides an installed but inactive systemd binary' );

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
stage_systemd_binary($legacy_root);
is( run_helper( $legacy_root, 'uses-systemd' ), 0,
    'the compatibility classifier preserves installed systemd precedence for upstart' );
isnt( run_helper( $legacy_root, 'uses-systemd', '--explicit-target' ), 0,
    'an explicit upstart target overrides an installed systemd binary' );
is( run_helper( $legacy_root, 'configure' ), 0,
    'compatibility-mode configuration succeeds for a hybrid target' );
ok( !-e legacy_init($legacy_root),
    'compatibility-mode configuration preserves systemd precedence' );
is( run_helper( $legacy_root, 'configure', '--explicit-target' ), 0,
    'explicit-target legacy configuration succeeds' );
ok( -x legacy_init($legacy_root),
    'explicit-target configuration materializes an executable init script' );
is( read_file( legacy_init($legacy_root) ), read_file($template),
    'the explicit-target init script matches the packaged template' );

my $real_sysvinit_root = stage_root();
make_path(
    File::Spec->catdir( $real_sysvinit_root, 'sbin' ),
    File::Spec->catdir( $real_sysvinit_root, 'etc' )
);
open( my $real_sysvinit, '>',
    File::Spec->catfile( $real_sysvinit_root, 'sbin', 'init' ) )
  or die "Unable to stage real SysV init: $!";
print {$real_sysvinit} "#!/bin/sh\n";
close($real_sysvinit);
chmod 0755, File::Spec->catfile( $real_sysvinit_root, 'sbin', 'init' );
open( my $real_sysv_os_release, '>',
    File::Spec->catfile( $real_sysvinit_root, 'etc', 'os-release' ) )
  or die "Unable to stage modern Debian metadata: $!";
print {$real_sysv_os_release} "ID=debian\nVERSION_ID=12\n";
close($real_sysv_os_release);
stage_systemd_binary($real_sysvinit_root);
is( run_helper( $real_sysvinit_root, 'uses-systemd' ), 0,
    'the compatibility classifier preserves installed systemd precedence for real SysV init' );
isnt( run_helper( $real_sysvinit_root, 'uses-systemd', '--explicit-target' ), 0,
    'a real SysV init binary overrides modern release and systemd fallback evidence' );
is( run_helper( $real_sysvinit_root, 'configure' ), 0,
    'compatibility-mode configuration succeeds for a real SysV target' );
ok( !-e legacy_init($real_sysvinit_root),
    'compatibility-mode configuration preserves installed systemd precedence' );
is( run_helper( $real_sysvinit_root, 'configure', '--explicit-target' ), 0,
    'real SysV explicit-target configuration succeeds' );
ok( -x legacy_init($real_sysvinit_root),
    'real SysV explicit-target configuration installs the legacy init script' );

my $legacy_state_root = stage_root();
is( helper_output( $legacy_state_root, 'legacy-state' ), 'unregistered',
    'legacy state reports no registration when rc links are absent' );
stage_symlink(
    $legacy_state_root, '/etc/init.d/xcatd',
    qw(etc rc.d rc3.d K60xcatd)
);
is( helper_output( $legacy_state_root, 'legacy-state' ), 'disabled',
    'legacy state recognizes registered-off rc links' );
stage_symlink(
    $legacy_state_root, '/etc/init.d/xcatd',
    qw(etc rc.d rc3.d S85xcatd)
);
is( helper_output( $legacy_state_root, 'legacy-state' ), 'enabled',
    'legacy enabled state takes precedence when start and kill links coexist' );

my $systemd_state_root = stage_root();
is( helper_output( $systemd_state_root, 'systemd-state' ), 'disabled',
    'systemd state reports disabled when enablement links are absent' );
stage_symlink(
    $systemd_state_root, '/usr/lib/systemd/system/xcatd.service',
    qw(etc systemd system multi-user.target.wants xcatd.service)
);
is( helper_output( $systemd_state_root, 'systemd-state' ), 'enabled',
    'systemd state recognizes persistent wants links' );

my $systemd_requires_root = stage_root();
stage_symlink(
    $systemd_requires_root, '/usr/lib/systemd/system/xcatd.service',
    qw(run systemd system multi-user.target.requires xcatd.service)
);
is( helper_output( $systemd_requires_root, 'systemd-state' ), 'enabled',
    'systemd state recognizes runtime requires links' );

my $systemd_linked_root = stage_root();
stage_symlink(
    $systemd_linked_root, '/usr/lib/systemd/system/xcatd.service',
    qw(etc systemd system xcatd.service)
);
is( helper_output( $systemd_linked_root, 'systemd-state' ), 'disabled',
    'a linked unit without target enablement remains disabled' );

my $systemd_masked_root = stage_root();
stage_symlink(
    $systemd_masked_root, '/dev/null',
    qw(etc systemd system xcatd.service)
);
is( helper_output( $systemd_masked_root, 'systemd-state' ), 'masked',
    'systemd state preserves an administrator mask' );

my $cleanup_root = stage_root();
my @cleanup_links = (
    stage_symlink(
        $cleanup_root, '/etc/init.d/xcatd',
        qw(etc rc.d rc3.d S85xcatd)
    ),
    stage_symlink(
        $cleanup_root, '/etc/init.d/xcatd',
        qw(etc rc.d rc0.d K60xcatd)
    ),
    stage_symlink(
        $cleanup_root, '/usr/lib/systemd/system/xcatd.service',
        qw(etc systemd system multi-user.target.wants xcatd.service)
    ),
    stage_symlink(
        $cleanup_root, '/usr/lib/systemd/system/xcatd.service',
        qw(run systemd system multi-user.target.requires xcatd.service)
    ),
);
my $cleanup_mask = stage_symlink(
    $cleanup_root, '/dev/null',
    qw(etc systemd system xcatd.service)
);
is( run_helper( $cleanup_root, 'unregister-all' ), 0,
    'cross-manager registration cleanup succeeds in a target root' );
ok( !( grep { -e $_ || -l $_ } @cleanup_links ),
    'cross-manager cleanup removes SysV and systemd enablement links' );
ok( -l $cleanup_mask,
    'cross-manager cleanup preserves an administrator systemd mask' );
is( run_helper( $cleanup_root, 'register-legacy', 'enabled' ), 2,
    'legacy registration refuses to execute host tools for a target root' );

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

my $custom_legacy_root = stage_root();
make_path( File::Spec->catdir( $custom_legacy_root, 'sbin' ) );
symlink( 'upstart', File::Spec->catfile( $custom_legacy_root, 'sbin', 'init' ) )
  or die "Unable to stage customization target: $!";
is( run_helper( $custom_legacy_root, 'configure' ), 0,
    'customizable legacy target configuration succeeds' );
open( my $custom_init, '>', legacy_init($custom_legacy_root) )
  or die "Unable to customize staged init script: $!";
print {$custom_init} "administrator customization\n";
close($custom_init);
is( run_helper( $custom_legacy_root, 'configure' ), 0,
    'reconfiguring a legacy target succeeds' );
is( read_file( legacy_init($custom_legacy_root) ), "administrator customization\n",
    'legacy reconfiguration preserves an existing init script' );
is( run_helper( $custom_legacy_root, 'configure', '--replace' ), 0,
    'RPM-style legacy upgrade configuration succeeds' );
is( read_file( legacy_init($custom_legacy_root) ), read_file($template),
    'RPM-style legacy upgrades refresh the init script from the packaged template' );
is( run_helper( $custom_legacy_root, 'remove' ), 0,
    'legacy cleanup succeeds' );
ok( !-e legacy_init($custom_legacy_root),
    'legacy cleanup removes the generated init script' );

my $rpm_spec = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'xCAT-server.spec' )
);
my $helper_source = read_file($helper);
like( $helper_source, qr{/sbin/chkconfig --level 345 xcatd on},
    'legacy registration enables only the init template runlevels' );
like( $helper_source,
    qr{if \[ -z "\$compat_root" \] &&\s+\{ \[ -e "\$legacy_init" \] \|\| \[ -L "\$legacy_init" \]; \}; then\s+if \[ -x /sbin/chkconfig \]; then\s+/sbin/chkconfig --del xcatd}s,
    'legacy cleanup invokes host registration tools only for an existing init script' );
my ($rpm_post) = $rpm_spec =~ /^%post\n(.*?)^%posttrans\n/ms;
my ($rpm_posttrans) = $rpm_spec =~ /^%posttrans\n(.*?)^%preun\n/ms;
my ($rpm_preun) = $rpm_spec =~ /^%preun\n(.*)\z/ms;
my ($rpm_fresh) = $rpm_post =~
  /if \[ "\$1" = "1" \]; then(.*?)\nfi\n\nif \[ "\$1" -gt "1" \]; then/ms;
my ( $rpm_upgrade_systemd, $rpm_upgrade_legacy ) = $rpm_post =~
  /if \[ "\$1" -gt "1" \]; then.*?if "\$xcatd_init_compat" uses-systemd --explicit-target; then(.*?)\n  else\n(.*?)\n  fi/ms;
ok( defined($rpm_post) && defined($rpm_posttrans) && defined($rpm_preun)
      && defined($rpm_fresh) && defined($rpm_upgrade_systemd)
      && defined($rpm_upgrade_legacy),
    'RPM service lifecycle scriptlets can be inspected independently' );
like( $rpm_spec,
    qr{cp etc/init\.d/xcatd \$RPM_BUILD_ROOT/%\{prefix\}/share/xcat/scripts/xcatd},
    'RPM stages the legacy script as a compatibility template' );
like( $rpm_spec, qr{xcatd-init-compat.*uses-systemd}s,
    'RPM scriptlets select the init implementation at install time' );
unlike( $rpm_spec,
    qr{"\$xcatd_init_compat" uses-systemd(?! --explicit-target)},
    'every RPM lifecycle classifier opts into explicit target detection' );
unlike( $rpm_spec,
    qr{"\$xcatd_init_compat" configure(?![^\n]*--explicit-target)},
    'every RPM lifecycle configuration uses the matching explicit target mode' );
like( $rpm_spec,
    qr{xcatd_init_compat=.*?"\$xcatd_init_compat" configure --replace}s,
    'RPM upgrades refresh an existing SysV init script' );
like( $rpm_fresh,
    qr{"\$xcatd_init_compat" legacy-state.*?"\$xcatd_init_compat" systemd-state}s,
    'RPM fresh installs query service state through the shared helper' );
like( $rpm_upgrade_systemd,
    qr{legacy_xcatd_state=\$\("\$xcatd_init_compat" legacy-state\).*?"\$xcatd_init_compat" unregister-legacy.*?"\$xcatd_init_compat" configure.*?if \[ "\$legacy_xcatd_state" = enabled \].*?systemctl enable xcatd\.service}s,
    'RPM systemd transitions preserve enabled SysV state after unregistering it' );
like( $rpm_upgrade_legacy,
    qr{legacy_xcatd_state=\$\("\$xcatd_init_compat" legacy-state\).*?if \[ "\$legacy_xcatd_state" = unregistered \].*?systemd-state.*?"\$xcatd_init_compat" disable-systemd.*?configure --replace.*?register-legacy "\$legacy_xcatd_state"}s,
    'RPM legacy transitions preserve prior state and clear systemd enablement' );
like( $rpm_fresh,
    qr{if \[ "\$\("\$xcatd_init_compat" systemd-state\)" != masked \]; then\s+"\$xcatd_init_compat" register-legacy enabled}s,
    'RPM fresh legacy installs do not override a persistent systemd mask' );
unlike( $rpm_post,
    qr{/sbin/chkconfig --(?:add|del) xcatd|/usr/lib/lsb/(?:install|remove)_initd},
    'RPM post delegates registration mechanics to the shared helper' );
like( $rpm_posttrans,
    qr{%ifos linux.*?uses-systemd --explicit-target.*?\[ ! -e /etc/init\.d/xcatd \].*?\[ ! -L /etc/init\.d/xcatd \].*?"\$xcatd_init_compat" configure --explicit-target(?: --track-managed)? \|\| exit 1}s,
    'RPM post-transaction recovery restores only a missing legacy script' );
unlike( $rpm_posttrans, qr{\$1|--replace},
    'RPM post-transaction recovery is idempotent and not argument-gated' );
like( $rpm_preun,
    qr{"\$xcatd_init_compat" unregister-all.*?"\$xcatd_init_compat" remove}s,
    'RPM erase cleans both managers before removing the generated script' );
unlike( $rpm_preun,
    qr{/sbin/chkconfig --del xcatd|/usr/lib/lsb/remove_initd},
    'RPM erase delegates cross-manager cleanup to the shared helper' );
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
like( join( "\n", $rpm_spec, $helper_source ),
    qr{if \[ -e "\$legacy(?:_xcatd)?_link" \] \|\| \[ -L "\$legacy(?:_xcatd)?_link" \]},
    'xcatd init management recognizes enabled state through dangling legacy links' );

done_testing();
