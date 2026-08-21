#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $source_dir = File::Spec->catdir(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-console files xcat-genesis-console src)
);
my @plain_sources = map { File::Spec->catfile( $source_dir, $_ ) }
  qw(main.c plain_ui.c shell.c state.c support.c);
my $root = tempdir( CLEANUP => 1 );
my $binary = File::Spec->catfile( $root, 'xcat-genesis-console' );
my $header_test_source = File::Spec->catfile( $root, 'header-test.c' );
my $header_test_binary = File::Spec->catfile( $root, 'header-test' );
my $compiler = $ENV{CC} || 'cc';

is(
    system(
        $compiler, '-D_POSIX_C_SOURCE=200809L', '-DXCAT_CONSOLE_PLAIN_ONLY',
        '-std=c17', '-Wall', '-Wextra', '-Wpedantic', '-Werror',
        @plain_sources, '-o', $binary
      ) >> 8,
    0,
    'plain console builds with strict warnings'
) or BAIL_OUT('unable to build the console test binary');

sub write_file {
    my ( $path, $contents ) = @_;
    open( my $stream, '>', $path ) or die "Unable to write $path: $!";
    print {$stream} $contents;
    close($stream);
}

sub read_file {
    my ($path) = @_;
    open( my $stream, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$stream> };
    close($stream);
    return $contents;
}

write_file(
    $header_test_source,
    <<'C'
#include "console.h"

#include <assert.h>

int main(void) {
    assert(xcat_header_context_columns(0) == 0);
    assert(xcat_header_context_columns(19) == 0);
    assert(xcat_header_context_columns(20) == 0);
    assert(xcat_header_context_columns(21) == 1);
    assert(xcat_header_context_columns(80) == 60);
    return 0;
}
C
);
is(
    system(
        $compiler, '-D_POSIX_C_SOURCE=200809L', '-std=c17', '-Wall', '-Wextra',
        '-Wpedantic', '-Werror', '-I', $source_dir, $header_test_source,
        File::Spec->catfile( $source_dir, 'support.c' ), '-o', $header_test_binary
      ) >> 8,
    0,
    'header bounds test builds with strict warnings'
);
is( system($header_test_binary) >> 8, 0,
    'narrow terminals leave no writable header context' );

my $cmdline = File::Spec->catfile( $root, 'cmdline' );
my $uptime = File::Spec->catfile( $root, 'uptime' );
my $os_release_real = File::Spec->catfile( $root, 'os-release.real' );
my $os_release = File::Spec->catfile( $root, 'os-release' );
my $state_dir = File::Spec->catdir( $root, 'status' );
my $genesis_env = File::Spec->catfile( $root, 'genesis.env' );
my $destiny = File::Spec->catfile( $root, 'destiny' );
my $response = File::Spec->catfile( $root, 'xcat-response.env' );
my $sys_root = File::Spec->catdir( $root, 'sys' );
my $proc_root = File::Spec->catdir( $root, 'proc' );
my $net_root = File::Spec->catdir( $sys_root, 'class', 'net', 'eth0' );
my $dmi_root = File::Spec->catdir( $sys_root, 'class', 'dmi', 'id' );
my $extensions = File::Spec->catdir( $root, 'extensions' );
my $providers = File::Spec->catdir( $root, 'providers' );

make_path(
    $state_dir, $net_root, $dmi_root, $proc_root, $extensions, $providers,
    File::Spec->catdir( $sys_root, 'firmware', 'efi' )
);
write_file( $cmdline,
    "xcatd=192.0.2.10:3001 BOOTIF=01-52-54-00-00-00-01 gateway=192.0.2.1\n" );
write_file( $uptime, "125.90 200.00\n" );
write_file( $os_release_real,
    "NAME=\"xCAT Genesis\"\nVERSION_ID=\"0.1\"\n" );
symlink( $os_release_real, $os_release )
  or die "Unable to create os-release link: $!";
