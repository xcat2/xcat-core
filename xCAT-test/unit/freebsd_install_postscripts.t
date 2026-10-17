#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_STATE_MODULE_DIR};
use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:flock);
use File::Temp qw(tempdir);
use JSON;
use Test::More;
use xCAT::FreeBSDInstall;

BEGIN {
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;
    $INC{'xCAT/FreeBSDPostscript.pm'} = __FILE__;
}
{
    package xCAT::NetworkUtils;
    sub clearcache { return; }
    sub getipaddr { return '192.0.2.10'; }
}
{
    package xCAT::FreeBSDPostscript;
    sub observe_boot { return main::observe(@_); }
    sub compile_execution { return { enabled => $main::repeat_enabled }; }
    sub export_execution { return main::export_run(@_); }
    sub deliver_execution { return main::deliver(@_); }
    sub collect_execution { return main::collect(@_); }
}

umask 0077;
my $temporary = tempdir(CLEANUP => 1);
my ($directory, $generation, $boot, %exports, %remote, %fault, @observations, @deliveries, @reports);
my $sequence = 0;
my $attempt = 'b' x 32;
my $first_preparation = 'c' x 64;
my $repeat_preparation = 'd' x 64;
my $changed_installation = 'Installation changed during boot postscript delivery';
our $repeat_enabled = 1;

sub disk_state {
    open(my $file, '<', "$directory/node1.json") or die $!;
    my $value = decode_json(do { local $/; <$file> });
    close($file) or die $!;
    return $value;
}

sub fixture {
    $directory = "$temporary/state-" . ++$sequence;
    $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $directory,
        postscript_preparations => { firstboot => $first_preparation, repeat => $repeat_preparation });
    for my $phase (qw(begin complete booted)) {
        xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $generation $attempt $phase", sub {}, directory => $directory);
    }
    $boot = 'e' x 64;
    %exports = (); %remote = (); %fault = ();
    @observations = (); @deliveries = (); @reports = ();
    $repeat_enabled = 1;
    return;
}

sub observe {
    my ($node, $gen, $nonce, $run) = @_;
    push @observations, $run;
    is_deeply([$node, $gen, $nonce], ['node1', $generation, $attempt], 'probe uses the protected deployment');
    my $retained = $remote{$run};
    $fault{at_observe}->() if $fault{at_observe};
    return { boot => $boot, run => $run,
        $retained ? (snapshot => $retained->{snapshot}, 'run-boot' => $retained->{boot},
            outcome => $retained->{outcome}, complete => $retained->{complete}, released => $retained->{released})
          : (snapshot => '-', 'run-boot' => '-', outcome => 'absent', complete => 'no', released => 'no'),
        %{$fault{observation} || {}} };
}

sub export_run {
    my ($preparation, %binding) = @_;
    my $decision = disk_state()->{postscript_boot};
    is_deeply([@{$decision}{qw(run boot preparation)}], [@binding{qw(run boot)}, $preparation],
        'decision is durable before export');
    open(my $lock, '+<', "$directory/node1.lock") or die $!;
    ok(flock($lock, LOCK_EX | LOCK_NB), 'installation state remains accessible during export');
    close($lock) or die $!;
    die "export unavailable\n" if delete($fault{export});
    my $run = $binding{run};
    my $export = { node => 'node1', snapshot => sha256_hex($run), binding => { %binding, preparation => $preparation } };
    is_deeply($exports{$run}, $export, 'retry preserves the exact export') if exists($exports{$run});
    $exports{$run} = $export;
    $fault{at_export}->() if $fault{at_export};
    return $export;
}

sub deliver {
    my ($run, $dispatch) = @_;
    push @deliveries, $run;
    my $decision = disk_state()->{postscript_boot};
    is($decision->{snapshot}, $exports{$run}{snapshot}, 'snapshot is durable before transfer or start');
    if (delete($fault{partial_delivery})) {
        $remote{$run} = { run => $run, snapshot => '-', boot => '-', outcome => 'incomplete',
            complete => 'no', released => 'no', starts => 0 };
        die "partial delivery disconnected\n";
    }
    delete $remote{$run} if $remote{$run} && $remote{$run}{outcome} eq 'incomplete';
    $remote{$run} ||= { run => $run, snapshot => $exports{$run}{snapshot}, boot => $boot,
        outcome => 'pending', complete => 'no', released => 'no', starts => 1 };
    die "delivery disconnected\n" if delete($fault{delivery});
    $fault{at_deliver}->($dispatch) if $fault{at_deliver};
    return $remote{$run};
}

