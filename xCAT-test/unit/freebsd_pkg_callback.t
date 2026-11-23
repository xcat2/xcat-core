#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_PKG_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path getcwd);
use Errno qw(EAGAIN ECHILD);
use File::Temp qw(tempdir);
use IO::Handle;
use JSON;
use POSIX qw(SIG_BLOCK SIG_SETMASK SIGCHLD);
use Test::More;
use Time::HiRes qw(time sleep);
use xCAT::FreeBSDPkg;
use xCAT::Utils;

my $temporary = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->canonical;

sub read_file {
    my ($path) = @_;
    open(my $file, '<:raw', $path) or croak "$path: $!";
    my $text = do { local $/; <$file> };
    close($file) or croak "$path: $!";
    return defined($text) ? $text : '';
}

sub observed_exit {
    my ($result, $status, $name) = @_;
    is($result->{exitcode}, $status, "$name actual exit status");
    is($result->{signal}, 0, "$name actual wait is not signalled");
    is($result->{callback_complete}, 1, "$name has internal callback completion");
    is($result->{callback_status}, $status, "$name callback status is separate");
    is($result->{streams_complete}, 1, "$name streams reached EOF");
    ok(!defined($result->{failure}), "$name has no supervisor failure");
    cmp_ok($result->{cleanup}{target}, '<', 0, "$name cleanup targets its owned group");
    is($result->{cleanup}{waited}, -$result->{cleanup}{target}, "$name reaps its own leader");
    return;
}

sub isolation_cases {
    local $ENV{XCAT_CALLBACK_PARENT} = 'parent';
    local $::XCAT_DBHS = { fixture => { Active => 1 } };
    my $parent = $$;
    my $cwd = getcwd();
    my $result = xCAT::FreeBSDPkg::run_in_child(sub {
        my $before = $ENV{XCAT_CALLBACK_PARENT};
        $ENV{XCAT_CALLBACK_PARENT} = 'child';
        print $json->encode({ pid => $$, cwd => getcwd(), before => $before,
            inherited_db => scalar(grep { defined($_) } values %{$::XCAT_DBHS}) }) or croak $!;
        print STDERR "private error\0bytes" or croak $!;
        return 0;
    }, cwd => $temporary, environment => { XCAT_CALLBACK_PARENT => 'explicit' });
    observed_exit($result, 0, 'isolated callback');
    my $record = $json->decode($result->{stdout});
    isnt($record->{pid}, $parent, 'callback actually runs in another process');
    is($record->{cwd}, $temporary, 'callback receives the selected directory');
    is($record->{before}, 'explicit', 'callback receives the explicit environment');
    is($record->{inherited_db}, 0, 'real xfork clears inherited database handles');
    is($result->{stderr}, "private error\0bytes", 'stderr is a separate exact private stream');
    is($ENV{XCAT_CALLBACK_PARENT}, 'parent', 'parent environment is unchanged');
    is(getcwd(), $cwd, 'parent working directory is unchanged');
    is_deeply($::XCAT_DBHS, { fixture => { Active => 1 } }, 'parent database handle is unchanged');
    my $nonzero = xCAT::FreeBSDPkg::run_in_child(sub { print '0' or croak $!; return 7; });
    observed_exit($nonzero, 7, 'ordinary nonzero callback');
    is($nonzero->{stdout}, '0', 'the one-byte zero stream is not mistaken for empty');
    return;
}

