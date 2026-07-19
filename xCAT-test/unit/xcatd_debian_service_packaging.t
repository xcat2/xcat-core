#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
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

sub init_classifier_block {
    my ($script) = @_;
    return $1
      if $script =~
      /(xcat_systemd_os_release_status\(\).*?\n}\n\nxcat_target_uses_systemd\(\).*?\n})\n\n/s;
    return '';
}

sub pending_cleanup_block {
    my ($script) = @_;
    return $1
      if $script =~ /(clear_xcatd_pending_state\(\)\n\{.*?\n\})\n/s;
    return '';
}

sub legacy_state_block {
    my ($script) = @_;
    return $1
      if $script =~
      /(xcatd_legacy_enable_state\(\)\n\{.*?\n\})\n\nif xcat_target_uses_systemd/s;
    return '';
}

sub run_legacy_state_block {
    my ( $block, $helper_source ) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $helper = File::Spec->catfile( $root, 'xcatd-init-compat' );
    open( my $helper_fh, '>', $helper )
      or die "Unable to stage compatibility helper: $!";
    print {$helper_fh} $helper_source;
    close($helper_fh);
    chmod 0755, $helper;

    my $rpm_runlevel =
      File::Spec->catdir( $root, 'etc', 'rc.d', 'rc3.d' );
    make_path($rpm_runlevel);
    symlink( '/etc/init.d/xcatd',
        File::Spec->catfile( $rpm_runlevel, 'S85xcatd' ) )
      or die "Unable to stage RPM-only runlevel link: $!";

    my $isolated_block = $block;
    $isolated_block =~ s{/etc/rc}{\$fixture_root/etc/rc}g;
    my $runner = File::Spec->catfile( $root, 'run-detector' );
    open( my $runner_fh, '>', $runner )
      or die "Unable to stage detector runner: $!";
    print {$runner_fh} "#!/bin/sh\nset -e\n";
    print {$runner_fh} "fixture_root=\${XCAT_TEST_ROOT:?}\n";
    print {$runner_fh} "xcatd_init_compat=\${XCAT_TEST_HELPER:?}\n";
    print {$runner_fh} "$isolated_block\n\nxcatd_legacy_enable_state\n";
    close($runner_fh);
    chmod 0755, $runner;

    local $ENV{XCAT_TEST_ROOT}   = $root;
    local $ENV{XCAT_TEST_HELPER} = $helper;
    open( my $pipe, '-|', '/bin/sh', $runner )
      or die "Unable to run preinst detector: $!";
    my $output = do { local $/; <$pipe> };
    close($pipe);
    my $status = $? >> 8;
    $output =~ s/\s+\z//;
    return ( $status, $output );
}

my $deb_install = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'install' )
);
like( $deb_install, qr{^etc/init\.d/xcatd opt/xcat/share/xcat/scripts$}m,
    'Debian stages the legacy script as a compatibility template' );
unlike( $deb_install, qr{^etc/init\.d/xcatd etc/init\.d$}m,
    'Debian does not install the legacy script directly' );

my $deb_dirs = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'dirs' )
);
unlike( $deb_dirs, qr{^etc/init\.d/?$}m,
    'Debian does not package an empty legacy init directory' );

foreach my $maintainer_script (qw(preinst postinst postrm)) {
    my $script = read_file(
        File::Spec->catfile(
            $repo_root, 'xCAT-server', 'debian', $maintainer_script
        )
    );
    like( $script,
        qr{dpkg-maintscript-helper rm_conffile /etc/init\.d/xcatd -- "\$\@"},
        "Debian $maintainer_script participates in graceful conffile removal" );
}

my $deb_postinst = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'postinst' )
);
like( $deb_postinst,
    qr{if "\$xcatd_init_compat" uses-systemd --explicit-target; then},
    'Debian postinst delegates target init detection to the packaged helper' );
unlike( $deb_postinst,
    qr{"\$xcatd_init_compat" (?:uses-systemd|configure)(?! --explicit-target)},
    'every Debian postinst helper call uses explicit target detection' );
unlike( $deb_postinst, qr{sub xcat_target_uses_systemd|xcat_target_uses_systemd\(\)},
    'Debian postinst does not carry weaker duplicate init detection' );