write_file(
    File::Spec->catfile( $state_dir, 'network.env' ),
    "SCHEMA=1\nSTATE=READY\nDETAIL=Management network ready on eth0\n"
      . "STARTED_SECONDS=100\nUPDATED_SECONDS=100\nVERIFIED_SECONDS=100\n"
);
write_file(
    File::Spec->catfile( $state_dir, 'registration.env' ),
    "SCHEMA=1\nSTATE=ACTION_RECEIVED\nDETAIL=Action osimage received\n"
      . "STARTED_SECONDS=110\nUPDATED_SECONDS=120\nVERIFIED_SECONDS=120\n"
      . "NODE_NAME=compute01\nACTION=osimage\nTARGET=rocky9\n"
);
my $extension_ready =
    "SCHEMA=1\nSTATE=READY\nDETAIL=Genesis extensions loaded\n"
      . "STARTED_SECONDS=105\nUPDATED_SECONDS=106\n";
write_file(
    File::Spec->catfile( $state_dir, 'extensions.env' ),
    $extension_ready
);
my $ipv4_network_state =
    "XCATDEST=192.0.2.10:3001\nXCAT_INTERFACE=eth0\n"
      . "XCAT_SOURCE_ADDRESS=192.0.2.20\n"
      . "XCAT_SOURCE_PREFIXED_ADDRESS=192.0.2.20/24\n"
      . "XCAT_GATEWAY=192.0.2.1\nXCAT_DNS_SERVERS=192.0.2.53\n"
      . "XCAT_NETWORK_METHOD=auto\nXCAT_LINK_STATE=up\n"
      . "XCAT_MAC_ADDRESS=52:54:00:00:00:01\n";
write_file( $genesis_env, $ipv4_network_state );
write_file( $destiny, "osimage=rocky9\n" );
write_file( $response, "XCAT_NODE_NAME=compute01\n" );
write_file( File::Spec->catfile( $net_root, 'operstate' ), "up\n" );
write_file( File::Spec->catfile( $net_root, 'address' ),
    "52:54:00:00:00:01\n" );
write_file( File::Spec->catfile( $dmi_root, 'product_serial' ),
    "TEST-SERIAL-001\n" );
write_file( File::Spec->catfile( $dmi_root, 'product_uuid' ),
    "11111111-2222-3333-4444-555555555555\n" );
write_file( File::Spec->catfile( $extensions, 'one.raw' ), '' );
write_file( File::Spec->catfile( $extensions, 'two.raw' ), '' );
symlink( File::Spec->catfile( $extensions, 'one.raw' ),
    File::Spec->catfile( $extensions, 'linked.raw' ) )
  or die "Unable to create extension link: $!";
write_file( File::Spec->catfile( $providers, 'one.json' ), "{}\n" );
write_file( File::Spec->catfile( $providers, 'two.json' ), "{}\n" );
symlink( File::Spec->catfile( $providers, 'one.json' ),
    File::Spec->catfile( $providers, 'linked.json' ) )
  or die "Unable to create provider link: $!";

my %environment = (
    XCAT_CMDLINE_FILE => $cmdline,
    XCAT_UPTIME_FILE  => $uptime,
    XCAT_OS_RELEASE   => $os_release,
    XCAT_STATUS_DIR   => $state_dir,
    XCAT_STATE_FILE   => $genesis_env,
    XCAT_DESTINY_FILE => $destiny,
    XCAT_RESPONSE_FILE => $response,
    XCAT_SYS_ROOT     => $sys_root,
    XCAT_PROC_ROOT    => $proc_root,
    XCAT_EXTENSION_DIR => $extensions,
    XCAT_PROVIDER_DIR => $providers,
);

sub run_console {
    local %ENV = ( %ENV, %environment );
    open( my $stream, '-|', $binary, '--once' )
      or die "Unable to run $binary: $!";
    my $output = do { local $/; <$stream> };
    close($stream);
    return ( $? >> 8, $output );
}

my ( $status, $output ) = run_console();
is( $status, 0, 'plain console renders a status snapshot' );
like( $output,
    qr/^xCAT Genesis \| ACTION_RECEIVED \| in stage 00:00:15$/m,
    'header shows the actual state and stage duration' );
