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
my $state_helper = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'debian', 'xcatd-init-state'
);
my $compat_helper = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'scripts', 'xcatd-init-compat'
);
my $template = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'etc', 'init.d', 'xcatd'
);

sub write_file {
    my ( $path, $contents, $mode ) = @_;
    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh);
    chmod $mode, $path if defined $mode;
}

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

sub path_mode {
    my ($path) = @_;
    return ( stat($path) )[2] & 07777;
}

sub stage_root {
    my $root = tempdir( CLEANUP => 1 );
    my $scripts = File::Spec->catdir(
        $root, 'opt', 'xcat', 'share', 'xcat', 'scripts'
    );
    my $fake_bin = File::Spec->catdir( $root, 'test-bin' );
    make_path( $scripts, $fake_bin, File::Spec->catdir( $root, 'sbin' ) );
    copy( $template, File::Spec->catfile( $scripts, 'xcatd' ) )
      or die "Unable to stage xcatd template: $!";
    copy( $compat_helper, File::Spec->catfile( $scripts, 'xcatd-init-compat' ) )
      or die "Unable to stage xcatd compatibility helper: $!";
    chmod 0755, File::Spec->catfile( $scripts, 'xcatd-init-compat' );

    write_file(
        File::Spec->catfile( $fake_bin, 'ucf' ),
        <<'SH', 0755
#!/bin/sh
set -eu
root=${XCAT_COMPAT_ROOT:?}
[ ! -f "$root/fail-ucf" ] || exit 9
new_file=$1
destination=$2
if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
    mkdir -p "$(dirname "$destination")"
    cp "$new_file" "$destination"
    chmod 755 "$destination"
fi
if [ -f "$root/mutate-ucf" ]; then
    printf '%s\n' '# ucf mutation' >> "$destination"
fi
SH
    );
    write_file(
        File::Spec->catfile( $fake_bin, 'ucfr' ),
        <<'SH', 0755
#!/bin/sh
set -eu
root=${XCAT_COMPAT_ROOT:?}
[ ! -f "$root/fail-ucfr" ] || exit 8
exit 0
SH
    );
    write_file(
        File::Spec->catfile( $fake_bin, 'update-rc.d' ),
        <<'SH', 0755
#!/bin/sh
set -eu
root=${XCAT_COMPAT_ROOT:?}
remove_links()
{
    rm -f "$root"/etc/rc?.d/[SK]??xcatd
}
defaults()
{
    remove_links
    for runlevel in 0 1 2 3 4 5 6; do
        mkdir -p "$root/etc/rc$runlevel.d"
        case "$runlevel" in
            2|3|4|5) prefix=S20 ;;
            *) prefix=K80 ;;
        esac
        ln -sfn ../init.d/xcatd "$root/etc/rc$runlevel.d/${prefix}xcatd"
    done
}
case "${1:-}:${2:-}" in
    -f:xcatd)
        [ "${3:-}" = remove ]
        remove_links
        ;;
    xcatd:defaults)
        defaults
        ;;
    xcatd:disable)
        remove_links
        for runlevel in 0 1 2 3 4 5 6; do
            mkdir -p "$root/etc/rc$runlevel.d"
            ln -sfn ../init.d/xcatd "$root/etc/rc$runlevel.d/K80xcatd"
        done
        ;;
    xcatd:enable)
        defaults
        ;;
    *) exit 2 ;;
esac
SH
    );
    write_file(
        File::Spec->catfile( $fake_bin, 'systemctl' ),
        <<'SH', 0755
#!/bin/sh
set -eu
root=${XCAT_COMPAT_ROOT:?}
case "${1:-}" in
    --root=*) shift ;;
esac
[ "${1:-}" = is-enabled ] || exit 0
if [ -r "$root/systemctl-state" ]; then
    status=$(sed -n '1p' "$root/systemctl-state")
else
    status=unknown
fi
printf '%s\n' "$status"
[ "$status" = enabled ] && exit 0
exit 1
SH
    );

    return $root;
}

sub run_script {
    my ( $root, $script, @arguments ) = @_;
    local $ENV{XCAT_COMPAT_ROOT} = $root;
    local $ENV{XCATROOT}         = '/opt/xcat';
    local $ENV{PATH} = File::Spec->catdir( $root, 'test-bin' ) . ':/usr/bin:/bin';
    system( '/bin/sh', $script, @arguments );
    return $? >> 8;
}

sub run_state {
    my ( $root, @arguments ) = @_;
    return run_script( $root, $state_helper, @arguments );
}

sub run_compat {
    my ( $root, @arguments ) = @_;
    return run_script( $root, $compat_helper, @arguments );
}

sub run_update_rc {
    my ( $root, @arguments ) = @_;
    my $update_rc = File::Spec->catfile( $root, 'test-bin', 'update-rc.d' );
    my $status = run_script( $root, $update_rc, @arguments );
    die "Fake update-rc.d failed with status $status" if $status;
}

sub live_init {
    my ($root) = @_;
    return File::Spec->catfile( $root, 'etc', 'init.d', 'xcatd' );
}

sub state_dir {
    my ($root) = @_;
    return File::Spec->catdir( $root, 'var', 'lib', 'xcat', 'xcatd-init-state' );
}

sub old_systemd_marker {
    my ($root) = @_;
    return File::Spec->catfile( $root, 'var', 'lib', 'xcat', 'xcatd-systemd-mode' );
}

sub state_value {
    my ( $root, $field ) = @_;
    my $state = read_file( File::Spec->catfile( state_dir($root), 'state' ) );
    return $1 if $state =~ /^\Q$field\E=(.+)$/m;
    return '';
}

sub set_init_target {
    my ( $root, $target ) = @_;
    my $init = File::Spec->catfile( $root, 'sbin', 'init' );
    unlink($init) if -e $init || -l $init;
    symlink( $target, $init ) or die "Unable to stage init target: $!";
}

sub set_systemd_state {
    my ( $root, $state ) = @_;
    write_file( File::Spec->catfile( $root, 'systemctl-state' ), "$state\n" );
}

sub rc_link {
    my ($root) = @_;
    return File::Spec->catfile( $root, 'etc', 'rc2.d', 'S20xcatd' );
}