my $deb_init_state = read_file(
    File::Spec->catfile(
        $repo_root, 'xCAT-server', 'debian', 'xcatd-init-state'
    )
);
like( $deb_init_state,
    qr{\[ -x "\$legacy_init" \].*?update-rc\.d xcatd defaults}s,
    'Debian registers SysV only after materializing an executable script' );
like( $deb_init_state,
    qr{apply_legacy_registration\(\).*?no\).*?update-rc\.d xcatd defaults.*?update-rc\.d xcatd disable.*?unregistered\|unknown\).*?update-rc\.d -f xcatd remove}s,
    'Debian distinguishes registered-disabled from unregistered SysV state' );
like( $deb_init_state,
    qr{stash_candidate\(\).*?if ! cp -a.*?\|\|\s*! mv -f.*?rm -f "\$stash_tmp".*?return 1}s,
    'Debian removes a failed atomic stash temporary' );
like( $deb_init_state, qr{printf 'format=2},
    'Debian writes registration-aware state format 2' );
like( $deb_init_state,
    qr{state_format" = 1.*?state_enabled" = no.*?state_enabled=unregistered}s,
    'Debian preserves format-1 remove-all-links behavior' );
my @unregistered_refresh_guards =
  $deb_init_state =~ /state_enabled" != unregistered/g;
is( scalar @unregistered_refresh_guards, 2,
    'both systemd refresh paths retain unregistered provenance' );
like( $deb_init_state,
    qr{init_compat=.*?xcatd-init-compat.*?shared_init_state\(\).*?"\$init_compat" "\$\@".*?debian-legacy-state.*?systemd-state --allow-unknown}s,
    'Debian delegates legacy and precise systemd state detection to the shared helper' );
unlike( $deb_init_state,
    qr{systemctl (?:--root=.*? )?is-enabled|systemd/system/\*\.(?:wants|requires)/xcatd\.service|rc\?\.d/S\?\?xcatd},
    'Debian init state does not duplicate shared service-state probes' );
like( $deb_postinst,
    qr{transition_origin=.*?get origin.*?fresh:yes\|legacy:yes.*?systemctl enable}s,
    'Debian changes systemd enablement only for fresh installs and init transitions' );
like( $deb_postinst,
    qr{legacy:no\|legacy:unregistered\) systemctl disable xcatd\.service},
    'Debian maps both disabled SysV registration states to systemd disablement' );
unlike( $deb_postinst, qr{systemd:yes.*?systemctl enable}s,
    'Debian same-systemd upgrades do not normalize existing enablement' );

my %classifier_blocks;
foreach my $fallback_script (qw(preinst postrm)) {
    my $script = read_file(
        File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', $fallback_script )
    );
    $classifier_blocks{$fallback_script} = init_classifier_block($script);
    ok( $classifier_blocks{$fallback_script} ne '',
        "Debian $fallback_script classifier can be extracted" );
    like( $script, qr{VERSION_ID.*?ubuntu.*?-ge 15.*?debian.*?-ge 8}s,
        "Debian $fallback_script recognizes stripped modern targets" );
    like( $script, qr{\[ "\$os_id" = "debian" \].*?\[ -z "\$os_version" \]}s,
        "Debian $fallback_script recognizes testing and sid without VERSION_ID" );
    like( $script, qr{value=\$\{value#\\'\}\s+value=\$\{value%\\'\}}s,
        "Debian $fallback_script strips single-quoted os-release values" );
    like( $script,
        qr{xcat_target_uses_systemd\(\).*?\[ -d /run/systemd/system \].*?\[ -L /sbin/init \].*?\*\) return 1 ;;.*?\[ -e /sbin/init \].*?return 1.*?if xcat_systemd_os_release_status; then.*?\[ -x /usr/lib/systemd/systemd \]}s,
        "Debian $fallback_script prefers active and explicit target evidence" );
    like( $script,
        qr{xcat_systemd_os_release_status\(\).*?return 2.*?return 1.*?return 2}s,
        "Debian $fallback_script distinguishes legacy from unknown releases" );
}
my $deb_preinst = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'preinst' )
);
my $preinst_legacy_state_block = legacy_state_block($deb_preinst);
ok( $preinst_legacy_state_block ne '',
    'preinst legacy registration detector can be extracted' );
