#!/usr/bin/env perl
use strict;
use warnings;

# Keep modules out of an installed /opt/xcat, so the checkout is what loads.
BEGIN { $ENV{XCATROOT} = '/nonexistent/xcatroot' }

use Capture::Tiny qw(capture_stdout);
use File::Slurper qw(read_lines);
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";
use Test::More;

require probe_utils;
like($INC{'probe_utils.pm'}, qr/\Q$FindBin::Bin\E/, 'probe_utils comes from this checkout');

# The case ran the probe through grep. ausearch is not involved here: grep kept
# the lines that name SELinux and discarded every other checkpoint, so the one
# CI failure reported an empty output and said nothing about the probe. The
# second check, on the word FAIL, then had nothing to read.
my %case;
my $name;
foreach my $line (read_lines("$FindBin::Bin/../autotest/testcase/probe/xcatmn")) {
    $name = $1 if ($line =~ /^start:(\S+)/);
    push @{ $case{$name}{cmd} },   $1 if ($line =~ /^cmd:(.+)/);
    push @{ $case{$name}{check} }, $1 if ($line =~ /^check:(.+)/);
}
my $probe = $case{xcatprobe_xcatmn_selinux};
ok($probe, 'the testcase file declares xcatprobe_xcatmn_selinux');
my @cmds   = @{ $probe->{cmd}   || [] };
my @checks = @{ $probe->{check} || [] };
ok(scalar(@cmds) >= 1,   "the case runs @{[scalar @cmds]} commands");
ok(scalar(@checks) >= 1, "the case makes @{[scalar @checks]} checks");

foreach my $cmd (@cmds) {
    unlike($cmd, qr/\|/,
        "the case keeps the whole output of '$cmd', instead of filtering it");
}

my @patterns = map { /^output\s*[=!]~\s*(\S.*)/ ? $1 : () } @checks;
my @positive = map { /^output\s*=~\s*(\S.*)/ ? $1 : () } @checks;
ok(scalar(@positive) >= 1,
    "the case asserts @{[scalar @positive]} patterns that the probe output must hold");
foreach my $pattern (@patterns) {
    like($pattern, qr/SELinux/,
        "the pattern '$pattern' names the SELinux checkpoint, so another checkpoint cannot satisfy it");
}

# The subcommand marks each checkpoint through send_msg, and xcatprobe rewrites
# that mark as a right hand [ OK ] or [FAIL]. Take the subcommand marks by
# calling send_msg, so a change of format fails here.
my $checkpoint = 'Checking SELinux policy for xCAT...';
my %mark;
foreach my $tag (qw(o f)) {
    $mark{$tag} = capture_stdout { probe_utils->send_msg('stdout', $tag, $checkpoint) };
    chomp($mark{$tag});
}
isnt($mark{o}, $mark{f},
    "send_msg marks an ok checkpoint '$mark{o}' apart from a failed one '$mark{f}'");
like($mark{o}, qr/\QSELinux\E/, 'the ok mark carries the checkpoint text');

my %rendered = (
    ok     => $checkpoint . (' ' x 39) . '[ OK ]',
    failed => $checkpoint . (' ' x 39) . '[FAIL]',
);
foreach my $pattern (@positive) {
    like($rendered{ok}, qr/$pattern/, "a passing SELinux checkpoint matches '$pattern'");
    unlike($rendered{failed}, qr/$pattern/,
        "a failing SELinux checkpoint does not match '$pattern'");
}
foreach my $pattern (map { /^output\s*!~\s*(\S.*)/ ? $1 : () } @checks) {
    like($rendered{failed}, qr/$pattern/,
        "a failing SELinux checkpoint matches the excluded pattern '$pattern'");
    unlike($rendered{ok}, qr/$pattern/,
        "a passing SELinux checkpoint does not match the excluded pattern '$pattern'");
}

done_testing();
