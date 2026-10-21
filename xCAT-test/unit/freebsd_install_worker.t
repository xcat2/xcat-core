#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_STATE_MODULE_DIR};
use Carp qw(croak);
use File::Temp qw(tempdir);
use IO::Select;
use JSON;
use POSIX qw(WNOHANG);
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);
use Test::More;
use Time::HiRes qw(time sleep);
use xCAT::FreeBSDInstall;
use xCAT::FreeBSDPostscript;

BEGIN {
    $INC{'xCAT/Table.pm'} = __FILE__;
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;
}
{
    package xCAT::Table;
    sub new {
        die 'Unexpected table' unless $_[1] eq 'noderes';
        return bless {}, $_[0];
    }
    sub getNodeAttribs {
        die 'Unexpected node' unless $_[1] eq 'node1';
        return { xcatmaster => '192.0.2.1' };
    }
    sub close { return; }
}
{
    package xCAT::NetworkUtils;
    sub clearcache { return; }
    sub getipaddr { return '192.0.2.10'; }
}

umask oct('0077');
my $temporary = tempdir(CLEANUP => 1);
local $ENV{XCATROOT} = $temporary;
my $json = JSON->new->canonical;
my ($attempt, $run) = map { $_ x 32 } qw(b c);
my ($boot, $snapshot, $preparation) = map { $_ x 64 } qw(d e f);
my $sequence = 0;

sub write_file {
    my ($path, $bytes) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    return;
}

sub read_file {
    my ($path) = @_;
    open(my $file, '<', $path) or croak "$path: $!";
    my $bytes = do { local $/ = undef; <$file> };
    close($file) or croak $!;
    return defined($bytes) ? $bytes : '';
}

sub fixture {
    my $root = "$temporary/case-" . ++$sequence;
    mkdir($root) or croak $!;
    my $directory = "$root/state";
    my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64,
        directory => $directory,
        postscript_preparations => { firstboot => $preparation, repeat => $preparation });
    for my $phase (qw(begin complete booted)) {
        xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $generation $attempt $phase",
            sub {}, directory => $directory);
    }
    my $state = xCAT::FreeBSDInstall::state('node1', directory => $directory);
    # A retained decision makes the real boot observation sufficient for a retry.
    $state->{postscript_boot} = { kind => 'firstboot', run => $run, boot => $boot,
        snapshot => $snapshot, preparation => $preparation };
    write_file("$directory/node1.json", $json->encode($state) . "\n");
    return { root => $root, directory => $directory, generation => $generation,
        expected => read_file("$directory/node1.json") };
}

sub response {
    my ($case, $callback) = @_;
    my %fields = (format => 'xcat-freebsd-boot-context-1', node => 'node1',
        generation => $case->{generation}, attempt => $attempt, boot => $boot,
        run => $run, snapshot => $snapshot, 'run-boot' => $boot,
        outcome => 'uncertain', complete => 'no', released => 'no');
    $callback->({ data => [join("\n", map { "node1: $_\t$fields{$_}" }
        qw(format node generation attempt boot run snapshot run-boot outcome complete released))] });
    $callback->({ data => ['node1: Remote_command_successful'] });
    return;
}