sub terminal_cases {
    my $exception = xCAT::FreeBSDPkg::run_in_child(sub { die "private exception\n"; });
    is($exception->{exitcode}, 127, 'a thrown callback retains actual setup-failure exit');
    is($exception->{signal}, 0, 'a thrown callback is not reported as a signal');
    is($exception->{setup}, "private exception\n", 'exception bytes stay in the private setup stream');
    is($exception->{callback_complete}, 0, 'throwing is not callback completion');
    like($exception->{failure}, qr/Callback completion is missing or invalid/, 'throwing is a failed outcome');
    my $early = xCAT::FreeBSDPkg::run_in_child(sub { POSIX::_exit(0); });
    is($early->{exitcode}, 0, 'early process exit retains its real zero status');
    is($early->{callback_complete}, 0, 'early zero exit lacks callback completion');
    like($early->{failure}, qr/Callback completion is missing or invalid/,
        'a zero wait status alone cannot authenticate completion');
    my $signal = xCAT::FreeBSDPkg::run_in_child(sub { kill('TERM', $$) or croak $!; sleep 5; return 0; });
    is($signal->{signal}, 15, 'signal termination keeps its actual signal');
    is($signal->{callback_complete}, 0, 'signalled callback has no completion');
    ok(defined($signal->{failure}), 'signalled callback is not accepted');
    my $invalid = xCAT::FreeBSDPkg::run_in_child(sub { return; });
    is($invalid->{callback_complete}, 0, 'undefined callback return is rejected');
    like($invalid->{setup}, qr/Callback must return an exit status/, 'invalid return retains private reason');
    return;
}

sub output_cases {
    my $exact = xCAT::FreeBSDPkg::run_in_child(sub {
        print 'abcd' or croak $!;
        print STDERR 'efgh' or croak $!;
        return 0;
    }, stdout_limit => 4, stderr_limit => 4);
    observed_exit($exact, 0, 'exact output bounds');
    is($exact->{stdout}, 'abcd', 'exact stdout limit is preserved');
    is($exact->{stderr}, 'efgh', 'exact stderr limit is preserved');
    for my $stream (qw(stdout stderr)) {
        my $result = xCAT::FreeBSDPkg::run_in_child(sub {
            if ($stream eq 'stdout') { print 'abcde' or croak $!; }
            else { print STDERR 'abcde' or croak $!; }
            return 0;
        }, stdout_limit => 4, stderr_limit => 4);
        like($result->{failure}, qr/Command \Q$stream\E exceeds its output limit/,
            "$stream overflow is a failed outcome");
        is($result->{$stream}, 'abcd', "$stream retains only the bounded incomplete prefix");
        is($result->{overflow}{$stream}, '65', "$stream records the overflow witness separately");
        is($result->{streams_complete}, 0, "$stream overflow is not complete capture");
        ok(defined($result->{exitcode}) && defined($result->{signal}),
            "$stream overflow retains actual wait status, not a guessed success");
    }
    return;
}

sub signal_cases {
    my $notifications = 0;
    local $SIG{CHLD} = sub { ++$notifications; };
    my $handler = $SIG{CHLD};
    my $before = POSIX::SigSet->new();
    POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(), $before) or croak $!;
    my $other = fork();
    croak $! unless defined($other);
    POSIX::_exit(23) unless $other;
    my $result = xCAT::FreeBSDPkg::run_in_child(sub { return 0; });
    observed_exit($result, 0, 'callback with caller SIGCHLD handler');
    is($SIG{CHLD}, $handler, 'caller signal handler is restored');
    ok($notifications, 'caller receives pending child notifications');
    is(waitpid($other, 0), $other, 'another child is not reaped by the supervisor');
    is($? >> 8, 23, 'another child retains its status');
    my $after = POSIX::SigSet->new();
    POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(), $after) or croak $!;
    is($after->ismember(SIGCHLD), $before->ismember(SIGCHLD), 'caller signal mask is restored');
    my $started = time();
    my $timeout = xCAT::FreeBSDPkg::run_in_child(sub { $SIG{TERM} = 'IGNORE'; sleep 20; return 0; },
        timeout => 0.2);
    like($timeout->{failure}, qr/Command timed out/, 'blocking callback reaches its deadline');
    cmp_ok(time() - $started, '<', 3, 'callback timeout cleanup is bounded');
    is($timeout->{signal}, 9, 'uncooperative callback reports actual supervisor SIGKILL');
    is($timeout->{callback_complete}, 0, 'supervisor killing is not callback completion');
    is($SIG{CHLD}, $handler, 'timeout restores the caller signal handler');
    POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(), $after) or croak $!;
    is($after->ismember(SIGCHLD), $before->ismember(SIGCHLD), 'timeout restores the caller signal mask');
    return;
}

