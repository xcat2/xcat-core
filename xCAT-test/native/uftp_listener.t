#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(realpath);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use IO::Select;
use IO::Socket::INET;
use POSIX qw(WNOHANG);
use Test::More;
use Time::HiRes qw(sleep time);
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use xCAT::SvrUtils;

plan skip_all => 'the UFTP listener test binds loopback addresses and uses Linux namespaces' unless $^O eq 'linux';
my ($bwrap) = grep { -x $_ } qw(/usr/bin/bwrap /bin/bwrap);
die "The UFTP listener test requires bubblewrap\n" unless $bwrap;
die "The UFTP listener test requires GNU timeout\n" unless grep { -x $_ } qw(/usr/bin/timeout /bin/timeout);
my $probe_client = IO::Socket::INET->new(LocalAddr => '127.0.0.2', LocalPort => 0, Proto => 'tcp')
  or die "The UFTP listener test cannot bind 127.0.0.2: $!\n";
close($probe_client);

my $listener = repo_path('xCAT-server/sbin/xcat-uftp-listener');
my $modules  = repo_path('xCAT-server/lib/perl');
my $tmp      = realpath(tempdir(CLEANUP => 1));
my $calls    = "$tmp/calls";
my $root     = "$tmp/install/netboot";
my $fp       = '31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2';
make_path($calls, $root, "$tmp/xcatroot/lib/perl", "$tmp/log");
local $ENV{XCATROOT}      = "$tmp/xcatroot";
local $ENV{FAKE_UFTP_DIR} = $calls;