sub collect {
    my $run = shift;
    push @reports, $run;
    die "report unavailable\n" if delete($fault{report});
    my $retained = $remote{$run};
    ok($retained->{complete} eq 'yes' || $retained->{released} eq 'yes', 'collection requires stable native evidence');
    $fault{at_collect}->() if $fault{at_collect};
    return { receipt => { %$retained, %{$fault{report_binding} || {}} } };
}

sub call_status {
    my (%changes) = @_;
    return xCAT::FreeBSDInstall::handle_status('node1', $changes{peer} || '192.0.2.10',
        $changes{message} || "freebsd-install-postscripts-v1 $generation $attempt $boot\n",
        $changes{dispatch} || sub {}, directory => $directory);
}

sub complete {
    my ($outcome) = @_;
    my $run = disk_state()->{postscript_boot}{run};
    $remote{$run}{outcome} = $outcome || 'success';
    $remote{$run}{complete} = 'yes';
    return $run;
}

sub reject {
    my ($code, $pattern, $label) = @_;
    my $ok = eval { $code->(); 1 };
    ok(!$ok, "$label rejected");
    like($@, $pattern, "$label reports the cause");
}

sub replace_installation {
    open(my $lock, '+<', "$directory/node1.lock") or croak $!;
    my $available = flock($lock, LOCK_EX | LOCK_NB);
    ok($available, 'another installation operation can acquire the state lock during transport');
    close($lock) or croak $!;
    return unless $available;
    xCAT::FreeBSDInstall::cancel('node1', directory => $directory);
    return xCAT::FreeBSDInstall::prepare('node1', '1' x 64, directory => $directory,
        postscript_preparations => { firstboot => $first_preparation, repeat => $repeat_preparation });
}

sub replacement_during_delivery {
    for my $phase (qw(observe export deliver collect)) {
        fixture();
        if ($phase eq 'collect') { call_status(); complete(); }
        my $previous = scalar(@deliveries);
        my $replacement;
        $fault{"at_$phase"} = sub { $replacement = replace_installation(); };
        reject(sub { call_status() }, qr/\Q$changed_installation\E/x,
            "$phase cannot acknowledge a replaced installation");
        ok(defined($replacement) && $replacement ne $generation, 'replacement generation completes during transport');
        is(disk_state()->{generation}, $replacement, 'older delivery cannot overwrite the replacement generation');
        is(disk_state()->{phase}, 'prepared', 'replacement remains prepared');
        ok(!exists(disk_state()->{postscript_boot}), 'older boot decision is not published into the replacement');
        is(scalar(@deliveries), $previous + ($phase eq 'deliver' ? 1 : 0),
            'changed installation stops subsequent delivery');
    }
    return;
}

subtest 'installation replacement is preserved at each delivery boundary' => \&replacement_during_delivery;

subtest 'each transport command rechecks the installation generation' => sub {
    fixture();
    my ($calls, $replacement) = (0, undef);
    $fault{at_deliver} = sub {
        my $dispatch = shift;
        my $request = { command => ['xdsh'], node => ['node1'], arg => ['receipt'] };
        $dispatch->($request, sub {});
        $replacement = replace_installation();
        $dispatch->($request, sub {});
    };
    reject(sub { call_status(dispatch => sub { ++$calls; }); },
        qr/\Q$changed_installation\E/x,
        'changed generation before the second transport command');
    is($calls, 1, 'second command never reaches the transport');
    is(disk_state()->{generation}, $replacement, 'replacement stays authoritative');
    ok(!exists(disk_state()->{postscript_boot}), 'old decision cannot return after replacement');
};

subtest 'another boot delivery is rejected without taking the installation lock' => sub {
    fixture();
    open(my $lock, '+>', "$directory/node1.boot.lock") or croak $!;
    flock($lock, LOCK_EX | LOCK_NB) or croak $!;
    reject(sub { call_status() }, qr/Boot[ ]postscript[ ]delivery[ ]is[ ]busy/x, 'overlapping boot delivery');
    is(scalar(@observations), 0, 'overlapping request never reaches the node');
    ok(!exists(disk_state()->{postscript_boot}), 'overlapping request allocates no run');
    is(xCAT::FreeBSDInstall::state('node1', directory => $directory)->{phase}, 'booted',
        'other state readers remain available while the boot lock is held');
    close($lock) or croak $!;
    like(call_status(), qr/[ ]pending\n\z/x, 'delivery resumes after the boot lock is released');
};