sub rc_kill_link {
    my ($root) = @_;
    return File::Spec->catfile( $root, 'etc', 'rc2.d', 'K80xcatd' );
}

sub registration_link_count {
    my ($root) = @_;
    my @links = glob( File::Spec->catfile(
        $root, 'etc', 'rc?.d', '[SK]??xcatd'
    ) );
    return scalar @links;
}

my $round_trip_root = stage_root();
set_init_target( $round_trip_root, 'upstart' );
my $saved_umask = umask 0022;
my $fresh_configure_status =
  run_state( $round_trip_root, 'configure-legacy', 'fresh' );
umask $saved_umask;
is( $fresh_configure_status, 0,
    'fresh legacy configuration succeeds' );
is( path_mode( state_dir($round_trip_root) ), 0700,
    'persistent init state remains private' );
is( path_mode( File::Spec->catfile( state_dir($round_trip_root), 'state' ) ),
    0600, 'the init state file remains private' );
is( state_value( $round_trip_root, 'format' ), '2',
    'new init state is written in registration-aware format 2' );
is( path_mode( File::Spec->catdir( $round_trip_root, 'etc', 'init.d' ) ),
    0755, 'state writes do not leak their private umask into init directories' );
ok( -x live_init($round_trip_root),
    'fresh legacy configuration materializes the init script' );
ok( -l rc_link($round_trip_root),
    'fresh legacy configuration enables the init script' );

write_file( live_init($round_trip_root), "administrator customization\n", 0755 );
is( run_state( $round_trip_root, 'prepare-systemd', 'upgrade' ), 0,
    'legacy to systemd preparation succeeds' );
is( state_value( $round_trip_root, 'content' ), 'stashed',
    'a customized init script is stashed before removal' );
is( state_value( $round_trip_root, 'enabled' ), 'yes',
    'SysV enablement is captured before removal' );
set_init_target( $round_trip_root, '../lib/systemd/systemd' );
is( run_compat( $round_trip_root, 'configure', '--explicit-target' ), 0,
    'systemd compatibility configuration succeeds' );
is( run_state( $round_trip_root, 'commit-systemd' ), 0,
    'systemd transition state commits' );
ok( !-e live_init($round_trip_root),
    'systemd mode omits the live legacy script' );
like( read_file( File::Spec->catfile( state_dir($round_trip_root), 'xcatd' ) ),
    qr/administrator customization/,
    'the exact customized script remains in the durable stash' );

set_systemd_state( $round_trip_root, 'enabled' );
set_init_target( $round_trip_root, 'upstart' );
is( run_state( $round_trip_root, 'configure-legacy', 'upgrade' ), 0,
    'systemd to legacy restoration succeeds' );
is( read_file( live_init($round_trip_root) ), "administrator customization\n",
    'the customized init script survives a mode round trip' );
ok( -l rc_link($round_trip_root),
    'systemd enablement maps back to SysV registration' );
is( state_value( $round_trip_root, 'mode' ), 'legacy',
    'the completed restoration records legacy mode' );

unlink( live_init($round_trip_root) )
  or die "Unable to stage administrator deletion: $!";
is( run_state( $round_trip_root, 'prepare-systemd', 'upgrade' ), 0,
    'deleted legacy state prepares for systemd' );
is( state_value( $round_trip_root, 'content' ), 'deleted',
    'administrator deletion is recorded separately from package omission' );
set_init_target( $round_trip_root, '../lib/systemd/systemd' );
is( run_state( $round_trip_root, 'commit-systemd' ), 0,
    'deleted state commits in systemd mode' );
set_systemd_state( $round_trip_root, 'disabled' );
set_init_target( $round_trip_root, 'upstart' );
is( run_state( $round_trip_root, 'configure-legacy', 'upgrade' ), 0,
    'deleted state returns to legacy mode' );
ok( !-e live_init($round_trip_root),
    'administrator deletion survives a mode round trip' );
ok( !-e rc_link($round_trip_root),
    'a missing legacy script is not registered' );

my $disabled_root = stage_root();
set_init_target( $disabled_root, 'upstart' );
is( run_state( $disabled_root, 'configure-legacy', 'fresh' ), 0,
    'disabled fixture starts in legacy mode' );
run_update_rc( $disabled_root, 'xcatd', 'disable' );
ok( -l rc_kill_link($disabled_root),
    'disabled fixture remains registered through a kill link' );
write_file( live_init($disabled_root), "disabled customization\n", 0755 );
is( run_state( $disabled_root, 'prepare-systemd', 'upgrade' ), 0,
    'disabled legacy fixture prepares for systemd' );
is( state_value( $disabled_root, 'enabled' ), 'no',
    'disabled SysV state is captured' );
set_init_target( $disabled_root, '../lib/systemd/systemd' );
is( run_compat( $disabled_root, 'configure', '--explicit-target' ), 0,
    'disabled systemd fixture removes the live script' );
is( run_state( $disabled_root, 'commit-systemd' ), 0,
    'disabled systemd state commits' );
set_systemd_state( $disabled_root, 'disabled' );
set_init_target( $disabled_root, 'upstart' );
is( run_state( $disabled_root, 'configure-legacy', 'upgrade' ), 0,
    'disabled systemd fixture returns to legacy' );
is( read_file( live_init($disabled_root) ), "disabled customization\n",
    'disabled customization is restored' );
ok( !-e rc_link($disabled_root),
    'disabled systemd state stays disabled under SysV' );
ok( -l rc_kill_link($disabled_root),
    'registered-disabled SysV state restores its kill link' );
run_update_rc( $disabled_root, 'xcatd', 'enable' );
ok( -l rc_link($disabled_root) && !-e rc_kill_link($disabled_root),
    'a restored registered-disabled service can be enabled later' );

my $unregistered_root = stage_root();
set_init_target( $unregistered_root, 'upstart' );
is( run_state( $unregistered_root, 'configure-legacy', 'fresh' ), 0,
    'unregistered fixture starts in legacy mode' );
run_update_rc( $unregistered_root, '-f', 'xcatd', 'remove' );
write_file( live_init($unregistered_root), "unregistered customization\n", 0755 );
is( run_state( $unregistered_root, 'prepare-systemd', 'upgrade' ), 0,
    'unregistered legacy fixture prepares for systemd' );
