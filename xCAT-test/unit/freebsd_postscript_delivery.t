#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use File::Temp qw(tempdir);
use Fcntl qw(LOCK_EX LOCK_NB);
use JSON;
use Test::More;
use XCAT::Test::PostageFixture ();
use xCAT::FreeBSDPostscript;

umask 0077;
my $temporary = tempdir(CLEANUP => 1);
my $json = JSON->new->canonical->utf8;
my $run = 'a' x 32;
my $snapshot = 'b' x 64;
my $generation = 'c' x 32;
my $attempt = 'd' x 32;
my $archive = "\0" x 10240;
my $sequence = 0;

sub write_file {
    my ($path, $bytes) = @_;
    open(my $file, '>:raw', $path) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    return;
}

sub read_file {
    open(my $file, '<:raw', shift) or croak $!;
    my $bytes = do { local $/ = undef; <$file> };
    close($file) or croak $!;
    return $bytes;
}

sub terminal {
    my $outcome = shift;
    return join("\n", "format\txcat-freebsd-postscript-result-1", "run\t$run", 'node' . "\tnode1",
        "generation\t$generation", "attempt\t$attempt", "snapshot\t$snapshot", 'plan' . "\t" . ('e' x 64),
        "entries\t2", map({ "$_\t" . ('f' x 64) } qw(results-sha256 packages-sha256 stdout-sha256 stderr-sha256)),
        "outcome\t$outcome", "complete\tyes", '');
}

sub pending {
    return "format\txcat-freebsd-postscript-status-1\nrun\t$run\nsnapshot\t$snapshot\noutcome\t$_[0]\ncomplete\tno\n";
}

sub respond {
    my ($state, $callback, $operation, $body) = @_;
    push @{$state->{calls}}, $operation;
    croak 'Transport disconnected after execution' if delete($state->{disconnect}{$operation});
    $body = $state->{filter}->($operation, $body) if $state->{filter};
    my @lines = map { "node1: $_" } split(/\n/x, $body);
    push @lines, 'node1: Remote_command_successful' unless $state->{missing_status};
    push @lines, 'node1: Remote_command_successful' if $state->{duplicate_status};
    $callback->({ data => [join("\n", @lines), undef], xcatdsource => ['master'] });
    $callback->({ errorcode => [1] }) if $state->{errorcode};
    $callback->({ errorcode => [undef] }) if $state->{empty_errorcode};
    $callback->({ errorcode => $state->{daemon_status} }) if exists($state->{daemon_status});
    $callback->({ serverdone => [undef] });
    return;
}

sub sync_transport {
    my ($root, $state, $request, $callback) = @_;
    if ($request->{arg}[3] eq '-F') {
        is_deeply($request->{command}, ['xdcp'], 'native synchronization uses the copy transport');
        is_deeply([@{$request->{arg}}[0..1]], ['--nodestatus', '-t'], 'copy requires an explicit completion status');
        cmp_ok($request->{arg}[2], '<=', 28, 'copy leaves time for acknowledgement');
        cmp_ok($request->{arg}[2], '>', 0, 'copy has a bounded positive timeout');
        is_deeply([@{$request->{arg}}[5..6]], ['-o', '--rsync-path=/usr/local/bin/rsync'], 'copy uses native rsync');
        push @{$state->{copies}}, read_file($request->{arg}[4]);
        if ($state->{copy_failure}) { $callback->({ errorcode => [23] }); }
        else { respond($state, $callback, 'copy', ''); }
        return 1;
    }
    my @words = split(/[ ]/x, $request->{arg}[3]);
    return 0 if @words < 2 || $words[1] ne 'sync-result';
    is_deeply($request->{command}, ['xdsh'], 'acknowledgement uses the shell transport');
    is_deeply([@{$request->{arg}}[0..2]], ['--nodestatus', '-t', '600'], 'acknowledgement requires a completion status');
    my $result = read_file("$root/delivery-$run.sync-1.result");
    my $decoded = decode_json($result);
    is_deeply(\@words, ['/usr/local/libexec/xcat-postscript', 'sync-result', $run, $snapshot, 1,
        $decoded->{status}, sha256_hex($result)], 'acknowledgement binds the retained copy result');
    croak 'Transport disconnected before acknowledgement' if delete($state->{lost_ack});
    ++$state->{acknowledgements};
    $state->{phase} = 'complete';
    $state->{finish} = $decoded->{status} ? 'failed' : 'success';
    respond($state, $callback, 'sync-result', '');
    return 1;
}