subtest 'first boot, cached replies and repeat use persistent decisions' => sub {
    fixture();
    like(call_status(), qr/ pending\n\z/, 'first boot starts asynchronously');
    my $first = disk_state()->{postscript_boot}{run};
    is($exports{$first}{binding}{preparation}, $first_preparation, 'first boot uses both frozen script phases');
    like(call_status(), qr/\Q$first\E pending\n\z/, 'same boot retry keeps its run');
    is($remote{$first}{starts}, 1, 'retry does not start another execution');
    complete();
    like(call_status(), qr/\Q$first\E success\n\z/, 'complete report is acknowledged');
    is(disk_state()->{postscript_first}{run}, $first, 'first completion persists');
    my $deliveries = @deliveries;
    like(call_status(), qr/\Q$first\E success\n\z/, 'lost terminal acknowledgement is recoverable');
    is(scalar(@deliveries), $deliveries, 'completed observation does not redeliver');
    for my $index (1 .. 8) {
        $boot = sha256_hex("boot-$index");
        like(call_status(), qr/ pending\n\z/, 'later boot receives a new repeat run');
        my $decision = disk_state()->{postscript_boot};
        is($decision->{kind}, 'repeat', 'later boot selects only repeat');
        is($decision->{preparation}, $repeat_preparation, 'repeat uses its frozen preparation');
        isnt($decision->{run}, $first, 'original first boot is not reused');
        complete();
        call_status();
    }
    cmp_ok(length(encode_json(disk_state())), '<', 1400, 'state remains bounded across boots');
    is(disk_state()->{phase}, 'booted', 'OS boot status is independent of script reporting');
    is(disk_state()->{postscript_first}{run}, $first, 'later boots retain the first result');
    done_testing();
};

subtest 'transport failures preserve the selected run' => sub {
    for my $failure (qw(export delivery report)) {
        fixture();
        if ($failure eq 'report') { call_status(); complete(); }
        $fault{$failure} = 1;
        reject(sub { call_status() }, qr/(?:unavailable|disconnected)/, "$failure failure");
        my $selected = disk_state()->{postscript_boot}{run};
        call_status();
        is(disk_state()->{postscript_boot}{run}, $selected, "$failure retry reuses the decision");
        is($remote{$selected}{starts}, 1, "$failure retry cannot replay execution");
    }
    done_testing();
};

subtest 'later boots may replace only demonstrably unstarted work' => sub {
    for my $outcome (qw(absent admitted)) {
        fixture();
        if ($outcome eq 'absent') {
            $fault{export} = 1;
            eval { call_status() };
        } else {
            call_status();
            my $run = disk_state()->{postscript_boot}{run};
            $remote{$run}{outcome} = 'admitted';
            $remote{$run}{starts} = 0;
        }
        my $previous = disk_state()->{postscript_boot}{run};
        $boot = 'f' x 64;
        call_status();
        my $decision = disk_state()->{postscript_boot};
        isnt($decision->{run}, $previous, "$outcome old boot receives a new bound run");
        is($decision->{kind}, 'firstboot', 'unstarted first boot remains eligible');
        is($observations[-1], $previous, 'old run was observed before replacement');
    }
    done_testing();
};

subtest 'incomplete admission resumes in the same boot and is replaceable after reboot' => sub {
    for my $reboot (0, 1) {
        fixture();
        $fault{partial_delivery} = 1;
        reject(sub { call_status() }, qr/partial[ ]delivery[ ]disconnected/x, 'interrupted transfer');
        my $run = disk_state()->{postscript_boot}{run};
        is($remote{$run}{starts}, 0, 'partial admission has not started a script');
        $boot = 'f' x 64 if $reboot;
        my $reply;
        my $ok = eval { $reply = call_status(); 1 };
        ok($ok, $reboot ? 'later boot replaces unstarted admission' : 'same boot resumes admission');
        diag($@) unless $ok;
        if ($ok) {
            my $current = disk_state()->{postscript_boot}{run};
            like($reply, qr/\Q$current\E[ ]pending\n\z/x, 'accepted delivery returns its selected run');
            is($remote{$current}{starts}, 1, 'accepted run starts once');
            is($remote{$current}{boot}, $boot, 'run is bound to the current boot');
            is(disk_state()->{postscript_boot}{kind}, 'firstboot', 'unstarted first boot remains eligible');
            if ($reboot) {
                isnt($current, $run, 'new boot receives a new run');
                is($remote{$run}{starts}, 0, 'abandoned partial admission never executes');
                is($exports{$run}{binding}{boot}, 'e' x 64, 'old export retains its original boot binding');
            } else {
                is($current, $run, 'same boot retains the original run');
                is(scalar(keys %exports), 1, 'same boot reuses the original export');
            }
        }
    }
    done_testing();
};

