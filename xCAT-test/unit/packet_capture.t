#!/usr/bin/env perl
use strict;
use warnings;

use Config;
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use POSIX qw(WNOHANG);
use Test::More;
use Time::HiRes qw(sleep);

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::PacketCapture;

my $dir = tempdir(CLEANUP => 1);
my $executable = "$dir/tcpdump";
write_text($executable, "#!$Config{perlpath}\n" . <<'CAPTURE');
$SIG{TERM} = 'DEFAULT';
$| = 1;
print "capture is ready\n";
sleep 60;
CAPTURE
chmod 0755, $executable or die "chmod $executable: $!";
local $ENV{TMPDIR} = $dir;

my $capture = xCAT::PacketCapture->start($executable, 'unused');
ok($capture, 'starts a capture without root or a network namespace')
  or BAIL_OUT('capture could not start');
my $pid = $capture->pid;
my $ready;
foreach (1 .. 3000) {
    $ready = read_text($capture->file) eq "capture is ready\n";
    last if $ready;
    sleep 0.01;
}
ok($ready, 'the real child has executed before stop sends TERM');
is($capture->stop, '', 'an untrapped TERM is a successful stop');
is(waitpid($pid, WNOHANG), -1, 'stop has already reaped its child');
is(read_text($capture->file), "capture is ready\n", 'captured output remains readable after stop');
ok(!defined $capture->pid, 'the reaped child is no longer owned');
is($capture->stop, '', 'stopping again succeeds without another child');

done_testing();
