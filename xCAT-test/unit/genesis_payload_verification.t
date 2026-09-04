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
plan tests => 9;

my $tmpdir = tempdir(CLEANUP => 1);

# A complete payload: OpenSSH 9.9 sshd plus its session helper, tmux plus a UTF-8 locale.
my $good = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1, dhclient => 1);
my ($rc, $err) = run($good, 'usr/sbin/dhclient');
is($rc, 0, 'a complete payload passes') or diag($err);

# doxcat calls dhclient with ISC flags. The released el9 image carried dhclient.conf and
# dhclient-script but no dhclient, so Genesis never acquired an address.
my $nodhcp = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 1, dhclient => 0);
($rc, $err) = run($nodhcp, 'usr/sbin/dhclient');
isnt($rc, 0, 'a payload without dhclient fails');
like($err, qr{usr/sbin/dhclient}, 'the missing dhclient is named');

# sshd 9.9 execs /usr/libexec/openssh/sshd-session for every connection.
my $nohelper = build_payload(sshd_execs_session => 1, session_helper => 0, tmux => 1, locale => 1, dhclient => 1);
($rc, $err) = run($nohelper, 'usr/sbin/dhclient');
isnt($rc, 0, 'a payload whose sshd execs sshd-session but does not ship it fails');
like($err, qr{sshd-session}, 'the missing sshd-session is named');

# OpenSSH 8 does not use the helper, so el8 must still pass without it.
my $openssh8 = build_payload(sshd_execs_session => 0, session_helper => 0, tmux => 1, locale => 1, dhclient => 1);
($rc, $err) = run($openssh8, 'usr/sbin/dhclient');
is($rc, 0, 'an OpenSSH 8 payload passes without sshd-session') or diag($err);

# tmux without a UTF-8 locale is what stopped doxcat from ever running.
my $nolocale = build_payload(sshd_execs_session => 1, session_helper => 1, tmux => 1, locale => 0, dhclient => 1);
($rc, $err) = run($nolocale, 'usr/sbin/dhclient');
isnt($rc, 0, 'a payload with tmux and no UTF-8 locale fails');
like($err, qr{C\.utf8}, 'the missing locale is named');

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
