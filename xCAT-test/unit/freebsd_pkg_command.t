#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_PKG_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path getcwd);
use Errno qw(EAGAIN);
use File::Temp qw(tempdir);
use JSON;
use POSIX qw(SIG_BLOCK SIG_SETMASK SIGCHLD);
use Test::More;
use Time::HiRes qw(time);
use xCAT::FreeBSDPkg;
use xCAT::Utils;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $perl = abs_path($^X);

sub rejects {
    my ($action, $pattern, $description) = @_;
    my $ok = eval { $action->(); 1 };
    my $error = $@;
    ok(!$ok, $description);
    like($error, $pattern, "$description diagnostic");
    return $error;
}

sub run_perl {
    my ($program, %options) = @_;
    return xCAT::FreeBSDPkg::run_command([$perl, '-e', $program], %options);
}

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak "$path: $!";
    return defined($bytes) ? $bytes : '';
}

sub basic_cases {
    my $cwd = getcwd();
    is_deeply(run_perl('print "out\\0bytes\\n"; print STDERR "error\\n"; exit 7;'),
        { exitcode => 7, signal => 0, stdout => "out\0bytes\n", stderr => "error\n" },
        'captures binary stdout, stderr and nonzero exit without treating exit as setup failure');
    is_deeply(run_perl('exit 127;'),
        { exitcode => 127, signal => 0, stdout => '', stderr => '' },
        'ordinary exit 127 is not an exec failure');
    my $signalled = run_perl('kill "TERM", $$; sleep 10;');
    is($signalled->{signal}, 15, 'reports signal termination');
    is($signalled->{stdout}, '', 'signal termination preserves empty output');

    local $ENV{XCAT_PKG_PARENT_ONLY} = 'must not inherit';
    local $ENV{PKG_DBDIR} = '/must/not/use';
    my @arguments = ('a b', '; touch should-not-exist', '$(touch should-not-exist)',
        '`touch should-not-exist`', '*', '', "line\nbreak", 'a=b');
    my $result = xCAT::FreeBSDPkg::run_command([$perl, '-MJSON', '-MCwd', '-e',
        'local $/; my $input = <STDIN>; my %values = map { $_ => $ENV{$_} } grep { exists $ENV{$_} } qw(XCAT_PKG_TEST XCAT_PKG_PARENT_ONLY PKG_DBDIR); print JSON->new->canonical->encode({args => \\@ARGV, env => \\%values, names => [sort keys %ENV], cwd => Cwd::getcwd(), stdin => defined($input) ? $input : ""});',
        @arguments], cwd => $tmp, environment => { XCAT_PKG_TEST => 'literal value' });
    is($result->{exitcode}, 0, 'literal argv probe completes');
    is_deeply(decode_json($result->{stdout}), { args => \@arguments,
        env => { XCAT_PKG_TEST => 'literal value' }, names => ['XCAT_PKG_TEST'], cwd => $tmp, stdin => '' },
        'argv is literal, environment is replaced, cwd selected and stdin EOF');
    ok(!-e "$tmp/should-not-exist", 'metacharacters do not execute commands');
    run_perl('exit 0;', cwd => $tmp);
    is(getcwd(), $cwd, 'child cwd does not change caller cwd');
    is($ENV{PKG_DBDIR}, '/must/not/use', 'child environment does not change caller environment');
    return;
}

sub option_cases {
    for my $argv (undef, {}, [], ['relative'], [$perl, undef], [$perl, []], [$perl, "bad\0arg"]) {
        rejects(sub { xCAT::FreeBSDPkg::run_command($argv) }, qr/Command[ ](?:arguments|executable)/x,
            'invalid argv fails before execution');
    }
    rejects(sub { xCAT::FreeBSDPkg::run_command([$perl], 'timeout') }, qr/options must be pairs/,
        'odd option list is rejected');
    rejects(sub { run_perl('', unknown => 1) }, qr/Unknown command option/, 'unknown option is rejected');
    for my $timeout (0, -1, 601, '1e2', 'nan', [], undef) {
        rejects(sub { run_perl('', timeout => $timeout) }, qr/Invalid command timeout/,
            'invalid timeout is rejected');
    }
    for my $key (qw(stdout_limit stderr_limit)) {
        for my $limit (-1, '1.5', 134217729, [], undef) {
            rejects(sub { run_perl('', $key => $limit) }, qr/Invalid[ ]command[ ]\Q$key\E/x,
                "invalid $key is rejected");
        }
    }
    for my $environment (undef, [], { 'a=b' => 'x' }, { a => undef }, { a => [] }, { a => "b\0c" }) {
        rejects(sub { run_perl('', environment => $environment) }, qr/(?:environment[ ]must|Invalid[ ]command[ ]environment)/x,
            'invalid replacement environment is rejected');
    }
    for my $cwd (undef, [], 'relative', "$tmp/missing", "bad\0path") {
        rejects(sub { run_perl('', cwd => $cwd) }, qr/Command directory/,
            'invalid working directory is rejected');
    }
    return;
}