sub fixture {
    my $root = "$temporary/store-" . ++$sequence;
    mkdir($root, 0700) or croak $!;
    mkdir("$root/export-$run", 0700) or croak $!;
    my $manifest = { kind => 'freebsd-postscript-export-v1', node => 'node1', source => '1' x 64,
        snapshot => $snapshot, scripts => 2, binding => { preparation => '2' x 64, run => $run,
            generation => $generation, attempt => $attempt, package_mode => 'verify',
            entry_timeout => 30, run_timeout => 120, log_limit => 4096 },
        archive => { bytes => length($archive), sha256 => sha256_hex($archive) } };
    write_file("$root/export-$run/manifest.json", $json->encode($manifest) . "\n");
    write_file("$root/export-$run/bundle.tar", $archive);
    my $state = { phase => 'upload', calls => [], starts => 0, transfers => 0, finish => 'success' };
    # Model only the authenticated xCAT subrequest boundary and remote state.
    my $subrequest = sub {
        my ($request, $callback) = @_;
        my $command = $request->{command}[0];
        is_deeply($request->{node}, ['node1'], 'transport targets the exported node');
        return if sync_transport($root, $state, $request, $callback);
        is_deeply([@{$request->{arg}}[0..2]], ['--nodestatus', '-t', '600'], 'transport requires an explicit completion status');
        my ($operation, $body);
        if ($command eq 'xdcp') {
            $operation = 'transfer';
            is_deeply([@{$request->{arg}}[3..4]], ["$root/export-$run/bundle.tar",
                "/var/db/xcat/postscripts/incoming/$run.delivery/bundle.tar"], 'copy uses retained archive and admitted upload path');
            $state->{copied} = read_file($request->{arg}[3]);
            ++$state->{transfers};
            $body = '';
        } else {
            is($command, 'xdsh', 'worker calls use the existing shell transport');
            my @words = split(/[ ]/x, $request->{arg}[3]);
            is(shift(@words), '/usr/local/libexec/xcat-postscript', 'only the installed worker is invoked');
            $operation = shift @words;
            if ($operation eq 'delivery' || $operation eq 'receive') {
                croak 'Native delivery is locked by the running worker' if $state->{phase} eq 'pending';
                is_deeply(\@words, [$run, $snapshot, sha256_hex($archive), length($archive)], 'worker gets the frozen transfer identity');
                if ($operation eq 'receive') {
                    is($state->{copied}, $archive, 'the full retained archive reached reception');
                    $state->{phase} = 'admitted';
                }
                my $phase = $state->{phase} eq 'upload' ? 'upload' : 'admitted';
                my $path = $phase eq 'upload' ? "/var/db/xcat/postscripts/incoming/$run.delivery/bundle.tar" : '-';
                $body = "format\txcat-freebsd-postscript-delivery-status-1\nrun\t$run\nsnapshot\t$snapshot\narchive-sha256\t"
                  . sha256_hex($archive) . "\narchive-bytes\t" . length($archive) . "\nstate\t$phase\npath\t$path\n";
            } elsif ($operation eq 'receipt') {
                is_deeply(\@words, [$run], 'receipt targets the bound run');
                $body = $state->{phase} eq 'complete' ? terminal($state->{finish}) : pending($state->{phase});
                if ($state->{sync} && $state->{phase} eq 'pending') {
                    $body =~ s/status-1/status-2/x;
                    $body .= "sync-ordinal\t1\nsync-timeout\t30\n";
                }
            } elsif ($operation eq 'start') {
                is_deeply(\@words, [$run], 'start targets the bound run');
                ++$state->{starts};
                $state->{phase} = $state->{defer} || $state->{sync} ? 'pending' : 'complete';
                $body = '';
            } else { croak "Unexpected operation $operation"; }
        }
        respond($state, $callback, $operation, $body);
        return;
    };
    return ($root, $state, $subrequest);
}

sub deliver {
    my ($root, $subrequest, @options) = @_;
    return xCAT::FreeBSDPostscript::deliver_execution($run, $subrequest, directory => $root, @options);
}

sub reject {
    my ($operation, $description, $diagnostic) = @_;
    my $result;
    my $ok = eval { $result = $operation->(); 1; };
    ok(!$ok, "$description fails");
    my $prefix = 'FreeBSD postscript delivery failed during ';
    $diagnostic ||= qr/\A\Q$prefix\E[a-z -]+(?:[:][^\n]+)?\n\z/x;
    like($@, $diagnostic, 'failure identifies a private stage');
    ok(!defined($result), 'failure produces no receipt');
    return;
}

sub delivery_diagnostic {
    my ($root, $operation) = @_;
    my $ok = eval { $operation->(); 1; };
    my $error = $@;
    ok(!$ok, 'delivery reports failure');
    my $prefix = 'FreeBSD postscript delivery failed during delivery:';
    like($error, qr/\A\Q$prefix\E/x, 'caller sees the failed phase');
    my ($path) = $error =~ /;[ ]diagnostic:[ ]([^\n]+)\n\z/x;
    ok(defined($path), 'caller receives a retained diagnostic path');
    return ($error, undef) unless defined($path);
    like($path, qr{\A\Q$root\E/[.]delivery-\Q$run\E[.][^/]+/failure\z}x,
        'diagnostic belongs to this delivery attempt');
    my @state = lstat($path);
    is($state[2] & oct('0777'), oct('0600'), 'diagnostic remains private');
    ok(!-e "$root/delivery-$run.result", 'transport failure cannot publish a completed receipt');
    return ($error, read_file($path));
}