subtest 'failed and interrupted first boots keep their disposition' => sub {
    fixture(); call_status();
    my $failed = complete('failed');
    like(call_status(), qr/ failed\n\z/, 'failed first boot is not called successful');
    $boot = 'f' x 64; call_status();
    is_deeply(disk_state()->{postscript_first}, { run => $failed, result => { outcome => 'failed', complete => 'yes' } },
        'repeat does not erase the failed first boot');
    is(disk_state()->{postscript_boot}{kind}, 'repeat', 'complete failure does not replay postscripts');

    fixture(); call_status();
    my $interrupted = disk_state()->{postscript_boot}{run};
    $remote{$interrupted}{outcome} = 'uncertain';
    my $count = @deliveries;
    like(call_status(), qr/ uncertain\n\z/, 'same boot reports uncertainty');
    is(scalar(@deliveries), $count, 'uncertain execution is not replayed');
    $boot = 'f' x 64;
    reject(sub { call_status() }, qr/explicit interruption recovery/, 'unreleased previous boot');
    is(disk_state()->{postscript_boot}{run}, $interrupted, 'blocked run remains selected');
    $remote{$interrupted}{released} = 'yes';
    call_status();
    is_deeply(disk_state()->{postscript_first}, { run => $interrupted, result => { outcome => 'uncertain', complete => 'no' } },
        'explicit release retains incomplete first boot');
    is(disk_state()->{postscript_boot}{kind}, 'repeat', 'recovery never replays initial postscripts');
    done_testing();
};

subtest 'disabled repeat and identity mismatches do not dispatch scripts' => sub {
    fixture(); call_status(); complete(); call_status();
    my $first = disk_state()->{postscript_boot}{run};
    $repeat_enabled = 0; $boot = 'f' x 64;
    like(call_status(), qr/ - disabled\n\z/, 'frozen disabled repeat is acknowledged');
    is(disk_state()->{postscript_boot}{run}, $first, 'disabled repeat allocates no run');
    is(scalar(keys %exports), 1, 'disabled repeat exports nothing');
    fixture();
    reject(sub { call_status(peer => '192.0.2.11') }, qr/Unexpected installation client/, 'wrong peer');
    reject(sub { call_status(message => "freebsd-install-postscripts-v1 " . ('1' x 32) . " $attempt $boot") },
        qr/deployment differs/, 'stale generation');
    reject(sub { call_status(message => "freebsd-install-postscripts-v1 $generation " . ('2' x 32) . " $boot") },
        qr/deployment differs/, 'stale attempt');
    is(scalar(@observations), 0, 'unbound callbacks do not reach the node');
    $fault{observation} = { boot => '1' x 64 };
    reject(sub { call_status() }, qr/Reported boot differs/, 'forged boot');
    is(scalar(keys %exports), 0, 'forged boot exports nothing');
    delete $fault{observation}; call_status();
    for my $changed ( { snapshot => '1' x 64 }, { 'run-boot' => '2' x 64 }) {
        $fault{observation} = $changed;
        reject(sub { call_status() }, qr/Observed boot run differs/, 'mismatched retained run');
    }
    delete $fault{observation}; complete(); call_status();
    $fault{observation} = { outcome => 'absent', complete => 'no' };
    reject(sub { call_status() }, qr/no longer retained/, 'lost completed evidence');
    delete $fault{observation};
    $fault{report_binding} = { snapshot => '3' x 64 };
    reject(sub { call_status() }, qr/Boot report binding differs/, 'wrong report snapshot');
    xCAT::FreeBSDInstall::cancel('node1', directory => $directory);
    reject(sub { call_status() }, qr/completed installation/, 'cancelled generation');
    done_testing();
};

subtest 'corrupt retained decisions fail before observation' => sub {
    for my $change (
        sub { $_[0]{postscript_boot}{run} = 'bad' },
        sub { $_[0]{postscript_boot}{boot} = 'bad' },
        sub { $_[0]{postscript_boot}{kind} = 'update' },
        sub { $_[0]{postscript_boot}{preparation} = '1' x 64 },
        sub { $_[0]{postscript_boot}{snapshot} = 'bad' },
        sub { $_[0]{postscript_boot}{extra} = 'unrecognized' },
        sub { $_[0]{postscript_boot}{result}{outcome} = 'pending' },
        sub { $_[0]{postscript_boot}{result}{complete} = 'no' },
        sub { $_[0]{postscript_first}{run} = '1' x 32 },
        sub { delete $_[0]{postscript_boot} },
        sub { delete $_[0]{postscript_first}; $_[0]{postscript_boot}{kind} = 'repeat';
            $_[0]{postscript_boot}{preparation} = $repeat_preparation },
    ) {
        fixture(); call_status(); complete(); call_status();
        my $state = disk_state(); $change->($state);
        open(my $file, '>', "$directory/node1.json") or die $!;
        print {$file} encode_json($state) or die $!;
        close($file) or die $!;
        my $observed = @observations;
        reject(sub { call_status() }, qr/(?:Invalid|no decision|no first boot|differs from)/, 'corrupt retained decision');
        is(scalar(@observations), $observed, 'corrupt state reaches no transport');
    }
    done_testing();
};

done_testing();
