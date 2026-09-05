#!/usr/bin/env perl
# Drive verify-genesis-payload against payload trees that reproduce the three holes the
# released legacy Genesis image shipped with.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $verifier = repo_path('xCAT-genesis-builder/verify-genesis-payload');
plan skip_all => 'verify-genesis-payload not found' unless -f $verifier;
plan tests => 18;

my $tmpdir = tempdir(CLEANUP => 1);
my $module_seq = 0;

# A complete payload: OpenSSH 9.9 sshd plus its session helper, tmux plus a UTF-8 locale.
my $good = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1, dhclient => 1, mktemp => 1);
my ($rc, $err) = run($good, 'usr/sbin/dhclient');
is($rc, 0, 'a complete payload passes') or diag($err);

# doxcat calls dhclient with ISC flags. The released el9 image carried dhclient.conf and
# dhclient-script but no dhclient, so Genesis never acquired an address.
my $nodhcp = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1, dhclient => 0, mktemp => 1);
($rc, $err) = run($nodhcp, 'usr/sbin/dhclient');
isnt($rc, 0, 'a payload without dhclient fails');
like($err, qr{usr/sbin/dhclient}, 'the missing dhclient is named');

# sshd 9.9 execs /usr/libexec/openssh/sshd-session for every connection.
my $nohelper = build_payload(sshd_execs_session => 1, session_helper => 0, tmux => 1, locale => 1, dhclient => 1, mktemp => 1);
($rc, $err) = run($nohelper, 'usr/sbin/dhclient');
isnt($rc, 0, 'a payload whose sshd execs sshd-session but does not ship it fails');
like($err, qr{sshd-session}, 'the missing sshd-session is named');

# OpenSSH 8 does not use the helper, so el8 must still pass without it.
my $openssh8 = build_payload(sshd_execs_session => 0, session_helper => 0, tmux => 1, locale => 1, dhclient => 1, mktemp => 1);
($rc, $err) = run($openssh8, 'usr/sbin/dhclient');
is($rc, 0, 'an OpenSSH 8 payload passes without sshd-session') or diag($err);

# tmux without a UTF-8 locale is what stopped doxcat from ever running.
my $nolocale = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 0, dhclient => 1, mktemp => 1);
($rc, $err) = run($nolocale, 'usr/sbin/dhclient');
isnt($rc, 0, 'a payload with tmux and no UTF-8 locale fails');
like($err, qr{C\.utf8}, 'the missing locale is named');

# getdestiny makes its request file with mktemp. Without it the node never reports its destiny,
# so xcatd never sets nodelist.status and the node stays at powering-on.
my $nomktemp = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1, dhclient => 1, mktemp => 0);
($rc, $err) = run($nomktemp, 'usr/sbin/dhclient');
isnt($rc, 0, 'a payload without mktemp fails');
like($err, qr{usr/bin/mktemp}, 'the missing mktemp is named');

# dracut_install reports a missing binary and returns, so every name the dracut module
# installs has to be checked against the payload. The el10 image shipped with no openssl and
# getcert waited on it for the life of the node.
my $module = write_module_setup([qw(openssl wget tar)]);
my $full = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1,
    dhclient => 1, mktemp => 1, commands => [qw(openssl wget tar)]);
($rc, $err) = run_with_commands($module, $full);
is($rc, 0, 'a payload carrying every command the module names passes') or diag($err);

my $noopenssl = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1,
    dhclient => 1, mktemp => 1, commands => [qw(wget tar)]);
($rc, $err) = run_with_commands($module, $noopenssl);
isnt($rc, 0, 'a payload without openssl fails');
like($err, qr/openssl/, 'the missing openssl is named');

# The DHCP client is release-dependent, so the module installs it inside a conditional. Those
# names are not the contract; the spec passes the one it wants as a required path.
my $conditional = write_module_setup(['wget'], ['dhclient']);
my $nodhclient = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1,
    dhclient => 0, mktemp => 1, commands => ['wget']);