sub stopped {
    my ($pid) = @_;
    my $result = xCAT::FreeBSDPkg::run_command(['/bin/ps', '-o', 'stat=', '-p', $pid], timeout => 2);
    return $result->{exitcode} != 0 || $result->{stdout} =~ /\A\s*Z/x;
}

sub cleanup_descendant {
    my ($pid, $group) = @_;
    my $result = xCAT::FreeBSDPkg::run_command(['/bin/ps', '-o', 'pgid=', '-p', $pid], timeout => 2);
    return if $result->{exitcode} != 0;
    croak 'Refusing cleanup outside the owned group' unless $result->{stdout} =~ /\A\s*\Q$group\E\s*\z/x;
    kill('KILL', $pid) or croak "Cannot stop owned fixture child: $!";
    return;
}

sub descendant_cases {
    for my $closed (0, 1) {
        my $pidfile = "$temporary/descendant-$closed";
        my $result = xCAT::FreeBSDPkg::run_in_child(sub {
            pipe(my $ready, my $send) or croak $!;
            my $child = fork();
            croak $! unless defined($child);
            if (!$child) {
                close($ready) or croak $!;
                $SIG{TERM} = 'IGNORE';
                open(my $pidout, '>', $pidfile) or croak $!;
                print {$pidout} "$$\n" or croak $!;
                close($pidout) or croak $!;
                syswrite($send, 'r') == 1 or croak $!;
                close($send) or croak $!;
                POSIX::close($_) for $closed ? (0 .. 255) : ();
                sleep 20;
                POSIX::_exit(0);
            }
            close($send) or croak $!;
            sysread($ready, my $byte, 1) == 1 or croak $!;
            close($ready) or croak $!;
            return 0;
        }, timeout => 0.4);
        my $pid = read_file($pidfile);
        chomp($pid);
        croak 'Invalid owned child PID' unless $pid =~ /\A[1-9][0-9]*\z/x && $pid != $$;
        my $gone = stopped($pid);
        cleanup_descendant($pid, -$result->{cleanup}{target}) if !$gone;
        ok($gone, $closed ? 'closed-FD descendant is stopped before success' : 'pipe-holding descendant is stopped');
        if ($closed) {
            observed_exit($result, 0, 'closed-FD descendant callback');
        } else {
            like($result->{failure}, qr/Command timed out/, 'pipe-holding descendant does not extend the deadline');
            is($result->{streams_complete}, 0, 'pipe-holder timeout reports incomplete streams');
        }
        $! = 0;
        my $waited = waitpid(-$result->{cleanup}{target}, POSIX::WNOHANG());
        ok($waited == -1 && $! == ECHILD, 'descendant case leader is reaped');
    }
    return;
}

sub argument_cases {
    for my $timeout (601, 1800, 7200) {
        my $result = eval { xCAT::FreeBSDPkg::run_in_child(sub { return 0; }, timeout => $timeout); };
        ok(defined($result), "callback accepts the $timeout second worker deadline");
        observed_exit($result, 0, 'accepted callback deadline completes') if defined($result);
    }
    for my $case (
        [sub { xCAT::FreeBSDPkg::run_in_child(sub { return 0; }, timeout => 7201); }, 'callback'],
        [sub { xCAT::FreeBSDPkg::run_command(['/bin/true'], timeout => 601); }, 'ordinary command'],
    ) {
        my $ok = eval { $case->[0]->(); 1 };
        ok(!$ok, "$case->[1] rejects an excessive deadline");
        like($@, qr/Invalid[ ]command[ ]timeout/x, "$case->[1] keeps its timeout bound");
    }
    for my $operation (undef, [], 'not code') {
        my $ok = eval { xCAT::FreeBSDPkg::run_in_child($operation); 1; };
        ok(!$ok, 'invalid callback fails before a child is launched');
        like($@, qr/Child operation must be a callback/, 'invalid callback has a bounded argument error');
    }
    {
        no warnings 'redefine';
        local *xCAT::Utils::xfork = sub { $! = EAGAIN; return; };
        my $result = xCAT::FreeBSDPkg::run_in_child(sub { croak 'must not run'; });
        like($result->{failure}, qr/Cannot fork command/, 'fork failure remains a private failed outcome');
        ok(!defined($result->{exitcode}) && !defined($result->{signal}), 'fork failure invents no wait status');
        is($result->{callback_complete}, 0, 'fork failure has no callback completion');
    }
    return;
}

