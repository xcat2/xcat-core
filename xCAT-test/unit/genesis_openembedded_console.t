#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

# The Newt interface of the Genesis console. newt_ui.c needs libnewt and a terminal, so no
# test builds or drives it, and these checks read its source. The plain console, the shared
# status view, the diagnostics text and the shell launcher are built and run by
# xCAT-test/bats/genesis_openembedded_console.bats.

my $SRC = 'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console/src';
my $newt_source = slurp_repo_file("$SRC/newt_ui.c");

my ($newt_renderer) = $newt_source =~
  /(static void update_form\(.*?)(?=\nstatic const char help_text)/s;
ok( defined($newt_renderer), 'console defines the Newt renderer' );
like( $newt_renderer,
    qr/const struct status_view \*view.*?STATUS_FIELD_COUNT/s,
    'Newt output consumes the shared view' );
unlike( $newt_renderer, qr/struct console_state|state->/,
    'Newt output cannot select fields from raw state' );

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
like( $header_source, qr/view->identity/,
    'the header draws the shared view identity' );
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

# Checks over every console source file.
my $console_source = join "\n", map { slurp_repo_file("$SRC/$_") }
  qw(console.h main.c newt_ui.c plain_ui.c shell.c state.c support.c);
unlike( $console_source, qr/genesis-debug-shell|XCAT_ON_DEMAND_SHELL/,
    'status console only uses the common maintenance-shell launcher' );
unlike( $console_source, qr/\b(?:system|popen)\s*\(/,
    'status console avoids command-string execution' );
like( $console_source, qr/LOG_LINE_COUNT = 128/,
    'log view keeps a bounded serial-friendly history' );

like( $newt_source, qr/newtDrawRootText\(1, 0, "xCAT Genesis"\)/,
    'status console keeps the product name in the header' );
like( $newt_source,
    qr/F1 Help   F2 Diagnostics   F3 Logs   F12 Shell/,
    'status console keeps useful shortcuts in the footer' );
unlike( $newt_source, qr/NEWT_KEY_F5|F5 Refresh|Ctrl-L Redraw/,
    'status console omits redundant redraw shortcuts' );
like( $newt_source, qr/newtFormSetTimer\(screen\.form, 1000\)/,
    'status console updates timers once per second' );
like( $newt_source, qr/newtCenteredWindow\(72, 17, "Genesis status"\)/,
    'main status removes unused top and bottom rows' );
like( $newt_source, qr/newtCenteredWindow\(72, 19, "Genesis diagnostics"\)/,
    'F2 opens diagnostics' );
like( $newt_source, qr/update_form\(&screen, &(?:state|view), changed\)/,
    'stable status updates only the timers' );
like( $newt_source, qr/if \(\+\+redraw >= 30\)/,
    'serial console limits periodic full redraws' );
like( $newt_source, qr/newtFormAddHotKey\(screen\.form, NEWT_KEY_F3\)/,
    'F3 opens recent Genesis logs' );
like( $newt_source, qr/sd_journal_open\(&journal,/,
    'log view reads the journal without a subprocess' );
like( $newt_source,
    qr/newtListbox\(1, 1, LOG_VIEW_HEIGHT, NEWT_FLAG_SCROLL\).*?newtFormSetTimer\(form, 1000\)/s,
    'log view is scrollable and refreshes once per second' );
like( $newt_source,
    qr/newtFormAddHotKey\(screen\.form, NEWT_KEY_F12\).*?show_maintenance_shell\(\)/s,
    'F12 opens the maintenance-shell confirmation' );
like( $newt_source,
    qr/newtWinChoice\(.*?Open a root maintenance shell\?/s,
    'the Newt confirmation names root shell access' );

done_testing();