is( state_value( $unregistered_root, 'enabled' ), 'unregistered',
    'an absent SysV registration is distinct from registered-disabled' );
set_init_target( $unregistered_root, '../lib/systemd/systemd' );
is( run_compat( $unregistered_root, 'configure', '--explicit-target' ), 0,
    'unregistered systemd fixture removes the live script' );
is( run_state( $unregistered_root, 'commit-systemd' ), 0,
    'unregistered systemd state commits' );
set_systemd_state( $unregistered_root, 'disabled' );
set_init_target( $unregistered_root, 'upstart' );
is( run_state( $unregistered_root, 'configure-legacy', 'upgrade' ), 0,
    'unregistered systemd fixture returns to legacy' );
is( read_file( live_init($unregistered_root) ),
    "unregistered customization\n",
    'unregistered customization is restored' );
is( registration_link_count($unregistered_root), 0,
    'unregistered state returns without start or kill links' );
is( state_value( $unregistered_root, 'enabled' ), 'unregistered',
    'completed state retains unregistered metadata' );

my $rpm_layout_root = stage_root();
set_init_target( $rpm_layout_root, 'upstart' );
is( run_state( $rpm_layout_root, 'configure-legacy', 'fresh' ), 0,
    'RPM-layout fixture starts in legacy mode' );
run_update_rc( $rpm_layout_root, '-f', 'xcatd', 'remove' );
my $rpm_runlevel_dir =
  File::Spec->catdir( $rpm_layout_root, 'etc', 'rc.d', 'rc3.d' );
make_path($rpm_runlevel_dir);
symlink( '/etc/init.d/xcatd',
    File::Spec->catfile( $rpm_runlevel_dir, 'S85xcatd' ) )
  or die "Unable to stage RPM-only registration: $!";
is( run_state( $rpm_layout_root, 'prepare-systemd', 'upgrade' ), 0,
    'RPM-only registration prepares for a Debian systemd transition' );
is( state_value( $rpm_layout_root, 'enabled' ), 'unregistered',
    'RPM-only links do not become Debian SysV enablement evidence' );

my $missing_update_rc_root = stage_root();
unlink( File::Spec->catfile(
        $missing_update_rc_root, 'test-bin', 'update-rc.d'
    ) )
  or die "Unable to remove fake update-rc.d: $!";
set_init_target( $missing_update_rc_root, 'upstart' );
is( run_state( $missing_update_rc_root, 'configure-legacy', 'fresh' ), 0,
    'fresh legacy configuration tolerates a missing update-rc.d' );
ok( -x live_init($missing_update_rc_root),
    'missing registration tooling does not prevent script materialization' );
is( registration_link_count($missing_update_rc_root), 0,
    'missing registration tooling leaves runlevel links untouched' );

my $legacy_reinstall_root = stage_root();
set_init_target( $legacy_reinstall_root, 'upstart' );
is( run_state( $legacy_reinstall_root, 'configure-legacy', 'fresh' ), 0,
    'legacy reinstall fixture starts enabled' );
run_update_rc( $legacy_reinstall_root, '-f', 'xcatd', 'remove' );
is( run_state( $legacy_reinstall_root, 'configure-legacy', 'fresh' ), 0,
    'legacy remove and reinstall configures as fresh' );
ok( -l rc_link($legacy_reinstall_root),
    'legacy remove and reinstall restores default enablement' );

my $masked_transition_root = stage_root();
set_init_target( $masked_transition_root, 'upstart' );
is( run_state( $masked_transition_root, 'configure-legacy', 'fresh' ), 0,
    'masked transition fixture starts enabled in legacy mode' );
my $masked_transition_unit_dir =
  File::Spec->catdir( $masked_transition_root, 'etc', 'systemd', 'system' );
make_path($masked_transition_unit_dir);
symlink( '/dev/null',
    File::Spec->catfile( $masked_transition_unit_dir, 'xcatd.service' ) )
  or die "Unable to stage transition mask: $!";
is( run_state( $masked_transition_root, 'prepare-systemd', 'upgrade' ), 0,
    'enabled legacy state prepares against a systemd mask' );
is( state_value( $masked_transition_root, 'enabled' ), 'unregistered',
    'an explicit systemd mask overrides legacy registration' );
is( state_value( $masked_transition_root, 'origin' ), 'systemd',
    'masked transition suppresses postinst enablement mutation' );

my $late_mask_root = stage_root();
set_init_target( $late_mask_root, 'upstart' );
is( run_state( $late_mask_root, 'configure-legacy', 'fresh' ), 0,
    'late-mask fixture starts enabled in legacy mode' );
is( run_state( $late_mask_root, 'prepare-systemd', 'upgrade' ), 0,
    'late-mask fixture begins a systemd transition' );
my $late_mask_unit_dir =
  File::Spec->catdir( $late_mask_root, 'etc', 'systemd', 'system' );
make_path($late_mask_unit_dir);
symlink( '/dev/null',
    File::Spec->catfile( $late_mask_unit_dir, 'xcatd.service' ) )
  or die "Unable to stage mask during transition: $!";
is( run_state( $late_mask_root, 'prepare-systemd', 'upgrade' ), 0,
    'systemd transition retries after a mask is added' );
is( state_value( $late_mask_root, 'enabled' ), 'unregistered',
    'a newly added mask overrides preserved transition enablement' );
is( state_value( $late_mask_root, 'origin' ), 'systemd',
    'a newly added mask suppresses retry enablement mutation' );

my $fresh_systemd_root = stage_root();
set_systemd_state( $fresh_systemd_root, 'disabled' );
is( run_state( $fresh_systemd_root, 'prepare-systemd', 'fresh' ), 0,
    'fresh systemd preparation succeeds for a newly unpacked disabled unit' );
is( state_value( $fresh_systemd_root, 'enabled' ), 'yes',
    'fresh systemd installs remain enabled by default' );
is( state_value( $fresh_systemd_root, 'origin' ), 'fresh',
    'fresh systemd state records a fresh transition' );

