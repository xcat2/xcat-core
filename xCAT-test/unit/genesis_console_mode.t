#!/usr/bin/env perl
# Drive xcat_console_mode() out of the Genesis dracut cmdline hook.
#
# The hook cannot be sourced: it mounts filesystems, starts udev and ends in an endless
# loop. Extract the one function and run it with the terminal multiplexer shadowed.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my %HOOK = (
    el     => { path => 'xCAT-genesis-builder/dracut_105/el/xcat-cmdline.sh',     mux => 'tmux' },
    ubuntu => { path => 'xCAT-genesis-builder/dracut_105/ubuntu/xcat-cmdline.sh', mux => 'screen' },
);

plan tests => 5 * scalar(keys %HOOK) + 2;

my $tmpdir = tempdir(CLEANUP => 1);

# The failure this captures: with no UTF-8 locale in the image, tmux exits and the old
# unconditional `while :; do tmux ...; done` never reached doxcat.
my $el = read_text(repo_path($HOOK{el}{path}));
ok($el !~ qr/^while :; do tmux attach-session/m,
    'el: no unguarded tmux loop is left at column 0');
ok($el =~ qr/^export LC_ALL=C\.UTF-8$/m,
    'el: the hook exports a UTF-8 locale so tmux can start');

foreach my $family (sort keys %HOOK) {
    my $hook = repo_path($HOOK{$family}{path});
    my $mux  = $HOOK{$family}{mux};

    my $body = extract_function($hook, 'xcat_console_mode', $family);

    is(run_mode($body, $mux, 0), 'direct',
        "$family: xcat_console_mode reports direct when $mux cannot start a session");
    is(run_mode($body, $mux, 1), $mux,
        "$family: xcat_console_mode reports $mux when $mux can start a session");

    my $text = read_text($hook);
    ok($text =~ qr/^XCAT_CONSOLE_MODE="\$\(xcat_console_mode\)"$/m,
        "$family: the hook resolves the console mode once");
    my $guard = qq{if [ "\$XCAT_CONSOLE_MODE" = "$mux" ]; then};
    ok(index($text, $guard) >= 0,
        "$family: the doxcat loop is guarded by the console mode");
    ok($text =~ qr/\Qelse\E\n\s+while :; do doxcat; sleep 5; done\n\Qfi\E/,
        "$family: doxcat runs directly when $mux is not usable");
}

#---
# extract_function: lift one shell function out of a script that cannot be sourced.
# Bails out when the function stops being extractable, so a rename fails loudly instead of
# leaving the test asserting nothing.
#---
sub extract_function {
    my ($path, $name, $label) = @_;
    my $text = read_text($path);
    my ($body) = $text =~ /^($name\(\)\s*\{.*?^\})$/ms;
    BAIL_OUT("$label: $name() not found in $path") unless defined $body;
    return $body;
}

#---
# run_mode: run the extracted function with the multiplexer shadowed by a stub that either
# starts a session or refuses, the way tmux refuses without a UTF-8 locale.
#---
sub run_mode {
    my ($body, $mux, $mux_works) = @_;
    my $dir = tempdir(DIR => $tmpdir, CLEANUP => 1);
    my $bin = "$dir/bin";
    make_path($bin);
    write_text("$bin/$mux", $mux_works
        ? "#!/bin/sh\nexit 0\n"
        : "#!/bin/sh\necho '$mux: need UTF-8 locale (LC_CTYPE) but have ANSI_X3.4-1968' >&2\nexit 1\n");
    chmod 0755, "$bin/$mux";
    write_text("$dir/probe.sh", "$body\nxcat_console_mode\n");
    my $out = `PATH="$bin:\$PATH" /bin/bash "$dir/probe.sh" 2>/dev/null`;
    chomp $out;
    return $out;
}
