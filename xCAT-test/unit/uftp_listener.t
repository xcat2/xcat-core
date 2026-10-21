#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(realpath);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::SvrUtils;
use xCAT::UFTP;

my $tmp  = realpath(tempdir(CLEANUP => 1));
my $root = "$tmp/install/netboot";
my $fp   = '31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2';
make_path($root, "$tmp/log");

# packimage publishes the archive with its checksum, and the listener sends only such an archive.
sub publish {
    my ($dir, $content, $name) = @_;
    $name ||= 'rootimg.cpio.gz';
    make_path($dir);
    chmod(0755, $dir);
    my ($stage, $error) = xCAT::SvrUtils->rootimg_stage($dir);
    die $error unless $stage;
    write_binary("$stage/$name", $content);
    chmod(0644, "$stage/$name");
    $error = xCAT::SvrUtils->write_rootimg_checksum("$stage/$name") // xCAT::SvrUtils->publish_rootimg("$stage/$name", "$dir/$name");
    die $error if $error;
    return sha256_hex($content);
}

my $config_seq = 0;
sub config {
    my (%override) = @_;
    my %settings = (
        listen_address   => '192.0.2.1',
        image_roots      => $root,
        batch_delay      => 2,
        transfer_timeout => 30,
        job_retention    => 60,
        key_file         => "$tmp/server.key",
        fingerprint_file => "$tmp/server.fingerprint",
        uftp             => "$tmp/uftp",
        log_dir          => "$tmp/log",
        %override,
    );
    my $path = "$tmp/listener." . ++$config_seq . '.conf';
    write_binary($path, join('', map { "$_ = $settings{$_}\n" } sort keys %settings));
    my ($config, $error) = xCAT::UFTP::load_listener_config($path);
    die $error if $error;
    return $config;
}

# The listener starts uftp in a child process, so the test records each start instead.
my (@log, @senders, @signals, $spawn_error);
my $next_pid = 4000;
sub spawn {
    my ($job, $log, @command) = @_;
    return (undef, $spawn_error) if $spawn_error;
    my ($hostlist) = map { /^\@(.+)$/ ? $1 : () } @command;
    sysseek($job->{fh}, 0, 0) or die "sysseek: $!";
    my $bytes = '';
    while (sysread($job->{fh}, my $chunk, 65536)) {
        $bytes .= $chunk;
    }
    push @senders, {
        pid      => ++$next_pid,
        log      => $log,
        command  => \@command,
        hostlist => $hostlist,
        hosts    => scalar(read_binary($hostlist)),
        mode     => (stat($hostlist))[2] & 07777,
        bytes    => $bytes,
    };
    return ($next_pid, undef);
}

sub listener {
    my $config = config(@_);
    @log = @senders = @signals = ();
    return xCAT::UFTP::listener_state($config, workdir => tempdir(DIR => $tmp), spawn => \&spawn,
        log    => sub { push @log, "$_[0]: $_[1]" },
        signal => sub { push @signals, "$_[0] $_[1]" });
}