for my $link_case (
    [ 'persistent wants',   qw(etc wants) ],
    [ 'persistent requires', qw(etc requires) ],
    [ 'runtime wants',      qw(run wants) ],
    [ 'runtime requires',   qw(run requires) ],
) {
    my ( $label, $scope, $relation ) = @{$link_case};
    my $link_root = stage_root();
    my $link_dir = File::Spec->catdir(
        $link_root, $scope, 'systemd', 'system',
        "multi-user.target.$relation"
    );
    make_path($link_dir);
    symlink(
        '/usr/lib/systemd/system/xcatd.service',
        File::Spec->catfile( $link_dir, 'xcatd.service' )
    ) or die "Unable to stage $label link: $!";
    set_systemd_state( $link_root, 'unknown' );
    is( run_state( $link_root, 'prepare-systemd', 'upgrade' ), 0,
        "$label enablement prepares successfully" );
    is( state_value( $link_root, 'enabled' ), 'yes',
        "$label enablement is preserved" );
}

my $masked_root = stage_root();
my $masked_unit_dir = File::Spec->catdir( $masked_root, 'etc', 'systemd', 'system' );
make_path($masked_unit_dir);
symlink( '/dev/null', File::Spec->catfile( $masked_unit_dir, 'xcatd.service' ) )
  or die "Unable to stage masked unit: $!";
make_path( File::Spec->catdir( $masked_root, 'var', 'lib', 'xcat' ) );
write_file( old_systemd_marker($masked_root), "marker\n" );
is( run_state( $masked_root, 'prepare-systemd', 'upgrade' ), 0,
    'masked systemd preparation succeeds' );
is( state_value( $masked_root, 'content' ), 'package-default',
    'an obsolete package conffile marker retains package omission semantics' );
is( state_value( $masked_root, 'enabled' ), 'unregistered',
    'a masked unit is not treated as boot-enabled' );

my $fresh_masked_root = stage_root();
my $fresh_masked_unit_dir =
  File::Spec->catdir( $fresh_masked_root, 'etc', 'systemd', 'system' );
make_path($fresh_masked_unit_dir);
symlink( '/dev/null',
    File::Spec->catfile( $fresh_masked_unit_dir, 'xcatd.service' ) )
  or die "Unable to stage fresh masked unit: $!";
is( run_state( $fresh_masked_root, 'prepare-systemd', 'fresh' ), 0,
    'fresh masked systemd preparation succeeds' );
is( state_value( $fresh_masked_root, 'enabled' ), 'unregistered',
    'a pre-existing mask is not overridden on fresh install' );

my $runtime_masked_root = stage_root();
my $runtime_masked_unit_dir =
  File::Spec->catdir( $runtime_masked_root, 'run', 'systemd', 'system' );
make_path($runtime_masked_unit_dir);
symlink( '/dev/null',
    File::Spec->catfile( $runtime_masked_unit_dir, 'xcatd.service' ) )
  or die "Unable to stage runtime masked unit: $!";
set_systemd_state( $runtime_masked_root, 'unknown' );
is( run_state( $runtime_masked_root, 'prepare-systemd', 'fresh' ), 0,
    'runtime masked systemd preparation succeeds' );
is( state_value( $runtime_masked_root, 'enabled' ), 'unregistered',
    'a runtime mask is not treated as enabled offline' );
is( state_value( $runtime_masked_root, 'origin' ), 'systemd',
    'a runtime mask overrides fresh-install enablement' );

my $pending_deleted_root = stage_root();
make_path( state_dir($pending_deleted_root) );
write_file( File::Spec->catfile( state_dir($pending_deleted_root), 'pending-deleted' ), "\n" );
write_file( File::Spec->catfile( state_dir($pending_deleted_root), 'pending-enabled' ), "no\n" );
set_systemd_state( $pending_deleted_root, 'enabled' );
is( run_state( $pending_deleted_root, 'prepare-systemd', 'upgrade' ), 0,
    'explicit preinst deletion evidence prepares successfully' );
is( state_value( $pending_deleted_root, 'content' ), 'deleted',
    'a still-owned missing conffile remains an administrator deletion' );
is( state_value( $pending_deleted_root, 'enabled' ), 'yes',
    'existing native-systemd enablement survives legacy deletion evidence' );
is( state_value( $pending_deleted_root, 'origin' ), 'legacy',
    'explicit conffile deletion retains legacy provenance' );

my $pending_enabled_root = stage_root();
make_path( state_dir($pending_enabled_root) );
write_file(
    File::Spec->catfile( state_dir($pending_enabled_root), 'pending-xcatd' ),
    "legacy content\n", 0755
);
write_file(
    File::Spec->catfile( state_dir($pending_enabled_root), 'pending-enabled' ),
    "yes\n"
);
set_systemd_state( $pending_enabled_root, 'disabled' );
is( run_state( $pending_enabled_root, 'prepare-systemd', 'upgrade' ), 0,
    'enabled legacy evidence prepares with disabled systemd state' );
is( state_value( $pending_enabled_root, 'enabled' ), 'yes',
    'first migration preserves enablement from either service manager' );

my $both_disabled_root = stage_root();
make_path( state_dir($both_disabled_root) );
write_file(
    File::Spec->catfile( state_dir($both_disabled_root), 'pending-xcatd' ),
    "legacy content\n", 0755
);
write_file(
    File::Spec->catfile( state_dir($both_disabled_root), 'pending-enabled' ),
    "no\n"
);
set_systemd_state( $both_disabled_root, 'disabled' );
is( run_state( $both_disabled_root, 'prepare-systemd', 'upgrade' ), 0,
    'fully disabled first migration prepares successfully' );
is( state_value( $both_disabled_root, 'enabled' ), 'no',
    'first migration remains disabled when both managers are disabled' );

my $masked_pending_root = stage_root();
make_path(
    state_dir($masked_pending_root),
    File::Spec->catdir( $masked_pending_root, 'etc', 'systemd', 'system' )
);
write_file(
    File::Spec->catfile( state_dir($masked_pending_root), 'pending-xcatd' ),
    "legacy content\n", 0755
);
write_file(
    File::Spec->catfile( state_dir($masked_pending_root), 'pending-enabled' ),
    "yes\n"
);
symlink( '/dev/null',
    File::Spec->catfile( $masked_pending_root, 'etc', 'systemd', 'system',
        'xcatd.service' ) )
  or die "Unable to stage masked first migration: $!";