is_deeply(
    [ run_legacy_state_block( $preinst_legacy_state_block, <<'SH' ) ],
#!/bin/sh
root=${XCAT_TEST_ROOT:?}
case "${1:-}" in
    legacy-state)
        for link in "$root"/etc/rc.d/rc?.d/S??xcatd; do
            if [ -e "$link" ] || [ -L "$link" ]; then
                printf '%s\n' enabled
                exit 0
            fi
        done
        printf '%s\n' unregistered
        ;;
    *) exit 2 ;;
esac
SH
    [ 0, 'unregistered' ],
    'preinst falls back to Debian links when the installed helper lacks the command'
);
is_deeply(
    [ run_legacy_state_block( $preinst_legacy_state_block, <<'SH' ) ],
#!/bin/sh
root=${XCAT_TEST_ROOT:?}
case "${1:-}:$#" in
    debian-legacy-state:1)
        for link in "$root"/etc/rc?.d/S??xcatd; do
            if [ -e "$link" ] || [ -L "$link" ]; then
                printf '%s\n' enabled
                exit 0
            fi
        done
        printf '%s\n' unregistered
        ;;
    *) exit 2 ;;
esac
SH
    [ 0, 'unregistered' ],
    'preinst uses Debian-only state from a command-aware installed helper'
);
my ( $malformed_helper_status, $malformed_helper_output ) =
  run_legacy_state_block( $preinst_legacy_state_block, <<'SH' );
#!/bin/sh
[ "${1:-}" = debian-legacy-state ] || exit 2
printf '%s\n' malformed
SH
is( $malformed_helper_status, 1,
    'preinst rejects malformed successful helper output' );
is( $malformed_helper_output, '',
    'preinst does not promote malformed helper output' );
my ( $failed_helper_status, $failed_helper_output ) =
  run_legacy_state_block( $preinst_legacy_state_block, <<'SH' );
#!/bin/sh
exit 7
SH
is( $failed_helper_status, 7,
    'preinst fails closed on non-capability helper errors' );
is( $failed_helper_output, '',
    'preinst does not fall back after a real helper failure' );
like( $deb_preinst,
    qr{write_xcatd_context\(\)\s*\(.*?umask 077.*?\n\)}s,
    'preinst confines the context-file umask to a subshell' );
like( $deb_preinst,
    qr{context_tmp=.*?if ! printf.*?\|\|\s*! mv -f.*?rm -f "\$context_tmp".*?return 1}s,
    'preinst removes a failed context-file temporary' );
my $preinst_pending_cleanup = pending_cleanup_block($deb_preinst);
like( $preinst_pending_cleanup,
    qr{pending-xcatd.*?pending-deleted.*?pending-enabled.*?pending-xcatd\.tmp\.}s,
    'preinst clears every transaction-local pending state artifact' );
like( $deb_preinst,
    qr{conffile_record=.*?dpkg-query.*?case "\$conffile_record" in.*?obsolete.*?touch "\$xcatd_old_systemd_marker".*?\*\).*?touch "\$xcatd_state_dir/pending-deleted"}s,
    'preinst distinguishes package-obsolete conffiles from administrator deletion' );
like( $deb_preinst,
    qr{xcatd_transition_context=\s*case "\$1" in\s*upgrade\) xcatd_transition_context=upgrade ;;\s*install\) xcatd_transition_context=fresh ;;\s*esac\s*if \[ -n "\$xcatd_transition_context" \]}s,
    'preinst prepares transition state only for install and upgrade calls' );
like( $deb_preinst,
    qr{\$xcatd_legacy_init\.dpkg-bak.*?\$xcatd_legacy_init\.dpkg-backup.*?\$xcatd_legacy_init\.dpkg-remove}s,
    'preinst recovers every conffile backup name used during interrupted removal' );
like( $deb_preinst,
    qr{pending_tmp=.*?if ! cp -a.*?\|\|\s*! mv -f.*?rm -f "\$pending_tmp".*?exit 1}s,
    'preinst removes a failed pending-stash temporary' );