like( $output,
    qr/^node: compute01\nserial: TEST-SERIAL-001$/m,
    'node and hardware serial are separate fields' );
like( $output,
    qr/^interface: eth0\nlink: up\nmethod: DHCP\naddress: 192\.0\.2\.20\/24\nMAC: 52:54:00:00:00:01$/m,
    'network fields use explicit labels and describe automatic setup as DHCP' );
like( $output,
    qr/^xCAT server: 192\.0\.2\.10:3001\nxCAT contact: Action received$/m,
    'xCAT endpoint and contact result are separate fields' );
like( $output,
    qr/^action: Boot assigned image\ntarget: rocky9\nprogress: none$/m,
    'action and target remain distinct' );
unlike( $output, qr/last contact/i,
    'main status omits the redundant contact timer' );
unlike( $output, qr/extensions:|providers:|Linux /,
    'inventory details stay off the main page' );
unlike( $output, qr/\e/, 'plain output has no terminal escapes' );

my $cmdline_without_xcat = $ipv4_network_state;
$cmdline_without_xcat =~ s/^XCATDEST=.*\n//m;
write_file( $genesis_env, $cmdline_without_xcat );
write_file(
    $cmdline,
    ( 'quiet ' x 100 )
      . "xcatd=198.51.100.10:3001 BOOTIF=01-52-54-00-00-00-01\n"
);
( $status, $output ) = run_console();
like( $output, qr/^xCAT server: 198\.51\.100\.10:3001$/m,
    'console reads xCAT parameters after byte 512' );
write_file( $genesis_env, $ipv4_network_state );
write_file( $cmdline,
    "xcatd=192.0.2.10:3001 BOOTIF=01-52-54-00-00-00-01 gateway=192.0.2.1\n" );

write_file(
    File::Spec->catfile( $state_dir, 'extensions.env' ),
    "SCHEMA=1\nSTATE=FAILED\nDETAIL=extension signature verification failed\n"
      . "STARTED_SECONDS=123\nUPDATED_SECONDS=124\n"
      . "CODE=EXTENSION_VERIFICATION_FAILED\n"
      . "RECOVERY=Check extension images, manifests, signatures, and trusted keys\n"
);
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders an extension failure' );
like( $output,
    qr/^error: EXTENSION_VERIFICATION_FAILED: extension signature verification failed$/m,
    'extension verification failures stop the main status' );
like( $output,
    qr/^recovery: Check extension images, manifests, signatures, and trusted keys$/m,
    'extension failures include a recovery hint' );
write_file(
    File::Spec->catfile( $state_dir, 'extensions.env' ),
    $extension_ready
);

write_file(
    $genesis_env,
    "XCATDEST=[2001:db8::10]:3001\nXCAT_INTERFACE=eth0\n"
      . "XCAT_SOURCE_ADDRESS=2001:db8::20\n"
      . "XCAT_SOURCE_PREFIXED_ADDRESS=2001:db8::20/64\n"
      . "XCAT_GATEWAY=2001:db8::1\nXCAT_DNS_SERVERS=2001:db8::53\n"
      . "XCAT_NETWORK_METHOD=auto\nXCAT_LINK_STATE=up\n"
      . "XCAT_MAC_ADDRESS=52:54:00:00:00:01\n"
);
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders an automatic IPv6 network' );
like( $output,
    qr/^method: SLAAC\/DHCPv6\naddress: 2001:db8::20\/64$/m,
    'automatic IPv6 setup has an accurate method label' );

my $static_network_state = $ipv4_network_state;
$static_network_state =~ s/XCAT_NETWORK_METHOD=auto/XCAT_NETWORK_METHOD=manual/;
write_file( $genesis_env, $static_network_state );
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders a static network' );
like( $output, qr/^method: Static$/m,
    'manual network setup is labeled Static' );
write_file( $genesis_env, $ipv4_network_state );