is( run_state( $masked_pending_root, 'prepare-systemd', 'upgrade' ), 0,
    'masked first migration prepares successfully' );
is( state_value( $masked_pending_root, 'enabled' ), 'unregistered',
    'an explicit systemd mask wins over stale legacy enablement' );

my $obsolete_disabled_root = stage_root();
make_path( File::Spec->catdir( $obsolete_disabled_root, 'var', 'lib', 'xcat' ) );
write_file( old_systemd_marker($obsolete_disabled_root), "marker\n" );
set_systemd_state( $obsolete_disabled_root, 'disabled' );
is( run_state( $obsolete_disabled_root, 'prepare-systemd', 'upgrade' ), 0,
    'disabled obsolete-conffile migration prepares successfully' );
is( state_value( $obsolete_disabled_root, 'content' ), 'package-default',
    'package-driven omission is not confused with administrator deletion' );
is( state_value( $obsolete_disabled_root, 'enabled' ), 'no',
    'disabled markerless systemd state remains disabled' );
is( run_state( $obsolete_disabled_root, 'commit-systemd' ), 0,
    'disabled markerless systemd state commits' );
set_init_target( $obsolete_disabled_root, 'upstart' );
is( run_state( $obsolete_disabled_root, 'configure-legacy', 'upgrade' ), 0,
    'disabled package omission returns to legacy mode' );
ok( -x live_init($obsolete_disabled_root),
    'package omission restores the packaged legacy script' );
ok( !-e rc_link($obsolete_disabled_root),
    'disabled package omission remains off under SysV' );
ok( -l rc_kill_link($obsolete_disabled_root),
    'native systemd disablement maps to registered-disabled SysV state' );

my $same_systemd_root = stage_root();
set_systemd_state( $same_systemd_root, 'disabled' );
is( run_state( $same_systemd_root, 'prepare-systemd', 'fresh' ), 0,
    'same-systemd fixture prepares as fresh' );
is( run_state( $same_systemd_root, 'commit-systemd' ), 0,
    'same-systemd fixture commits its initial state' );
set_systemd_state( $same_systemd_root, 'enabled' );
is( run_state( $same_systemd_root, 'prepare-systemd', 'upgrade' ), 0,
    'same-systemd upgrade preparation succeeds' );
is( state_value( $same_systemd_root, 'origin' ), 'systemd',
    'same-systemd upgrades are distinguishable from mode changes' );

my $reinstall_state_root = stage_root();
set_init_target( $reinstall_state_root, 'upstart' );
is( run_state( $reinstall_state_root, 'configure-legacy', 'fresh' ), 0,
    'reinstall-state fixture starts in legacy mode' );
write_file( live_init($reinstall_state_root), "reinstall customization\n", 0755 );
is( run_state( $reinstall_state_root, 'prepare-systemd', 'upgrade' ), 0,
    'reinstall-state fixture stashes its customization' );
set_init_target( $reinstall_state_root, '../lib/systemd/systemd' );
is( run_compat( $reinstall_state_root, 'configure', '--explicit-target' ), 0,
    'reinstall-state fixture enters systemd mode' );
is( run_state( $reinstall_state_root, 'commit-systemd' ), 0,
    'reinstall-state fixture commits durable systemd state' );
write_file(
    File::Spec->catfile( state_dir($reinstall_state_root), 'pending-deleted' ),
    "stale\n"
);
write_file(
    File::Spec->catfile( state_dir($reinstall_state_root), 'pending-enabled' ),
    "no\n"
);
set_systemd_state( $reinstall_state_root, 'disabled' );
is( run_state( $reinstall_state_root, 'prepare-systemd', 'fresh' ), 0,
    'remove and reinstall preparation uses durable state' );
is( state_value( $reinstall_state_root, 'content' ), 'stashed',
    'stale fallback deletion evidence cannot replace a durable stash' );
is( state_value( $reinstall_state_root, 'enabled' ), 'yes',
    'a genuine reinstall restores the default enabled state' );
is( read_file( File::Spec->catfile( state_dir($reinstall_state_root), 'xcatd' ) ),
    "reinstall customization\n",
    'remove and reinstall preserves the exact administrator customization' );

my $stale_pending_root = stage_root();
set_init_target( $stale_pending_root, 'upstart' );
is( run_state( $stale_pending_root, 'configure-legacy', 'fresh' ), 0,
    'stale-pending fixture starts in legacy mode' );
write_file( live_init($stale_pending_root), "current live content\n", 0755 );
write_file(
    File::Spec->catfile( state_dir($stale_pending_root), 'pending-xcatd' ),
    "stale pending content\n", 0755
);
is( run_state( $stale_pending_root, 'prepare-systemd', 'upgrade' ), 0,
    'stable legacy state ignores stale pending evidence' );
is( read_file( File::Spec->catfile( state_dir($stale_pending_root), 'xcatd' ) ),
    "current live content\n",
    'current live content wins over stale pending content' );
ok( !-e File::Spec->catfile( state_dir($stale_pending_root), 'pending-xcatd' ),
    'successful systemd preparation clears stale pending evidence' );

my $pending_cleanup_root = stage_root();
make_path( state_dir($pending_cleanup_root) );
for my $pending_name (qw(pending-xcatd pending-deleted pending-enabled)) {
    write_file(
        File::Spec->catfile( state_dir($pending_cleanup_root), $pending_name ),
        "stale\n", 0755
    );
}
set_init_target( $pending_cleanup_root, 'upstart' );
is( run_state( $pending_cleanup_root, 'configure-legacy', 'fresh' ), 0,
    'legacy convergence succeeds with stale pending evidence' );
for my $pending_name (qw(pending-xcatd pending-deleted pending-enabled)) {
    ok( !-e File::Spec->catfile( state_dir($pending_cleanup_root), $pending_name ),
        "legacy convergence clears $pending_name" );
}

my $legacy_retry_root = stage_root();
set_init_target( $legacy_retry_root, 'upstart' );
is( run_state( $legacy_retry_root, 'configure-legacy', 'fresh' ), 0,
    'same-mode retry fixture starts in legacy mode' );