sub output_cases {
    is(run_perl('print "1234";', stdout_limit => 4)->{stdout}, '1234', 'exact stdout bound passes');
    is(run_perl('print STDERR "1234";', stderr_limit => 4)->{stderr}, '1234', 'exact stderr bound passes');
    is(run_perl('exit 0;', stdout_limit => 0, stderr_limit => 0)->{exitcode}, 0,
        'zero output limits permit a silent command');
    rejects(sub { run_perl('print "12345";', stdout_limit => 4) }, qr/stdout exceeds/,
        'stdout overflow is rejected');
    rejects(sub { run_perl('print STDERR "12345";', stderr_limit => 4) }, qr/stderr exceeds/,
        'stderr overflow is rejected');
    my $both = run_perl('for (1 .. 100) { print "o" x 4096; print STDERR "e" x 4096; }');
    is(length($both->{stdout}), 409600, 'interleaved large stdout is fully drained');
    is(length($both->{stderr}), 409600, 'interleaved large stderr is fully drained without deadlock');
    my $error = rejects(sub { run_perl('print STDERR "\\x01" x 3000; close STDERR; sleep 20;',
        timeout => 0.2) }, qr/timed out/, 'timeout retains a bounded diagnostic');
    cmp_ok(length($error), '<=', 2049, 'exception text remains bounded');
    unlike($error, qr/[\x00-\x08\x0b-\x1f\x7f]/x, 'exception sanitizes control bytes');
    return;
}

sub failure_cases {
    rejects(sub { xCAT::FreeBSDPkg::run_command(["$tmp/absent"]) }, qr/Cannot execute command/,
        'exec failure is observed through setup channel');
    rejects(sub { xCAT::FreeBSDPkg::run_command([$tmp]) }, qr/Cannot execute command/,
        'unexecutable directory is an exec failure');
    {
        local *xCAT::Utils::xfork = sub { local $! = EAGAIN; return; };
        rejects(sub { run_perl('exit 0;') }, qr/Cannot fork command/, 'fork failure returns a bounded error');
    }
    my $started = time();
    rejects(sub { run_perl('$SIG{TERM} = "IGNORE"; sleep 20;', timeout => 0.2) }, qr/timed out/,
        'uncooperative command times out');
    cmp_ok(time() - $started, '<', 3, 'timeout does not wait for natural command exit');
    is(run_perl('exit 0;')->{exitcode}, 0, 'a later command works after failures');
    return;
}

sub signal_cases {
    my $received = 0;
    local $SIG{CHLD} = sub { ++$received; };
    my $handler = $SIG{CHLD};
    my $before = POSIX::SigSet->new();
    POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(), $before) or croak $!;
    my $other = fork();
    croak "fork: $!" unless defined($other);
    POSIX::_exit(23) unless $other;
    is(run_perl('select undef, undef, undef, 0.1; exit 0;')->{exitcode}, 0,
        'runner works with another child and a caller SIGCHLD handler');
    is($SIG{CHLD}, $handler, 'caller signal handler is restored');
    ok($received, 'caller handler receives pending child notification after restoration');
    is(waitpid($other, 0), $other, 'runner does not reap another child');
    is($? >> 8, 23, 'other child status is preserved');
    my $after = POSIX::SigSet->new();
    POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(), $after) or croak $!;
    is($after->ismember(SIGCHLD), $before->ismember(SIGCHLD), 'caller child-signal mask is restored');
    rejects(sub { run_perl('sleep 20;', timeout => 0.1) }, qr/timed out/,
        'timeout while caller has SIGCHLD handler');
    is($SIG{CHLD}, $handler, 'failure restores the caller signal handler');
    POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(SIGCHLD), $before) or croak $!;
    my $ok = eval {
        is(run_perl('exit 3;')->{exitcode}, 3, 'runner handles an initially blocked SIGCHLD');
        POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(), $after) or croak $!;
        ok($after->ismember(SIGCHLD), 'initially blocked signal remains blocked');
        1;
    };
    my $error = $@;
    POSIX::sigprocmask(SIG_SETMASK, $before) or croak $!;
    croak $error unless $ok;
    {
        local $SIG{CHLD} = 'IGNORE';
        is(run_perl('exit 4;')->{exitcode}, 4, 'runner can observe status despite caller SIGCHLD ignore');
        is($SIG{CHLD}, 'IGNORE', 'caller SIGCHLD ignore is restored');
    }
    return;
}

sub descendant_cases {
    my $pidfile = "$tmp/descendants";
    my $program = 'open(my $f, ">", $ARGV[0]) or die $!; $f->autoflush(1); print {$f} "$$\\n"; '
      . 'my $child = fork(); die $! unless defined($child); if (!$child) { '
      . '$SIG{TERM} = "IGNORE"; print {$f} "$$\\n"; close $f; sleep 20; exit 0; } '
      . 'close $f; exit 0;';
    my $started = time();
    rejects(sub { xCAT::FreeBSDPkg::run_command([$perl, '-MIO::Handle', '-e', $program, $pidfile],
        timeout => 0.4) }, qr/timed out/, 'descendant-held pipes cannot make collection unbounded');
    cmp_ok(time() - $started, '<', 3, 'descendant cleanup is bounded');
    my @pids = split(/\n/x, read_file($pidfile));
    is(scalar(@pids), 2, 'both leader and descendant actually ran');
    ok(!kill(0, $pids[0]), 'owned group leader is reaped after cleanup');
    my $status = xCAT::FreeBSDPkg::run_command(['/bin/ps', '-o', 'stat=', '-p', $pids[1]],
        environment => { PATH => '/usr/bin:/bin' });
    ok($status->{exitcode} != 0 || $status->{stdout} =~ /\A\s*Z/x, 'descendant is gone or awaiting its own parent reaper');
    return;
}

basic_cases();
option_cases();
output_cases();
failure_cases();
signal_cases();
descendant_cases();
done_testing();