write_file(
    File::Spec->catfile( $state_dir, 'action.env' ),
    "SCHEMA=1\nSTATE=RUNNING\nDETAIL=Rebooting into the assigned image\n"
      . "STARTED_SECONDS=122\nUPDATED_SECONDS=124\nVERIFIED_SECONDS=124\n"
      . "ACTION=install\nTARGET=rocky9 install image\n"
);
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders action execution' );
like( $output,
    qr/^xCAT Genesis \| RUNNING \| in stage 00:00:03$/m,
    'action execution becomes the overall state' );
like( $output,
    qr/^action: Install assigned image\ntarget: rocky9 install image\nprogress: none$/m,
    'action status overrides the registration snapshot' );

write_file(
    File::Spec->catfile( $state_dir, 'action.env' ),
    "SCHEMA=1\nSTATE=FAILED\nDETAIL=Unsigned runimage actions are not supported\n"
      . "STARTED_SECONDS=124\nUPDATED_SECONDS=124\n"
      . "CODE=UNSAFE_LEGACY_ACTION\n"
      . "RECOVERY=Package the operation as a signed Genesis system extension\n"
      . "ACTION=runimage\nTARGET=legacy.tgz\n"
);
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders an action failure' );
like( $output,
    qr/^error: UNSAFE_LEGACY_ACTION: Unsigned runimage actions are not supported$/m,
    'action failures remain visible on the main page' );
unlike( $output, qr/^(?:target|progress):/m,
    'failure output uses the same detail rows as the status screen' );

unlink( File::Spec->catfile( $state_dir, 'action.env' ) );
write_file(
    File::Spec->catfile( $state_dir, 'registration.env' ),
    "SCHEMA=1\nSTATE=FAILED\nDETAIL=No valid response from xCAT\n"
      . "STARTED_SECONDS=120\nUPDATED_SECONDS=124\n"
      . "CODE=XCAT_RESPONSE_UNAVAILABLE\n"
      . "RECOVERY=Check xcatd and the management network\n"
);
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders a failed state' );
like( $output,
    qr/^xCAT Genesis \| FAILED \| in stage 00:00:05$/m,
    'failed component becomes the overall state' );
like( $output,
    qr/^error: XCAT_RESPONSE_UNAVAILABLE: No valid response from xCAT$/m,
    'failed component supplies an exact error' );
like( $output,
    qr/^xCAT contact: Failed: No valid response from xCAT$/m,
    'xCAT failure appears on the contact line' );
like( $output,
    qr/^recovery: Check xcatd and the management network$/m,
    'failed component supplies a recovery hint' );

write_file(
    File::Spec->catfile( $state_dir, 'registration.env' ),
    "SCHEMA=1\nSTATE=CONTACTING_XCAT\nDETAIL=xCAT has not answered yet\n"
      . "STARTED_SECONDS=120\nUPDATED_SECONDS=124\n"
      . "ATTEMPT=2\nATTEMPT_LIMIT=6\nNEXT_RETRY_SECONDS=5\n"
);
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders retry progress' );
like( $output,
    qr/^action: Boot assigned image\ntarget: rocky9\nprogress: Attempt 2 of 6; retry in 4s$/m,
    'retry countdown uses structured status fields' );

write_file( $response, "XCAT_NODE_NAME=\n" );
( $status, $output ) = run_console();
is( $status, 0, 'plain console renders an empty node response' );
like( $output, qr/^node: unassigned$/m,
    'an empty node response is shown as unassigned' );

my $state_source = read_file( File::Spec->catfile( $source_dir, 'state.c' ) );
my $plain_source = read_file( File::Spec->catfile( $source_dir, 'plain_ui.c' ) );
my $newt_source = read_file( File::Spec->catfile( $source_dir, 'newt_ui.c' ) );
my $shell_launcher = read_file( File::Spec->catfile( $source_dir, 'shell.c' ) );
my $header = read_file( File::Spec->catfile( $source_dir, 'console.h' ) );
my $console_source = join "\n", $state_source, $plain_source, $newt_source,
  $shell_launcher, $header;