sub transport_diagnostics {
    my ($root, $state, $subrequest) = fixture();
    my $response = { error => ['node1: Permission denied while opening the installed package anchor'], errorcode => [1] };
    my @requests;
    my ($error, $diagnostic) = delivery_diagnostic($root, sub {
        deliver($root, sub { my ($request, $callback) = @_; push @requests, $request; $callback->($response); });
    });
    return unless defined($diagnostic);
    my ($responses) = $diagnostic =~ /responses:[ ]([^\n]+)\n/x;
    ok(defined($responses), 'retained diagnostic identifies the transport responses');
    is_deeply(decode_json(read_file($responses)), [$response], 'exact remote failure is retained') if defined($responses);
    is(scalar(@requests), 1, 'failed delivery performs no subsequent transfer or execution');
    like($requests[0]{arg}[3], qr{\A/usr/local/libexec/xcat-postscript[ ]delivery[ ]}x,
        'only the admission query reached the transport');

    ($root, $state, $subrequest) = fixture();
    ($error, $diagnostic) = delivery_diagnostic($root, sub {
        deliver($root, sub { croak 'Transport connection closed before acknowledgement'; });
    });
    like($error, qr/Transport[ ]connection[ ]closed[ ]before[ ]acknowledgement/x, 'caller sees the underlying connection error');
    like($diagnostic, qr/Transport[ ]connection[ ]closed[ ]before[ ]acknowledgement/x, 'connection error survives failure retention');

    ($root, $state, $subrequest) = fixture();
    my $large = "Connection lost\e[31m\n" . ('x' x 10000);
    ($error, $diagnostic) = delivery_diagnostic($root, sub { deliver($root, sub { croak $large; }); });
    cmp_ok(length($error), '<', 1024, 'caller output is bounded');
    unlike($error, qr/[\x00-\x1f\x7f]./x, 'caller output contains no embedded terminal controls');
    is(length($diagnostic), 8192, 'retained exception is bounded');
    like($diagnostic, qr/Connection[ ]lost\e\[31m\n/x, 'private diagnostic preserves original error bytes');
    return;
}

subtest 'transport errors retain actionable bounded diagnostics' => \&transport_diagnostics;

subtest 'request rejection reports its reason before an attempt exists' => sub {
    my ($root, $state, $subrequest) = fixture();
    my $ok = eval { deliver($root, $subrequest, username => ['root;id']); 1; };
    ok(!$ok, 'invalid request fails');
    like($@, qr/Invalid[ ]delivery[ ]username/x, 'caller sees the request rejection reason');
    is_deeply($state->{calls}, [], 'request rejection invokes no transport');
};

subtest 'failed diagnostic retention preserves the original failure' => sub {
    my ($root, $state, $subrequest) = fixture();
    my $path;
    my $ok = eval {
        deliver($root, sub {
            opendir(my $directory, $root) or croak $!;
            my @attempts = grep { /\A[.]delivery-/x } readdir($directory);
            closedir($directory) or croak $!;
            is(scalar(@attempts), 1, 'only the current attempt exists');
            $path = "$root/$attempts[0]/failure";
            write_file($path, 'existing diagnostic');
            croak 'Disconnected after remote admission';
        });
        1;
    };
    ok(!$ok, 'failed retention cannot report success');
    like($@, qr/Disconnected[ ]after[ ]remote[ ]admission/x, 'original failure remains actionable');
    like($@, qr/diagnostic[ ]retention[ ]failed:/x, 'caller learns that retention failed');
    is(read_file($path), 'existing diagnostic', 'existing evidence is not overwritten');
    ok(!-e "$root/delivery-$run.result", 'no terminal receipt is fabricated');
};

subtest 'deliver, retain terminal receipt and reuse completed result' => sub {
    my ($root, $state, $subrequest) = fixture();
    my $result = deliver($root, $subrequest, username => ['root']);
    is($result->{outcome}, 'success', 'terminal success reaches the caller');
    is($result->{complete}, 'yes', 'success is complete');
    is_deeply($state->{calls}, [qw(delivery transfer receive receipt start receipt)], 'admission precedes execution and receipt collection');
    is(read_file("$root/delivery-$run.result"), terminal('success'), 'controller retains exact native receipt');
    ok(!-e "$root/export-$run/bundle.tar", 'committed terminal delivery retires its transfer payload');
    ok(-s "$root/export-$run.retired", 'payload retirement has a retained proof');
    my $descriptor = xCAT::FreeBSDPostscript::read_export($run, directory => $root);
    is($descriptor->{archive}{sha256}, sha256_hex($archive), 'retired export retains its original archive identity');
    is($descriptor->{archive}{bytes}, length($archive), 'retired export retains its original archive size');
    my %binding = %{$descriptor->{binding}};
    my $preparation = delete $binding{preparation};
    SKIP: {
        skip('Export requires Linux root', 1) unless $^O eq 'linux' && $> == 0;
        is_deeply(xCAT::FreeBSDPostscript::export_execution($preparation, directory => $root, %binding),
            $descriptor, 'same-run export remains usable after retirement');
    }
    my $before = [@{$state->{calls}}];
    is_deeply(deliver($root, $subrequest), $result, 'completed retry returns the same result');
    is_deeply($state->{calls}, $before, 'completed retry needs no remote operations');
    is($state->{starts}, 1, 'completed retry does not start again');
    write_file("$root/export-$run/bundle.tar", 'changed');
    reject(sub { deliver($root, $subrequest) }, 'changed archive on a completed retry');
    is_deeply($state->{calls}, $before, 'corruption is rejected before remote operations');
};

sub retirement_interruptions {
    for my $boundary (qw(marker payload)) {
        my ($root, $state, $subrequest) = fixture();
        my $sync = \&xCAT::FreeBSDPostscript::_sync_directory;
        my $failed = 0;
        {
            no warnings 'redefine';
            local *xCAT::FreeBSDPostscript::_sync_directory = sub {
                my $path = $_[0];
                if (-e "$root/export-$run.retired" && !$failed
                    && (($boundary eq 'marker' && $path eq $root)
                        || ($boundary eq 'payload' && $path eq "$root/export-$run"))) {
                    ++$failed;
                    croak 'injected retirement sync failure';
                }
                return $sync->(@_);
            };
            reject(sub { deliver($root, $subrequest) }, "$boundary interruption");
        }
        is($failed, 1, 'the requested durability boundary was reached');
        is(read_file("$root/delivery-$run.result"), terminal('success'), 'interrupted retirement preserves the terminal receipt');
        is(-e "$root/export-$run/bundle.tar" ? 1 : 0, $boundary eq 'marker' ? 1 : 0,
            'payload absence follows the durable retirement boundary');
        my $before = [@{$state->{calls}}];
        is(deliver($root, $subrequest)->{outcome}, 'success', 'retirement retry preserves the completed outcome');
        ok(!-e "$root/export-$run/bundle.tar", 'retirement retry removes the remaining payload');
        is_deeply($state->{calls}, $before, 'retirement retry does not contact or restart the node');
    }
    return;
}

sub retirement_bindings {
    my ($root, $state, $subrequest) = fixture();
    deliver($root, $subrequest);
    my $proof = -e "$root/export-$run.retired" ? read_file("$root/export-$run.retired") : '';
    ok(length($proof), 'completed export has retirement evidence');
    my $manifest = read_file("$root/export-$run/manifest.json");
    my $diagnostic = qr/\AFreeBSD[ ]postscript[ ]export[ ]verification[ ]failed\n\z/x;
    for my $key (qw(run manifest receipt)) {
        my $changed = length($proof) ? decode_json($proof) : {};
        $changed->{$key} = '0' x ($key eq 'run' ? 32 : 64);
        write_file("$root/export-$run.retired", $json->encode($changed) . "\n");
        reject(sub { xCAT::FreeBSDPostscript::read_export($run, directory => $root) }, "retirement $key binding", $diagnostic);
    }
    write_file("$root/export-$run.retired", $proof);
    write_file("$root/delivery-$run.result", terminal('failed'));
    reject(sub { xCAT::FreeBSDPostscript::read_export($run, directory => $root) }, 'changed retired receipt', $diagnostic);
    write_file("$root/delivery-$run.result", terminal('success'));
    my $changed = decode_json($manifest);
    $changed->{archive}{sha256} = '0' x 64;
    write_file("$root/export-$run/manifest.json", $json->encode($changed) . "\n");
    reject(sub { xCAT::FreeBSDPostscript::read_export($run, directory => $root) }, 'changed retired archive identity', $diagnostic);
    write_file("$root/export-$run/manifest.json", $manifest);
    unlink("$root/export-$run.retired") or croak $!;
    unlink("$root/export-$run/bundle.tar") if -e "$root/export-$run/bundle.tar";
    reject(sub { xCAT::FreeBSDPostscript::read_export($run, directory => $root) }, 'payload missing without retirement', $diagnostic);
    return;
}

subtest 'payload retirement resumes at both durable boundaries' => \&retirement_interruptions;
subtest 'retired exports require their exact manifest and terminal receipt' => \&retirement_bindings;

subtest 'package rejection retains its transfer input' => sub {
    my ($root, $state, $subrequest) = fixture();
    $state->{finish} = 'failed';
    $state->{filter} = sub {
        my ($operation, $body) = @_;
        $body =~ s/postscript-result-1/postscript-result-2/x if $operation eq 'receipt';
        return $body;
    };
    is(deliver($root, $subrequest)->{outcome}, 'failed', 'package rejection remains a failed terminal outcome');
    is(read_file("$root/export-$run/bundle.tar"), $archive, 'rejected package payload remains intact');
    ok(!-e "$root/export-$run.retired", 'package rejection cannot authorize retirement');
};

subtest 'terminal framework failure retires its completed transfer' => sub {
    my ($root, $state, $subrequest) = fixture();
    $state->{finish} = 'failed';
    my $receipt = terminal('failed');
    my $inventory = 'f' x 64;
    $receipt =~ s/postscript-result-1/postscript-result-3/x;
    $receipt =~ s/^outcome\t/inventory-sha256\t$inventory\noutcome\t/mx;
    $state->{filter} = sub {
        my ($operation, $body) = @_;
        return $operation eq 'receipt' && $body =~ /postscript-result-/x ? $receipt : $body;
    };
    my $result = deliver($root, $subrequest);
    is($result->{outcome}, 'failed', 'framework failure remains a failed terminal outcome');
    is(read_file("$root/delivery-$run.result"), $receipt, 'the exact failure receipt is retained');
    ok(!-e "$root/export-$run/bundle.tar", 'completed transfer payload is retired');
    ok(-s "$root/export-$run.retired", 'failure has a bound retirement proof');
    is(xCAT::FreeBSDPostscript::read_export($run, directory => $root)->{snapshot}, $snapshot,
        'retired failure export remains readable');
    my $before = [@{$state->{calls}}];
    is_deeply(deliver($root, $subrequest), $result, 'cached delivery preserves the failed outcome');
    is_deeply($state->{calls}, $before, 'retirement retry does not restart the run');
};

subtest 'daemon and client completion status preserve delivery results' => sub {
    for my $status (0, [0]) {
        my ($root, $state, $subrequest) = fixture();
        $state->{daemon_status} = $status;
        my $result = eval { deliver($root, $subrequest) };
        is($@, '', 'successful daemon or client status permits delivery');
        is(defined($result) ? $result->{outcome} : undef, 'success', 'native terminal success reaches the caller');
        is($state->{starts}, 1, 'the admitted run starts once');
    }
    for my $status (1, [0, 1], undef, '', { errorcode => 0 }) {
        my ($root, $state, $subrequest) = fixture();
        $state->{daemon_status} = $status;
        reject(sub { deliver($root, $subrequest) }, 'failed or invalid daemon completion');
        is($state->{transfers}, 0, 'failed status prevents transfer');
        is($state->{starts}, 0, 'failed status prevents execution');
    }
};

subtest 'resume after a lost receive or start acknowledgement' => sub {
    for my $operation (qw(receive start)) {
        my ($root, $state, $subrequest) = fixture();
        $state->{disconnect}{$operation} = 1;
        reject(sub { deliver($root, $subrequest) }, "lost $operation acknowledgement");
        ok(!-e "$root/delivery-$run.result", 'interrupted call cannot publish completion');
        is(deliver($root, $subrequest)->{outcome}, 'success', 'retry reconciles remote completion');
        is($state->{transfers}, 1, 'accepted archive is not copied again');
        is($state->{starts}, 1, 'accepted execution is not started again');
    }
};

subtest 'admitted polling avoids rereading the payload and keeps its bindings' => sub {
    my ($root, $state, $subrequest) = fixture();
    $state->{defer} = 1;
    my $read = \&xCAT::FreeBSDPostscript::_read;
    my $payload_reads = 0;
    no warnings 'redefine';
    local *xCAT::FreeBSDPostscript::_read = sub {
        ++$payload_reads if $_[0] eq "$root/export-$run/bundle.tar";
        return $read->(@_);
    };
    is(deliver($root, $subrequest)->{outcome}, 'pending', 'initial delivery admits the verified payload');
    is($payload_reads, 1, 'initial delivery reads the complete payload once');
    for (1 .. 3) {
        is(deliver($root, $subrequest)->{outcome}, 'pending', 'admitted poll remains pending');
        is($payload_reads, 1, 'admitted poll does not read the payload again');
    }
    my $admitted = read_file("$root/delivery-$run.admitted");
    my $before = [@{$state->{calls}}];
    my $other_snapshot = '0' x 64;
    (my $changed = $admitted) =~ s/^snapshot\t[^\n]+/snapshot\t$other_snapshot/mx;
    write_file("$root/delivery-$run.admitted", $changed);
    reject(sub { deliver($root, $subrequest) }, 'changed admission binding');
    is_deeply($state->{calls}, $before, 'invalid admission is rejected before observation');
    write_file("$root/delivery-$run.admitted", $admitted);
    $state->{phase} = 'complete';
    is(deliver($root, $subrequest)->{outcome}, 'success', 'completed execution retains its terminal result');
    is($payload_reads, 2, 'retirement verifies the full payload before deletion');
    ok(!-e "$root/export-$run/bundle.tar", 'verified payload is retired');
    is($state->{transfers}, 1, 'polling does not repeat payload transfer');
    is($state->{starts}, 1, 'polling does not repeat execution');
};

sub busy_transport {
    my ($state, $subrequest) = @_;
    return sub {
        my ($request, $callback) = @_;
        my @words = split(/[ ]/x, $request->{arg}[3]);
        my $operation = $words[1] || '';
        if ($request->{command}[0] eq 'xdsh' && $state->{busy}{$operation}) {
            --$state->{busy}{$operation};
            my $busy = pending('busy');
            $busy =~ s/status-1/status-3/x;
            respond($state, $callback, $operation, $busy);
            return;
        }
        return $subrequest->(@_);
    };
}

sub busy_delivery {
    PHASE:
    for my $phase (qw(delivery receive start)) {
        my ($root, $state, $subrequest) = fixture();
        $subrequest = busy_transport($state, $subrequest);
        $state->{busy}{$phase} = 2;
        for (1 .. 2) {
            my $receipt;
            my $observed = eval { $receipt = deliver($root, $subrequest); 1; };
            ok($observed, "$phase contention permits another observation");
            if (!$observed) { diag($@); next PHASE; }
            is($receipt->{outcome}, 'busy', "$phase reports contention without failing transport");
            is($receipt->{complete}, 'no', 'contention never completes a run');
            is($receipt->{run}, $run, 'contention keeps the original run');
            is($state->{starts}, 0, 'busy request has not executed scripts');
            ok(!-e "$root/delivery-$run.result", 'busy request has no terminal receipt');
            is(-e "$root/delivery-$run.admitted" ? 1 : 0, $phase eq 'start' ? 1 : 0,
                'only acknowledged admission is retained');
        }
        is(deliver($root, $subrequest)->{outcome}, 'success', 'unlocked node completes the retained request');
        is($state->{starts}, 1, 'unlocked request starts once');
        is(deliver($root, $subrequest)->{outcome}, 'success', 'completed retry remains successful');
        is($state->{starts}, 1, 'completed retry cannot replay scripts');
    }
    done_testing();
    return;
}

sub busy_bindings {
    for my $fault (qw(run snapshot complete outcome format duplicate missing-status failed-status)) {
        my ($root, $state, $subrequest) = fixture();
        $subrequest = busy_transport($state, $subrequest);
        $state->{busy}{delivery} = 1;
        $state->{missing_status} = 1 if $fault eq 'missing-status';
        $state->{errorcode} = 1 if $fault eq 'failed-status';
        $state->{filter} = sub {
            my ($operation, $body) = @_;
            $body =~ s/^run\t./run\t0/mx if $fault eq 'run';
            $body =~ s/^snapshot\t./snapshot\t0/mx if $fault eq 'snapshot';
            $body =~ s/complete\tno/complete\tyes/x if $fault eq 'complete';
            $body =~ s/outcome\tbusy/outcome\tpending/x if $fault eq 'outcome';
            $body =~ s/status-3/status-1/x if $fault eq 'format';
            $body .= "complete\tno\n" if $fault eq 'duplicate';
            return $body;
        };
        reject(sub { deliver($root, $subrequest) }, "invalid busy $fault");
        is($state->{starts}, 0, 'invalid contention response causes no execution');
        ok(!-e "$root/delivery-$run.admitted", 'invalid contention response cannot admit a bundle');
    }
    done_testing();
    return;
}

subtest 'busy delivery, reception and start retry the same run' => \&busy_delivery;
subtest 'busy responses require identity, shape and transport completion' => \&busy_bindings;

subtest 'pending and uncertain executions do not authorize another start' => sub {
    my ($root, $state, $subrequest) = fixture();
    $state->{defer} = 1;
    is(deliver($root, $subrequest)->{outcome}, 'pending', 'background execution remains pending');
    ok(-f "$root/delivery-$run.admitted", 'admission is durable before a pending receipt');
    for my $phase (qw(pending uncertain)) {
        $state->{phase} = $phase;
        my $receipt = eval { deliver($root, $subrequest) };
        is($@, '', 'receipt polling does not require the running worker lock');
        is(defined($receipt) ? $receipt->{outcome} : undef, $phase, 'observed incomplete state reaches caller');
        is($state->{starts}, 1, 'incomplete retry does not replay execution');
        ok(!-e "$root/delivery-$run.result", 'incomplete state is not terminal');
    }
    $state->{phase} = 'complete';
    $state->{finish} = 'failed';
    is(deliver($root, $subrequest)->{outcome}, 'failed', 'completed script failure is reported as failure');
    is(read_file("$root/delivery-$run.result"), terminal('failed'), 'failed terminal receipt is durable');
};

sub completed_polling {
    my ($root, $state, $subrequest) = fixture();
    $state->{defer} = 1;
    my @active;
    my $observing = sub {
        my ($request, $callback) = @_;
        my @attempts = glob("$root/.delivery-$run.*");
        is(scalar(@attempts), 1, 'one transient attempt exists during transport');
        push @active, @attempts;
        $subrequest->($request, $callback);
        ok(-f "$attempts[0]/export.json", 'attempt remains available until the transport returns');
    };
    for my $poll (1 .. 8) {
        is(deliver($root, $observing)->{outcome}, 'pending', 'successful poll remains pending');
        is_deeply([glob("$root/.delivery-$run.*")], [], 'completed poll leaves no transient attempt');
    }
    $state->{phase} = 'uncertain';
    is(deliver($root, $observing)->{outcome}, 'uncertain', 'uncertainty does not retain successful poll files');
    ok(!grep({ -e $_ } @active), 'all completed attempts are removed');
    is(read_file("$root/export-$run/bundle.tar"), $archive, 'transfer input remains intact');
    ok(-s "$root/delivery-$run.admitted", 'durable admission remains available');
    is($state->{transfers}, 1, 'polling does not repeat transfer');
    is($state->{starts}, 1, 'polling does not repeat execution');

    $state->{phase} = 'complete';
    is(deliver($root, $observing)->{outcome}, 'success', 'terminal result is still published');
    is(read_file("$root/delivery-$run.result"), terminal('success'), 'receipt survives terminal attempt cleanup');
    is_deeply([glob("$root/.delivery-$run.*")], [], 'terminal attempt is removed');
    return;
}

sub preserved_failures {
    my ($root, $state, $subrequest) = fixture();
    $state->{disconnect}{receive} = 1;
    reject(sub { deliver($root, $subrequest) }, 'lost admission acknowledgement');
    my @failed = glob("$root/.delivery-$run.*");
    is(scalar(@failed), 1, 'failed attempt is retained');
    my $diagnostic = read_file("$failed[0]/failure");
    my $responses = read_file("$failed[0]/receive.responses.json");
    is(deliver($root, $subrequest)->{outcome}, 'success', 'retry completes the admitted run');
    is_deeply([glob("$root/.delivery-$run.*")], \@failed, 'only the failed attempt remains');
    is(read_file("$failed[0]/failure"), $diagnostic, 'failure diagnostic is unchanged');
    is(read_file("$failed[0]/receive.responses.json"), $responses, 'transport evidence remains readable');
    is($state->{transfers}, 1, 'retry does not retransmit the admitted archive');
    is($state->{starts}, 1, 'retry starts once');
    return;
}

sub unsafe_cleanup {
    for my $kind (qw(link directory)) {
        my ($root, $state, $subrequest) = fixture();
        $state->{defer} = 1;
        my $sentinel = "$root/unrelated";
        write_file($sentinel, 'preserve');
        my $path;
        my $transport = sub {
            unless (defined($path)) {
                ($path) = glob("$root/.delivery-$run.*");
                if ($kind eq 'link') { symlink($sentinel, "$path/foreign") or croak $!; }
                else { mkdir("$path/foreign", oct('0700')) or croak $!; }
            }
            $subrequest->(@_);
        };
        reject(sub { deliver($root, $transport) }, "unsafe cleanup $kind");
        is(read_file($sentinel), 'preserve', 'unrelated file is unchanged');
        ok(-s "$path/export.json" && -s "$path/receipt", 'attempt files remain available after cleanup rejection');
        ok(-s "$path/failure", 'cleanup failure retains its diagnostic');
    }
    return;
}

subtest 'successful polling removes only its transient diagnostics' => \&completed_polling;
subtest 'successful retry preserves failed-attempt evidence' => \&preserved_failures;
subtest 'attempt cleanup rejects links and directories before removing files' => \&unsafe_cleanup;

subtest 'transport completion and protocol bindings are required' => sub {
    for my $fault (qw(missing_status duplicate_status errorcode empty_errorcode)) {
        my ($root, $state, $subrequest) = fixture();
        $state->{$fault} = 1;
        reject(sub { deliver($root, $subrequest) }, $fault);
        is($state->{starts}, 0, 'transport failure does not start scripts');
    }
    for my $field (qw(run snapshot archive-sha256 archive-bytes path state)) {
        my ($root, $state, $subrequest) = fixture();
        $state->{filter} = sub { my ($operation, $bytes) = @_; $bytes =~ s/^\Q$field\E\t[^\n]*/$field\twrong/mx if $operation eq 'delivery'; return $bytes; };
        reject(sub { deliver($root, $subrequest) }, "wrong delivery $field");
        is($state->{transfers}, 0, 'unbound response never authorizes a transfer');
    }
    for my $field (qw(run snapshot node generation attempt entries plan results-sha256 packages-sha256 stdout-sha256 stderr-sha256 outcome complete)) {
        my ($root, $state, $subrequest) = fixture();
        $state->{phase} = 'complete';
        $state->{filter} = sub { my ($operation, $bytes) = @_; $bytes =~ s/^\Q$field\E\t[^\n]*/$field\twrong/mx if $operation eq 'receipt'; return $bytes; };
        reject(sub { deliver($root, $subrequest) }, "wrong receipt $field");
        ok(!-e "$root/delivery-$run.result", 'invalid receipt is not published');
    }
};

subtest 'local ownership, locks and retained receipt are checked' => sub {
    my ($root, $state, $subrequest) = fixture();
    open(my $lock, '>', "$root/delivery-$run.lock") or croak $!;
    flock($lock, LOCK_EX | LOCK_NB) or croak $!;
    reject(sub { deliver($root, $subrequest) }, 'busy run');
    is_deeply($state->{calls}, [], 'busy run performs no transport');
    close($lock) or croak $!;
    deliver($root, $subrequest);
    my $admitted = read_file("$root/delivery-$run.admitted");
    my $terminal = read_file("$root/delivery-$run.result");
    unlink("$root/delivery-$run.result") or croak $!;
    write_file("$root/delivery-$run.admitted", 'corrupt');
    my $before = [@{$state->{calls}}];
    reject(sub { deliver($root, $subrequest) }, 'altered admission');
    is_deeply($state->{calls}, $before, 'corrupt admission prevents remote operations');
    write_file("$root/delivery-$run.admitted", $admitted);
    write_file("$root/delivery-$run.result", $terminal);
    write_file("$root/delivery-$run.result", pending('admitted'));
    reject(sub { deliver($root, $subrequest) }, 'incomplete retained result');
    unlink("$root/delivery-$run.result") or croak $!;
    write_file("$root/other", terminal('success'));
    symlink('other', "$root/delivery-$run.result") or croak $!;
    reject(sub { deliver($root, $subrequest) }, 'symlinked result');
    reject(sub { deliver($root, $subrequest, username => ['root;id']) }, 'invalid transport user');
};

sub sync_fixture {
    my $tables = XCAT::Test::PostageFixture::fixture();
    my ($root, $state, $subrequest) = fixture();
    my $list = "$root/selected.list";
    write_file($list, "/source -> /target\n");
    $tables->{osimage}[0]{synclists} = $list;
    $state->{sync} = 1;
    $state->{copies} = [];
    return ($root, $state, $subrequest, $list);
}

sub native_sync_tests {
subtest 'native request copies in order and acknowledgement retry cannot repeat it' => sub {
    my ($root, $state, $subrequest, $list) = sync_fixture();
    $state->{lost_ack} = 1;
    reject(sub { deliver($root, $subrequest) }, 'lost synchronization acknowledgement');
    is_deeply($state->{copies}, ["/source -> /target\n"], 'request runs the actual frozen-list copy path');
    write_file($list, "/changed -> /different\n");
    my $result = deliver($root, $subrequest);
    is($result->{outcome}, 'success', 'retained completion reaches the waiting script');
    is(scalar(@{$state->{copies}}), 1, 'retry does not copy a changed selection');
    is($state->{acknowledgements}, 1, 'completion is acknowledged once');
    is($state->{starts}, 1, 'delivery never restarts the script');
    my $calls = scalar(@{$state->{calls}});
    is(deliver($root, $subrequest)->{outcome}, 'success', 'terminal observation is reusable');
    is(scalar(@{$state->{calls}}), $calls, 'terminal observation uses retained evidence');
    my $copy = decode_json(read_file("$root/delivery-$run.sync-1.result"));
    ok(-s "$copy->{directory}/result.json", 'published synchronization result still locates its evidence');
    my $selection = decode_json(read_file("$copy->{directory}/selection.json"));
    is(read_file("$copy->{directory}/blob-$selection->{lists}[0]{sha256}"), "/source -> /target\n",
        'original transfer input remains readable after delivery cleanup');
    done_testing();
};

subtest 'uncertain copy intent fails without replay' => sub {
    my ($root, $state, $subrequest) = sync_fixture();
    write_file("$root/delivery-$run.sync-1.intent", $json->encode({
        format => 'freebsd-postscript-sync-v1', run => $run, snapshot => $snapshot, ordinal => 1 }) . "\n");
    is(deliver($root, $subrequest)->{outcome}, 'failed', 'interrupted copy cannot become a success');
    is_deeply($state->{copies}, [], 'an uncertain copy is never replayed');
    my $result = decode_json(read_file("$root/delivery-$run.sync-1.result"));
    is($result->{outcome}, 'uncertain', 'retained evidence distinguishes interrupted intent');
    done_testing();
};

subtest 'native synchronization failures propagate to the script' => sub {
    for my $fault (qw(missing writable copy)) {
        my ($root, $state, $subrequest, $list) = sync_fixture();
        unlink($list) or croak $! if $fault eq 'missing';
        chmod(0666, $list) == 1 or croak $! if $fault eq 'writable';
        $state->{copy_failure} = 1 if $fault eq 'copy';
        is(deliver($root, $subrequest)->{outcome}, 'failed', "$fault failure reaches the script");
        is(scalar(@{$state->{copies}}), $fault eq 'copy' ? 1 : 0, 'unsafe selection never starts a copy');
        my $result = decode_json(read_file("$root/delivery-$run.sync-1.result"));
        is($result->{status}, 1, 'the acknowledgement contains failure');
        ok(length($result->{error}), 'failure evidence is retained');
    }
    done_testing();
};

subtest 'invalid native synchronization context cannot trigger a copy' => sub {
    for my $replacement ("sync-ordinal\t0", "sync-ordinal\t3", "sync-timeout\t31", "sync-timeout\t0") {
        my ($root, $state, $subrequest) = sync_fixture();
        my ($field) = split(/\t/x, $replacement);
        $state->{filter} = sub {
            my ($operation, $body) = @_;
            $body =~ s/^\Q$field\E\t[^\n]+$/$replacement/mx if $operation eq 'receipt';
            return $body;
        };
        reject(sub { deliver($root, $subrequest) }, 'invalid synchronization context');
        is_deeply($state->{copies}, [], 'invalid context has no side effect');
    }
    done_testing();
};

return;
}

native_sync_tests();

done_testing();