# The sender fixture records its arguments, its host list and the bytes of /dev/fd/3.
write_binary("$tmp/fake-uftp", <<'EOF');
#!/usr/bin/env perl
# The listener looks for: UFTP version 5.0.4 (xCAT build 1)
use strict;
use warnings;
my $dir = $ENV{FAKE_UFTP_DIR};
my @args = @ARGV;
my %value;
for (my $i = 0; $i < $#args; $i++) {
    $value{ $args[$i] } = $args[ $i + 1 ] if $args[$i] =~ /^-[A-Za-z]$/;
}
open(my $argv, '>', "$dir/$$.argv") or die;
print {$argv} join("\n", @args), "\n";
close($argv);
if (($value{'-H'} // '') =~ /^\@(.+)$/ && open(my $hosts, '<', $1)) {
    local $/;
    my $list = <$hosts>;
    open(my $copy, '>', "$dir/$$.hosts") or die;
    print {$copy} $list;
    close($copy);
}
open(my $image, '<:raw', $args[-1]) or exit 66;
my $bytes = do { local $/; <$image> };
open(my $out, '>:raw', "$dir/$$.bytes") or die;
print {$out} $bytes;
close($out);
my $mode = 'exit:0';
if (open(my $control, '<', "$dir/mode")) {
    $mode = <$control>;
    chomp($mode);
}
exit $1 if $mode =~ /^exit:(\d+)$/;
if ($mode =~ /^block:(\d+)$/) {
    sleep $1;
    exit 0;
}
exit 0;
EOF
write_binary("$tmp/fake-keymgt", <<"EOF");
#!/bin/sh
if [ "\$1" = -g ]; then
    printf 'fixture private key\\n' > "\$3"
    exit 0
fi
[ -r "\$1" ] || exit 1
printf '%s: ECDSA, curve prime256v1, fingerprint: $fp\\n' "\$1" >&2
EOF
chmod(0755, "$tmp/fake-uftp", "$tmp/fake-keymgt");

# packimage publishes the archive with its checksum, and the listener sends only such an archive.
sub publish {
    my ($dir, $content) = @_;
    make_path($dir);
    chmod(0755, $dir);
    my ($stage, $error) = xCAT::SvrUtils->rootimg_stage($dir);
    die $error unless $stage;
    write_binary("$stage/rootimg.cpio.gz", $content);
    chmod(0644, "$stage/rootimg.cpio.gz");
    $error = xCAT::SvrUtils->write_rootimg_checksum("$stage/rootimg.cpio.gz")
      // xCAT::SvrUtils->publish_rootimg("$stage/rootimg.cpio.gz", "$dir/rootimg.cpio.gz");
    die $error if $error;
    return sha256_hex($content);
}

sub free_port {
    my $probe = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp', Listen => 1)
      or die "probe: $!";
    my $port = $probe->sockport();
    close($probe);
    return $port;
}

my $config_seq = 0;
sub config {
    my (%override) = @_;
    my %settings = (
        listen_address   => '127.0.0.1',
        listen_port      => free_port(),
        image_roots      => $root,
        batch_delay      => 1,
        transfer_timeout => 30,
        request_timeout  => 2,
        key_file         => "$tmp/server.key",
        fingerprint_file => "$tmp/server.fingerprint",
        uftp             => "$tmp/fake-uftp",
        uftp_keymgt      => "$tmp/fake-keymgt",
        log_dir          => "$tmp/log",
        %override,
    );
    my $path = "$tmp/listener." . ++$config_seq . '.conf';
    write_binary($path, join('', map { "$_ = $settings{$_}\n" } sort keys %settings));
    return ($path, $settings{listen_port});
}

sub run_listener {
    my ($config, @args) = @_;
    return run_command('timeout', '20', $^X, "-I$modules", $listener, '--config', $config, @args);
}

my %running;
sub start_listener {
    my ($config) = @_;
    my $log = "$tmp/listener.$config_seq.log";
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if ($pid == 0) {
        open(STDOUT, '>', $log) or die;
        open(STDERR, '>&', \*STDOUT) or die;
        exec($^X, "-I$modules", $listener, '--config', $config) or die;
    }
    $running{$pid} = 1;
    return ($pid, $log);
}

sub stop_listener {
    my ($pid) = @_;
    delete $running{$pid};
    kill('TERM', $pid);
    my $deadline = time() + 15;
    while (time() < $deadline) {
        return $? if waitpid($pid, WNOHANG) == $pid;
        sleep(0.1);
    }
    kill('KILL', $pid);
    waitpid($pid, 0);
    return -1;
}

END {
    for my $pid (keys %running) {
        kill('KILL', $pid);
        waitpid($pid, 0);
    }
}

sub http {
    my ($port, $raw, $client) = @_;
    my $sock = IO::Socket::INET->new(
        PeerAddr  => '127.0.0.1',
        PeerPort  => $port,
        LocalAddr => $client || '127.0.0.2',
        Proto     => 'tcp',
        Timeout   => 5,
    ) or return { code => 0, error => "$!" };
    print {$sock} $raw;
    my $response = '';
    my $select   = IO::Select->new($sock);
    while ($select->can_read(5)) {
        last unless sysread($sock, my $chunk, 4096);
        $response .= $chunk;
    }
    close($sock);
    my ($head, $body) = split /\r\n\r\n/, $response, 2;
    my ($status) = ($head // '') =~ m{^HTTP/1\.0 (\d{3}) };
    my %record = map { split /=/, $_, 2 } grep { /=/ } split /\n/, $body // '';
    return { %record, code => $status // 0 };
}

sub request {
    my ($port, $digest, $path, $client) = @_;
    return http($port, "GET /xcat-uftp/v1/transfer/$digest$path HTTP/1.0\r\nHost: test\r\n\r\n", $client);
}

sub job_state {
    my ($port, $job, $client) = @_;
    return http($port, "GET /xcat-uftp/v1/job/$job HTTP/1.0\r\n\r\n", $client);
}

sub wait_state {
    my ($port, $job, $client, @states) = @_;
    my %want = map { $_ => 1 } @states;
    my $deadline = time() + 20;
    my $state;
    while (time() < $deadline) {
        $state = job_state($port, $job, $client);
        return $state if $want{ $state->{state} // '' };
        sleep(0.2);
    }
    return $state;
}

sub wait_port {
    my ($port) = @_;
    my $deadline = time() + 10;
    while (time() < $deadline) {
        my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp');
        if ($sock) {
            close($sock);
            return 1;
        }
        sleep(0.1);
    }
    return 0;
}

sub first_request {
    my ($port, @args) = @_;
    my $deadline = time() + 10;
    my $reply;
    while (time() < $deadline) {
        $reply = request($port, @args);
        return $reply if $reply->{code};
        sleep(0.05);
    }
    return $reply;
}

sub sender_calls {
    opendir(my $dh, $calls) or return ();
    my @pids = sort { $a <=> $b } map { /^(\d+)\.argv$/ ? $1 : () } readdir($dh);
    closedir($dh);
    return map {
        my $pid = $_;
        { pid => $pid, argv => [ split /\n/, read_binary("$calls/$pid.argv") ],
          hosts => -e "$calls/$pid.hosts" ? read_binary("$calls/$pid.hosts") : '',
          bytes => -e "$calls/$pid.bytes" ? read_binary("$calls/$pid.bytes") : undef }
    } @pids;
}

sub wait_call {
    my ($hosts) = @_;
    my $deadline = time() + 10;
    while (time() < $deadline) {
        my ($call) = grep { $_->{hosts} eq $hosts && defined($_->{bytes}) } sender_calls();
        return $call if $call;
        sleep(0.1);
    }
    return undef;
}

sub reset_calls {
    unlink(glob("$calls/*"));
}

sub mode {
    write_binary("$calls/mode", "$_[0]\n");
}

my ($check_config) = config();
my ($rc, $out) = run_listener($check_config, '--check');
is($rc, 1, 'the listener refuses to start without a server key');
like($out, qr/run xcat-uftp-listener --init-key/, 'the missing key error says how to create it');
($rc, $out) = run_listener($check_config, '--init-key');
is($rc, 0, 'the server key is created') or diag($out);
is((stat("$tmp/server.key"))[2] & 07777, 0600, 'the server key is readable only by its owner');
is(scalar(read_binary("$tmp/server.fingerprint")), "$fp\n", 'the fingerprint that uftp_keymgt reports is published for nodeset');
($rc, $out) = run_listener($check_config, '--check');
is($rc, 0, 'the configuration check passes') or diag($out);
like($out, qr/server key fingerprint \Q$fp\E/, 'the check reports the fingerprint of the server key');

# The service sandbox mounts every path except its LogsDirectory read-only, and the listener runs as root.
make_path("$tmp/readonly-log");
my ($readonly_config) = config(log_dir => "$tmp/readonly-log");
($rc, $out) = run_command('timeout', '20', $bwrap, '--dev-bind', '/', '/', '--ro-bind', "$tmp/readonly-log", "$tmp/readonly-log",
    '--unshare-user', '--uid', '0', '--gid', '0', '--', $^X, "-I$modules", $listener, '--config', $readonly_config, '--check');
isnt($rc, 0, 'the check fails as root when log_dir is on a read-only mount');
like($out, qr/Cannot write to \Q$tmp\E\/readonly-log: Read-only file system/, 'the check names the log directory and the reason');

my $image_a = "$root/rhels9/x86_64/compute";
my $content_a = "image A generation 1\n" x 200;
my $sum_a = publish($image_a, $content_a);
my $path_a = "$image_a/rootimg.cpio.gz";

my ($main_config, $port) = config(batch_delay => 2);
my ($pid, $main_log) = start_listener($main_config);
my $first = first_request($port, $sum_a, $path_a, '127.0.0.2');
is($first->{code}, 200, 'the first connection after startup is answered as a transfer request');
is($first->{client_ip}, '127.0.0.2', 'the reply gives the address of the connection');
($rc, $out) = run_listener($main_config);
is($rc, 1, 'a second listener on an occupied port exits with an error');
like($out, qr/Cannot listen on 127\.0\.0\.1:$port: Address already in use/, 'the occupied port is reported');
is(request($port, $sum_a, $path_a, '127.0.0.3')->{job}, $first->{job}, 'a request from another node joins the job');

my $done = wait_state($port, $first->{job}, '127.0.0.2', 'done', 'failed');
is($done->{state}, 'done', 'the job completes when its sender exits');
my @sent = sender_calls();
is(scalar(@sent), 1, 'one sender serves the job');
is($sent[0]{hosts}, "127.0.0.2\n127.0.0.3\n", 'the sender reads the host list of the job');
is($sent[0]{bytes}, $content_a, 'the sender reads the published bytes from its inherited descriptor');
is_deeply([ @{ $sent[0]{argv} }[ -3 .. -1 ] ], [ '-D', 'rootimg.cpio.gz', '/dev/fd/3' ], 'the sender reads the image from descriptor 3');
like(scalar(read_binary("$tmp/log/job-$first->{job}.log")), qr/^starting: \Q$tmp\E\/fake-uftp /m, 'the job log records the sender command');
like(scalar(read_binary($main_log)), qr/job \Q$first->{job}\E: done$/m, 'the listener log reports the finished job');
reset_calls();

mode('exit:7');
my $failing = request($port, $sum_a, $path_a, '127.0.0.5');
my $failed = wait_state($port, $failing->{job}, '127.0.0.5', 'failed', 'done');
is($failed->{state}, 'failed', 'a sender failure fails the job');
is($failed->{reason}, 'uftp exited with status 7', 'the job reports the exit status of the sender');
mode('exit:0');
reset_calls();

my $idle = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, LocalAddr => '127.0.0.2', Proto => 'tcp');
my $idle_started = time();
my $idle_read = sysread($idle, my $nothing, 10);
ok(defined($idle_read) && $idle_read == 0 && time() - $idle_started < 6, 'an idle connection is closed after the request timeout');
close($idle);
is(stop_listener($pid), 0, 'the listener stops cleanly');

my $image_b = "$root/rhels9/x86_64/service";
my $sum_b = publish($image_b, "image B\n" x 100);
my ($limited, $limited_port) = config(batch_delay => 0, max_transfers => 1, transfer_timeout => 3);
($pid) = start_listener($limited);
wait_port($limited_port);
mode('block:20');
my $blocking = request($limited_port, $sum_a, $path_a, '127.0.0.2');
is(wait_state($limited_port, $blocking->{job}, '127.0.0.2', 'running')->{state}, 'running', 'the transfer starts');
# A waiting job fails after transfer_timeout, so it must arrive at least a second after the running one started.
sleep(1.5);
my $waiting = request($limited_port, $sum_b, "$image_b/rootimg.cpio.gz", '127.0.0.3');
is(job_state($limited_port, $waiting->{job}, '127.0.0.3')->{state}, 'pending', 'a second image waits while the transfer limit is reached');
my $timed_out = wait_state($limited_port, $blocking->{job}, '127.0.0.2', 'failed', 'done');
like($timed_out->{reason}, qr/transfer exceeded 3s/, 'a sender that exceeds its timeout fails the job');
my $blocked_call = wait_call("127.0.0.2\n");
ok($blocked_call && !kill(0, $blocked_call->{pid}), 'the timed out sender was stopped');
is(wait_state($limited_port, $waiting->{job}, '127.0.0.3', 'running')->{state}, 'running', 'the waiting transfer starts when the slot frees');
my $held = wait_call("127.0.0.3\n");
is(stop_listener($pid), 0, 'the listener stops while a transfer runs');
ok($held && !kill(0, $held->{pid}), 'stopping the listener stops its senders');
mode('exit:0');
reset_calls();

my ($crowded, $crowded_port) = config(max_connections => 2, request_timeout => 30, allowed_networks => '127.0.0.2/32');
($pid) = start_listener($crowded);
wait_port($crowded_port);
sleep(0.5);
my @held = map {
    IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $crowded_port, LocalAddr => '127.0.0.2', Proto => 'tcp')
} 1 .. 2;
sleep(0.5);
my $fds_before = () = glob("/proc/$pid/fd/*");
my @refused;
for (1 .. 20) {
    my $started = time();
    my $reply = http($crowded_port, '');
    push @refused, $reply->{code} == 503 && time() - $started < 2 ? 1 : 0;
}
is(scalar(grep { $_ } @refused), 20, 'connections beyond max_connections are refused at once');
my $fds_after = () = glob("/proc/$pid/fd/*");
is($fds_after, $fds_before, 'refused connections are not kept open');
close($_) for @held;
sleep(0.5);
is(request($crowded_port, $sum_a, $path_a, '127.0.0.3')->{code}, 403, 'the address of the connection is checked against allowed_networks');
is(request($crowded_port, $sum_a, $path_a, '127.0.0.2')->{code}, 200, 'the listener serves requests again when connections close');
stop_listener($pid);

done_testing();