run_update_rc( $legacy_retry_root, 'xcatd', 'disable' );
is( run_state( $legacy_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'disabled same-mode state is recorded' );
set_systemd_state( $legacy_retry_root, 'enabled' );
write_file( live_init($legacy_retry_root), "same-mode original\n", 0755 );
write_file( File::Spec->catfile( $legacy_retry_root, 'mutate-ucf' ), "mutate\n" );
write_file( File::Spec->catfile( $legacy_retry_root, 'fail-ucfr' ), "fail\n" );
isnt( run_state( $legacy_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'same-mode failure after UCF mutation is reported' );
is( state_value( $legacy_retry_root, 'origin' ), 'legacy',
    'failed same-mode configuration retains its legacy origin' );
is( read_file( File::Spec->catfile( state_dir($legacy_retry_root), 'xcatd' ) ),
    "same-mode original\n",
    'same-mode failure retains an exact transactional stash' );
unlink( File::Spec->catfile( $legacy_retry_root, 'mutate-ucf' ) )
  or die "Unable to clear same-mode UCF mutation: $!";
unlink( File::Spec->catfile( $legacy_retry_root, 'fail-ucfr' ) )
  or die "Unable to clear same-mode ucfr failure: $!";
is( run_state( $legacy_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'same-mode legacy retry succeeds' );
is( read_file( live_init($legacy_retry_root) ), "same-mode original\n",
    'same-mode retry restores exact pre-failure content' );
ok( !-e rc_link($legacy_retry_root),
    'same-mode retry does not import stale systemd enablement' );

my $admin_disabled_retry_root = stage_root();
set_init_target( $admin_disabled_retry_root, 'upstart' );
is( run_state( $admin_disabled_retry_root, 'configure-legacy', 'fresh' ), 0,
    'admin-disabled retry fixture starts enabled' );
run_update_rc( $admin_disabled_retry_root, 'xcatd', 'disable' );
write_file(
    File::Spec->catfile( $admin_disabled_retry_root, 'fail-ucfr' ),
    "fail\n"
);
isnt( run_state( $admin_disabled_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'same-mode upgrade fails after current disablement is sampled' );
is( state_value( $admin_disabled_retry_root, 'enabled' ), 'no',
    'failed same-mode upgrade records current disabled rc state' );
unlink( File::Spec->catfile( $admin_disabled_retry_root, 'fail-ucfr' ) )
  or die "Unable to clear admin-disabled retry failure: $!";
is( run_state( $admin_disabled_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'admin-disabled same-mode upgrade retries' );
ok( !-e rc_link($admin_disabled_retry_root),
    'retry does not undo a current administrator disablement' );

my $admin_enabled_retry_root = stage_root();
set_init_target( $admin_enabled_retry_root, 'upstart' );
is( run_state( $admin_enabled_retry_root, 'configure-legacy', 'fresh' ), 0,
    'admin-enabled retry fixture starts enabled' );
run_update_rc( $admin_enabled_retry_root, 'xcatd', 'disable' );
is( run_state( $admin_enabled_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'disabled baseline is recorded' );
make_path( File::Spec->catdir( $admin_enabled_retry_root, 'etc', 'rc2.d' ) );
symlink( '../init.d/xcatd', rc_link($admin_enabled_retry_root) )
  or die "Unable to stage current administrator enablement: $!";
write_file(
    File::Spec->catfile( $admin_enabled_retry_root, 'fail-ucfr' ),
    "fail\n"
);
isnt( run_state( $admin_enabled_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'same-mode upgrade fails after current enablement is sampled' );
is( state_value( $admin_enabled_retry_root, 'enabled' ), 'yes',
    'failed same-mode upgrade records current enabled rc state' );
unlink( File::Spec->catfile( $admin_enabled_retry_root, 'fail-ucfr' ) )
  or die "Unable to clear admin-enabled retry failure: $!";
is( run_state( $admin_enabled_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'admin-enabled same-mode upgrade retries' );
ok( -l rc_link($admin_enabled_retry_root),
    'retry does not undo a current administrator enablement' );

my $markerless_enabled_root = stage_root();
set_systemd_state( $markerless_enabled_root, 'enabled' );
set_init_target( $markerless_enabled_root, 'upstart' );
is( run_state( $markerless_enabled_root, 'configure-legacy', 'upgrade' ), 0,
    'enabled markerless migration succeeds' );
ok( -x live_init($markerless_enabled_root),
    'strong systemd enablement evidence restores the packaged script' );
ok( -l rc_link($markerless_enabled_root),
    'strong systemd enablement evidence restores SysV registration' );

my $markerless_unknown_root = stage_root();
set_systemd_state( $markerless_unknown_root, 'unknown' );
set_init_target( $markerless_unknown_root, 'upstart' );
is( run_state( $markerless_unknown_root, 'configure-legacy', 'upgrade' ), 0,
    'ambiguous markerless migration converges safely' );
ok( !-e live_init($markerless_unknown_root),
    'ambiguous absence is not silently resurrected' );
ok( !-e rc_link($markerless_unknown_root),
    'ambiguous enablement defaults to disabled' );

my $legacy_target_obsolete_root = stage_root();
make_path( File::Spec->catdir( $legacy_target_obsolete_root, 'var', 'lib', 'xcat' ) );
write_file( old_systemd_marker($legacy_target_obsolete_root), "marker\n" );
set_systemd_state( $legacy_target_obsolete_root, 'disabled' );
set_init_target( $legacy_target_obsolete_root, 'upstart' );
is( run_state( $legacy_target_obsolete_root, 'configure-legacy', 'upgrade' ), 0,
    'obsolete conffile migrates directly to a legacy target' );
ok( -x live_init($legacy_target_obsolete_root),
    'direct legacy migration restores package-driven omission' );
ok( !-e rc_link($legacy_target_obsolete_root),
    'direct legacy migration preserves disabled systemd state' );
ok( -l rc_kill_link($legacy_target_obsolete_root),
    'direct legacy migration records disabled systemd state with kill links' );

my $legacy_target_live_root = stage_root();
make_path( File::Spec->catdir( $legacy_target_live_root, 'etc', 'init.d' ) );
write_file( live_init($legacy_target_live_root), "live first-migration content\n", 0755 );
set_systemd_state( $legacy_target_live_root, 'enabled' );
set_init_target( $legacy_target_live_root, 'upstart' );
is( run_state( $legacy_target_live_root, 'configure-legacy', 'upgrade' ), 0,
    'live conffile migrates directly to a legacy target' );
is( read_file( live_init($legacy_target_live_root) ),
    "live first-migration content\n",
    'direct legacy migration preserves live administrator content' );
ok( -l rc_link($legacy_target_live_root),
    'native systemd enablement maps to SysV on first legacy migration' );

my $legacy_target_deleted_root = stage_root();
make_path( state_dir($legacy_target_deleted_root) );
write_file(
    File::Spec->catfile( state_dir($legacy_target_deleted_root), 'pending-deleted' ),
    "deleted\n"
);
set_systemd_state( $legacy_target_deleted_root, 'enabled' );
set_init_target( $legacy_target_deleted_root, 'upstart' );
is( run_state( $legacy_target_deleted_root, 'configure-legacy', 'upgrade' ), 0,
    'deleted conffile migrates directly to a legacy target' );
ok( !-e live_init($legacy_target_deleted_root),
    'direct legacy migration preserves administrator deletion' );
ok( !-e rc_link($legacy_target_deleted_root),
    'deleted conffile is never registered under SysV' );
is( registration_link_count($legacy_target_deleted_root), 0,
    'deleted conffile gains neither start nor kill links' );

my $backup_root = stage_root();
make_path( File::Spec->catdir( $backup_root, 'etc', 'init.d' ) );
write_file( live_init($backup_root) . '.dpkg-bak', "recoverable customization\n", 0755 );
set_systemd_state( $backup_root, 'disabled' );
set_init_target( $backup_root, 'upstart' );
is( run_state( $backup_root, 'configure-legacy', 'upgrade' ), 0,
    'dpkg backup migration succeeds' );
is( read_file( live_init($backup_root) ), "recoverable customization\n",
    'a dpkg conffile backup is recovered through ucf' );

my $origin_reversal_root = stage_root();
set_init_target( $origin_reversal_root, 'upstart' );
is( run_state( $origin_reversal_root, 'configure-legacy', 'fresh' ), 0,
    'origin-reversal fixture starts in legacy mode' );
write_file( live_init($origin_reversal_root), "origin customization\n", 0755 );
is( run_state( $origin_reversal_root, 'prepare-systemd', 'upgrade' ), 0,
    'origin-reversal fixture begins a systemd transition' );
is( state_value( $origin_reversal_root, 'origin' ), 'legacy',
    'legacy origin is recorded before systemd enablement runs' );
write_file( File::Spec->catfile( $origin_reversal_root, 'mutate-ucf' ), "mutate\n" );
write_file( File::Spec->catfile( $origin_reversal_root, 'fail-ucfr' ), "fail\n" );
isnt( run_state( $origin_reversal_root, 'configure-legacy', 'upgrade' ), 0,
    'reversed pre-enable transition can fail during legacy restoration' );
is( state_value( $origin_reversal_root, 'origin' ), 'legacy',
    'failed reversal preserves the original legacy provenance' );
set_init_target( $origin_reversal_root, '../lib/systemd/systemd' );
is( run_state( $origin_reversal_root, 'prepare-systemd', 'upgrade' ), 0,
    'failed reversal can return toward systemd' );
is( state_value( $origin_reversal_root, 'origin' ), 'legacy',
    'second systemd attempt still requires legacy-origin enablement' );
is( state_value( $origin_reversal_root, 'enabled' ), 'yes',
    'second systemd attempt retains intended enablement' );

my $registration_retry_root = stage_root();
set_init_target( $registration_retry_root, 'upstart' );
is( run_state( $registration_retry_root, 'configure-legacy', 'fresh' ), 0,
    'registration retry fixture starts enabled in legacy mode' );
is( run_state( $registration_retry_root, 'prepare-systemd', 'upgrade' ), 0,
    'registration retry fixture begins a systemd transition' );
run_update_rc( $registration_retry_root, '-f', 'xcatd', 'remove' );
write_file( File::Spec->catfile( $registration_retry_root, 'fail-ucfr' ), "fail\n" );
isnt( run_state( $registration_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'legacy reversal fails before registration is restored' );
unlink( File::Spec->catfile( $registration_retry_root, 'fail-ucfr' ) )
  or die "Unable to clear registration retry failure: $!";
is( run_state( $registration_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'legacy reversal retries successfully' );
ok( -l rc_link($registration_retry_root),
    'transition retry restores missing SysV registration' );

my $retry_root = stage_root();
set_init_target( $retry_root, 'upstart' );
is( run_state( $retry_root, 'configure-legacy', 'fresh' ), 0,
    'retry fixture starts in legacy mode' );
write_file( live_init($retry_root), "retry customization\n", 0755 );
is( run_state( $retry_root, 'prepare-systemd', 'upgrade' ), 0,
    'retry fixture is durably stashed' );
set_init_target( $retry_root, '../lib/systemd/systemd' );
is( run_compat( $retry_root, 'configure', '--explicit-target' ), 0,
    'retry fixture enters systemd mode' );
is( run_state( $retry_root, 'commit-systemd' ), 0,
    'retry fixture commits systemd state' );
set_systemd_state( $retry_root, 'enabled' );
set_init_target( $retry_root, 'upstart' );
write_file( File::Spec->catfile( $retry_root, 'mutate-ucf' ), "mutate\n" );
write_file( File::Spec->catfile( $retry_root, 'fail-ucfr' ), "fail\n" );
isnt( run_state( $retry_root, 'configure-legacy', 'upgrade' ), 0,
    'a failure after ucf mutation reports failure' );
ok( -e File::Spec->catfile( state_dir($retry_root), 'xcatd' ),
    'failed restoration retains the durable stash' );
is( read_file( File::Spec->catfile( state_dir($retry_root), 'xcatd' ) ),
    "retry customization\n",
    'partial restoration cannot overwrite the original stash' );
is( state_value( $retry_root, 'mode' ), 'transition-legacy',
    'failed restoration remains explicitly transitional' );
unlink( File::Spec->catfile( $retry_root, 'mutate-ucf' ) )
  or die "Unable to clear injected ucf mutation: $!";
unlink( File::Spec->catfile( $retry_root, 'fail-ucfr' ) )
  or die "Unable to clear injected ucfr failure: $!";
is( run_state( $retry_root, 'configure-legacy', 'upgrade' ), 0,
    'a repeated configure completes the interrupted transition' );
is( read_file( live_init($retry_root) ), "retry customization\n",
    'retry preserves the customized content' );

my $reversal_retry_root = stage_root();
set_init_target( $reversal_retry_root, 'upstart' );
is( run_state( $reversal_retry_root, 'configure-legacy', 'fresh' ), 0,
    'reversal retry fixture starts in legacy mode' );
write_file( live_init($reversal_retry_root), "reversal customization\n", 0755 );
is( run_state( $reversal_retry_root, 'prepare-systemd', 'upgrade' ), 0,
    'reversal retry fixture is durably stashed' );
set_init_target( $reversal_retry_root, '../lib/systemd/systemd' );
is( run_compat( $reversal_retry_root, 'configure', '--explicit-target' ), 0,
    'reversal retry fixture enters systemd mode' );
is( run_state( $reversal_retry_root, 'commit-systemd' ), 0,
    'reversal retry fixture commits systemd state' );
set_systemd_state( $reversal_retry_root, 'enabled' );
set_init_target( $reversal_retry_root, 'upstart' );
write_file( File::Spec->catfile( $reversal_retry_root, 'mutate-ucf' ), "mutate\n" );
write_file( File::Spec->catfile( $reversal_retry_root, 'fail-ucfr' ), "fail\n" );
isnt( run_state( $reversal_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'reversal retry fixture fails after UCF mutation' );
set_init_target( $reversal_retry_root, '../lib/systemd/systemd' );
is( run_state( $reversal_retry_root, 'prepare-systemd', 'upgrade' ), 0,
    'a reversed transition prepares for systemd again' );
is( read_file(
        File::Spec->catfile( state_dir($reversal_retry_root), 'xcatd' )
    ),
    "reversal customization\n",
    'reversing a failed restoration cannot overwrite the durable stash' );
is( run_compat( $reversal_retry_root, 'configure', '--explicit-target' ), 0,
    'reversed transition removes the partial live script' );
is( run_state( $reversal_retry_root, 'commit-systemd' ), 0,
    'reversed transition commits systemd state' );
unlink( File::Spec->catfile( $reversal_retry_root, 'mutate-ucf' ) )
  or die "Unable to clear reversed UCF mutation: $!";
unlink( File::Spec->catfile( $reversal_retry_root, 'fail-ucfr' ) )
  or die "Unable to clear reversed ucfr failure: $!";
set_init_target( $reversal_retry_root, 'upstart' );
is( run_state( $reversal_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'reversed transition can later return to legacy mode' );
is( read_file( live_init($reversal_retry_root) ), "reversal customization\n",
    'reversed transition eventually restores exact administrator content' );

my $default_retry_root = stage_root();
set_systemd_state( $default_retry_root, 'disabled' );
is( run_state( $default_retry_root, 'prepare-systemd', 'fresh' ), 0,
    'package-default retry fixture prepares as a fresh systemd install' );
is( run_state( $default_retry_root, 'commit-systemd' ), 0,
    'package-default retry fixture commits systemd state' );
set_systemd_state( $default_retry_root, 'enabled' );
set_init_target( $default_retry_root, 'upstart' );
write_file( File::Spec->catfile( $default_retry_root, 'mutate-ucf' ), "mutate\n" );
write_file( File::Spec->catfile( $default_retry_root, 'fail-ucfr' ), "fail\n" );
isnt( run_state( $default_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'package-default restoration can fail after materialization' );
is( state_value( $default_retry_root, 'content' ), 'package-default',
    'partial package materialization is not promoted to customization' );
unlink( File::Spec->catfile( $default_retry_root, 'mutate-ucf' ) )
  or die "Unable to clear package-default UCF mutation: $!";
unlink( File::Spec->catfile( $default_retry_root, 'fail-ucfr' ) )
  or die "Unable to clear package-default ucfr failure: $!";
is( run_state( $default_retry_root, 'configure-legacy', 'upgrade' ), 0,
    'package-default restoration retries successfully' );
is( read_file( live_init($default_retry_root) ), read_file($template),
    'package-default retry rematerializes the exact packaged template' );
ok( !-e File::Spec->catfile( state_dir($default_retry_root), 'xcatd' ),
    'package-default retry does not create a durable customization stash' );

my $format1_root = stage_root();
make_path( state_dir($format1_root) );
write_file( File::Spec->catfile( state_dir($format1_root), 'state' ),
    "format=1\nmode=systemd\ncontent=package-default\nenabled=no\norigin=unknown\n" );
set_systemd_state( $format1_root, 'disabled' );
set_init_target( $format1_root, 'upstart' );
is( run_state( $format1_root, 'configure-legacy', 'upgrade' ), 0,
    'format-1 disabled state converges safely' );
is( state_value( $format1_root, 'format' ), '2',
    'format-1 state is rewritten in registration-aware format 2' );
is( state_value( $format1_root, 'enabled' ), 'unregistered',
    'format-1 no preserves its historical remove-all-links behavior' );
is( registration_link_count($format1_root), 0,
    'format-1 no does not invent registered-disabled metadata' );

my $malformed_root = stage_root();
make_path( state_dir($malformed_root), File::Spec->catdir( $malformed_root, 'etc', 'init.d' ) );
write_file( live_init($malformed_root), "must survive\n", 0755 );
write_file( File::Spec->catfile( state_dir($malformed_root), 'state' ),
    "format=9\nmode=legacy\ncontent=active\nenabled=yes\n" );
isnt( run_state( $malformed_root, 'prepare-systemd', 'upgrade' ), 0,
    'malformed persistent state fails closed' );
is( read_file( live_init($malformed_root) ), "must survive\n",
    'malformed state cannot delete the live init script' );

write_file( File::Spec->catfile( state_dir($malformed_root), 'state' ),
    "format=1\nmode=legacy\ncontent=active\nenabled=yes\n" );
isnt( run_state( $malformed_root, 'prepare-systemd', 'upgrade' ), 0,
    'incomplete persistent state fails closed' );
is( read_file( live_init($malformed_root) ), "must survive\n",
    'incomplete state cannot delete the live init script' );

done_testing();