sub launch {
    my ($case, $dispatch) = @_;
    socketpair(my $client, my $server, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or croak $!;
    $server->autoflush(1);
    my $observe = \&xCAT::FreeBSDPostscript::observe_boot;
    my $pid;
    {
        no warnings 'redefine';
        # Route only the evidence store; keep observation and response validation real.
        local *xCAT::FreeBSDPostscript::observe_boot = sub {
            return $observe->(@_, directory => "$case->{root}/postscripts");
        };
        $pid = xCAT::FreeBSDInstall::start_status_worker('node1', '192.0.2.10',
            "freebsd-install-postscripts-v1 $case->{generation} $attempt $boot\n",
            $server, $dispatch, directory => $case->{directory},
            cleanup => sub { close($client) or croak $!; },
            log => sub { write_file("$case->{root}/error", $_[0]); });
    }
    croak 'Worker was not started' unless $pid;
    return ($pid, $client);
}

sub collect {
    my ($pid, $client, $seconds) = @_;
    my $deadline = time() + $seconds;
    my $waited;
    while (time() < $deadline) {
        $waited = waitpid($pid, WNOHANG);
        last if $waited == $pid;
        croak 'Lost status worker' if $waited < 0;
        sleep 0.02;
    }
    my $finished = $waited == $pid;
    my $status = $?;
    if (!$finished) {
        kill('KILL', $pid) or croak $!;
        waitpid($pid, 0) == $pid or croak $!;
        $status = $?;
    }
    my $ready = IO::Select->new($client)->can_read(1);
    my $bytes = '';
    sysread($client, $bytes, 8192) if $ready;
    close($client) or croak $!;
    return ($finished, $status, $bytes);
}

sub stopped {
    my $pid = shift;
    my $result = xCAT::FreeBSDPkg::run_command(['/bin/ps', '-o', 'stat=', '-p', $pid], timeout => 2);
    return $result->{exitcode} != 0 || $result->{stdout} =~ /\A\s*Z/x;
}

sub cleanup_child {
    my ($pid, $group) = @_;
    my $result = xCAT::FreeBSDPkg::run_command(['/bin/ps', '-o', 'pgid=', '-p', $pid], timeout => 2);
    return if $result->{exitcode} != 0;
    croak 'Fixture process changed group' unless $result->{stdout} =~ /\A\s*\Q$group\E\s*\z/x;
    kill('KILL', $pid) or croak $!;
    return;
}

sub descendant {
    my ($case) = @_;
    pipe(my $reader, my $writer) or croak $!;
    my $pid = fork();
    croak $! unless defined($pid);
    if (!$pid) {
        close($reader) or croak $!;
        local $SIG{TERM} = 'IGNORE';
        write_file("$case->{root}/descendant", "$$ " . getpgrp(0) . "\n");
        syswrite($writer, 'r') == 1 or croak $!;
        close($writer) or croak $!;
        POSIX::close($_) for 0 .. 255;
        sleep 40;
        POSIX::_exit(0);
    }
    close($writer) or croak $!;
    sysread($reader, my $byte, 1) == 1 or croak $!;
    close($reader) or croak $!;
    return;
}

sub check_descendant {
    my ($case) = @_;
    my ($pid, $group) = split(/\s+/x, read_file("$case->{root}/descendant"));
    croak 'Invalid fixture PID' if $pid !~ /\A[1-9][0-9]*\z/x || $pid == $$;
    my $gone = stopped($pid);
    cleanup_child($pid, $group) unless $gone;
    ok($gone, 'owned descendant is stopped before the worker returns');
    return;
}

sub unchanged {
    my ($case) = @_;
    is(read_file("$case->{directory}/node1.json"), $case->{expected},
        'interruption or observation preserves the retained installation decision');
    return;
}

sub accepted {
    my ($case, $dispatch) = @_;
    my ($pid, $client) = launch($case, $dispatch || sub { response($case, $_[1]); });
    my ($finished, $status, $bytes) = collect($pid, $client, 5);
    diag(read_file("$case->{root}/error")) if $status && -f "$case->{root}/error";
    ok($finished, 'status worker finishes within the test bound');
    is($status, 0, 'completed observation exits successfully');
    is($bytes, "freebsd-install-postscripts-v1 $case->{generation} $boot $run uncertain\n",
        'the real validated observation reaches the protocol response');
    unchanged($case);
    return;
}

sub successful_transport {
    my $case = fixture();
    local $ENV{XCAT_WORKER_TRANSPORT_TEST} = 'inherited';
    local $ENV{XCAT_WORKER_ABSENT} = undef;
    accepted($case, sub {
        croak 'Environment lost' unless $ENV{XCAT_WORKER_TRANSPORT_TEST} eq 'inherited';
        descendant($case);
        print "transport output outside callbacks\n" or croak $!;
        response($case, $_[1]);
    });
    check_descendant($case);
    return;
}

sub interrupted_transport {
    for my $signal (qw(ALRM TERM INT USR2)) {
        my $case = fixture();
        my ($pid, $client) = launch($case, sub {
            local @SIG{qw(ALRM TERM INT USR2)} = ('IGNORE') x 4;
            descendant($case);
            write_file("$case->{root}/ready", "$$\n");
            sleep 40;
        });
        my $deadline = time() + 5;
        sleep 0.02 while !-s "$case->{root}/ready" && time() < $deadline;
        ok(-s "$case->{root}/ready", "$signal reaches the transport boundary");
        kill($signal, $pid) or croak $!;
        my ($finished, $status, $bytes) = collect($pid, $client, 2);
        ok($finished, "$signal cannot be replaced by transport signal handlers");
        is($status >> 8, 1, "$signal is a failed status request");
        is($bytes, '', "$signal sends no acknowledgment");
        check_descendant($case);
        my $transport_pid = read_file("$case->{root}/ready");
        chomp($transport_pid);
        my $transport_stopped = stopped($transport_pid);
        cleanup_child($transport_pid, $transport_pid) unless $transport_stopped;
        ok($transport_stopped, "$signal stops the transport leader");
        unchanged($case);
        accepted($case);
    }
    return;
}

sub failed_transport {
    for my $kind (qw(exception early invalid overflow)) {
        my $case = fixture();
        my ($pid, $client) = launch($case, sub {
            my $callback = $_[1];
            $callback->({ error => ['node1: retained transport diagnostic'] });
            croak "transport exception marker\n" if $kind eq 'exception';
            POSIX::_exit(0) if $kind eq 'early';
            $callback->([]) if $kind eq 'invalid';
            $callback->({ data => ['x' x 1048576] }) if $kind eq 'overflow';
        });
        my ($finished, $status, $bytes) = collect($pid, $client, 5);
        ok($finished, "$kind failure is bounded");
        is($status >> 8, 1, "$kind cannot succeed");
        is($bytes, '', "$kind has no acknowledgment");
        my @responses = glob("$case->{root}/postscripts/.boot-node1.*/context.responses.json");
        is(scalar(@responses), 1, "$kind retains one failed transport record");
        like(read_file($responses[0]), qr/retained[ ]transport[ ]diagnostic/x,
            "$kind retains callbacks received before failure") if @responses;
        if ($kind eq 'exception') {
            like(read_file("$case->{root}/error"), qr/transport[ ]exception[ ]marker/x,
                'underlying exception reaches the status logger');
        }
        unchanged($case);
    }
    return;
}

sub transport_deadline {
    my $case = fixture();
    my $started = time();
    my ($pid, $client) = launch($case, sub {
        local @SIG{qw(ALRM TERM)} = ('IGNORE') x 2;
        descendant($case);
        write_file("$case->{root}/ready", "$$\n");
        sleep 40;
    });
    my ($finished, $status, $bytes) = collect($pid, $client, 25);
    ok($finished, 'the actual 20 second observation deadline stops transport');
    is($status >> 8, 1, 'transport timeout fails the request');
    is($bytes, '', 'transport timeout sends no acknowledgment');
    cmp_ok(time() - $started, '<', 25, 'transport timeout does not wait for the outer worker deadline');
    check_descendant($case);
    unchanged($case);
    accepted($case);
    return;
}

subtest 'successful supervised transport reaps descendants' => \&successful_transport;
subtest 'transport cannot defeat status worker cancellation' => \&interrupted_transport;
subtest 'transport failures preserve diagnostics and ownership' => \&failed_transport;
subtest 'transport request deadline remains authoritative' => \&transport_deadline;
done_testing();