($rc, $err) = run_with_commands($conditional, $nodhclient);
is($rc, 0, 'a name installed under a condition is not required') or diag($err);

# A module the verifier cannot read names for covers nothing, so say so instead of passing.
my $unparsable = "$tmpdir/module-setup-unparsable.sh";
write_text($unparsable, "#!/bin/bash\nsetup() {\n    dracut_install wget\n}\n");
($rc, $err) = run_with_commands($unparsable, $full);
is($rc, 2, 'a module the verifier finds no command names in is a usage error');
like($err, qr/command name/, 'the empty command list is named');

($rc, $err) = run_with_commands("$tmpdir/no-such-module", $full);
is($rc, 2, 'a module file that cannot be read is a usage error');

($rc, $err) = run("$tmpdir/does-not-exist");
is($rc >> 0, 2, 'a missing payload directory is a usage error');

#---
# build_payload: make a payload tree with the pieces the verifier reasons about.
#---
sub build_payload {
    my (%opt) = @_;
    my $root = tempdir(DIR => $tmpdir, CLEANUP => 1);
    make_path("$root/usr/sbin", "$root/usr/bin", "$root/usr/libexec/openssh");
    write_text("$root/usr/sbin/sshd",
        $opt{sshd_execs_session}
            ? "OpenSSH_9.9p1\n/usr/libexec/openssh/sshd-session\n"
            : "OpenSSH_8.0p1\n");
    write_text("$root/usr/libexec/openssh/sshd-session", "helper\n") if $opt{session_helper};
    write_text("$root/usr/bin/tmux", "tmux\n") if $opt{tmux};
    if ($opt{locale}) {
        make_path("$root/usr/lib/locale/C.utf8");
        write_text("$root/usr/lib/locale/C.utf8/LC_CTYPE", "ctype\n");
    }
    write_text("$root/usr/sbin/dhclient", "dhclient\n") if $opt{dhclient};
    write_text("$root/usr/bin/mktemp", "mktemp\n") if $opt{mktemp};
    write_text("$root/usr/bin/$_", "$_\n") for @{ $opt{commands} || [] };
    return $root;
}

#---
# run: run the verifier and return its exit status and stderr.
#---
sub run {
    my ($root, @required) = @_;
    my $errfile = "$tmpdir/err.$$";
    my $cmd = join ' ', map { "'$_'" } ($verifier, $root, @required);
    system("/bin/bash $cmd >/dev/null 2>$errfile");
    my $status = $? >> 8;
    my $err = -f $errfile ? read_text($errfile) : '';
    unlink $errfile;
    return ($status, $err);
}

#---
# write_module_setup: a dracut module whose install() names commands at the top level, and
# optionally more inside a conditional.
#---
sub write_module_setup {
    my ($top, $conditional) = @_;
    my $path = "$tmpdir/module-setup." . ++$module_seq . ".sh";
    my $text = "#!/bin/bash\n\ninstall() {\n";
    $text .= "    dracut_install " . join(' ', @$top) . " # a trailing comment\n";
    $text .= "    dracut_install /usr/bin/awk /etc/services\n";
    if ($conditional) {
        $text .= "    if command -v " . $conditional->[0] . " >/dev/null 2>&1; then\n";
        $text .= "        dracut_install " . join(' ', @$conditional) . "\n";
        $text .= "    fi\n";
    }
    $text .= "}\n";
    write_text($path, $text);
    return $path;
}

#---
# run_with_commands: run the verifier with the command list read back from a dracut module.
#---
sub run_with_commands {
    my ($module, $root) = @_;
    my $errfile = "$tmpdir/err.commands.$$";
    my $cmd = join ' ', map { "'$_'" } ($verifier, '--commands-from', $module, $root);
    system("/bin/bash $cmd >/dev/null 2>$errfile");
    my $status = $? >> 8;
    my $err = -f $errfile ? read_text($errfile) : '';
    unlink $errfile;
    return ($status, $err);
}