sub failed_output_cases {
    for my $kind (qw(exception invalid)) {
        my $result = xCAT::FreeBSDPkg::run_in_child(sub {
            STDOUT->autoflush(0);
            STDERR->autoflush(0);
            print "buffered\0output" or croak $!;
            print STDERR "buffered\0errors" or croak $!;
            die "private callback failure\n" if $kind eq 'exception';
            return;
        });
        is($result->{stdout}, "buffered\0output", "$kind retains buffered stdout");
        is($result->{stderr}, "buffered\0errors", "$kind retains buffered stderr");
        is($result->{exitcode}, 127, "$kind retains actual failure status");
        is($result->{signal}, 0, "$kind is not reported as a signal");
        is($result->{callback_complete}, 0, "$kind is not callback completion");
        is($result->{streams_complete}, 1, "$kind drains streams before returning");
        ok(defined($result->{failure}), "$kind remains a failed outcome");
        like($result->{setup}, $kind eq 'exception'
            ? qr/\Aprivate callback failure\n\z/ : qr/\ACallback must return an exit status\n\z/,
            "$kind retains its original private reason");
    }
    return;
}

{
    package XCAT::Test::CallbackException;
    use overload q{""} => sub { die "exception stringification failed\n"; }, fallback => 1;
}

sub reporting_cases {
    for my $kind (qw(wide object)) {
        my $parent = $$;
        my $sentinel = "$temporary/continued-$kind";
        my $result = xCAT::FreeBSDPkg::run_in_child(sub {
            die "\x{100}\n" if $kind eq 'wide';
            die bless {}, 'XCAT::Test::CallbackException';
        });
        if ($$ != $parent) {
            open(my $file, '>', $sentinel) or POSIX::_exit(97);
            print {$file} "child returned\n" or POSIX::_exit(98);
            close($file) or POSIX::_exit(99);
            POSIX::_exit(96);
        }
        is($result->{exitcode}, 127, "$kind reporting failure exits the child");
        is($result->{signal}, 0, "$kind reporting failure is not a signal");
        is($result->{callback_complete}, 0, "$kind reporting failure has no completion");
        is($result->{streams_complete}, 1, "$kind reporting failure closes capture streams");
        ok(defined($result->{failure}), "$kind reporting failure remains a failed outcome");
        ok(!-e $sentinel, "$kind reporting failure cannot continue caller code");
        is($result->{setup}, $kind eq 'wide' ? "\xc4\x80\n" : '',
            "$kind retains encodable private diagnostics without inventing bytes");
    }
    return;
}

subtest 'real inherited-context isolation' => sub { isolation_cases(); done_testing(); };
subtest 'callback completion and actual terminal status' => sub { terminal_cases(); done_testing(); };
subtest 'bounded complete and incomplete streams' => sub { output_cases(); done_testing(); };
subtest 'signals deadlines and unrelated children' => sub { signal_cases(); done_testing(); };
subtest 'owned descendants with open and closed capture descriptors' => sub { descendant_cases(); done_testing(); };
subtest 'argument and fork failures' => sub { argument_cases(); done_testing(); };
subtest 'buffered diagnostics from failed callbacks' => sub { failed_output_cases(); done_testing(); };
subtest 'exception reporting cannot return a forked child' => sub { reporting_cases(); done_testing(); };
done_testing();
