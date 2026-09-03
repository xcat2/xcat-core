#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use Test::More;

# When Subiquity finishes it reboots, and unless the node has been flipped to local-disk boot it
# PXEs straight back into the installer. The in-target post-script does that through
# updateflag.awk, which needs gawk's |& coprocess -- Ubuntu's /usr/bin/awk is mawk, so the flip
# silently failed and the node reinstalled forever. The template now does the exchange from the
# live installer over bash's built-in /dev/tcp.
#
# Run that command against a stand-in for xcatd and check the exchange, rather than reading the
# template text.

my $tmpl = "$FindBin::Bin/../../xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl";
plan skip_all => 'compute.subiquity.tmpl not found' unless -r $tmpl;

# The install monitor listens on site.xcatiport, and on any management node xcatd is already
# there -- so binding it here made the whole file skip_all exactly where the suite runs. Take an
# ephemeral port from the kernel instead and hand it to the template as the site value.
my $probe = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp',
    Listen => 5, ReuseAddr => 1)
  or BAIL_OUT("could not take an ephemeral port on the loopback interface: $!");
my $XCATD_PORT = $probe->sockport;
close $probe;    # each case below opens its own listener, or none at all

open(my $fh, '<', $tmpl) or die "open $tmpl: $!";
my $source = do { local $/; <$fh> };
close $fh;

# The boot flip is the late-command that talks to the install-monitor port.
my ($command) = $source =~ m{- \['bash', '-c', '(.*?/dev/tcp/.*?)'\]};
BAIL_OUT('no late-command in the template performs the boot flip over /dev/tcp') unless $command;

# Run the command with the install server pointed at our stand-in, and its log inside a scratch
# tree. site.xcatiport is substituted the way the template renderer substitutes it. Everything
# else is the template's own text.
sub run_flip {
    my (%opt) = @_;
    my $root = tempdir(CLEANUP => 1);
    mkdir "$root/target"; mkdir "$root/target/var"; mkdir "$root/target/var/log";
    mkdir "$root/target/var/log/xcat";

    my $site_port = exists $opt{site_port} ? $opt{site_port} : $XCATD_PORT;

    my $script = $command;
    $script =~ s/\#XCATVAR:XCATMASTER\#/127.0.0.1/;
    $script =~ s/\#TABLEBLANKOKAY:site:key=xcatiport:value\#/$site_port/;
    $script =~ s{/target/var/log/xcat/xcat\.log}{$root/target/var/log/xcat/xcat.log};
    $script =~ s/sleep 5/sleep 1/;    # shorten the retry pause, keep the retry

    my $pid;
    if ($opt{listen}) {
        $pid = fork();
        die "fork: $!" unless defined $pid;
        if (!$pid) {    # the stand-in xcatd
            sleep $opt{delay} if $opt{delay};    # appear only after the first attempts fail
            my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $XCATD_PORT,
                Proto => 'tcp', Listen => 5, ReuseAddr => 1) or exit 1;
            open my $seen, '>', "$root/received" or exit 1;
            $seen->autoflush(1);
            for (1 .. $opt{listen}) {
                my $c = $srv->accept() or last;
                $c->autoflush(1);
                if ($opt{mute}) { sleep 600; close $c; next }  # accept and hold, never answer
                # xcatd greets with "ready", then answers every request with "done".
                print {$c} ($opt{greeting} || "ready\n");
                my $line = <$c>;
                print {$seen} $line if defined $line;
                print {$c} ($opt{ack} || "done\n") unless $opt{no_ack};
                close $c;
            }
            close $seen;
            close $srv;
            exit 0;
        }
    }

    # The installer would hang here if the exchange ever blocked, so bound it.
    # the no-listener case prints "Connection refused" by design
    my $cap = $opt{cap} || 25;
    my $rc = system("timeout $cap bash -c \Q$script\E 2>/dev/null");
    my $timed_out = (($rc >> 8) == 124);
    if ($pid) { kill 'TERM', $pid; waitpid($pid, 0) }

    my $received = '';
    if (open my $rh, '<', "$root/received") { local $/; $received = <$rh> || ''; close $rh }

    my $log = '';
    if (open my $lh, '<', "$root/target/var/log/xcat/xcat.log") { local $/; $log = <$lh> || ''; close $lh }
    return { rc => $rc, timed_out => $timed_out, log => $log, received => $received };
}

# --- xcatd answers: the node is flipped ------------------------------------
{
    my $r = run_flip(listen => 1);
    is($r->{rc}, 0, 'the boot flip exits cleanly so the install is not failed by it');
    is($r->{log}, '', 'nothing is written to the install log when the flip succeeds');
    is($r->{received}, "next\n",
        'the node sends the token that makes xcatd run "nodeset <node> next"');
    ok(!$r->{timed_out}, 'the exchange completes rather than hanging the late-command');
}

# --- the port comes from site.xcatiport ------------------------------------
# The case above already proves it: the stand-in listens on an ephemeral port, not on 3002, and
# the exchange only completes because the template asks site for the port. What is left is the
# default, for a site table that does not carry the key.
{
    my $r = run_flip(site_port => '', listen => 0, cap => 90);
    like($r->{log}, qr/:3002\b/,
        'an unset site.xcatiport falls back to the port xcatd listens on by default');
}

# --- xcatd never answers: the failure is recorded, not swallowed -----------
{
    my $r = run_flip(listen => 0);
    is($r->{rc}, 0, 'a failed flip still exits 0 rather than aborting the install');
    like($r->{log}, qr/FAILED to flip/,
        'a failed flip is recorded in the install log instead of PXE-looping silently');
    like($r->{log}, qr/127\.0\.0\.1:\Q$XCATD_PORT\E\b/,
        'the log names the install server and port that could not be reached');
}

# --- something else is listening on the port -------------------------------
# Only xcatd's install monitor answers "nodeset <node> next". A service that accepts the
# connection and talks its own protocol must not be counted as a flipped node.
{
    my $r = run_flip(listen => 5, greeting => "220 smtp\n");
    like($r->{log}, qr/FAILED to flip/,
        'a peer that does not greet with "ready" is not treated as the install monitor');
    is($r->{received}, '',
        'and the flip token is never sent to it');
}

# --- the peer greets but does not acknowledge the request ------------------
{
    my $r = run_flip(listen => 5, ack => "?\n");
    like($r->{log}, qr/FAILED to flip/,
        'a reply other than "done" is not counted as an accepted request');
}

# --- xcatd accepts but never acknowledges ----------------------------------
{
    my $r = run_flip(listen => 5, no_ack => 1);
    like($r->{log}, qr/FAILED to flip/,
        'a connection without an acknowledgement counts as a failure, not a success');
}

# --- a monitor that accepts and never answers must not hang the install ----
# The late-command runs inside Subiquity: a bare read on a socket that is open but silent blocks
# forever and the install never finishes. #7759 fixes the monitor dying; this bounds the wait.
{
    # Five attempts, each bounded by two 10s reads plus the retry pause: ~2 minutes worst case.
    my $r = run_flip(listen => 1, mute => 1, cap => 200);
    ok(!$r->{timed_out},
        'a monitor that accepts but never replies does not hang the late-command');
    like($r->{log}, qr/FAILED to flip/,
        'it is recorded as a failed flip rather than waiting indefinitely');
}

# --- the command retries rather than giving up on the first refusal --------
{
    # Answer only on a later connection: the flip must still succeed.
    my $r = run_flip(listen => 1, delay => 2);
    is($r->{log}, '', 'the flip retries until the install monitor answers');
    is($r->{received}, "next\n", 'and the token still reaches it on the later attempt');
}

done_testing();