sub reply {
    my ($state, $peer, $raw, $now) = @_;
    my ($status, $body) = xCAT::UFTP::listener_reply($state, $peer, $raw, $now);
    return { code => $status, body => $body, map { split /=/, $_, 2 } grep { /=/ } split /\n/, $body // '' };
}

sub transfer {
    my ($state, $peer, $digest, $path, $now) = @_;
    return reply($state, $peer, "GET /xcat-uftp/v1/transfer/$digest$path HTTP/1.0\r\nHost: test\r\n\r\n", $now);
}

sub job_state {
    my ($state, $peer, $job, $now) = @_;
    return reply($state, $peer, "GET /xcat-uftp/v1/job/$job HTTP/1.0\r\n\r\n", $now);
}

sub runtime {
    my ($config, $key_fingerprint) = @_;
    return xCAT::UFTP::check_listener_runtime($config, $key_fingerprint || sub { ($fp, undef) });
}

write_binary("$tmp/uftp", ("\0" x 64) . "UFTP version 5.0.4 (xCAT build 1)  Copyright\0");
write_binary("$tmp/uftp4", "\0UFTP version 4.10.2  Copyright\0");
write_binary("$tmp/uftp-stock", "\0UFTP version 5.0.4  Copyright\0");
chmod(0755, "$tmp/uftp", "$tmp/uftp4", "$tmp/uftp-stock");

my $checked = config();
my ($fingerprint, $error) = runtime($checked);
like($error, qr/^UFTP server key \Q$tmp\E\/server\.key is missing; run xcat-uftp-listener --init-key$/,
    'a missing server key is refused with the command that creates it');
write_binary("$tmp/server.key", "fixture private key\n");
chmod(0600, "$tmp/server.key");
($fingerprint, $error) = runtime($checked);
like($error, qr/^Cannot read UFTP server fingerprint .*; run xcat-uftp-listener --init-key$/,
    'a missing fingerprint file is refused');
write_binary("$tmp/server.fingerprint", "$fp\n");
($fingerprint, $error) = runtime($checked);
is($error, undef, 'the runtime check passes');
is($fingerprint, $fp, 'the runtime check returns the fingerprint of the server key');
is(scalar(() = glob("$tmp/log/.write-check*")), 0, 'the write check leaves no file in log_dir');
(undef, $error) = runtime($checked, sub { (undef, "$tmp/uftp_keymgt failed for $tmp/server.key") });
is($error, "$tmp/uftp_keymgt failed for $tmp/server.key", 'a key that uftp_keymgt cannot read is refused');
chmod(0640, "$tmp/server.key");
(undef, $error) = runtime($checked);
like($error, qr/must not be accessible by other users/, 'a private key that others can read is refused');
chmod(0600, "$tmp/server.key");
write_binary("$tmp/server.fingerprint", "00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33\n");
(undef, $error) = runtime($checked);
like($error, qr/server\.fingerprint does not match \Q$tmp\E\/server\.key; run xcat-uftp-listener --init-key$/,
    'a fingerprint file for another key is refused');
write_binary("$tmp/server.fingerprint", "$fp\n");
chmod(0644, "$tmp/uftp");
(undef, $error) = runtime($checked);
like($error, qr/UFTP sender \Q$tmp\E\/uftp is not executable; install the uftp package/, 'a sender that cannot run is refused');
chmod(0755, "$tmp/uftp");
(undef, $error) = runtime(config(uftp => "$tmp/uftp4"));
like($error, qr/UFTP 4\.10\.2; UFTP 5\.x is required/, 'a UFTP 4 sender is refused');
(undef, $error) = runtime(config(uftp => "$tmp/uftp-stock"));
like($error, qr/UFTP 5\.0\.4 without the xCAT fixes/, 'a UFTP 5 sender without the xCAT build mark is refused');
write_binary("$tmp/log-file", "not a directory\n");
(undef, $error) = runtime(config(log_dir => "$tmp/log-file"));
is($error, "Cannot create $tmp/log-file", 'a log_dir that cannot be created is refused');
(undef, $error) = runtime(config(log_dir => "$tmp/new/log"));
ok(!defined($error) && -d "$tmp/new/log", 'a missing log_dir is created');

my $image_a   = "$root/rhels9/x86_64/compute";
my $content_a = "image A generation 1\n" x 200;
my $sum_a     = publish($image_a, $content_a);
my $path_a    = "$image_a/rootimg.cpio.gz";

my $t = 1000;
my $state = listener();
my $first = transfer($state, '192.0.2.10', $sum_a, $path_a, $t);
is($first->{code}, 200, 'a request for a published image is accepted');
like($first->{job}, qr/^[0-9a-f]{16}$/, 'the reply names the transfer job');
is($first->{file}, 'rootimg.cpio.gz', 'the reply names the artifact');
is($first->{size}, length($content_a), 'the reply gives the artifact size');
is($first->{port}, 1044, 'the reply gives the server-owned UDP port');
is($first->{mcast}, '230.4.4.1', 'the reply gives the public multicast address');
is($first->{server_id}, '0xC0000201', 'the reply gives the UFTP server ID');
is($first->{server_ip}, '192.0.2.1', 'the reply gives the sending address');
is($first->{client_ip}, '192.0.2.10', 'the reply gives the address the server saw');
is($first->{start_in}, 2, 'the reply gives the batch delay');
is($first->{timeout}, 30, 'the reply gives the transfer timeout');

my $again = transfer($state, '192.0.2.10', $sum_a, $path_a, $t + 1);
is($again->{job}, $first->{job}, 'a duplicate request joins the same job');
is($again->{start_in}, 1, 'a later request gets the remaining batch delay');
is(transfer($state, '192.0.2.11', $sum_a, "/$path_a", $t + 1)->{code}, 400, 'an unnormalized image path is refused');
is(transfer($state, '192.0.2.11', $sum_a, $path_a, $t + 1)->{job}, $first->{job},
    'a compatible request from another node joins the same job');
my @added = map { /: job \Q$first->{job}\E: added (\S+)$/ ? $1 : () } @log;
is_deeply(\@added, [ '192.0.2.10', '192.0.2.11' ], 'the log adds each node to the job once');
ok((grep { $_ eq "info: job $first->{job}: 192.0.2.10 asked again" } @log), 'the log reports the repeated request');
my $pending = job_state($state, '192.0.2.10', $first->{job}, $t + 1);
is($pending->{state}, 'pending', 'a member sees the job wait for its batch');
is($pending->{start_in}, 1, 'a waiting job reports the remaining batch delay');

xCAT::UFTP::run_jobs($state, $t + 1);
is(scalar(@senders), 0, 'no sender starts before the batch delay ends');
xCAT::UFTP::run_jobs($state, $t + 2);
is(scalar(@senders), 1, 'one sender serves the coalesced requests');
my $sent = $senders[0];
is($sent->{hosts}, "192.0.2.10\n192.0.2.11\n", 'the closed group lists each requesting node once');
is($sent->{mode}, 0600, 'only the listener can read the host list');
is($sent->{bytes}, $content_a, 'the sender gets the published bytes');
is($sent->{log}, "$tmp/log/job-$first->{job}.log", 'the sender writes the log of its job');
is_deeply($sent->{command}, [ "$tmp/uftp", '-I', '192.0.2.1', '-U', '0xC0000201', '-p', '1044', '-M', '230.4.4.1',
        '-P', '230.5.5.x', '-t', '1', '-R', '100000', '-b', '1300', '-N', '98', '-Y', 'aes256-gcm',
        '-h', 'sha256', '-k', "$tmp/server.key", '-H', "\@$sent->{hostlist}", '-x', '2', '-l',
        '-D', 'rootimg.cpio.gz', '/dev/fd/3' ], 'the sender gets only server-owned arguments');
is_deeply([ xCAT::UFTP::sender_pids($state) ], [ $sent->{pid} ], 'the listener tracks the running sender');
is(job_state($state, '192.0.2.10', $first->{job}, $t + 2)->{state}, 'running', 'a member sees the job run');
is(job_state($state, '192.0.2.99', $first->{job}, $t + 2)->{code}, 404, 'a node outside the job cannot query it');
my $late = transfer($state, '192.0.2.12', $sum_a, $path_a, $t + 3);
isnt($late->{job}, $first->{job}, 'a node arriving after the transfer started gets a new job');

xCAT::UFTP::sender_exited($state, $sent->{pid}, 0, $t + 4);
is(job_state($state, '192.0.2.10', $first->{job}, $t + 4)->{state}, 'done', 'a sender that exits with status 0 completes the job');
ok(!-e $sent->{hostlist}, 'the host list is removed when the job finishes');
is(scalar(xCAT::UFTP::sender_pids($state)), 0, 'a finished sender is no longer tracked');
xCAT::UFTP::sender_exited($state, 999999, 0, $t + 4);
is(job_state($state, '192.0.2.10', $first->{job}, $t + 4)->{state}, 'done', 'the exit of an unknown process changes no job');
xCAT::UFTP::run_jobs($state, $t + 63);
is(job_state($state, '192.0.2.10', $first->{job}, $t + 63)->{state}, 'done', 'a finished job stays for job_retention');
xCAT::UFTP::run_jobs($state, $t + 64);
is(job_state($state, '192.0.2.10', $first->{job}, $t + 64)->{code}, 404, 'a finished job is forgotten after job_retention');

$state = listener();
is(reply($state, '192.0.2.10', "GET / HTTP/1.0\r\nX-Image: $path_a\r\nReferer: /xcat-uftp/v1/transfer/$sum_a$path_a\r\n\r\n", $t)->{code},
    404, 'an image path in a header does not select an image');
is(transfer($state, '192.0.2.10', $sum_a, '/etc/passwd', $t)->{code}, 400, 'a request for an unrelated file is refused');
ok((grep { /^warning: 192\.0\.2\.10: rejected request: unsupported image artifact$/ } @log), 'the log reports why a request is refused');
write_binary("$image_a/rootimg.tar.gz", "unrelated archive\n");
chmod(0644, "$image_a/rootimg.tar.gz");
is(transfer($state, '192.0.2.10', sha256_hex("unrelated archive\n"), "$image_a/rootimg.tar.gz", $t)->{code}, 403,
    'an existing image file that was not published is refused');
is(transfer($state, '192.0.2.10', $sum_a, "$root/rhels9/../../../etc/rootimg.cpio.gz", $t)->{code}, 400, 'traversal is refused');
is(reply($state, '192.0.2.10', "GET /xcat-uftp/v1/transfer/$sum_a/install/%2e%2e/rootimg.cpio.gz HTTP/1.0\r\n\r\n", $t)->{code},
    400, 'percent-encoded paths are refused');
is(transfer($state, '192.0.2.10', 'f' x 64, $path_a, $t)->{code}, 403, 'an unpublished digest is refused');
my $outside = "$tmp/outside/compute";
my $sum_out = publish($outside, "outside\n");
symlink($outside, "$root/escape") or die $!;
is(transfer($state, '192.0.2.10', $sum_out, "$root/escape/rootimg.cpio.gz", $t)->{code}, 403,
    'a symbolic link escaping the image roots is refused');
is(reply($state, '192.0.2.10', "GET /xcat-uftp/v1/job/0123456789abcdef HTTP/1.0\r\n\r\n", $t)->{code}, 404,
    'an unknown job is not found');
is(reply($state, '192.0.2.10', 'GET /x HTTP/1.0' . ('y' x 9000) . "\r\n\r\n", $t)->{code}, 413, 'an oversized request is refused');
is(scalar(my @none = xCAT::UFTP::listener_reply($state, '192.0.2.10', "GET / HTTP/1.0\r\n", $t)), 0,
    'an incomplete request gets no reply yet');
is(reply($state, '192.0.2.10', "POST /xcat-uftp/v1/transfer/$sum_a$path_a HTTP/1.0\r\n\r\n", $t)->{code}, 405,
    'a method other than GET is refused');
is(scalar(keys %{ $state->{jobs} }), 0, 'refused requests create no job');

my $odd     = "$root/-H/-x";
my $sum_odd = publish($odd, "option-looking directory\n", 'rootimg.sfs');
is(transfer($state, '192.0.2.10', $sum_odd, "$odd/rootimg.sfs", $t)->{code}, 200, 'an image in an option-looking directory is accepted');
xCAT::UFTP::run_jobs($state, $t + 2);
is_deeply([ @{ $senders[0]{command} }[ -3 .. -1 ] ], [ '-D', 'rootimg.sfs', '/dev/fd/3' ],
    'the sender gets the file name of the image');
is(scalar(grep { index($_, '/-H/-x') >= 0 } @{ $senders[0]{command} }), 0, 'no request text is passed to the sender');
is($senders[0]{bytes}, "option-looking directory\n", 'the option-looking image is sent intact');

my $image_b = "$root/rhels9/x86_64/service";
my $gen1    = "image B generation 1\n" x 100;
my $gen2    = "image B generation 2\n" x 120;
$state = listener();
my $sum_b1  = publish($image_b, $gen1);
my $old_gen = transfer($state, '192.0.2.20', $sum_b1, "$image_b/rootimg.cpio.gz", $t);
my $sum_b2  = publish($image_b, $gen2);
is(transfer($state, '192.0.2.21', $sum_b1, "$image_b/rootimg.cpio.gz", $t)->{code}, 403, 'a repacked generation is no longer offered');
my $new_gen = transfer($state, '192.0.2.21', $sum_b2, "$image_b/rootimg.cpio.gz", $t);
isnt($new_gen->{job}, $old_gen->{job}, 'different image generations never share a job');
xCAT::UFTP::run_jobs($state, $t + 2);
my %by_hosts = map { $_->{hosts} => $_->{bytes} } @senders;
is($by_hosts{"192.0.2.20\n"}, $gen1, 'a queued job still sends the generation it validated');
is($by_hosts{"192.0.2.21\n"}, $gen2, 'the new generation is sent to its own job');

$state = listener();
my $failing = transfer($state, '192.0.2.30', $sum_a, $path_a, $t);
xCAT::UFTP::run_jobs($state, $t + 2);
xCAT::UFTP::sender_exited($state, $senders[-1]{pid}, 7 << 8, $t + 3);
my $failed = job_state($state, '192.0.2.30', $failing->{job}, $t + 3);
is($failed->{state}, 'failed', 'a sender failure fails the job');
is($failed->{reason}, 'uftp exited with status 7', 'the job reports why the sender failed');
ok((grep { $_ eq "error: job $failing->{job}: failed (uftp exited with status 7)" } @log), 'the log reports the failed job');
my $retry = transfer($state, '192.0.2.30', $sum_a, $path_a, $t + 3);
isnt($retry->{job}, $failing->{job}, 'a retry after a failure gets a new job');
xCAT::UFTP::run_jobs($state, $t + 5);
xCAT::UFTP::sender_exited($state, $senders[-1]{pid}, 9, $t + 6);
is(job_state($state, '192.0.2.30', $retry->{job}, $t + 6)->{reason}, 'uftp killed by signal 9', 'the job reports the signal that stopped the sender');
my $unstarted = transfer($state, '192.0.2.31', $sum_a, $path_a, $t + 6);
$spawn_error = 'fork failed: Resource temporarily unavailable';
xCAT::UFTP::run_jobs($state, $t + 8);
undef $spawn_error;
my $unstarted_state = job_state($state, '192.0.2.31', $unstarted->{job}, $t + 8);
is($unstarted_state->{state}, 'failed', 'a sender that cannot start fails the job');
is($unstarted_state->{reason}, 'fork failed: Resource temporarily unavailable', 'the job reports why the sender did not start');
is(scalar(() = glob("$state->{workdir}/*.hosts")), 0, 'no host list stays after the jobs finish');

$state = listener(batch_delay => 0, max_transfers => 1, max_queued_jobs => 2, max_clients_per_job => 2, transfer_timeout => 3);
my $c_image = "$root/rhels9/x86_64/login";
my $sum_c   = publish($c_image, "image C\n");
my $blocking = transfer($state, '192.0.2.40', $sum_a, $path_a, $t);
xCAT::UFTP::run_jobs($state, $t);
is(job_state($state, '192.0.2.40', $blocking->{job}, $t)->{state}, 'running', 'a zero batch delay starts the transfer at once');
my $waiting = transfer($state, '192.0.2.41', $sum_b2, "$image_b/rootimg.cpio.gz", $t);
xCAT::UFTP::run_jobs($state, $t + 1);
is(job_state($state, '192.0.2.41', $waiting->{job}, $t + 1)->{state}, 'pending', 'a second image waits while the transfer limit is reached');
is(transfer($state, '192.0.2.42', $sum_c, "$c_image/rootimg.cpio.gz", $t + 1)->{code}, 503, 'the queue limit refuses further images');
is(transfer($state, '192.0.2.42', $sum_b2, "$image_b/rootimg.cpio.gz", $t + 1)->{job}, $waiting->{job}, 'a node joins the waiting job');
my $full = transfer($state, '192.0.2.43', $sum_b2, "$image_b/rootimg.cpio.gz", $t + 1);
is($full->{code}, 503, 'the per-job client limit refuses further nodes');
is($full->{error}, 'transfer is full', 'the reply says the job is full');
xCAT::UFTP::run_jobs($state, $t + 2);
is_deeply(\@signals, [], 'a sender within its timeout keeps running');
xCAT::UFTP::run_jobs($state, $t + 3);
is_deeply(\@signals, ["TERM $senders[0]{pid}"], 'a sender that exceeds transfer_timeout is asked to stop');
xCAT::UFTP::sender_exited($state, $senders[0]{pid}, 15, $t + 3);
my $timed_out = job_state($state, '192.0.2.40', $blocking->{job}, $t + 3);
is($timed_out->{state}, 'failed', 'a transfer that exceeds its timeout fails');
is($timed_out->{reason}, 'transfer exceeded 3s', 'the timeout is reported');
xCAT::UFTP::run_jobs($state, $t + 3);
is(job_state($state, '192.0.2.41', $waiting->{job}, $t + 3)->{state}, 'running', 'the waiting transfer starts when the slot frees');
is($senders[1]{hosts}, "192.0.2.41\n192.0.2.42\n", 'the waiting transfer sends to the nodes that joined it');
@signals = ();
xCAT::UFTP::run_jobs($state, $t + 6);
xCAT::UFTP::run_jobs($state, $t + 10);
is_deeply(\@signals, ["TERM $senders[1]{pid}"], 'a sender gets the kill grace time after it is asked to stop');
xCAT::UFTP::run_jobs($state, $t + 11);
is_deeply(\@signals, [ "TERM $senders[1]{pid}", "KILL $senders[1]{pid}" ], 'a sender that ignores the request to stop is killed');
xCAT::UFTP::sender_exited($state, $senders[1]{pid}, 9, $t + 11);
is(job_state($state, '192.0.2.41', $waiting->{job}, $t + 11)->{reason}, 'transfer exceeded 3s', 'a killed sender reports the timeout');

$state = listener(batch_delay => 0, max_transfers => 1, transfer_timeout => 3);
transfer($state, '192.0.2.50', $sum_a, $path_a, $t);
xCAT::UFTP::run_jobs($state, $t);
my $starved = transfer($state, '192.0.2.51', $sum_c, "$c_image/rootimg.cpio.gz", $t);
xCAT::UFTP::run_jobs($state, $t + 3);
is(job_state($state, '192.0.2.51', $starved->{job}, $t + 3)->{state}, 'pending', 'a waiting job waits up to transfer_timeout for a slot');
xCAT::UFTP::run_jobs($state, $t + 4);
my $starved_state = job_state($state, '192.0.2.51', $starved->{job}, $t + 4);
is($starved_state->{state}, 'failed', 'a job that gets no slot within transfer_timeout fails');
is($starved_state->{reason}, 'no transfer slot became free', 'the job reports that no slot became free');

$state = listener();
my $queued = transfer($state, '192.0.2.60', $sum_a, $path_a, $t);
my $sending = transfer($state, '192.0.2.61', $sum_c, "$c_image/rootimg.cpio.gz", $t - 2);
xCAT::UFTP::run_jobs($state, $t);
xCAT::UFTP::sender_exited($state, $senders[0]{pid}, 15, $t, 'listener stopped');
xCAT::UFTP::stop_jobs($state, $t);
is(job_state($state, '192.0.2.61', $sending->{job}, $t)->{reason}, 'listener stopped', 'a sender stopped with the listener fails its job');
my $stopped = job_state($state, '192.0.2.60', $queued->{job}, $t);
is($stopped->{state}, 'failed', 'a queued job fails when the listener stops');
is($stopped->{reason}, 'listener stopped', 'the queued job reports that the listener stopped');

$state = listener(max_connections => 2, allowed_networks => '192.0.2.8/30');
is_deeply([ xCAT::UFTP::connection_refusal($state, 1, '192.0.2.9') ], [], 'an address inside allowed_networks is accepted');
is_deeply([ xCAT::UFTP::connection_refusal($state, 2, '192.0.2.9') ], [ 503, "error=too many connections\n" ],
    'a connection beyond max_connections is refused');
is_deeply([ xCAT::UFTP::connection_refusal($state, 0, '192.0.2.12') ], [ 403, "error=client address is not allowed\n" ],
    'an address outside allowed_networks is refused');
is_deeply(\@log, ['warning: 192.0.2.12: address is not in allowed_networks'], 'the log names the refused address');
$state = listener();
is_deeply([ xCAT::UFTP::connection_refusal($state, 0, '198.51.100.7') ], [], 'any address is accepted without allowed_networks');

done_testing();