my ($view_builder) = $state_source =~
  /(void xcat_build_status_view.*?)(?=\nbool xcat_status_view_changed)/s;
ok( defined($view_builder), 'console builds one shared main status view' );
foreach my $field (qw/STATE STAGE_TIME ACTIVITY NODE SERIAL INTERFACE LINK METHOD ADDRESS MAC XCAT_SERVER XCAT_STATUS ACTION DETAIL_ONE DETAIL_TWO/) {
    like( $view_builder, qr/STATUS_FIELD_\Q$field\E/,
        "shared view defines the $field field" );
}

my ($plain_renderer) = $plain_source =~
  /(static void print_plain\(.*?)(?=\nstatic bool read_plain_command)/s;
ok( defined($plain_renderer), 'console defines the plain renderer' );
like( $plain_renderer,
    qr/const struct status_view \*view.*?STATUS_FIELD_COUNT/s,
    'plain output consumes the shared view' );
unlike( $plain_renderer, qr/struct console_state|state->/,
    'plain output cannot select fields from raw state' );

my ($newt_renderer) = $newt_source =~
  /(static void update_form\(.*?)(?=\nstatic const char help_text)/s;
ok( defined($newt_renderer), 'console defines the Newt renderer' );
like( $newt_renderer,
    qr/const struct status_view \*view.*?STATUS_FIELD_COUNT/s,
    'Newt output consumes the shared view' );
unlike( $newt_renderer, qr/struct console_state|state->/,
    'Newt output cannot select fields from raw state' );

my ($view_change_detection) = $state_source =~
  /(bool xcat_status_view_changed.*?)(?=\nvoid xcat_format_diagnostics)/s;
ok( defined($view_change_detection), 'console compares shared status views' );
like( $view_change_detection,
    qr/STATUS_FIELD_STATE.*?STATUS_FIELD_COUNT.*?fields\[field\]\.value/s,
    'every shared field participates in change detection' );
like( $view_change_detection, qr/field == STATUS_FIELD_STAGE_TIME/,
    'the one-second stage timer remains the only cadence exception' );

my ($help_source) = $newt_source =~
  /(static const char help_text\[\].*?)(?=\nstatic void show_help)/s;
ok( defined($help_source), 'console defines its interface help text' );
like( $help_source, qr/Screen fields/, 'help explains the visible fields' );
like( $help_source,
    qr/xCAT contact.*Not configured.*Action received.*Failed/s,
    'help explains each xCAT contact result' );
like( $help_source, qr/Method is DHCP, Static, or.*SLAAC\/DHCPv6/s,
    'help explains the network-method labels' );
like( $help_source, qr/F3.*follows new entries.*End to resume/s,
    'help explains log following' );
like( $help_source, qr/F12.*root maintenance shell/s,
    'help explains the maintenance shell' );
foreach my $state (qw/STARTING IDLE WAITING_FOR_LINK CONFIGURING_NETWORK CONTACTING_XCAT ACTION_RECEIVED RUNNING READY DEGRADED FAILED/) {
    like( $help_source, qr/\b\Q$state\E\b/, "help explains the $state state" );
}
unlike( $help_source, qr/xcat\.(?:console|debug-shell)|updates automatically/,
    'interface help omits boot overrides and redundant refresh advice' );

my ($diagnostics_source) = $state_source =~
  /(void xcat_format_diagnostics.*)\z/s;
ok( defined($diagnostics_source), 'console defines the diagnostics view' );
like( $diagnostics_source, qr/Identity\\n\\n.*System\\n\\n.*Management network\\n\\n.*xCAT\\n\\n.*Action\\n\\n.*Runtime\\n\\n/s,
    'diagnostics separates each section with an empty line' );
unlike( $diagnostics_source, qr/Last contact|Uptime|network_age|registration_age|action_age/,
    'diagnostics omits component timers' );
my ($diagnostics_ui) = $newt_source =~
  /(static void show_diagnostics.*?)(?=\nstatic bool journal_value)/s;
ok( defined($diagnostics_ui), 'console defines the diagnostics window' );
unlike( $diagnostics_ui, qr/newtFormSetTimer/,
    'diagnostics does not refresh while the operator scrolls' );
like( $diagnostics_ui,
    qr/newtTextboxSetText\(text_box, text\);\s+newtRefresh\(\);\s+while/s,
    'diagnostics loads one stable snapshot before handling input' );

my ($header_source) = $newt_source =~
  /(static void draw_header.*?)(?=\nstatic void update_form)/s;
ok( defined($header_source), 'console defines the status header' );
like( $console_source, qr/state->local_hostname/,
    'header uses the local hostname before node assignment' );
like( $console_source, qr/state->serial/,
    'header shows the firmware serial when available' );
unlike( $header_source, qr/state->architecture/,
    'header leaves architecture in diagnostics' );
like( $header_source, qr/xcat_header_context_columns\(columns\)/,
    'header clamps its context to the available terminal width' );

my ($logs_source) = $newt_source =~
  /(static void show_logs.*?)(?=\nstatic void show_maintenance_shell)/s;
ok( defined($logs_source), 'console defines the log view' );
like( $logs_source, qr/newtListbox.*NEWT_FLAG_SCROLL/s,
    'log view provides a scrollable list' );
like( $logs_source, qr/bool follow = true/,
    'log view starts in follow mode' );
like( $logs_source,
    qr/NEWT_KEY_UP.*?NEWT_KEY_PGUP.*?NEWT_KEY_HOME.*?follow = false/s,
    'upward navigation pauses log following' );
like( $logs_source,
    qr/NEWT_KEY_DOWN.*?NEWT_KEY_PGDN.*?follow = selected == item_count/s,
    'downward navigation resumes following only at the tail' );
like( $logs_source, qr/NEWT_KEY_END.*?follow = true/s,
    'End resumes log following' );

my ($shell_source) = $newt_source =~
  /(static void show_maintenance_shell.*?)(?=\nint xcat_run_newt)/s;
ok( defined($shell_source), 'console defines the maintenance-shell action' );
like( $shell_source, qr/newtWinChoice.*Open.*Cancel/s,
    'maintenance shell requires confirmation' );
like( $shell_source, qr/xcat_run_maintenance_shell\(\)/,
    'Newt uses the common maintenance-shell launcher' );
like( $shell_source, qr/newtResume\(\).*newtResizeScreen\(1\)/s,
    'Newt restores and repaints its saved screen after the shell' );
unlike( $shell_source, qr/newtCls\(\)/,
    'maintenance-shell return preserves the window frame' );
like( $shell_launcher,
    qr{execl\("/usr/libexec/xcat/genesis-maintenance-shell"},
    'maintenance shell uses the packaged executable' );
like( $shell_launcher, qr/FD_CLOEXEC.*exec_error_size/s,
    'maintenance shell distinguishes launch failure from shell exit' );
unlike( $shell_launcher, qr/WEXITSTATUS/,
    'maintenance shell accepts any later shell exit status' );

my ($plain_runner) = $plain_source =~
  /(int xcat_run_plain.*)\z/s;
ok( defined($plain_runner), 'console defines the plain-mode loop' );
like( $plain_runner, qr/Type shell and press Enter for maintenance/,
    'plain mode advertises its maintenance command' );
like( $plain_runner,
    qr/read_plain_command.*?strcmp\(command, "shell"\).*?open_plain_maintenance_shell/s,
    'plain mode accepts the shell command' );

my ($plain_shell) = $plain_source =~
  /(static void open_plain_maintenance_shell.*?)(?=\nint xcat_run_plain)/s;
ok( defined($plain_shell), 'console defines plain shell confirmation' );
like( $plain_shell, qr/Open a root maintenance shell\? \[y\/N\]/,
    'plain mode confirms root shell access' );
like( $plain_shell, qr/xcat_run_maintenance_shell\(\)/,
    'plain mode uses the common maintenance-shell launcher' );

done_testing();