like( $deb_preinst,
    qr{if \[ -n "\$conffile_record" \]; then.*?case "\$conffile_record" in.*?esac\s*else\s*# A retry without an installed conffile record.*?clear_xcatd_pending_state\s*fi}s,
    'preinst discards stale pending evidence when dpkg has no conffile record' );
like( $deb_preinst,
    qr{xcatd_legacy_enable_state\(\).*?"\$xcatd_init_compat" debian-legacy-state 2>/dev/null.*?detector_status=\$\?.*?"\$detector_status" -ne 2.*?/etc/rc\?\.d/S\?\?xcatd.*?/etc/rc\?\.d/K\?\?xcatd.*?unregistered}s,
    'preinst reuses shared registration detection with a pre-unpack S/K fallback' );
like( $deb_preinst,
    qr{upgrade\)\s*write_xcatd_context upgrade.*?install\)\s*write_xcatd_context fresh.*?abort-upgrade\)\s*rm -f "\$xcatd_context_file"}s,
    'preinst records explicit durable package transition context' );
like( $deb_postinst,
    qr{ln -sf /opt/xcat/sbin/xcatd /usr/sbin/xcatd.*?#DEBHELPER#.*?rm -f "\$xcatd_context_file"}s,
    'postinst retains upgrade context until every fallible installation step succeeds' );
like( $deb_postinst,
    qr{if \[ -r "\$xcatd_context_file" \].*?fresh\|upgrade.*?elif \[ "\$1" = configure \] && \[ -n "\$\{2:-\}" \].*?xcatd_transition_context=upgrade}s,
    'postinst validates explicit context and preserves state on configured-package fallback' );
unlike( "$deb_preinst\n$deb_postinst", qr{/tmp/xCAT-server_upgrade\.tmp},
    'maintainer scripts keep transaction state out of shared temporary storage' );
is( $classifier_blocks{preinst}, $classifier_blocks{postrm},
    'Debian preinst and postrm carry the same lifecycle-safe classifier' );

my $deb_postrm = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'postrm' )
);
my $postrm_pending_cleanup = pending_cleanup_block($deb_postrm);
is( $postrm_pending_cleanup, $preinst_pending_cleanup,
    'preinst and postrm share the same pending-state cleanup contract' );
unlike( $deb_postrm, qr{/tmp/xCAT-server_upgrade\.tmp},
    'postrm keeps transaction state out of shared temporary storage' );
my ($abort_install) = $deb_postrm =~ /\n\s*abort-install\)\n(.*?)\n\s*;;/s;
my ($abort_upgrade) =
  $deb_postrm =~ /\n\s*abort-upgrade\|disappear\)\n(.*?)\n\s*;;/s;
ok( defined($abort_install) && defined($abort_upgrade),
    'postrm abort recovery arms can be inspected independently' );
like( $abort_install,
    qr{clear_xcatd_pending_state.*?rm -f "\$xcatd_context_file".*?rmdir "\$xcatd_state_dir"}s,
    'abort-install clears pending context and removes only an empty state directory' );
unlike( $abort_install,
    qr{\$xcatd_state_dir/(?:state|xcatd)|xcatd_old_systemd_marker},
    'abort-install preserves durable init state and compatibility evidence' );
like( $abort_upgrade, qr{rm -f "\$xcatd_context_file"},
    'abort-upgrade clears only the completed-attempt context' );
unlike( $abort_upgrade,
    qr{clear_xcatd_pending_state|pending-(?:xcatd|deleted|enabled)},
    'abort-upgrade preserves pending recovery evidence for retry' );
like( $deb_postrm,
    qr{purge\).*?rm -f "\$xcatd_context_file".*?upgrade\|failed-upgrade\)\s*;;.*?remove\).*?rm -f "\$xcatd_context_file"}s,
    'postrm clears upgrade context only when installation cannot continue' );

my $deb_prerm = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'prerm' )
);
like( $deb_prerm,
    qr{if "\$xcatd_init_compat" uses-systemd --explicit-target; then.*?update-rc\.d -f xcatd remove}s,
    'Debian prerm removes registration through the detected init implementation' );
unlike( $deb_prerm,
    qr{"\$xcatd_init_compat" uses-systemd(?! --explicit-target)},
    'every Debian prerm helper call uses explicit target detection' );

done_testing();
